--!strict
-- PaperRouteBuilder (edit-time dev tool): builds the starter job's News Stand in the
-- spawn park and a mailbox beside the door of every filler shop in Old Town.
-- Run once from the command bar / MCP after (re)generating the city:
--   require(game.ServerStorage.DevTools.PaperRouteBuilder).build()
-- Output: Workspace.City.PaperRoute { NewsStand, Mailboxes { MB_01.. } }
-- Container: ServerStorage.DevTools

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Props = require(ReplicatedStorage.Shared.Props)

local PaperRouteBuilder = {}

local STAND_CFRAME = CFrame.new(11, 0.9, 28) * CFrame.Angles(0, math.rad(90), 0) -- front faces the park path
local OLD_TOWN_HALF = 200

local GREEN = Color3.fromRGB(46, 160, 105)
local DARK_GREEN = Color3.fromRGB(30, 110, 75)
local CREAM = Color3.fromRGB(250, 240, 215)
local WOOD = Color3.fromRGB(170, 115, 70)
local PAPER = Color3.fromRGB(240, 238, 230)
local INK = Color3.fromRGB(40, 40, 50)

local function surfaceText(part: BasePart, face: Enum.NormalId, text: string, color: Color3, pixels: number)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixels
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(30, 25, 25)
	stroke.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.Parent = label
	label.Parent = gui
	gui.Parent = part
end

local function paperStack(parent: Instance, cf: CFrame, count: number)
	for i = 0, count - 1 do
		local tone = if i % 2 == 0 then PAPER else Color3.fromRGB(215, 215, 210)
		Props.part(parent, "Paper", Vector3.new(1.8, 0.22, 2.4), cf * CFrame.new(0, 0.11 + i * 0.22, 0) * CFrame.Angles(0, math.rad((i % 3 - 1) * 4), 0), tone)
	end
	Props.part(parent, "Twine", Vector3.new(0.12, count * 0.22 + 0.04, 2.45), cf * CFrame.new(0, count * 0.11, 0), Color3.fromRGB(200, 60, 50), { collide = false })
end

local function buildStand(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "NewsStand"
	local function at(x: number, y: number, z: number): CFrame
		return STAND_CFRAME * CFrame.new(x, y, z)
	end
	Props.part(model, "Platform", Vector3.new(10, 0.4, 8), at(0, 0.2, 1), WOOD, { material = Enum.Material.WoodPlanks })
	Props.part(model, "BackWall", Vector3.new(9, 9, 0.6), at(0, 4.9, 4.4), GREEN)
	for _, side in { -1, 1 } do
		Props.part(model, "SideWall", Vector3.new(0.6, 9, 6.6), at(side * 4.5, 4.9, 1.4), GREEN)
		Props.part(model, "Corner", Vector3.new(0.9, 9.4, 0.9), at(side * 4.6, 4.9, -2), DARK_GREEN)
	end
	-- Counter
	Props.part(model, "Counter", Vector3.new(8.4, 3.6, 1.4), at(0, 2.2, -2.1), CREAM)
	Props.part(model, "CounterStripe", Vector3.new(8.5, 0.6, 1.45), at(0, 1.4, -2.1), GREEN, { collide = false })
	Props.part(model, "CounterTop", Vector3.new(9.4, 0.4, 2), at(0, 4.2, -2.2), WOOD, { material = Enum.Material.WoodPlanks })
	paperStack(model, at(-2.7, 4.4, -2.2), 6)
	paperStack(model, at(2.7, 4.4, -2.2), 4)
	paperStack(model, at(0, 4.4, -2.4) * CFrame.Angles(0, math.rad(90), 0), 2)
	-- Roof + striped awning
	Props.part(model, "Roof", Vector3.new(10.4, 0.6, 8), at(0, 9.7, 1.2), DARK_GREEN)
	for i = 0, 4 do
		Props.wedge(model, "Awning", Vector3.new(2.08, 1.6, 2.6), at(-4.16 + i * 2.08, 8.6, -4), if i % 2 == 0 then GREEN else CREAM)
	end
	-- Big sign
	local sign = Props.part(model, "Sign", Vector3.new(9.6, 2.8, 0.5), at(0, 11.5, -1.6), Color3.fromRGB(255, 205, 40))
	Props.part(model, "SignFrame", Vector3.new(10.2, 3.4, 0.3), at(0, 11.5, -1.25), INK)
	surfaceText(sign, Enum.NormalId.Front, "\u{1F4F0} NEWS STAND", Color3.new(1, 1, 1), 30)
	-- Headline posters on the walls
	local poster = Props.part(model, "Poster", Vector3.new(0.2, 3.2, 2.6), at(-4.85, 5.2, 1.2), PAPER, { collide = false })
	surfaceText(poster, Enum.NormalId.Left, "EXTRA!\nEXTRA!", Color3.fromRGB(220, 50, 50), 30)
	local poster2 = Props.part(model, "Poster2", Vector3.new(0.2, 3.2, 2.6), at(4.85, 5.2, 1.2), PAPER, { collide = false })
	surfaceText(poster2, Enum.NormalId.Right, "PAPER\nROUTE", Color3.fromRGB(46, 160, 105), 30)
	local board = Props.part(model, "JobBoard", Vector3.new(6.6, 3, 0.2), at(0, 7, 4.05), Color3.fromRGB(60, 70, 90), { collide = false })
	surfaceText(board, Enum.NormalId.Front, "Deliver papers \u{2192} earn cash!", Color3.new(1, 1, 1), 30)
	-- Bundles on the ground and a bicycle-free sandwich board
	paperStack(model, at(-6.2, 0.9 - 0.9, -2.6), 5)
	paperStack(model, at(6.2, 0.9 - 0.9, -2.6) * CFrame.Angles(0, math.rad(20), 0), 3)
	-- Where the prompt lives (server listens to it).
	local grab = Props.part(model, "GrabPoint", Vector3.new(4, 2, 2), at(0, 5, -2.6), Color3.new(1, 1, 1), { transparency = 1, collide = false })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GrabPrompt"
	prompt.ActionText = "Grab Newspapers"
	prompt.ObjectText = "News Stand"
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = grab
	-- Where the client-side vendor stands.
	local vendor = Props.part(model, "VendorSpot", Vector3.new(1, 1, 1), at(0, 0.4, 1), Color3.new(1, 1, 1), { transparency = 1, collide = false })
	local _ = vendor
	model.PrimaryPart = grab
	model.Parent = parent
	return model
end

local function buildMailbox(parent: Instance, name: string, cf: CFrame, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = name
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	Props.part(model, "Post", Vector3.new(0.4, 3, 0.4), at(0, 1.5, 0.2), Color3.fromRGB(70, 70, 80))
	local box = Props.part(model, "Box", Vector3.new(1.5, 1.2, 2.3), at(0, 3.6, 0), color)
	Props.part(model, "Top", Vector3.new(2.3, 1.5, 1.5), at(0, 4.2, 0) * CFrame.Angles(0, math.rad(90), 0), color, { shape = Enum.PartType.Cylinder })
	Props.part(model, "Lid", Vector3.new(1.3, 1.5, 0.12), at(0, 3.85, -1.17), color:Lerp(Color3.new(1, 1, 1), 0.35), { collide = false })
	Props.part(model, "Flag", Vector3.new(0.12, 1.3, 0.4), at(0.82, 3.9, 0.55), Color3.fromRGB(230, 50, 50), { collide = false })
	model.PrimaryPart = box
	model.Parent = parent
	return model
end

local function clear(position: Vector3, size: Vector3, ignore: { Instance }): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	for _, hit in Workspace:GetPartBoundsInBox(CFrame.new(position), size, params) do
		local n = hit.Name
		if not (n == "Sidewalk" or n == "Plaza" or n == "Lawn" or n == "Grass" or n:find("Asphalt") or n:find("Path")) then
			return false
		end
	end
	return true
end

function PaperRouteBuilder.build(): Folder
	local city = Workspace:WaitForChild("City")
	local old = city:FindFirstChild("PaperRoute")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "PaperRoute"
	buildStand(folder)
	local mailboxes = Instance.new("Folder")
	mailboxes.Name = "Mailboxes"
	mailboxes.Parent = folder
	folder.Parent = city

	local colors = { Color3.fromRGB(60, 120, 220), Color3.fromRGB(70, 170, 120), Color3.fromRGB(230, 120, 60), Color3.fromRGB(150, 90, 210) }
	local doors = {}
	for _, block in (city:WaitForChild("Blocks") :: Instance):GetChildren() do
		for _, shop in block:GetChildren() do
			if shop.Name == "Shop" then
				local door = shop:FindFirstChild("Door", true)
				if door and door:IsA("BasePart") and math.abs(door.Position.X) < OLD_TOWN_HALF and math.abs(door.Position.Z) < OLD_TOWN_HALF then
					table.insert(doors, door)
				end
			end
		end
	end
	table.sort(doors, function(a, b)
		return if a.Position.Z == b.Position.Z then a.Position.X < b.Position.X else a.Position.Z < b.Position.Z
	end)
	local count = 0
	for _, door in doors do
		local look = Vector3.new(door.CFrame.LookVector.X, 0, door.CFrame.LookVector.Z).Unit
		local right = look:Cross(Vector3.yAxis)
		local base = door.Position - Vector3.new(0, door.Size.Y / 2, 0) + look * 3.2
		for _, side in { 1, -1 } do
			local spot = base + right * side * (door.Size.X / 2 + 2.6)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { folder }
			local hit = Workspace:Raycast(spot + Vector3.new(0, 4, 0), Vector3.new(0, -10, 0), params)
			if hit and clear(hit.Position + Vector3.new(0, 2.7, 0), Vector3.new(2.6, 4.8, 3), { folder }) then
				count += 1
				local ground = hit.Position
				buildMailbox(mailboxes, string.format("MB_%02d", count), CFrame.lookAt(ground, ground + look), colors[(count % #colors) + 1])
				break
			end
		end
	end
	print(string.format("[PaperRouteBuilder] News stand + %d mailboxes (from %d shop doors)", count, #doors))
	return folder
end

return PaperRouteBuilder
