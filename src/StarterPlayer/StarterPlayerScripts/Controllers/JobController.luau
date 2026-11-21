--!strict
-- JobController (client): the paper route starter job.
--  * A vendor at the News Stand shouts headlines; new players get a big "START HERE".
--  * The route from the server (state.job) becomes bouncing markers on mailboxes, a
--    guide beam to the nearest one and a "Throw Paper" prompt on each.
--  * Throwing plays an overhand arm swing and a spinning paper arc; the server checks
--    range and the route, then pays (PaperJob "delivered").
-- Container: StarterPlayerScripts.Controllers

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Client = ReplicatedStorage:WaitForChild("Client")
local NpcRig = require(Client:WaitForChild("NpcRig"))
local Bubble = require(Client:WaitForChild("Bubble"))
local UIKit = require(Client:WaitForChild("UIKit"))

local JobController = {}

local player = Players.LocalPlayer
local controllers: any

local JOB = Config.PaperJob
local PROMPT_RANGE = JOB.throwRange - 4
local YELLOW = Color3.fromRGB(255, 214, 40)
local PAPER = Color3.fromRGB(240, 238, 230)

local routeFolder: Instance? = nil
local mailboxFolder: Instance? = nil
local standGrab: BasePart? = nil
local vendor: NpcRig.Rig? = nil
local effects: Folder

type Marker = { name: string, box: BasePart, gui: BillboardGui, distance: TextLabel, highlight: Highlight, prompt: ProximityPrompt, attachment: Attachment }
local markers: { [string]: Marker } = {}
local routeKey = ""
local papers = 0
local standMarker: BillboardGui? = nil
local beam: Beam? = nil
local beamTarget: Attachment? = nil
local rootAttachment: Attachment? = nil
local chip: Frame? = nil
local chipText: TextLabel? = nil
local throwing = false

local VENDOR_LINES = {
	"Extra! Extra! Read all about it!",
	"Papers! Get your papers here!",
	"Need cash? Deliver papers!",
	"\u{1F4F0} Fresh news, hot off the press!",
	"Big news: the city is booming!",
}

----- Helpers -----
local function rootPart(): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function inside(): boolean
	return controllers.Interior ~= nil and controllers.Interior.isInside()
end

local function ownsAnything(): boolean
	local state = controllers.Store.state
	return state ~= nil and next(state.businesses) ~= nil
end

local function floatText(position: Vector3, text: string, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(180, 44)
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
	stroke.Thickness = 2.5
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = anchor
	anchor.Parent = effects
	TweenService:Create(anchor, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(position + Vector3.new(0, 5, 0)) }):Play()
	TweenService:Create(label, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	task.delay(1.4, function()
		anchor:Destroy()
	end)
end

local function burst(position: Vector3, colors: { Color3 }, count: number)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	local keys = {}
	for i, color in colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / math.max(1, #colors - 1), color))
	end
	emitter.Color = if #keys >= 2 then ColorSequence.new(keys) else ColorSequence.new(colors[1])
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -14, 0)
	emitter.LightEmission = 0.6
	emitter.Rate = 0
	emitter.Parent = anchor
	anchor.Parent = effects
	emitter:Emit(count)
	task.delay(1.2, function()
		anchor:Destroy()
	end)
end

----- Throw animation -----
local function shoulder(): (Motor6D?, (number) -> CFrame)
	local character = player.Character
	if not character then
		return nil, function(_)
			return CFrame.new()
		end
	end
	local upperArm = character:FindFirstChild("RightUpperArm")
	local r15 = upperArm and upperArm:FindFirstChild("RightShoulder")
	if r15 and r15:IsA("Motor6D") then
		return r15, function(a: number)
			return CFrame.Angles(a, 0, 0)
		end
	end
	local torso = character:FindFirstChild("Torso")
	local r6 = torso and torso:FindFirstChild("Right Shoulder")
	if r6 and r6:IsA("Motor6D") then
		return r6, function(a: number)
			return CFrame.Angles(0, 0, a)
		end
	end
	return nil, function(_)
		return CFrame.new()
	end
end

local function handPart(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart?
end

local function makePaper(): (BasePart, BasePart)
	local paper = Instance.new("Part")
	paper.Name = "FlyingPaper"
	paper.Shape = Enum.PartType.Cylinder
	paper.Size = Vector3.new(1.6, 0.55, 0.55)
	paper.Color = PAPER
	paper.Material = Enum.Material.SmoothPlastic
	paper.Anchored = true
	paper.CanCollide = false
	paper.CanQuery = false
	paper.CanTouch = false
	paper.CastShadow = false
	local band = paper:Clone()
	band.Name = "Band"
	band.Size = Vector3.new(0.3, 0.6, 0.6)
	band.Color = Color3.fromRGB(220, 50, 50)
	return paper, band
end

local function flyPaper(from: Vector3, box: BasePart, onLand: () -> ())
	local paper, band = makePaper()
	paper.Parent = effects
	band.Parent = effects
	local target = box.Position + Vector3.new(0, 0.4, 0)
	local distance = (target - from).Magnitude
	local height = 3 + distance * 0.18
	local duration = 0.3 + distance / 70
	local t = 0
	local spinAxis = math.random() * math.pi
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		t = math.min(1, t + dt / duration)
		local position = from:Lerp(target, t) + Vector3.new(0, 4 * height * t * (1 - t), 0)
		local cf = CFrame.new(position) * CFrame.Angles(t * 14, spinAxis, t * 3)
		paper.CFrame = cf
		band.CFrame = cf
		if t >= 1 then
			connection:Disconnect()
			paper:Destroy()
			band:Destroy()
			onLand()
		end
	end)
end

local function wiggleFlag(box: BasePart)
	local model = box.Parent
	local flag = model and model:FindFirstChild("Flag") :: BasePart?
	if not flag or flag:GetAttribute("Busy") then
		return
	end
	flag:SetAttribute("Busy", true)
	local home = flag.CFrame
	-- Hinge at the bottom of the flag: swing it down, then back up after a moment.
	local hinge = home * CFrame.new(0, -flag.Size.Y / 2, 0)
	local down = hinge * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.new(0, flag.Size.Y / 2, 0)
	TweenService:Create(flag, TweenInfo.new(0.25, Enum.EasingStyle.Back), { CFrame = down }):Play()
	task.delay(4, function()
		TweenService:Create(flag, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { CFrame = home }):Play()
		task.wait(0.45)
		flag:SetAttribute("Busy", nil)
	end)
end

local function throwAt(name: string)
	local marker = markers[name]
	local root = rootPart()
	if throwing or not marker or not root or papers <= 0 then
		return
	end
	throwing = true
	local box = marker.box
	-- Turn to face the mailbox.
	local flatTarget = Vector3.new(box.Position.X, root.Position.Y, box.Position.Z)
	if (flatTarget - root.Position).Magnitude > 0.5 then
		root.CFrame = CFrame.lookAt(root.Position, flatTarget)
	end
	local motor, rotate = shoulder()
	local base = if motor then motor.C0 else CFrame.new()
	local hand = handPart()
	local held: BasePart? = nil
	local heldBand: BasePart? = nil
	if hand then
		local p, b = makePaper()
		held, heldBand = p, b
		p.Parent = effects
		b.Parent = effects
	end
	controllers.Sound.play("Whoosh", 0.35)
	local released = false
	local t = 0
	local TOTAL = 0.55
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		t += dt
		local angle
		if t < 0.16 then
			local k = t / 0.16
			angle = 3.4 * (1 - (1 - k) ^ 2) -- wind up behind the head
		elseif t < 0.3 then
			local k = (t - 0.16) / 0.14
			angle = 3.4 + (1.0 - 3.4) * k * k -- fast overhand swing
		else
			local k = math.min(1, (t - 0.3) / 0.25)
			angle = 1.0 * (1 - k) ^ 2
		end
		if motor and motor.Parent then
			motor.C0 = base * rotate(angle)
		end
		if held and hand and hand.Parent then
			local cf = hand.CFrame * CFrame.new(0, -0.9, 0) * CFrame.Angles(0, 0, math.pi / 2)
			held.CFrame = cf
			;(heldBand :: BasePart).CFrame = cf
		end
		if not released and t >= 0.24 then
			released = true
			local from = if held then held.Position else root.Position + Vector3.new(0, 2, 0)
			if held then
				held:Destroy()
				;(heldBand :: BasePart):Destroy()
				held = nil
			end
			controllers.Store.send("PaperThrow", name)
			flyPaper(from, box, function()
				controllers.Sound.play("Click", 0.6)
				wiggleFlag(box)
				burst(box.Position + Vector3.new(0, 1, 0), { PAPER, YELLOW }, 14)
			end)
		end
		if t >= TOTAL then
			connection:Disconnect()
			if motor and motor.Parent then
				motor.C0 = base
			end
			if held then
				held:Destroy()
				;(heldBand :: BasePart):Destroy()
			end
			throwing = false
		end
	end)
end

----- Markers -----
local function clearMarkers()
	for _, marker in markers do
		marker.gui:Destroy()
		marker.highlight:Destroy()
		marker.prompt:Destroy()
		marker.attachment:Destroy()
	end
	table.clear(markers)
end

local function makeMarker(name: string): Marker?
	local model = mailboxFolder and mailboxFolder:FindFirstChild(name)
	local box = model and (model :: Model).PrimaryPart
	if not box then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "PaperMarker"
	gui.Adornee = box
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(70, 86)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 1000
	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundColor3 = YELLOW
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.fromScale(0.5, 0)
	icon.Size = UDim2.fromOffset(54, 54)
	icon.Font = Enum.Font.GothamBlack
	icon.Text = "\u{1F4F0}"
	icon.TextScaled = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = icon
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(24, 30, 34)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = icon
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = icon
	icon.Parent = gui
	local distance = Instance.new("TextLabel")
	distance.Name = "Distance"
	distance.BackgroundTransparency = 1
	distance.AnchorPoint = Vector2.new(0.5, 1)
	distance.Position = UDim2.fromScale(0.5, 1)
	distance.Size = UDim2.new(1, 0, 0, 26)
	distance.Font = Enum.Font.GothamBlack
	distance.TextScaled = true
	distance.TextColor3 = Color3.new(1, 1, 1)
	distance.Text = ""
	local dstroke = Instance.new("UIStroke")
	dstroke.Thickness = 2.5
	dstroke.Parent = distance
	distance.Parent = gui
	gui.Parent = effects

	local highlight = Instance.new("Highlight")
	highlight.Adornee = model
	highlight.FillColor = YELLOW
	highlight.FillTransparency = 0.55
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = effects

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ThrowPrompt"
	prompt.ActionText = "Throw Paper"
	prompt.ObjectText = "\u{1F4EB} Mailbox"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_RANGE
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = box
	prompt.Triggered:Connect(function()
		throwAt(name)
	end)

	local attachment = Instance.new("Attachment")
	attachment.Name = "PaperTarget"
	attachment.Position = Vector3.new(0, 1, 0)
	attachment.Parent = box
	return { name = name, box = box, gui = gui, distance = distance, highlight = highlight, prompt = prompt, attachment = attachment }
end

local function applyJob(job: any)
	local stops = if type(job) == "table" and type(job.stops) == "table" then job.stops else {}
	papers = if type(job) == "table" and type(job.papers) == "number" then job.papers else 0
	local key = table.concat(stops, ",")
	if key == routeKey then
		return
	end
	routeKey = key
	-- Keep markers that are still on the route (so their tweens don't restart).
	local wanted = {}
	for _, name in stops do
		wanted[name] = true
	end
	for name, marker in markers do
		if not wanted[name] then
			marker.gui:Destroy()
			marker.highlight:Destroy()
			marker.prompt:Destroy()
			marker.attachment:Destroy()
			markers[name] = nil
		end
	end
	for _, name in stops do
		if not markers[name] then
			local marker = makeMarker(name)
			if marker then
				markers[name] = marker
			end
		end
	end
end

----- Stand: vendor + start marker -----
local function buildStandMarker(stand: Instance)
	local grab = stand:FindFirstChild("GrabPoint") :: BasePart?
	if not grab then
		return
	end
	standGrab = grab
	local gui = Instance.new("BillboardGui")
	gui.Name = "StartHere"
	gui.Adornee = grab
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(230, 96)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 11, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 1000
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = gui
	local pill = UIKit.panel({
		Name = "Pill",
		BackgroundColor3 = Color3.fromRGB(46, 160, 105),
		Size = UDim2.new(1, 0, 0, 58),
		Parent = holder,
	})
	UIKit.label({ Text = "\u{1F4F0} START HERE", Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(8, 3), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 28, Parent = pill })
	UIKit.label({ Text = "Deliver papers for cash", Font = UIKit.BodyFont, Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 33), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 17, Parent = pill })
	UIKit.label({ Name = "Arrow", Text = "\u{25BC}", Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 60), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = YELLOW, MaxTextSize = 34, Parent = holder })
	gui.Parent = effects
	standMarker = gui
	-- Bounce
	task.spawn(function()
		while gui.Parent do
			local up = TweenService:Create(holder, TweenInfo.new(0.5, Enum.EasingStyle.Sine), { Position = UDim2.fromOffset(0, -8) })
			up:Play()
			up.Completed:Wait()
			local down = TweenService:Create(holder, TweenInfo.new(0.5, Enum.EasingStyle.Sine), { Position = UDim2.fromOffset(0, 0) })
			down:Play()
			down.Completed:Wait()
		end
	end)
end

local function spawnVendor(stand: Instance)
	local spot = stand:FindFirstChild("VendorSpot") :: BasePart?
	local grab = stand:FindFirstChild("GrabPoint") :: BasePart?
	if not spot or not grab then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "NewsVendor"
	folder.Parent = effects
	local rng = Random.new(7)
	local rig = NpcRig.new(folder, rng, { shirt = Color3.fromRGB(46, 160, 105), pants = Color3.fromRGB(60, 50, 45), hat = Color3.fromRGB(90, 70, 55) }, spot.Position - Vector3.new(0, spot.Size.Y / 2, 0))
	rig:face(rig.position + (grab.Position - spot.Position) * Vector3.new(1, 0, 1))
	vendor = rig
	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	local workTimer = 0
	RunService.Heartbeat:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		if not camera or inside() or (camera.CFrame.Position - rig.position).Magnitude > 250 then
			return
		end
		workTimer -= dt
		if workTimer <= 0 then
			workTimer = math.random(2, 5)
			rig.working = not rig.working
		end
		table.clear(parts)
		table.clear(frames)
		rig:collect(dt, parts, frames)
		NpcRig.flush(parts, frames)
	end)
	task.spawn(function()
		local index = 0
		while rig.model.Parent do
			task.wait(math.random(55, 90) / 10)
			local root = rootPart()
			if root and not inside() and (root.Position - rig.position).Magnitude < 70 then
				index = index % #VENDOR_LINES + 1
				local line = VENDOR_LINES[index]
				if papers == 0 and not ownsAnything() and index % 2 == 0 then
					line = "Hey kid! Want to earn some cash?"
				end
				Bubble.say(rig.parts.Head, line, 3)
			end
		end
	end)
end

----- HUD chip + guide beam -----
local function buildChip()
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("CityHUD", 10)
	local root = gui and gui:FindFirstChild("Root")
	if not root then
		return
	end
	local frame = UIKit.panel({
		Name = "PaperJob",
		Size = UDim2.fromOffset(400, 52),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -112),
		Visible = false,
		Parent = root,
	})
	chipText = UIKit.label({ Text = "", Size = UDim2.new(1, -20, 1, -12), Position = UDim2.fromOffset(10, 6), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 22, Parent = frame })
	chip = frame
end

local function ensureBeam(root: BasePart)
	if rootAttachment and rootAttachment.Parent == root then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "PaperGuide"
	attachment.Position = Vector3.new(0, -1.5, 0)
	attachment.Parent = root
	rootAttachment = attachment
	if not beam then
		local b = Instance.new("Beam")
		b.Name = "PaperGuideBeam"
		b.Color = ColorSequence.new(YELLOW)
		b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.5) })
		b.Width0 = 0.5
		b.Width1 = 0.5
		b.FaceCamera = true
		b.LightEmission = 0.6
		b.Segments = 1
		b.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		b.TextureMode = Enum.TextureMode.Static
		b.TextureLength = 3
		b.TextureSpeed = 1.5
		b.Parent = effects
		beam = b
	end
	local guide = beam :: Beam
	guide.Attachment0 = attachment
end

local standAttachment: Attachment? = nil

local function freeShopReady(): boolean
	local state = controllers.Store.state
	return state ~= nil and state.starterShop ~= nil
end

local function refresh()
	local root = rootPart()
	local isInside = inside()
	local freeReady = freeShopReady()
	-- Brand-new players are pointed at the News Stand; once a route is done the golden
	-- trail (CityController) leads to the first shop instead.
	local showStart = papers <= 0 and not ownsAnything() and not freeReady
	-- Stand marker
	if standMarker then
		standMarker.Enabled = showStart and not isInside
	end
	-- Markers + nearest
	local nearest: Marker? = nil
	local nearestDistance = math.huge
	for _, marker in markers do
		marker.gui.Enabled = not isInside
		if root then
			local d = (marker.box.Position - root.Position) * Vector3.new(1, 0, 1)
			local studs = d.Magnitude
			marker.distance.Text = if studs <= PROMPT_RANGE then "THROW!" else string.format("%dm", math.floor(studs / 3.5))
			if studs < nearestDistance then
				nearestDistance = studs
				nearest = marker
			end
		end
	end
	-- Guide beam: to the nearest mailbox, or to the stand for brand-new players.
	local target: Attachment? = nil
	if not isInside and root then
		if nearest and nearestDistance > PROMPT_RANGE * 0.6 then
			target = nearest.attachment
		elseif showStart and standGrab and (standGrab.Position - root.Position).Magnitude > 14 then
			if not standAttachment then
				local a = Instance.new("Attachment")
				a.Name = "StandTarget"
				a.Parent = standGrab
				standAttachment = a
			end
			target = standAttachment
		end
	end
	if root and target then
		ensureBeam(root)
		local guide = beam :: Beam
		guide.Attachment1 = target
		guide.Enabled = true
	elseif beam then
		beam.Enabled = false
	end
	-- Chip
	if chip and chipText then
		local text: string? = nil
		if papers > 0 then
			text = string.format("\u{1F4F0} %d / %d papers left  \u{2022}  follow the yellow line!", papers, JOB.bagSize)
		elseif showStart then
			text = "\u{1F4F0} Deliver newspapers for extra cash!"
		end
		chip.Visible = text ~= nil and not isInside
		if text then
			chipText.Text = text
		end
	end
end

----- Events -----
local function onJobEvent(kind: any, a: any, b: any, c: any, d: any)
	if kind == "grab" then
		controllers.Sound.play("Purchase", 0.5)
		if vendor then
			Bubble.say(vendor.parts.Head, "Here you go! Follow the markers!", 2.5)
		end
		local root = rootPart()
		if root then
			burst(root.Position + Vector3.new(0, 1, 0), { PAPER, Color3.fromRGB(46, 160, 105) }, 20)
		end
	elseif kind == "delivered" then
		local name, pay, tip = a, b, c
		local model = mailboxFolder and mailboxFolder:FindFirstChild(name)
		local box = model and (model :: Model).PrimaryPart
		local position = if box then box.Position + Vector3.new(0, 3, 0) else (rootPart() and (rootPart() :: BasePart).Position or Vector3.zero)
		if type(pay) == "number" then
			floatText(position, "+" .. Format.cash(pay), Color3.fromRGB(150, 255, 90))
		end
		if type(tip) == "number" and tip > 0 then
			task.delay(0.35, function()
				floatText(position + Vector3.new(0, 1.5, 0), "Tip! +" .. Format.cash(tip), YELLOW)
			end)
		end
		controllers.Sound.play("Cash", 0.45)
	elseif kind == "bagDone" then
		controllers.Sound.play("LevelUp", 0.5)
		local root = rootPart()
		if root then
			burst(root.Position + Vector3.new(0, 2, 0), { Color3.fromRGB(255, 90, 90), YELLOW, Color3.fromRGB(90, 200, 255), Color3.fromRGB(120, 230, 120) }, 40)
		end
	end
end

function JobController.init(registry: any)
	controllers = registry
end

function JobController.start()
	if not Config.PAPER_ROUTE_ENABLED then
		return -- the paper route is switched off (Config.PAPER_ROUTE_ENABLED)
	end
	effects = Instance.new("Folder")
	effects.Name = "PaperJobFx"
	effects.Parent = Workspace
	local city = Workspace:WaitForChild("City")
	routeFolder = city:WaitForChild("PaperRoute", 30)
	if not routeFolder then
		warn("[JobController] no PaperRoute in the city")
		return
	end
	mailboxFolder = (routeFolder :: Instance):WaitForChild("Mailboxes")
	local stand = (routeFolder :: Instance):WaitForChild("NewsStand")
	buildStandMarker(stand)
	spawnVendor(stand)
	buildChip()
	controllers.Store.remote("PaperJob").OnClientEvent:Connect(function(...)
		local ok, err = pcall(onJobEvent, ...)
		if not ok then
			warn("[JobController] " .. tostring(err))
		end
	end)
	controllers.Store.onChange(function(state)
		applyJob(state.job)
	end)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.15 then
			return
		end
		accumulator = 0
		local ok, err = pcall(refresh)
		if not ok then
			warn("[JobController] " .. tostring(err))
		end
	end)
end

return JobController
