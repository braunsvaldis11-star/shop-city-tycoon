--!strict
-- LifeController (client): the little things that make the city feel alive.
--  * Pedestrians chat in speech bubbles and say hi when you walk past them.
--  * Gulls circle overhead in loose V flocks that drift along with you.
--  * Pigeons peck around the parks and plazas, scatter when you walk at them and
--    land again once you have moved on.
--  * Butterflies flutter over the flower beds near you.
--  * A street guitarist (with real music) and a balloon seller in the spawn park.
-- Everything is local, anchored and non-colliding, all moved in ONE BulkMoveTo per
-- frame, and hidden inside businesses or when the "ambient life" setting is off.
-- Container: StarterPlayerScripts.Controllers

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Props = require(Shared.Props)
local Client = ReplicatedStorage:WaitForChild("Client")
local NpcRig = require(Client:WaitForChild("NpcRig"))
local Bubble = require(Client:WaitForChild("Bubble"))

local LifeController = {}

local player = Players.LocalPlayer
local controllers: any
local rng = Random.new()

local MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local HIDDEN = CFrame.new(0, -500, 0)
local FLOCK_COUNT = if MOBILE then 2 else 3
local BIRDS_PER_FLOCK = 6
local BUTTERFLY_COUNT = if MOBILE then 6 else 10
local BUTTERFLY_RANGE = 110
local PIGEONS_PER_GROUP = if MOBILE then 4 else 5
local PIGEON_RANGE = 170
local FLEE_RADIUS = 9
local LAND_TIME = 1.8
local PERFORMER_RANGE = 220
local BUSKER_SONG = "rbxassetid://1837768517" -- "Bossa Me" (APM, Roblox licensed library)
local BIRDSONG = "rbxassetid://9112831284" -- "Morning Birds 1" (ProSoundEffects)

-- Spawn park (Block05_park): fountain plaza ring between r = 12 and r = 19.
local SPAWN_POINT = Vector3.new(0, 1.1, 34)
local BUSKER_SPOT = Vector2.new(-14, 10)
local SELLER_SPOT = Vector2.new(15, 8)
local SPAWN_PIGEONS = Vector2.new(3, 17.5)

local WALKABLE = { Plaza = true, PathX = true, PathZ = true, Lawn = true, Sidewalk = true, Paving = true, Grass = true }

local CHATTER = {
	"What a lovely day! \u{2600}\u{FE0F}",
	"This city keeps growing!",
	"I could really use a coffee \u{2615}",
	"Ooh, a new shop opened!",
	"Running late again! \u{23F0}",
	"Love this neighbourhood \u{2764}\u{FE0F}",
	"Did you see the fireworks? \u{1F386}",
	"Nice weather for a walk.",
	"My feet hurt... \u{1F605}",
	"Who owns all these shops?",
	"\u{1F3B5} La la la... \u{1F3B5}",
	"I'm so hungry! \u{1F354}",
	"Read today's paper? \u{1F4F0}",
	"Where did I park my car?",
	"The park looks so pretty \u{1F337}",
}
local SHOPPING_LINES = {
	"Time to treat myself! \u{1F6CD}\u{FE0F}",
	"I heard this place is great!",
	"I know exactly what I want!",
	"My favourite shop! \u{2B50}",
	"Hope there's no queue...",
}
local LEAVING_LINES = {
	"That was delicious! \u{1F60B}",
	"Best service in town!",
	"I'll be back! \u{1F44D}",
	"Worth every penny! \u{1F4B0}",
	"Five stars! \u{2B50}\u{2B50}\u{2B50}",
}
local GREETINGS = { "Hi there! \u{1F44B}", "Hello, neighbour!", "Hey! \u{1F604}", "Good day to you!", "Nice to see you!", "Oh, hello!" }
local OWNER_GREETINGS = { "Hey, it's the boss! \u{1F44B}", "Love your shops! \u{2B50}", "Hi, business owner!", "Your shop is the best!", "Big fan! \u{1F604}" }
local SELLER_LINES = { "Balloons! \u{1F388}", "Every colour you like! \u{1F388}", "A balloon for the boss? \u{1F604}", "Balloons make days better!" }
local BUSKER_LINES = { "Thanks for listening! \u{1F3B8}", "This one's for you! \u{1F3B6}", "Tips appreciated! \u{1F3A9}", "Feel the rhythm! \u{1F3B5}" }
local NOTES = { "\u{266A}", "\u{266B}", "\u{266C}" }
local NOTE_COLORS = { Color3.fromRGB(255, 214, 40), Color3.fromRGB(255, 120, 190), Color3.fromRGB(110, 200, 255), Color3.fromRGB(140, 235, 120) }

local folder: Folder
local visible = true
local clock = 0
local batchParts: { BasePart } = {}
local batchFrames: { CFrame } = {}

----- Helpers -----
local function add(part: BasePart, cframe: CFrame)
	table.insert(batchParts, part)
	table.insert(batchFrames, cframe)
end

local function piece(parent: Instance, name: string, size: Vector3, color: Color3, shape: Enum.PartType?): Part
	return Props.part(parent, name, size, HIDDEN, color, { collide = false, shadow = false, shape = shape })
end

local function pick(list: { string }): string
	return list[rng:NextInteger(1, #list)]
end

local function rootPart(): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function settings(): any
	local state = controllers.Store.state
	return state and state.settings
end

local function ownsAnything(): boolean
	local state = controllers.Store.state
	return state ~= nil and type(state.businesses) == "table" and next(state.businesses) ~= nil
end

local function shouldShow(): boolean
	if controllers.Interior and controllers.Interior.isInside() then
		return false
	end
	local s = settings()
	return not (s and s.ambient == false)
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include

-- Ground under (x, z) in the city, and the name of the part that was hit.
local function ground(x: number, z: number): (Vector3?, string?)
	local city = Workspace:FindFirstChild("City")
	if not city then
		return nil, nil
	end
	groundParams.FilterDescendantsInstances = { city }
	local hit = Workspace:Raycast(Vector3.new(x, 80, z), Vector3.new(0, -160, 0), groundParams)
	if hit then
		return hit.Position, hit.Instance.Name
	end
	return nil, nil
end

local function walkable(x: number, z: number): Vector3?
	local hit, name = ground(x, z)
	if hit and name and WALKABLE[name] then
		return hit
	end
	return nil
end

local function onScreen(camera: Camera, position: Vector3): boolean
	local point, inView = camera:WorldToViewportPoint(position)
	return inView and point.Z > 0
end

----- Gulls -----
type Bird = { body: BasePart, head: BasePart, beak: BasePart, wingL: BasePart, wingR: BasePart, offset: Vector3, phase: number }
type Flock = { birds: { Bird }, center: Vector3, home: Vector3, radius: number, height: number, speed: number, angle: number, direction: number }
local flocks: { Flock } = {}

local GULL_BODY = Color3.fromRGB(246, 246, 250)
local GULL_WING = Color3.fromRGB(190, 198, 212)
local BEAK = Color3.fromRGB(250, 175, 60)

local function buildFlocks()
	for f = 1, FLOCK_COUNT do
		local model = Instance.new("Model")
		model.Name = "Flock" .. f
		model.Parent = folder
		local flock: Flock = {
			birds = {},
			center = Vector3.zero,
			home = Vector3.new(rng:NextNumber(-110, 110), 0, rng:NextNumber(-110, 110)),
			radius = rng:NextNumber(35, 75),
			height = rng:NextNumber(48, 72),
			speed = rng:NextNumber(14, 20),
			angle = rng:NextNumber(0, math.pi * 2),
			direction = if rng:NextNumber() < 0.5 then 1 else -1,
		}
		for i = 1, BIRDS_PER_FLOCK do
			-- Loose V behind the leader (local +Z is behind, +X is right).
			local row = math.floor(i / 2)
			local side = if i % 2 == 0 then 1 else -1
			table.insert(flock.birds, {
				body = piece(model, "Body", Vector3.new(0.9, 0.8, 2), GULL_BODY),
				head = piece(model, "Head", Vector3.new(0.7, 0.7, 0.7), GULL_BODY),
				beak = piece(model, "Beak", Vector3.new(0.2, 0.2, 0.5), BEAK),
				wingL = piece(model, "WingL", Vector3.new(2.4, 0.12, 1.1), GULL_WING),
				wingR = piece(model, "WingR", Vector3.new(2.4, 0.12, 1.1), GULL_WING),
				offset = Vector3.new(side * row * 3.2 + rng:NextNumber(-0.8, 0.8), rng:NextNumber(-1.5, 1.5), row * 3.4 + rng:NextNumber(-0.8, 0.8)),
				phase = rng:NextNumber(0, math.pi * 2),
			})
		end
		table.insert(flocks, flock)
	end
end

-- flap > 0 raises the wing tips.
local function poseBird(bird: Bird, cf: CFrame, flap: number)
	add(bird.body, cf)
	add(bird.head, cf * CFrame.new(0, 0.35, -1.2))
	add(bird.beak, cf * CFrame.new(0, 0.28, -1.75))
	add(bird.wingL, cf * CFrame.new(-0.45, 0.2, -0.1) * CFrame.Angles(0, 0, -flap) * CFrame.new(-1.2, 0, 0))
	add(bird.wingR, cf * CFrame.new(0.45, 0.2, -0.1) * CFrame.Angles(0, 0, flap) * CFrame.new(1.2, 0, 0))
end

local function updateFlocks(dt: number, cameraPosition: Vector3)
	local follow = Vector3.new(cameraPosition.X, 0, cameraPosition.Z)
	for _, flock in flocks do
		local goal = follow + flock.home
		local gap = goal - flock.center
		if gap.Magnitude > 600 then
			flock.center = goal
		else
			flock.center += gap * math.min(1, dt * 0.06)
		end
		flock.angle += flock.direction * flock.speed / flock.radius * dt
		local a = flock.angle
		local radial = Vector3.new(math.cos(a), 0, math.sin(a))
		local lead = flock.center + radial * flock.radius + Vector3.new(0, flock.height + math.sin(a * 0.5) * 4, 0)
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a)) * flock.direction
		local heading = CFrame.lookAt(lead, lead + tangent)
		-- Bank into the turn (the circle centre is on the inside).
		local inward = if (-radial):Dot(heading.RightVector) > 0 then 1 else -1
		local bank = CFrame.Angles(0, 0, -0.3 * inward)
		for _, bird in flock.birds do
			local gliding = (clock + bird.phase) % 5 > 3.2
			local flap = if gliding then 0.1 else math.sin(clock * 11 + bird.phase) * 0.75
			local bob = Vector3.new(0, math.sin(clock * 1.7 + bird.phase) * 0.5, 0)
			poseBird(bird, heading * CFrame.new(bird.offset + bob) * bank, flap)
		end
	end
end

----- Pigeons -----
type Pigeon = {
	body: BasePart,
	head: BasePart,
	beak: BasePart,
	wingL: BasePart,
	wingR: BasePart,
	tail: BasePart,
	legs: BasePart,
	position: Vector3,
	yaw: number,
	target: Vector3?,
	timer: number,
	peck: number,
	phase: number,
	velocity: Vector3,
	from: Vector3,
	to: Vector3,
}
type PigeonGroup = { spot: Vector3, pigeons: { Pigeon }, state: string, timer: number }
local pigeonGroups: { PigeonGroup } = {}

local PIGEON_LOOKS = {
	{ body = Color3.fromRGB(150, 156, 172), head = Color3.fromRGB(96, 108, 128), wing = Color3.fromRGB(128, 134, 150) },
	{ body = Color3.fromRGB(236, 236, 240), head = Color3.fromRGB(222, 222, 228), wing = Color3.fromRGB(200, 200, 210) },
	{ body = Color3.fromRGB(165, 125, 100), head = Color3.fromRGB(120, 92, 75), wing = Color3.fromRGB(140, 105, 85) },
}
local FOLDED = -1.4 -- wings tucked flat against the sides

local function scatterPoint(spot: Vector3, radius: number): Vector3?
	local angle = rng:NextNumber(0, math.pi * 2)
	local r = math.sqrt(rng:NextNumber()) * radius
	local hit = walkable(spot.X + math.cos(angle) * r, spot.Z + math.sin(angle) * r)
	if hit and math.abs(hit.Y - spot.Y) < 0.6 then
		return hit
	end
	return nil
end

local function posePigeon(p: Pigeon, flap: number, peck: number, hop: number, pitch: number)
	local base = CFrame.new(p.position + Vector3.new(0, hop, 0)) * CFrame.Angles(0, p.yaw, 0) * CFrame.Angles(pitch, 0, 0)
	add(p.body, base * CFrame.new(0, 0.55, 0))
	local head = base * CFrame.new(0, 1.0 - 0.6 * peck, -0.5 - 0.25 * peck) * CFrame.Angles(-0.9 * peck, 0, 0)
	add(p.head, head)
	add(p.beak, head * CFrame.new(0, -0.05, -0.32))
	add(p.tail, base * CFrame.new(0, 0.6, 0.68) * CFrame.Angles(0.35, 0, 0))
	add(p.legs, base * CFrame.new(0, 0.12, 0))
	add(p.wingL, base * CFrame.new(-0.36, 0.85, 0.05) * CFrame.Angles(0, 0, -flap) * CFrame.new(-0.375, 0, 0))
	add(p.wingR, base * CFrame.new(0.36, 0.85, 0.05) * CFrame.Angles(0, 0, flap) * CFrame.new(0.375, 0, 0))
end

local function hidePigeon(p: Pigeon)
	for _, part in { p.body, p.head, p.beak, p.wingL, p.wingR, p.tail, p.legs } do
		add(part, HIDDEN)
	end
end

local function addPigeonGroup(spot: Vector3)
	for _, group in pigeonGroups do
		if (group.spot - spot).Magnitude < 25 then
			return
		end
	end
	local model = Instance.new("Model")
	model.Name = "Pigeons"
	model.Parent = folder
	local group: PigeonGroup = { spot = spot, pigeons = {}, state = "ground", timer = 0 }
	for _ = 1, PIGEONS_PER_GROUP do
		local look = if rng:NextNumber() < 0.7 then PIGEON_LOOKS[1] else PIGEON_LOOKS[rng:NextInteger(2, 3)]
		local start = scatterPoint(spot, 3.5) or spot
		table.insert(group.pigeons, {
			body = piece(model, "Body", Vector3.new(0.75, 0.7, 1.1), look.body),
			head = piece(model, "Head", Vector3.new(0.45, 0.45, 0.45), look.head),
			beak = piece(model, "Beak", Vector3.new(0.14, 0.12, 0.26), Color3.fromRGB(230, 170, 90)),
			wingL = piece(model, "WingL", Vector3.new(0.75, 0.08, 0.6), look.wing),
			wingR = piece(model, "WingR", Vector3.new(0.75, 0.08, 0.6), look.wing),
			tail = piece(model, "Tail", Vector3.new(0.5, 0.1, 0.5), look.head),
			legs = piece(model, "Legs", Vector3.new(0.36, 0.24, 0.1), Color3.fromRGB(225, 120, 110)),
			position = start,
			yaw = rng:NextNumber(0, math.pi * 2),
			target = nil,
			timer = rng:NextNumber(0, 1.5),
			peck = 0,
			phase = rng:NextNumber(0, math.pi * 2),
			velocity = Vector3.zero,
			from = start,
			to = start,
		})
	end
	table.insert(pigeonGroups, group)
end

local function buildPigeons(city: Instance)
	local spawnSpot = walkable(SPAWN_PIGEONS.X, SPAWN_PIGEONS.Y)
	if spawnSpot then
		addPigeonGroup(spawnSpot)
	end
	local blocks = city:FindFirstChild("Blocks")
	if not blocks then
		return
	end
	local offsets = { Vector2.new(0.28, 0.3), Vector2.new(-0.3, -0.26), Vector2.new(-0.3, 0.3), Vector2.new(0.3, -0.3), Vector2.new(0, 0.36), Vector2.new(0.36, 0) }
	for _, block in blocks:GetChildren() do
		if block:IsA("Model") and (block.Name:match("park$") or block.Name:match("plaza$")) then
			local cf, size = block:GetBoundingBox()
			local found = 0
			for _, offset in offsets do
				local hit = walkable(cf.Position.X + offset.X * size.X, cf.Position.Z + offset.Y * size.Z)
				if hit then
					addPigeonGroup(hit)
					found += 1
					if found >= 2 then
						break
					end
				end
			end
		end
	end
end

local function startFlee(group: PigeonGroup, from: Vector3)
	group.state = "fleeing"
	group.timer = 3
	for _, p in group.pigeons do
		local away = Vector3.new(p.position.X - from.X, 0, p.position.Z - from.Z)
		if away.Magnitude < 0.1 then
			local a = rng:NextNumber(0, math.pi * 2)
			away = Vector3.new(math.cos(a), 0, math.sin(a))
		end
		p.velocity = away.Unit * rng:NextNumber(9, 14) + Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(9, 13), rng:NextNumber(-3, 3))
		p.peck = 0
		p.target = nil
		p.timer = rng:NextNumber(0, 0.25) -- a little stagger before take-off
	end
end

local function stepPigeonOnGround(group: PigeonGroup, p: Pigeon, dt: number)
	local hop = 0
	local peck = 0
	if p.peck > 0 then
		p.peck = math.max(0, p.peck - dt)
		peck = math.sin((1 - p.peck / 0.35) * math.pi)
	elseif p.target then
		local target = p.target :: Vector3
		local offset = Vector3.new(target.X - p.position.X, 0, target.Z - p.position.Z)
		local distance = offset.Magnitude
		local travel = 2.4 * dt
		if distance <= travel then
			p.position = target
			p.target = nil
		else
			local direction = offset / distance
			p.position += direction * travel
			p.yaw = math.atan2(-direction.X, -direction.Z)
			hop = math.abs(math.sin(clock * 16 + p.phase)) * 0.1
		end
	else
		p.timer -= dt
		if p.timer <= 0 then
			local roll = rng:NextNumber()
			if roll < 0.5 then
				p.peck = 0.35
				p.timer = rng:NextNumber(0.2, 0.9)
			elseif roll < 0.85 then
				p.target = scatterPoint(group.spot, 3.5)
				p.timer = rng:NextNumber(0.4, 1.5)
			else
				p.yaw += rng:NextNumber(-1.2, 1.2)
				p.timer = rng:NextNumber(0.5, 1.5)
			end
		end
	end
	posePigeon(p, FOLDED, peck, hop, 0)
end

local function updatePigeons(dt: number, cameraPosition: Vector3, root: BasePart?)
	for _, group in pigeonGroups do
		if group.state == "ground" then
			if (group.spot - cameraPosition).Magnitude > PIGEON_RANGE then
				continue
			end
			if root then
				local d = root.Position - group.spot
				if Vector2.new(d.X, d.Z).Magnitude < FLEE_RADIUS and math.abs(d.Y) < 10 then
					startFlee(group, root.Position)
				end
			end
			if group.state == "ground" then
				for _, p in group.pigeons do
					stepPigeonOnGround(group, p, dt)
				end
			end
		elseif group.state == "fleeing" then
			group.timer -= dt
			for _, p in group.pigeons do
				if group.timer <= 0 then
					hidePigeon(p)
				elseif p.timer > 0 then
					p.timer -= dt
					posePigeon(p, math.sin(clock * 30 + p.phase) * 0.9, 0, 0.1, 0)
				else
					p.velocity += Vector3.new(0, 3 * dt, 0)
					p.position += p.velocity * dt
					local flat = Vector3.new(p.velocity.X, 0, p.velocity.Z)
					if flat.Magnitude > 0.1 then
						p.yaw = math.atan2(-flat.X, -flat.Z)
					end
					posePigeon(p, math.sin(clock * 28 + p.phase) * 0.9, 0, 0, 0.35)
				end
			end
			if group.timer <= 0 then
				group.state = "away"
				group.timer = rng:NextNumber(14, 24)
			end
		elseif group.state == "away" then
			group.timer -= dt
			if group.timer <= 0 then
				if root and (root.Position - group.spot).Magnitude < 30 then
					group.timer = 3 -- still too close: try again soon
				else
					group.state = "landing"
					group.timer = LAND_TIME
					for _, p in group.pigeons do
						local to = scatterPoint(group.spot, 3.5) or group.spot
						local a = rng:NextNumber(0, math.pi * 2)
						p.from = to + Vector3.new(math.cos(a) * 26, 20, math.sin(a) * 26)
						p.to = to
						p.position = p.from
						local flat = to - p.from
						p.yaw = math.atan2(-flat.X, -flat.Z)
					end
				end
			end
		elseif group.state == "landing" then
			group.timer -= dt
			local alpha = 1 - math.max(group.timer, 0) / LAND_TIME
			local eased = 1 - (1 - alpha) * (1 - alpha)
			for _, p in group.pigeons do
				p.position = p.from:Lerp(p.to, eased)
				if group.timer > 0 then
					posePigeon(p, math.sin(clock * 24 + p.phase) * 0.8, 0, 0, -0.2 * (1 - alpha))
				else
					p.position = p.to
					p.timer = rng:NextNumber(0.3, 1.5)
					posePigeon(p, FOLDED, 0, 0, 0)
				end
			end
			if group.timer <= 0 then
				group.state = "ground"
			end
		end
	end
end

----- Butterflies -----
type Butterfly = { body: BasePart, wingL: BasePart, wingR: BasePart, bed: BasePart?, phase: number, speed: number, last: Vector3, yaw: number, hidden: boolean }
local butterflies: { Butterfly } = {}
local beds: { BasePart } = {}
local bedSet: { [BasePart]: boolean } = {}
local BUTTERFLY_COLORS = {
	Color3.fromRGB(255, 165, 40), Color3.fromRGB(120, 190, 255), Color3.fromRGB(255, 120, 200),
	Color3.fromRGB(255, 236, 90), Color3.fromRGB(250, 250, 250), Color3.fromRGB(180, 120, 255),
}

local function addBed(instance: Instance)
	if instance:IsA("BasePart") and instance.Name == "Soil" and instance.Parent and instance.Parent.Name == "FlowerBed" and not bedSet[instance] then
		bedSet[instance] = true
		table.insert(beds, instance)
	end
end

local function buildButterflies(city: Instance)
	for _, descendant in city:GetDescendants() do
		if descendant.Name == "FlowerBed" then
			local soil = descendant:FindFirstChild("Soil")
			if soil then
				addBed(soil)
			end
		end
	end
	city.DescendantAdded:Connect(function(descendant)
		if descendant.Name == "Soil" then
			task.defer(addBed, descendant)
		end
	end)
	local model = Instance.new("Model")
	model.Name = "Butterflies"
	model.Parent = folder
	for i = 1, BUTTERFLY_COUNT do
		local color = BUTTERFLY_COLORS[(i - 1) % #BUTTERFLY_COLORS + 1]
		table.insert(butterflies, {
			body = piece(model, "Body", Vector3.new(0.16, 0.16, 0.75), Color3.fromRGB(45, 40, 40)),
			wingL = piece(model, "WingL", Vector3.new(1, 0.05, 0.85), color),
			wingR = piece(model, "WingR", Vector3.new(1, 0.05, 0.85), color),
			bed = nil,
			phase = rng:NextNumber(0, 50),
			speed = rng:NextNumber(0.8, 1.2),
			last = Vector3.zero,
			yaw = 0,
			hidden = true,
		})
	end
end

-- Gives every butterfly a nearby flower bed: one each first, then a second on the nearest.
local function daylight(): number
	local dayNight = controllers.DayNight
	return if dayNight and dayNight.daylight then dayNight.daylight() else 1
end

local function assignButterflies(cameraPosition: Vector3)
	local near: { BasePart } = {}
	local distances: { [BasePart]: number } = {}
	local awake = daylight() > 0.5 -- butterflies sleep at night
	local index = 1
	while index <= #beds do
		local soil = beds[index]
		if not soil.Parent then
			bedSet[soil] = nil
			beds[index] = beds[#beds]
			beds[#beds] = nil
		else
			local distance = (soil.Position - cameraPosition).Magnitude
			if awake and distance < BUTTERFLY_RANGE then
				table.insert(near, soil)
				distances[soil] = distance
			end
			index += 1
		end
	end
	table.sort(near, function(a, b)
		return distances[a] < distances[b]
	end)
	local load: { [BasePart]: number } = {}
	for _, b in butterflies do
		local bed = b.bed
		if bed and distances[bed] then
			load[bed] = (load[bed] or 0) + 1
		else
			b.bed = nil
		end
	end
	for capacity = 1, 2 do
		for _, b in butterflies do
			if b.bed then
				continue
			end
			for _, soil in near do
				if (load[soil] or 0) < capacity then
					b.bed = soil
					load[soil] = (load[soil] or 0) + 1
					b.last = soil.Position
					break
				end
			end
		end
	end
end

local function updateButterflies()
	for _, b in butterflies do
		local soil = b.bed
		if not soil then
			if not b.hidden then
				b.hidden = true
				add(b.body, HIDDEN)
				add(b.wingL, HIDDEN)
				add(b.wingR, HIDDEN)
			end
			continue
		end
		b.hidden = false
		local t = clock * b.speed + b.phase
		local half = soil.Size.X * 0.5
		local localPosition = Vector3.new(
			math.sin(t * 0.6) * half * 0.85,
			2.2 + math.sin(t * 1.7) * 0.6 + math.sin(t * 3.1) * 0.2,
			math.sin(t * 0.9 + 1) * 1.8
		)
		local position = soil.CFrame:PointToWorldSpace(localPosition)
		local move = position - b.last
		b.last = position
		if move.Magnitude > 0.001 then
			b.yaw = math.atan2(-move.X, -move.Z)
		end
		local cf = CFrame.new(position) * CFrame.Angles(0, b.yaw, 0)
		local flap = 0.25 + math.abs(math.sin(clock * 16 + b.phase)) * 1.1
		add(b.body, cf)
		add(b.wingL, cf * CFrame.Angles(0, 0, -flap) * CFrame.new(-0.5, 0, 0))
		add(b.wingR, cf * CFrame.Angles(0, 0, flap) * CFrame.new(0.5, 0, 0))
	end
end

----- Street performers -----
type Balloon = { ball: BasePart, line: BasePart, offset: Vector3, phase: number, length: number }
local busker: NpcRig.Rig? = nil
local guitar: { body: BasePart, hole: BasePart, neck: BasePart, headstock: BasePart }? = nil
local buskerSound: Sound? = nil
local seller: NpcRig.Rig? = nil
local sellerFacing = Vector3.zero
local balloons: { Balloon } = {}
local birdsong: { Sound } = {}

local function buildBusker()
	local feet = walkable(BUSKER_SPOT.X, BUSKER_SPOT.Y)
	if not feet then
		return
	end
	local model = Instance.new("Model")
	model.Name = "Busker"
	model.Parent = folder
	local rig = NpcRig.new(model, Random.new(11), { shirt = Color3.fromRGB(235, 95, 70), pants = Color3.fromRGB(55, 65, 95), hat = Color3.fromRGB(45, 45, 50) }, feet)
	rig:face(Vector3.new(SPAWN_POINT.X, feet.Y, SPAWN_POINT.Z))
	rig.working = true -- head-bob to the beat
	busker = rig
	local parts = {
		body = piece(model, "GuitarBody", Vector3.new(1.5, 1.9, 0.45), Color3.fromRGB(205, 130, 60)),
		hole = piece(model, "GuitarHole", Vector3.new(0.08, 0.6, 0.6), Color3.fromRGB(60, 35, 20), Enum.PartType.Cylinder),
		neck = piece(model, "GuitarNeck", Vector3.new(0.3, 2.3, 0.22), Color3.fromRGB(95, 60, 35)),
		headstock = piece(model, "GuitarHead", Vector3.new(0.42, 0.5, 0.24), Color3.fromRGB(60, 40, 25)),
	}
	guitar = parts
	local sound = Instance.new("Sound")
	sound.Name = "BuskerSong"
	sound.SoundId = BUSKER_SONG
	sound.Looped = true
	sound.Volume = 0.45
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = 75
	sound.Parent = parts.body
	buskerSound = sound
	-- Upturned hat for tips, with a few coins in it.
	local forward = Vector3.new(SPAWN_POINT.X - feet.X, 0, SPAWN_POINT.Z - feet.Z).Unit
	local hatAt = feet + forward * 2.6
	local dark = Color3.fromRGB(40, 40, 46)
	Props.cylinder(model, "TipHatBrim", 0.08, 2.1, hatAt + Vector3.new(0, 0.04, 0), dark, { collide = false, shadow = false })
	Props.cylinder(model, "TipHat", 0.7, 1.4, hatAt + Vector3.new(0, 0.38, 0), dark, { collide = false, shadow = false })
	Props.cylinder(model, "TipHatBand", 0.18, 1.46, hatAt + Vector3.new(0, 0.18, 0), Color3.fromRGB(220, 60, 70), { collide = false, shadow = false })
	for i = 1, 3 do
		local a = i * 2.1
		Props.cylinder(model, "Coin", 0.08, 0.36, hatAt + Vector3.new(math.cos(a) * 0.3, 0.76, math.sin(a) * 0.3), Color3.fromRGB(255, 205, 50), { collide = false, shadow = false })
	end
end

local function buildSeller()
	local feet = walkable(SELLER_SPOT.X, SELLER_SPOT.Y)
	if not feet then
		return
	end
	local model = Instance.new("Model")
	model.Name = "BalloonSeller"
	model.Parent = folder
	local rig = NpcRig.new(model, Random.new(23), { shirt = Color3.fromRGB(250, 205, 60), pants = Color3.fromRGB(70, 120, 200), hat = Color3.fromRGB(230, 60, 80) }, feet)
	sellerFacing = Vector3.new(SPAWN_POINT.X, feet.Y, SPAWN_POINT.Z)
	rig:face(sellerFacing)
	seller = rig
	local colors = {
		Color3.fromRGB(240, 60, 70), Color3.fromRGB(60, 150, 245), Color3.fromRGB(255, 210, 50),
		Color3.fromRGB(80, 205, 100), Color3.fromRGB(255, 120, 200), Color3.fromRGB(170, 100, 245),
	}
	for i, color in colors do
		local angle = i * math.pi / 3
		local spread = 0.9 + (i % 2) * 0.6
		local offset = Vector3.new(math.cos(angle) * spread, 4.2 + (i % 3) * 0.7, math.sin(angle) * spread)
		local ball = piece(model, "Balloon", Vector3.one * 1.8, color, Enum.PartType.Ball)
		ball.Reflectance = 0.12
		local length = math.max(0.5, offset.Magnitude - 0.9)
		table.insert(balloons, {
			ball = ball,
			line = piece(model, "String", Vector3.new(0.05, 0.05, length), Color3.fromRGB(245, 245, 245)),
			offset = offset,
			phase = rng:NextNumber(0, math.pi * 2),
			length = length,
		})
	end
end

-- Replaces the arm poses NpcRig just queued (between `first` and the end of the batch).
local function setArm(rig: NpcRig.Rig, first: number, name: string, cf: CFrame)
	local part = rig.parts[name]
	for index = first, #batchParts do
		if batchParts[index] == part then
			batchFrames[index] = cf
			return
		end
	end
end

local function updatePerformers(dt: number, cameraPosition: Vector3, root: BasePart?)
	local b = busker
	local g = guitar
	if b and g and (b.position - cameraPosition).Magnitude < PERFORMER_RANGE then
		local first = #batchParts + 1
		b:collect(dt, batchParts, batchFrames)
		local body = batchFrames[first]
		setArm(b, first, "LeftArm", body * CFrame.new(-1.5, 1, 0) * CFrame.Angles(0.9, 0, 0.25) * CFrame.new(0, -1, 0))
		setArm(b, first, "RightArm", body * CFrame.new(1.5, 1, 0) * CFrame.Angles(0.55 + math.sin(clock * 12) * 0.18, 0, -0.45) * CFrame.new(0, -1, 0))
		local guitarCf = body * CFrame.new(0.15, -0.35, -0.9) * CFrame.Angles(0, 0, math.rad(70))
		add(g.body, guitarCf)
		add(g.hole, guitarCf * CFrame.new(0, 0.15, -0.22) * CFrame.Angles(0, math.pi / 2, 0))
		add(g.neck, guitarCf * CFrame.new(0, 2.0, 0))
		add(g.headstock, guitarCf * CFrame.new(0, 3.35, 0))
	end
	local s = seller
	if s and (s.position - cameraPosition).Magnitude < PERFORMER_RANGE then
		-- Turns to watch you when you come close.
		if root and (root.Position - s.position).Magnitude < 22 then
			s:face(Vector3.new(root.Position.X, s.position.Y, root.Position.Z))
		else
			s:face(sellerFacing)
		end
		local first = #batchParts + 1
		s:collect(dt, batchParts, batchFrames)
		local body = batchFrames[first]
		local arm = body * CFrame.new(1.5, 1, 0) * CFrame.Angles(2.6, 0, -0.2)
		setArm(s, first, "RightArm", arm * CFrame.new(0, -1, 0))
		local hand = (arm * CFrame.new(0, -2, 0)).Position
		for _, balloon in balloons do
			local sway = Vector3.new(math.sin(clock * 1.1 + balloon.phase) * 0.35, math.sin(clock * 1.6 + balloon.phase) * 0.12, math.cos(clock * 0.9 + balloon.phase) * 0.35)
			local center = hand + balloon.offset + sway
			add(balloon.ball, CFrame.new(center))
			local direction = (center - hand).Unit
			local middle = hand + direction * (balloon.length / 2)
			add(balloon.line, CFrame.lookAt(middle, middle + direction))
		end
	end
end

local function spawnNote(head: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Note"
	gui.Size = UDim2.fromOffset(34, 34)
	gui.LightInfluence = 0
	gui.MaxDistance = 90
	gui.Adornee = head
	local start = Vector3.new(rng:NextNumber(-1.5, 1.5), 1.6, 0)
	gui.StudsOffsetWorldSpace = start
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = NOTES[rng:NextInteger(1, #NOTES)]
	label.TextColor3 = NOTE_COLORS[rng:NextInteger(1, #NOTE_COLORS)]
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(24, 30, 34)
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = folder
	local info = TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffsetWorldSpace = start + Vector3.new(rng:NextNumber(-1, 1), 3.5, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, Rotation = rng:NextNumber(-25, 25) }):Play()
	TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	Debris:AddItem(gui, 2.1)
end

local function buildBirdsong(city: Instance)
	local blocks = city:FindFirstChild("Blocks")
	if not blocks then
		return
	end
	for _, block in blocks:GetChildren() do
		if block:IsA("Model") and block.Name:match("park$") then
			local cf = block:GetBoundingBox()
			local emitter = Props.part(folder, "Birdsong", Vector3.one, CFrame.new(cf.Position.X, 10, cf.Position.Z), Color3.new(1, 1, 1), { transparency = 1, collide = false, shadow = false })
			local sound = Instance.new("Sound")
			sound.Name = "Birdsong"
			sound.SoundId = BIRDSONG
			sound.Looped = true
			sound.Volume = 0.5
			sound.RollOffMode = Enum.RollOffMode.InverseTapered
			sound.RollOffMinDistance = 25
			sound.RollOffMaxDistance = 140
			sound.Parent = emitter
			table.insert(birdsong, sound)
		end
	end
end

----- Sounds + visibility -----
local function setPlaying(sound: Sound, on: boolean)
	if on and not sound.IsPlaying then
		sound:Play()
	elseif not on and sound.IsPlaying then
		sound:Stop()
	end
end

local function refreshSounds()
	local s = settings()
	local sfx = not (s and s.sfx == false)
	local music = not (s and s.music == false)
	for _, sound in birdsong do
		setPlaying(sound, visible and sfx)
	end
	if buskerSound then
		setPlaying(buskerSound, visible and music)
	end
end

local function setVisible(show: boolean)
	visible = show
	if not show then
		refreshSounds()
		folder.Parent = nil
	else
		folder.Parent = Workspace
		refreshSounds()
	end
end

local assignTimer = 0

local function update(dt: number)
	local show = shouldShow()
	if show ~= visible then
		setVisible(show)
	end
	if not visible then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	clock += dt
	local cameraPosition = camera.CFrame.Position
	local root = rootPart()
	table.clear(batchParts)
	table.clear(batchFrames)
	updateFlocks(dt, cameraPosition)
	updatePigeons(dt, cameraPosition, root)
	assignTimer -= dt
	if assignTimer <= 0 then
		assignTimer = 1.5
		assignButterflies(cameraPosition)
		local light = daylight()
		for _, sound in birdsong do
			sound.Volume = 0.5 * (0.15 + 0.85 * light) -- birds quieten down at night
		end
	end
	updateButterflies()
	updatePerformers(dt, cameraPosition, root)
	if #batchParts > 0 then
		Workspace:BulkMoveTo(batchParts, batchFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

----- Chatter -----
local greeted: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any
local lastGreeting = 0

local function walkerList(): { any }?
	local ambient = controllers.Ambient
	if ambient and ambient.walkerList then
		return ambient.walkerList()
	end
	return nil
end

-- A random pedestrian on screen says something that fits what they are doing.
local function chatterLoop()
	while true do
		task.wait(rng:NextNumber(1.6, 3))
		local list = walkerList()
		local camera = Workspace.CurrentCamera
		if not visible or not list or #list == 0 or not camera then
			continue
		end
		local cameraPosition = camera.CFrame.Position
		for _ = 1, 8 do
			local walker = list[rng:NextInteger(1, #list)]
			if walker.shown and walker.state ~= "inside" then
				local head = walker.rig.parts.Head
				if head and (head.Position - cameraPosition).Magnitude < 65 and onScreen(camera, head.Position) and not head:FindFirstChild("SpeechBubble") then
					local pool = CHATTER
					if walker.state == "shopping" or walker.state == "entering" then
						pool = SHOPPING_LINES
					elseif walker.state == "leaving" then
						pool = LEAVING_LINES
					end
					Bubble.say(head, pick(pool), 2.8)
					break
				end
			end
		end
	end
end

-- Pedestrians who pass close by say hello (each one only every so often).
local function greetLoop()
	while true do
		task.wait(0.4)
		local list = walkerList()
		local root = rootPart()
		local now = os.clock()
		if not visible or not list or not root or now - lastGreeting < 4 then
			continue
		end
		for _, walker in list do
			if not walker.shown or walker.state == "inside" then
				continue
			end
			local rig = walker.rig
			local offset = rig.position - root.Position
			if Vector2.new(offset.X, offset.Z).Magnitude < 8 and math.abs(offset.Y + 3) < 6 then
				local last = greeted[rig]
				if last == nil or now - last > 40 then
					greeted[rig] = now
					if rng:NextNumber() < 0.6 then
						Bubble.say(rig.parts.Head, pick(if ownsAnything() then OWNER_GREETINGS else GREETINGS), 2.4)
						lastGreeting = now
						break
					end
				end
			end
		end
	end
end

-- Floating music notes over the busker and the odd line from both performers.
local function performerLoop()
	local lineTimer = 4
	while true do
		task.wait(0.8)
		local camera = Workspace.CurrentCamera
		if not visible or not camera then
			continue
		end
		local cameraPosition = camera.CFrame.Position
		local b = busker
		if b and (b.position - cameraPosition).Magnitude < 90 then
			spawnNote(b.parts.Head)
		end
		lineTimer -= 0.8
		if lineTimer <= 0 then
			lineTimer = rng:NextNumber(6, 10)
			local root = rootPart()
			if root then
				local s = seller
				if s and (s.position - root.Position).Magnitude < 45 then
					Bubble.say(s.parts.Head, pick(SELLER_LINES), 3)
				end
				if b and (b.position - root.Position).Magnitude < 30 and rng:NextNumber() < 0.5 then
					Bubble.say(b.parts.Head, pick(BUSKER_LINES), 2.6)
				end
			end
		end
	end
end

----- Public -----
-- Studs from the camera to the busker (math.huge when he is silent), so the
-- SoundController can turn the background music down while you listen to him.
function LifeController.buskerDistance(): number
	local b = busker
	local camera = Workspace.CurrentCamera
	if not b or not camera or not visible or not (buskerSound and buskerSound.IsPlaying) then
		return math.huge
	end
	return (b.position - camera.CFrame.Position).Magnitude
end

function LifeController.init(registry: any)
	controllers = registry
end

function LifeController.start()
	folder = Instance.new("Folder")
	folder.Name = "CityLife"
	folder.Parent = Workspace
	local city = Workspace:WaitForChild("City", 30)
	if not city then
		warn("[LifeController] Workspace.City not found")
		return
	end
	buildFlocks()
	buildPigeons(city)
	buildButterflies(city)
	buildBusker()
	buildSeller()
	buildBirdsong(city)
	refreshSounds()
	controllers.Store.onChange(function()
		refreshSounds()
	end)
	RunService.Heartbeat:Connect(update)
	task.spawn(chatterLoop)
	task.spawn(greetLoop)
	task.spawn(performerLoop)
end

return LifeController
