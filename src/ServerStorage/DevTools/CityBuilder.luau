--!strict
-- CityBuilder (edit-time tool, never runs in a live server)
-- Generates the shared low-poly city from ReplicatedStorage.Shared.CityLayout: six
-- open districts of dense blocks, roads, business entrances, welcome arches and decoration.
-- Every road-facing block edge is lined with buildings in the district's style, so the
-- city stays dense no matter how the layout is edited.
-- Rebuild from the command bar after editing CityLayout or Businesses:
--     require(game.ServerStorage.DevTools.CityBuilder).buildAll()
-- ModuleScripts are cached per Studio session, so require a fresh :Clone() after edits.
-- Container: ServerStorage.DevTools

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Businesses = require(Shared.Businesses)
local CityLayout = require(Shared.CityLayout)
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Props = require(Shared.Props)

local CityBuilder = {}

local ASPHALT = Color3.fromRGB(72, 76, 88)
local SIDEWALK = Color3.fromRGB(214, 214, 222)
local PAVING = Color3.fromRGB(236, 228, 212)
local CONCRETE = Color3.fromRGB(200, 200, 208)
local GRASS = Color3.fromRGB(112, 200, 92)
local HEDGE = Color3.fromRGB(60, 150, 70)
local WATER = Color3.fromRGB(45, 150, 215)
local SAND = Color3.fromRGB(240, 220, 160)
local WOOD = Color3.fromRGB(175, 125, 80)
local WINDOW = Color3.fromRGB(160, 215, 245)
local WHITE = Color3.fromRGB(250, 250, 250)
local DARK = Color3.fromRGB(55, 60, 75)
local GOLD = Color3.fromRGB(255, 200, 60)
local CURB = 0.8 -- top of block slabs
local TOP = CURB + 0.1 -- top of block surfaces (lawn, plaza, ...)
local ROAD_HALF = CityLayout.ROAD_HALF
local COAST_X = CityLayout.COAST_X
local S = CityLayout.SCALE -- landmarks are drawn at plan size, then scaled by this
local SURFACE_INSET = 8 -- width of the raised sidewalk around every block

CityBuilder.Roads = CityLayout.Roads
CityBuilder.Blocks = CityLayout.Blocks
CityBuilder.Gates = CityLayout.Gates

type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }
type Edge = { a: Vector3, dir: Vector3, outward: Vector3, length: number, road: boolean }

local SHOP_COLORS = {
	Color3.fromRGB(255, 205, 150), Color3.fromRGB(175, 215, 255), Color3.fromRGB(255, 180, 190), Color3.fromRGB(190, 235, 180),
	Color3.fromRGB(250, 240, 200), Color3.fromRGB(215, 190, 245), Color3.fromRGB(255, 225, 120), Color3.fromRGB(160, 225, 220),
}
local AWNING_COLORS = {
	Color3.fromRGB(230, 70, 70), Color3.fromRGB(60, 150, 230), Color3.fromRGB(60, 180, 100),
	Color3.fromRGB(250, 170, 40), Color3.fromRGB(170, 90, 220), Color3.fromRGB(240, 110, 170),
}
local HOUSE_WALLS = {
	Color3.fromRGB(255, 236, 200), Color3.fromRGB(185, 215, 245), Color3.fromRGB(250, 205, 205), Color3.fromRGB(200, 235, 200),
	Color3.fromRGB(246, 246, 240), Color3.fromRGB(255, 225, 150), Color3.fromRGB(215, 200, 240), Color3.fromRGB(230, 205, 170),
}
local HOUSE_ROOFS = {
	Color3.fromRGB(190, 75, 65), Color3.fromRGB(70, 90, 150), Color3.fromRGB(120, 85, 70),
	Color3.fromRGB(70, 130, 100), Color3.fromRGB(110, 115, 130), Color3.fromRGB(200, 110, 70),
}
local DOOR_COLORS = {
	Color3.fromRGB(170, 60, 60), Color3.fromRGB(60, 90, 160), Color3.fromRGB(60, 130, 90), Color3.fromRGB(230, 170, 60), Color3.fromRGB(120, 80, 60),
}
local SHUTTER_COLORS = {
	Color3.fromRGB(70, 110, 170), Color3.fromRGB(60, 120, 80), Color3.fromRGB(150, 60, 60), Color3.fromRGB(90, 90, 100), Color3.fromRGB(245, 245, 245),
}
local HOUSE_TRIM = Color3.fromRGB(250, 250, 245)
local TOWER_COLORS = {
	Color3.fromRGB(110, 150, 210), Color3.fromRGB(150, 160, 180), Color3.fromRGB(90, 190, 190),
	Color3.fromRGB(230, 200, 150), Color3.fromRGB(200, 120, 110), Color3.fromRGB(170, 140, 220),
}
local LUXURY_COLORS = {
	Color3.fromRGB(230, 215, 185), Color3.fromRGB(70, 110, 170), Color3.fromRGB(245, 245, 250), Color3.fromRGB(190, 160, 120), Color3.fromRGB(120, 90, 150),
}
local GLASS_TRIMS = {
	Color3.fromRGB(60, 70, 90), Color3.fromRGB(205, 210, 220), Color3.fromRGB(40, 90, 140), Color3.fromRGB(225, 205, 150), Color3.fromRGB(30, 30, 40),
}
local WAREHOUSE_COLORS = {
	Color3.fromRGB(200, 90, 70), Color3.fromRGB(110, 150, 190), Color3.fromRGB(220, 200, 150), Color3.fromRGB(130, 170, 130), Color3.fromRGB(180, 180, 190),
}
local CONTAINER_COLORS = {
	Color3.fromRGB(220, 70, 60), Color3.fromRGB(50, 120, 200), Color3.fromRGB(250, 180, 40),
	Color3.fromRGB(60, 160, 90), Color3.fromRGB(240, 240, 240), Color3.fromRGB(150, 80, 180),
}
local SHOP_NAMES = {
	"📚 BOOKS", "💐 FLOWERS", "🧸 TOYS", "💈 BARBER", "🎮 GAMES", "👟 SHOES", "🎵 MUSIC", "🍩 DONUTS",
	"💊 PHARMACY", "🎨 ART", "🌮 TACOS", "🍜 NOODLES", "📷 PHOTO", "👓 OPTICIAN", "🧺 LAUNDRY", "🎁 GIFTS",
	"🍬 CANDY", "🧀 DELI", "🕰️ CLOCKS", "🪴 PLANTS", "✂️ TAILOR", "🎲 HOBBIES", "🍵 TEA", "🥤 JUICE",
}
local BILLBOARDS = {
	"🍕 EAT PIZZA!", "📱 NEW PHONE OUT", "🚗 DRIVE IN STYLE", "☕ COFFEE TIME", "🏋️ GET FIT", "🍦 COOL DOWN", "🏨 STAY UPTOWN", "💼 INVEST NOW",
}

----- Helpers -----
local function folder(parent: Instance, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function rect(parent: Instance, name: string, minX: number, maxX: number, minZ: number, maxZ: number, top: number, thickness: number, color: Color3, material: Enum.Material?): Part
	return Props.part(parent, name, Vector3.new(maxX - minX, thickness, maxZ - minZ),
		CFrame.new((minX + maxX) / 2, top - thickness / 2, (minZ + maxZ) / 2), color, { material = material })
end

local function label(parent: Instance, face: Enum.NormalId, text: string, color: Color3, pixelsPerStud: number?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 30
	gui.LightInfluence = 0
	gui.MaxDistance = 450
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Text"
	textLabel.BackgroundTransparency = 1
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.Font = Enum.Font.FredokaOne
	textLabel.TextScaled = true
	textLabel.TextColor3 = color
	textLabel.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(40, 30, 30)
	stroke.Parent = textLabel
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.PaddingBottom = UDim.new(0.08, 0)
	padding.Parent = textLabel
	textLabel.Parent = gui
	gui.Parent = parent
	return gui
end
CityBuilder.label = label

local function box(minX: number, maxX: number, minZ: number, maxZ: number): Rect
	return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
end

local function around(cx: number, cz: number, halfX: number, halfZ: number): Rect
	return box(cx - halfX, cx + halfX, cz - halfZ, cz + halfZ)
end

local function overlaps(a: Rect, b: Rect, margin: number): boolean
	return a.minX < b.maxX + margin and a.maxX > b.minX - margin and a.minZ < b.maxZ + margin and a.maxZ > b.minZ - margin
end

local function onRoad(point: Vector3): boolean
	return CityLayout.onRoad(point.X, point.Z)
end

local function intersections(): { Vector3 }
	local result = {}
	for _, a in CityLayout.Roads do
		if a[1] == a[3] then -- runs along Z
			for _, b in CityLayout.Roads do
				if b[2] == b[4] then -- runs along X
					local x, z = a[1], b[2]
					if z >= math.min(a[2], a[4]) and z <= math.max(a[2], a[4]) and x >= math.min(b[1], b[3]) and x <= math.max(b[1], b[3]) then
						table.insert(result, Vector3.new(x, 0, z))
					end
				end
			end
		end
	end
	return result
end

-- The four edges of a block: start corner, direction along the edge, outward normal.
local function blockEdges(block: { any }): { Edge }
	local minX, maxX, minZ, maxZ = block[1], block[2], block[3], block[4]
	local edges: { Edge } = {
		{ a = Vector3.new(minX, 0, minZ), dir = Vector3.xAxis, outward = -Vector3.zAxis, length = maxX - minX, road = false },
		{ a = Vector3.new(maxX, 0, maxZ), dir = -Vector3.xAxis, outward = Vector3.zAxis, length = maxX - minX, road = false },
		{ a = Vector3.new(minX, 0, maxZ), dir = -Vector3.zAxis, outward = -Vector3.xAxis, length = maxZ - minZ, road = false },
		{ a = Vector3.new(maxX, 0, minZ), dir = Vector3.zAxis, outward = Vector3.xAxis, length = maxZ - minZ, road = false },
	}
	for _, edge in edges do
		local mid = edge.a + edge.dir * (edge.length / 2) + edge.outward * ROAD_HALF
		edge.road = CityLayout.onRoad(mid.X, mid.Z, -2)
	end
	return edges
end

----- Buildings -----
-- All builders take a ground-level CFrame whose -Z axis is the front (the street side).

-- Office tower: ribbon windows (or a glass curtain wall), corner columns, roof details.
function CityBuilder.tower(parent: Instance, cf: CFrame, w: number, d: number, h: number, color: Color3, glassy: boolean?, rng: Random?): Model
	local model = Instance.new("Model")
	model.Name = if glassy then "GlassTower" else "Tower"
	local trim = color:Lerp(Color3.new(0, 0, 0), 0.22)
	if glassy then
		Props.part(model, "Body", Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), Color3.fromRGB(120, 185, 235), { material = Enum.Material.Glass })
		local y = 12
		while y < h - 4 do
			Props.part(model, "Floor", Vector3.new(w + 0.5, 0.9, d + 0.5), cf * CFrame.new(0, y, 0), color)
			y += 12
		end
	else
		Props.part(model, "Body", Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), color)
		Props.part(model, "Lobby", Vector3.new(w + 0.3, 9, d + 0.3), cf * CFrame.new(0, 5.5, 0), WINDOW, { material = Enum.Material.Glass })
		local y = 18
		while y < h - 4 do
			Props.part(model, "Windows", Vector3.new(w + 0.4, 4.4, d + 0.4), cf * CFrame.new(0, y, 0), WINDOW, { material = Enum.Material.Glass })
			y += 9
		end
	end
	local cornerColor = if glassy then color else trim
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Props.part(model, "Corner", Vector3.new(2, h, 2), cf * CFrame.new(sx * (w / 2 - 0.6), h / 2, sz * (d / 2 - 0.6)), cornerColor)
		end
	end
	Props.part(model, "Roof", Vector3.new(w + 1.5, 1.2, d + 1.5), cf * CFrame.new(0, h + 0.6, 0), trim)
	Props.part(model, "Entrance", Vector3.new(8, 10, 1), cf * CFrame.new(0, 5, -d / 2 - 0.3), Color3.fromRGB(70, 75, 90))
	Props.part(model, "Canopy", Vector3.new(13, 0.8, 4.5), cf * CFrame.new(0, 10.6, -d / 2 - 2.25), trim)

	local r = rng or Random.new(math.floor(h * 13 + w))
	local roll = r:NextNumber()
	local top = cf * CFrame.new(0, h + 1.2, 0)
	if h > 150 and roll < 0.55 then
		Props.cylinder(model, "Antenna", 30, 1, (top * CFrame.new(w * 0.2, 15, 0)).Position, Color3.fromRGB(200, 200, 210))
		Props.ball(model, "Beacon", 2.2, (top * CFrame.new(w * 0.2, 30, 0)).Position, Color3.fromRGB(255, 60, 60), { material = Enum.Material.Neon })
	elseif glassy and roll < 0.8 then
		Props.cylinder(model, "Helipad", 0.4, math.min(w, d) * 0.75, (top * CFrame.new(0, 0.2, 0)).Position, Color3.fromRGB(70, 70, 80))
		Props.part(model, "HelipadH", Vector3.new(1.8, 0.1, 9), top * CFrame.new(-2.4, 0.45, 0), WHITE)
		Props.part(model, "HelipadH", Vector3.new(1.8, 0.1, 9), top * CFrame.new(2.4, 0.45, 0), WHITE)
		Props.part(model, "HelipadH", Vector3.new(3.2, 0.1, 1.8), top * CFrame.new(0, 0.45, 0), WHITE)
	elseif roll < 0.75 then
		Props.part(model, "RoofBox", Vector3.new(w * 0.35, 6, d * 0.3), top * CFrame.new(w * 0.15, 3, d * 0.1), Color3.fromRGB(190, 190, 200))
	end
	model.Parent = parent
	return model
end

-- Rooftop advertising billboard.
local function billboard(parent: Instance, top: CFrame, width: number, text: string, color: Color3)
	local w = math.min(width - 4, 30)
	for _, x in { -w / 3, w / 3 } do
		Props.part(parent, "BillboardLeg", Vector3.new(1, 7, 1), top * CFrame.new(x, 3.5, 2), DARK)
	end
	local board = Props.part(parent, "Billboard", Vector3.new(w, 9, 0.8), top * CFrame.new(0, 11.5, 2), color)
	label(board, Enum.NormalId.Front, text, WHITE, 18)
end

-- Old Town storefront: framed shop window and glazed door, awning with a valance, a sign
-- board, upper floors with separate windows, corner pilasters and rooftop clutter.
function CityBuilder.storefront(parent: Instance, cf: CFrame, w: number, d: number, floors: number, color: Color3, accent: Color3, sign: string?, rng: Random): Model
	local model = Instance.new("Model")
	model.Name = "Shop"
	local groundH, floorH = 12, 8
	local h = groundH + (floors - 1) * floorH
	local front = -d / 2
	local trim = color:Lerp(Color3.new(1, 1, 1), 0.55)
	local frame = accent:Lerp(Color3.new(0, 0, 0), 0.3)
	local glass = { material = Enum.Material.Glass }
	Props.part(model, "Body", Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), color)
	Props.part(model, "Plinth", Vector3.new(w + 0.4, 1.4, 0.8), cf * CFrame.new(0, 0.7, front - 0.2), Color3.fromRGB(75, 75, 85))
	local displayW, displayX = w - 10, -2.6
	Props.part(model, "DisplayFrame", Vector3.new(displayW + 1.2, 7, 0.4), cf * CFrame.new(displayX, 5.3, front - 0.15), frame)
	Props.part(model, "Display", Vector3.new(displayW, 6, 0.4), cf * CFrame.new(displayX, 5.3, front - 0.3), WINDOW, glass)
	Props.part(model, "Mullion", Vector3.new(0.5, 6, 0.6), cf * CFrame.new(displayX, 5.3, front - 0.4), frame)
	local doorX = w / 2 - 3.8
	Props.part(model, "DoorFrame", Vector3.new(5, 8.6, 0.4), cf * CFrame.new(doorX, 4.3, front - 0.15), frame)
	Props.part(model, "Door", Vector3.new(3.8, 7.8, 0.4), cf * CFrame.new(doorX, 3.9, front - 0.3), WINDOW, glass)
	Props.wedge(model, "Awning", Vector3.new(w - 1, 2, 4), cf * CFrame.new(0, 10.2, front - 2), accent, { collide = false })
	Props.part(model, "Valance", Vector3.new(w - 1, 0.8, 0.3), cf * CFrame.new(0, 8.9, front - 3.85), WHITE, { collide = false })
	if sign then
		local board = Props.part(model, "ShopSign", Vector3.new(math.min(w - 6, 18), 2.2, 0.5), cf * CFrame.new(0, groundH + 0.3, front - 0.35), Color3.fromRGB(45, 40, 50))
		label(board, Enum.NormalId.Front, sign, WHITE, 20)
	end
	for floor = 2, floors do
		local y = groundH + (floor - 2) * floorH + floorH / 2
		Props.part(model, "Windows", Vector3.new(w - 5, 4.4, 0.3), cf * CFrame.new(0, y + 0.4, front - 0.15), WINDOW, glass)
		Props.part(model, "Sill", Vector3.new(w - 4, 0.5, 0.9), cf * CFrame.new(0, y - 2.1, front - 0.45), trim)
		-- Wall-coloured mullions split the glass band into separate windows.
		local panes = math.max(2, math.floor((w - 5) / 7))
		for i = 1, panes - 1 do
			local x = -(w - 5) / 2 + i * (w - 5) / panes
			Props.part(model, "Mullion", Vector3.new(1.1, 4.4, 0.45), cf * CFrame.new(x, y + 0.4, front - 0.2), color)
		end
	end
	for _, side in { -1, 1 } do
		Props.part(model, "Pilaster", Vector3.new(1.6, h, 1), cf * CFrame.new(side * (w / 2 - 0.8), h / 2, front - 0.3), trim)
	end
	Props.part(model, "Cornice", Vector3.new(w + 1.4, 1.4, d + 1.4), cf * CFrame.new(0, h + 0.7, 0), accent)
	-- Rooftop clutter: a water tank or air-conditioning units.
	local roll = rng:NextNumber()
	local roof = cf * CFrame.new(0, h + 1.4, 0)
	if roll < 0.3 then
		local p = roof * CFrame.new(w * 0.2, 0, d * 0.15)
		Props.part(model, "TankStand", Vector3.new(5, 3, 5), p * CFrame.new(0, 1.5, 0), Color3.fromRGB(110, 80, 60))
		Props.cylinder(model, "WaterTank", 6, 6, (p * CFrame.new(0, 6, 0)).Position, WOOD)
		Props.ball(model, "TankTop", 6.2, (p * CFrame.new(0, 9, 0)).Position, Color3.fromRGB(110, 80, 60))
	elseif roll < 0.65 then
		for i = 1, 2 do
			Props.part(model, "AirCon", Vector3.new(4, 2.6, 3), roof * CFrame.new(-w * 0.25 + i * 5, 1.3, d * 0.1), Color3.fromRGB(200, 200, 208))
		end
	end
	model.Parent = parent
	return model
end

----- Houses -----
-- Three styles (two-storey family house, porch bungalow, flat-roofed modern house),
-- each with a front yard (path, driveway, fence or hedge, mailbox, tree, flowers) and a
-- backyard (pool, shed, swing, trampoline or barbecue patio) inside its footprint.
local HOUSE_SETBACK = 22 -- block edge (kerb) to the front wall; the lawn starts SURFACE_INSET in
local BACKYARD = 8 -- depth of the footprint kept behind the house

type HousePalette = { wall: Color3, roof: Color3, door: Color3, shutter: Color3 }
type Drive = { x: number, w: number }

local function pick<T>(list: { T }, rng: Random): T
	return list[rng:NextInteger(1, #list)]
end

-- Gable roof over a w x d box (ridge along local X) with its eaves at height y.
local function gableRoof(parent: Instance, cf: CFrame, w: number, d: number, y: number, rise: number, color: Color3)
	local overhang = 1.2
	local half = d / 2 + overhang
	local length = w + overhang * 2
	Props.wedge(parent, "RoofFront", Vector3.new(length, rise, half), cf * CFrame.new(0, y + rise / 2, -half / 2), color)
	Props.wedge(parent, "RoofBack", Vector3.new(length, rise, half), cf * CFrame.new(0, y + rise / 2, half / 2) * CFrame.Angles(0, math.pi, 0), color)
	Props.part(parent, "Ridge", Vector3.new(length + 0.4, 0.7, 1.4), cf * CFrame.new(0, y + rise, 0), color:Lerp(Color3.new(0, 0, 0), 0.25))
end

-- Framed window with a sill (and optional shutters); `at` is the window centre on a wall facing -Z.
local function houseWindow(parent: Instance, at: CFrame, w: number, h: number, shutter: Color3?)
	Props.part(parent, "WindowFrame", Vector3.new(w + 0.9, h + 0.9, 0.3), at * CFrame.new(0, 0, -0.15), HOUSE_TRIM)
	Props.part(parent, "Window", Vector3.new(w, h, 0.3), at * CFrame.new(0, 0, -0.05), WINDOW, { material = Enum.Material.Glass })
	Props.part(parent, "Sill", Vector3.new(w + 1.6, 0.45, 1), at * CFrame.new(0, -h / 2 - 0.6, -0.45), HOUSE_TRIM)
	if shutter then
		for _, side in { -1, 1 } do
			Props.part(parent, "Shutter", Vector3.new(1.5, h + 0.6, 0.3), at * CFrame.new(side * (w / 2 + 1.35), 0, -0.2), shutter)
		end
	end
end

-- Front door with frame, knob and step; `at` is on the ground at the wall.
local function houseDoor(parent: Instance, at: CFrame, color: Color3)
	Props.part(parent, "DoorFrame", Vector3.new(5.6, 9.2, 0.4), at * CFrame.new(0, 4.6, -0.2), HOUSE_TRIM)
	Props.part(parent, "Door", Vector3.new(4.2, 8, 0.4), at * CFrame.new(0, 4.4, -0.35), color)
	Props.ball(parent, "Knob", 0.5, (at * CFrame.new(1.4, 4.2, -0.65)).Position, GOLD)
	Props.part(parent, "Step", Vector3.new(6.4, 0.6, 2.6), at * CFrame.new(0, 0.3, -1.3), CONCRETE)
end

-- Two storeys, gable roof, chimney, porch or door canopy, and usually an attached garage.
local function familyHouse(model: Model, cf: CFrame, w: number, d: number, rng: Random, pal: HousePalette): (number, Drive?)
	local garageW = if w >= 30 then 11 else 0
	local side = if rng:NextNumber() < 0.5 then 1 else -1
	local mainW = w - garageW
	local m = cf * CFrame.new(-side * garageW / 2, 0, 0)
	local floorH = 10
	local h = floorH * 2
	local front = -d / 2
	Props.part(model, "Body", Vector3.new(mainW, h, d), m * CFrame.new(0, h / 2, 0), pal.wall)
	Props.part(model, "BaseBand", Vector3.new(mainW + 0.5, 1.2, d + 0.5), m * CFrame.new(0, 0.6, 0), Color3.fromRGB(150, 150, 158))
	Props.part(model, "FloorBand", Vector3.new(mainW + 0.5, 0.8, d + 0.5), m * CFrame.new(0, floorH, 0), HOUSE_TRIM)
	gableRoof(model, m, mainW, d, h, 8, pal.roof)
	Props.part(model, "Chimney", Vector3.new(2.8, 10, 2.8), m * CFrame.new(-side * mainW * 0.28, h + 5, d * 0.2), Color3.fromRGB(175, 90, 75))
	local doorX = side * mainW * 0.2
	houseDoor(model, m * CFrame.new(doorX, 0, front), pal.door)
	local windowX = -side * mainW * 0.22
	local windowW = math.min(7, mainW * 0.3)
	houseWindow(model, m * CFrame.new(windowX, 5.2, front), windowW, 4.6, pal.shutter)
	Props.flowerBed(model, m * CFrame.new(windowX, 0, front - 1.9), windowW)
	for _, fx in (if mainW >= 20 then { -0.3, 0, 0.3 } else { -0.25, 0.25 }) do
		houseWindow(model, m * CFrame.new(fx * mainW, floorH + 5, front), 4, 4.4, nil)
	end
	if rng:NextNumber() < 0.55 then
		local pw = math.min(mainW * 0.5, 16)
		Props.part(model, "PorchDeck", Vector3.new(pw, 0.8, 6), m * CFrame.new(doorX, 0.4, front - 3), WOOD, { material = Enum.Material.WoodPlanks })
		for _, s in { -1, 1 } do
			Props.part(model, "PorchColumn", Vector3.new(0.9, 8.6, 0.9), m * CFrame.new(doorX + s * (pw / 2 - 0.6), 5.1, front - 5.4), HOUSE_TRIM)
		end
		Props.wedge(model, "PorchRoof", Vector3.new(pw + 1, 1.6, 6.6), m * CFrame.new(doorX, 10.2, front - 3.1), pal.roof)
	else
		Props.wedge(model, "DoorCanopy", Vector3.new(7.5, 1.3, 3.2), m * CFrame.new(doorX, 9.9, front - 1.6), pal.roof, { collide = false })
	end
	if garageW == 0 then
		return doorX, nil
	end
	local gx = side * (w / 2 - garageW / 2)
	local gd = d * 0.8
	local g = cf * CFrame.new(gx, 0, front + gd / 2)
	Props.part(model, "Garage", Vector3.new(garageW, 10, gd), g * CFrame.new(0, 5, 0), pal.wall:Lerp(Color3.new(1, 1, 1), 0.2))
	Props.part(model, "GarageRoof", Vector3.new(garageW + 1, 1, gd + 1), g * CFrame.new(0, 10.5, 0), pal.roof)
	Props.part(model, "GarageDoor", Vector3.new(garageW - 3, 7, 0.4), g * CFrame.new(0, 3.5, -gd / 2 - 0.2), HOUSE_TRIM)
	for _, y in { 2.6, 4.8 } do
		Props.part(model, "GarageDoorLine", Vector3.new(garageW - 3.2, 0.25, 0.5), g * CFrame.new(0, y, -gd / 2 - 0.2), Color3.fromRGB(200, 200, 205))
	end
	return doorX, { x = gx, w = garageW - 2 }
end

-- One storey with a street-facing gable, a full-width porch and a gable window.
local function bungalow(model: Model, cf: CFrame, w: number, d: number, rng: Random, pal: HousePalette): (number, Drive?)
	local h = 12
	local front = -d / 2
	local side = if rng:NextNumber() < 0.5 then 1 else -1
	Props.part(model, "Body", Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), pal.wall)
	Props.part(model, "BaseBand", Vector3.new(w + 0.5, 1.2, d + 0.5), cf * CFrame.new(0, 0.6, 0), Color3.fromRGB(150, 150, 158))
	gableRoof(model, cf * CFrame.Angles(0, math.pi / 2, 0), d, w, h, 9, pal.roof)
	houseWindow(model, cf * CFrame.new(0, h + 3.2, front - 1.2), 3.4, 3.4, nil)
	Props.part(model, "Chimney", Vector3.new(2.6, 9, 2.6), cf * CFrame.new(side * w * 0.3, h + 5, d * 0.15), Color3.fromRGB(175, 90, 75))
	houseDoor(model, cf * CFrame.new(0, 0.8, front), pal.door)
	for _, s in { -1, 1 } do
		houseWindow(model, cf * CFrame.new(s * w * 0.3, 6.2, front), 6, 4.6, pal.shutter)
	end
	local porchD = 6
	Props.part(model, "PorchDeck", Vector3.new(w - 1, 0.8, porchD), cf * CFrame.new(0, 0.4, front - porchD / 2), WOOD, { material = Enum.Material.WoodPlanks })
	for _, fx in { -0.45, -0.17, 0.17, 0.45 } do
		Props.part(model, "PorchColumn", Vector3.new(1, h - 2, 1), cf * CFrame.new(fx * w, (h - 2) / 2 + 0.8, front - porchD + 0.8), HOUSE_TRIM)
	end
	for _, s in { -1, 1 } do
		Props.part(model, "PorchRail", Vector3.new(w * 0.27, 0.5, 0.4), cf * CFrame.new(s * w * 0.31, 3.8, front - porchD + 0.8), HOUSE_TRIM)
		Props.flowerBed(model, cf * CFrame.new(s * w * 0.3, 0, front - porchD - 1.8), 7)
	end
	Props.wedge(model, "PorchRoof", Vector3.new(w + 1, 2, porchD + 1), cf * CFrame.new(0, h, front - (porchD + 1) / 2), pal.roof)
	return 0, nil
end

-- Flat roofs, a cantilevered upper storey with a glass band, wood cladding and a glass wall.
local function modernHouse(model: Model, cf: CFrame, w: number, d: number, rng: Random, pal: HousePalette): (number, Drive?)
	local front = -d / 2
	local side = if rng:NextNumber() < 0.5 then 1 else -1
	local white = Color3.fromRGB(245, 245, 242)
	local charcoal = Color3.fromRGB(60, 62, 70)
	local timber = Color3.fromRGB(175, 125, 80)
	local glass = { material = Enum.Material.Glass }
	Props.part(model, "Ground", Vector3.new(w, 10, d), cf * CFrame.new(0, 5, 0), white)
	Props.part(model, "GroundRoof", Vector3.new(w + 0.8, 0.8, d + 0.8), cf * CFrame.new(0, 10.4, 0), charcoal)
	local uw, ud = w * 0.6, d * 0.85
	local ux = side * (w - uw) / 2
	local uz = front + ud / 2 - 3
	local wooden = rng:NextNumber() < 0.5
	Props.part(model, "Upper", Vector3.new(uw, 9, ud), cf * CFrame.new(ux, 15.3, uz), if wooden then timber else pal.wall,
		if wooden then { material = Enum.Material.WoodPlanks } else nil)
	Props.part(model, "UpperRoof", Vector3.new(uw + 1.6, 0.8, ud + 1.6), cf * CFrame.new(ux, 20.2, uz), charcoal)
	Props.part(model, "UpperGlass", Vector3.new(uw * 0.75, 4.6, 0.3), cf * CFrame.new(ux, 15.3, front - 3.1), WINDOW, glass)
	Props.part(model, "BalconyRail", Vector3.new(w - uw - 0.6, 3, 0.3), cf * CFrame.new(-side * uw / 2, 12.3, front + 0.2),
		Color3.fromRGB(190, 230, 250), { material = Enum.Material.Glass, transparency = 0.4 })
	local gx = -side * (w / 2 - 6.5)
	Props.part(model, "GarageDoor", Vector3.new(10, 8, 0.4), cf * CFrame.new(gx, 4, front - 0.2), charcoal)
	local doorX = -side * (w / 2 - 16)
	Props.part(model, "Cladding", Vector3.new(6.5, 10, 0.4), cf * CFrame.new(doorX, 5, front - 0.15), timber, { material = Enum.Material.WoodPlanks })
	Props.part(model, "Door", Vector3.new(4, 8.4, 0.4), cf * CFrame.new(doorX, 4.2, front - 0.35), charcoal)
	Props.part(model, "Step", Vector3.new(6.4, 0.6, 2.6), cf * CFrame.new(doorX, 0.3, front - 1.3), CONCRETE)
	local gw = w - 24
	if gw > 3 then
		local glassX = side * (w / 2 - gw / 2 - 1)
		Props.part(model, "GlassWall", Vector3.new(gw, 7.4, 0.3), cf * CFrame.new(glassX, 4.6, front - 0.15), WINDOW, glass)
		Props.part(model, "Planter", Vector3.new(gw, 1.6, 2.4), cf * CFrame.new(glassX, 0.8, front - 1.6), CONCRETE)
		Props.bush(model, (cf * CFrame.new(glassX - gw / 4, 1, front - 1.6)).Position, 0.8)
		Props.bush(model, (cf * CFrame.new(glassX + gw / 4, 1, front - 1.6)).Position, 0.8)
	end
	return doorX, { x = gx, w = 11 }
end

local function frontYard(model: Model, cf: CFrame, w: number, d: number, rng: Random, doorX: number, drive: Drive?, fence: string)
	local front = -d / 2
	local kerb = front - HOUSE_SETBACK
	local edge = kerb + SURFACE_INSET -- where the lawn meets the sidewalk
	local pathLength = front - 2.6 - edge
	Props.part(model, "Path", Vector3.new(3.4, 0.2, pathLength), cf * CFrame.new(doorX, 0.2, edge + pathLength / 2), PAVING)
	if drive then
		-- The driveway crosses the sidewalk down to the kerb.
		Props.part(model, "Driveway", Vector3.new(drive.w, 0.2, HOUSE_SETBACK), cf * CFrame.new(drive.x, 0.15, kerb + HOUSE_SETBACK / 2), Color3.fromRGB(185, 185, 190))
	end
	-- Fence, hedge or low wall along the front of the lawn, open at the path and the driveway.
	local fenceZ = edge + 1
	if fence ~= "none" then
		local gaps = { { doorX - 2.2, doorX + 2.2 } }
		if drive then
			table.insert(gaps, { drive.x - drive.w / 2 - 0.4, drive.x + drive.w / 2 + 0.4 })
		end
		table.sort(gaps, function(a, b)
			return a[1] < b[1]
		end)
		local function segment(a: number, b: number)
			if b - a < 1.5 then
				return
			end
			local mid = cf * CFrame.new((a + b) / 2, 0, fenceZ)
			if fence == "picket" then
				Props.part(model, "Fence", Vector3.new(b - a, 2.8, 0.4), mid * CFrame.new(0, 1.4, 0), HOUSE_TRIM, { material = Enum.Material.WoodPlanks })
				Props.part(model, "FenceRail", Vector3.new(b - a, 0.4, 0.7), mid * CFrame.new(0, 2.3, 0), HOUSE_TRIM)
			elseif fence == "hedge" then
				Props.part(model, "Hedge", Vector3.new(b - a, 2.6, 1.8), mid * CFrame.new(0, 1.3, 0), HEDGE)
			else
				Props.part(model, "LowWall", Vector3.new(b - a, 1.8, 1), mid * CFrame.new(0, 0.9, 0), Color3.fromRGB(205, 205, 210))
			end
		end
		local x = -w / 2 + 0.5
		for _, gap in gaps do
			segment(x, gap[1])
			x = math.max(x, gap[2])
		end
		segment(x, w / 2 - 0.5)
	end
	-- Mailbox beside the path (away from the driveway) and a tree on the lawn.
	local mailX = doorX + (if drive and drive.x > doorX then -3 else 3)
	Props.part(model, "MailboxPost", Vector3.new(0.5, 3.4, 0.5), cf * CFrame.new(mailX, 1.7, fenceZ + 1.4), WOOD)
	Props.part(model, "Mailbox", Vector3.new(1.2, 1.2, 2), cf * CFrame.new(mailX, 3.9, fenceZ + 1.4), pick(DOOR_COLORS, rng))
	local treeX = if doorX > 0 then -w / 2 + 5 else w / 2 - 5
	if not drive or math.abs(treeX - drive.x) > drive.w / 2 + 4 then
		Props.tree(model, (cf * CFrame.new(treeX, 0, edge + 6)).Position, rng:NextNumber(0.8, 1))
	end
end

local function backyard(model: Model, cf: CFrame, w: number, d: number, rng: Random, kind: string)
	local at = cf * CFrame.new(if kind == "pool" then 0 else rng:NextNumber(-w * 0.25, w * 0.25), 0, d / 2 + BACKYARD / 2)
	if kind == "pool" then
		Props.part(model, "PoolEdge", Vector3.new(w * 0.55 + 1.6, 0.3, 8), at * CFrame.new(0, 0.15, 0), Color3.fromRGB(235, 235, 240))
		Props.part(model, "Pool", Vector3.new(w * 0.55, 0.32, 6.4), at * CFrame.new(0, 0.2, 0), Color3.fromRGB(70, 190, 245), { material = Enum.Material.Glass, transparency = 0.1 })
	elseif kind == "shed" then
		Props.part(model, "Shed", Vector3.new(7, 7, 6), at * CFrame.new(0, 3.5, 0), Color3.fromRGB(160, 120, 85), { material = Enum.Material.WoodPlanks })
		gableRoof(model, at, 7, 6, 7, 2.4, Color3.fromRGB(90, 90, 100))
	elseif kind == "swing" then
		local blue = Color3.fromRGB(80, 160, 230)
		Props.part(model, "SwingBar", Vector3.new(9, 0.6, 0.6), at * CFrame.new(0, 7, 0), blue)
		for _, x in { -4.2, 4.2 } do
			Props.part(model, "SwingLeg", Vector3.new(0.5, 7, 0.5), at * CFrame.new(x, 3.5, 0), blue)
		end
		Props.part(model, "SwingSeat", Vector3.new(2, 0.3, 1.2), at * CFrame.new(0, 2.4, 0), Color3.fromRGB(255, 200, 60))
	elseif kind == "trampoline" then
		Props.cylinder(model, "TrampolineFrame", 2, 9, (at * CFrame.new(0, 1, 0)).Position, Color3.fromRGB(60, 140, 230))
		Props.cylinder(model, "TrampolineMat", 2.1, 8, (at * CFrame.new(0, 1, 0)).Position, Color3.fromRGB(40, 40, 45))
	else -- barbecue patio
		Props.part(model, "Patio", Vector3.new(12, 0.25, 8), at * CFrame.new(0, 0.15, 0), PAVING)
		Props.part(model, "Grill", Vector3.new(2.6, 3, 1.6), at * CFrame.new(-3, 1.5, 1), DARK)
		Props.cylinder(model, "PatioTable", 2.6, 4, (at * CFrame.new(2, 1.3, 0)).Position, WHITE)
	end
end

-- Footprint: w along the street, d deep (front yard excluded, backyard included).
function CityBuilder.house(parent: Instance, footprint: CFrame, w: number, d: number, rng: Random): Model
	local model = Instance.new("Model")
	model.Name = "House"
	local bodyD = d - BACKYARD
	local cf = footprint * CFrame.new(0, 0, -BACKYARD / 2)
	local pal: HousePalette = {
		wall = pick(HOUSE_WALLS, rng), roof = pick(HOUSE_ROOFS, rng),
		door = pick(DOOR_COLORS, rng), shutter = pick(SHUTTER_COLORS, rng),
	}
	local roll = rng:NextNumber()
	local doorX: number, drive: Drive?, fence: string, yardItem: string = 0, nil, "none", "patio"
	if roll < 0.45 then
		doorX, drive = familyHouse(model, cf, w, bodyD, rng, pal)
		fence = if rng:NextNumber() < 0.6 then "picket" else "hedge"
		yardItem = pick({ "shed", "swing", "patio", "trampoline" }, rng)
	elseif roll < 0.75 then
		doorX, drive = bungalow(model, cf, w, bodyD, rng, pal)
		fence = if rng:NextNumber() < 0.7 then "picket" else "none"
		yardItem = pick({ "swing", "patio", "trampoline", "shed" }, rng)
	else
		doorX, drive = modernHouse(model, cf, w, bodyD, rng, pal)
		fence = "lowwall"
		yardItem = if rng:NextNumber() < 0.7 then "pool" else "patio"
	end
	frontYard(model, cf, w, bodyD, rng, doorX, drive, fence)
	backyard(model, cf, w, bodyD, rng, yardItem)
	model.Parent = parent
	return model
end

-- Harbor warehouse with a gable roof and a big roller door.
function CityBuilder.warehouse(parent: Instance, cf: CFrame, w: number, d: number, h: number, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "Warehouse"
	Props.part(model, "Body", Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), color)
	local roof = color:Lerp(Color3.new(0, 0, 0), 0.3)
	Props.wedge(model, "RoofA", Vector3.new(w + 1, 6, d / 2 + 0.5), cf * CFrame.new(0, h + 3, -d / 4 - 0.25), roof)
	Props.wedge(model, "RoofB", Vector3.new(w + 1, 6, d / 2 + 0.5), cf * CFrame.new(0, h + 3, d / 4 + 0.25) * CFrame.Angles(0, math.pi, 0), roof)
	Props.part(model, "RollerDoor", Vector3.new(w * 0.45, math.min(h * 0.6, 16), 0.4), cf * CFrame.new(-w * 0.15, math.min(h * 0.3, 8), -d / 2 - 0.2), Color3.fromRGB(150, 155, 165))
	Props.part(model, "OfficeDoor", Vector3.new(4, 8, 0.4), cf * CFrame.new(w * 0.3, 4, -d / 2 - 0.2), Color3.fromRGB(70, 110, 170))
	Props.part(model, "OfficeWindows", Vector3.new(w * 0.3, 3.4, 0.3), cf * CFrame.new(w * 0.3, h * 0.6, -d / 2 - 0.15), WINDOW, { material = Enum.Material.Glass })
	Props.part(model, "Stripe", Vector3.new(w + 0.3, 1.6, d + 0.3), cf * CFrame.new(0, h - 2, 0), WHITE)
	model.Parent = parent
	return model
end

----- Fill styles: what lines the streets of each district -----
type FillStyle = {
	minW: number, maxW: number, minD: number, maxD: number,
	setback: number, -- distance from the block edge (keeps the sidewalk clear)
	gap: number, -- spacing between neighbours along the street
	build: (Instance, CFrame, number, number, Random) -> (),
}

local signIndex = 0
local FILL: { [string]: FillStyle } = {
	shops = {
		minW = 18, maxW = 28, minD = 16, maxD = 24, setback = 11, gap = 0.5,
		build = function(parent, cf, w, d, rng)
			signIndex += 1
			local sign = if rng:NextNumber() < 0.8 then SHOP_NAMES[(signIndex % #SHOP_NAMES) + 1] else nil
			CityBuilder.storefront(parent, cf, w, d, rng:NextInteger(2, 3), pick(SHOP_COLORS, rng), pick(AWNING_COLORS, rng), sign, rng)
		end,
	},
	houses = {
		minW = 30, maxW = 36, minD = 30, maxD = 34, setback = HOUSE_SETBACK, gap = 8,
		build = function(parent, cf, w, d, rng)
			CityBuilder.house(parent, cf, w, d, rng)
		end,
	},
	towers = {
		minW = 24, maxW = 36, minD = 22, maxD = 32, setback = 11, gap = 2,
		build = function(parent, cf, w, d, rng)
			local h = rng:NextInteger(6, 15) * 9
			local model = CityBuilder.tower(parent, cf, w, d, h, pick(TOWER_COLORS, rng), rng:NextNumber() < 0.2, rng)
			if rng:NextNumber() < 0.25 then
				billboard(model, cf * CFrame.new(0, h + 1.2, 0), w, pick(BILLBOARDS, rng), pick(AWNING_COLORS, rng))
			end
		end,
	},
	luxury = {
		minW = 30, maxW = 42, minD = 28, maxD = 36, setback = 12, gap = 6,
		build = function(parent, cf, w, d, rng)
			local h = rng:NextInteger(8, 18) * 9
			CityBuilder.tower(parent, cf, w, d, h, pick(LUXURY_COLORS, rng), rng:NextNumber() < 0.5, rng)
		end,
	},
	glass = {
		minW = 30, maxW = 44, minD = 28, maxD = 40, setback = 11, gap = 4,
		build = function(parent, cf, w, d, rng)
			local h = rng:NextInteger(9, 18) * 12
			CityBuilder.tower(parent, cf, w, d, h, pick(GLASS_TRIMS, rng), true, rng)
		end,
	},
	harbor = {
		minW = 24, maxW = 36, minD = 18, maxD = 26, setback = 11, gap = 3,
		build = function(parent, cf, w, d, rng)
			CityBuilder.warehouse(parent, cf, w, d, rng:NextInteger(14, 22), pick(WAREHOUSE_COLORS, rng))
		end,
	},
}

-- Lines the block's edges (street sides first) with buildings, skipping anything that
-- would overlap a reserved area (business lot, park, landmark) or another building.
local function fillBlock(parent: Instance, block: { any }, style: FillStyle, reserved: { Rect }, placed: { Rect }, rng: Random)
	local inner = box(block[1] + 2, block[2] - 2, block[3] + 2, block[4] - 2)
	local edges = blockEdges(block)
	table.sort(edges, function(a, b)
		return a.road and not b.road
	end)
	local function fits(footprint: Rect): boolean
		if footprint.minX < inner.minX or footprint.maxX > inner.maxX or footprint.minZ < inner.minZ or footprint.maxZ > inner.maxZ then
			return false
		end
		for _, r in reserved do
			if overlaps(footprint, r, 1) then
				return false
			end
		end
		for _, r in placed do
			if overlaps(footprint, r, 0.8) then
				return false
			end
		end
		return true
	end
	for _, edge in edges do
		local s = 3
		while s < edge.length - 3 - style.minW do
			local w = rng:NextInteger(style.minW, style.maxW)
			if s + w > edge.length - 3 then
				w = math.floor(edge.length - 3 - s)
			end
			local built = false
			for attempt = 1, 2 do
				local d = if attempt == 1 then rng:NextInteger(style.minD, style.maxD) else style.minD
				local center = edge.a + edge.dir * (s + w / 2) - edge.outward * (style.setback + d / 2)
				local footprint = if math.abs(edge.dir.X) > 0.5
					then around(center.X, center.Z, w / 2, d / 2)
					else around(center.X, center.Z, d / 2, w / 2)
				if fits(footprint) then
					local base = Vector3.new(center.X, CURB, center.Z)
					style.build(parent, CFrame.lookAt(base, base + edge.outward), w, d, rng)
					table.insert(placed, footprint)
					built = true
					break
				end
			end
			s += if built then w + style.gap else 4
		end
	end
end

-- Trees (or crates in the harbor) in whatever space is left inside a block.
local function courtyard(parent: Instance, block: { any }, reserved: { Rect }, placed: { Rect }, rng: Random, wanted: number, harbor: boolean)
	local planted = 0
	for _ = 1, wanted * 5 do
		if planted >= wanted then
			break
		end
		local x = rng:NextNumber(block[1] + 14, block[2] - 14)
		local z = rng:NextNumber(block[3] + 14, block[4] - 14)
		local spot = around(x, z, 5, 5)
		local free = true
		for _, r in reserved do
			if overlaps(spot, r, 1) then
				free = false
				break
			end
		end
		if free then
			for _, r in placed do
				if overlaps(spot, r, 1.5) then
					free = false
					break
				end
			end
		end
		if free then
			local ground = Vector3.new(x, TOP, z)
			if harbor then
				Props.part(parent, "Crate", Vector3.new(5, 5, 5), CFrame.new(ground + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, rng:NextNumber(0, 1.5), 0), WOOD, { material = Enum.Material.WoodPlanks })
				Props.cylinder(parent, "Barrel", 3.6, 2.6, ground + Vector3.new(4.2, 1.8, 1), Color3.fromRGB(60, 110, 170))
			elseif rng:NextNumber() < 0.55 then
				Props.tree(parent, ground, rng:NextNumber(0.9, 1.15))
			else
				Props.pine(parent, ground, rng:NextNumber(0.9, 1.15))
			end
			table.insert(placed, spot)
			planted += 1
		end
	end
end

----- Business entrance (shared) -----
-- Human-sized doorway: about twice a character's height.
local DOOR_W, DOOR_H, VESTIBULE = 8, 10, 8

local function roofProp(model: Model, definition: Businesses.Definition, top: CFrame)
	local t = definition.theme
	local style = definition.roofStyle or definition.stationStyle
	local cylinder = Enum.PartType.Cylinder
	local up = CFrame.Angles(0, 0, math.pi / 2) -- turns a cylinder's X axis to Y
	local function at(x: number, y: number, z: number): Vector3
		return (top * CFrame.new(x, y, z)).Position
	end
	if style == "oven" then
		local disc = top * CFrame.new(0, 9, 0) * CFrame.Angles(math.rad(-28), 0, 0)
		Props.part(model, "Stand", Vector3.new(1, 8, 1), top * CFrame.new(0, 4, 0), Color3.fromRGB(80, 80, 90))
		Props.part(model, "Crust", Vector3.new(1.6, 18, 18), disc * up, Color3.fromRGB(235, 180, 95), { shape = cylinder })
		Props.part(model, "Sauce", Vector3.new(1.7, 16, 16), disc * CFrame.new(0, 0.1, 0) * up, Color3.fromRGB(215, 60, 40), { shape = cylinder })
		Props.part(model, "Cheese", Vector3.new(1.8, 14.5, 14.5), disc * CFrame.new(0, 0.15, 0) * up, Color3.fromRGB(255, 210, 90), { shape = cylinder })
		for i = 1, 7 do
			local angle = i / 7 * math.pi * 2
			local radius = if i % 2 == 0 then 4.5 else 2.3
			Props.part(model, "Pepperoni", Vector3.new(2, 3, 3), disc * CFrame.new(math.cos(angle) * radius, 0.25, math.sin(angle) * radius) * up, Color3.fromRGB(180, 40, 35), { shape = cylinder })
		end
	elseif style == "espresso" then
		local base = top * CFrame.new(0, 5, 0)
		Props.part(model, "Cup", Vector3.new(9, 8, 8), base * up, Color3.fromRGB(250, 250, 250), { shape = cylinder })
		Props.part(model, "Coffee", Vector3.new(0.4, 7.2, 7.2), base * CFrame.new(0, 4.4, 0) * up, Color3.fromRGB(110, 65, 40), { shape = cylinder })
		Props.part(model, "Band", Vector3.new(2.5, 8.2, 8.2), base * up, t.primary, { shape = cylinder })
		Props.part(model, "Handle", Vector3.new(1, 5, 3.5), base * CFrame.new(5, 0.5, 0), Color3.fromRGB(250, 250, 250))
		for i = 1, 3 do
			Props.ball(model, "Steam", 2.4 - i * 0.4, (base * CFrame.new(math.sin(i) * 1.2, 5 + i * 2.2, 0)).Position, WHITE, { transparency = 0.35, collide = false })
		end
	elseif style == "rack" then
		local base = top * CFrame.new(0, 7, 0)
		Props.part(model, "Shirt", Vector3.new(7, 9, 1.2), base, t.primary)
		Props.part(model, "SleeveL", Vector3.new(3.5, 3, 1.2), base * CFrame.new(-4.6, 2.6, 0) * CFrame.Angles(0, 0, math.rad(30)), t.primary)
		Props.part(model, "SleeveR", Vector3.new(3.5, 3, 1.2), base * CFrame.new(4.6, 2.6, 0) * CFrame.Angles(0, 0, math.rad(-30)), t.primary)
		Props.part(model, "Collar", Vector3.new(3, 1, 1.4), base * CFrame.new(0, 4.4, 0), t.secondary)
		Props.part(model, "Stand", Vector3.new(1, 3, 1), top * CFrame.new(0, 1.5, 0), Color3.fromRGB(80, 80, 90))
	elseif style == "shelf" then
		local base = top * CFrame.new(0, 4, 0)
		local metal = Color3.fromRGB(200, 205, 215)
		Props.part(model, "Basket", Vector3.new(12, 6, 7), base * CFrame.new(0, 2, 0), metal)
		Props.part(model, "BasketTrim", Vector3.new(12.4, 1, 7.4), base * CFrame.new(0, 5, 0), t.primary)
		Props.part(model, "Handle", Vector3.new(1, 1, 8), base * CFrame.new(7, 6, 0), t.primary)
		for _, x in { -4.5, 4.5 } do
			for _, z in { -2.5, 2.5 } do
				Props.part(model, "Wheel", Vector3.new(1, 2, 2), base * CFrame.new(x, -1.5, z), Color3.fromRGB(40, 40, 45), { shape = cylinder })
			end
		end
	elseif style == "treadmill" then
		local base = top * CFrame.new(0, 5, 0)
		Props.part(model, "Bar", Vector3.new(16, 1.2, 1.2), base, Color3.fromRGB(200, 200, 210), { shape = cylinder })
		for _, x in { -6.5, 6.5 } do
			Props.part(model, "Plate", Vector3.new(2, 8, 8), base * CFrame.new(x, 0, 0), DARK, { shape = cylinder })
			Props.part(model, "PlateTrim", Vector3.new(2.2, 5, 5), base * CFrame.new(x, 0, 0), t.accent, { shape = cylinder })
		end
		Props.part(model, "Stand", Vector3.new(1, 4, 1), top * CFrame.new(0, 2, 0), DARK)
	elseif style == "car" then
		local car = Props.car(model, t.primary, true)
		car:PivotTo(top * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, math.rad(35), 0))
		Props.part(model, "Turntable", Vector3.new(1, 18, 18), top * CFrame.new(0, 0.5, 0) * up, Color3.fromRGB(230, 230, 235), { shape = cylinder })
	elseif style == "desk" then
		local board = Props.part(model, "HotelSign", Vector3.new(26, 7, 1), top * CFrame.new(0, 6, -10), t.accent)
		label(board, Enum.NormalId.Front, "★ HOTEL ★", Color3.fromRGB(255, 220, 90), 20)
		Props.part(model, "SignLegs", Vector3.new(20, 3, 0.8), top * CFrame.new(0, 1.5, -10), Color3.fromRGB(60, 60, 70))
	elseif style == "kiosk" then
		Props.ball(model, "Dome", 30, at(0, -4, 0), Color3.fromRGB(150, 220, 240), { material = Enum.Material.Glass, transparency = 0.35 })
	elseif style == "cake" then
		Props.cylinder(model, "CakeBottom", 5, 16, at(0, 2.5, 0), Color3.fromRGB(250, 225, 180))
		Props.cylinder(model, "Icing", 1, 16.6, at(0, 5.3, 0), Color3.fromRGB(255, 160, 200))
		Props.cylinder(model, "CakeTop", 4, 11, at(0, 7.8, 0), Color3.fromRGB(250, 225, 180))
		Props.cylinder(model, "TopIcing", 0.8, 11.6, at(0, 10.1, 0), WHITE)
		Props.ball(model, "Cherry", 2.6, at(0, 11.6, 0), Color3.fromRGB(220, 30, 50))
		for i = 1, 3 do
			local angle = i * 2.1
			Props.cylinder(model, "Candle", 2.6, 0.7, at(math.cos(angle) * 3.6, 11.8, math.sin(angle) * 3.6), Color3.fromRGB(120, 200, 255))
		end
	elseif style == "cone" then
		local waffle = Color3.fromRGB(215, 160, 90)
		Props.cylinder(model, "ConeTip", 3, 2, at(0, 1.5, 0), waffle)
		Props.cylinder(model, "ConeMid", 3, 4.5, at(0, 4.5, 0), waffle)
		Props.cylinder(model, "ConeTop", 3, 7, at(0, 7.5, 0), waffle)
		Props.ball(model, "Scoop", 9, at(0, 11.5, 0), Color3.fromRGB(255, 160, 200))
		Props.ball(model, "Scoop2", 7.5, at(0, 16.5, 0), Color3.fromRGB(160, 235, 200))
		Props.ball(model, "Cherry", 2, at(0, 20.6, 0), Color3.fromRGB(220, 30, 50))
	elseif style == "bone" then
		local bone = Color3.fromRGB(250, 245, 230)
		local base = top * CFrame.new(0, 8, 0) * CFrame.Angles(0, 0, math.rad(12))
		Props.part(model, "Stand", Vector3.new(1.2, 7, 1.2), top * CFrame.new(0, 3.5, 0), DARK)
		Props.part(model, "BoneShaft", Vector3.new(14, 2.8, 2.8), base, bone)
		for _, x in { -7, 7 } do
			for _, y in { -1.6, 1.6 } do
				Props.ball(model, "BoneEnd", 4.4, (base * CFrame.new(x, y, 0)).Position, bone)
			end
		end
	elseif style == "burger" then
		Props.cylinder(model, "BunBottom", 3, 15, at(0, 1.5, 0), Color3.fromRGB(225, 160, 80))
		Props.cylinder(model, "Patty", 2.4, 16, at(0, 4.2, 0), Color3.fromRGB(110, 60, 35))
		Props.part(model, "Cheese", Vector3.new(14, 0.7, 14), top * CFrame.new(0, 5.6, 0) * CFrame.Angles(0, math.rad(45), 0), Color3.fromRGB(255, 205, 50))
		Props.cylinder(model, "Lettuce", 0.9, 16.6, at(0, 6.3, 0), Color3.fromRGB(110, 200, 70))
		Props.ball(model, "BunTop", 15, at(0, 7.6, 0), Color3.fromRGB(230, 165, 80))
		for i = 1, 3 do
			Props.ball(model, "Seed", 1.1, at(math.cos(i * 2.1) * 3, 14.6, math.sin(i * 2.1) * 3), Color3.fromRGB(255, 250, 230))
		end
	elseif style == "phone" then
		local base = top * CFrame.new(0, 12, 0) * CFrame.Angles(math.rad(-10), math.rad(18), 0)
		Props.part(model, "Stand", Vector3.new(6, 1.2, 6), top * CFrame.new(0, 0.6, 0), DARK)
		Props.part(model, "PhoneNeck", Vector3.new(1.4, 2.4, 1.4), top * CFrame.new(0, 2, 0), DARK)
		Props.part(model, "PhoneBody", Vector3.new(11, 20, 1.4), base, Color3.fromRGB(40, 42, 55))
		local screen = Props.part(model, "PhoneScreen", Vector3.new(9.6, 17, 0.2), base * CFrame.new(0, 0.2, -0.75), t.primary, { material = Enum.Material.Neon })
		label(screen, Enum.NormalId.Front, "📱", WHITE, 8)
	elseif style == "fish" then
		local fish = t.accent
		local base = top * CFrame.new(0, 11, 0)
		Props.part(model, "Stand", Vector3.new(1.2, 7, 1.2), top * CFrame.new(0, 3.5, 0), DARK)
		Props.part(model, "FishBody", Vector3.new(14, 8, 8), base, fish, { shape = cylinder })
		Props.ball(model, "Nose", 8, (base * CFrame.new(-7, 0, 0)).Position, fish)
		Props.part(model, "TailTop", Vector3.new(6, 2, 1), base * CFrame.new(9, 2, 0) * CFrame.Angles(0, 0, math.rad(35)), fish)
		Props.part(model, "TailBottom", Vector3.new(6, 2, 1), base * CFrame.new(9, -2, 0) * CFrame.Angles(0, 0, math.rad(-35)), fish)
		Props.part(model, "Fin", Vector3.new(5, 3, 0.8), base * CFrame.new(0, 4.6, 0) * CFrame.Angles(0, 0, math.rad(-20)), fish:Lerp(Color3.new(1, 1, 1), 0.2))
		Props.ball(model, "Eye", 2.6, (base * CFrame.new(-8.4, 1.4, -2.6)).Position, WHITE)
		Props.ball(model, "Pupil", 1.3, (base * CFrame.new(-8.9, 1.4, -3.4)).Position, Color3.fromRGB(20, 20, 25))
	elseif style == "aquadome" then
		Props.ball(model, "Dome", 32, at(0, -4, 0), Color3.fromRGB(120, 210, 245), { material = Enum.Material.Glass, transparency = 0.3 })
		local colours = { Color3.fromRGB(255, 140, 40), Color3.fromRGB(255, 230, 60), Color3.fromRGB(255, 90, 140) }
		for i = 1, 3 do
			Props.part(model, "DomeFish", Vector3.new(3, 1.6, 0.6), top * CFrame.new(-6 + i * 3.5, 2 + (i % 2) * 3, -4 + i * 2), colours[i], { collide = false })
		end
		Props.cylinder(model, "Spire", 6, 1, at(0, 14, 0), WHITE)
		Props.ball(model, "SpireTop", 2.4, at(0, 17.5, 0), t.accent)
	elseif style == "satellite" then
		local metal = Color3.fromRGB(205, 210, 220)
		Props.part(model, "DishBase", Vector3.new(8, 3, 8), top * CFrame.new(-16, 1.5, 0), DARK)
		Props.cylinder(model, "Mast", 6, 1.2, at(-16, 6, 0), metal)
		local aim = Vector3.new(0, 0.82, -0.57)
		Props.part(model, "Dish", Vector3.new(1, 16, 16), top * CFrame.fromMatrix(Vector3.new(-16, 10, 0), aim, Vector3.xAxis), metal, { shape = cylinder })
		Props.ball(model, "Receiver", 1.6, (top * CFrame.new(Vector3.new(-16, 10, 0) + aim * 5)).Position, t.accent, { material = Enum.Material.Neon })
		local cube = Props.part(model, "LogoCube", Vector3.new(10, 10, 10), top * CFrame.new(14, 5, 0), t.primary)
		label(cube, Enum.NormalId.Front, definition.emoji, WHITE, 10)
	elseif style == "book" then
		-- A stack of giant books with an open one on top.
		local colours = { t.primary, t.accent, Color3.fromRGB(200, 70, 70) }
		for i, colour in colours do
			local cover = top * CFrame.new(0, 1 + (i - 1) * 2.4, 0) * CFrame.Angles(0, math.rad(i * 9 - 12), 0)
			Props.part(model, "BookCover", Vector3.new(14, 2.2, 10), cover, colour)
			Props.part(model, "BookPages", Vector3.new(13.4, 1.8, 9), cover * CFrame.new(0.4, 0, 0), Color3.fromRGB(250, 245, 230))
		end
		local open = top * CFrame.new(0, 8.6, 0)
		for _, side in { -1, 1 } do
			Props.part(model, "OpenPage", Vector3.new(6.5, 0.6, 9), open * CFrame.new(side * 3.3, 0.6, 0) * CFrame.Angles(0, 0, math.rad(side * -12)), WHITE)
		end
	elseif style == "surfboard" then
		for i, colour in { t.primary, t.accent, Color3.fromRGB(255, 220, 80) } do
			local board = top * CFrame.new((i - 2) * 5, 9, 0) * CFrame.Angles(0, 0, math.rad((i - 2) * -14))
			Props.part(model, "Surfboard", Vector3.new(3.6, 18, 0.8), board, colour)
			Props.part(model, "BoardStripe", Vector3.new(0.8, 17, 0.9), board, WHITE)
			Props.ball(model, "BoardTip", 3.6, (board * CFrame.new(0, 9, 0)).Position, colour)
		end
		Props.part(model, "BoardStand", Vector3.new(16, 1.2, 4), top * CFrame.new(0, 0.6, 0), DARK)
	elseif style == "toy" then
		-- Toy blocks and a teddy bear.
		for i, letter in { "A", "B", "C" } do
			local colour = ({ t.primary, t.accent, t.roof })[i]
			local spot = if i == 3 then top * CFrame.new(-6, 7.5, 0) else top * CFrame.new(-10 + (i - 1) * 7, 2.5, 0)
			local cube = Props.part(model, "ToyBlock", Vector3.new(5, 5, 5), spot * CFrame.Angles(0, math.rad(i * 11), 0), colour)
			label(cube, Enum.NormalId.Front, letter, WHITE, 10)
		end
		local fur = Color3.fromRGB(190, 130, 80)
		Props.ball(model, "TeddyBody", 8, at(8, 4.5, 0), fur)
		Props.ball(model, "TeddyHead", 6, at(8, 10.5, 0), fur)
		for _, x in { -2.4, 2.4 } do
			Props.ball(model, "TeddyEar", 2.4, at(8 + x, 13.4, 0), fur)
		end
		Props.ball(model, "TeddySnout", 2.4, at(8, 10, -2.6), Color3.fromRGB(240, 210, 170))
	elseif style == "sushi" then
		-- A giant salmon roll on a plate.
		local base = top * CFrame.new(0, 0, 0)
		Props.cylinder(model, "Plate", 1, 22, at(0, 0.5, 0), WHITE)
		for i, x in { -5.5, 5.5 } do
			local roll = base * CFrame.new(x, 4, 0)
			Props.part(model, "Nori", Vector3.new(6, 9, 9), roll * up, Color3.fromRGB(35, 45, 40), { shape = cylinder })
			Props.part(model, "Rice", Vector3.new(6.2, 7.6, 7.6), roll * up, WHITE, { shape = cylinder })
			Props.part(model, "Salmon", Vector3.new(6.4, 3.6, 3.6), roll * up, Color3.fromRGB(255, 140, 90), { shape = cylinder })
			Props.ball(model, "Roe", 1.4, (roll * CFrame.new(0, 3.6, i - 1.5)).Position, Color3.fromRGB(255, 90, 50))
		end
	elseif style == "joystick" then
		Props.part(model, "JoyBase", Vector3.new(14, 4, 10), top * CFrame.new(0, 2, 0), Color3.fromRGB(40, 40, 50))
		Props.part(model, "JoyTrim", Vector3.new(14.4, 0.8, 10.4), top * CFrame.new(0, 4.2, 0), t.accent, { material = Enum.Material.Neon })
		Props.cylinder(model, "Stick", 8, 1.4, at(-3, 8, 0), Color3.fromRGB(60, 60, 70))
		Props.ball(model, "StickBall", 4.4, at(-3, 12.4, 0), t.primary)
		for i, colour in { Color3.fromRGB(255, 70, 70), Color3.fromRGB(255, 220, 60) } do
			Props.cylinder(model, "Button", 1, 2.6, at(2 + i * 2.6, 4.9, 0), colour)
		end
	elseif style == "popcorn" then
		-- Striped popcorn bucket, overflowing.
		for i = 0, 5 do
			local angle = i / 6 * math.pi * 2
			Props.part(model, "BucketStripe", Vector3.new(3.2, 12, 0.6), top * CFrame.new(math.cos(angle) * 5, 6, math.sin(angle) * 5) * CFrame.Angles(0, -angle + math.pi / 2, 0),
				if i % 2 == 0 then t.primary else WHITE)
		end
		Props.cylinder(model, "BucketInside", 11.6, 9.4, at(0, 6, 0), WHITE)
		for i = 1, 9 do
			local angle = i * 2.4
			local radius = if i % 3 == 0 then 0 else 3.2
			Props.ball(model, "Popcorn", 3, at(math.cos(angle) * radius, 12.4 + (i % 3) * 0.9, math.sin(angle) * radius), Color3.fromRGB(255, 245, 200))
		end
	elseif style == "spa" then
		-- Stacked spa stones with a leaf and a candle.
		local stone = Color3.fromRGB(110, 115, 120)
		for i, width in { 12, 10, 8, 6 } do
			Props.cylinder(model, "SpaStone", 2.4, width, at(0, 1.2 + (i - 1) * 2.4, 0), stone:Lerp(WHITE, i * 0.08))
		end
		Props.part(model, "Leaf", Vector3.new(0.4, 6, 3), top * CFrame.new(3, 11, 0) * CFrame.Angles(0, 0, math.rad(-35)), t.primary)
		Props.cylinder(model, "Candle", 3, 2, at(-6, 1.5, 4), Color3.fromRGB(255, 245, 230))
		Props.ball(model, "Flame", 1, at(-6, 3.6, 4), Color3.fromRGB(255, 190, 60), { material = Enum.Material.Neon, collide = false })
	elseif style == "diamond" then
		Props.part(model, "Stand", Vector3.new(6, 2, 6), top * CFrame.new(0, 1, 0), t.primary)
		local gem = top * CFrame.new(0, 9, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45))
		Props.part(model, "Diamond", Vector3.new(8, 8, 8), gem, t.accent, { material = Enum.Material.Glass, transparency = 0.15 })
		Props.ball(model, "Sparkle", 2, at(4, 14, -2), WHITE, { material = Enum.Material.Neon, collide = false })
	elseif style == "coin" then
		local gold = Color3.fromRGB(245, 200, 60)
		local face = top * CFrame.new(0, 11, 0) * CFrame.Angles(0, math.rad(90), 0)
		Props.part(model, "Stand", Vector3.new(4, 3, 4), top * CFrame.new(0, 1.5, 0), DARK)
		Props.part(model, "GoldCoin", Vector3.new(2, 18, 18), face, gold, { shape = cylinder, material = Enum.Material.Metal })
		local sign = Props.part(model, "CoinFace", Vector3.new(0.2, 12, 12), face * CFrame.new(-1.1, 0, 0), gold:Lerp(Color3.new(1, 1, 1), 0.2))
		label(sign, Enum.NormalId.Left, "$", Color3.fromRGB(150, 110, 20), 10)
	end
end

function CityBuilder.buildBusiness(parent: Instance, definition: Businesses.Definition): Model
	local model = Instance.new("Model")
	model.Name = definition.id
	model:SetAttribute("BusinessId", definition.id)
	local t = definition.theme
	local w, h, d = definition.lot.size.X, definition.lot.size.Y, definition.lot.size.Z
	local B = CFrame.new(definition.lot.position.X, CURB, definition.lot.position.Z) * CFrame.Angles(0, math.rad(definition.lot.yaw), 0)
	local function at(x: number, y: number, z: number): CFrame
		return B * CFrame.new(x, y, z)
	end
	local front = -d / 2
	local sideW = w / 2 - DOOR_W / 2
	local sideX = DOOR_W / 2 + sideW / 2

	-- Shell: solid masses around a recessed doorway (players never walk inside the shell).
	local shell = Instance.new("Model")
	shell.Name = "Shell"
	shell.Parent = model
	Props.part(shell, "WallLeft", Vector3.new(sideW, h, d), at(-sideX, h / 2, 0), t.secondary)
	Props.part(shell, "WallRight", Vector3.new(sideW, h, d), at(sideX, h / 2, 0), t.secondary)
	Props.part(shell, "WallTop", Vector3.new(DOOR_W, h - DOOR_H, d), at(0, DOOR_H + (h - DOOR_H) / 2, 0), t.secondary)
	Props.part(shell, "WallBack", Vector3.new(DOOR_W, DOOR_H, d - VESTIBULE), at(0, DOOR_H / 2, front + VESTIBULE + (d - VESTIBULE) / 2), t.secondary)
	Props.part(shell, "Trim", Vector3.new(w + 1.2, 2.4, d + 1.2), at(0, h + 0.2, 0), t.primary)
	Props.part(shell, "Roof", Vector3.new(w + 2, 1.2, d + 2), at(0, h + 1.8, 0), t.roof)
	for _, side in { -1, 1 } do
		Props.part(shell, "BaseStripe", Vector3.new(sideW, 3, 0.6), at(side * sideX, 1.5, front - 0.3), t.primary)
		Props.part(shell, "DisplayWindow", Vector3.new(sideW - 6, 6, 0.4), at(side * sideX, 6, front - 0.25), WINDOW, { material = Enum.Material.Glass, transparency = 0.1 })
		Props.part(shell, "WindowSill", Vector3.new(sideW - 5, 0.6, 1.2), at(side * sideX, 2.9, front - 0.6), t.primary)
		Props.flowerBed(shell, at(side * sideX, 0, front - 2.2), math.max(4, sideW - 10))
	end
	-- Upper floors for tall buildings (hotel, mall, tech company).
	if h >= 30 then
		local y = DOOR_H + 12
		while y < h - 4 do
			Props.part(shell, "UpperWindows", Vector3.new(w + 0.4, 3.8, d + 0.4), at(0, y, 0), WINDOW, { material = Enum.Material.Glass, transparency = 0.05 })
			y += 8
		end
	end

	-- Striped awning over the front.
	local stripes = math.max(4, math.floor(w / 4))
	local stripeW = w / stripes
	for i = 1, stripes do
		local x = -w / 2 + (i - 0.5) * stripeW
		Props.wedge(shell, "Awning", Vector3.new(stripeW, 2.4, 4.5), at(x, DOOR_H + 1.5, front - 2.25),
			if i % 2 == 0 then Color3.fromRGB(255, 255, 255) else t.primary, { collide = false })
	end

	-- Name sign.
	local signY = math.min(h - 3.6, DOOR_H + 7.2)
	local sign = Props.part(model, "NameSign", Vector3.new(math.min(w * 0.75, 44), 5.5, 1), at(0, signY, front - 0.6), t.primary)
	label(sign, Enum.NormalId.Front, definition.emoji .. " " .. definition.name:upper(), Color3.fromRGB(255, 255, 255), 25)

	-- Doorway: frame, glass door (the physical entrance), status light, portal glow.
	Props.part(model, "FrameL", Vector3.new(1, DOOR_H + 1, 1.4), at(-(DOOR_W / 2 + 0.5), (DOOR_H + 1) / 2, front - 0.2), t.accent)
	Props.part(model, "FrameR", Vector3.new(1, DOOR_H + 1, 1.4), at(DOOR_W / 2 + 0.5, (DOOR_H + 1) / 2, front - 0.2), t.accent)
	Props.part(model, "FrameTop", Vector3.new(DOOR_W + 2, 1, 1.4), at(0, DOOR_H + 0.5, front - 0.2), t.accent)
	Props.part(model, "DoorLight", Vector3.new(4, 0.7, 0.4), at(0, DOOR_H + 0.5, front - 1), Color3.fromRGB(255, 80, 80), { material = Enum.Material.Neon, collide = false })

	local door = Props.part(model, "Door", Vector3.new(DOOR_W, DOOR_H, 0.6), at(0, DOOR_H / 2, front + 0.6),
		Color3.fromRGB(170, 225, 255), { material = Enum.Material.Glass, transparency = 0.35 })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DoorPrompt"
	prompt.ActionText = "Buy " .. Format.cash(definition.price)
	prompt.ObjectText = definition.name
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = door

	Props.part(model, "Mat", Vector3.new(DOOR_W, 0.2, VESTIBULE), at(0, 0.1, front + VESTIBULE / 2), t.roof)
	Props.part(model, "Portal", Vector3.new(DOOR_W - 0.5, DOOR_H - 0.5, 0.3), at(0, DOOR_H / 2, front + VESTIBULE - 0.2),
		t.accent:Lerp(Color3.new(1, 1, 1), 0.3), { material = Enum.Material.Neon, transparency = 0.25, collide = false })
	local trigger = Props.part(model, "EntryTrigger", Vector3.new(DOOR_W - 1, DOOR_H, 4), at(0, DOOR_H / 2, front + VESTIBULE - 2.5),
		Color3.new(0, 1, 0), { transparency = 1, collide = false })
	trigger.CanTouch = true
	Props.part(model, "ExitSpot", Vector3.new(4, 1, 4), at(0, 0.5, front - 9), Color3.new(1, 1, 0), { transparency = 1, collide = false })

	-- "For sale" sign (texts are personalised on each client).
	local signX = DOOR_W / 2 + 6.5
	-- Low enough to clear the awning and far enough out to clear the flower bed.
	local board = Props.part(model, "SaleSign", Vector3.new(9, 6, 0.5), at(signX, 6.3, front - 6), Color3.fromRGB(255, 255, 255))
	-- Two posts and a frame BEHIND the board (local +Z, toward the building), so nothing
	-- pokes through the text on the front face.
	local signDark = Color3.fromRGB(80, 80, 90)
	Props.part(model, "SignFrame", Vector3.new(9.6, 6.6, 0.3), board.CFrame * CFrame.new(0, 0, 0.4), signDark)
	for i, x in { -3.4, 3.4 } do
		Props.part(model, if i == 1 then "SignPost" else "SignPost2", Vector3.new(9.3, 0.6, 0.6),
			board.CFrame * CFrame.new(x, -1.65, 0.85) * CFrame.Angles(0, 0, math.pi / 2), signDark, { shape = Enum.PartType.Cylinder })
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local function signText(name: string, y: number, height: number, color: Color3, text: string)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.05, y)
		l.Size = UDim2.fromScale(0.9, height)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = text
		l.Parent = gui
	end
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundColor3 = t.primary
	header.BorderSizePixel = 0
	header.Size = UDim2.fromScale(1, 0.24)
	header.Parent = gui
	signText("Status", 0.02, 0.2, Color3.fromRGB(255, 255, 255), "FOR SALE")
	signText("Title", 0.27, 0.22, Color3.fromRGB(50, 50, 60), definition.emoji .. " " .. definition.name)
	signText("Price", 0.5, 0.22, Color3.fromRGB(40, 160, 70), Format.cash(definition.price))
	signText("Income", 0.74, 0.18, Color3.fromRGB(110, 110, 120), "Walk up to the door to buy")
	gui.Parent = board

	-- Ownership flag (coloured per player on the client).
	Props.cylinder(model, "FlagPole", 16, 0.5, at(-signX, 8, front - 4.5).Position, Color3.fromRGB(200, 200, 210))
	Props.part(model, "OwnerFlag", Vector3.new(4.5, 2.8, 0.2), at(-signX + 2.4, 14.4, front - 4.5), Color3.fromRGB(180, 180, 190), { collide = false })

	-- Floating ownership tag.
	local anchor = Props.part(model, "TagAnchor", Vector3.new(1, 1, 1), at(0, h + 14, front), Color3.new(1, 1, 1), { transparency = 1, collide = false })
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "OwnerTag"
	billboardGui.Size = UDim2.fromScale(16, 3.2)
	billboardGui.MaxDistance = 360
	billboardGui.LightInfluence = 0
	billboardGui.AlwaysOnTop = false
	local pill = Instance.new("TextLabel")
	pill.Name = "Label"
	pill.Size = UDim2.fromScale(1, 1)
	pill.BackgroundColor3 = Color3.fromRGB(40, 45, 60)
	pill.BackgroundTransparency = 0.15
	pill.Font = Enum.Font.FredokaOne
	pill.TextScaled = true
	pill.TextColor3 = Color3.fromRGB(255, 255, 255)
	pill.Text = definition.emoji .. " FOR SALE • " .. Format.cash(definition.price)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = pill
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.Parent = pill
	pill.Parent = billboardGui
	billboardGui.Parent = anchor

	-- The rooftop mascot is drawn at its original size, then scaled up with the city.
	local mascot = Instance.new("Model")
	mascot.Name = "RoofProp"
	roofProp(mascot, definition, at(0, h + 2.4, 0))
	mascot.WorldPivot = at(0, h + 2.4, 0)
	mascot:ScaleTo(S)
	mascot.Parent = model

	-- Business-specific front plaza extras.
	if definition.id == "CarDealership" then
		for i, x in { -24, 24 } do
			for j, z in { front - 12, front - 26 } do
				local colors = { Color3.fromRGB(240, 70, 60), Color3.fromRGB(250, 200, 50), Color3.fromRGB(60, 200, 120), Color3.fromRGB(240, 240, 245) }
				Props.part(model, "Platform", Vector3.new(1, 17, 17), at(x, 0.5, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(230, 230, 235), { shape = Enum.PartType.Cylinder })
				local car = Props.car(model, colors[(i - 1) * 2 + j], true)
				car:PivotTo(at(x, 1, z) * CFrame.Angles(0, math.rad(30 + i * 40), 0))
				car:ScaleTo(1.15)
			end
		end
	elseif definition.id == "Hotel" then
		for _, x in { -9, 9 } do
			Props.cylinder(model, "CanopyPillar", 16, 1.4, at(x, 8, front - 16).Position, Color3.fromRGB(240, 230, 200))
		end
		Props.part(model, "Canopy", Vector3.new(22, 1.2, 18), at(0, 16.6, front - 9), t.accent)
		Props.part(model, "Carpet", Vector3.new(6, 0.2, 18), at(0, 0.1, front - 9), Color3.fromRGB(200, 30, 50), { collide = false })
	elseif definition.id == "Bakery" or definition.id == "IceCream" or definition.id == "Burger" or definition.id == "Seafood" then
		-- Café tables with parasols on the front plaza.
		for _, x in { -(w / 2 - 6), w / 2 - 6 } do
			local p = at(x, 0, front - 11)
			Props.cylinder(model, "CafeTable", 3, 4.5, (p * CFrame.new(0, 1.5, 0)).Position, WHITE)
			Props.cylinder(model, "ParasolPole", 10, 0.4, (p * CFrame.new(0, 5, 0)).Position, DARK)
			Props.cylinder(model, "Parasol", 0.6, 11, (p * CFrame.new(0, 10, 0)).Position, t.primary, { collide = false })
			for _, cx in { -3.6, 3.6 } do
				Props.part(model, "CafeChair", Vector3.new(1.8, 2, 1.8), p * CFrame.new(cx, 1, 0), t.secondary)
			end
		end
	elseif definition.id == "TechCompany" then
		-- Glass entrance pavilion with the company logo.
		Props.part(model, "Pavilion", Vector3.new(26, 0.8, 14), at(0, 16.4, front - 8), t.primary)
		for _, x in { -12, 12 } do
			Props.part(model, "PavilionPost", Vector3.new(1, 16, 1), at(x, 8, front - 14), WHITE)
		end
	end

	model.Parent = parent
	return model
end

-- Area a business lot keeps clear: the building, its sides and the plaza in front of it.
local function lotReservation(definition: Businesses.Definition): Rect
	local lot = definition.lot
	local cf = CFrame.new(lot.position) * CFrame.Angles(0, math.rad(lot.yaw), 0)
	local w, d = lot.size.X, lot.size.Z
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, corner in { Vector3.new(-w / 2 - 6, 0, -d / 2 - 34), Vector3.new(w / 2 + 6, 0, -d / 2 - 34), Vector3.new(-w / 2 - 6, 0, d / 2 + 6), Vector3.new(w / 2 + 6, 0, d / 2 + 6) } do
		local p = cf * corner
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
	end
	return box(minX, maxX, minZ, maxZ)
end

----- Block centrepieces -----
local function blockSurface(parent: Instance, block: { any })
	local kind, style = block[5], block[6]
	if kind == "quay" then
		rect(parent, "Boardwalk", block[1], block[2], block[3], block[4], TOP, 0.2, WOOD, Enum.Material.WoodPlanks)
		return
	end
	local color, name = CONCRETE, "Plaza"
	if kind == "park" or kind == "maplepark" or kind == "field" or kind == "pond" or style == "houses" or style == "luxury" then
		color, name = GRASS, "Lawn"
	elseif style == "shops" then
		color = PAVING
	elseif style == "harbor" or kind == "containers" then
		color = Color3.fromRGB(185, 185, 190)
	end
	rect(parent, name, block[1] + SURFACE_INSET, block[2] - SURFACE_INSET, block[3] + SURFACE_INSET, block[4] - SURFACE_INSET, TOP, 0.2, color)
end

-- Areas inside a block that buildings must not cover.
local function centreReservation(block: { any }): Rect?
	local kind = block[5]
	local cx, cz = (block[1] + block[2]) / 2, (block[3] + block[4]) / 2
	-- Centrepieces are drawn at plan size and scaled by S, so their areas scale too.
	if kind == "parking" then
		return around(cx, cz, 31 * S, 31 * S)
	elseif kind == "playground" then
		return around(cx, cz, 28 * S, 24 * S)
	elseif kind == "plaza" then
		return around(cx, cz, 34 * S, 34 * S)
	elseif kind == "market" then
		return around(cx, cz, 30 * S, 30 * S)
	elseif kind == "pond" then
		return around(cx, cz, 56 * S, 60 * S)
	elseif kind == "exchange" then
		return box(cx - 46 * S, cx + 46 * S, cz - 36 * S, block[4])
	end
	return nil
end

-- Each centrepiece draws at plan size from a block given in plan units (world / S);
-- buildBlocks then scales the result by S about the world origin.
local CENTREPIECES: { [string]: (Instance, { any }, Random) -> () } = {}
local PLAN_COAST_X = COAST_X / S

CENTREPIECES.park = function(parent, block, _rng)
	local inMinX, inMaxX, inMinZ, inMaxZ = block[1] + 6, block[2] - 6, block[3] + 6, block[4] - 6
	rect(parent, "PathX", inMinX, inMaxX, -4, 4, TOP + 0.05, 0.2, PAVING)
	rect(parent, "PathZ", -4, 4, inMinZ, inMaxZ, TOP + 0.05, 0.2, PAVING)
	Props.cylinder(parent, "Plaza", 0.25, 38, Vector3.new(0, TOP + 0.1, 0), PAVING)
	local fountain = Instance.new("Model")
	fountain.Name = "Fountain"
	Props.cylinder(fountain, "Basin", 2, 24, Vector3.new(0, TOP + 1, 0), Color3.fromRGB(205, 205, 215))
	Props.cylinder(fountain, "Water", 0.4, 21, Vector3.new(0, TOP + 2, 0), Color3.fromRGB(80, 185, 255), { material = Enum.Material.Glass, transparency = 0.15 })
	Props.cylinder(fountain, "Column", 7, 3, Vector3.new(0, TOP + 4.5, 0), Color3.fromRGB(205, 205, 215))
	Props.cylinder(fountain, "Bowl", 1.2, 10, Vector3.new(0, TOP + 8, 0), Color3.fromRGB(205, 205, 215))
	local spout = Props.ball(fountain, "Spout", 3, Vector3.new(0, TOP + 9.5, 0), Color3.fromRGB(110, 200, 255), { material = Enum.Material.Glass, transparency = 0.2 })
	local spray = Instance.new("ParticleEmitter")
	spray.Color = ColorSequence.new(Color3.fromRGB(190, 235, 255))
	spray.Size = NumberSequence.new(0.6, 0.2)
	spray.Transparency = NumberSequence.new(0.2, 1)
	spray.Lifetime = NumberRange.new(1, 1.4)
	spray.Rate = 40
	spray.Speed = NumberRange.new(10, 13)
	spray.SpreadAngle = Vector2.new(25, 25)
	spray.Acceleration = Vector3.new(0, -25, 0)
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Parent = spout
	fountain.Parent = parent
	for _, p in { Vector3.new(-14, 0, -14), Vector3.new(14, 0, -14), Vector3.new(-14, 0, 14), Vector3.new(14, 0, 14) } do
		Props.bench(parent, CFrame.lookAt(Vector3.new(p.X * 1.25, TOP, p.Z * 1.25), Vector3.new(0, TOP, 0)) * CFrame.Angles(0, math.pi, 0))
	end
	for _, q in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		Props.tree(parent, Vector3.new(q.X * 34, TOP, q.Z * 34), 1.15)
		Props.tree(parent, Vector3.new(q.X * 44, TOP, q.Z * 22), 0.9)
		Props.tree(parent, Vector3.new(q.X * 20, TOP, q.Z * 44), 0.95)
		Props.flowerBed(parent, CFrame.new(q.X * 24, TOP, q.Z * 8), 10)
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CitySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 0.4, 10)
	local spawnAt = Vector3.new(Config.CITY_SPAWN.X / S, TOP + 0.2, Config.CITY_SPAWN.Z / S)
	spawn.CFrame = CFrame.lookAt(spawnAt, spawnAt + Vector3.new(0, 0, 1))
	spawn.Color = Color3.fromRGB(255, 215, 90)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = parent
end

CENTREPIECES.parking = function(parent, block, rng)
	local cx, cz = (block[1] + block[2]) / 2, (block[3] + block[4]) / 2
	rect(parent, "ParkingLot", cx - 30, cx + 30, cz - 30, cz + 30, TOP + 0.05, 0.2, Color3.fromRGB(95, 98, 110))
	for row, z in { cz - 13, cz + 13 } do
		for i = 0, 5 do
			local x = cx - 27 + i * 10.8
			Props.part(parent, "Line", Vector3.new(0.5, 0.05, 14), CFrame.new(x, TOP + 0.18, z), WHITE, { collide = false, shadow = false })
			if i < 5 and rng:NextNumber() < 0.75 then
				local car = Props.car(parent, TOWER_COLORS[rng:NextInteger(1, #TOWER_COLORS)], true)
				car:PivotTo(CFrame.new(x + 5.4, TOP + 0.15, z) * CFrame.Angles(0, if row == 1 then 0 else math.pi, 0))
			end
		end
	end
end

CENTREPIECES.playground = function(parent, block, _rng)
	local cx, cz = (block[1] + block[2]) / 2, (block[3] + block[4]) / 2
	rect(parent, "SoftFloor", cx - 27, cx + 27, cz - 23, cz + 23, TOP + 0.05, 0.2, Color3.fromRGB(240, 140, 110))
	Props.part(parent, "Sandbox", Vector3.new(18, 0.6, 14), CFrame.new(cx - 14, TOP + 0.3, cz + 8), Color3.fromRGB(240, 220, 160))
	Props.part(parent, "SlideTower", Vector3.new(6, 8, 6), CFrame.new(cx - 14, TOP + 4, cz - 10), Color3.fromRGB(255, 120, 80))
	Props.wedge(parent, "Slide", Vector3.new(4, 8, 12), CFrame.new(cx - 14, TOP + 4, cz - 1) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(255, 210, 60))
	Props.part(parent, "SwingBar", Vector3.new(14, 1, 1), CFrame.new(cx + 12, TOP + 10, cz - 8), Color3.fromRGB(80, 160, 230))
	for _, x in { -6, 6 } do
		Props.part(parent, "SwingPost", Vector3.new(1, 10, 1), CFrame.new(cx + 12 + x, TOP + 5, cz - 8), Color3.fromRGB(80, 160, 230))
	end
	for _, x in { -3, 3 } do
		Props.part(parent, "SwingSeat", Vector3.new(2.4, 0.4, 1.4), CFrame.new(cx + 12 + x, TOP + 3, cz - 8), Color3.fromRGB(255, 200, 60))
	end
	Props.cylinder(parent, "Roundabout", 0.8, 9, Vector3.new(cx + 14, TOP + 0.6, cz + 10), Color3.fromRGB(150, 90, 230))
end

CENTREPIECES.plaza = function(parent, block, _rng)
	local cx, cz = (block[1] + block[2]) / 2, (block[3] + block[4]) / 2
	rect(parent, "PlazaStone", cx - 33, cx + 33, cz - 33, cz + 33, TOP + 0.05, 0.2, PAVING)
	Props.part(parent, "Pedestal", Vector3.new(9, 6, 9), CFrame.new(cx, TOP + 3, cz), Color3.fromRGB(205, 205, 215))
	local statue = Instance.new("Model")
	statue.Name = "FounderStatue"
	local foil = { material = Enum.Material.Foil }
	Props.part(statue, "Legs", Vector3.new(3, 4, 1.6), CFrame.new(cx, TOP + 8, cz), GOLD, foil)
	Props.part(statue, "Torso", Vector3.new(4, 4, 2), CFrame.new(cx, TOP + 12, cz), GOLD, foil)
	Props.part(statue, "Arm", Vector3.new(1.2, 5, 1.2), CFrame.new(cx + 2.6, TOP + 15, cz) * CFrame.Angles(0, 0, math.rad(-20)), GOLD, foil)
	Props.ball(statue, "Head", 2.8, Vector3.new(cx, TOP + 15.4, cz), GOLD, foil)
	Props.part(statue, "Briefcase", Vector3.new(2, 1.6, 0.6), CFrame.new(cx - 2.8, TOP + 10, cz), GOLD, foil)
	statue.Parent = parent
	for _, q in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		local p = Vector3.new(cx + q.X * 24, TOP, cz + q.Z * 24)
		Props.part(parent, "Planter", Vector3.new(9, 2, 9), CFrame.new(p + Vector3.new(0, 1, 0)), Color3.fromRGB(180, 180, 190))
		Props.tree(parent, p + Vector3.new(0, 2, 0), 1)
		Props.bench(parent, CFrame.lookAt(Vector3.new(cx + q.X * 12, TOP, cz + q.Z * 12), Vector3.new(cx, TOP, cz)) * CFrame.Angles(0, math.pi, 0))
	end
end

CENTREPIECES.market = function(parent, block, rng)
	local cx, cz = (block[1] + block[2]) / 2, (block[3] + block[4]) / 2
	rect(parent, "MarketFloor", cx - 29, cx + 29, cz - 29, cz + 29, TOP + 0.05, 0.2, PAVING)
	for i, offset in { Vector3.new(-14, 0, -14), Vector3.new(14, 0, -14), Vector3.new(-14, 0, 14), Vector3.new(14, 0, 14) } do
		local cf = CFrame.lookAt(Vector3.new(cx + offset.X, TOP, cz + offset.Z), Vector3.new(cx, TOP, cz))
		local color = AWNING_COLORS[i]
		Props.part(parent, "Counter", Vector3.new(10, 3.4, 4), cf * CFrame.new(0, 1.7, 0), WOOD, { material = Enum.Material.WoodPlanks })
		Props.part(parent, "Ice", Vector3.new(9, 0.6, 3.4), cf * CFrame.new(0, 3.7, 0), Color3.fromRGB(220, 245, 255))
		for k = -1, 1 do
			Props.part(parent, "Fish", Vector3.new(2.2, 0.6, 0.9), cf * CFrame.new(k * 2.8, 4.2, 0) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0), Color3.fromRGB(170, 190, 210))
		end
		for _, x in { -4.6, 4.6 } do
			Props.part(parent, "StallPost", Vector3.new(0.5, 9, 0.5), cf * CFrame.new(x, 4.5, 2), DARK)
		end
		Props.wedge(parent, "StallRoof", Vector3.new(11, 1.6, 6), cf * CFrame.new(0, 9.6, -0.6), color, { collide = false })
	end
	local sign = Props.part(parent, "MarketSign", Vector3.new(18, 4, 0.8), CFrame.new(cx, TOP + 13, cz), Color3.fromRGB(40, 110, 170))
	label(sign, Enum.NormalId.Front, "🐟 FISH MARKET", WHITE, 20)
	label(sign, Enum.NormalId.Back, "🐟 FISH MARKET", WHITE, 20)
	Props.cylinder(parent, "SignPole", 11, 0.8, Vector3.new(cx, TOP + 5.5, cz), DARK)
end

CENTREPIECES.pond = function(parent, block, rng)
	local cx, cz = (block[1] + block[2]) / 2, (block[3] + block[4]) / 2
	Props.cylinder(parent, "PondEdge", 0.3, 76, Vector3.new(cx, TOP + 0.02, cz), Color3.fromRGB(200, 190, 170))
	Props.cylinder(parent, "Pond", 0.4, 70, Vector3.new(cx, TOP + 0.1, cz), Color3.fromRGB(80, 180, 240), { material = Enum.Material.Glass, transparency = 0.1 })
	for i = 1, 10 do
		local angle = i / 10 * math.pi * 2
		Props.tree(parent, Vector3.new(cx + math.cos(angle) * 47, TOP, cz + math.sin(angle) * 50), rng:NextNumber(0.9, 1.15))
	end
	for i = 1, 4 do
		local angle = i / 4 * math.pi * 2 + 0.4
		local p = Vector3.new(cx + math.cos(angle) * 41, TOP, cz + math.sin(angle) * 41)
		Props.bench(parent, CFrame.lookAt(p, Vector3.new(cx, TOP, cz)) * CFrame.Angles(0, math.pi, 0))
	end
	-- A little island with a gazebo.
	Props.cylinder(parent, "Island", 1, 16, Vector3.new(cx, TOP + 0.5, cz), GRASS)
	Props.cylinder(parent, "GazeboRoof", 1, 12, Vector3.new(cx, TOP + 9, cz), Color3.fromRGB(250, 250, 250))
	for i = 1, 4 do
		local angle = i / 4 * math.pi * 2 + math.pi / 4
		Props.cylinder(parent, "GazeboPost", 8, 0.6, Vector3.new(cx + math.cos(angle) * 4.5, TOP + 5, cz + math.sin(angle) * 4.5), WHITE)
	end
	Props.ball(parent, "GazeboTop", 6, Vector3.new(cx, TOP + 9.5, cz), Color3.fromRGB(200, 130, 255))
end

CENTREPIECES.exchange = function(parent, block, _rng)
	local cx, cz = (block[1] + block[2]) / 2, (block[3] + block[4]) / 2
	local model = Instance.new("Model")
	model.Name = "StockExchange"
	local marble = { material = Enum.Material.Marble }
	local stone = Color3.fromRGB(240, 238, 230)
	-- Faces +Z (towards the street and the Tech Company).
	local cf = CFrame.new(cx, TOP, cz - 6) * CFrame.Angles(0, math.pi, 0)
	Props.part(model, "Steps", Vector3.new(64, 1.2, 12), cf * CFrame.new(0, 0.6, -25), stone, marble)
	Props.part(model, "Podium", Vector3.new(62, 2.4, 44), cf * CFrame.new(0, 1.2, 0), stone, marble)
	Props.part(model, "Hall", Vector3.new(56, 26, 34), cf * CFrame.new(0, 15.4, 3), stone, marble)
	for i = 0, 5 do
		local x = -22.5 + i * 9
		Props.cylinder(model, "Column", 22, 3, (cf * CFrame.new(x, 13.4, -18)).Position, WHITE, marble)
	end
	local architrave = Props.part(model, "Architrave", Vector3.new(58, 4, 6), cf * CFrame.new(0, 26.4, -18), stone, marble)
	label(architrave, Enum.NormalId.Front, "📈 CITY STOCK EXCHANGE", Color3.fromRGB(60, 50, 40), 14)
	local ticker = Props.part(model, "Ticker", Vector3.new(40, 2.2, 0.4), cf * CFrame.new(0, 10.5, -14.4), Color3.fromRGB(20, 25, 30))
	label(ticker, Enum.NormalId.Front, "▲ CITY500 +2.4%   ▲ PIZZA +8.1%   ▼ COFFEE -0.6%", Color3.fromRGB(90, 255, 140), 14)
	Props.ball(model, "Dome", 26, (cf * CFrame.new(0, 28.4, 3)).Position, Color3.fromRGB(110, 180, 160))
	for _, x in { -26, 26 } do
		Props.cylinder(model, "FlagPole", 24, 0.6, (cf * CFrame.new(x, 12, -30)).Position, Color3.fromRGB(220, 220, 230))
		Props.part(model, "Flag", Vector3.new(6, 3.6, 0.2), cf * CFrame.new(x + 3.2, 21.8, -30), GOLD)
	end
	model.Parent = parent
end

CENTREPIECES.maplepark = function(parent, block, rng)
	local cx, cz = (block[1] + block[2]) / 2, (block[3] + block[4]) / 2
	rect(parent, "PathZ", cx - 3, cx + 3, block[3] + 6, block[4] - 6, TOP + 0.05, 0.2, PAVING)
	rect(parent, "PathX", block[1] + 6, block[2] - 6, cz - 3, cz + 3, TOP + 0.05, 0.2, PAVING)
	-- Duck pond.
	local pond = Vector3.new(cx + 24, TOP, cz + 42)
	Props.cylinder(parent, "PondEdge", 0.3, 40, pond + Vector3.new(0, 0.02, 0), Color3.fromRGB(200, 190, 170))
	Props.cylinder(parent, "Pond", 0.4, 36, pond + Vector3.new(0, 0.1, 0), Color3.fromRGB(80, 180, 240), { material = Enum.Material.Glass, transparency = 0.1 })
	for i = 1, 3 do
		local duck = pond + Vector3.new(math.cos(i * 2) * 8, 0.8, math.sin(i * 2) * 8)
		Props.ball(parent, "Duck", 1.6, duck, Color3.fromRGB(255, 230, 80))
		Props.ball(parent, "DuckHead", 1, duck + Vector3.new(0.7, 0.8, 0), Color3.fromRGB(255, 230, 80))
	end
	-- Gazebo.
	local gazebo = Vector3.new(cx - 24, TOP, cz - 40)
	Props.cylinder(parent, "GazeboFloor", 1, 16, gazebo + Vector3.new(0, 0.5, 0), WOOD)
	for i = 1, 6 do
		local angle = i / 6 * math.pi * 2
		Props.cylinder(parent, "GazeboPost", 8, 0.7, gazebo + Vector3.new(math.cos(angle) * 6.6, 5, math.sin(angle) * 6.6), WHITE)
	end
	Props.cylinder(parent, "GazeboRoof", 1.2, 18, gazebo + Vector3.new(0, 9.6, 0), Color3.fromRGB(200, 80, 70))
	Props.ball(parent, "GazeboDome", 10, gazebo + Vector3.new(0, 10.4, 0), Color3.fromRGB(200, 80, 70))
	-- Little playground.
	local play = Vector3.new(cx + 26, TOP, cz - 40)
	Props.part(parent, "SlideTower", Vector3.new(5, 7, 5), CFrame.new(play + Vector3.new(0, 3.5, -4)), Color3.fromRGB(80, 170, 240))
	Props.wedge(parent, "Slide", Vector3.new(3.4, 7, 10), CFrame.new(play + Vector3.new(0, 3.5, 3.5)) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(255, 120, 80))
	Props.cylinder(parent, "Seesaw", 1, 1.2, play + Vector3.new(10, 0.5, 0), DARK)
	Props.part(parent, "SeesawBoard", Vector3.new(12, 0.5, 1.4), CFrame.new(play + Vector3.new(10, 1.3, 0)) * CFrame.Angles(0, 0, math.rad(10)), Color3.fromRGB(255, 200, 60))
	-- Trees, flowers and benches.
	for i = 1, 14 do
		local x = rng:NextNumber(block[1] + 10, block[2] - 10)
		local z = rng:NextNumber(block[3] + 10, block[4] - 10)
		local p = Vector3.new(x, TOP, z)
		if math.abs(x - cx) > 7 and math.abs(z - cz) > 7 and (p - pond).Magnitude > 26 and (p - gazebo).Magnitude > 14 and (p - play).Magnitude > 16 then
			if i % 3 == 0 then
				Props.pine(parent, p, rng:NextNumber(0.9, 1.2))
			else
				Props.tree(parent, p, rng:NextNumber(0.9, 1.25))
			end
		end
	end
	for _, offset in { Vector3.new(-8, 0, 12), Vector3.new(8, 0, -12) } do
		Props.bench(parent, CFrame.lookAt(Vector3.new(cx + offset.X, TOP, cz + offset.Z), Vector3.new(cx, TOP, cz + offset.Z)) * CFrame.Angles(0, math.pi, 0))
		Props.flowerBed(parent, CFrame.new(cx + offset.X * 2.5, TOP, cz - offset.Z), 10)
	end
	local sign = Props.part(parent, "ParkSign", Vector3.new(14, 3.4, 0.6), CFrame.new(cx + 12, TOP + 4.5, block[3] + 9), Color3.fromRGB(110, 70, 40))
	label(sign, Enum.NormalId.Front, "🍁 MAPLE PARK", WHITE, 24)
end

CENTREPIECES.field = function(parent, block, _rng)
	local cx, cz = (block[1] + block[2]) / 2, (block[3] + block[4]) / 2
	local halfW, halfL = 32, 62
	for i = -2, 2 do
		local shade = if i % 2 == 0 then Color3.fromRGB(90, 185, 80) else Color3.fromRGB(105, 200, 90)
		rect(parent, "Pitch", cx - halfW, cx + halfW, cz + i * 24.8 - 12.4, cz + i * 24.8 + 12.4, TOP + 0.05, 0.2, shade)
	end
	local lineTop = TOP + 0.12
	local function line(minX: number, maxX: number, minZ: number, maxZ: number)
		rect(parent, "Line", minX, maxX, minZ, maxZ, lineTop, 0.05, WHITE).CanCollide = false
	end
	line(cx - halfW, cx + halfW, cz - halfL, cz - halfL + 0.6)
	line(cx - halfW, cx + halfW, cz + halfL - 0.6, cz + halfL)
	line(cx - halfW, cx - halfW + 0.6, cz - halfL, cz + halfL)
	line(cx + halfW - 0.6, cx + halfW, cz - halfL, cz + halfL)
	line(cx - halfW, cx + halfW, cz - 0.3, cz + 0.3)
	for _, side in { -1, 1 } do
		local goalZ = cz + side * halfL
		line(cx - 12, cx + 12, goalZ - side * 14 - 0.3, goalZ - side * 14 + 0.3)
		line(cx - 12, cx - 11.4, math.min(goalZ, goalZ - side * 14), math.max(goalZ, goalZ - side * 14))
		line(cx + 11.4, cx + 12, math.min(goalZ, goalZ - side * 14), math.max(goalZ, goalZ - side * 14))
		for _, x in { -6, 6 } do
			Props.part(parent, "GoalPost", Vector3.new(0.6, 6, 0.6), CFrame.new(cx + x, TOP + 3, goalZ), WHITE)
		end
		Props.part(parent, "Crossbar", Vector3.new(12.6, 0.6, 0.6), CFrame.new(cx, TOP + 6, goalZ), WHITE)
		Props.part(parent, "Net", Vector3.new(12, 6, 0.2), CFrame.new(cx, TOP + 3, goalZ + side * 3), WHITE, { transparency = 0.6 })
	end
	Props.cylinder(parent, "CentreCircle", 0.05, 18, Vector3.new(cx, lineTop + 0.02, cz), WHITE, { collide = false })
	Props.cylinder(parent, "CentreInner", 0.06, 16.8, Vector3.new(cx, lineTop + 0.03, cz), Color3.fromRGB(90, 185, 80), { collide = false })
	-- Bleachers along one side and floodlights in the corners.
	for step = 0, 2 do
		Props.part(parent, "Bleacher", Vector3.new(4, 1.6 + step * 1.6, 80), CFrame.new(cx + halfW + 6 + step * 4, TOP + (1.6 + step * 1.6) / 2, cz), Color3.fromRGB(60, 120, 200))
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local p = Vector3.new(cx + sx * (halfW + 4), TOP, cz + sz * (halfL + 2))
			Props.cylinder(parent, "FloodPole", 26, 1, p + Vector3.new(0, 13, 0), Color3.fromRGB(190, 190, 200))
			Props.part(parent, "Floodlight", Vector3.new(4, 2.4, 1), CFrame.lookAt(p + Vector3.new(0, 26, 0), Vector3.new(cx, TOP, cz)), Color3.fromRGB(255, 250, 220), { material = Enum.Material.Neon })
		end
	end
end

CENTREPIECES.containers = function(parent, block, rng)
	local cx = (block[1] + block[2]) / 2
	local z = block[3] + 14
	while z < block[4] - 14 do
		for _, x in { cx - 9, cx + 9 } do
			local stack = rng:NextInteger(1, 3)
			for level = 1, stack do
				local container = Props.part(parent, "Container", Vector3.new(8, 8.4, 20), CFrame.new(x, TOP + 4.2 + (level - 1) * 8.5, z + 10), CONTAINER_COLORS[rng:NextInteger(1, #CONTAINER_COLORS)], { material = Enum.Material.DiamondPlate })
				container.CastShadow = level == stack
			end
		end
		z += 23
	end
	-- Gantry crane straddling the stacks.
	local crane = Instance.new("Model")
	crane.Name = "GantryCrane"
	local yellow = Color3.fromRGB(250, 190, 40)
	local cz = (block[3] + block[4]) / 2
	for _, x in { cx - 18, cx + 18 } do
		for _, dz in { -6, 6 } do
			Props.part(crane, "Leg", Vector3.new(1.6, 34, 1.6), CFrame.new(x, TOP + 17, cz + dz), yellow)
		end
		Props.part(crane, "Rail", Vector3.new(1.6, 1.6, 14), CFrame.new(x, TOP + 34, cz), yellow)
	end
	Props.part(crane, "Beam", Vector3.new(40, 3, 3), CFrame.new(cx, TOP + 35.5, cz), yellow)
	Props.part(crane, "Cabin", Vector3.new(5, 4, 5), CFrame.new(cx + 6, TOP + 32, cz), Color3.fromRGB(230, 70, 60))
	Props.part(crane, "Cable", Vector3.new(0.3, 8, 0.3), CFrame.new(cx - 4, TOP + 30, cz), DARK)
	crane.Parent = parent
end

-- Harbor quay: boardwalk, railing, piers, boats, bollards and the lighthouse.
local function boat(parent: Instance, cf: CFrame, color: Color3)
	local model = Instance.new("Model")
	model.Name = "Boat"
	Props.part(model, "Hull", Vector3.new(7, 3, 16), cf * CFrame.new(0, 0.6, 0), WHITE)
	Props.wedge(model, "Bow", Vector3.new(7, 3, 6), cf * CFrame.new(0, 0.6, -11) * CFrame.Angles(0, math.pi, 0), WHITE)
	Props.part(model, "Stripe", Vector3.new(7.2, 0.8, 16.2), cf * CFrame.new(0, 1.3, 0), color)
	Props.part(model, "Cabin", Vector3.new(5, 3, 6), cf * CFrame.new(0, 3.6, 2.5), color:Lerp(Color3.new(1, 1, 1), 0.4))
	Props.cylinder(model, "Mast", 12, 0.5, (cf * CFrame.new(0, 8, -2)).Position, Color3.fromRGB(150, 110, 70))
	model.Parent = parent
end

CENTREPIECES.quay = function(parent, block, rng)
	local COAST_X = PLAN_COAST_X
	local minZ, maxZ = block[3], block[4]
	local railX = COAST_X + 0.6
	-- A pier every 130 studs along the waterfront (the original three sit at -130, 0, 130).
	local piers = {}
	local centre = (minZ + maxZ) / 2
	for k = -6, 6 do
		local p = centre + k * 130
		if p > minZ + 30 and p < maxZ - 30 then
			table.insert(piers, p)
		end
	end
	local function nearPier(z: number, distance: number): boolean
		for _, p in piers do
			if math.abs(z - p) < distance then
				return true
			end
		end
		return false
	end
	-- Railing and invisible sea wall, with openings onto the piers.
	local cuts = { minZ }
	for _, p in piers do
		table.insert(cuts, p - 6)
		table.insert(cuts, p + 6)
	end
	table.insert(cuts, maxZ)
	for i = 1, #cuts, 2 do
		local a, b = cuts[i], cuts[i + 1]
		Props.part(parent, "Railing", Vector3.new(0.5, 0.6, b - a), CFrame.new(railX, TOP + 3.3, (a + b) / 2), WHITE)
		local wall = Props.part(parent, "SeaWall", Vector3.new(1, 60, b - a), CFrame.new(COAST_X - 0.5, 30, (a + b) / 2), WHITE, { transparency = 1, shadow = false })
		wall.CanQuery = false
	end
	local z = minZ + 4
	while z < maxZ - 2 do
		if not nearPier(z, 7) then
			Props.part(parent, "RailPost", Vector3.new(0.6, 3.4, 0.6), CFrame.new(railX, TOP + 1.7, z), WHITE)
		end
		z += 16
	end
	z = minZ + 12
	while z < maxZ - 8 do
		if not nearPier(z, 10) then
			Props.cylinder(parent, "Bollard", 2, 1.4, Vector3.new(COAST_X + 3, TOP + 1, z), DARK)
		end
		z += 32
	end
	-- Piers with moored boats.
	for i, pz in piers do
		local length = 70
		local deck = Props.part(parent, "Pier", Vector3.new(length, 1, 10), CFrame.new(COAST_X - length / 2, TOP - 0.5, pz), WOOD, { material = Enum.Material.WoodPlanks })
		deck.Name = "Pier"
		for k = 1, 4 do
			for _, side in { -1, 1 } do
				Props.cylinder(parent, "PierPost", 6, 1, Vector3.new(COAST_X - k * 17, TOP - 3, pz + side * 4.6), Color3.fromRGB(120, 85, 55))
			end
		end
		for _, side in { -1, 1 } do
			local guard = Props.part(parent, "PierWall", Vector3.new(length, 30, 1), CFrame.new(COAST_X - length / 2, 15, pz + side * 5.5), WHITE, { transparency = 1, shadow = false })
			guard.CanQuery = false
			Props.part(parent, "PierRail", Vector3.new(length, 0.5, 0.4), CFrame.new(COAST_X - length / 2, TOP + 2.8, pz + side * 4.8), WHITE)
		end
		local endWall = Props.part(parent, "PierWall", Vector3.new(1, 30, 12), CFrame.new(COAST_X - length - 0.5, 15, pz), WHITE, { transparency = 1, shadow = false })
		endWall.CanQuery = false
		local lampBase = Vector3.new(COAST_X - length + 3, TOP, pz + 3.5)
		Props.streetLight(parent, CFrame.lookAt(lampBase, lampBase - Vector3.zAxis))
		for _, side in { -1, 1 } do
			boat(parent, CFrame.new(COAST_X - 22 - (i % 2) * 18, 0.35, pz + side * 11) * CFrame.Angles(0, math.rad(90 + rng:NextNumber(-6, 6)), 0), AWNING_COLORS[rng:NextInteger(1, #AWNING_COLORS)])
		end
	end
	-- Lighthouse on a rocky islet.
	local lh = Vector3.new(-585, 0, 168)
	local lighthouse = Instance.new("Model")
	lighthouse.Name = "Lighthouse"
	Props.cylinder(lighthouse, "Rock", 6, 32, lh + Vector3.new(0, 1, 0), Color3.fromRGB(140, 135, 130))
	for level = 0, 4 do
		Props.cylinder(lighthouse, "TowerBand", 8, 11 - level * 0.8, lh + Vector3.new(0, 8 + level * 8, 0), if level % 2 == 0 then WHITE else Color3.fromRGB(220, 50, 50))
	end
	Props.cylinder(lighthouse, "Gallery", 1, 12, lh + Vector3.new(0, 44.5, 0), DARK)
	local lamp = Props.cylinder(lighthouse, "LampRoom", 5, 6, lh + Vector3.new(0, 47.5, 0), Color3.fromRGB(255, 240, 150), { material = Enum.Material.Neon })
	local glow = Instance.new("PointLight")
	glow.Range = 40
	glow.Brightness = 2
	glow.Color = Color3.fromRGB(255, 235, 160)
	glow.Parent = lamp
	Props.ball(lighthouse, "Cap", 7, lh + Vector3.new(0, 50.5, 0), Color3.fromRGB(220, 50, 50))
	lighthouse.Parent = parent
	-- Buoys.
	for i, p in { Vector3.new(-560, 0, -60), Vector3.new(-575, 0, 60), Vector3.new(-600, 0, -170) } do
		Props.ball(parent, "Buoy", 3, p + Vector3.new(0, 0.8, 0), if i % 2 == 0 then Color3.fromRGB(60, 190, 90) else Color3.fromRGB(230, 60, 50))
	end
end

----- Street furniture -----
local function streetFurniture(parent: Instance, block: { any }, doorPoints: { Vector3 }, rng: Random)
	local style = block[6]
	local leafy = style == "shops" or style == "houses" or style == "luxury" or style == "glass" or style == "towers"
	-- Parks have footpaths meeting the middle of each edge; keep those entrances clear.
	local centralPaths = block[5] == "park" or block[5] == "maplepark"
	local function nearDoor(p: Vector3, distance: number): boolean
		for _, door in doorPoints do
			if (Vector3.new(p.X, 0, p.Z) - door).Magnitude < distance then
				return true
			end
		end
		return false
	end
	local hydrantPlaced = false
	for _, edge in blockEdges(block) do
		if edge.road then
			local count = math.max(1, math.floor(edge.length / 42))
			for i = 1, count do
				local p = edge.a + edge.dir * (edge.length * (i - 0.5) / count) - edge.outward * 1.5
				if not nearDoor(p, 14) then
					local base = Vector3.new(p.X, CURB, p.Z)
					local lightModel = Props.streetLight(parent, CFrame.lookAt(base, base + edge.outward))
					-- Daytime city: keep the lamps glowing but skip the dynamic light cost.
					local lamp = lightModel:FindFirstChild("Lamp")
					local spot = lamp and lamp:FindFirstChildOfClass("SpotLight")
					if spot then
						spot.Enabled = false
					end
				end
				if i < count then
					-- Kerb side of the sidewalk; pedestrians walk 5 studs in from the kerb.
					local m = edge.a + edge.dir * (edge.length * i / count) - edge.outward * 2.2
					local onPath = centralPaths and math.abs(edge.length * i / count - edge.length / 2) < 6
					if not onPath and not nearDoor(m, 12) then
						local base = Vector3.new(m.X, CURB, m.Z)
						local roll = rng:NextNumber()
						if leafy and roll < 0.5 then
							Props.tree(parent, base, rng:NextNumber(0.62, 0.75))
						elseif roll < 0.72 then
							Props.bench(parent, CFrame.lookAt(base, base + edge.outward))
						elseif roll < 0.86 then
							Props.trashCan(parent, base)
						end
					end
				end
			end
			if not hydrantPlaced then
				local h = edge.a + edge.dir * 7 - edge.outward * 2
				if not nearDoor(h, 12) then
					Props.hydrant(parent, Vector3.new(h.X, CURB, h.Z))
					hydrantPlaced = true
				end
			end
		end
	end
end

local function trafficLight(parent: Instance, position: Vector3, facing: Vector3)
	local model = Instance.new("Model")
	model.Name = "TrafficLight"
	local base = CFrame.lookAt(position, position + facing)
	Props.cylinder(model, "Pole", 14, 0.7, position + Vector3.new(0, 7, 0), DARK)
	Props.part(model, "Arm", Vector3.new(0.5, 0.5, 8), base * CFrame.new(0, 13.6, -4), DARK)
	Props.part(model, "Housing", Vector3.new(1.6, 4.6, 1.4), base * CFrame.new(0, 11.6, -7.6), Color3.fromRGB(250, 200, 50))
	local lamps = { Color3.fromRGB(240, 60, 50), Color3.fromRGB(255, 200, 40), Color3.fromRGB(70, 230, 100) }
	for i, color in lamps do
		Props.part(model, "Lamp", Vector3.new(1.1, 1.1, 1.7), base * CFrame.new(0, 13.1 - (i - 1) * 1.4, -7.6), color, { material = if i == 3 then Enum.Material.Neon else Enum.Material.SmoothPlastic, collide = false })
	end
	model.Parent = parent
end

----- Sections -----
function CityBuilder.clear()
	local old = Workspace:FindFirstChild("City")
	if old then
		old:Destroy()
	end
	for _, name in { "Baseplate", "SpawnLocation" } do
		local template = Workspace:FindFirstChild(name)
		if template then
			template:Destroy()
		end
	end
end

function CityBuilder.buildGround(city: Instance)
	local ground = folder(city, "Ground")
	-- Land east of the coast, open sea west of it (parts are capped at 2048 studs).
	local LAND = 2000
	for _, span in { { -LAND, 0 }, { 0, LAND } } do
		rect(ground, "Grass", COAST_X, 640, span[1], span[2], 0, 4, GRASS)
		rect(ground, "Grass", 640, LAND, span[1], span[2], 0, 4, GRASS)
		local sea = rect(ground, "Sea", -1900, COAST_X, span[1], span[2], 0.35, 6, WATER, Enum.Material.Glass)
		sea.CastShadow = false
	end
	-- Beaches along the coast outside the harbor.
	local beachFrom = 614 * S -- the quay runs the whole city edge; beaches beyond it
	rect(ground, "Beach", COAST_X, COAST_X + 16, beachFrom, LAND, 0.25, 1, SAND)
	rect(ground, "Beach", COAST_X, COAST_X + 16, -LAND, -beachFrom, 0.25, 1, SAND)
	-- Asphalt under each district; blocks are raised on top, so the gaps become roads.
	for _, district in Config.Districts do
		local slab = rect(ground, "Asphalt_" .. district.id, math.max(district.minX, COAST_X), district.maxX, district.minZ, district.maxZ, 0.2, 0.4, ASPHALT)
		slab:SetAttribute("DistrictId", district.id)
	end
	-- Rolling hills on the horizon (none out at sea).
	-- Centred on the middle of the (wider) city.
	local mid = Vector3.new((CityLayout.BOUNDS.minX + CityLayout.BOUNDS.maxX) / 2, 0, 0)
	local rng = Random.new(7)
	for i = 1, 56 do
		local angle = i / 56 * math.pi * 2
		local radius = rng:NextNumber(1150, 1300)
		local size = rng:NextNumber(140, 260)
		local center = mid + Vector3.new(math.cos(angle) * radius, -size * 0.28, math.sin(angle) * radius)
		if center.X > COAST_X + size * 0.5 then
			Props.ball(ground, "Hill", size, center, GRASS:Lerp(Color3.fromRGB(60, 140, 70), rng:NextNumber(0, 0.5)))
		end
	end
	for i = 0, 11 do
		local angle = math.rad(-110 + i * 20)
		local center = mid + Vector3.new(math.cos(angle) * 1600, -40, math.sin(angle) * 1600)
		local mountain = Props.part(ground, "Mountain", Vector3.new(230, 270, 230), CFrame.new(center) * CFrame.Angles(math.rad(45), math.rad(i * 17), math.rad(45)),
			Color3.fromRGB(120, 130, 160))
		mountain.CastShadow = false
	end
end

function CityBuilder.buildRoadMarkings(city: Instance)
	local markings = folder(city, "RoadMarkings")
	local crossings = intersections()
	local white = Color3.fromRGB(245, 245, 245)
	local yellow = Color3.fromRGB(255, 210, 70)
	local function nearCrossing(p: Vector3, distance: number): boolean
		for _, c in crossings do
			if (Vector3.new(p.X, 0, p.Z) - c).Magnitude < distance then
				return true
			end
		end
		return false
	end
	for _, road in CityLayout.Roads do
		local a = Vector3.new(road[1], 0, road[2])
		local b = Vector3.new(road[3], 0, road[4])
		local length = (b - a).Magnitude
		local direction = (b - a).Unit
		local yaw = if road[1] == road[3] then 0 else math.pi / 2
		local s = 10
		while s < length - 8 do
			local p = a + direction * s
			if not nearCrossing(p, ROAD_HALF + 8) then
				Props.part(markings, "Dash", Vector3.new(0.8, 0.05, 6), CFrame.new(p.X, 0.22, p.Z) * CFrame.Angles(0, yaw, 0), yellow, { collide = false, shadow = false })
			end
			s += 14
		end
		task.wait()
	end
	-- Zebra crossings on every approach of every intersection, plus traffic lights.
	for _, c in crossings do
		for _, dir in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
			-- Lines up with the sidewalks either side, where the pedestrians cross.
			local center = c + dir * (ROAD_HALF + 5)
			if onRoad(center) and onRoad(c + dir * (ROAD_HALF + 12)) then
				local across = Vector3.new(dir.Z, 0, dir.X)
				for k = -3, 3 do
					local p = center + across * (k * 3.2)
					local yaw = if dir.X ~= 0 then math.pi / 2 else 0
					Props.part(markings, "Zebra", Vector3.new(1.8, 0.05, 6), CFrame.new(p.X, 0.22, p.Z) * CFrame.Angles(0, yaw, 0), white, { collide = false, shadow = false })
				end
			end
		end
		local offset = ROAD_HALF + 2.5
		for _, corner in { Vector3.new(1, 0, 1), Vector3.new(-1, 0, -1) } do
			local p = c + corner * offset
			if not onRoad(p) then
				trafficLight(markings, Vector3.new(p.X, CURB, p.Z), Vector3.new(-corner.X, 0, 0))
			end
		end
	end
end

function CityBuilder.buildBlocks(city: Instance)
	local blocks = folder(city, "Blocks")
	local doorPoints = {}
	for _, definition in Businesses.List do
		local cf = CFrame.new(definition.lot.position) * CFrame.Angles(0, math.rad(definition.lot.yaw), 0)
		local door = (cf * CFrame.new(0, 0, -definition.lot.size.Z / 2 - 10)).Position
		table.insert(doorPoints, Vector3.new(door.X, 0, door.Z))
	end
	local rng = Random.new(42)
	for index, block in CityLayout.Blocks do
		local model = Instance.new("Model")
		model.Name = string.format("Block%02d_%s", index, block[5])
		rect(model, "Sidewalk", block[1], block[2], block[3], block[4], CURB, 0.6, SIDEWALK)
		blockSurface(model, block)

		local reserved: { Rect } = {}
		for _, definition in Businesses.List do
			local p = definition.lot.position
			if p.X > block[1] and p.X < block[2] and p.Z > block[3] and p.Z < block[4] then
				table.insert(reserved, lotReservation(definition))
			end
		end
		local centre = centreReservation(block)
		if centre then
			table.insert(reserved, centre)
		end
		local centrepiece = CENTREPIECES[block[5]]
		if centrepiece then
			-- Draw at plan size, then scale everything (sizes and positions) by S.
			local plan = { block[1] / S, block[2] / S, block[3] / S, block[4] / S, block[5], block[6] }
			local drawn = Instance.new("Model")
			centrepiece(drawn, plan, rng)
			drawn.WorldPivot = CFrame.new(0, TOP, 0)
			drawn:ScaleTo(S)
			for _, child in drawn:GetChildren() do
				child.Parent = model
			end
			drawn:Destroy()
		end
		local style = block[6] and FILL[block[6]]
		if style then
			local placed: { Rect } = {}
			fillBlock(model, block, style, reserved, placed, rng)
			courtyard(model, block, reserved, placed, rng, if block[6] == "houses" then 6 else 4, block[6] == "harbor")
		end
		streetFurniture(model, block, doorPoints, rng)
		model.Parent = blocks
		task.wait()
	end
end

-- Hedge pieces along every district boundary, with openings at the gates.
local function hedgePieces(): { { number } }
	local pieces = {}
	for _, line in CityLayout.Boundaries do
		local x1, z1, x2, z2 = line[1], line[2], line[3], line[4]
		local horizontal = z1 == z2
		local from = if horizontal then math.min(x1, x2) else math.min(z1, z2)
		local to = if horizontal then math.max(x1, x2) else math.max(z1, z2)
		local cuts = {}
		for _, gate in CityLayout.Gates do
			if horizontal and math.abs(gate.z - z1) < 1 and gate.x > from and gate.x < to then
				table.insert(cuts, gate.x)
			elseif not horizontal and math.abs(gate.x - x1) < 1 and gate.z > from and gate.z < to then
				table.insert(cuts, gate.z)
			end
		end
		table.sort(cuts)
		local start = from
		local function add(a: number, b: number)
			if b - a > 1 then
				table.insert(pieces, if horizontal then { a, z1, b, z1 } else { x1, a, x1, b })
			end
		end
		-- Openings span the road and both sidewalks, so pedestrians can walk through.
		local opening = ROAD_HALF + SURFACE_INSET + 1
		for _, c in cuts do
			add(start, c - opening)
			start = c + opening
		end
		add(start, to)
	end
	return pieces
end

-- Road ends that lead nowhere (no junction, no gate) get a barricade.
local function roadEnds(): { { position: Vector3, inward: Vector3 } }
	local ends = {}
	for _, road in CityLayout.Roads do
		local p1 = Vector3.new(road[1], 0, road[2])
		local p2 = Vector3.new(road[3], 0, road[4])
		local dir = (p2 - p1).Unit
		for _, item in { { p1, dir }, { p2, -dir } } do
			local p, inward = item[1], item[2]
			local connected = false
			for _, gate in CityLayout.Gates do
				if (Vector3.new(gate.x, 0, gate.z) - p).Magnitude < 1 then
					connected = true
				end
			end
			for _, other in CityLayout.Roads do
				if other ~= road and not connected then
					if p.X >= math.min(other[1], other[3]) - 1 and p.X <= math.max(other[1], other[3]) + 1
						and p.Z >= math.min(other[2], other[4]) - 1 and p.Z <= math.max(other[2], other[4]) + 1 then
						connected = true
					end
				end
			end
			if not connected then
				table.insert(ends, { position = p + inward * 6, inward = inward })
			end
		end
	end
	return ends
end

function CityBuilder.buildBorders(city: Instance)
	local borders = folder(city, "Borders")
	for _, h in hedgePieces() do
		local minX, maxX = math.min(h[1], h[3]) - 3, math.max(h[1], h[3]) + 3
		local minZ, maxZ = math.min(h[2], h[4]) - 3, math.max(h[2], h[4]) + 3
		local hedge = rect(borders, "Hedge", minX, maxX, minZ, maxZ, 14, 14, HEDGE)
		hedge.Material = Enum.Material.SmoothPlastic
		-- Rounded bumps along the top for a cartoon look.
		local length = math.max(maxX - minX, maxZ - minZ)
		local steps = math.floor(length / 14)
		for i = 0, steps do
			local f = i / math.max(steps, 1)
			local x = minX + (maxX - minX) * f
			local z = minZ + (maxZ - minZ) * f
			if maxX - minX > maxZ - minZ then
				z = (minZ + maxZ) / 2
			else
				x = (minX + maxX) / 2
			end
			Props.ball(borders, "HedgeBump", 8, Vector3.new(x, 14, z), HEDGE:Lerp(Color3.new(1, 1, 1), 0.06), { collide = false, shadow = false })
		end
		-- Invisible wall so nobody can jump over.
		local wall = rect(borders, "InvisibleWall", minX, maxX, minZ, maxZ, 80, 66, HEDGE)
		wall.Transparency = 1
		wall.CastShadow = false
	end

	-- Welcome arches where roads cross from one district into the next (all districts
	-- are open). The front faces the district you arrive from.
	local arches = folder(city, "Arches")
	for _, gate in CityLayout.Gates do
		local district = Config.getDistrict(gate.district)
		local from = Config.getDistrict(gate.from)
		if district and from then
			local model = Instance.new("Model")
			model.Name = "Arch_" .. gate.district
			model:SetAttribute("DistrictId", gate.district)
			local position = Vector3.new(gate.x, 0, gate.z)
			local fromCentre = Vector3.new((from.minX + from.maxX) / 2, 0, (from.minZ + from.maxZ) / 2)
			local towardFrom = if gate.alongX
				then Vector3.new(0, 0, math.sign(fromCentre.Z - gate.z))
				else Vector3.new(math.sign(fromCentre.X - gate.x), 0, 0)
			local base = CFrame.lookAt(position, position + towardFrom)
			-- Pillars stand at the kerbs, leaving the sidewalks behind them free.
			local pillarX = ROAD_HALF + 1.5
			for _, x in { -pillarX, pillarX } do
				Props.part(model, "Pillar", Vector3.new(4, 22, 4), base * CFrame.new(x, 11, 0), Color3.fromRGB(240, 240, 245))
				Props.ball(model, "PillarTop", 5, (base * CFrame.new(x, 23, 0)).Position, district.color)
			end
			local arch = Props.part(model, "Arch", Vector3.new(pillarX * 2 + 4, 5, 3), base * CFrame.new(0, 21, 0), district.color)
			for face, caption in { [Enum.NormalId.Front] = "WELCOME TO " .. district.name:upper(), [Enum.NormalId.Back] = from.name:upper() } do
				local gui = label(arch, face, caption, WHITE, 20)
				-- Keep the text clear of the balls on top of the pillars.
				local padding = gui:FindFirstChild("Text") and (gui :: any).Text:FindFirstChildOfClass("UIPadding")
				if padding then
					padding.PaddingLeft = UDim.new(0.16, 0)
					padding.PaddingRight = UDim.new(0.16, 0)
				end
			end
			model.Parent = arches
		end
	end

	-- Dead ends: barricades.
	local closed = folder(city, "RoadEnds")
	for _, ending in roadEnds() do
		local base = CFrame.lookAt(ending.position, ending.position + ending.inward)
		for i = -2, 2 do
			local stripe = if i % 2 == 0 then Color3.fromRGB(255, 140, 40) else Color3.fromRGB(255, 255, 255)
			Props.part(closed, "Barricade", Vector3.new(4.6, 1.4, 0.6), base * CFrame.new(i * 4.6, 3.4, 0), stripe)
		end
		for _, x in { -11, 11 } do
			Props.part(closed, "BarricadeLeg", Vector3.new(0.6, 4, 0.6), base * CFrame.new(x, 2, 0), Color3.fromRGB(80, 80, 90))
		end
		local sign = Props.part(closed, "RoadClosed", Vector3.new(12, 4, 0.4), base * CFrame.new(0, 7, 0.5), Color3.fromRGB(255, 200, 40))
		label(sign, Enum.NormalId.Back, "🚧 ROAD CLOSED", Color3.fromRGB(60, 40, 20), 30)
	end
end

function CityBuilder.buildBusinesses(city: Instance)
	local folderInstance = folder(city, "Businesses")
	for _, definition in Businesses.List do
		local existing = folderInstance:FindFirstChild(definition.id)
		if existing then
			existing:Destroy()
		end
		CityBuilder.buildBusiness(folderInstance, definition)
		task.wait()
	end
end

function CityBuilder.buildOutskirts(city: Instance)
	local nature = folder(city, "Outskirts")
	local rng = Random.new(99)
	local placed = 0
	for _ = 1, 3000 do
		if placed >= 420 then
			break
		end
		local x = rng:NextNumber(COAST_X + 24, 1500)
		local z = rng:NextNumber(-1350, 1350)
		local insideCity = false
		for _, district in Config.Districts do
			if x > district.minX - 16 and x < district.maxX + 16 and z > district.minZ - 16 and z < district.maxZ + 16 then
				insideCity = true
			end
		end
		if not insideCity then
			if rng:NextNumber() < 0.55 then
				Props.pine(nature, Vector3.new(x, 0, z), rng:NextNumber(1, 1.8))
			else
				Props.tree(nature, Vector3.new(x, 0, z), rng:NextNumber(1, 1.7))
			end
			placed += 1
			if placed % 30 == 0 then
				task.wait()
			end
		end
	end
	-- A few sailboats out at sea.
	for i, p in { Vector3.new(-700 * S, 0, -320 * S), Vector3.new(-760 * S, 0, 260 * S), Vector3.new(-660 * S, 0, 520 * S), Vector3.new(-830 * S, 0, -600 * S) } do
		local sail = Instance.new("Model")
		boat(sail, CFrame.new(p.X, 0.35, p.Z) * CFrame.Angles(0, math.rad(i * 70), 0), AWNING_COLORS[i])
		sail.WorldPivot = CFrame.new(p.X, 0, p.Z)
		sail:ScaleTo(S)
		for _, child in sail:GetChildren() do
			child.Parent = nature
		end
		sail:Destroy()
	end
end

function CityBuilder.buildLighting()
	-- Lighting.Technology cannot be set from scripts; set it to ShadowMap or Future in Properties.
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(120, 120, 135)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 165)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 240, 215)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.4
	for _, name in { "CityAtmosphere", "CityColor", "CityBloom", "CitySunRays" } do
		local old = Lighting:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "CityAtmosphere"
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(200, 225, 255)
	atmosphere.Decay = Color3.fromRGB(140, 170, 220)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.2
	atmosphere.Parent = Lighting
	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "CityColor"
	color.Saturation = 0.18
	color.Contrast = 0.06
	color.Brightness = 0.02
	color.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "CityBloom"
	bloom.Intensity = 0.35
	bloom.Size = 24
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Name = "CitySunRays"
	rays.Intensity = 0.05
	rays.Spread = 0.6
	rays.Parent = Lighting
end

function CityBuilder.buildAll()
	CityBuilder.clear()
	local city = Instance.new("Folder")
	city.Name = "City"
	city.Parent = Workspace
	CityBuilder.buildLighting()
	CityBuilder.buildGround(city)
	task.wait()
	CityBuilder.buildBlocks(city)
	CityBuilder.buildRoadMarkings(city)
	CityBuilder.buildBorders(city)
	CityBuilder.buildBusinesses(city)
	CityBuilder.buildOutskirts(city)
	return city
end

return CityBuilder
