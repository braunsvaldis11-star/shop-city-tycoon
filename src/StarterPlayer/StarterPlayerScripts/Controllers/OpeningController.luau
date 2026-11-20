--!strict
-- OpeningController (client): the "Grand Opening" cinematic that plays when a
-- business becomes yours. The camera swoops to the shop front, a crowd gathers and
-- claps, the red ribbon is cut, confetti and fireworks go off and a big banner says
-- the shop is open. Purely cosmetic: it only reads the synced state.
-- Container: StarterPlayerScripts.Controllers

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Businesses = require(Shared.Businesses)
local Client = ReplicatedStorage:WaitForChild("Client")
local NpcRig = require(Client:WaitForChild("NpcRig"))
local Bubble = require(Client:WaitForChild("Bubble"))
local UIKit = require(Client:WaitForChild("UIKit"))

local OpeningController = {}

local player = Players.LocalPlayer
local controllers: any
local owned: { [string]: boolean }? = nil
local queue: { string } = {}
local playing = false
local skipRequested = false
-- Tears down the scene that is playing right now (used if the cinematic errors).
local abortScene: (() -> ())? = nil

local RED = Color3.fromRGB(225, 35, 50)
local GOLD = Color3.fromRGB(255, 200, 60)
local CONFETTI = {
	Color3.fromRGB(255, 80, 90), Color3.fromRGB(255, 200, 40), Color3.fromRGB(80, 200, 255),
	Color3.fromRGB(120, 230, 110), Color3.fromRGB(200, 110, 255), Color3.fromRGB(255, 140, 60),
}
local CHEERS = { "Yay!", "\u{1F389}", "Congrats!", "Woohoo!", "I'll be your first customer!", "\u{1F44F}\u{1F44F}", "So exciting!", "Finally open!" }

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

----- Effects -----
local function confettiRain(parent: Instance, origin: Vector3, spread: Vector3, count: number)
	for _ = 1, count do
		local piece = Instance.new("Part")
		piece.Name = "Confetti"
		piece.Size = Vector3.new(0.45, 0.06, 0.3)
		piece.Color = CONFETTI[math.random(1, #CONFETTI)]
		piece.Material = Enum.Material.SmoothPlastic
		piece.CanQuery = false
		piece.CanTouch = false
		piece.CastShadow = false
		piece.CFrame = CFrame.new(origin + Vector3.new((math.random() - 0.5) * spread.X, math.random() * spread.Y, (math.random() - 0.5) * spread.Z))
			* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		piece.AssemblyLinearVelocity = Vector3.new((math.random() - 0.5) * 30, math.random(18, 34), (math.random() - 0.5) * 30)
		piece.AssemblyAngularVelocity = Vector3.new(math.random(-12, 12), math.random(-12, 12), math.random(-12, 12))
		piece.Parent = parent
		Debris:AddItem(piece, 7 + math.random() * 2)
	end
end

local function firework(parent: Instance, from: Vector3, height: number, color: Color3)
	local rocket = part(parent, "Rocket", Vector3.new(0.6, 0.6, 0.6), CFrame.new(from), color, Enum.Material.Neon)
	rocket.Shape = Enum.PartType.Ball
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.3, 0)
	a0.Parent = rocket
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.3, 0)
	a1.Parent = rocket
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 230, 160), color)
	trail.Lifetime = 0.4
	trail.LightEmission = 1
	trail.Transparency = NumberSequence.new(0, 1)
	trail.Parent = rocket
	local top = from + Vector3.new((math.random() - 0.5) * 8, height, (math.random() - 0.5) * 8)
	local rise = TweenService:Create(rocket, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(top) })
	rise:Play()
	rise.Completed:Once(function()
		rocket.Transparency = 1
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
		emitter.Lifetime = NumberRange.new(0.9, 1.4)
		emitter.Speed = NumberRange.new(18, 26)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Drag = 2.5
		emitter.Acceleration = Vector3.new(0, -6, 0)
		emitter.Rate = 0
		emitter.Parent = rocket
		emitter:Emit(90)
		local flash = Instance.new("PointLight")
		flash.Color = color
		flash.Range = 40
		flash.Brightness = 4
		flash.Parent = rocket
		TweenService:Create(flash, TweenInfo.new(0.8), { Brightness = 0 }):Play()
		if controllers.Sound then
			controllers.Sound.play("Firework", 0.35)
		end
		Debris:AddItem(rocket, 2)
	end)
end

----- Banner -----
local function banner(definition: any): (ScreenGui, () -> ())
	local gui = Instance.new("ScreenGui")
	gui.Name = "GrandOpening"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 40
	gui.Parent = player:WaitForChild("PlayerGui")

	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0.1, 0)
	holder.Size = UDim2.fromOffset(640, 190)
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = holder
	local camera = Workspace.CurrentCamera
	local fit = if camera then math.clamp(camera.ViewportSize.X / 900, 0.55, 1.15) else 1

	local burst = Instance.new("ImageLabel")
	burst.BackgroundTransparency = 1
	burst.Image = "rbxassetid://130563114903838"
	burst.ImageColor3 = Color3.fromRGB(255, 225, 120)
	burst.ImageTransparency = 0.25
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.45)
	burst.Size = UDim2.fromOffset(620, 620)
	burst.ZIndex = 0
	burst.Parent = holder

	local panel = UIKit.panel({
		Name = "Ribbon",
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(600, 112),
		Parent = holder,
	})
	UIKit.gradient(Color3.fromRGB(255, 70, 90), Color3.fromRGB(210, 20, 45)).Parent = panel
	local checker = Instance.new("ImageLabel")
	checker.BackgroundTransparency = 1
	checker.Image = UIKit.CHECKER
	checker.ImageColor3 = Color3.new(0, 0, 0)
	checker.ImageTransparency = 0.88
	checker.ScaleType = Enum.ScaleType.Tile
	checker.TileSize = UDim2.fromOffset(24, 24)
	checker.Size = UDim2.fromScale(1, 1)
	checker.Parent = panel
	UIKit.corner(8).Parent = checker
	UIKit.label({ Text = "\u{1F389} GRAND OPENING! \u{1F389}", Size = UDim2.new(1, -24, 0, 66), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 58, Parent = panel })
	UIKit.label({
		Text = definition.emoji .. " " .. definition.name .. " is open for business!",
		Font = UIKit.BodyFont, Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 72),
		TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.fromRGB(255, 240, 160), MaxTextSize = 26, Parent = panel,
	})
	local tip = UIKit.label({
		Text = "Walk in, hire staff and upgrade to earn more!",
		Font = UIKit.BodyFont, Size = UDim2.new(1, -24, 0, 26), Position = UDim2.fromOffset(12, 126),
		TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 22, Parent = holder,
	})
	local _ = tip

	local skip = UIKit.button({
		Name = "Skip", Text = "Skip \u{25B6}", Color = UIKit.Colors.Grey,
		Size = UDim2.fromOffset(120, 44), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -24),
		MaxTextSize = 22, Parent = gui,
	}, function()
		skipRequested = true
	end)
	local _ = skip

	TweenService:Create(scale, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fit }):Play()
	local spin = RunService.RenderStepped:Connect(function(dt)
		burst.Rotation = (burst.Rotation + dt * 25) % 360
	end)
	local function close()
		spin:Disconnect()
		local out = TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
		out:Play()
		task.delay(0.35, function()
			gui:Destroy()
		end)
	end
	return gui, close
end

----- Cinematic -----
local function waitOrSkip(seconds: number)
	local deadline = os.clock() + seconds
	while os.clock() < deadline and not skipRequested do
		task.wait()
	end
end

-- Never waits: if there is no PlayerModule (custom or not loaded yet) we simply don't
-- freeze the player. Waiting for it here used to stall the whole ceremony forever,
-- leaving the crowd standing at the door.
local function controls(): any
	local scripts = player:FindFirstChild("PlayerScripts")
	local moduleScript = scripts and scripts:FindFirstChild("PlayerModule")
	if not (moduleScript and moduleScript:IsA("ModuleScript")) then
		return nil
	end
	local ok, result = pcall(function()
		local module = require(moduleScript :: ModuleScript) :: any
		return if type(module) == "table" and module.GetControls then module:GetControls() else nil
	end)
	return if ok then result else nil
end

local function play(businessId: string)
	local definition = Businesses.get(businessId)
	local city = Workspace:FindFirstChild("City")
	local lots = city and city:FindFirstChild("Businesses")
	local lot = lots and lots:FindFirstChild(businessId)
	if not definition then
		return
	end
	skipRequested = false
	if controllers.UI and controllers.UI.close then
		pcall(controllers.UI.close)
	end
	local door = lot and lot:FindFirstChild("Door") :: BasePart?
	local exitSpot = lot and lot:FindFirstChild("ExitSpot") :: BasePart?
	local isInside = controllers.Interior and controllers.Interior.isInside()
	if not door or not exitSpot or isInside then
		-- No street scene available: just the banner and a cheer.
		controllers.Sound.play("LevelUp", 0.6)
		local _, close = banner(definition)
		waitOrSkip(3.5)
		close()
		return
	end

	local camera = Workspace.CurrentCamera
	local folder = Instance.new("Folder")
	folder.Name = "GrandOpeningFx"
	folder.Parent = Workspace
	Debris:AddItem(folder, 60) -- last-resort cleanup, whatever happens below

	local outward = (exitSpot.Position - door.Position) * Vector3.new(1, 0, 1)
	outward = if outward.Magnitude > 0.1 then outward.Unit else Vector3.new(0, 0, -1)
	local right = outward:Cross(Vector3.yAxis)
	local base = door.Position - Vector3.new(0, door.Size.Y / 2, 0)
	local ribbonCenter = base + outward * 2.6
	-- Faces the street, so a part's X size runs across the doorway.
	local function frame(at: Vector3): CFrame
		return CFrame.lookAt(at, at + outward)
	end

	-- Stanchions + ribbon + bow
	local half = door.Size.X / 2 + 1.6
	for _, side in { -1, 1 } do
		local at = ribbonCenter + right * side * half
		part(folder, "Stanchion", Vector3.new(0.5, 4.2, 0.5), CFrame.new(at + Vector3.new(0, 2.1, 0)), GOLD, Enum.Material.Foil)
		part(folder, "StanchionBase", Vector3.new(1.4, 0.3, 1.4), CFrame.new(at + Vector3.new(0, 0.15, 0)), GOLD, Enum.Material.Foil)
		local knob = part(folder, "Knob", Vector3.new(0.8, 0.8, 0.8), CFrame.new(at + Vector3.new(0, 4.4, 0)), GOLD, Enum.Material.Foil)
		knob.Shape = Enum.PartType.Ball
	end
	local ribbonY = Vector3.new(0, 3.7, 0)
	local halves = {}
	for _, side in { -1, 1 } do
		local piece = part(folder, "Ribbon", Vector3.new(half, 0.7, 0.12), frame(ribbonCenter + ribbonY + right * side * half / 2), RED)
		table.insert(halves, { piece = piece, side = side })
	end
	local bowParts = {}
	for _, side in { -1, 1 } do
		local loop = part(folder, "Bow", Vector3.new(1.4, 1.1, 0.3), frame(ribbonCenter + ribbonY + right * side * 0.75) * CFrame.Angles(0, 0, math.rad(side * 25)), RED)
		table.insert(bowParts, loop)
	end
	local knot = part(folder, "Knot", Vector3.new(0.6, 0.6, 0.6), CFrame.new(ribbonCenter + ribbonY), Color3.fromRGB(180, 20, 35))
	knot.Shape = Enum.PartType.Ball
	table.insert(bowParts, knot)

	-- Crowd
	local rng = Random.new()
	local crowd: { NpcRig.Rig } = {}
	for i = 1, 8 do
		local across = (i - 4.5) * 2.6 + rng:NextNumber(-0.5, 0.5)
		local back = 9 + math.abs(across) * 0.35 + rng:NextNumber(0, 2)
		local position = base + outward * back + right * across
		local rig = NpcRig.new(folder, rng, nil, position)
		rig:face(base + outward * 2)
		rig.phase = rng:NextNumber(0, 6)
		table.insert(crowd, rig)
	end
	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	local leaving = false
	local crowdLoop = RunService.Heartbeat:Connect(function(dt)
		table.clear(parts)
		table.clear(frames)
		for _, rig in crowd do
			if leaving then
				rig:step(dt)
			end
			rig:collect(dt, parts, frames)
		end
		NpcRig.flush(parts, frames)
	end)
	local orbiting: RBXScriptConnection? = nil
	local finished = false
	-- Removes everything the ceremony made. Safe to call more than once.
	local function finish()
		if finished then
			return
		end
		finished = true
		crowdLoop:Disconnect()
		if orbiting then
			orbiting:Disconnect()
			orbiting = nil
		end
		folder:Destroy()
	end
	abortScene = finish
	task.delay(45, finish) -- failsafe: the crowd never stays longer than this

	-- Camera
	local controlModule = controls()
	if controlModule then
		pcall(function()
			controlModule:Disable()
		end)
	end
	local oldType = camera.CameraType
	local oldCFrame = camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	local focus = base + Vector3.new(0, 6, 0)
	local radius, height = 30, 11
	local function orbit(angle: number): CFrame
		local dir = (outward * math.cos(angle) + right * math.sin(angle))
		return CFrame.lookAt(focus + dir * radius + Vector3.new(0, height, 0), focus)
	end
	local swoop = TweenService:Create(camera, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = orbit(math.rad(-22)) })
	swoop:Play()
	controllers.Sound.play("Whoosh", 0.5)
	waitOrSkip(1.15)

	-- Slow orbit for the rest of the show.
	local angle = math.rad(-22)
	orbiting = RunService.RenderStepped:Connect(function(dt)
		angle = math.min(math.rad(22), angle + dt * math.rad(9))
		radius = math.max(22, radius - dt * 1.6)
		camera.CFrame = orbit(angle)
	end)

	-- Crowd claps in anticipation
	for _, rig in crowd do
		rig.working = true
	end
	if not skipRequested then
		Bubble.say(crowd[2].parts.Head, "Cut the ribbon!", 1.6)
	end
	waitOrSkip(0.9)

	-- Snip!
	controllers.Sound.play("Click", 0.8)
	for _, h in halves do
		-- Each half drops to the pavement and curls a little.
		local landed = frame(ribbonCenter + right * h.side * (half / 2 + 0.6) + outward * 0.8 + Vector3.new(0, 0.12, 0))
			* CFrame.Angles(math.rad(90), math.rad(h.side * 12), 0)
		TweenService:Create(h.piece, TweenInfo.new(0.8, Enum.EasingStyle.Bounce), { CFrame = landed }):Play()
	end
	for _, bow in bowParts do
		bow.Anchored = false
		bow.CanCollide = true
		bow.AssemblyLinearVelocity = outward * 8 + Vector3.new(0, 12, 0)
	end
	controllers.Sound.play("LevelUp", 0.6)
	controllers.Sound.play("Cheer", 0.5)
	local _, closeBanner = banner(definition)
	confettiRain(folder, base + Vector3.new(0, 11, 0) + outward * 3, Vector3.new(16, 3, 6), 70)
	local colors = { CONFETTI[1], CONFETTI[2], CONFETTI[3], CONFETTI[5] }
	for i, side in { -1, 1, -1, 1 } do
		task.delay(0.15 + i * 0.35, function()
			if folder.Parent then
				firework(folder, base + right * side * (10 + i * 2) - outward * 2, 24 + i * 4, colors[i])
			end
		end)
	end
	for i, rig in crowd do
		if i % 2 == 1 then
			task.delay(rng:NextNumber(0, 0.8), function()
				if rig.model.Parent and not skipRequested then
					Bubble.say(rig.parts.Head, CHEERS[rng:NextInteger(1, #CHEERS)], 2.2)
				end
			end)
		end
	end
	waitOrSkip(3.6)

	-- Back to the player
	if orbiting then
		orbiting:Disconnect()
		orbiting = nil
	end
	closeBanner()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local home = oldCFrame
	if root then
		local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		if look.Magnitude > 0.01 then
			home = CFrame.lookAt(root.Position - look.Unit * 14 + Vector3.new(0, 6, 0), root.Position + look.Unit * 4)
		end
	end
	local back = TweenService:Create(camera, TweenInfo.new(if skipRequested then 0.35 else 0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = home })
	back:Play()
	back.Completed:Wait()
	camera.CameraType = if oldType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else oldType
	if controlModule then
		pcall(function()
			controlModule:Enable()
		end)
	end

	-- The ribbon and stanchions fade away...
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Confetti" and not d:FindFirstAncestorOfClass("Model") then
			TweenService:Create(d, TweenInfo.new(1.2), { Transparency = 1 }):Play()
		end
	end
	-- ...while the crowd turns around and walks off down the street.
	for _, rig in crowd do
		rig.working = false
		task.delay(rng:NextNumber(0, 0.7), function()
			if finished then
				return
			end
			local side = if (rig.position - base):Dot(right) >= 0 then 1 else -1
			local first = rig.position + outward * rng:NextNumber(2, 4) + right * side * rng:NextNumber(2, 4)
			local last = first + right * side * rng:NextNumber(26, 38)
			rig.speed = rng:NextNumber(7, 10)
			rig:setPath({ first, last })
			rig.moving = true
		end)
	end
	leaving = true
	-- Once they're down the street they fade out, then everything is removed.
	task.delay(4, function()
		if finished then
			return
		end
		for _, rig in crowd do
			for _, d in rig.model:GetDescendants() do
				if d:IsA("BasePart") or d:IsA("Decal") then
					TweenService:Create(d, TweenInfo.new(1), { Transparency = 1 }):Play()
				end
			end
		end
	end)
	task.delay(6, finish)
	abortScene = nil

	-- Point the way if the shop is far away.
	if root and (root.Position - door.Position).Magnitude > 80 and controllers.City and controllers.City.setWaypoint then
		pcall(controllers.City.setWaypoint, businessId)
	end
end

local function pump()
	if playing then
		return
	end
	playing = true
	while #queue > 0 do
		local id = table.remove(queue, 1) :: string
		local ok, err = pcall(play, id)
		if not ok then
			warn("[OpeningController] " .. tostring(err))
			local cleanup = abortScene
			abortScene = nil
			if cleanup then
				cleanup() -- never leave a frozen crowd behind
			end
			local camera = Workspace.CurrentCamera
			if camera and camera.CameraType == Enum.CameraType.Scriptable then
				camera.CameraType = Enum.CameraType.Custom
			end
			local controlModule = controls()
			if controlModule then
				pcall(function()
					controlModule:Enable()
				end)
			end
		end
	end
	playing = false
end

-- Plays the cinematic for a business (also used for previews/testing).
function OpeningController.celebrate(businessId: string)
	table.insert(queue, businessId)
	task.spawn(pump)
end

function OpeningController.init(registry: any)
	controllers = registry
end

function OpeningController.start()
	controllers.Store.onChange(function(state)
		local now: { [string]: boolean } = {}
		for id in state.businesses do
			now[id] = true
		end
		local before = owned
		owned = now
		if before == nil then
			return -- first snapshot: these were bought in an earlier session
		end
		for id in now do
			if not before[id] then
				OpeningController.celebrate(id)
			end
		end
	end)
end

return OpeningController
