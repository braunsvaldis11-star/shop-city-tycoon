--!strict
-- InteriorController (client): builds the player's PRIVATE business interior and runs
-- its employees and customers.
--  * The server decides when we enter/leave and where our private slot is.
--  * Geometry and NPCs exist only on this client, so nobody else sees them.
--  * NPCs are purely visual. Customers are the server's real customers: every one the
--    server rolls for this shop (the "Customers" event, which also drives the street
--    walkers) walks in when their street walker reaches the door. In a shop they queue,
--    pick up their item and pay at the till; at an attraction (entry fee) they pay at
--    the door and then enjoy the place. The server decides who comes and what they
--    pay, so nothing here can be exploited.
--  * The F prompt at the counter opens the owner's mini game (MiniGameController).
-- Container: StarterPlayerScripts.Controllers

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientModules = ReplicatedStorage:WaitForChild("Client")
local Businesses = require(Shared.Businesses)
local Format = require(Shared.Format)
local InteriorBuilder = require(ClientModules.InteriorBuilder)
local Bubble = require(ClientModules.Bubble)
local NpcRig = require(ClientModules.NpcRig)
local Props = require(Shared.Props)

local InteriorController = {}

local player = Players.LocalPlayer
local controllers: any

type Customer = {
	rig: NpcRig.Rig,
	state: string,
	amount: number, -- what they pay at the till (0 when already paid)
	timer: number,
	register: number,
	seat: number?,
}
type Worker = {
	rig: NpcRig.Rig,
	role: string,
	state: string,
	timer: number,
	index: number,
	home: Vector3,
}

local active: {
	businessId: string,
	definition: Businesses.Definition,
	origin: Vector3,
	model: Model,
	layout: InteriorBuilder.Layout,
	npcFolder: Folder,
	customers: { Customer },
	workers: { Worker },
	queues: { { Customer } },
	seatTaken: { [number]: boolean },
	trays: { { BasePart } },
	signature: string,
	connections: { RBXScriptConnection },
	arrivedAt: number,
}? = nil

local rng = Random.new()
local heartbeat: RBXScriptConnection? = nil
local exitRequested = 0

-- Customers the server has sent towards a door; they walk in when they get there.
type Arrival = { id: string, count: number, amount: number, at: number }
local arrivals: { Arrival } = {}

local MAX_TRAY = 5

-- Interiors are open-topped for the camera, so the midday sun floods them. Dim the
-- exposure a little while inside so the warm lamps read and nothing looks blown out.
local Lighting = game:GetService("Lighting")
local INSIDE_EXPOSURE = -0.45
local outsideExposure = Lighting.ExposureCompensation
local function setInsideLighting(on: boolean)
	local goal = if on then outsideExposure + INSIDE_EXPOSURE else outsideExposure
	TweenService:Create(Lighting, TweenInfo.new(0.4), { ExposureCompensation = goal }):Play()
end

----- Helpers -----
local function businessState(): any
	local state = controllers.Store.state
	if not state or not active then
		return nil
	end
	return state.businesses[active.businessId]
end

local function upgradeLevel(id: string): number
	local biz = businessState()
	return if biz and biz.upgrades[id] then biz.upgrades[id] else 0
end

local function signatureOf(biz: any): string
	if not biz then
		return ""
	end
	local keys = {}
	for id, value in biz.upgrades do
		table.insert(keys, id .. "=" .. tostring(value))
	end
	table.sort(keys)
	return tostring(biz.level) .. "|" .. table.concat(keys, ",")
end

local function staffSpeed(): number
	return 8 * (1 + 0.15 * upgradeLevel("training"))
end

local function popText(position: Vector3, text: string, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 40)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = anchor
	anchor.Parent = if active then active.npcFolder else Workspace
	TweenService:Create(anchor, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(position + Vector3.new(0, 4, 0)) }):Play()
	TweenService:Create(label, TweenInfo.new(1.2), { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, TweenInfo.new(1.2), { Transparency = 1 }):Play()
	task.delay(1.3, function()
		anchor:Destroy()
	end)
end

local function sparkle(position: Vector3)
	if not active then
		return
	end
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.CFrame = CFrame.new(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 255, 255))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(1.2, 0)
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(12, 22)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = part
	part.Parent = active.npcFolder
	emitter:Emit(60)
	task.delay(2, function()
		part:Destroy()
	end)
end

----- Trays (finished products waiting on the counter) -----
local function trayPosition(trayIndex: number, slot: number): Vector3
	local base = (active :: any).layout.pickups[trayIndex]
	return base + Vector3.new(0, 3.45 + (slot - 1) * 0.55, 0)
end

local function addToTray(): boolean
	local a = active
	if not a then
		return false
	end
	local best = 1
	for i, tray in a.trays do
		if #tray < #a.trays[best] then
			best = i
		end
	end
	local tray = a.trays[best]
	if #tray >= MAX_TRAY then
		return false
	end
	local product = InteriorBuilder.product(a.definition.productStyle, a.definition.theme)
	product.CFrame = CFrame.new(trayPosition(best, #tray + 1))
	product.Parent = a.npcFolder
	table.insert(tray, product)
	return true
end

local function takeFromTray()
	local a = active
	if not a then
		return
	end
	for _, tray in a.trays do
		local product = table.remove(tray)
		if product then
			product:Destroy()
			return
		end
	end
end

----- Staff -----
local function spawnStaff()
	local a = active
	if not a then
		return
	end
	local theme = a.definition.theme
	local uniform = { shirt = theme.primary, pants = Color3.fromRGB(50, 50, 60), hat = theme.accent }
	-- Cashiers: one per register.
	for i, register in a.layout.registers do
		local rig = NpcRig.new(a.npcFolder, rng, uniform, register.cashier)
		rig.yaw = math.pi
		table.insert(a.workers, { rig = rig, role = "cashier", state = "idle", timer = 0, index = i, home = register.cashier })
	end
	-- Production workers (cooks, baristas, ...): base worker + hired ones.
	local workerLook = { shirt = Color3.fromRGB(250, 250, 250), pants = Color3.fromRGB(50, 50, 60), hat = Color3.fromRGB(255, 255, 255) }
	for i = 1, 1 + upgradeLevel("workers") do
		local stationIndex = ((i - 1) % #a.layout.stations) + 1
		local home = a.layout.stations[stationIndex]
		local rig = NpcRig.new(a.npcFolder, rng, workerLook, home + Vector3.new(rng:NextNumber(-1, 1), 0, 0))
		rig.yaw = 0
		rig.speed = staffSpeed()
		table.insert(a.workers, { rig = rig, role = "cook", state = "working", timer = rng:NextNumber(0.5, 2.5), index = stationIndex, home = home })
	end
	-- Cleaners wander the dining room.
	for _ = 1, upgradeLevel("cleaners") do
		local start = a.origin + Vector3.new(rng:NextNumber(-30, 30), 0, rng:NextNumber(0, 24))
		local rig = NpcRig.new(a.npcFolder, rng, { shirt = Color3.fromRGB(90, 170, 230), pants = Color3.fromRGB(40, 60, 110), hat = Color3.fromRGB(255, 220, 60) }, start)
		rig.speed = staffSpeed() * 0.6
		local mop = Props.part(nil, "Mop", Vector3.new(0.4, 0.4, 3.5), CFrame.new(), Color3.fromRGB(150, 110, 70), { collide = false, shadow = false })
		mop.Parent = a.npcFolder
		rig.carrying = mop
		table.insert(a.workers, { rig = rig, role = "cleaner", state = "pause", timer = 1, index = 0, home = start })
	end
end

local function updateWorker(worker: Worker, dt: number)
	local a = active :: any
	local rig = worker.rig
	if worker.role == "cashier" then
		worker.timer -= dt
		rig.working = worker.timer > 0
		return
	end
	if worker.role == "cook" then
		if worker.state == "working" then
			rig.working = true
			rig:face(rig.position + Vector3.new(0, 0, -1))
			worker.timer -= dt
			if worker.timer <= 0 then
				rig.working = false
				-- Carry the product to the counter (via a prep station if we have any).
				local tray = a.layout.pickups[rng:NextInteger(1, #a.layout.pickups)]
				local path = {}
				if #a.layout.preps > 0 then
					table.insert(path, a.layout.preps[rng:NextInteger(1, #a.layout.preps)])
				end
				table.insert(path, tray + Vector3.new(0, 0, -3))
				rig:setPath(path)
				rig.speed = staffSpeed()
				rig.carrying = InteriorBuilder.product(a.definition.productStyle, a.definition.theme)
				;(rig.carrying :: BasePart).Parent = a.npcFolder
				worker.state = "delivering"
			end
		elseif worker.state == "delivering" then
			if rig:step(dt) then
				if rig.carrying then
					rig.carrying:Destroy()
					rig.carrying = nil
				end
				addToTray()
				rig:setPath({ worker.home })
				worker.state = "returning"
			end
		elseif worker.state == "returning" then
			if rig:step(dt) then
				worker.state = "working"
				local equipment = upgradeLevel("equipment")
				worker.timer = 3.2 / (1 + 0.35 * equipment)
			end
		end
		return
	end
	-- Cleaner
	if worker.state == "pause" then
		rig.working = true
		worker.timer -= dt
		if worker.timer <= 0 then
			rig.working = false
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			rig:setPath({ a.origin + Vector3.new(side * rng:NextNumber(9, 36), 0, rng:NextNumber(-3, 27)) })
			worker.state = "walking"
		end
	elseif rig:step(dt) then
		worker.state = "pause"
		worker.timer = rng:NextNumber(1.5, 3)
	end
end

----- Customers -----
local function queueSpot(registerIndex: number, position: number): Vector3
	local register = (active :: any).layout.registers[registerIndex]
	return register.queue + Vector3.new(0, 0, (position - 1) * 2.8)
end

local function spawnCustomer(amount: number)
	local a = active
	if not a or #a.customers >= math.min(6 + #a.layout.seats, 22) then
		return
	end
	-- Shortest queue wins.
	local best = 1
	for i, queue in a.queues do
		if #queue < #a.queues[best] then
			best = i
		end
	end
	if #a.queues[best] >= 4 then
		return
	end
	local rig = NpcRig.new(a.npcFolder, rng, nil, a.layout.door)
	rig.speed = rng:NextNumber(8, 11)
	local customer: Customer = { rig = rig, state = "entering", amount = amount, timer = 0, register = best, seat = nil }
	table.insert(a.queues[best], customer)
	rig:setPath({ a.layout.lane, queueSpot(best, #a.queues[best]) })
	table.insert(a.customers, customer)
end

local function serveTime(): number
	return math.clamp(3.2 / (1 + 0.2 * upgradeLevel("training")), 0.9, 3.2)
end

local function finishOrder(customer: Customer, byPlayer: boolean)
	local a = active :: any
	local queue = a.queues[customer.register]
	local index = table.find(queue, customer)
	if index then
		table.remove(queue, index)
	end
	-- Everyone behind moves up.
	for position, waiting in queue do
		if waiting.state ~= "entering" then
			waiting.state = "queued"
			waiting.rig:setPath({ queueSpot(customer.register, position) })
		end
	end
	takeFromTray()
	local rig = customer.rig
	rig.carrying = InteriorBuilder.product(a.definition.productStyle, a.definition.theme)
	;(rig.carrying :: BasePart).Parent = a.npcFolder

	local cashier = nil
	for _, worker in a.workers do
		if worker.role == "cashier" and worker.index == customer.register then
			cashier = worker
		end
	end
	if cashier then
		cashier.timer = 0.8
	end
	if not byPlayer and customer.amount > 0 then
		popText(a.layout.registers[customer.register].cashier + Vector3.new(0, 7, 0), "+" .. Format.money(customer.amount), Color3.fromRGB(120, 255, 140))
	end
	customer.amount = 0

	-- Dine in if a seat is free, otherwise take it to go.
	local freeSeats = {}
	for i in a.layout.seats do
		if not a.seatTaken[i] then
			table.insert(freeSeats, i)
		end
	end
	if #freeSeats > 0 and rng:NextNumber() < 0.7 then
		local seatIndex = freeSeats[rng:NextInteger(1, #freeSeats)]
		local seat = a.layout.seats[seatIndex]
		a.seatTaken[seatIndex] = true
		customer.seat = seatIndex
		customer.state = "toSeat"
		rig:setPath({ a.layout.lane, seat.aisle, seat.position })
	else
		customer.state = "leaving"
		rig:setPath({ a.layout.lane, a.layout.door })
	end
end

local function updateCustomer(customer: Customer, dt: number): boolean -- returns false when done
	local a = active :: any
	local rig = customer.rig
	local state = customer.state
	if state == "entering" or state == "queued" then
		if rig:step(dt) then
			local queue = a.queues[customer.register]
			local index = table.find(queue, customer) or 1
			local spot = queueSpot(customer.register, index)
			if (Vector3.new(spot.X, 0, spot.Z) - Vector3.new(rig.position.X, 0, rig.position.Z)).Magnitude > 0.5 then
				-- The line moved while we walked in: step up to our real place.
				customer.state = "queued"
				rig:setPath({ spot })
			elseif queue[1] == customer then
				customer.state = "ordering"
				customer.timer = serveTime()
			else
				customer.state = "waiting"
			end
			rig:face(rig.position + Vector3.new(0, 0, -1))
		end
	elseif state == "waiting" then
		if a.queues[customer.register][1] == customer then
			customer.state = "ordering"
			customer.timer = serveTime()
		end
	elseif state == "ordering" then
		customer.timer -= dt
		if customer.timer <= 0 then
			finishOrder(customer, false)
		end
	elseif state == "toSeat" then
		if rig:step(dt) then
			local seat = a.layout.seats[customer.seat :: number]
			rig.yaw = seat.yaw
			rig.sitting = true
			customer.state = "sitting"
			customer.timer = rng:NextNumber(6, 11)
			if rig.carrying then
				rig.carrying:Destroy()
				rig.carrying = nil
			end
		end
	elseif state == "sitting" then
		customer.timer -= dt
		if customer.timer <= 0 then
			rig.sitting = false
			local seat = a.layout.seats[customer.seat :: number]
			a.seatTaken[customer.seat :: number] = nil
			customer.seat = nil
			customer.state = "leaving"
			rig:setPath({ seat.aisle, a.layout.lane, a.layout.door })
		end
	elseif state == "toView" then
		if rig:step(dt) then
			customer.state = "viewing"
			customer.timer = rng:NextNumber(5, 9)
			rig:face(rig.position + Vector3.new(0, 0, -1))
		end
	elseif state == "viewing" then
		customer.timer -= dt
		if customer.timer <= 0 then
			customer.state = "leaving"
			rig:setPath({ a.origin + Vector3.new(0, 0, -4), a.layout.lane, a.layout.door })
		end
	elseif state == "leaving" then
		if rig:step(dt) then
			rig:destroy()
			return false
		end
	end
	return true
end

-- Customers who were already inside when we arrived (or before a rebuild): put them
-- straight at the tables, or in line when every seat is taken.
local function seatCustomers(count: number)
	local a = active
	if not a then
		return
	end
	for _ = 1, count do
		local free = {}
		for i in a.layout.seats do
			if not a.seatTaken[i] then
				table.insert(free, i)
			end
		end
		if #free == 0 then
			spawnArrival(0)
		else
			local seatIndex = free[rng:NextInteger(1, #free)]
			local seat = a.layout.seats[seatIndex]
			local rig = NpcRig.new(a.npcFolder, rng, nil, seat.position)
			rig.speed = rng:NextNumber(8, 11)
			rig.yaw = seat.yaw
			rig.sitting = true
			a.seatTaken[seatIndex] = true
			table.insert(a.customers, {
				rig = rig, state = "sitting", amount = 0, timer = rng:NextNumber(2, 10), register = 1, seat = seatIndex,
			})
		end
	end
end

-- Attractions (entry fee): the visitor pays at the door, then enjoys the place for a
-- while (a seat, or watching from the front of the room) and leaves.
local function viewingSpot(): Vector3
	local a = active :: any
	return a.origin + Vector3.new(rng:NextNumber(-32, 32), 0, rng:NextNumber(-8, -3))
end

local function spawnVisitor(amount: number)
	local a = active
	if not a or #a.customers >= math.min(6 + #a.layout.seats, 22) then
		return
	end
	local rig = NpcRig.new(a.npcFolder, rng, nil, a.layout.door)
	rig.speed = rng:NextNumber(8, 11)
	local customer: Customer = { rig = rig, state = "toView", amount = 0, timer = 0, register = 1, seat = nil }
	if amount > 0 then
		popText(a.layout.door + Vector3.new(0, 7, 0), "🎟️ +" .. Format.money(amount), Color3.fromRGB(120, 255, 140))
	end
	local freeSeats = {}
	for i in a.layout.seats do
		if not a.seatTaken[i] then
			table.insert(freeSeats, i)
		end
	end
	if #freeSeats > 0 and rng:NextNumber() < 0.5 then
		local seatIndex = freeSeats[rng:NextInteger(1, #freeSeats)]
		local seat = a.layout.seats[seatIndex]
		a.seatTaken[seatIndex] = true
		customer.seat = seatIndex
		customer.state = "toSeat"
		rig:setPath({ a.layout.lane, seat.aisle, seat.position })
	else
		rig:setPath({ a.layout.lane, a.origin + Vector3.new(0, 0, -4), viewingSpot() })
	end
	table.insert(a.customers, customer)
end

local function spawnArrival(amount: number)
	local a = active
	if a and a.definition.entryFee then
		spawnVisitor(amount)
	else
		spawnCustomer(amount)
	end
end

-- The server's customer roll: each one walks in here when their street walker would
-- reach the door (`lead` seconds from now).
local function onCustomers(list: any, lead: any)
	if type(list) ~= "table" then
		return
	end
	local now = os.clock()
	local delay = if type(lead) == "number" and lead == lead then math.clamp(lead, 0, 30) else 0
	local i = 1
	while i <= #arrivals do -- forget the ones we missed while outside
		if arrivals[i].at < now - 1 then
			table.remove(arrivals, i)
		else
			i += 1
		end
	end
	for _, entry in list do
		if type(entry) == "table" and type(entry[1]) == "string" and type(entry[2]) == "number" and type(entry[3]) == "number" then
			table.insert(arrivals, { id = entry[1], count = entry[2], amount = entry[3], at = now + delay })
		end
	end
	while #arrivals > 200 do
		table.remove(arrivals, 1)
	end
end

local function admitArrivals()
	local a = active
	if not a or not a.layout or #arrivals == 0 then
		return
	end
	local now = os.clock()
	local i = 1
	while i <= #arrivals do
		local arrival = arrivals[i]
		if arrival.at <= now then
			table.remove(arrivals, i)
			if arrival.id == a.businessId then
				local shown = math.clamp(math.floor(arrival.count), 1, 4)
				for _ = 1, shown do
					spawnArrival(arrival.amount / shown)
				end
			end
		else
			i += 1
		end
	end
end

----- Main loop -----
local batchParts: { BasePart } = {}
local batchFrames: { CFrame } = {}

local function onHeartbeat(dt: number)
	local a = active
	if not a then
		return
	end
	dt = math.min(dt, 0.1)
	admitArrivals()

	table.clear(batchParts)
	table.clear(batchFrames)
	for _, worker in a.workers do
		updateWorker(worker, dt)
		worker.rig:collect(dt, batchParts, batchFrames)
	end
	local i = 1
	while i <= #a.customers do
		local customer = a.customers[i]
		if updateCustomer(customer, dt) then
			customer.rig:collect(dt, batchParts, batchFrames)
			i += 1
		else
			table.remove(a.customers, i)
		end
	end
	NpcRig.flush(batchParts, batchFrames)
end

----- Build / teardown -----
local function clearNpcs()
	local a = active
	if not a then
		return
	end
	for _, customer in a.customers do
		customer.rig:destroy()
	end
	for _, worker in a.workers do
		worker.rig:destroy()
	end
	for _, tray in a.trays do
		for _, product in tray do
			product:Destroy()
		end
	end
	a.npcFolder:ClearAllChildren()
	a.customers = {}
	a.workers = {}
	a.seatTaken = {}
	a.queues = {}
	a.trays = {}
end

local function requestExit()
	if os.clock() - exitRequested < 2 then
		return
	end
	exitRequested = os.clock()
	controllers.Store.send("RequestExit")
end

local function frontCustomer(): Customer?
	local a = active
	if not a then
		return nil
	end
	for _, queue in a.queues do
		local front = queue[1]
		if front and (front.state == "ordering" or front.state == "waiting") then
			return front
		end
	end
	return nil
end

local function buildRoom()
	local a = active
	if not a then
		return
	end
	for _, connection in a.connections do
		connection:Disconnect()
	end
	a.connections = {}
	local stayed = #a.customers -- an upgrade rebuilds the room: keep the same crowd
	clearNpcs()
	a.npcFolder.Parent = nil -- keep the NPC folder alive while the old room is destroyed
	if a.model then
		a.model:Destroy()
	end
	local biz = businessState() or { level = 1, upgrades = {} }
	local model, layout = InteriorBuilder.build(Workspace, a.definition, biz, a.origin)
	a.model = model
	a.layout = layout
	a.npcFolder.Parent = model
	a.signature = signatureOf(biz)
	for i in layout.registers do
		a.queues[i] = {}
	end
	for i in layout.pickups do
		a.trays[i] = {}
	end
	for _ = 1, 3 do
		addToTray()
	end
	spawnStaff()
	seatCustomers(stayed)

	table.insert(a.connections, layout.managePrompt.Triggered:Connect(function()
		controllers.UI.openManage(a.businessId)
	end))
	table.insert(a.connections, layout.workPrompt.Triggered:Connect(function()
		local miniGame = controllers.MiniGame
		if miniGame then
			miniGame.open(a.businessId)
		end
	end))
	table.insert(a.connections, layout.exitPrompt.Triggered:Connect(requestExit))
	table.insert(a.connections, layout.exitTrigger.Touched:Connect(function(hit: BasePart)
		local character = player.Character
		if character and hit:IsDescendantOf(character) and os.clock() - a.arrivedAt > 2 then
			requestExit()
		end
	end))
end

local function teardown()
	local a = active
	if not a then
		return
	end
	local miniGame = controllers.MiniGame
	if miniGame then
		miniGame.close()
	end
	for _, connection in a.connections do
		connection:Disconnect()
	end
	clearNpcs()
	a.model:Destroy()
	a.npcFolder:Destroy()
	active = nil
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	setInsideLighting(false)
	controllers.UI.setInside(nil)
end

-- After a teleport the camera keeps its old heading; swing it behind the character.
local function cameraBehindCharacter()
	local camera = workspace.CurrentCamera
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not camera or not root then
		return
	end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		return
	end
	flat = flat.Unit
	camera.CFrame = CFrame.lookAt(root.Position - flat * 12 + Vector3.new(0, 6, 0), root.Position + flat * 6)
end

local function onEnter(businessId: any, origin: any, token: any)
	if type(businessId) ~= "string" or typeof(origin) ~= "Vector3" or type(token) ~= "string" then
		return
	end
	local definition = Businesses.get(businessId)
	if not definition then
		return
	end
	controllers.UI.fade(true)
	controllers.Sound.play("Whoosh", 0.6)
	teardown()
	local npcFolder = Instance.new("Folder")
	npcFolder.Name = "Npcs"
	active = {
		businessId = businessId,
		definition = definition,
		origin = origin,
		model = nil :: any,
		layout = nil :: any,
		npcFolder = npcFolder,
		customers = {},
		workers = {},
		queues = {},
		seatTaken = {},
		trays = {},
		signature = "",
		connections = {},
		arrivedAt = os.clock(),
	}
	buildRoom()
	-- The customers who walked in from the street before us are already inside.
	local ambient = controllers.Ambient
	if ambient and ambient.customersInside then
		seatCustomers(ambient.customersInside(businessId))
	end
	heartbeat = RunService.Heartbeat:Connect(onHeartbeat)
	task.wait(0.25) -- let the fade cover the screen
	controllers.Store.send("InteriorReady", token)

	-- Wait until the server has moved us inside, then reveal.
	local deadline = os.clock() + 6
	while os.clock() < deadline do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - origin).Magnitude < 80 then
			break
		end
		task.wait(0.05)
	end
	if active then
		active.arrivedAt = os.clock()
	end
	cameraBehindCharacter()
	setInsideLighting(true)
	controllers.UI.setInside(businessId)
	controllers.UI.fade(false)
end

local function onExit()
	if not active then
		return
	end
	controllers.UI.fade(true)
	controllers.Sound.play("Whoosh", 0.6)
	task.wait(0.3)
	teardown()
	cameraBehindCharacter()
	controllers.UI.fade(false)
end

function InteriorController.isInside(): boolean
	return active ~= nil
end

function InteriorController.currentBusiness(): string?
	return if active then active.businessId else nil
end

-- Mini game finished: the customer at the front of a line gets their order now.
function InteriorController.serveFront()
	local front = frontCustomer()
	if front then
		finishOrder(front, false)
	end
end

-- The customer at the front of a line says what they want (the mini game's order).
function InteriorController.customerSays(text: string)
	local front = frontCustomer()
	local head = front and front.rig.parts.Head
	if head then
		Bubble.say(head, text, 4.5)
	end
end

function InteriorController.init(registry: any)
	controllers = registry
end

function InteriorController.start()
	local Store = controllers.Store
	Store.remote("EnterInterior").OnClientEvent:Connect(function(...)
		task.spawn(onEnter, ...)
	end)
	Store.remote("ExitInterior").OnClientEvent:Connect(function()
		task.spawn(onExit)
	end)
	Store.remote("Customers").OnClientEvent:Connect(function(list, lead)
		local ok, err = pcall(onCustomers, list, lead)
		if not ok then
			warn("[InteriorController] customers: " .. tostring(err))
		end
	end)
	-- Upgrades bought while inside physically rebuild the room.
	Store.onChange(function(state)
		local a = active
		if not a then
			return
		end
		local biz = state.businesses[a.businessId]
		if not biz then
			return
		end
		local signature = signatureOf(biz)
		if signature ~= a.signature then
			buildRoom()
			sparkle(a.origin + Vector3.new(0, 6, 4))
			controllers.Sound.play("LevelUp", 0.5)
		end
	end)
end

return InteriorController
