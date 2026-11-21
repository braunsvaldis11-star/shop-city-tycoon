--!strict
-- InteriorBuilder (client only): builds a business interior from its upgrade levels.
-- Upgrades change the room physically: more stations, registers, guest rooms / tables /
-- racks / machines, better floors, walls, lights, furniture and premium centrepieces.
-- This file is the shared shell (room, counter, staff spots, decor tiers). What makes
-- each business look like itself (hotel rooms, cinema rows, gym machines ...) comes
-- from its kit in InteriorKits; station machines come from InteriorStations.
-- Room: 80 x 64 studs, open-top. Local -Z is back-of-house, +Z is the exit door.
-- Zones (room-local): back of house z < -14 (stations, preps), counter at z -12, queues
-- z -9..0.5, front units around the walkway at z 11, entrance z 23.5..32 (front wall
-- decor, plants, sofa, premium centrepieces).
-- Container: ReplicatedStorage.Client

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Businesses = require(Shared.Businesses)
local Props = require(Shared.Props)
local MiniGames = require(Shared.MiniGames)
local D = require(script.Parent.InteriorDraw)
local InteriorStations = require(script.Parent.InteriorStations)
local InteriorKits = require(script.Parent.InteriorKits)

local InteriorBuilder = {}

export type Seat = {
	position: Vector3,
	yaw: number,
	aisle: Vector3, -- point on the walkway (z 11) straight in front of the seat
	approach: Vector3?, -- optional extra step between aisle and seat (cinema rows)
	stand: boolean?, -- browse on foot instead of sitting
	busy: boolean?, -- move the arms (playing, running, typing)
}
export type View = { position: Vector3, yaw: number, aisle: Vector3 }
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
	views: { View }?, -- where attraction visitors stand when not seated (else near the counter)
	wander: { Vector3 }, -- walkway points cleaners move between
	workerLook: Props.NpcLook,
	product: string, -- what staff and customers carry
	managePrompt: ProximityPrompt,
	workPrompt: ProximityPrompt,
	exitTrigger: BasePart,
	exitPrompt: ProximityPrompt,
	banner: TextLabel,
}

local HALF_W, HALF_D, WALL_H = 40, 32, 22
local WHITE, WOOD, DARK, STEEL, GOLD, WARM = D.WHITE, D.WOOD, D.DARK, D.STEEL, D.GOLD, D.WARM
local V = Vector3.new

local STATION_X = { 0, -12, 12, -24, 24 }
local REGISTER_X = { -6, 6, -16, 16 }
local PREP_X = { -12, 12, 0 }
-- Front unit slots in upgrade order. North-row slots are turned around so a unit's
-- front always faces the walkway at z 11.
local SLOTS = {
	V(-17, 0, 4), V(17, 0, 4), V(-17, 0, 18), V(17, 0, 18),
	V(-30, 0, 4), V(30, 0, 4), V(-30, 0, 18), V(30, 0, 18),
}
local AISLE_Z = 11

-- Back-of-house looks: floor, back wall panel and what sits on the wall shelves.
local BACKS: { [string]: { floor: Color3, floorMaterial: Enum.Material, wall: Color3, wallMaterial: Enum.Material, shelf: string } } = {
	kitchen = { floor = Color3.fromRGB(200, 205, 212), floorMaterial = Enum.Material.Slate, wall = Color3.fromRGB(232, 240, 246), wallMaterial = Enum.Material.CeramicTiles, shelf = "jars" },
	stock = { floor = Color3.fromRGB(175, 175, 172), floorMaterial = Enum.Material.Concrete, wall = Color3.fromRGB(205, 200, 190), wallMaterial = Enum.Material.Concrete, shelf = "cartons" },
	office = { floor = Color3.fromRGB(110, 70, 80), floorMaterial = Enum.Material.Fabric, wall = Color3.fromRGB(150, 100, 65), wallMaterial = Enum.Material.WoodPlanks, shelf = "binders" },
	dark = { floor = Color3.fromRGB(55, 58, 68), floorMaterial = Enum.Material.Slate, wall = Color3.fromRGB(42, 44, 56), wallMaterial = Enum.Material.SmoothPlastic, shelf = "gadgets" },
	spa = { floor = Color3.fromRGB(215, 190, 150), floorMaterial = Enum.Material.WoodPlanks, wall = Color3.fromRGB(200, 185, 130), wallMaterial = Enum.Material.WoodPlanks, shelf = "towels" },
	laundry = { floor = Color3.fromRGB(225, 230, 235), floorMaterial = Enum.Material.CeramicTiles, wall = Color3.fromRGB(235, 242, 248), wallMaterial = Enum.Material.CeramicTiles, shelf = "towels" },
	tank = { floor = Color3.fromRGB(70, 95, 120), floorMaterial = Enum.Material.Slate, wall = Color3.fromRGB(50, 120, 180), wallMaterial = Enum.Material.SmoothPlastic, shelf = "buckets" },
}

local function surfaceText(part: BasePart, face: Enum.NormalId, text: string, color: Color3, pixels: number?): TextLabel
	return D.text(part, face, text, color, pixels)
end

local function light(part: BasePart, color: Color3, range: number, brightness: number)
	D.light(part, color, range, brightness)
end

-- One item for a back-wall shelf, by the shelf style.
local function shelfItem(parent: Instance, style: string, cf: CFrame, index: number, theme: any)
	local colors = { Color3.fromRGB(240, 90, 80), Color3.fromRGB(250, 205, 70), Color3.fromRGB(110, 190, 110), Color3.fromRGB(120, 170, 240), WHITE }
	local color = colors[index % #colors + 1]
	if style == "jars" then
		if index % 2 == 0 then
			D.cyl(parent, "Jar", 1.5, 1.1, cf * CFrame.new(0, 0.95, 0), color, nil, true)
		else
			D.box(parent, "Box", V(1.4, 1.8, 1.2), cf * CFrame.new(0, 1.1, 0), color, nil, true)
		end
	elseif style == "cartons" then
		D.box(parent, "Carton", V(1.6, 1.4 + (index % 2) * 0.6, 1.4), cf * CFrame.new(0, 0.9 + (index % 2) * 0.3, 0), Color3.fromRGB(200, 155, 100), nil, true)
	elseif style == "binders" then
		D.box(parent, "Binder", V(0.5, 1.9, 1.3), cf * CFrame.new(-0.4, 1.15, 0), color, nil, true)
		D.box(parent, "Binder", V(0.5, 1.9, 1.3), cf * CFrame.new(0.3, 1.15, 0), colors[(index + 2) % #colors + 1], nil, true)
	elseif style == "gadgets" then
		D.box(parent, "Gadget", V(1.4, 1, 1.2), cf * CFrame.new(0, 0.7, 0), Color3.fromRGB(40, 40, 50), nil, true)
		D.glow(parent, "Led", V(0.8, 0.15, 0.1), cf * CFrame.new(0, 0.8, 0.62), theme.accent)
	elseif style == "towels" then
		D.rod(parent, "Towel", 1.6, 1, cf * CFrame.new(0, 0.7, 0), if index % 2 == 0 then WHITE else theme.accent:Lerp(WHITE, 0.5), D.FABRIC, true)
	else -- buckets
		D.cyl(parent, "Bucket", 1.4, 1.2, cf * CFrame.new(0, 0.9, 0), if index % 2 == 0 then Color3.fromRGB(80, 160, 240) else D.YELLOW, nil, true)
	end
end

-- The material/product the staff carry for this business.
function InteriorBuilder.productStyle(definition: Businesses.Definition): string
	local kit = InteriorKits.get(definition.id)
	return kit.product or definition.productStyle
end

----- Main build -----
function InteriorBuilder.build(parent: Instance, definition: Businesses.Definition, state: any, origin: Vector3): (Model, Layout)
	local upgrades = state.upgrades or {}
	local function lv(id: string): number
		return upgrades[id] or 0
	end
	local kit = InteriorKits.get(definition.id)
	local theme = definition.theme
	local model = Instance.new("Model")
	model.Name = "Interior_" .. definition.id
	local O = CFrame.new(origin)
	local function at(x: number, y: number, z: number): CFrame
		return O * CFrame.new(x, y, z)
	end
	local function world(x: number, z: number): Vector3
		return origin + V(x, 0, z)
	end

	local structure = Instance.new("Model")
	structure.Name = "Structure"
	structure.Parent = model
	local decor = Instance.new("Model")
	decor.Name = "Decor"
	decor.Parent = model
	local back = BACKS[kit.back] or BACKS.kitchen
	local wallsUsed = kit.walls or ""

	----- Floor (Decoration: floor) -----
	local floorTier = lv("floor")
	local floorColors = { Color3.fromRGB(188, 160, 128), WHITE, WOOD, Color3.fromRGB(240, 238, 235) }
	local floorMaterials = { Enum.Material.CeramicTiles, Enum.Material.SmoothPlastic, Enum.Material.WoodPlanks, Enum.Material.Marble }
	Props.part(structure, "Floor", V(HALF_W * 2 + 4, 2, HALF_D * 2 + 4), at(0, -1, 0), floorColors[floorTier + 1], { material = floorMaterials[floorTier + 1] })
	Props.part(structure, "BackFloor", V(HALF_W * 2, 0.1, 18), at(0, 0.05, -23), back.floor, { material = back.floorMaterial, collide = false })
	if floorTier <= 1 and lv("furniture") < 2 then
		-- Runner rug from the door to the counter (the big rug replaces it at Furniture 2).
		Props.part(decor, "Runner", V(7, 0.1, 30), at(0, 0.07, 15), theme.primary:Lerp(Color3.new(0, 0, 0), 0.25), { material = Enum.Material.Fabric, collide = false, shadow = false })
		Props.part(decor, "RunnerTrim", V(8, 0.08, 30.6), at(0, 0.06, 15), Color3.fromRGB(240, 205, 120), { material = Enum.Material.Fabric, collide = false, shadow = false })
	end
	if floorTier == 1 then
		local dark = theme.primary:Lerp(Color3.new(0, 0, 0), 0.15)
		for ix = 0, 9 do
			for iz = 0, 5 do
				if (ix + iz) % 2 == 0 then
					Props.part(decor, "Tile", V(8, 0.1, 8), at(-36 + ix * 8, 0.05, -10 + iz * 8), dark, { collide = false, shadow = false })
				end
			end
		end
	elseif floorTier == 3 then
		Props.part(decor, "InlayX", V(HALF_W * 2 - 6, 0.1, 0.6), at(0, 0.05, 11), GOLD, { collide = false, shadow = false })
		Props.part(decor, "InlayDiamond", V(7, 0.1, 7), at(0, 0.06, 26) * CFrame.Angles(0, math.rad(45), 0), GOLD, { collide = false, shadow = false })
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
	wall("WallBack", V(HALF_W * 2 + 4, WALL_H, 2), at(0, WALL_H / 2, -HALF_D - 1))
	wall("WallLeft", V(2, WALL_H, HALF_D * 2 + 4), at(-HALF_W - 1, WALL_H / 2, 0))
	wall("WallRight", V(2, WALL_H, HALF_D * 2 + 4), at(HALF_W + 1, WALL_H / 2, 0))
	local sideWidth = HALF_W - 5
	wall("WallFrontL", V(sideWidth + 2, WALL_H, 2), at(-(5 + (sideWidth + 2) / 2), WALL_H / 2, HALF_D + 1))
	wall("WallFrontR", V(sideWidth + 2, WALL_H, 2), at(5 + (sideWidth + 2) / 2, WALL_H / 2, HALF_D + 1))
	wall("WallFrontTop", V(10, WALL_H - 13, 2), at(0, 13 + (WALL_H - 13) / 2, HALF_D + 1))
	-- Baseboards on every tier, a painted lower band + chair rail on the basic walls.
	for _, spec in {
		{ V(HALF_W * 2, 0.8, 0.5), at(0, 0.4, -HALF_D + 0.25) },
		{ V(0.5, 0.8, HALF_D * 2), at(-HALF_W + 0.25, 0.4, 0) },
		{ V(0.5, 0.8, HALF_D * 2), at(HALF_W - 0.25, 0.4, 0) },
	} do
		Props.part(decor, "Baseboard", spec[1], spec[2], DARK, { collide = false })
	end
	if wallTier == 0 then
		local band = theme.primary:Lerp(WHITE, 0.2)
		for _, spec in {
			{ V(0.3, 6, HALF_D * 2), at(-HALF_W + 0.15, 3, 0), V(0.5, 0.5, HALF_D * 2), at(-HALF_W + 0.25, 6.2, 0) },
			{ V(0.3, 6, HALF_D * 2), at(HALF_W - 0.15, 3, 0), V(0.5, 0.5, HALF_D * 2), at(HALF_W - 0.25, 6.2, 0) },
		} do
			Props.part(decor, "Wainscot", spec[1], spec[2], band, { collide = false })
			Props.part(decor, "ChairRail", spec[3], spec[4], WHITE, { collide = false })
		end
	end
	-- Back-of-house wall panel (tiles, concrete, wood, bamboo ...).
	Props.part(decor, "Backsplash", V(HALF_W * 2 - 1, 6, 0.2), at(0, 6.5, -HALF_D + 0.55), back.wall, { material = back.wallMaterial, collide = false })
	if kit.back == "dark" then
		D.glow(decor, "BackNeon", V(HALF_W * 2 - 1, 0.3, 0.1), at(0, 9.6, -HALF_D + 0.7), theme.accent)
	elseif kit.back == "tank" then
		for i = 1, 4 do
			D.fish(decor, at(-30 + i * 12, 6 + (i % 2) * 1.5, -HALF_D + 0.75), Color3.fromRGB(150, 210, 255), 2.2)
		end
	end
	if wallTier == 2 then
		for _, spec in {
			{ V(HALF_W * 2, 7, 0.4), at(0, 3.5, -HALF_D + 0.2) },
			{ V(0.4, 7, HALF_D * 2), at(-HALF_W + 0.2, 3.5, 0) },
			{ V(0.4, 7, HALF_D * 2), at(HALF_W - 0.2, 3.5, 0) },
		} do
			Props.part(decor, "Wainscot", spec[1], spec[2], WOOD, { material = Enum.Material.WoodPlanks })
		end
	elseif wallTier == 3 then
		for _, spec in {
			{ V(HALF_W * 2, 0.6, 0.4), at(0, 7, -HALF_D + 0.2) },
			{ V(0.4, 0.6, HALF_D * 2), at(-HALF_W + 0.2, 7, 0) },
			{ V(0.4, 0.6, HALF_D * 2), at(HALF_W - 0.2, 7, 0) },
		} do
			Props.part(decor, "GoldTrim", spec[1], spec[2], GOLD, { material = Enum.Material.Foil, collide = false })
		end
	end
	-- Wall tops and roof beams (the room is open-topped for a clear camera view).
	for _, spec in {
		{ V(HALF_W * 2 + 5, 1.2, 3), at(0, WALL_H, -HALF_D - 1) },
		{ V(HALF_W * 2 + 5, 1.2, 3), at(0, WALL_H, HALF_D + 1) },
		{ V(3, 1.2, HALF_D * 2 + 5), at(-HALF_W - 1, WALL_H, 0) },
		{ V(3, 1.2, HALF_D * 2 + 5), at(HALF_W + 1, WALL_H, 0) },
	} do
		Props.part(structure, "WallCap", spec[1], spec[2], theme.primary)
	end
	for _, z in { -16, 0, 16 } do
		Props.part(structure, "Beam", V(HALF_W * 2, 1.4, 1.4), at(0, WALL_H - 1.5, z), WOOD, { material = Enum.Material.WoodPlanks, collide = false })
	end
	-- Fake windows with daylight (only on walls the kit leaves free).
	for _, side in { -1, 1 } do
		if not string.find(wallsUsed, if side < 0 then "L" else "R", 1, true) then
			for _, z in { 2, 18 } do
				Props.part(decor, "Window", V(0.3, 7, 9), at(side * (HALF_W - 0.1), 10, z), Color3.fromRGB(170, 225, 255), { material = Enum.Material.Neon, transparency = 0.2, collide = false })
				Props.part(decor, "WindowFrame", V(0.5, 7.8, 0.6), at(side * (HALF_W - 0.2), 10, z), WHITE, { collide = false })
			end
		end
	end

	----- Big name sign + level banner -----
	local nameBoard = Props.part(decor, "NameBoard", V(40, 6, 0.6), at(0, 17.5, -HALF_D + 0.3), theme.primary)
	surfaceText(nameBoard, Enum.NormalId.Back, definition.emoji .. " " .. definition.name:upper(), WHITE, 20)
	local bannerPart = Props.part(decor, "LevelBanner", V(14, 3, 0.4), at(0, 13, -HALF_D + 0.3), DARK)
	local banner = surfaceText(bannerPart, Enum.NormalId.Back, "⭐ Level " .. tostring(state.level or 1), GOLD, 25)

	----- Counter + registers (Employees: cashiers) -----
	-- Waist height for the staff and customers (top surface at y 3).
	local counterStyle = kit.counter or "food"
	if counterStyle == "desk" then
		Props.part(structure, "Counter", V(46, 2.6, 3), at(0, 1.3, -12), D.DARKWOOD, { material = Enum.Material.WoodPlanks })
		Props.part(decor, "CounterStripe", V(46.2, 0.5, 0.2), at(0, 1.8, -10.45), theme.primary, { collide = false })
		Props.part(structure, "CounterTop", V(47, 0.4, 4), at(0, 2.8, -12), WHITE, { material = Enum.Material.Marble })
	else
		Props.part(structure, "Counter", V(46, 2.6, 3), at(0, 1.3, -12), theme.primary)
		Props.part(structure, "CounterTop", V(47, 0.4, 4), at(0, 2.8, -12), WHITE, { material = if floorTier >= 3 then Enum.Material.Marble else Enum.Material.SmoothPlastic })
	end
	local registerStyle = kit.register or "till"
	local registers = {}
	for i = 1, math.min(1 + lv("cashiers"), #REGISTER_X) do
		local x = REGISTER_X[i]
		if registerStyle == "desk" then
			D.box(decor, "Monitor", V(2.2, 1.5, 0.2), at(x, 4.1, -12.9) * CFrame.Angles(math.rad(-10), 0, 0), DARK, nil, true)
			D.glow(decor, "MonitorScreen", V(1.9, 1.2, 0.05), at(x, 4.1, -12.78) * CFrame.Angles(math.rad(-10), 0, 0), Color3.fromRGB(120, 200, 255))
			D.ball(decor, "Bell", 0.7, at(x + 1.6, 3.3, -11.2), GOLD, nil, true)
		elseif registerStyle == "ticket" or registerStyle == "teller" then
			-- Glass window between staff and customer, with a little slot.
			local frame = if registerStyle == "teller" then GOLD else theme.primary
			D.glass(decor, "Window", V(4, 4, 0.2), at(x, 5.6, -12), 0.6)
			for _, dx in { -2.1, 2.1 } do
				D.box(decor, "WindowPost", V(0.3, 4.8, 0.3), at(x + dx, 5.4, -12), frame, nil, true)
			end
			D.box(decor, "WindowTop", V(4.5, 0.5, 0.4), at(x, 7.8, -12), frame, nil, true)
			local number = D.box(decor, "WindowNumber", V(2, 0.8, 0.1), at(x, 8.5, -11.8), DARK, nil, true)
			D.text(number, Enum.NormalId.Back, (if registerStyle == "teller" then "TELLER " else "WINDOW ") .. tostring(i), WHITE, 30)
			if registerStyle == "ticket" then
				D.rod(decor, "TicketRoll", 0.8, 0.8, at(x + 1.4, 3.4, -12.6), D.RED, nil, true)
			else
				D.box(decor, "CashTray", V(1.6, 0.3, 1), at(x, 3.15, -11.4), STEEL, D.METAL, true)
			end
		else
			D.box(decor, "Register", V(2.2, 1, 1.6), at(x, 3.5, -12.4), DARK)
			D.glow(decor, "RegisterScreen", V(1.8, 0.9, 0.2), at(x, 4.4, -12.9) * CFrame.Angles(math.rad(-20), 0, 0), Color3.fromRGB(120, 230, 160))
		end
		table.insert(registers, { cashier = world(x, -15.5), queue = world(x, -8.6) })
	end
	if counterStyle == "food" then
		-- Striped canopy over the counter and two hanging menu boards.
		local stripeCount = 12
		for i = 0, stripeCount - 1 do
			local x = -HALF_W + 17 + (i + 0.5) * (46 / stripeCount)
			Props.wedge(decor, "Canopy", V(46 / stripeCount, 1.4, 3), at(x, 10.6, -11.4) * CFrame.Angles(0, math.pi, 0),
				if i % 2 == 0 then theme.primary else WHITE, { collide = false })
		end
		Props.part(decor, "CanopyRail", V(47, 0.4, 0.4), at(0, 9.8, -9.9), theme.primary:Lerp(Color3.new(0, 0, 0), 0.25), { collide = false })
		local menu = kit.menu or { "Special of the Day", "Best Seller", "Combo Deal" }
		for side, x in { -14, 14 } do
			local board = Props.part(decor, "MenuBoard", V(11, 5.2, 0.4), at(x, 15.4, -15.6), Color3.fromRGB(45, 55, 50))
			Props.part(decor, "MenuFrame", V(11.6, 5.8, 0.3), at(x, 15.4, -15.85), WOOD, { collide = false })
			for _, cx in { -4.5, 4.5 } do
				Props.part(decor, "MenuCord", V(0.12, 2.6, 0.12), at(x + cx, 19.3, -15.6), DARK, { collide = false })
			end
			local lines = if side == 1
				then "MENU\n" .. menu[1] .. "  $5\n" .. menu[2] .. "  $7"
				else definition.emoji .. " TODAY\n" .. menu[3] .. "  $9\nSmile  FREE"
			surfaceText(board, Enum.NormalId.Back, lines, Color3.fromRGB(250, 245, 225), 20)
		end
	else
		-- One hanging sign over the counter (CHECKOUT, RECEPTION, TICKETS ...).
		local sign = D.box(decor, "CounterSign", V(18, 3, 0.4), at(0, 11.2, -12.4), if counterStyle == "desk" then DARK else theme.primary, nil, true)
		D.box(decor, "CounterSignTrim", V(18.6, 3.6, 0.3), at(0, 11.2, -12.65), if counterStyle == "desk" then GOLD else WHITE, nil, true)
		surfaceText(sign, Enum.NormalId.Back, kit.sign or (definition.emoji .. " " .. definition.name:upper()), WHITE, 20)
		for _, cx in { -7, 7 } do
			D.box(decor, "SignCord", V(0.12, 6.4, 0.12), at(cx, 15.9, -12.4), DARK, nil, true)
		end
	end
	-- Wall shelves on both sides of the back of house.
	for _, sx in { -1, 1 } do
		for row, y in { 9.6, 12.8 } do
			Props.part(decor, "Shelf", V(8, 0.4, 1.8), at(sx * 32.5, y, -HALF_D + 1.1), WOOD, { material = Enum.Material.WoodPlanks, collide = false })
			for j = 0, 3 do
				shelfItem(decor, back.shelf, at(sx * 32.5 - 2.85 + j * 1.9, y + 0.2, -HALF_D + 1.1), j + row + (if sx > 0 then 2 else 0), theme)
			end
		end
	end

	local pickups = { world(20, -12), world(-20, -12) }
	for _, x in { 20, -20 } do
		Props.part(decor, "PickupTray", V(4, 0.2, 2.6), at(x, 3.1, -12), STEEL)
	end

	----- Production stations (equipment tier + extra stations) -----
	local stations, stationParts = {}, {}
	local equipmentTier = math.clamp(lv("equipment"), 0, 4)
	for i = 1, math.min(1 + lv("stations"), #STATION_X) do
		local x = STATION_X[i]
		local glow = InteriorStations.build(decor, kit.station, at(x, 0, -28) * CFrame.Angles(0, math.pi, 0), equipmentTier, theme)
		table.insert(stations, world(x, -23.5))
		table.insert(stationParts, glow)
	end
	local preps = {}
	local prepStyle = if kit.back == "laundry" then "spa" else kit.back
	for i = 1, math.min(lv("prep"), #PREP_X) do
		local x = PREP_X[i]
		InteriorStations.prep(decor, prepStyle, at(x, 0, -19) * CFrame.Angles(0, math.pi, 0), theme)
		table.insert(preps, world(x, -16.6))
	end

	----- Front of the room: the business's own units (Seating: tables + seating) -----
	local units = math.min(1 + lv("tables"), #SLOTS - 1)
	local ctx = {
		def = definition,
		theme = theme,
		lv = lv,
		tier = equipmentTier,
		seatTier = math.clamp(lv("seating"), 0, 3),
		units = units,
		decor = decor,
		at = at,
		world = world,
		origin = origin,
	}
	local seats: { Seat } = {}
	local views: { View }? = nil
	if kit.front then
		local builtSeats, builtViews = kit.front(ctx)
		seats = builtSeats
		views = builtViews
	else
		for i = 1, units do
			local slot = SLOTS[i]
			local yaw = if slot.Z > AISLE_Z then math.pi else 0
			local U = at(slot.X, 0, slot.Z) * CFrame.Angles(0, yaw, 0)
			-- Units beside the queues (inner south slots) stay a bit shallower.
			local depth = if math.abs(slot.X) < 20 and slot.Z < AISLE_Z and not definition.entryFee then -3 else -4.5
			local unit = Instance.new("Model")
			unit.Name = "Unit" .. tostring(i)
			unit.Parent = decor
			local unitCtx = table.clone(ctx)
			unitCtx.decor = unit
			local function c(x: number, y: number, z: number): CFrame
				return U * CFrame.new(x, y, z)
			end
			for _, s in kit.unit(unitCtx, c, i, depth) do
				local position = (U * CFrame.new(s.x, 0, s.z)).Position
				table.insert(seats, {
					position = position,
					yaw = yaw + s.yaw,
					aisle = V(position.X, origin.Y, origin.Z + AISLE_Z),
					stand = s.stand,
					busy = s.busy,
				})
			end
		end
	end
	if kit.extras then
		local extras = Instance.new("Model")
		extras.Name = "Extras"
		extras.Parent = decor
		local extrasCtx = table.clone(ctx)
		extrasCtx.decor = extras
		kit.extras(extrasCtx)
	end
	local wander = {}
	for x = -34, 34, 4 do
		table.insert(wander, world(x, AISLE_Z))
	end

	----- Lighting -----
	local lightTier = lv("lighting")
	if lightTier == 0 then
		-- Simple hanging bulbs so even a brand-new shop has warm light.
		for _, spot in { V(-17, 0, 11), V(17, 0, 11), V(0, 0, 22) } do
			Props.part(decor, "Cord", V(0.15, 5.8, 0.15), at(spot.X, 17.6, spot.Z), DARK, { collide = false })
			Props.part(decor, "Shade", V(2.2, 0.9, 2.2), at(spot.X, 14.5, spot.Z), DARK, { collide = false })
			local bulb = Props.ball(decor, "Bulb", 1.1, at(spot.X, 13.8, spot.Z).Position, WARM, { material = Enum.Material.Neon, collide = false })
			light(bulb, WARM, 24, 0.9)
		end
	end
	for _, spec in { { -1, -4 }, { 1, -4 }, { -1, 24 }, { 1, 24 } } do
		local sconce = Props.part(decor, "Sconce", V(0.8, 1.6, 1.6), at(spec[1] * (HALF_W - 0.5), 12, spec[2]), WARM, { material = Enum.Material.Neon, collide = false })
		light(sconce, WARM, 26, 0.8 + lightTier * 0.25)
	end
	if lightTier >= 1 then
		for i = 1, math.min(units, 4) do
			local spot = SLOTS[i]
			Props.part(decor, "Cord", V(0.15, 7, 0.15), at(spot.X, 16.5, spot.Z), DARK, { collide = false })
			Props.part(decor, "Pendant", V(3, 1.6, 3), at(spot.X, 12.6, spot.Z), theme.primary, { collide = false })
			local bulb = Props.ball(decor, "Bulb", 1.2, at(spot.X, 11.6, spot.Z).Position, WARM, { material = Enum.Material.Neon, collide = false })
			if i <= 2 then
				light(bulb, WARM, 18, 1)
			end
		end
	end
	if lightTier >= 2 then
		for i = 0, 13 do
			local x = -HALF_W + 3 + i * 5.9
			local colors = { Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 140, 160), Color3.fromRGB(140, 220, 255) }
			Props.ball(decor, "StringLight", 0.8, at(x, 19, -HALF_D + 0.6).Position, colors[(i % 3) + 1], { material = Enum.Material.Neon, collide = false })
			Props.ball(decor, "StringLight", 0.8, at(x, 19, HALF_D - 0.6).Position, colors[(i % 3) + 1], { material = Enum.Material.Neon, collide = false })
		end
		local center = Props.part(decor, "Chandelier", V(4, 1, 4), at(0, 17, 8), GOLD, { collide = false })
		light(center, WARM, 40, 1.6)
	end
	if lightTier >= 3 then
		for _, spec in {
			{ V(HALF_W * 2 - 2, 0.5, 0.3), at(0, 20.5, -HALF_D + 0.3), theme.accent },
			{ V(0.3, 0.5, HALF_D * 2 - 2), at(-HALF_W + 0.3, 20.5, 0), theme.primary },
			{ V(0.3, 0.5, HALF_D * 2 - 2), at(HALF_W - 0.3, 20.5, 0), theme.primary },
		} do
			Props.part(decor, "NeonStrip", spec[1], spec[2], spec[3], { material = Enum.Material.Neon, collide = false })
		end
		local neon = Props.part(decor, "NeonSign", V(12, 3.6, 0.3), at(29, 16.6, HALF_D - 0.4), Color3.fromRGB(30, 20, 40), { collide = false })
		surfaceText(neon, Enum.NormalId.Front, definition.emoji .. " OPEN 24/7", theme.accent:Lerp(WHITE, 0.3), 25)
	end

	----- Furniture & plants (entrance area) -----
	local furnitureTier = lv("furniture")
	-- Every shop: plants by the door, a bin, a poster and a wall clock.
	for _, p in { V(-8.5, 0, 29.5), V(8.5, 0, 29.5) } do
		D.plant(decor, origin + p, 0.85)
	end
	Props.cylinder(decor, "Bin", 2.6, 1.8, at(-21.5, 1.3, 30.5).Position, Color3.fromRGB(70, 130, 90))
	Props.cylinder(decor, "BinLid", 0.3, 2, at(-21.5, 2.75, 30.5).Position, Color3.fromRGB(50, 95, 65), { collide = false })
	if furnitureTier < 2 then
		Props.part(decor, "PosterFrame", V(5, 6.4, 0.3), at(29, 10, HALF_D - 0.25), WOOD, { collide = false })
		local poster = Props.part(decor, "Poster", V(4.4, 5.8, 0.35), at(29, 10, HALF_D - 0.3), theme.primary:Lerp(WHITE, 0.15), { collide = false })
		surfaceText(poster, Enum.NormalId.Front, definition.emoji .. "\nBEST IN\nTOWN!", WHITE, 25)
	end
	Props.part(decor, "Clock", V(0.4, 3.2, 3.2), at(-HALF_W + 0.3, 15.5, -4), WHITE, { shape = Enum.PartType.Cylinder, collide = false })
	Props.part(decor, "ClockRim", V(0.3, 3.6, 3.6), at(-HALF_W + 0.2, 15.5, -4), DARK, { shape = Enum.PartType.Cylinder, collide = false })
	Props.part(decor, "HourHand", V(0.1, 0.9, 0.18), at(-HALF_W + 0.55, 15.5 + 0.4, -4), DARK, { collide = false })
	Props.part(decor, "MinuteHand", V(0.1, 0.18, 1.3), at(-HALF_W + 0.55, 15.5, -4 + 0.6), DARK, { collide = false })
	if furnitureTier >= 1 then
		for _, p in { V(-38, 0, 27.5), V(38, 0, 27.5) } do
			D.plant(decor, origin + p, 1)
		end
	end
	if furnitureTier >= 2 then
		local paintings = { Color3.fromRGB(255, 160, 80), Color3.fromRGB(110, 190, 255), Color3.fromRGB(160, 230, 130) }
		for i, x in { 22, 29, 36 } do
			Props.part(decor, "Frame", V(5.5, 5, 0.4), at(x, 10.5, HALF_D - 0.3), GOLD, { collide = false })
			Props.part(decor, "Painting", V(4.6, 4, 0.5), at(x, 10.5, HALF_D - 0.35), paintings[i], { collide = false })
		end
		Props.part(decor, "Rug", V(10, 0.1, 22), at(0, 0.07, 18), theme.primary:Lerp(WHITE, 0.35), { material = Enum.Material.Fabric, collide = false })
	end
	if furnitureTier >= 3 then
		local sofa = theme.accent
		Props.part(decor, "Sofa", V(11, 2.2, 3.5), at(29.5, 1.1, 29.2), sofa, { material = Enum.Material.Fabric })
		Props.part(decor, "SofaBack", V(11, 4, 1), at(29.5, 3, 30.9), sofa, { material = Enum.Material.Fabric })
		Props.part(decor, "CoffeeTable", V(6, 1.6, 3), at(29.5, 0.8, 25.4), WOOD, { material = Enum.Material.WoodPlanks })
		local lamp = Props.ball(decor, "FloorLamp", 2, at(22.5, 7, 30).Position, WARM, { material = Enum.Material.Neon, collide = false })
		Props.part(decor, "LampPole", V(0.3, 6, 0.3), at(22.5, 3, 30), DARK, { collide = false })
		light(lamp, WARM, 16, 1)
	end

	----- Premium decor (the business's own centrepiece) -----
	local premium = lv("premium")
	if premium >= 1 then
		Props.part(decor, "Pedestal", V(5, 3, 5), at(17, 1.5, 27.5), WHITE, { material = Enum.Material.Marble })
		local statue = Props.npc(decor, Random.new(3), { shirt = GOLD, pants = GOLD, hat = GOLD })
		for _, d in statue:GetDescendants() do
			if d:IsA("BasePart") then
				d.Color = GOLD
				d.Material = Enum.Material.Foil
			end
		end
		statue:PivotTo(at(17, 6, 27.5) * CFrame.Angles(0, math.pi, 0))
		statue:ScaleTo(1.4)
	end
	if premium >= 2 then
		Props.cylinder(decor, "FountainBasin", 1.6, 9, at(-15, 0.8, 27).Position, WHITE, { material = Enum.Material.Marble })
		Props.cylinder(decor, "FountainWater", 0.3, 7.6, at(-15, 1.6, 27).Position, Color3.fromRGB(90, 190, 255), { material = Enum.Material.Glass, transparency = 0.2 })
		Props.cylinder(decor, "FountainTier", 4, 1.4, at(-15, 3, 27).Position, GOLD, { material = Enum.Material.Foil })
		local top = Props.ball(decor, "FountainTop", 2.2, at(-15, 5.4, 27).Position, GOLD, { material = Enum.Material.Foil })
		local spray = Instance.new("ParticleEmitter")
		spray.Color = ColorSequence.new(Color3.fromRGB(190, 235, 255))
		spray.Size = NumberSequence.new(0.4, 0.1)
		spray.Lifetime = NumberRange.new(0.8, 1)
		spray.Rate = 30
		spray.Speed = NumberRange.new(6, 8)
		spray.SpreadAngle = Vector2.new(30, 30)
		spray.Acceleration = V(0, -20, 0)
		spray.EmissionDirection = Enum.NormalId.Top
		spray.Parent = top
	end

	----- Marketing visuals: a poster per ads level, review stars per reputation -----
	for i = 1, math.min(lv("ads"), 5) do
		local poster = Props.part(decor, "AdPoster", V(3, 4, 0.3), at(-35 + (i - 1) * 5, 15.5, HALF_D - 0.3), theme.accent:Lerp(WHITE, 0.2), { collide = false })
		surfaceText(poster, Enum.NormalId.Front, "SALE!", WHITE, 25)
	end
	if lv("reputation") > 0 then
		local stars = Props.part(decor, "ReviewBoard", V(8, 2.4, 0.3), at(-21, 10, -HALF_D + 0.3), WHITE, { collide = false })
		surfaceText(stars, Enum.NormalId.Back, string.rep("⭐", lv("reputation")), GOLD, 25)
	end

	----- Manage board (by the door), mini game point, exit -----
	local board = Props.part(structure, "ManageBoard", V(12, 8, 0.6), at(-30, 7, HALF_D - 0.3), Color3.fromRGB(45, 50, 70))
	surfaceText(board, Enum.NormalId.Front, "📋 MANAGE\nUpgrades • Staff • Decor", WHITE, 25)
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
	local workPoint = Props.part(structure, "WorkPoint", V(2, 2, 2), at(0, 3.8, -10.4), WHITE, { transparency = 1, collide = false })
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

	Props.part(structure, "ExitPortal", V(10, 13, 0.4), at(0, 6.5, HALF_D + 1.8), Color3.fromRGB(170, 230, 255), { material = Enum.Material.Neon, transparency = 0.2 })
	Props.part(structure, "ExitFrame", V(12, 1, 1), at(0, 13.5, HALF_D), theme.accent)
	local exitSign = Props.part(structure, "ExitSign", V(7, 2.2, 0.4), at(0, 15.5, HALF_D - 0.1), Color3.fromRGB(40, 180, 80), { material = Enum.Material.Neon })
	surfaceText(exitSign, Enum.NormalId.Front, "🚪 EXIT TO CITY", WHITE, 30)
	local exitTrigger = Props.part(structure, "ExitTrigger", V(9, 12, 1.5), at(0, 6, HALF_D + 0.6), WHITE, { transparency = 1, collide = false })
	exitTrigger.CanTouch = true
	local exitPrompt = Instance.new("ProximityPrompt")
	exitPrompt.Name = "ExitPrompt"
	exitPrompt.ActionText = "Exit to City"
	exitPrompt.ObjectText = definition.name
	exitPrompt.HoldDuration = 0.3
	exitPrompt.MaxActivationDistance = 10
	exitPrompt.RequiresLineOfSight = false
	exitPrompt.Parent = exitTrigger
	Props.part(structure, "WelcomeMat", V(10, 0.1, 5), at(0, 0.06, HALF_D - 3), theme.primary, { collide = false })

	-- Staff look: chefs in white for food places, the business's own uniform elsewhere.
	local workerLook: Props.NpcLook = kit.worker
		or (if kit.food then { shirt = WHITE, pants = Color3.fromRGB(50, 50, 60), hat = Color3.fromRGB(255, 255, 255) }
			else { shirt = theme.accent:Lerp(DARK, 0.15), pants = Color3.fromRGB(50, 50, 60) })

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
		views = views,
		wander = wander,
		workerLook = workerLook,
		product = InteriorBuilder.productStyle(definition),
		managePrompt = managePrompt,
		workPrompt = workPrompt,
		exitTrigger = exitTrigger,
		exitPrompt = exitPrompt,
		banner = banner,
	}
end

-- Small product prop that customers carry out.
function InteriorBuilder.product(style: string, theme: any): BasePart
	return InteriorStations.product(style, theme)
end

return InteriorBuilder
