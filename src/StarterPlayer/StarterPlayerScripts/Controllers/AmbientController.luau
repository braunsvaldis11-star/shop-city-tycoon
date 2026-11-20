--!strict
-- AmbientController (client): traffic and the pedestrians of the player's own city.
-- Everything is client-side, anchored and non-colliding, so it costs the server nothing,
-- and every player sees only their own pedestrians: how many depends on their City
-- Population upgrade (Config.pedestrianCount). Pedestrians wander the sidewalk network
-- (CityPaths) and cross at the zebra crossings (cars stop for them).
-- Customers are real: the server rolls every customer of every business (EconomyService)
-- and tells us a few seconds before they pay. We send a pedestrian who can reach that
-- door in time (or bring one round the corner, out of sight), and when they step
-- inside the sale pops up over the door. So what walks in is exactly what you earn.
-- All parts move in ONE workspace:BulkMoveTo call per frame; far-away ones are skipped.
-- Container: StarterPlayerScripts.Controllers

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CityLayout = require(Shared.CityLayout)
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Props = require(Shared.Props)
local Client = ReplicatedStorage:WaitForChild("Client")
local CityPaths = require(Client.CityPaths)
local NpcRig = require(Client.NpcRig)

local AmbientController = {}

local controllers: any
local player = Players.LocalPlayer

-- Traffic: one car loop per road (right-hand lanes with U-turns at the ends).
local ROADS = CityLayout.Roads
local CAR_SCALE = 1.15
local CAR_SPACING = 130 -- one car per this many studs of road
local LANE = 5.5 -- lane offset from the road centre
local END_INSET = 9 -- keep U-turns clear of the road ends
local CAR_SPEED = 26
local UPDATE_RADIUS = 460 -- only things this close to the camera are moved each frame
local CAR_COLORS = {
	Color3.fromRGB(235, 70, 70), Color3.fromRGB(60, 140, 240), Color3.fromRGB(250, 200, 50), Color3.fromRGB(80, 200, 110),
	Color3.fromRGB(245, 245, 245), Color3.fromRGB(160, 90, 230), Color3.fromRGB(255, 140, 50), Color3.fromRGB(50, 55, 70),
}

-- Pedestrians.
local VISIT_MIN, VISIT_MAX = 8, 20 -- seconds a customer spends inside
local MAX_INCOMING = 8 -- walkers heading for one door at once; extra sales ride along
local ARRIVAL_SLACK = 3 -- seconds early/late a walker may arrive and still be picked
local HIDDEN_BONUS = 40 -- studs of extra walk worth paying to start a walker out of sight
-- Pedestrians live in a bubble around the camera, so the streets you see stay busy.
local RECYCLE_DISTANCE = 380 -- pedestrians this far from the camera move back near it...
local RESPAWN_MIN, RESPAWN_MAX = 110, 300 -- ...reappearing at a sidewalk this far away, out of view
local POPUP_RADIUS = 200
-- Phones and tablets get fewer pedestrians to keep the frame rate up.
local DEVICE_SHARE = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then 0.6 else 1

type Track = { a: Vector3, d: Vector3, right: Vector3, length: number, loop: number }
type Car = { model: Model, parts: { BasePart }, offsets: { CFrame }, track: Track, s: number, speed: number, shown: boolean }
type Walker = {
	rig: NpcRig.Rig,
	state: string, -- "wander" | "shopping" | "entering" | "inside" | "leaving"
	node: number, -- the node being walked to
	previous: number?, -- the node just left
	door: CityPaths.Door?,
	amount: number, -- what this customer pays (several sales when the shop is busy)
	count: number,
	timer: number,
	jitter: Vector3, -- small personal offset so walkers do not all share one line
	onRoad: boolean, -- currently on a crossing (cars stop)
	shown: boolean, -- parented to the world (near the camera and not inside a shop)
}

local folder: Folder
local cars: { Car } = {}
local walkers: { Walker } = {}
local wantedWalkers = 0
local visible = true
local ready = false
local rng = Random.new()

local function groundY(x: number, z: number, include: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	local hit = Workspace:Raycast(Vector3.new(x, 2.5, z), Vector3.new(0, -20, 0), params)
	return if hit then hit.Position.Y else 0.2
end

----- Traffic -----
-- Position and heading at distance s along a closed loop: lane out, U-turn, lane back, U-turn.
local function sample(track: Track, s: number): (Vector3, Vector3)
	local L, r = track.length, LANE
	local half = math.pi * r
	local a, d, right = track.a, track.d, track.right
	local b = a + d * L
	s %= track.loop
	if s < L then
		return a + right * r + d * s, d
	elseif s < L + half then
		local theta = (s - L) / r
		return b + right * (r * math.cos(theta)) + d * (r * math.sin(theta)), d * math.cos(theta) - right * math.sin(theta)
	elseif s < 2 * L + half then
		return b - right * r - d * (s - L - half), -d
	else
		local theta = (s - 2 * L - half) / r
		return a - right * (r * math.cos(theta)) - d * (r * math.sin(theta)), right * math.sin(theta) - d * math.cos(theta)
	end
end

local function makeCar(track: Track, s: number, color: Color3)
	local model = Props.car(nil, color, false)
	local root = model.PrimaryPart :: BasePart
	-- Scale about the car's ground point (the Root sits 0.5 above it).
	model.WorldPivot = root.CFrame * CFrame.new(0, -0.5, 0)
	model:ScaleTo(CAR_SCALE)
	local ground = model:GetPivot()
	local parts, offsets = {}, {}
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") then
			child.Anchored = true
			child.CanCollide = false
			child.CanTouch = false
			child.CanQuery = false
			child.CastShadow = child.Name == "Body"
			table.insert(parts, child)
			table.insert(offsets, ground:ToObjectSpace(child.CFrame))
		end
	end
	-- Parented only while near the camera (see update), so a car is never seen where it was built.
	table.insert(cars, { model = model, parts = parts, offsets = offsets, track = track, s = s, speed = CAR_SPEED, shown = false })
end

local function buildTraffic(ground: Instance)
	local seed = Random.new(2024)
	for index, road in ROADS do
		local p1 = Vector3.new(road[1], 0, road[2])
		local p2 = Vector3.new(road[3], 0, road[4])
		local d = (p2 - p1).Unit
		local y = groundY((p1.X + p2.X) / 2, (p1.Z + p2.Z) / 2, { ground })
		local a = p1 + d * END_INSET + Vector3.new(0, y, 0)
		local length = (p2 - p1).Magnitude - END_INSET * 2
		local track: Track = { a = a, d = d, right = d:Cross(Vector3.yAxis), length = length, loop = 2 * length + 2 * math.pi * LANE }
		local count = math.max(1, math.floor(CityLayout.roadLength(road) / CAR_SPACING))
		for i = 1, count do
			makeCar(track, track.loop * (i - 1) / count + seed:NextNumber(0, 40), CAR_COLORS[seed:NextInteger(1, #CAR_COLORS)])
		end
		if index % 3 == 0 then
			task.wait() -- spread construction over a few frames
		end
	end
end

----- Pedestrians -----
local function walkTo(walker: Walker, nextNode: number)
	walker.previous, walker.node = walker.node, nextNode
	walker.onRoad = CityPaths.isRoad(walker.previous :: number, nextNode)
	walker.rig:setPath({ CityPaths.position(nextNode) + walker.jitter })
end

local function inView(point: Vector3): boolean
	local camera = Workspace.CurrentCamera
	if not camera then
		return false
	end
	local _, onScreen = camera:WorldToViewportPoint(point + Vector3.new(0, 3, 0))
	return onScreen and (point - camera.CFrame.Position).Magnitude < 300
end

-- Starts a walker somewhere along a sidewalk, optionally near a point, preferring a
-- spot the camera can't see so nobody pops into existence in front of the player.
local function place(walker: Walker, near: Vector3?)
	local start = CityPaths.randomNode(rng, near, RESPAWN_MIN, RESPAWN_MAX)
	if near then
		for _ = 1, 6 do
			if not inView(CityPaths.position(start)) then
				break
			end
			start = CityPaths.randomNode(rng, near, RESPAWN_MIN, RESPAWN_MAX)
		end
	end
	local nextNode = CityPaths.wander(start, nil, rng)
	if CityPaths.isRoad(start, nextNode) then
		nextNode = start
	end
	local from, to = CityPaths.position(start), CityPaths.position(nextNode)
	walker.rig.position = from:Lerp(to, rng:NextNumber(0, 0.9)) + walker.jitter
	walker.state = "wander"
	walker.door = nil
	walker.amount, walker.count = 0, 0
	walker.node = start
	walkTo(walker, nextNode)
end

local function spawnWalker(near: Vector3?)
	local rig = NpcRig.new(folder, rng, nil, Vector3.zero)
	rig.model.Parent = nil -- shown by update once it has been posed near the camera
	rig.speed = rng:NextNumber(5, 7.5)
	local walker: Walker = {
		rig = rig, state = "wander", node = 1, previous = nil, door = nil, amount = 0, count = 0, timer = 0,
		jitter = Vector3.new(rng:NextNumber(-1.2, 1.2), 0, rng:NextNumber(-1.2, 1.2)),
		onRoad = false, shown = false,
	}
	place(walker, near)
	table.insert(walkers, walker)
end

local function customerPopup(door: CityPaths.Door, amount: number, count: number)
	local anchor = Instance.new("Part")
	anchor.Name = "CustomerPopup"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = door.approach + Vector3.new(0, 7, 0)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(150, 36)
	gui.LightInfluence = 0
	gui.MaxDistance = POPUP_RADIUS
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "🛍️ +" .. Format.money(amount) .. if count > 1 then " ×" .. count else ""
	label.TextColor3 = Color3.fromRGB(140, 255, 150)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	gui.Parent = anchor
	anchor.Parent = folder
	local info = TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffset = Vector3.new(0, 5, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1.7)
end

-- Called whenever a walker reaches the end of its current path.
local function arrive(walker: Walker, focus: Vector3)
	local rig = walker.rig
	local state = walker.state
	if state == "entering" then
		-- Through the door: the customer is inside for a while.
		walker.state = "inside"
		walker.timer = rng:NextNumber(VISIT_MIN, VISIT_MAX)
		walker.onRoad = false
		rig.moving = false
		rig.model.Parent = nil
		walker.shown = false
		local door = walker.door :: CityPaths.Door
		if (door.approach - focus).Magnitude < POPUP_RADIUS then
			customerPopup(door, walker.amount, walker.count)
		end
		return
	end
	if state == "leaving" then
		walker.state = "wander"
		walker.door = nil
		walker.amount, walker.count = 0, 0
	end
	local here = walker.node
	if walker.state == "wander" then
		if (rig.position - focus).Magnitude > RECYCLE_DISTANCE then
			place(walker, focus)
			return
		end
	end
	if walker.state == "shopping" then
		local door = walker.door :: CityPaths.Door
		if here == door.entry then
			walker.state = "entering"
			walker.onRoad = false
			rig:setPath({ door.approach, door.inside })
			return
		end
		local nextNode = door.next[here]
		if nextNode then
			walkTo(walker, nextNode)
			return
		end
		walker.state = "wander" -- unreachable (should not happen): just keep strolling
	end
	walkTo(walker, CityPaths.wander(here, walker.previous, rng))
end

----- Customers (sent by the server) -----
-- Studs from a door's sidewalk node, through the door, to inside.
local function doorWalk(door: CityPaths.Door): number
	return (door.approach - CityPaths.position(door.entry)).Magnitude + (door.inside - door.approach).Magnitude
end

-- Studs a wandering walker still has to walk to get inside this door.
local function distanceToDoor(walker: Walker, door: CityPaths.Door): number?
	local remaining = door.distance[walker.node]
	if not remaining then
		return nil
	end
	local toNode = (CityPaths.position(walker.node) + walker.jitter - walker.rig.position).Magnitude
	return toNode + remaining + doorWalk(door)
end

-- A sidewalk spot `want` path-studs from the door (out of sight when possible).
-- Returns the edge (from -> to, walking towards the door) and the point on it.
local function spotAt(door: CityPaths.Door, want: number): (number?, number?, Vector3?)
	local bestFrom, bestTo, bestPoint, bestScore = nil, nil, nil, math.huge
	for from, to in door.next do
		local far, near = door.distance[from], door.distance[to]
		if far and near and far > near and not CityPaths.isRoad(from, to) then
			local along = math.clamp(want - near, 0, far - near)
			local point = CityPaths.position(to):Lerp(CityPaths.position(from), along / (far - near))
			local score = math.abs(want - near - along) + (if inView(point) then HIDDEN_BONUS else 0)
			if score < bestScore then
				bestFrom, bestTo, bestPoint, bestScore = from, to, point, score
			end
		end
	end
	return bestFrom, bestTo, bestPoint
end

local function sendCustomer(door: CityPaths.Door, count: number, amount: number, lead: number, focus: Vector3)
	-- A busy shop: once enough walkers are on their way, the last one carries extra sales.
	local incoming, last = 0, nil
	for _, walker in walkers do
		if walker.door == door and (walker.state == "shopping" or walker.state == "entering") then
			incoming += 1
			last = walker
		end
	end
	if incoming >= MAX_INCOMING and last then
		last.amount += amount
		last.count += count
		return
	end

	-- The wandering walker who would arrive closest to the moment the sale is paid.
	local chosen: Walker? = nil
	local bestMiss = ARRIVAL_SLACK
	for _, walker in walkers do
		if walker.state == "wander" and not walker.onRoad then
			local distance = distanceToDoor(walker, door)
			if distance then
				local miss = math.abs(distance / walker.rig.speed - lead)
				if miss < bestMiss then
					chosen, bestMiss = walker, miss
				end
			end
		end
	end

	if not chosen then
		-- Nobody is in the right place: borrow the walker farthest from the camera and
		-- start them on the sidewalk the right distance away, out of sight if we can.
		local farthest = -1
		for _, walker in walkers do
			if walker.state == "wander" and not walker.onRoad then
				local distance = (walker.rig.position - focus).Magnitude
				if distance > farthest then
					chosen, farthest = walker, distance
				end
			end
		end
		local walker = chosen
		if not walker then
			return
		end
		local from, to, point = spotAt(door, math.max(0, lead * walker.rig.speed - doorWalk(door)))
		if not (from and to and point) then
			return
		end
		walker.rig.position = point + walker.jitter
		walker.previous, walker.node = from, to
		walker.onRoad = false
		walker.rig:setPath({ CityPaths.position(to) + walker.jitter })
	end

	local walker = chosen :: Walker
	walker.state = "shopping"
	walker.door = door
	walker.amount = amount
	walker.count = count
end

local function onCustomers(list: any, lead: any)
	if type(list) ~= "table" or type(lead) ~= "number" or not ready or not visible then
		return
	end
	local camera = Workspace.CurrentCamera
	local focus = if camera then camera.CFrame.Position else Vector3.zero
	for _, entry in list do
		if type(entry) == "table" then
			local id, count, amount = entry[1], entry[2], entry[3]
			local door = if type(id) == "string" then CityPaths.doors[id] else nil
			if door and type(count) == "number" and type(amount) == "number" and (door.approach - focus).Magnitude < UPDATE_RADIUS then
				sendCustomer(door, count, amount, lead, focus)
			end
		end
	end
end

-- How many of the walkers are inside this shop right now (the interior shows them).
-- Read-only access for LifeController (speech bubbles over pedestrians).
function AmbientController.walkerList(): { any }
	return walkers
end

function AmbientController.customersInside(businessId: string): number
	local door = CityPaths.doors[businessId]
	local count = 0
	if door then
		for _, walker in walkers do
			if walker.door == door and walker.state == "inside" then
				count += 1
			end
		end
	end
	return count
end

local function setWalkerCount(count: number)
	wantedWalkers = math.floor(count * DEVICE_SHARE)
	if not ready then
		return
	end
	local camera = Workspace.CurrentCamera
	local near = if camera then camera.CFrame.Position else nil
	while #walkers < wantedWalkers do
		spawnWalker(near)
	end
	while #walkers > wantedWalkers do
		local walker = table.remove(walkers) :: Walker
		walker.rig:destroy()
	end
end

local function onState(state: any)
	if not state then
		return
	end
	setWalkerCount(Config.pedestrianCount(state.population or 0))
end

----- Frame update -----
local batchParts: { BasePart } = {}
local batchFrames: { CFrame } = {}
local crossers: { Vector3 } = {}

local function shouldShow(): boolean
	if controllers.Interior.isInside() then
		return false
	end
	local state = controllers.Store.state
	return not (state and state.settings and state.settings.ambient == false)
end

local function blocks(position: Vector3, heading: Vector3, point: Vector3): boolean
	local offset = point - position
	local ahead = offset:Dot(heading)
	if ahead <= 0 or ahead > 16 or math.abs(offset.Y) > 8 then
		return false
	end
	return (offset - heading * ahead).Magnitude < 5.5
end

local function update(dt: number)
	local show = shouldShow()
	if show ~= visible then
		visible = show
		folder.Parent = if show then Workspace else nil
	end
	if not show then
		return
	end
	local camera = Workspace.CurrentCamera
	local focus = if camera then camera.CFrame.Position else Vector3.zero
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local playerPosition = if rootPart then rootPart.Position else nil

	table.clear(batchParts)
	table.clear(batchFrames)
	table.clear(crossers)

	for _, walker in walkers do
		local rig = walker.rig
		if walker.state == "inside" then
			walker.timer -= dt
			if walker.timer <= 0 then
				-- Back out through the door and on along the sidewalk.
				local door = walker.door :: CityPaths.Door
				walker.state = "leaving"
				walker.node = door.entry
				walker.previous = nil
				rig.position = door.inside
				rig:setPath({ door.approach, CityPaths.position(door.entry) + walker.jitter })
			end
		else
			if rig:step(dt) then
				arrive(walker, focus)
			end
			if walker.onRoad then
				table.insert(crossers, rig.position)
			end
			if walker.state ~= "inside" then
				local near = (rig.position - focus).Magnitude < UPDATE_RADIUS
				if near ~= walker.shown then
					walker.shown = near
					rig.model.Parent = if near then folder else nil
				end
				if near then
					rig:collect(dt, batchParts, batchFrames)
				end
			end
		end
	end

	for _, car in cars do
		local position, heading = sample(car.track, car.s)
		-- Stop for the player or for pedestrians on a crossing ahead.
		local target = CAR_SPEED
		if playerPosition and blocks(position, heading, playerPosition) then
			target = 0
		else
			for _, point in crossers do
				if blocks(position, heading, point) then
					target = 0
					break
				end
			end
		end
		car.speed += (target - car.speed) * math.min(1, dt * 4)
		car.s += car.speed * dt
		local near = (position - focus).Magnitude < UPDATE_RADIUS
		if near ~= car.shown then
			car.shown = near
			car.model.Parent = if near then folder else nil
		end
		if near then
			local cframe = CFrame.lookAt(position, position + heading)
			for i, part in car.parts do
				table.insert(batchParts, part)
				table.insert(batchFrames, cframe * car.offsets[i])
			end
		end
	end
	NpcRig.flush(batchParts, batchFrames)
end

local function build()
	folder = Instance.new("Folder")
	folder.Name = "AmbientLife"
	local city = Workspace:WaitForChild("City")
	local ground = city:WaitForChild("Ground")
	CityPaths.build()
	buildTraffic(ground)
	folder.Parent = Workspace
	ready = true
	onState(controllers.Store.state)
	if wantedWalkers == 0 then
		setWalkerCount(Config.pedestrianCount(0))
	end
end

function AmbientController.init(registry: any)
	controllers = registry
end

function AmbientController.start()
	controllers.Store.onChange(onState)
	controllers.Store.remote("Customers").OnClientEvent:Connect(function(list, lead)
		local ok, err = pcall(onCustomers, list, lead)
		if not ok then
			warn("[AmbientController] customers: " .. tostring(err))
		end
	end)
	task.spawn(function()
		local ok, err = pcall(build)
		if not ok then
			warn("[AmbientController] build failed: " .. tostring(err))
			return
		end
		RunService.Heartbeat:Connect(function(dt)
			local success, message = pcall(update, math.min(dt, 0.1))
			if not success then
				warn("[AmbientController] " .. tostring(message))
			end
		end)
	end)
end

return AmbientController
