--!strict
-- JobService: the optional paper route side job (OFF unless Config.PAPER_ROUTE_ENABLED).
-- Players grab a bag of newspapers at the News Stand and throw them at the mailboxes.
-- The server owns everything that matters: it hands out the route, checks the player
-- is at the stand / within throwing range of a mailbox that is really on their route,
-- rate-limits deliveries and pays. The client only animates the throw.
-- Container: ServerScriptService.Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)

local JobService = {}

local JOB = Config.PaperJob

type Route = { papers: number, stops: { string }, lastThrow: number, lastGrab: number }

local services: any
local routes: { [Player]: Route } = {}
local mailboxes: { [string]: Vector3 } = {}
local mailboxNames: { string } = {}
local standPosition: Vector3? = nil
local rng = Random.new()

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function routeOf(player: Player): Route
	local route = routes[player]
	if not route then
		route = { papers = 0, stops = {}, lastThrow = 0, lastGrab = 0 }
		routes[player] = route
	end
	return route
end

----- Delivery Sneakers: after the first finished route you run faster with a bag -----
local FEET = { "LeftFoot", "RightFoot", "Left Leg", "Right Leg" }

local function hasSneakers(player: Player): boolean
	local profile = services.Data.get(player)
	return profile ~= nil and (profile.data.stats.routes or 0) >= JOB.sneakerRoutes
end

local function setSneakers(player: Player, on: boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then
		return
	end
	humanoid.WalkSpeed = if on then JOB.sneakerSpeed else StarterPlayer.CharacterWalkSpeed
	local old = character:FindFirstChild("SneakerTrails")
	if old then
		old:Destroy()
	end
	for _, name in FEET do
		local foot = character:FindFirstChild(name)
		if foot then
			for _, child in foot:GetChildren() do
				if child.Name == "SneakerTop" or child.Name == "SneakerBottom" then
					child:Destroy()
				end
			end
		end
	end
	if not on then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "SneakerTrails"
	for _, name in FEET do
		local foot = character:FindFirstChild(name)
		if foot and foot:IsA("BasePart") then
			local bottomY = -foot.Size.Y / 2
			local top = Instance.new("Attachment")
			top.Name = "SneakerTop"
			top.Position = Vector3.new(0, bottomY + 0.45, 0)
			top.Parent = foot
			local bottom = Instance.new("Attachment")
			bottom.Name = "SneakerBottom"
			bottom.Position = Vector3.new(0, bottomY + 0.05, 0)
			bottom.Parent = foot
			local trail = Instance.new("Trail")
			trail.Attachment0 = top
			trail.Attachment1 = bottom
			trail.Color = ColorSequence.new(Color3.fromRGB(255, 225, 60), Color3.fromRGB(255, 120, 40))
			trail.Transparency = NumberSequence.new(0.25, 1)
			trail.Lifetime = 0.3
			trail.LightEmission = 0.6
			trail.MinLength = 0.05
			trail.FaceCamera = true
			trail.Parent = folder
		end
	end
	folder.Parent = character
end

----- Bag visual (server-side so everyone sees the paper kid) -----
local function removeBag(player: Player)
	local character = player.Character
	local bag = character and character:FindFirstChild("PaperBag")
	if bag then
		bag:Destroy()
	end
	setSneakers(player, false)
end

local function giveBag(player: Player)
	local character = player.Character
	if not character or character:FindFirstChild("PaperBag") then
		return
	end
	local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
	if not torso then
		return
	end
	local model = Instance.new("Model")
	model.Name = "PaperBag"
	local function part(name: string, size: Vector3, offset: CFrame, color: Color3): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.Fabric
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CFrame = torso.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = torso
		weld.Part1 = p
		weld.Parent = p
		p.Parent = model
		return p
	end
	-- Satchel on the left hip with a strap across the chest and papers sticking out.
	local bagColor = Color3.fromRGB(205, 160, 95)
	part("Satchel", Vector3.new(0.9, 1.5, 1.7), CFrame.new(-1.25, -0.9, 0), bagColor)
	part("Flap", Vector3.new(0.95, 0.5, 1.75), CFrame.new(-1.27, -0.3, 0), bagColor:Lerp(Color3.new(0, 0, 0), 0.2))
	part("Strap", Vector3.new(0.25, 2.6, 0.12), CFrame.new(-0.1, 0, -0.62) * CFrame.Angles(0, 0, math.rad(-40)), Color3.fromRGB(120, 80, 45))
	part("StrapBack", Vector3.new(0.25, 2.6, 0.12), CFrame.new(-0.1, 0, 0.62) * CFrame.Angles(0, 0, math.rad(-40)), Color3.fromRGB(120, 80, 45))
	for i = 0, 2 do
		local paper = part("Paper", Vector3.new(0.35, 0.9, 0.35), CFrame.new(-1.25, 0, -0.5 + i * 0.5) * CFrame.Angles(0, 0, math.rad(-12 + i * 10)), Color3.fromRGB(240, 238, 230))
		paper.Material = Enum.Material.SmoothPlastic
	end
	model.Parent = character
	if hasSneakers(player) then
		setSneakers(player, true)
	end
end

----- Route planning -----
-- A walkable route: start at the stand, each next stop is one of the few nearest
-- unvisited mailboxes, so the route snakes through the neighbourhood.
local function planRoute(from: Vector3): { string }
	local pool = {}
	for _, name in mailboxNames do
		if standPosition == nil or flat(mailboxes[name], standPosition) <= JOB.routeRadius then
			table.insert(pool, name)
		end
	end
	local stops = {}
	local here = from
	for _ = 1, math.min(JOB.bagSize, #pool) do
		table.sort(pool, function(a, b)
			return flat(mailboxes[a], here) < flat(mailboxes[b], here)
		end)
		local pick = rng:NextInteger(1, math.min(JOB.pickFrom, #pool))
		local name = table.remove(pool, pick) :: string
		table.insert(stops, name)
		here = mailboxes[name]
	end
	return stops
end

function JobService.describe(player: Player): any
	if not Config.PAPER_ROUTE_ENABLED then
		return nil
	end
	local route = routes[player]
	if not route then
		return { papers = 0, stops = {} }
	end
	return { papers = route.papers, stops = route.stops }
end

local function income(player: Player): number
	return services.Economy.getCache(player).total
end

function JobService.paperPay(player: Player): number
	return math.max(JOB.payPerPaper, math.floor(income(player) * JOB.incomeSecondsPerPaper))
end

local function grab(player: Player)
	local profile = services.Data.get(player)
	local root = rootOf(player)
	if not profile or not root or not standPosition then
		return
	end
	if flat(root.Position, standPosition) > JOB.standRange then
		return
	end
	local route = routeOf(player)
	local now = os.clock()
	if now - route.lastGrab < 1 then
		return
	end
	route.lastGrab = now
	if route.papers > 0 then
		services.Net.notify(player, "info", string.format("\u{1F4F0} You still have %d papers - follow the markers to the mailboxes!", route.papers))
		giveBag(player)
		return
	end
	route.papers = JOB.bagSize
	route.stops = planRoute(standPosition)
	profile.data.stats.bags = (profile.data.stats.bags or 0) + 1
	services.Data.markDirty(player)
	giveBag(player)
	services.Net.notify(player, "success", string.format("\u{1F4F0} Got %d papers! Throw one at each marked mailbox (%s each).", JOB.bagSize, Format.cash(JobService.paperPay(player))))
	services.Net.fire(player, "PaperJob", "grab")
	services.Progression.check(player)
	services.Sync.mark(player)
end

local function deliver(player: Player, mailbox: any)
	if type(mailbox) ~= "string" or #mailbox > 16 then
		return
	end
	local profile = services.Data.get(player)
	local route = routes[player]
	local root = rootOf(player)
	local target = mailboxes[mailbox]
	if not profile or not route or not root or not target or route.papers <= 0 then
		return
	end
	local index = table.find(route.stops, mailbox)
	if not index then
		return
	end
	local now = os.clock()
	if now - route.lastThrow < JOB.minInterval then
		return
	end
	if flat(root.Position, target) > JOB.throwRange + 4 then -- a little slack for latency
		services.Net.notify(player, "error", "Too far away - get closer to the mailbox!")
		return
	end
	route.lastThrow = now
	table.remove(route.stops, index)
	route.papers -= 1

	local pay = JobService.paperPay(player)
	local tip = 0
	if rng:NextNumber() < JOB.tipChance then
		tip = math.max(JOB.tip, math.floor(pay * 0.4))
	end
	services.Economy.addMoney(player, pay + tip, true)
	profile.data.stats.papers = (profile.data.stats.papers or 0) + 1
	services.Data.markDirty(player)
	services.Net.fire(player, "PaperJob", "delivered", mailbox, pay, tip, route.papers)

	if route.papers <= 0 then
		route.stops = {}
		local bonus = math.max(JOB.bagBonus, math.floor(income(player) * JOB.incomeSecondsPerBag))
		services.Economy.addMoney(player, bonus, true)
		local stats = profile.data.stats
		stats.routes = (stats.routes or 0) + 1
		removeBag(player)
		services.Net.fire(player, "PaperJob", "bagDone", bonus)
		services.Net.notify(player, "reward", "\u{1F389} Route complete! +" .. Format.cash(bonus) .. " bonus. Grab another bag at the News Stand!")
		if stats.routes == JOB.sneakerRoutes then
			task.delay(2.5, function()
				services.Net.notify(player, "reward", "\u{1F45F} Delivery Sneakers unlocked! You run faster while you carry papers.")
			end)
		end
	end
	services.Progression.check(player)
	services.Sync.mark(player)
end

function JobService.init(registry: any)
	services = registry
end

function JobService.start()
	if not Config.PAPER_ROUTE_ENABLED then
		-- Switched off: remove the News Stand and mailboxes for this server (the copy in
		-- the place file stays, so flipping the flag brings everything back).
		local city = Workspace:FindFirstChild("City")
		local old = city and city:FindFirstChild("PaperRoute")
		if old then
			old:Destroy()
		end
		return
	end
	local route = Workspace:WaitForChild("City"):WaitForChild("PaperRoute", 10)
	if not route then
		warn("[JobService] Workspace.City.PaperRoute is missing - run ServerStorage.DevTools.PaperRouteBuilder.build()")
		return
	end
	local folder = route:WaitForChild("Mailboxes")
	for _, mailbox in folder:GetChildren() do
		if mailbox:IsA("Model") and mailbox.PrimaryPart then
			mailboxes[mailbox.Name] = mailbox.PrimaryPart.Position
			table.insert(mailboxNames, mailbox.Name)
		end
	end
	table.sort(mailboxNames)
	local stand = route:WaitForChild("NewsStand")
	local grabPoint = stand:WaitForChild("GrabPoint") :: BasePart
	standPosition = grabPoint.Position
	local prompt = grabPoint:WaitForChild("GrabPrompt") :: ProximityPrompt
	prompt.Triggered:Connect(function(player)
		local ok, err = pcall(grab, player)
		if not ok then
			warn("[JobService] grab failed: " .. tostring(err))
		end
	end)
	services.Net.on("PaperThrow", 4, deliver)

	local function onCharacter(player: Player)
		local r = routes[player]
		if r and r.papers > 0 then
			task.delay(1, giveBag, player)
		end
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			onCharacter(player)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function()
			onCharacter(player)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		routes[player] = nil
	end)
	print(string.format("[JobService] Paper route ready: %d mailboxes", #mailboxNames))
end

return JobService
