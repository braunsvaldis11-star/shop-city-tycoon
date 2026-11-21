--!strict
-- CityController (client): makes the SHARED city look personal.
-- Every player sees the same lots, but doors, signs and flags are restyled locally
-- from this player's own state. Opening a door here is purely visual/local
-- collision; the server re-checks ownership on every entry.
-- Container: StarterPlayerScripts.Controllers

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Businesses = require(Shared.Businesses)
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)

local CityController = {}

local controllers: any
local player = Players.LocalPlayer

type Lot = {
	id: string,
	definition: Businesses.Definition,
	model: Model,
	door: BasePart?,
	prompt: ProximityPrompt?,
	doorLight: BasePart?,
	portal: BasePart?,
	flag: BasePart?,
	sign: SurfaceGui?,
	tag: TextLabel?,
}

local lots: { [string]: Lot } = {}

local OWNED_COLOR = Color3.fromRGB(70, 210, 90)
local SALE_COLOR = Color3.fromRGB(255, 190, 40)

----- Waypoint (beam from the player to a business door) -----
local waypoint: { beam: Beam, target: Attachment, source: Attachment?, highlight: Highlight, id: string, expires: number }? = nil

local function clearWaypoint()
	if waypoint then
		waypoint.beam:Destroy()
		waypoint.target:Destroy()
		if waypoint.source then
			waypoint.source:Destroy()
		end
		waypoint.highlight:Destroy()
		waypoint = nil
	end
end

function CityController.setWaypoint(businessId: string)
	clearWaypoint()
	local lot = lots[businessId]
	if not lot or not lot.door then
		return
	end
	if controllers.Interior.isInside() then
		controllers.UI.notify("info", "Leave the building first, then follow the arrow.")
	end
	local target = Instance.new("Attachment")
	target.Name = "WaypointTarget"
	target.Position = Vector3.new(0, -4, -3)
	target.Parent = lot.door
	local beam = Instance.new("Beam")
	beam.Name = "Waypoint"
	beam.Attachment1 = target
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 230, 90))
	beam.Width0, beam.Width1 = 1.2, 1.2
	beam.FaceCamera = true
	beam.LightEmission = 0.8
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureMode = Enum.TextureMode.Static
	beam.TextureLength = 3
	beam.TextureSpeed = 2
	beam.Transparency = NumberSequence.new(0.15)
	beam.Parent = lot.door
	local highlight = Instance.new("Highlight")
	highlight.Name = "WaypointHighlight"
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(255, 230, 90)
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Adornee = lot.model
	highlight.Parent = lot.model
	waypoint = { beam = beam, target = target, source = nil, highlight = highlight, id = businessId, expires = os.clock() + 120 }
	controllers.UI.notify("info", "📍 Follow the golden trail to the " .. lot.definition.name .. ".")
end

local function updateWaypoint()
	local current = waypoint
	if not current then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	if not current.source or current.source.Parent ~= root then
		if current.source then
			current.source:Destroy()
		end
		local source = Instance.new("Attachment")
		source.Name = "WaypointSource"
		source.Position = Vector3.new(0, -2, 0)
		source.Parent = root
		current.source = source
		current.beam.Attachment0 = source
	end
	local inside = root.Position.Y > Config.INTERIOR_MIN_Y
	current.beam.Enabled = not inside
	local distance = (root.Position - current.target.WorldPosition).Magnitude
	if distance < 14 or os.clock() > current.expires then
		clearWaypoint()
	end
end

----- Lots -----
local function findLots()
	local city = Workspace:WaitForChild("City")
	local folder = city:WaitForChild("Businesses")
	for _, definition in Businesses.List do
		local model = folder:WaitForChild(definition.id, 20) :: Model?
		if model then
			local door = model:WaitForChild("Door", 10) :: BasePart?
			local signPart = model:FindFirstChild("SaleSign")
			local tagAnchor = model:FindFirstChild("TagAnchor")
			local tagGui = tagAnchor and tagAnchor:FindFirstChild("OwnerTag")
			lots[definition.id] = {
				id = definition.id,
				definition = definition,
				model = model,
				door = door,
				prompt = door and door:FindFirstChild("DoorPrompt") :: ProximityPrompt?,
				doorLight = model:FindFirstChild("DoorLight") :: BasePart?,
				portal = model:FindFirstChild("Portal") :: BasePart?,
				flag = model:FindFirstChild("OwnerFlag") :: BasePart?,
				sign = signPart and signPart:FindFirstChild("SignGui") :: SurfaceGui?,
				tag = tagGui and tagGui:FindFirstChild("Label") :: TextLabel?,
			}
		else
			warn("[CityController] Missing lot model for", definition.id)
		end
	end
end

local function setLabel(gui: Instance?, name: string, value: string, color: Color3?)
	local label = gui and gui:FindFirstChild(name) :: TextLabel?
	if label then
		label.Text = value
		if color then
			label.TextColor3 = color
		end
	end
end

local STARTER_COLOR = Color3.fromRGB(80, 200, 255)

local function styleLot(lot: Lot, state: any)
	local definition = lot.definition
	local owned = state.businesses[definition.id]
	-- The first shop of a player who owns nothing (server: Formulas.starterShop); they
	-- start with exactly enough cash for it.
	local starter = not owned and state.starterShop == definition.id
	local color = if owned then OWNED_COLOR elseif starter then STARTER_COLOR else SALE_COLOR

	if lot.door then
		-- Owners walk straight through (local collision only); everyone else meets a shut door.
		lot.door.CanCollide = not owned
		lot.door.Transparency = if owned then 0.75 else 0
	end
	if lot.portal then
		lot.portal.Transparency = if owned then 0.45 else 1
		lot.portal.Color = definition.theme.accent
		lot.portal.Material = Enum.Material.Neon
	end
	if lot.doorLight then
		lot.doorLight.Color = color
		lot.doorLight.Material = Enum.Material.Neon
	end
	if lot.flag then
		lot.flag.Color = color
	end
	if lot.prompt then
		lot.prompt.ObjectText = definition.emoji .. " " .. definition.name
		if owned then
			lot.prompt.ActionText = "Enter"
			lot.prompt.HoldDuration = 0
		elseif starter then
			lot.prompt.ActionText = "Buy your first shop " .. Format.cash(definition.price)
			lot.prompt.HoldDuration = 0.3
		else
			lot.prompt.ActionText = "Buy " .. Format.cash(definition.price)
			lot.prompt.HoldDuration = 0.6
		end
	end
	if lot.sign then
		local header = lot.sign:FindFirstChild("Header") :: Frame?
		if header then
			header.BackgroundColor3 = color
		end
		setLabel(lot.sign, "Title", definition.emoji .. " " .. definition.name)
		if owned then
			setLabel(lot.sign, "Status", "⭐ YOUR BUSINESS")
			setLabel(lot.sign, "Price", "Level " .. owned.level .. " / " .. Config.MAX_BUSINESS_LEVEL)
			setLabel(lot.sign, "Income", "Earning " .. Format.cash(if owned.stats then owned.stats.income else 0) .. "/s")
		else
			local affordable = state.money >= definition.price
			setLabel(lot.sign, "Status", if starter then "🎁 YOUR FIRST SHOP" else "FOR SALE")
			setLabel(lot.sign, "Price", Format.cash(definition.price), if affordable then Color3.fromRGB(60, 170, 70) else Color3.fromRGB(200, 70, 60))
			setLabel(lot.sign, "Income", "~" .. Format.cash(Formulas.startingIncome(definition, state.prestige, state.population, state.incomeBoost)) .. "/s")
		end
	end
	if lot.tag then
		local gui = lot.tag.Parent :: BillboardGui
		gui.Enabled = true
		if owned then
			lot.tag.Text = "⭐ " .. player.DisplayName .. "'s " .. definition.name .. "  •  Lv " .. owned.level
			lot.tag.BackgroundColor3 = Color3.fromRGB(40, 150, 60)
		elseif starter then
			lot.tag.Text = "🎁 Your first shop: " .. definition.name .. " • " .. Format.cash(definition.price)
			lot.tag.BackgroundColor3 = Color3.fromRGB(30, 140, 220)
		else
			lot.tag.Text = "🏷️ " .. definition.name .. " • For sale " .. Format.cash(definition.price)
			lot.tag.BackgroundColor3 = Color3.fromRGB(210, 140, 20)
		end
	end
end

-- The new-player guide (chip, steps and when to show the trail) is GuideController.
local function applyState(state: any)
	if not state or not state.businesses then
		return
	end
	for _, lot in lots do
		styleLot(lot, state)
	end
end

function CityController.init(registry: any)
	controllers = registry
end

function CityController.start()
	findLots()
	controllers.Store.onChange(applyState)
	applyState(controllers.Store.state)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.2 then
			elapsed = 0
			updateWaypoint()
		end
	end)
end

return CityController
