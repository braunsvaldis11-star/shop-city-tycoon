--!strict
-- InteriorBuilder (client only): builds a business interior from its upgrade levels.
-- Upgrades change the room physically: more ovens, registers, tables, better floors,
-- walls, lights, furniture and premium centrepieces. Works for every business type;
-- only the station/product style and colours differ.
-- Room: 80 x 64 studs, open-top. Local -Z is the kitchen, +Z is the exit door.
-- Container: ReplicatedStorage.Client

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Businesses = require(Shared.Businesses)
local Format = require(Shared.Format)
local Props = require(Shared.Props)
local MiniGames = require(Shared.MiniGames)

local InteriorBuilder = {}

export type Seat = { position: Vector3, yaw: number, aisle: Vector3 }
export type Register = { cashier: Vector3, queue: Vector3 }
export type Layout = {
	origin: Vector3,
	door: Vector3,
	lane: Vector3,
	registers: { Register },
	stations: { Vector3 }, -- where a worker stands to use a station
	stationParts: { BasePart },
	preps: { Vector3 },
	pickups: { Vector3 },
	seats: { Seat },
	managePrompt: ProximityPrompt,
	workPrompt: ProximityPrompt,
	exitTrigger: BasePart,
	exitPrompt: ProximityPrompt,
	banner: TextLabel,
}

local HALF_W, HALF_D, WALL_H = 40, 32, 22
local WHITE = Color3.fromRGB(250, 250, 250)
local WOOD = Color3.fromRGB(170, 115, 70)
local DARK = Color3.fromRGB(55, 55, 65)
local STEEL = Color3.fromRGB(200, 205, 212)
local GOLD = Color3.fromRGB(255, 200, 60)

local TIER_TINTS = {
	Color3.fromRGB(175, 100, 80), -- basic
	Color3.fromRGB(150, 150, 160), -- stone
	Color3.fromRGB(210, 60, 55), -- deluxe
	Color3.fromRGB(60, 140, 235), -- turbo
	GOLD, -- golden
}
local TIER_MATERIALS = {
	Enum.Material.Brick, Enum.Material.Slate, Enum.Material.SmoothPlastic, Enum.Material.Metal, Enum.Material.Foil,
}

local STATION_X = { 0, -12, 12, -24, 24 }
local REGISTER_X = { -6, 6, -16, 16 }
local PREP_X = { -12, 12, 0 }
local TABLE_SPOTS = {
	Vector3.new(-17, 0, 4), Vector3.new(17, 0, 4), Vector3.new(-17, 0, 18), Vector3.new(17, 0, 18),
	Vector3.new(-30, 0, 4), Vector3.new(30, 0, 4), Vector3.new(-30, 0, 18), Vector3.new(30, 0, 18),
}
local AISLE_Z = 11

-- What the menu boards over the counter list, by product style.
local MENUS: { [string]: { string } } = {
	pizza = { "Margherita", "Pepperoni", "Veggie Slice" },
	box = { "Croissant", "Donut", "Cupcake" },
	cup = { "Espresso", "Latte", "Hot Cocoa" },
	cone = { "Vanilla", "Strawberry", "Choco Mint" },
	bag = { "Best Sellers", "New Arrivals", "Gift Cards" },
	bottle = { "Day Pass", "Protein Shake", "Coaching" },
	key = { "Savings", "Loans", "Safe Box" },
}
local DEFAULT_MENU = { "Special of the Day", "Best Seller", "Combo Deal" }

local function surfaceText(part: BasePart, face: Enum.NormalId, text: string, color: Color3, pixels: number?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixels or 25
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
	stroke.Color = Color3.fromRGB(30, 25, 25)
	stroke.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.Parent = label
	label.Parent = gui
	gui.Parent = part
	return label
end

local function light(part: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = part
end

----- Stations (one per production line) -----
local function buildStation(parent: Instance, style: string, cf: CFrame, tier: number, theme: any): BasePart
	local tint = TIER_TINTS[tier + 1]
	local material = TIER_MATERIALS[tier + 1]
	local model = Instance.new("Model")
	model.Name = "Station"
	local glow: BasePart
	if style == "oven" then
		Props.part(model, "Body", Vector3.new(7, 6, 5), cf * CFrame.new(0, 3, 0), tint, { material = material })
		Props.ball(model, "Dome", 7, (cf * CFrame.new(0, 6, 0)).Position, tint, { material = material })
		Props.cylinder(model, "Chimney", 6, 1.4, (cf * CFrame.new(0, 10, 0.8)).Position, DARK)
		glow = Props.part(model, "Opening", Vector3.new(4, 2.4, 0.3), cf * CFrame.new(0, 3.2, -2.55), Color3.fromRGB(255, 140, 40), { material = Enum.Material.Neon })
		local fire = Instance.new("Fire")
		fire.Size = 2.5
		fire.Heat = 2
		fire.Color = Color3.fromRGB(255, 150, 50)
		fire.SecondaryColor = Color3.fromRGB(255, 220, 90)
		fire.Parent = glow
		if tier >= 3 then
			Props.part(model, "Trim", Vector3.new(7.4, 0.6, 5.4), cf * CFrame.new(0, 0.3, 0), Color3.fromRGB(80, 230, 255), { material = Enum.Material.Neon })
		end
	elseif style == "espresso" then
		Props.part(model, "Base", Vector3.new(7, 4, 4), cf * CFrame.new(0, 2, 0), WOOD, { material = Enum.Material.WoodPlanks })
		Props.part(model, "Machine", Vector3.new(5, 3.5, 3), cf * CFrame.new(0, 5.75, 0.2), tint, { material = material })
		glow = Props.part(model, "Lights", Vector3.new(4, 0.5, 0.2), cf * CFrame.new(0, 6.8, -1.4), Color3.fromRGB(255, 220, 120), { material = Enum.Material.Neon })
		for _, x in { -1.3, 1.3 } do
			Props.cylinder(model, "Cup", 0.8, 0.8, (cf * CFrame.new(x, 4.4, -1.4)).Position, WHITE)
		end
	elseif style == "rack" then
		local colors = { theme.primary, theme.accent, Color3.fromRGB(80, 160, 240), Color3.fromRGB(250, 210, 70), WHITE }
		for _, x in { -3.5, 3.5 } do
			Props.part(model, "Pole", Vector3.new(0.4, 7, 0.4), cf * CFrame.new(x, 3.5, 0), tint, { material = material })
		end
		glow = Props.part(model, "Rail", Vector3.new(7.4, 0.4, 0.4), cf * CFrame.new(0, 7, 0), tint, { material = material })
		for i = 1, 5 do
			Props.part(model, "Shirt", Vector3.new(1.2, 3, 0.3), cf * CFrame.new(-3 + i * 1.2 - 0.6, 5.2, 0) * CFrame.Angles(0, math.rad(80), 0), colors[i])
		end
	elseif style == "shelf" then
		glow = Props.part(model, "Unit", Vector3.new(8, 8, 2.5), cf * CFrame.new(0, 4, 0.8), tint, { material = material })
		local colors = { Color3.fromRGB(240, 80, 80), Color3.fromRGB(80, 200, 120), Color3.fromRGB(250, 210, 70), Color3.fromRGB(80, 160, 240) }
		for row = 0, 2 do
			for i = 1, 4 do
				Props.part(model, "Goods", Vector3.new(1.4, 1.6, 1), cf * CFrame.new(-4.4 + i * 1.75, 1.6 + row * 2.6, -0.8), colors[((i + row) % 4) + 1])
			end
		end
	elseif style == "treadmill" then
		Props.part(model, "Base", Vector3.new(4, 0.8, 8), cf * CFrame.new(0, 0.4, 0), tint, { material = material })
		Props.part(model, "Belt", Vector3.new(3.2, 0.2, 7), cf * CFrame.new(0, 0.9, 0), DARK)
		for _, x in { -1.8, 1.8 } do
			Props.part(model, "Handle", Vector3.new(0.3, 4, 0.3), cf * CFrame.new(x, 2.5, 3.4), tint)
		end
		glow = Props.part(model, "Console", Vector3.new(4, 1.2, 0.8), cf * CFrame.new(0, 4.5, 3.4), theme.accent, { material = Enum.Material.Neon })
	elseif style == "car" then
		glow = Props.part(model, "Platform", Vector3.new(0.6, 11, 11), cf * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.pi / 2), STEEL, { shape = Enum.PartType.Cylinder })
		local car = Props.car(model, tint, true)
		car:PivotTo(cf * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, math.rad(60), 0))
		car:ScaleTo(0.8)
	elseif style == "desk" then
		Props.part(model, "Desk", Vector3.new(8, 4, 3), cf * CFrame.new(0, 2, 0), tint, { material = material })
		Props.part(model, "Top", Vector3.new(8.4, 0.4, 3.4), cf * CFrame.new(0, 4.2, 0), WHITE, { material = Enum.Material.Marble })
		glow = Props.part(model, "Monitor", Vector3.new(2, 1.4, 0.2), cf * CFrame.new(1.8, 5.2, 0.5), Color3.fromRGB(120, 200, 255), { material = Enum.Material.Neon })
		Props.ball(model, "Bell", 0.8, (cf * CFrame.new(-2, 4.6, -0.6)).Position, GOLD)
	elseif style == "freezer" then
		-- Ice cream display freezer: glass top over rows of coloured tubs.
		Props.part(model, "Cabinet", Vector3.new(8, 3.6, 4), cf * CFrame.new(0, 1.8, 0), tint, { material = material })
		local flavours = { Color3.fromRGB(255, 180, 210), Color3.fromRGB(255, 240, 200), Color3.fromRGB(140, 90, 60), Color3.fromRGB(150, 230, 170), Color3.fromRGB(255, 220, 90) }
		for i = 1, 5 do
			Props.part(model, "Tub", Vector3.new(1.3, 0.6, 2.6), cf * CFrame.new(-3.6 + i * 1.45 - 0.7, 3.9, 0), flavours[i], { material = Enum.Material.SmoothPlastic })
		end
		glow = Props.part(model, "Glass", Vector3.new(7.6, 1.6, 3.4), cf * CFrame.new(0, 4.6, 0.1), Color3.fromRGB(200, 240, 255), { material = Enum.Material.Glass, transparency = 0.5 })
		Props.part(model, "Light", Vector3.new(7, 0.3, 0.3), cf * CFrame.new(0, 3.2, -2.05), theme.accent, { material = Enum.Material.Neon })
	elseif style == "grill" then
		-- Flat-top grill with patties and a steel hood.
		Props.part(model, "Base", Vector3.new(8, 3.6, 4), cf * CFrame.new(0, 1.8, 0), STEEL, { material = Enum.Material.Metal })
		glow = Props.part(model, "Plate", Vector3.new(7.4, 0.3, 3.4), cf * CFrame.new(0, 3.75, 0), Color3.fromRGB(255, 120, 40), { material = Enum.Material.Neon })
		for i = 1, 3 do
			Props.part(model, "Patty", Vector3.new(0.4, 1.4, 1.4), cf * CFrame.new(-3 + i * 1.6, 4.05, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(110, 60, 35), { shape = Enum.PartType.Cylinder })
		end
		Props.part(model, "Hood", Vector3.new(8.4, 1.4, 4.4), cf * CFrame.new(0, 9.5, 0.4), tint, { material = material })
		Props.part(model, "Duct", Vector3.new(2, 4, 2), cf * CFrame.new(0, 12, 0.8), STEEL)
		local smoke = Instance.new("Smoke")
		smoke.Size = 0.6
		smoke.RiseVelocity = 2
		smoke.Opacity = 0.08
		smoke.Color = Color3.fromRGB(230, 230, 230)
		smoke.Parent = glow
	elseif style == "screen" then
		-- Display stand / server rack with a glowing screen.
		Props.part(model, "Stand", Vector3.new(7, 3.4, 3), cf * CFrame.new(0, 1.7, 0), tint, { material = material })
		Props.part(model, "Bezel", Vector3.new(7, 4.6, 0.5), cf * CFrame.new(0, 6, 0.9), DARK)
		glow = Props.part(model, "Screen", Vector3.new(6.4, 4, 0.2), cf * CFrame.new(0, 6, 0.6), theme.primary:Lerp(Color3.new(1, 1, 1), 0.3), { material = Enum.Material.Neon })
		for _, x in { -2, 0, 2 } do
			Props.part(model, "Gadget", Vector3.new(1.2, 0.3, 2), cf * CFrame.new(x, 3.55, -0.2), Color3.fromRGB(40, 40, 50))
		end
	elseif style == "tank" then
		-- Fish tank: blue glowing water, sand and little fish.
		Props.part(model, "Cabinet", Vector3.new(8, 2.4, 4), cf * CFrame.new(0, 1.2, 0), tint, { material = material })
		glow = Props.part(model, "Water", Vector3.new(7.6, 5, 3.6), cf * CFrame.new(0, 4.9, 0), Color3.fromRGB(60, 170, 255), { material = Enum.Material.Glass, transparency = 0.35 })
		Props.part(model, "Sand", Vector3.new(7.4, 0.5, 3.4), cf * CFrame.new(0, 2.65, 0), Color3.fromRGB(240, 220, 160))
		local fishColours = { Color3.fromRGB(255, 140, 40), Color3.fromRGB(255, 230, 60), Color3.fromRGB(255, 90, 120) }
		for i = 1, 3 do
			Props.part(model, "Fish", Vector3.new(1, 0.6, 0.3), cf * CFrame.new(-3 + i * 1.6, 3.6 + (i % 2) * 1.6, -0.4), fishColours[i], { collide = false })
		end
		Props.part(model, "Lid", Vector3.new(8, 0.4, 4), cf * CFrame.new(0, 7.6, 0), DARK)
	else -- kiosk
		Props.part(model, "Booth", Vector3.new(6, 5, 4), cf * CFrame.new(0, 2.5, 0), tint, { material = material })
		Props.wedge(model, "Awning", Vector3.new(6.4, 1.6, 2), cf * CFrame.new(0, 7.8, -1.6), theme.primary)
		for _, x in { -2.8, 2.8 } do
			Props.part(model, "Post", Vector3.new(0.3, 3, 0.3), cf * CFrame.new(x, 6.5, 1.6), DARK)
		end
		glow = Props.part(model, "Sign", Vector3.new(5, 1, 0.3), cf * CFrame.new(0, 5.8, -2.1), theme.accent, { material = Enum.Material.Neon })
	end
	model.Parent = parent
	return glow
end

----- Furniture -----
local function buildChair(parent: Instance, cf: CFrame, tier: number, theme: any)
	if tier >= 3 then
		local velvet = Color3.fromRGB(120, 40, 140)
		Props.part(parent, "Booth", Vector3.new(3.2, 1.6, 3.2), cf * CFrame.new(0, 1.2, 0), velvet, { material = Enum.Material.Fabric })
		Props.part(parent, "BoothBack", Vector3.new(3.2, 4.4, 0.9), cf * CFrame.new(0, 3.2, 1.4), velvet, { material = Enum.Material.Fabric })
		Props.part(parent, "BoothTrim", Vector3.new(3.3, 0.3, 1), cf * CFrame.new(0, 5.5, 1.4), GOLD)
		return
	end
	local frame = if tier == 0 then theme.primary else WOOD
	local material = if tier == 0 then Enum.Material.SmoothPlastic else Enum.Material.WoodPlanks
	Props.part(parent, "Seat", Vector3.new(2.6, 0.5, 2.6), cf * CFrame.new(0, 2, 0), frame, { material = material })
	Props.part(parent, "Back", Vector3.new(2.6, 3, 0.4), cf * CFrame.new(0, 3.6, 1.1), frame, { material = material })
	Props.part(parent, "Leg", Vector3.new(0.4, 1.8, 0.4), cf * CFrame.new(0, 0.9, 0), DARK)
	if tier == 2 then
		Props.part(parent, "Cushion", Vector3.new(2.3, 0.4, 2.3), cf * CFrame.new(0, 2.4, -0.1), Color3.fromRGB(220, 60, 70), { material = Enum.Material.Fabric })
	end
end

local function buildTable(parent: Instance, center: CFrame, seatingTier: number, theme: any, productStyle: string)
	local model = Instance.new("Model")
	model.Name = "DiningTable"
	local topColor = if seatingTier >= 2 then WHITE else theme.secondary
	Props.part(model, "Top", Vector3.new(5.5, 0.5, 5.5), center * CFrame.new(0, 3.4, 0), topColor, { material = if seatingTier >= 3 then Enum.Material.Marble else Enum.Material.SmoothPlastic })
	Props.cylinder(model, "Leg", 3.2, 0.8, (center * CFrame.new(0, 1.6, 0)).Position, DARK)
	if seatingTier >= 1 then
		Props.part(model, "Cloth", Vector3.new(3, 0.1, 5.6), center * CFrame.new(0, 3.7, 0), theme.primary, { collide = false })
	end
	if productStyle == "pizza" or productStyle == "cup" or productStyle == "box" or productStyle == "cone" then
		Props.cylinder(model, "Vase", 1.2, 0.6, (center * CFrame.new(0, 4.2, 0)).Position, theme.accent)
	end
	-- Seats on the X sides face the table (customers sit here). A chair faces its -Z
	-- (backrest at +Z), so the left one turns -90° to look +X and the right one +90°.
	buildChair(model, center * CFrame.new(-4.4, 0, 0) * CFrame.Angles(0, math.rad(-90), 0), seatingTier, theme)
	buildChair(model, center * CFrame.new(4.4, 0, 0) * CFrame.Angles(0, math.rad(90), 0), seatingTier, theme)
	model.Parent = parent
end

local function plant(parent: Instance, position: Vector3, scale: number)
	Props.cylinder(parent, "Pot", 2.4 * scale, 2.6 * scale, position + Vector3.new(0, 1.2 * scale, 0), Color3.fromRGB(200, 110, 70))
	Props.ball(parent, "Leaves", 4 * scale, position + Vector3.new(0, 3.8 * scale, 0), Color3.fromRGB(80, 180, 80))
	Props.ball(parent, "Leaves", 2.8 * scale, position + Vector3.new(0.8 * scale, 5.4 * scale, 0.4 * scale), Color3.fromRGB(100, 200, 90))
end

----- Main build -----
function InteriorBuilder.build(parent: Instance, definition: Businesses.Definition, state: any, origin: Vector3): (Model, Layout)
	local upgrades = state.upgrades or {}
	local function lv(id: string): number
		return upgrades[id] or 0
	end
	local theme = definition.theme
	local model = Instance.new("Model")
	model.Name = "Interior_" .. definition.id
	local O = CFrame.new(origin)
	local function at(x: number, y: number, z: number): CFrame
		return O * CFrame.new(x, y, z)
	end
	local function world(x: number, z: number): Vector3
		return origin + Vector3.new(x, 0, z)
	end

	local structure = Instance.new("Model")
	structure.Name = "Structure"
	structure.Parent = model
	local decor = Instance.new("Model")
	decor.Name = "Decor"
	decor.Parent = model

	----- Floor (Decoration: floor) -----
	local floorTier = lv("floor")
	local floorColors = { Color3.fromRGB(188, 160, 128), WHITE, WOOD, Color3.fromRGB(240, 238, 235) }
	local floorMaterials = { Enum.Material.CeramicTiles, Enum.Material.SmoothPlastic, Enum.Material.WoodPlanks, Enum.Material.Marble }
	Props.part(structure, "Floor", Vector3.new(HALF_W * 2 + 4, 2, HALF_D * 2 + 4), at(0, -1, 0), floorColors[floorTier + 1], { material = floorMaterials[floorTier + 1] })
	Props.part(structure, "KitchenFloor", Vector3.new(HALF_W * 2, 0.1, 18), at(0, 0.05, -23), Color3.fromRGB(200, 205, 212), { material = Enum.Material.Slate, collide = false })
	if floorTier <= 1 and lv("furniture") < 2 then
		-- Runner rug from the door to the counter (the big rug replaces it at Furniture 2).
		Props.part(decor, "Runner", Vector3.new(7, 0.1, 30), at(0, 0.07, 15), theme.primary:Lerp(Color3.new(0, 0, 0), 0.25), { material = Enum.Material.Fabric, collide = false, shadow = false })
		Props.part(decor, "RunnerTrim", Vector3.new(8, 0.08, 30.6), at(0, 0.06, 15), Color3.fromRGB(240, 205, 120), { material = Enum.Material.Fabric, collide = false, shadow = false })
	end
	if floorTier == 1 then
		local dark = theme.primary:Lerp(Color3.new(0, 0, 0), 0.15)
		for ix = 0, 9 do
			for iz = 0, 5 do
				if (ix + iz) % 2 == 0 then
					Props.part(decor, "Tile", Vector3.new(8, 0.1, 8), at(-36 + ix * 8, 0.05, -10 + iz * 8), dark, { collide = false, shadow = false })
				end
			end
		end
	elseif floorTier == 3 then
		Props.part(decor, "InlayX", Vector3.new(HALF_W * 2 - 6, 0.1, 0.6), at(0, 0.05, 11), GOLD, { collide = false, shadow = false })
		Props.part(decor, "InlayDiamond", Vector3.new(7, 0.1, 7), at(0, 0.06, 20) * CFrame.Angles(0, math.rad(45), 0), GOLD, { collide = false, shadow = false })
	end

	----- Walls (Decoration: walls) -----
	local wallTier = lv("walls")
	-- Theme "secondary" colours are near-white creams that wash out in daylight, so the
	-- painted walls are tinted toward the brand colour and slightly darkened.
	local paint = theme.secondary:Lerp(theme.primary, 0.22):Lerp(Color3.new(0, 0, 0), 0.06)
	local wallColor = ({ paint, Color3.fromRGB(185, 95, 70), theme.secondary:Lerp(theme.primary, 0.12), theme.primary:Lerp(Color3.new(0, 0, 0), 0.3) })[wallTier + 1]
	local wallMaterial = ({ Enum.Material.Plaster, Enum.Material.Brick, Enum.Material.Plaster, Enum.Material.Fabric })[wallTier + 1]
	local function wall(name: string, size: Vector3, cf: CFrame)
		Props.part(structure, name, size, cf, wallColor, { material = wallMaterial })
	end
	wall("WallBack", Vector3.new(HALF_W * 2 + 4, WALL_H, 2), at(0, WALL_H / 2, -HALF_D - 1))
	wall("WallLeft", Vector3.new(2, WALL_H, HALF_D * 2 + 4), at(-HALF_W - 1, WALL_H / 2, 0))
	wall("WallRight", Vector3.new(2, WALL_H, HALF_D * 2 + 4), at(HALF_W + 1, WALL_H / 2, 0))
	local sideWidth = HALF_W - 5
	wall("WallFrontL", Vector3.new(sideWidth + 2, WALL_H, 2), at(-(5 + (sideWidth + 2) / 2), WALL_H / 2, HALF_D + 1))
	wall("WallFrontR", Vector3.new(sideWidth + 2, WALL_H, 2), at(5 + (sideWidth + 2) / 2, WALL_H / 2, HALF_D + 1))
	wall("WallFrontTop", Vector3.new(10, WALL_H - 13, 2), at(0, 13 + (WALL_H - 13) / 2, HALF_D + 1))
	-- Baseboards on every tier, a painted lower band + chair rail on the basic walls.
	for _, spec in {
		{ Vector3.new(HALF_W * 2, 0.8, 0.5), at(0, 0.4, -HALF_D + 0.25) },
		{ Vector3.new(0.5, 0.8, HALF_D * 2), at(-HALF_W + 0.25, 0.4, 0) },
		{ Vector3.new(0.5, 0.8, HALF_D * 2), at(HALF_W - 0.25, 0.4, 0) },
	} do
		Props.part(decor, "Baseboard", spec[1], spec[2], DARK, { collide = false })
	end
	if wallTier == 0 then
		local band = theme.primary:Lerp(WHITE, 0.2)
		for _, spec in {
			{ Vector3.new(0.3, 6, HALF_D * 2), at(-HALF_W + 0.15, 3, 0), Vector3.new(0.5, 0.5, HALF_D * 2), at(-HALF_W + 0.25, 6.2, 0) },
			{ Vector3.new(0.3, 6, HALF_D * 2), at(HALF_W - 0.15, 3, 0), Vector3.new(0.5, 0.5, HALF_D * 2), at(HALF_W - 0.25, 6.2, 0) },
		} do
			Props.part(decor, "Wainscot", spec[1], spec[2], band, { collide = false })
			Props.part(decor, "ChairRail", spec[3], spec[4], WHITE, { collide = false })
		end
	end
	-- Tiled kitchen backsplash behind the stations.
	Props.part(decor, "Backsplash", Vector3.new(HALF_W * 2 - 1, 6, 0.2), at(0, 6.5, -HALF_D + 0.55), Color3.fromRGB(232, 240, 246), { material = Enum.Material.CeramicTiles, collide = false })
	if wallTier == 2 then
		for _, spec in {
			{ Vector3.new(HALF_W * 2, 7, 0.4), at(0, 3.5, -HALF_D + 0.2) },
			{ Vector3.new(0.4, 7, HALF_D * 2), at(-HALF_W + 0.2, 3.5, 0) },
			{ Vector3.new(0.4, 7, HALF_D * 2), at(HALF_W - 0.2, 3.5, 0) },
		} do
			Props.part(decor, "Wainscot", spec[1], spec[2], WOOD, { material = Enum.Material.WoodPlanks })
		end
	elseif wallTier == 3 then
		for _, spec in {
			{ Vector3.new(HALF_W * 2, 0.6, 0.4), at(0, 7, -HALF_D + 0.2) },
			{ Vector3.new(0.4, 0.6, HALF_D * 2), at(-HALF_W + 0.2, 7, 0) },
			{ Vector3.new(0.4, 0.6, HALF_D * 2), at(HALF_W - 0.2, 7, 0) },
		} do
			Props.part(decor, "GoldTrim", spec[1], spec[2], GOLD, { material = Enum.Material.Foil, collide = false })
		end
	end
	-- Wall tops and roof beams (the room is open-topped for a clear camera view).
	for _, spec in {
		{ Vector3.new(HALF_W * 2 + 5, 1.2, 3), at(0, WALL_H, -HALF_D - 1) },
		{ Vector3.new(HALF_W * 2 + 5, 1.2, 3), at(0, WALL_H, HALF_D + 1) },
		{ Vector3.new(3, 1.2, HALF_D * 2 + 5), at(-HALF_W - 1, WALL_H, 0) },
		{ Vector3.new(3, 1.2, HALF_D * 2 + 5), at(HALF_W + 1, WALL_H, 0) },
	} do
		Props.part(structure, "WallCap", spec[1], spec[2], theme.primary)
	end
	for _, z in { -16, 0, 16 } do
		Props.part(structure, "Beam", Vector3.new(HALF_W * 2, 1.4, 1.4), at(0, WALL_H - 1.5, z), WOOD, { material = Enum.Material.WoodPlanks, collide = false })
	end
	-- Fake windows with daylight.
	for _, side in { -1, 1 } do
		for _, z in { 2, 18 } do
			Props.part(decor, "Window", Vector3.new(0.3, 7, 9), at(side * (HALF_W - 0.1), 10, z), Color3.fromRGB(170, 225, 255), { material = Enum.Material.Neon, transparency = 0.2, collide = false })
			Props.part(decor, "WindowFrame", Vector3.new(0.5, 7.8, 0.6), at(side * (HALF_W - 0.2), 10, z), WHITE, { collide = false })
		end
	end

	----- Big name sign + menu board -----
	local nameBoard = Props.part(decor, "NameBoard", Vector3.new(40, 6, 0.6), at(0, 17.5, -HALF_D + 0.3), theme.primary)
	surfaceText(nameBoard, Enum.NormalId.Back, definition.emoji .. " " .. definition.name:upper(), WHITE, 20)
	local bannerPart = Props.part(decor, "LevelBanner", Vector3.new(14, 3, 0.4), at(0, 13, -HALF_D + 0.3), DARK)
	local banner = surfaceText(bannerPart, Enum.NormalId.Back, "⭐ Level " .. tostring(state.level or 1), GOLD, 25)

	----- Counter + registers (Employees: cashiers) -----
	-- Waist height for the staff and customers (top surface at y 3).
	Props.part(structure, "Counter", Vector3.new(46, 2.6, 3), at(0, 1.3, -12), theme.primary)
	Props.part(structure, "CounterTop", Vector3.new(47, 0.4, 4), at(0, 2.8, -12), WHITE, { material = if floorTier >= 3 then Enum.Material.Marble else Enum.Material.SmoothPlastic })
	local registers = {}
	for i = 1, math.min(1 + lv("cashiers"), #REGISTER_X) do
		local x = REGISTER_X[i]
		Props.part(decor, "Register", Vector3.new(2.2, 1, 1.6), at(x, 3.5, -12.4), DARK)
		Props.part(decor, "RegisterScreen", Vector3.new(1.8, 0.9, 0.2), at(x, 4.4, -12.9) * CFrame.Angles(math.rad(-20), 0, 0), Color3.fromRGB(120, 230, 160), { material = Enum.Material.Neon, collide = false })
		table.insert(registers, { cashier = world(x, -15.5), queue = world(x, -8.6) })
	end
	-- Striped canopy over the counter and two hanging menu boards.
	local stripeCount = 12
	for i = 0, stripeCount - 1 do
		local x = -HALF_W + 17 + (i + 0.5) * (46 / stripeCount)
		Props.wedge(decor, "Canopy", Vector3.new(46 / stripeCount, 1.4, 3), at(x, 10.6, -11.4) * CFrame.Angles(0, math.pi, 0),
			if i % 2 == 0 then theme.primary else WHITE, { collide = false })
	end
	Props.part(decor, "CanopyRail", Vector3.new(47, 0.4, 0.4), at(0, 9.8, -9.9), theme.primary:Lerp(Color3.new(0, 0, 0), 0.25), { collide = false })
	local menu = MENUS[definition.productStyle] or DEFAULT_MENU
	for side, x in { -14, 14 } do
		local board = Props.part(decor, "MenuBoard", Vector3.new(11, 5.2, 0.4), at(x, 15.4, -15.6), Color3.fromRGB(45, 55, 50))
		Props.part(decor, "MenuFrame", Vector3.new(11.6, 5.8, 0.3), at(x, 15.4, -15.85), WOOD, { collide = false })
		for _, cx in { -4.5, 4.5 } do
			Props.part(decor, "MenuCord", Vector3.new(0.12, 2.6, 0.12), at(x + cx, 19.3, -15.6), DARK, { collide = false })
		end
		local lines = if side == 1
			then "MENU\n" .. menu[1] .. "  $5\n" .. menu[2] .. "  $7"
			else definition.emoji .. " TODAY\n" .. menu[3] .. "  $9\nSmile  FREE"
		surfaceText(board, Enum.NormalId.Back, lines, Color3.fromRGB(250, 245, 225), 20)
	end
	-- Wall shelves with jars and boxes on both sides of the kitchen.
	local jarColors = { Color3.fromRGB(240, 90, 80), Color3.fromRGB(250, 205, 70), Color3.fromRGB(110, 190, 110), Color3.fromRGB(120, 170, 240), WHITE }
	for _, sx in { -1, 1 } do
		for row, y in { 9.6, 12.8 } do
			Props.part(decor, "Shelf", Vector3.new(8, 0.4, 1.8), at(sx * 32.5, y, -HALF_D + 1.1), WOOD, { material = Enum.Material.WoodPlanks, collide = false })
			for j = 0, 3 do
				local color = jarColors[((j + row + (if sx > 0 then 2 else 0)) % #jarColors) + 1]
				if (j + row) % 2 == 0 then
					Props.cylinder(decor, "Jar", 1.5, 1.1, at(sx * 32.5 - 2.85 + j * 1.9, y + 0.95, -HALF_D + 1.1).Position, color, { collide = false })
				else
					Props.part(decor, "Box", Vector3.new(1.4, 1.8, 1.2), at(sx * 32.5 - 2.85 + j * 1.9, y + 1.1, -HALF_D + 1.1), color, { collide = false })
				end
			end
		end
	end

	local pickups = { world(20, -12), world(-20, -12) }
	for _, x in { 20, -20 } do
		Props.part(decor, "PickupTray", Vector3.new(4, 0.2, 2.6), at(x, 3.1, -12), STEEL)
	end

	----- Production stations (Kitchen: equipment tier + extra stations) -----
	local stations, stationParts = {}, {}
	local equipmentTier = math.clamp(lv("equipment"), 0, 4)
	for i = 1, math.min(1 + lv("stations"), #STATION_X) do
		local x = STATION_X[i]
		local glow = buildStation(decor, definition.stationStyle, at(x, 0, -28) * CFrame.Angles(0, math.pi, 0), equipmentTier, theme)
		table.insert(stations, world(x, -23.5))
		table.insert(stationParts, glow)
	end
	local preps = {}
	for i = 1, math.min(lv("prep"), #PREP_X) do
		local x = PREP_X[i]
		Props.part(decor, "PrepCounter", Vector3.new(7, 2.8, 3), at(x, 1.4, -19), STEEL, { material = Enum.Material.Metal })
		Props.part(decor, "CuttingBoard", Vector3.new(3, 0.3, 2), at(x, 2.95, -19), WOOD)
		table.insert(preps, world(x, -16.6))
	end

	----- Dining / seating (tables + chair quality) -----
	local seats = {}
	local seatingTier = lv("seating")
	for i = 1, math.min(1 + lv("tables"), #TABLE_SPOTS) do
		local spot = TABLE_SPOTS[i]
		buildTable(decor, at(spot.X, 0, spot.Z), seatingTier, theme, definition.productStyle)
		for _, side in { -1, 1 } do
			local sx = spot.X + side * 4.4
			table.insert(seats, {
				position = world(sx, spot.Z),
				yaw = if side < 0 then math.rad(-90) else math.rad(90),
				aisle = world(sx, AISLE_Z),
			})
		end
	end

	----- Lighting -----
	local lightTier = lv("lighting")
	local warm = Color3.fromRGB(255, 220, 170)
	if lightTier == 0 then
		-- Simple hanging bulbs so even a brand-new shop has warm light.
		for _, spot in { Vector3.new(-17, 0, 11), Vector3.new(17, 0, 11), Vector3.new(0, 0, 22) } do
			Props.part(decor, "Cord", Vector3.new(0.15, 5.8, 0.15), at(spot.X, 17.6, spot.Z), DARK, { collide = false })
			Props.part(decor, "Shade", Vector3.new(2.2, 0.9, 2.2), at(spot.X, 14.5, spot.Z), DARK, { collide = false })
			local bulb = Props.ball(decor, "Bulb", 1.1, at(spot.X, 13.8, spot.Z).Position, warm, { material = Enum.Material.Neon, collide = false })
			light(bulb, warm, 24, 0.9)
		end
	end
	for _, spec in { { -1, -4 }, { 1, -4 }, { -1, 24 }, { 1, 24 } } do
		local sconce = Props.part(decor, "Sconce", Vector3.new(0.8, 1.6, 1.6), at(spec[1] * (HALF_W - 0.5), 12, spec[2]), warm, { material = Enum.Material.Neon, collide = false })
		light(sconce, warm, 26, 0.8 + lightTier * 0.25)
	end
	if lightTier >= 1 then
		for i = 1, math.min(1 + lv("tables"), 4) do
			local spot = TABLE_SPOTS[i]
			Props.part(decor, "Cord", Vector3.new(0.15, 7, 0.15), at(spot.X, 16.5, spot.Z), DARK, { collide = false })
			local shade = Props.part(decor, "Pendant", Vector3.new(3, 1.6, 3), at(spot.X, 12.6, spot.Z), theme.primary, { collide = false })
			local bulb = Props.ball(decor, "Bulb", 1.2, at(spot.X, 11.6, spot.Z).Position, warm, { material = Enum.Material.Neon, collide = false })
			if i <= 2 then
				light(bulb, warm, 18, 1)
			end
			local _ = shade
		end
	end
	if lightTier >= 2 then
		for i = 0, 13 do
			local x = -HALF_W + 3 + i * 5.9
			local colors = { Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 140, 160), Color3.fromRGB(140, 220, 255) }
			Props.ball(decor, "StringLight", 0.8, at(x, 19, -HALF_D + 0.6).Position, colors[(i % 3) + 1], { material = Enum.Material.Neon, collide = false })
			Props.ball(decor, "StringLight", 0.8, at(x, 19, HALF_D - 0.6).Position, colors[(i % 3) + 1], { material = Enum.Material.Neon, collide = false })
		end
		local center = Props.part(decor, "Chandelier", Vector3.new(4, 1, 4), at(0, 17, 8), GOLD, { collide = false })
		light(center, warm, 40, 1.6)
	end
	if lightTier >= 3 then
		for _, spec in {
			{ Vector3.new(HALF_W * 2 - 2, 0.5, 0.3), at(0, 20.5, -HALF_D + 0.3), theme.accent },
			{ Vector3.new(0.3, 0.5, HALF_D * 2 - 2), at(-HALF_W + 0.3, 20.5, 0), theme.primary },
			{ Vector3.new(0.3, 0.5, HALF_D * 2 - 2), at(HALF_W - 0.3, 20.5, 0), theme.primary },
		} do
			Props.part(decor, "NeonStrip", spec[1], spec[2], spec[3], { material = Enum.Material.Neon, collide = false })
		end
		local neon = Props.part(decor, "NeonSign", Vector3.new(0.3, 4, 12), at(HALF_W - 0.4, 15, 10), Color3.fromRGB(30, 20, 40), { collide = false })
		surfaceText(neon, Enum.NormalId.Left, definition.emoji .. " OPEN 24/7", theme.accent:Lerp(WHITE, 0.3), 25)
	end

	----- Furniture & plants -----
	local furnitureTier = lv("furniture")
	-- Every shop: plants by the door, a bin, a poster and a wall clock.
	for _, p in { Vector3.new(-8.5, 0, 29.5), Vector3.new(8.5, 0, 29.5) } do
		plant(decor, origin + p, 0.85)
	end
	Props.cylinder(decor, "Bin", 2.6, 1.8, at(-13, 1.3, 29.5).Position, Color3.fromRGB(70, 130, 90))
	Props.cylinder(decor, "BinLid", 0.3, 2, at(-13, 2.75, 29.5).Position, Color3.fromRGB(50, 95, 65), { collide = false })
	if furnitureTier < 2 then
		Props.part(decor, "PosterFrame", Vector3.new(0.3, 6.4, 5), at(HALF_W - 0.25, 9.5, 10), WOOD, { collide = false })
		local poster = Props.part(decor, "Poster", Vector3.new(0.35, 5.8, 4.4), at(HALF_W - 0.3, 9.5, 10), theme.primary:Lerp(WHITE, 0.15), { collide = false })
		surfaceText(poster, Enum.NormalId.Left, definition.emoji .. "\nBEST IN\nTOWN!", WHITE, 25)
	end
	local clock = Props.part(decor, "Clock", Vector3.new(0.4, 3.2, 3.2), at(-HALF_W + 0.3, 15.5, -4), WHITE, { shape = Enum.PartType.Cylinder, collide = false })
	Props.part(decor, "ClockRim", Vector3.new(0.3, 3.6, 3.6), at(-HALF_W + 0.2, 15.5, -4), DARK, { shape = Enum.PartType.Cylinder, collide = false })
	Props.part(decor, "HourHand", Vector3.new(0.1, 0.9, 0.18), at(-HALF_W + 0.55, 15.5 + 0.4, -4), DARK, { collide = false })
	Props.part(decor, "MinuteHand", Vector3.new(0.1, 0.18, 1.3), at(-HALF_W + 0.55, 15.5, -4 + 0.6), DARK, { collide = false })
	local _ = clock
	if furnitureTier >= 1 then
		for _, p in { Vector3.new(-37, 0, 29), Vector3.new(-37, 0, -9), Vector3.new(37, 0, 29) } do
			plant(decor, origin + p, 1)
		end
	end
	if furnitureTier >= 2 then
		local paintings = { Color3.fromRGB(255, 160, 80), Color3.fromRGB(110, 190, 255), Color3.fromRGB(160, 230, 130) }
		for i, z in { -4, 10, 24 } do
			Props.part(decor, "Frame", Vector3.new(0.4, 5, 6.5), at(HALF_W - 0.3, 9, z), GOLD, { collide = false })
			Props.part(decor, "Painting", Vector3.new(0.5, 4, 5.5), at(HALF_W - 0.35, 9, z), paintings[i], { collide = false })
		end
		Props.part(decor, "Rug", Vector3.new(10, 0.1, 22), at(0, 0.07, 18), theme.primary:Lerp(WHITE, 0.35), { material = Enum.Material.Fabric, collide = false })
	end
	if furnitureTier >= 3 then
		local sofa = theme.accent
		Props.part(decor, "Sofa", Vector3.new(12, 2.2, 3.5), at(31, 1.1, 29), sofa, { material = Enum.Material.Fabric })
		Props.part(decor, "SofaBack", Vector3.new(12, 4, 1), at(31, 3, 30.6), sofa, { material = Enum.Material.Fabric })
		Props.part(decor, "CoffeeTable", Vector3.new(6, 1.6, 3), at(31, 0.8, 24.5), WOOD, { material = Enum.Material.WoodPlanks })
		Props.part(decor, "Bookshelf", Vector3.new(1.6, 9, 7), at(HALF_W - 1, 4.5, 23), WOOD, { material = Enum.Material.WoodPlanks })
		local lamp = Props.ball(decor, "FloorLamp", 2, at(24, 7, 30).Position, warm, { material = Enum.Material.Neon, collide = false })
		Props.part(decor, "LampPole", Vector3.new(0.3, 6, 0.3), at(24, 3, 30), DARK, { collide = false })
		light(lamp, warm, 16, 1)
	end

	----- Premium decor -----
	local premium = lv("premium")
	if premium >= 1 then
		Props.part(decor, "Pedestal", Vector3.new(5, 3, 5), at(15, 1.5, 27), WHITE, { material = Enum.Material.Marble })
		local statue = Props.npc(decor, Random.new(3), { shirt = GOLD, pants = GOLD, hat = GOLD })
		for _, d in statue:GetDescendants() do
			if d:IsA("BasePart") then
				d.Color = GOLD
				d.Material = Enum.Material.Foil
			end
		end
		statue:PivotTo(at(15, 6, 27) * CFrame.Angles(0, math.pi, 0))
		statue:ScaleTo(1.4)
	end
	if premium >= 2 then
		Props.cylinder(decor, "FountainBasin", 1.6, 9, at(-15, 0.8, 26).Position, WHITE, { material = Enum.Material.Marble })
		Props.cylinder(decor, "FountainWater", 0.3, 7.6, at(-15, 1.6, 26).Position, Color3.fromRGB(90, 190, 255), { material = Enum.Material.Glass, transparency = 0.2 })
		Props.cylinder(decor, "FountainTier", 4, 1.4, at(-15, 3, 26).Position, GOLD, { material = Enum.Material.Foil })
		local top = Props.ball(decor, "FountainTop", 2.2, at(-15, 5.4, 26).Position, GOLD, { material = Enum.Material.Foil })
		local spray = Instance.new("ParticleEmitter")
		spray.Color = ColorSequence.new(Color3.fromRGB(190, 235, 255))
		spray.Size = NumberSequence.new(0.4, 0.1)
		spray.Lifetime = NumberRange.new(0.8, 1)
		spray.Rate = 30
		spray.Speed = NumberRange.new(6, 8)
		spray.SpreadAngle = Vector2.new(30, 30)
		spray.Acceleration = Vector3.new(0, -20, 0)
		spray.EmissionDirection = Enum.NormalId.Top
		spray.Parent = top
	end

	----- Marketing visuals: a poster per ads level, review stars per reputation -----
	for i = 1, math.min(lv("ads"), 5) do
		local poster = Props.part(decor, "Poster", Vector3.new(0.3, 4, 3), at(-HALF_W + 0.3, 8, 4 + i * 4), theme.accent:Lerp(WHITE, 0.2), { collide = false })
		surfaceText(poster, Enum.NormalId.Right, "SALE!", WHITE, 25)
	end
	if lv("reputation") > 0 then
		local stars = Props.part(decor, "ReviewBoard", Vector3.new(10, 2.4, 0.3), at(-25, 10, -HALF_D + 0.3), WHITE, { collide = false })
		surfaceText(stars, Enum.NormalId.Back, string.rep("⭐", lv("reputation")), GOLD, 25)
	end

	----- Manage board, mini game point, exit -----
	local board = Props.part(structure, "ManageBoard", Vector3.new(0.6, 8, 12), at(-HALF_W + 0.4, 7, -4), Color3.fromRGB(45, 50, 70))
	surfaceText(board, Enum.NormalId.Right, "📋 MANAGE\nUpgrades • Staff • Decor", WHITE, 25)
	local managePrompt = Instance.new("ProximityPrompt")
	managePrompt.Name = "ManagePrompt"
	managePrompt.ActionText = "Manage Business"
	managePrompt.ObjectText = definition.name
	managePrompt.HoldDuration = 0
	managePrompt.MaxActivationDistance = 14
	managePrompt.RequiresLineOfSight = false
	managePrompt.KeyboardKeyCode = Enum.KeyCode.E
	managePrompt.Parent = board

	-- The owner's mini game (make the pizza, pack the order, ...) at the front of the counter.
	local workPoint = Props.part(structure, "WorkPoint", Vector3.new(2, 2, 2), at(0, 3.8, -10.4), WHITE, { transparency = 1, collide = false })
	local workPrompt = Instance.new("ProximityPrompt")
	workPrompt.Name = "WorkPrompt"
	workPrompt.ActionText = MiniGames.get(definition.id).action
	workPrompt.ObjectText = "Mini game \u{2022} earn cash"
	workPrompt.HoldDuration = 0
	workPrompt.MaxActivationDistance = 12
	workPrompt.RequiresLineOfSight = false
	workPrompt.KeyboardKeyCode = Enum.KeyCode.F
	workPrompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	workPrompt.Parent = workPoint

	Props.part(structure, "ExitPortal", Vector3.new(10, 13, 0.4), at(0, 6.5, HALF_D + 1.8), Color3.fromRGB(170, 230, 255), { material = Enum.Material.Neon, transparency = 0.2 })
	Props.part(structure, "ExitFrame", Vector3.new(12, 1, 1), at(0, 13.5, HALF_D), theme.accent)
	local exitSign = Props.part(structure, "ExitSign", Vector3.new(7, 2.2, 0.4), at(0, 15.5, HALF_D - 0.1), Color3.fromRGB(40, 180, 80), { material = Enum.Material.Neon })
	surfaceText(exitSign, Enum.NormalId.Front, "🚪 EXIT TO CITY", WHITE, 30)
	local exitTrigger = Props.part(structure, "ExitTrigger", Vector3.new(9, 12, 1.5), at(0, 6, HALF_D + 0.6), WHITE, { transparency = 1, collide = false })
	exitTrigger.CanTouch = true
	local exitPrompt = Instance.new("ProximityPrompt")
	exitPrompt.Name = "ExitPrompt"
	exitPrompt.ActionText = "Exit to City"
	exitPrompt.ObjectText = definition.name
	exitPrompt.HoldDuration = 0.3
	exitPrompt.MaxActivationDistance = 10
	exitPrompt.RequiresLineOfSight = false
	exitPrompt.Parent = exitTrigger
	local welcome = Props.part(structure, "WelcomeMat", Vector3.new(10, 0.1, 5), at(0, 0.06, HALF_D - 3), theme.primary, { collide = false })
	local _ = welcome

	model.Parent = parent
	return model, {
		origin = origin,
		door = world(0, HALF_D - 2),
		lane = world(0, AISLE_Z),
		registers = registers,
		stations = stations,
		stationParts = stationParts,
		preps = preps,
		pickups = pickups,
		seats = seats,
		managePrompt = managePrompt,
		workPrompt = workPrompt,
		exitTrigger = exitTrigger,
		exitPrompt = exitPrompt,
		banner = banner,
	}
end

-- Small product prop that customers carry out.
function InteriorBuilder.product(style: string, theme: any): BasePart
	if style == "pizza" then
		return Props.part(nil, "PizzaBox", Vector3.new(2.6, 0.5, 2.6), CFrame.new(), Color3.fromRGB(235, 205, 150), { collide = false, shadow = false })
	elseif style == "cup" then
		return Props.part(nil, "Cup", Vector3.new(1.2, 1.2, 1.2), CFrame.new(), WHITE, { shape = Enum.PartType.Cylinder, collide = false, shadow = false })
	elseif style == "bottle" then
		return Props.part(nil, "Bottle", Vector3.new(0.9, 1.8, 0.9), CFrame.new(), Color3.fromRGB(90, 190, 255), { collide = false, shadow = false })
	elseif style == "key" then
		return Props.part(nil, "Key", Vector3.new(1.4, 0.4, 0.6), CFrame.new(), GOLD, { collide = false, shadow = false })
	elseif style == "box" then
		return Props.part(nil, "Box", Vector3.new(1.8, 1.2, 1.8), CFrame.new(), theme.primary:Lerp(Color3.new(1, 1, 1), 0.35), { collide = false, shadow = false })
	elseif style == "cone" then
		return Props.part(nil, "Cone", Vector3.new(1, 1, 1), CFrame.new(), theme.primary, { shape = Enum.PartType.Ball, collide = false, shadow = false })
	end
	return Props.part(nil, "Bag", Vector3.new(1.8, 2, 0.8), CFrame.new(), theme.primary, { collide = false, shadow = false })
end

return InteriorBuilder
