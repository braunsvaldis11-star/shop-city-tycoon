--!strict
-- InteriorKits (client only): what makes every business look like itself inside.
-- The shared shell (InteriorBuilder) builds the room, counter, staff spots and decor
-- tiers; a kit picks the back-of-house look, the station machine, the counter and till
-- style, and builds the front of the room: hotel guest rooms, cinema seat rows, gym
-- machines, aquarium tanks, clothing racks, diner booths ...
--
-- Front units fill the slot grid in upgrade order (Seating: tables = one more unit).
-- A unit is built in its own frame `c(x, y, z)`: x -5.5..5.5, z `back`..4.5, and +Z
-- always points at the aisle (z = 11) customers walk along. Seats are returned in that
-- frame: { x, z, yaw } (yaw 0 faces -Z, +90° faces -X, -90° faces +X, 180° faces the
-- aisle), `stand` for people who browse on their feet, `busy` for people who move
-- their arms (playing, running). Customers walk from the aisle straight down the
-- seat's x, so nothing may stand between a seat and the front edge of its unit.
--
-- Extras (walls and corners) stay out of the walking areas: side walls |x| >= 36
-- between z -1 and 21, back corners x ±24..39 / z -14..-8, overhead above y 14.
-- Container: ReplicatedStorage.Client

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local D = require(script.Parent.InteriorDraw)
local Props = require(ReplicatedStorage:WaitForChild("Shared").Props)

local V = Vector3.new
local box, glow, glass, cyl, rod, ball, wedge = D.box, D.glow, D.glass, D.cyl, D.rod, D.ball, D.wedge
local WHITE, WOOD, DARK, STEEL, GOLD = D.WHITE, D.WOOD, D.DARK, D.STEEL, D.GOLD
local R90 = math.pi / 2
local PI = math.pi
local FABRIC, METAL, NEON, PLANKS, MARBLE = D.FABRIC, D.METAL, D.NEON, D.PLANKS, D.MARBLE

export type Seat = { x: number, z: number, yaw: number, stand: boolean?, busy: boolean? }
export type WorldSeat = { position: Vector3, yaw: number, aisle: Vector3, approach: Vector3?, stand: boolean?, busy: boolean? }
export type View = { position: Vector3, yaw: number, aisle: Vector3 }
type Frame = (number, number, number) -> CFrame

local Kits: any = {}

----- Shared helpers -----
local function turn(cf: CFrame, yaw: number): CFrame
	return cf * CFrame.Angles(0, yaw, 0)
end

-- Two chairs facing each other across a table, at x = ±dist.
local function chairs(k: any, c: Frame, dist: number, tier: number, frame: Color3?, cushion: Color3?): { Seat }
	D.chair(k.decor, turn(c(-dist, 0, 0), -R90), tier, frame, cushion)
	D.chair(k.decor, turn(c(dist, 0, 0), R90), tier, frame, cushion)
	return { { x = -dist, z = 0, yaw = -R90 }, { x = dist, z = 0, yaw = R90 } }
end

local function armchair(m: Instance, cf: CFrame, color: Color3, material: Enum.Material?, tall: boolean?)
	box(m, "ArmSeat", V(3.2, 1.9, 3), cf * CFrame.new(0, 0.95, 0), color, material)
	local backHeight = if tall then 5 else 3.2
	box(m, "ArmBack", V(3.2, backHeight, 0.8), cf * CFrame.new(0, 1.9 + backHeight / 2 - 0.4, 1.3), color, material)
	for _, s in { -1, 1 } do
		box(m, "ArmRest", V(0.6, 1.1, 3), cf * CFrame.new(s * 1.6, 2.4, 0), color, material)
	end
end

-- Booth: two benches facing each other across a small table. Seats at x ±3.5.
local function booth(k: any, c: Frame, seat: Color3, frame: Color3, top: Color3, material: Enum.Material?): { Seat }
	local m = k.decor
	box(m, "BoothTable", V(3, 0.4, 3.6), c(0, 3.2, -0.6), top)
	box(m, "BoothTableEdge", V(3.1, 0.2, 3.7), c(0, 2.95, -0.6), frame, METAL)
	box(m, "BoothLeg", V(0.6, 2.9, 0.6), c(0, 1.45, -0.6), frame, METAL)
	for _, s in { -1, 1 } do
		box(m, "BenchSeat", V(2.4, 1.9, 3.6), c(s * 3.5, 0.95, -0.6), seat, material)
		box(m, "BenchBack", V(0.8, 3.8, 3.6), c(s * 5, 2.9, -0.6), seat, material)
		box(m, "BenchTrim", V(0.9, 0.3, 3.7), c(s * 5, 4.9, -0.6), frame, METAL)
	end
	return { { x = -3.5, z = 0.3, yaw = -R90 }, { x = 3.5, z = 0.3, yaw = R90 } }
end

-- Thin panel against a side wall (side -1 = left, 1 = right), inner face toward the room.
local function wallBox(k: any, name: string, side: number, z: number, y: number, height: number, width: number, depth: number, color: Color3, material: Enum.Material?): Part
	return box(k.decor, name, V(depth, height, width), k.at(side * (39.6 - depth / 2), y, z), color, material, true)
end

local function wallText(part: BasePart, side: number, text: string, color: Color3?, pixels: number?)
	D.text(part, if side < 0 then Enum.NormalId.Right else Enum.NormalId.Left, text, color or WHITE, pixels)
end

-- Back corners (the free floor beside the counter), centre ±31.5, -11.
local function corner(k: any, side: number, dx: number, y: number, dz: number): CFrame
	return k.at(side * 31.5 + dx, y, -11 + dz)
end

local function fishColor(i: number): Color3
	return ({ Color3.fromRGB(255, 140, 40), Color3.fromRGB(255, 230, 60), Color3.fromRGB(255, 90, 120), Color3.fromRGB(90, 200, 255), Color3.fromRGB(180, 120, 255) })[(i - 1) % 5 + 1]
end

local function lantern(k: any, x: number, z: number, color: Color3)
	box(k.decor, "LanternCord", V(0.12, 4.5, 0.12), k.at(x, 18.2, z), DARK, nil, true)
	local l = ball(k.decor, "Lantern", 2, k.at(x, 15.2, z), color, NEON, true)
	box(k.decor, "LanternCap", V(1.2, 0.3, 1.2), k.at(x, 16.3, z), DARK, nil, true)
	box(k.decor, "LanternBase", V(1.2, 0.3, 1.2), k.at(x, 14.1, z), DARK, nil, true)
	local _ = l
end

local function teddy(m: Instance, cf: CFrame, s: number, color: Color3?)
	local fur = color or Color3.fromRGB(170, 110, 60)
	ball(m, "TeddyBody", 2 * s, cf * CFrame.new(0, 1.2 * s, 0), fur, nil, true)
	ball(m, "TeddyHead", 1.5 * s, cf * CFrame.new(0, 2.7 * s, 0), fur, nil, true)
	for _, x in { -0.6, 0.6 } do
		ball(m, "TeddyEar", 0.6 * s, cf * CFrame.new(x * s, 3.4 * s, 0), fur, nil, true)
		ball(m, "TeddyPaw", 0.8 * s, cf * CFrame.new(x * 1.5 * s, 1.5 * s, -0.4 * s), fur, nil, true)
	end
	ball(m, "TeddyNose", 0.5 * s, cf * CFrame.new(0, 2.6 * s, -0.65 * s), Color3.fromRGB(240, 210, 170), nil, true)
end

local function dog(m: Instance, cf: CFrame, color: Color3)
	box(m, "DogBody", V(1, 0.9, 1.8), cf * CFrame.new(0, 0.9, 0), color, nil, true)
	box(m, "DogHead", V(0.9, 0.9, 0.9), cf * CFrame.new(0, 1.5, -1.1), color, nil, true)
	box(m, "DogEar", V(1.1, 0.4, 0.3), cf * CFrame.new(0, 1.9, -1), color:Lerp(Color3.new(0, 0, 0), 0.25), nil, true)
	for _, x in { -0.3, 0.3 } do
		for _, z in { -0.6, 0.6 } do
			box(m, "DogLeg", V(0.3, 0.5, 0.3), cf * CFrame.new(x, 0.25, z), color, nil, true)
		end
	end
	box(m, "DogTail", V(0.2, 0.2, 0.7), cf * CFrame.new(0, 1.3, 1.1) * CFrame.Angles(math.rad(35), 0, 0), color, nil, true)
end

local function balloons(m: Instance, cf: CFrame, count: number, size: number)
	for j = 1, count do
		local a = j * 2.4
		local p = cf * CFrame.new(math.cos(a) * 0.9, 5 + (j % 3) * 0.9, math.sin(a) * 0.9)
		ball(m, "Balloon", size, p, D.BRIGHT[(j - 1) % #D.BRIGHT + 1], nil, true)
		box(m, "String", V(0.05, 4.6, 0.05), cf * CFrame.new(math.cos(a) * 0.45, 2.6 + (j % 3) * 0.45, math.sin(a) * 0.45), WHITE, nil, true)
	end
end

local CAR_COLORS = {
	Color3.fromRGB(220, 40, 45), Color3.fromRGB(40, 120, 230), Color3.fromRGB(250, 250, 250),
	Color3.fromRGB(30, 30, 35), Color3.fromRGB(255, 200, 40), Color3.fromRGB(60, 190, 110), Color3.fromRGB(150, 90, 220),
}

----- Kits -----

Kits.Pizza = {
	back = "kitchen", station = "pizzaOven", counter = "food", register = "till", food = true, walls = "R",
	menu = { "Margherita", "Pepperoni", "Quattro Formaggi" },
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		box(m, "Table", V(5, 0.4, 5), c(0, 3.2, 0), WOOD, PLANKS)
		cyl(m, "TableLeg", 3, 0.8, c(0, 1.5, 0), DARK)
		for ix = 0, 2 do
			for iz = 0, 2 do
				box(m, "Check", V(1.68, 0.05, 1.68), c(-1.68 + ix * 1.68, 3.43, -1.68 + iz * 1.68), if (ix + iz) % 2 == 0 then D.RED else WHITE, nil, true)
			end
		end
		cyl(m, "Bottle", 1.4, 0.7, c(0, 4.15, -0.6), Color3.fromRGB(40, 120, 60), D.GLASSMAT, true)
		cyl(m, "Candle", 0.6, 0.3, c(0, 5.15, -0.6), WHITE, nil, true)
		ball(m, "Flame", 0.35, c(0, 5.6, -0.6), D.ORANGE, NEON, true)
		cyl(m, "Pizza", 0.15, 2, c(0, 3.55, 1), Color3.fromRGB(240, 190, 90), nil, true)
		for j = 0, 3 do
			cyl(m, "Pepperoni", 0.06, 0.4, c(-0.4 + (j % 2) * 0.8, 3.65, 0.6 + math.floor(j / 2) * 0.8), D.RED, nil, true)
		end
		return chairs(k, c, 4.4, k.seatTier, nil, D.RED)
	end,
	extras = function(k: any)
		local m = k.decor
		local flag = { Color3.fromRGB(0, 150, 70), WHITE, Color3.fromRGB(210, 40, 50) }
		for _, z in { 4, 18 } do
			D.bunting(m, k.at(-38, 17, z).Position, k.at(38, 17, z).Position, flag)
		end
		-- Wine barrels, back-left.
		for j, dx in { -4, 0, 4 } do
			local barrel = cyl(m, "Barrel", 3.6, 3, corner(k, -1, dx, 1.8, -0.5), Color3.fromRGB(140, 90, 50), PLANKS)
			local _ = barrel
			for _, y in { 0.6, 3 } do
				cyl(m, "Hoop", 0.25, 3.1, corner(k, -1, dx, y, -0.5), DARK, METAL, true)
			end
			if j == 2 then
				cyl(m, "WineBottle", 1.4, 0.5, corner(k, -1, dx, 4.3, -0.5), Color3.fromRGB(60, 20, 40), D.GLASSMAT, true)
			end
		end
		-- Olive tree in a pot, back-right.
		cyl(m, "TreePot", 2.4, 3, corner(k, 1, 0, 1.2, 0), Color3.fromRGB(200, 110, 70))
		cyl(m, "TreeTrunk", 6, 0.7, corner(k, 1, 0, 5, 0), Color3.fromRGB(120, 90, 60), nil, true)
		for j = 0, 4 do
			ball(m, "Olive", 3.2, corner(k, 1, math.cos(j * 1.3) * 1.6, 8.2 + (j % 2), math.sin(j * 1.3) * 1.2), Color3.fromRGB(110, 150, 70), nil, true)
		end
		-- "Napoli" mural on the right wall.
		local mural = wallBox(k, "Mural", 1, 10, 10, 8, 18, 0.3, Color3.fromRGB(110, 170, 220))
		wallText(mural, 1, "🍕 NAPOLI 🌋", WHITE, 22)
		wallBox(k, "MuralSea", 1, 10, 6.6, 1.2, 18, 0.35, Color3.fromRGB(40, 110, 180))
		wallBox(k, "MuralFrame", 1, 10, 10, 8.6, 18.6, 0.2, WOOD)
	end,
}

Kits.Bakery = {
	back = "kitchen", station = "breadOven", counter = "food", register = "till", food = true, walls = "LR",
	menu = { "Croissant", "Baguette", "Éclair" },
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		cyl(m, "Top", 0.3, 4, c(0, 3.1, 0), WHITE, MARBLE)
		cyl(m, "Pedestal", 3, 0.5, c(0, 1.5, 0), DARK, METAL)
		cyl(m, "Foot", 0.2, 2, c(0, 0.1, 0), DARK, METAL)
		cyl(m, "Plate", 0.1, 1.6, c(0, 3.3, 0.3), WHITE, nil, true)
		rod(m, "Croissant", 1.2, 0.6, c(0, 3.6, 0.3), Color3.fromRGB(225, 160, 80), nil, true)
		cyl(m, "Cup", 0.6, 0.6, c(-0.9, 3.55, -0.7), WHITE, nil, true)
		if k.seatTier == 0 then
			for _, s in { -1, 1 } do
				D.stool(m, c(s * 3.6, 0, 0), 0, WOOD)
			end
			return { { x = -3.6, z = 0, yaw = -R90 }, { x = 3.6, z = 0, yaw = R90 } }
		end
		local cushions = { WHITE, Color3.fromRGB(240, 170, 110), Color3.fromRGB(150, 60, 80) }
		return chairs(k, c, 3.8, k.seatTier, Color3.fromRGB(70, 50, 40), cushions[k.seatTier])
	end,
	extras = function(k: any)
		local m = k.decor
		-- Bread racks along both side walls.
		for _, side in { -1, 1 } do
			wallBox(k, "BreadRack", side, 10, 4.5, 9, 18, 0.4, Color3.fromRGB(150, 100, 60), PLANKS)
			for row, y in { 2, 4.6, 7.2 } do
				box(m, "RackBoard", V(2.4, 0.3, 18), k.at(side * 38.2, y - 0.55, 10), Color3.fromRGB(150, 100, 60), PLANKS, true)
				for j = 0, 4 do
					local z = 2 + j * 4
					box(m, "Basket", V(2, 0.8, 3), k.at(side * 38.2, y, z), Color3.fromRGB(210, 170, 110), FABRIC, true)
					if (j + row) % 2 == 0 then
						for b = 0, 2 do
							rod(m, "Baguette", 3, 0.5, k.at(side * 38.2, y + 0.6, z - 0.8 + b * 0.8) * CFrame.Angles(0, R90, math.rad(15)), Color3.fromRGB(220, 165, 90), nil, true)
						end
					else
						for b = 0, 1 do
							ball(m, "Loaf", 1.3, k.at(side * 38.2, y + 0.7, z - 0.6 + b * 1.2), Color3.fromRGB(200, 140, 70), nil, true)
						end
					end
				end
			end
			local sign = wallBox(k, "BreadSign", side, 10, 11, 2, 10, 0.3, Color3.fromRGB(90, 60, 40))
			wallText(sign, side, "FRESH BREAD", D.CREAM, 25)
		end
		-- Three-tier cake stand, back-right.
		box(m, "CakeTable", V(5, 3, 4), corner(k, 1, 0, 1.5, 0), WHITE)
		for t, d in { 3.6, 2.6, 1.6 } do
			cyl(m, "Cake", 1.1, d, corner(k, 1, 0, 3.55 + (t - 1) * 1.1, 0), if t % 2 == 1 then Color3.fromRGB(255, 190, 210) else WHITE, nil, true)
		end
		ball(m, "Cherry", 0.6, corner(k, 1, 0, 6.6, 0), D.RED, nil, true)
		-- Flour sacks, back-left.
		for j = 0, 3 do
			local sack = box(m, "Flour", V(2.4, 3, 1.6), corner(k, -1, -4 + j * 2.6, 1.5 + (if j == 3 then 0 else 0), (j % 2) * 0.8), Color3.fromRGB(240, 230, 205), FABRIC)
			if j == 1 then
				D.text(sack, Enum.NormalId.Back, "FLOUR", Color3.fromRGB(150, 110, 70), 20)
			end
		end
	end,
}

Kits.Coffee = {
	back = "kitchen", station = "espresso", counter = "food", register = "till", food = true, walls = "R",
	menu = { "Espresso", "Latte", "Cappuccino" },
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		box(m, "LowTable", V(3, 1.4, 2.4), c(0, 0.7, 0), Color3.fromRGB(110, 75, 50), PLANKS)
		box(m, "LowTop", V(3.4, 0.2, 2.8), c(0, 1.5, 0), Color3.fromRGB(90, 60, 40), PLANKS)
		for _, x in { -0.7, 0.7 } do
			cyl(m, "Cup", 0.5, 0.6, c(x, 1.85, 0.2), WHITE, nil, true)
			cyl(m, "Coffee", 0.05, 0.5, c(x, 2.12, 0.2), Color3.fromRGB(120, 80, 50), nil, true)
		end
		box(m, "Magazine", V(1, 0.05, 1.3), c(0, 1.62, -0.7), D.BRIGHT[i % 6 + 1], nil, true)
		local colors = { Color3.fromRGB(200, 180, 150), Color3.fromRGB(120, 70, 40), Color3.fromRGB(50, 110, 80), Color3.fromRGB(110, 40, 120) }
		local materials = { FABRIC, Enum.Material.Leather, FABRIC, FABRIC }
		local tier = k.seatTier + 1
		armchair(m, turn(c(-4, 0, 0), -R90), colors[tier], materials[tier])
		armchair(m, turn(c(4, 0, 0), R90), colors[tier], materials[tier])
		-- Floor lamp behind the table.
		box(m, "LampPole", V(0.25, 6, 0.25), c(0, 3, back + 0.6), DARK, nil, true)
		local shade = glow(m, "LampShade", V(1.6, 1.2, 1.6), c(0, 6.4, back + 0.6), D.WARM)
		local _ = shade
		return { { x = -4, z = 0, yaw = -R90 }, { x = 4, z = 0, yaw = R90 } }
	end,
	extras = function(k: any)
		local m = k.decor
		-- Burlap coffee sacks, back-left.
		for j = 0, 4 do
			local sack = box(m, "Sack", V(2.6, 2, 3.4), corner(k, -1, -5 + (j % 3) * 3, 1 + math.floor(j / 3) * 2, (j % 2) * 0.6), Color3.fromRGB(185, 150, 100), FABRIC)
			if j == 1 then
				D.text(sack, Enum.NormalId.Back, "☕ BEANS", Color3.fromRGB(90, 60, 40), 20)
			end
		end
		-- Chalkboard on the right wall.
		local board = wallBox(k, "Chalkboard", 1, 10, 9.5, 7, 12, 0.3, Color3.fromRGB(40, 50, 45))
		wallText(board, 1, "TODAY'S BREW\nCaramel Latte\nIced Mocha", Color3.fromRGB(245, 240, 225), 22)
		wallBox(k, "ChalkFrame", 1, 10, 9.5, 7.6, 12.6, 0.2, WOOD)
		-- Mug shelf, back-right.
		box(m, "MugShelf", V(1.6, 8, 6), corner(k, 1, 6.6, 4, 0), Color3.fromRGB(120, 80, 50), PLANKS)
		for row, y in { 3, 5.5, 8 } do
			box(m, "Board", V(2.6, 0.3, 6), corner(k, 1, 5.6, y - 0.45, 0), Color3.fromRGB(150, 100, 60), PLANKS)
			for j = 0, 3 do
				cyl(m, "Mug", 1, 0.9, corner(k, 1, 5.3, y + 0.2, -2.2 + j * 1.45), D.BRIGHT[(j + row) % 6 + 1], nil, true)
			end
		end
	end,
}

Kits.IceCream = {
	back = "kitchen", station = "softServe", counter = "food", register = "till", food = true, walls = "LR",
	menu = { "Vanilla", "Strawberry", "Choco Mint" },
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local seat = ({ WHITE, Color3.fromRGB(255, 150, 190), Color3.fromRGB(150, 230, 200), Color3.fromRGB(230, 70, 150) })[k.seatTier + 1]
		local material = if k.seatTier >= 2 then FABRIC else nil
		local seats = booth(k, c, seat, STEEL, WHITE, material)
		local m = k.decor
		cyl(m, "SundaeGlass", 1.2, 0.9, c(0, 4, -0.6), D.GLASS, D.GLASSMAT, true)
		ball(m, "ScoopA", 0.9, c(-0.15, 4.8, -0.6), Color3.fromRGB(255, 180, 210), nil, true)
		ball(m, "ScoopB", 0.8, c(0.2, 5.4, -0.6), Color3.fromRGB(150, 230, 170), nil, true)
		ball(m, "Cherry", 0.35, c(0, 5.9, -0.6), D.RED, nil, true)
		return seats
	end,
	extras = function(k: any)
		local m = k.decor
		-- Giant cone sculpture, back-left.
		for j = 0, 5 do
			cyl(m, "Cone", 1, 0.8 + j * 0.55, corner(k, -1, 0, 0.5 + j, 0), Color3.fromRGB(225, 165, 90), nil, j > 0)
		end
		ball(m, "Scoop", 4.4, corner(k, -1, 0, 7.6, 0), Color3.fromRGB(255, 170, 205), nil, true)
		ball(m, "Scoop", 3.6, corner(k, -1, 0, 10.2, 0), Color3.fromRGB(150, 225, 200), nil, true)
		ball(m, "Cherry", 1, corner(k, -1, 0, 12.2, 0), D.RED, nil, true)
		-- Pastel stripes on both side walls.
		local pastel = { Color3.fromRGB(255, 200, 220), Color3.fromRGB(200, 240, 225), Color3.fromRGB(255, 245, 210) }
		for _, side in { -1, 1 } do
			for j = 0, 10 do
				wallBox(k, "Stripe", side, -0.2 + j * 2, 7.5, 13, 2, 0.2, pastel[j % 3 + 1])
			end
		end
		-- Candy jars, back-right.
		box(m, "CandyTable", V(6, 3, 3.4), corner(k, 1, 0, 1.5, 0), Color3.fromRGB(255, 200, 220))
		for j = 0, 3 do
			local x = -2.2 + j * 1.45
			cyl(m, "Jar", 2, 1.2, corner(k, 1, x, 4, 0), D.GLASS, D.GLASSMAT, true).Transparency = 0.5
			for b = 0, 2 do
				ball(m, "Candy", 0.45, corner(k, 1, x - 0.2 + (b % 2) * 0.4, 3.3 + b * 0.4, 0), D.BRIGHT[(j + b) % 6 + 1], nil, true)
			end
		end
	end,
}

Kits.Burger = {
	back = "kitchen", station = "grill", counter = "food", register = "till", food = true, walls = "R",
	menu = { "Cheeseburger", "Fries", "Milkshake" },
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local seat = ({ Color3.fromRGB(170, 70, 65), Color3.fromRGB(215, 40, 45), Color3.fromRGB(230, 50, 55), Color3.fromRGB(130, 20, 35) })[k.seatTier + 1]
		local seats = booth(k, c, seat, STEEL, WHITE, if k.seatTier >= 3 then FABRIC else nil)
		local m = k.decor
		if k.seatTier >= 2 then
			for _, s in { -1, 1 } do
				box(m, "Piping", V(0.85, 0.25, 3.65), c(s * 5, 3.3, -0.6), WHITE, nil, true)
			end
		end
		cyl(m, "Ketchup", 1, 0.45, c(-0.5, 3.9, -1.8), D.RED, nil, true)
		cyl(m, "Mustard", 1, 0.45, c(0.1, 3.9, -1.8), D.YELLOW, nil, true)
		box(m, "Napkins", V(0.8, 0.8, 0.5), c(0.8, 3.8, -1.8), STEEL, METAL, true)
		box(m, "Tray", V(1.4, 0.1, 1.2), c(0, 3.45, -0.2), D.RED, nil, true)
		ball(m, "Burger", 0.9, c(0, 3.85, -0.2), Color3.fromRGB(220, 150, 70), nil, true)
		return seats
	end,
	extras = function(k: any)
		local m = k.decor
		-- Jukebox, back-left.
		box(m, "Jukebox", V(4, 5, 2.6), corner(k, -1, 0, 2.5, 0), Color3.fromRGB(200, 60, 50))
		rod(m, "JukeTop", 2.6, 4, corner(k, -1, 0, 5, 0) * CFrame.Angles(0, R90, 0), Color3.fromRGB(200, 60, 50))
		glow(m, "JukeLight", V(3.2, 0.4, 0.2), corner(k, -1, 0, 4, -1.35), Color3.fromRGB(255, 220, 80))
		glow(m, "JukeArch", V(0.4, 3.5, 0.2), corner(k, -1, -1.7, 3, -1.35), Color3.fromRGB(80, 220, 255))
		glow(m, "JukeArch", V(0.4, 3.5, 0.2), corner(k, -1, 1.7, 3, -1.35), Color3.fromRGB(80, 220, 255))
		glass(m, "JukeWindow", V(2.6, 1.6, 0.2), corner(k, -1, 0, 5.4, -1.3), 0.3)
		-- Neon "EAT" sign on the right wall.
		local sign = wallBox(k, "NeonEat", 1, 10, 11, 5, 12, 0.3, Color3.fromRGB(30, 20, 30))
		wallText(sign, 1, "EAT", Color3.fromRGB(255, 60, 70), 25)
		for _, dz in { -6.4, 6.4 } do
			wallBox(k, "NeonTube", 1, 10 + dz, 11, 5.4, 0.3, 0.4, Color3.fromRGB(255, 60, 70), NEON)
		end
		-- Checker strip along the right wall.
		for j = 0, 10 do
			wallBox(k, "Checker", 1, -0.2 + j * 2, 1.5, 2, 2, 0.25, if j % 2 == 0 then DARK else WHITE)
		end
		-- Milkshake machine, back-right.
		box(m, "ShakeCounter", V(6, 3, 3.4), corner(k, 1, 0, 1.5, 0), Color3.fromRGB(200, 205, 212), METAL)
		for j = 0, 2 do
			cyl(m, "ShakeCup", 1.6, 0.9, corner(k, 1, -1.8 + j * 1.8, 3.8, 0), STEEL, METAL, true)
			ball(m, "Shake", 0.9, corner(k, 1, -1.8 + j * 1.8, 4.7, 0), ({ Color3.fromRGB(255, 180, 210), Color3.fromRGB(120, 80, 50), Color3.fromRGB(255, 245, 220) })[j + 1], nil, true)
		end
	end,
}

Kits.Seafood = {
	back = "kitchen", station = "seafoodGrill", counter = "food", register = "till", food = true, walls = "LR",
	menu = { "Lobster Roll", "Fish & Chips", "Oysters" },
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		cyl(m, "Top", 0.4, 4.6, c(0, 3.2, 0), Color3.fromRGB(110, 70, 45), PLANKS)
		cyl(m, "Rope", 0.25, 4.8, c(0, 3.05, 0), Color3.fromRGB(210, 180, 130), FABRIC, true)
		cyl(m, "Leg", 3, 0.8, c(0, 1.5, 0), DARK)
		cyl(m, "LanternGlass", 1.2, 0.8, c(0, 4, -0.5), D.GLASS, D.GLASSMAT, true)
		ball(m, "LanternFlame", 0.4, c(0, 4, -0.5), D.ORANGE, NEON, true)
		cyl(m, "Plate", 0.1, 1.6, c(0, 3.45, 0.9), WHITE, nil, true)
		ball(m, "Lobster", 0.8, c(0, 3.75, 0.9), Color3.fromRGB(230, 70, 50), nil, true)
		if k.seatTier == 0 then
			for _, s in { -1, 1 } do
				cyl(m, "BarrelSeat", 1.9, 2, c(s * 4, 0.95, 0), Color3.fromRGB(140, 90, 50), PLANKS)
				cyl(m, "Hoop", 0.2, 2.1, c(s * 4, 1.5, 0), DARK, METAL, true)
			end
			return { { x = -4, z = 0, yaw = -R90 }, { x = 4, z = 0, yaw = R90 } }
		end
		local cushion = ({ Color3.fromRGB(40, 70, 130), Color3.fromRGB(40, 70, 130), Color3.fromRGB(30, 50, 110) })[k.seatTier]
		return chairs(k, c, 4, k.seatTier, Color3.fromRGB(100, 65, 40), cushion)
	end,
	extras = function(k: any)
		local m = k.decor
		-- Lobster tank, back-left.
		box(m, "TankBase", V(8, 2.4, 4), corner(k, -1, 0, 1.2, 0), DARK)
		local water = glass(m, "TankWater", V(7.6, 4, 3.6), corner(k, -1, 0, 4.4, 0), 0.4, Color3.fromRGB(70, 160, 220))
		D.bubbles(water, 5)
		for j = 0, 2 do
			ball(m, "Lobster", 1, corner(k, -1, -2.4 + j * 2.4, 2.9, (j % 2) * 0.8 - 0.4), Color3.fromRGB(200, 60, 45), nil, true)
		end
		-- Ship wheel and life ring on the right wall.
		local wheel = rod(m, "ShipWheel", 0.4, 5, k.at(39.3, 11, 5), Color3.fromRGB(130, 85, 50), PLANKS, true)
		local _ = wheel
		for j = 0, 3 do
			box(m, "Spoke", V(0.5, 7, 0.4), k.at(39.1, 11, 5) * CFrame.Angles(j * math.pi / 4, 0, 0), Color3.fromRGB(150, 100, 60), nil, true)
		end
		rod(m, "LifeRing", 0.6, 4, k.at(39.3, 10, 15), WHITE, nil, true)
		rod(m, "RingHole", 0.7, 2, k.at(39.3, 10, 15), Color3.fromRGB(60, 110, 160), nil, true)
		for j = 0, 3 do
			box(m, "RingBand", V(0.7, 0.9, 1.1), k.at(39.3, 10, 15) * CFrame.Angles(j * R90, 0, 0) * CFrame.new(0, 1.5, 0), D.RED, nil, true)
		end
		-- Fishing net on the left wall.
		local net = wallBox(k, "Net", -1, 10, 9, 9, 16, 0.2, Color3.fromRGB(60, 90, 70), FABRIC)
		net.Transparency = 0.35
		for j = 0, 4 do
			ball(m, "Float", 1, k.at(-39.1, 13.5, 3 + j * 3.5), D.ORANGE, nil, true)
		end
		-- Barrel and crate, back-right.
		cyl(m, "Barrel", 3.6, 3, corner(k, 1, -2.5, 1.8, 0), Color3.fromRGB(140, 90, 50), PLANKS)
		box(m, "Crate", V(3, 3, 3), corner(k, 1, 2, 1.5, 0), Color3.fromRGB(180, 140, 90), PLANKS)
		D.fish(m, corner(k, 1, 2, 3.2, 0) * CFrame.Angles(math.pi / 2, 0, 0), Color3.fromRGB(150, 170, 190), 1.5)
	end,
}

Kits.Sushi = {
	back = "kitchen", station = "sushiPrep", counter = "food", register = "till", food = true, walls = "",
	menu = { "Salmon Roll", "Tuna Nigiri", "Miso Soup" },
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		box(m, "Bar", V(11, 3.2, 2.4), c(0, 1.6, -1.4), Color3.fromRGB(150, 100, 60), PLANKS)
		box(m, "BarTop", V(11.2, 0.2, 1), c(0, 3.3, -0.4), Color3.fromRGB(230, 200, 150), PLANKS)
		box(m, "Belt", V(11, 0.25, 1.2), c(0, 3.3, -1.7), DARK, METAL)
		glow(m, "BeltEdge", V(11, 0.1, 0.1), c(0, 3.3, -1.05), k.theme.primary)
		local plateColors = { D.RED, D.BLUE, D.YELLOW, WHITE, D.GREEN }
		for j = 0, 4 do
			local x = -4.4 + j * 2.2
			cyl(m, "Plate", 0.12, 1, c(x, 3.5, -1.7), plateColors[(j + i) % 5 + 1], nil, true)
			rod(m, "Roll", 0.6, 0.45, c(x - 0.2, 3.75, -1.7) * CFrame.Angles(0, 0, R90), Color3.fromRGB(30, 50, 35), nil, true)
			box(m, "Nigiri", V(0.6, 0.3, 0.35), c(x + 0.25, 3.7, -1.7), Color3.fromRGB(255, 140, 90), nil, true)
		end
		local stoolColors = { WOOD, Color3.fromRGB(200, 175, 110), Color3.fromRGB(180, 50, 50), Color3.fromRGB(30, 25, 25) }
		for _, x in { -2.5, 2.5 } do
			D.stool(m, c(x, 0, 1.8), k.seatTier, stoolColors[k.seatTier + 1])
		end
		cyl(m, "SoySauce", 0.6, 0.35, c(0, 3.7, -0.4), Color3.fromRGB(60, 30, 20), nil, true)
		return { { x = -2.5, z = 1.8, yaw = 0 }, { x = 2.5, z = 1.8, yaw = 0 } }
	end,
	extras = function(k: any)
		local m = k.decor
		for j, x in { -30, -22, -14, -6, 6, 14, 22, 30 } do
			lantern(k, x, 11, if j % 2 == 0 then WHITE else Color3.fromRGB(230, 50, 45))
		end
		-- Bamboo grove, back-right.
		for j = 0, 6 do
			local h = 10 + (j % 3) * 2
			cyl(m, "Bamboo", h, 0.6, corner(k, 1, -5 + j * 1.7, h / 2, (j % 2) * 1.4 - 0.7), Color3.fromRGB(120, 170, 80), nil, true)
			for y = 2, h, 3 do
				cyl(m, "Node", 0.2, 0.7, corner(k, 1, -5 + j * 1.7, y, (j % 2) * 1.4 - 0.7), Color3.fromRGB(90, 130, 60), nil, true)
			end
		end
		-- Koi pond, back-left.
		cyl(m, "PondRim", 1.2, 7, corner(k, -1, 0, 0.6, 0) * CFrame.new(0, 0, 0), Color3.fromRGB(140, 140, 135), Enum.Material.Slate)
		cyl(m, "PondWater", 0.2, 6, corner(k, -1, 0, 1.15, 0), Color3.fromRGB(70, 150, 190), D.GLASSMAT, true)
		for j = 0, 2 do
			D.fish(m, corner(k, -1, -1.5 + j * 1.5, 1.3, (j % 2) - 0.5) * CFrame.Angles(math.pi / 2, 0, j), if j == 1 then WHITE else D.ORANGE, 1.1)
		end
		box(m, "Rock", V(1.6, 1.4, 1.4), corner(k, -1, 2.6, 1.5, -1.2), Color3.fromRGB(120, 120, 115), Enum.Material.Slate)
		-- A big wave painting on both walls.
		for _, side in { -1, 1 } do
			local art = wallBox(k, "WavePanel", side, 10, 10, 7, 14, 0.3, Color3.fromRGB(240, 235, 220))
			wallText(art, side, "🌊", Color3.fromRGB(40, 90, 170), 25)
			wallBox(k, "WaveFrame", side, 10, 10, 7.6, 14.6, 0.2, DARK)
		end
	end,
}

Kits.Clothing = {
	back = "stock", station = "sewing", counter = "shop", sign = "🛍️ CHECKOUT", register = "till", walls = "R",
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		local tier = k.seatTier
		local frame = ({ DARK, WOOD, STEEL, GOLD })[tier + 1]
		if tier >= 1 then
			box(m, "Platform", V(11, 0.2, 4.4), c(0, 0.1, -1.4), if tier == 3 then Color3.fromRGB(150, 30, 50) else Color3.fromRGB(190, 150, 110), if tier == 3 then FABRIC else PLANKS, true)
		end
		for _, x in { -4.6, 4.6 } do
			box(m, "Post", V(0.4, 6.4, 0.4), c(x, 3.2, -2), frame, METAL)
			box(m, "Foot", V(0.6, 0.3, 2), c(x, 0.15, -2), frame, METAL)
		end
		rod(m, "Rail", 9.6, 0.3, c(0, 6.3, -2), frame, METAL)
		local palette = { k.theme.primary, k.theme.accent, D.BLUE, D.YELLOW, WHITE, D.GREEN, D.RED }
		for s = 0, 5 do
			local x = -3.6 + s * 1.45
			box(m, "Shirt", V(0.4, 3, 1.8), c(x, 4.6, -2), palette[(s + i) % #palette + 1], FABRIC, true)
			box(m, "Hanger", V(0.1, 0.6, 0.1), c(x, 6.05, -2), DARK, nil, true)
		end
		-- Mannequin beside the rack.
		cyl(m, "MannequinBase", 0.3, 1.6, c(4.4, 0.15, 1.2), DARK)
		box(m, "MannequinPole", V(0.25, 2.4, 0.25), c(4.4, 1.4, 1.2), STEEL, nil, true)
		box(m, "MannequinTorso", V(1.8, 2.4, 1), c(4.4, 3.8, 1.2), palette[(i + 3) % #palette + 1], FABRIC, true)
		ball(m, "MannequinHead", 1.1, c(4.4, 5.6, 1.2), Color3.fromRGB(235, 225, 215), nil, true)
		if tier >= 2 then
			glass(m, "Mirror", V(2.2, 5, 0.2), c(-4.6, 2.8, 1.6), 0.15, Color3.fromRGB(220, 235, 245))
		end
		if tier >= 3 then
			glow(m, "Spot", V(9.6, 0.2, 0.3), c(0, 6.6, -2.2), D.WARM)
		end
		return { { x = -2, z = 1.2, yaw = 0, stand = true }, { x = 2, z = 1.2, yaw = 0, stand = true } }
	end,
	extras = function(k: any)
		local m = k.decor
		-- Fitting rooms, back-left.
		for j, dx in { -3.6, 3.6 } do
			box(m, "BoothWall", V(0.4, 8, 5), corner(k, -1, dx - 3.4, 4, 0), WHITE)
			box(m, "BoothBack", V(7, 8, 0.4), corner(k, -1, dx, 4, -2.4), WHITE)
			box(m, "Curtain", V(6.4, 7, 0.3), corner(k, -1, dx, 4.3, 2.3), if j == 1 then k.theme.primary else k.theme.accent, FABRIC, true)
			box(m, "CurtainRod", V(7, 0.3, 0.3), corner(k, -1, dx, 8, 2.3), GOLD, nil, true)
		end
		box(m, "BoothWall", V(0.4, 8, 5), corner(k, -1, 7, 4, 0), WHITE)
		-- Mirror and shoe shelf on the right wall.
		wallBox(k, "Mirror", 1, 4, 5, 9, 6, 0.3, GOLD)
		wallBox(k, "MirrorGlass", 1, 4, 5, 8.2, 5.2, 0.35, Color3.fromRGB(215, 235, 245), Enum.Material.Glass)
		wallBox(k, "ShoeShelf", 1, 15, 4.5, 9, 9, 0.4, Color3.fromRGB(240, 235, 230))
		for row, y in { 1.5, 4, 6.5 } do
			box(m, "ShoeBoard", V(2, 0.3, 9), k.at(38.4, y - 0.55, 15), Color3.fromRGB(240, 235, 230), nil, true)
			for j = 0, 2 do
				box(m, "Shoe", V(1.2, 0.8, 2), k.at(38.4, y, 12.2 + j * 2.8), D.BRIGHT[(j + row) % 6 + 1], nil, true)
			end
		end
		local sign = wallBox(k, "SaleSign", 1, 15, 11, 2.4, 9, 0.3, k.theme.accent)
		wallText(sign, 1, "NEW COLLECTION", WHITE, 25)
	end,
}

Kits.Supermarket = {
	back = "stock", station = "stockShelf", counter = "shop", sign = "🛒 CHECKOUT", register = "till", walls = "LR",
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		local z0 = back + 0.4
		box(m, "ShelfBack", V(10.6, 7, 0.4), c(0, 3.5, z0), WHITE)
		for _, x in { -5.1, 5.1 } do
			box(m, "ShelfSide", V(0.4, 7, 2.2), c(x, 3.5, z0 + 0.9), WHITE)
		end
		local goods = { Color3.fromRGB(240, 80, 80), Color3.fromRGB(90, 200, 120), Color3.fromRGB(250, 210, 70), Color3.fromRGB(80, 160, 240), Color3.fromRGB(255, 140, 60), WHITE }
		for row, y in { 0.4, 2.6, 4.8 } do
			box(m, "ShelfBoard", V(10, 0.3, 1.8), c(0, y, z0 + 1.1), STEEL, METAL)
			glow(m, "PriceStrip", V(10, 0.25, 0.1), c(0, y, z0 + 2.05), Color3.fromRGB(255, 230, 90))
			for j = 0, 5 do
				local h = 1.2 + ((j + row + i) % 3) * 0.4
				box(m, "Goods", V(1.3, h, 1.2), c(-4.1 + j * 1.64, y + 0.15 + h / 2, z0 + 1.1), goods[(j + row + i) % #goods + 1], nil, true)
			end
		end
		local sign = box(m, "AisleSign", V(4, 1.4, 0.3), c(0, 7.8, z0), k.theme.accent, nil, true)
		D.text(sign, Enum.NormalId.Back, "AISLE " .. tostring(i), WHITE, 20)
		-- Basket or cart by the aisle (Seating tiers).
		local tier = k.seatTier
		local cartColor = if tier == 3 then GOLD else D.RED
		if tier == 0 then
			box(m, "Basket", V(1.6, 1.2, 1.2), c(4.6, 0.6, 2.6), D.RED, nil, true)
		else
			local s = 0.8 + tier * 0.2
			box(m, "CartBasket", V(1.8 * s, 1.6 * s, 2.6 * s), c(4.6, 2 * s, 2.6), cartColor, METAL, true)
			box(m, "CartFrame", V(1.6 * s, 0.2, 2.4 * s), c(4.6, 0.8, 2.6), STEEL, METAL, true)
			for _, dx in { -0.6, 0.6 } do
				for _, dz in { -0.9, 0.9 } do
					ball(m, "CartWheel", 0.5, c(4.6 + dx * s, 0.25, 2.6 + dz * s), DARK, nil, true)
				end
			end
		end
		return { { x = -2.5, z = 1.6, yaw = 0, stand = true }, { x = 2.5, z = 1.6, yaw = 0, stand = true } }
	end,
	extras = function(k: any)
		local m = k.decor
		-- Drinks fridges along the left wall.
		wallBox(k, "FridgeBack", -1, 10, 4.5, 9, 22, 0.6, WHITE)
		box(m, "FridgeBase", V(2.8, 0.9, 22), k.at(-38.2, 0.45, 10), WHITE)
		box(m, "FridgeTop", V(2.8, 0.8, 22), k.at(-38.2, 8.6, 10), WHITE)
		local drinks = { D.RED, D.BLUE, D.GREEN, D.ORANGE, WHITE }
		for j = 0, 3 do
			local z = 1.8 + j * 5.5
			glass(m, "FridgeDoor", V(0.2, 7.2, 5.2), k.at(-36.9, 4.5, z), 0.55)
			box(m, "Handle", V(0.3, 2, 0.3), k.at(-36.7, 4.5, z + 2.1), STEEL, METAL, true)
			for row, y in { 1.6, 3.8, 6 } do
				box(m, "FridgeShelf", V(2.2, 0.15, 5), k.at(-38.1, y - 0.75, z), STEEL, METAL, true)
				for b = 0, 3 do
					cyl(m, "Drink", 1.4, 0.6, k.at(-38.1, y, z - 1.8 + b * 1.2), drinks[(b + row + j) % #drinks + 1], nil, true)
				end
			end
		end
		glow(m, "FridgeLight", V(0.2, 0.3, 22), k.at(-36.9, 8.1, 10), Color3.fromRGB(200, 240, 255))
		-- Produce crates along the right wall.
		local fruit = { D.RED, D.ORANGE, D.YELLOW, D.GREEN, Color3.fromRGB(150, 60, 160) }
		for j = 0, 4 do
			local z = 1 + j * 4.2
			wedge(m, "Crate", V(3.6, 2.4, 3.2), k.at(37.6, 1.9, z) * CFrame.Angles(0, R90, 0), Color3.fromRGB(190, 140, 90), PLANKS)
			box(m, "CrateBase", V(3.2, 0.7, 3.6), k.at(37.6, 0.35, z), Color3.fromRGB(170, 120, 75), PLANKS)
			for b = 0, 2 do
				ball(m, "Fruit", 0.9, k.at(37.2 + (b % 2) * 0.6, 2 + b * 0.3, z - 1 + b), fruit[j + 1], nil, true)
			end
		end
		local produce = wallBox(k, "ProduceSign", 1, 9.4, 9.5, 2.4, 10, 0.3, Color3.fromRGB(90, 160, 80))
		wallText(produce, 1, "🍎 FRESH PRODUCE", WHITE, 25)
		-- Stacked carts, back-right.
		for j = 0, 3 do
			box(m, "Cart", V(2.4, 2.2, 3), corner(k, 1, 0, 2, -1.2 + j * 0.7), D.RED, METAL, true)
		end
		box(m, "CartRack", V(3, 0.3, 5), corner(k, 1, 0, 0.6, 0), STEEL, METAL)
	end,
}

Kits.PetShop = {
	back = "stock", station = "grooming", counter = "shop", sign = "🐾 CHECKOUT", register = "till", walls = "LR",
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		local tier = k.seatTier
		local kind = i % 3
		local zb = back + 0.4
		if kind == 1 then
			-- Puppy pen.
			local wall = ({ STEEL, WOOD, D.GLASS, D.GLASS })[tier + 1]
			local material = ({ METAL, PLANKS, D.GLASSMAT, D.GLASSMAT })[tier + 1]
			local zf = 1.4
			local depth = zf - zb
			box(m, "PenFloor", V(10, 0.2, depth), c(0, 0.1, (zb + zf) / 2), Color3.fromRGB(120, 180, 90), Enum.Material.Grass, true)
			for _, spec in { { V(10, 2.4, 0.3), c(0, 1.2, zf) }, { V(10, 2.4, 0.3), c(0, 1.2, zb) }, { V(0.3, 2.4, depth), c(-5, 1.2, (zb + zf) / 2) }, { V(0.3, 2.4, depth), c(5, 1.2, (zb + zf) / 2) } } do
				local p = box(m, "PenWall", spec[1], spec[2], wall, material)
				if tier >= 2 then
					p.Transparency = 0.5
				end
			end
			if tier == 3 then
				box(m, "PenTrim", V(10.2, 0.3, 0.4), c(0, 2.5, zf), GOLD, nil, true)
				wedge(m, "DogHouseRoof", V(3, 1.6, 2.4), c(3, 3.2, zb + 1.4), D.RED, nil, true)
			end
			box(m, "DogHouse", V(3, 2.4, 2.4), c(3, 1.4, zb + 1.4), Color3.fromRGB(240, 220, 180), PLANKS, true)
			dog(m, turn(c(-2, 0.2, (zb + zf) / 2), 0.6), Color3.fromRGB(235, 200, 140))
			dog(m, turn(c(0.4, 0.2, (zb + zf) / 2 + 0.4), -0.9), Color3.fromRGB(120, 85, 60))
			return { { x = -2, z = 2.8, yaw = 0, stand = true }, { x = 2, z = 2.8, yaw = 0, stand = true } }
		elseif kind == 2 then
			-- Cat tree and bird cage.
			local post = ({ Color3.fromRGB(200, 180, 150), Color3.fromRGB(190, 150, 110), Color3.fromRGB(150, 120, 200), GOLD })[tier + 1]
			for level, y in { 1.5, 3.5, 5.5 } do
				box(m, "CatShelf", V(2.6, 0.4, 2.6), c(-3 + (level % 2) * 0.8, y, zb + 1.4), Color3.fromRGB(210, 190, 160), FABRIC)
			end
			cyl(m, "CatPost", 6, 0.8, c(-2.6, 3, zb + 1.4), post, FABRIC)
			box(m, "Cat", V(1.4, 0.8, 0.8), c(-2.2, 6.1, zb + 1.4), D.ORANGE, nil, true)
			box(m, "CatHead", V(0.8, 0.8, 0.8), c(-1.4, 6.4, zb + 1.4), D.ORANGE, nil, true)
			box(m, "CageStand", V(0.4, 3, 0.4), c(2.8, 1.5, zb + 1.4), DARK)
			cyl(m, "CageBase", 0.3, 3, c(2.8, 3.1, zb + 1.4), DARK)
			for j = 0, 7 do
				local a = j * math.pi / 4
				box(m, "Bar", V(0.1, 3, 0.1), c(2.8 + math.cos(a) * 1.4, 4.7, zb + 1.4 + math.sin(a) * 1.4), GOLD, nil, true)
			end
			ball(m, "CageTop", 3, c(2.8, 6.2, zb + 1.4), GOLD, nil, true).Transparency = 0.6
			ball(m, "Bird", 0.8, c(2.8, 4.4, zb + 1.4), Color3.fromRGB(80, 200, 120), nil, true)
			return { { x = -2, z = 2.8, yaw = 0, stand = true }, { x = 2, z = 2.8, yaw = 0, stand = true } }
		end
		-- Fish tank wall.
		box(m, "TankStand", V(10, 2.6, 2.6), c(0, 1.3, zb + 1.3), Color3.fromRGB(60, 60, 70))
		local water = glass(m, "TankWater", V(9.6, 4, 2.4), c(0, 4.6, zb + 1.3), 0.4, Color3.fromRGB(70, 170, 240))
		D.bubbles(water, 4)
		for j = 1, 5 do
			D.fish(m, c(-4 + j * 1.5, 3.6 + (j % 3) * 1, zb + 1.1), fishColor(j))
		end
		if tier >= 2 then
			glow(m, "TankLight", V(9.6, 0.3, 2.4), c(0, 6.75, zb + 1.3), Color3.fromRGB(180, 230, 255))
		end
		return { { x = -2, z = 2.8, yaw = 0, stand = true }, { x = 2, z = 2.8, yaw = 0, stand = true } }
	end,
	extras = function(k: any)
		local m = k.decor
		-- Pet food shelves on the left wall.
		wallBox(k, "FoodShelf", -1, 10, 4.5, 9, 20, 0.4, WHITE)
		for row, y in { 1.4, 4.2, 7 } do
			box(m, "FoodBoard", V(2, 0.3, 20), k.at(-38.6, y - 1.25, 10), WHITE, nil, true)
			for j = 0, 5 do
				box(m, "FoodBag", V(1.4, 2.2, 2.4), k.at(-38.5, y, 1.5 + j * 3.4), ({ D.RED, D.BLUE, D.GREEN, D.ORANGE })[(j + row) % 4 + 1], FABRIC, true)
			end
		end
		local sign = wallBox(k, "FoodSign", -1, 10, 10.6, 2, 10, 0.3, Color3.fromRGB(80, 175, 240))
		wallText(sign, -1, "🦴 PET FOOD", WHITE, 25)
		-- Small fish tanks on the right wall.
		wallBox(k, "TankShelf", 1, 10, 3, 6, 20, 2.4, Color3.fromRGB(60, 60, 70))
		for j = 0, 2 do
			local water = glass(m, "SmallTank", V(2.2, 3.4, 5.6), k.at(38.2, 7.8, 2.8 + j * 7.2), 0.4, Color3.fromRGB(70, 170, 240))
			D.bubbles(water, 3)
			D.fish(m, k.at(38.2, 7.6, 2.8 + j * 7.2) * CFrame.Angles(0, R90, 0), fishColor(j + 1))
		end
		-- Parrot perch, back-right.
		box(m, "PerchPole", V(0.4, 7, 0.4), corner(k, 1, 0, 3.5, 0), Color3.fromRGB(120, 85, 55), nil, true)
		rod(m, "Perch", 4, 0.4, corner(k, 1, 0, 7, 0), Color3.fromRGB(120, 85, 55), nil, true)
		cyl(m, "PerchBase", 0.4, 3, corner(k, 1, 0, 0.2, 0), Color3.fromRGB(120, 85, 55))
		ball(m, "Parrot", 1.3, corner(k, 1, 0.8, 7.8, 0), D.RED, nil, true)
		ball(m, "ParrotHead", 0.8, corner(k, 1, 0.8, 8.7, 0), D.YELLOW, nil, true)
		box(m, "ParrotTail", V(0.3, 1.4, 0.5), corner(k, 1, 0.8, 6.8, 0.4), D.BLUE, nil, true)
		-- Dog beds, back-left.
		for j, dx in { -3.5, 2.5 } do
			cyl(m, "DogBed", 1, 4, corner(k, -1, dx, 0.5, 0), if j == 1 then D.BLUE else D.PINK, FABRIC)
			dog(m, turn(corner(k, -1, dx, 0.6, 0), j * 1.3), if j == 1 then Color3.fromRGB(240, 240, 235) else Color3.fromRGB(90, 70, 55))
		end
	end,
}

Kits.Electronics = {
	back = "dark", station = "repairBench", counter = "shop", sign = "📱 CHECKOUT", register = "till", walls = "L",
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		local tier = k.seatTier
		local z = -1.2
		box(m, "DemoTable", V(10, 0.4, 3), c(0, 3, z), if tier >= 2 then DARK else WHITE)
		if tier == 2 then
			glass(m, "GlassTop", V(10, 0.2, 3), c(0, 3.3, z), 0.4)
		end
		box(m, "DemoBase", V(9, 2.8, 2.4), c(0, 1.4, z), DARK)
		if tier >= 1 then
			glow(m, "Edge", V(10, 0.15, 0.1), c(0, 2.8, z + 1.55), k.theme.primary)
		end
		local screen = k.theme.primary:Lerp(WHITE, 0.35)
		-- Phone, laptop, tablet, watch.
		box(m, "Phone", V(0.8, 0.1, 1.5), c(-3.6, 3.25, z), DARK, nil, true)
		glow(m, "PhoneScreen", V(0.65, 0.05, 1.3), c(-3.6, 3.32, z), screen)
		box(m, "LaptopBase", V(2.6, 0.15, 1.8), c(-1, 3.28, z + 0.2), Color3.fromRGB(190, 195, 205), METAL, true)
		box(m, "LaptopLid", V(2.6, 1.7, 0.1), c(-1, 4.1, z - 0.7) * CFrame.Angles(math.rad(-10), 0, 0), Color3.fromRGB(190, 195, 205), METAL, true)
		glow(m, "LaptopScreen", V(2.3, 1.4, 0.05), c(-1, 4.1, z - 0.62) * CFrame.Angles(math.rad(-10), 0, 0), screen)
		box(m, "Tablet", V(1.8, 0.1, 2.4), c(1.8, 3.25, z), DARK, nil, true)
		glow(m, "TabletScreen", V(1.6, 0.05, 2.2), c(1.8, 3.32, z), k.theme.accent:Lerp(WHITE, 0.3))
		box(m, "Watch", V(0.6, 0.3, 0.6), c(3.8, 3.35, z), D.BRIGHT[i % 6 + 1], nil, true)
		if tier == 3 then
			local holo = glow(m, "Hologram", V(1.8, 1.8, 1.8), c(0, 6, z), Color3.fromRGB(110, 230, 255))
			holo.Shape = Enum.PartType.Ball
			holo.Transparency = 0.4
		end
		local tag = box(m, "PriceTag", V(1.4, 0.7, 0.1), c(-3.6, 3.6, z + 1.2), WHITE, nil, true)
		D.text(tag, Enum.NormalId.Back, "NEW!", D.RED, 30)
		return { { x = -2.2, z = 1.8, yaw = 0, stand = true }, { x = 2.2, z = 1.8, yaw = 0, stand = true } }
	end,
	extras = function(k: any)
		local m = k.decor
		-- TV wall on the left wall.
		local tvColors = { Color3.fromRGB(110, 200, 255), Color3.fromRGB(255, 140, 200), Color3.fromRGB(140, 255, 160), Color3.fromRGB(255, 220, 110), Color3.fromRGB(180, 140, 255), Color3.fromRGB(110, 255, 240) }
		for row = 0, 1 do
			for col = 0, 2 do
				local z = 2.5 + col * 7.5
				local y = 6.5 + row * 5.2
				wallBox(k, "TV", -1, z, y, 4.6, 6.8, 0.5, DARK)
				local screen = wallBox(k, "TVScreen", -1, z, y, 4, 6.2, 0.6, tvColors[row * 3 + col + 1], NEON)
				local _ = screen
			end
		end
		local sign = wallBox(k, "TVSign", -1, 10, 15.2, 1.6, 12, 0.3, DARK)
		wallText(sign, -1, "📺 4K TVs", WHITE, 25)
		-- Speaker towers, back-left.
		for _, dx in { -3, 3 } do
			box(m, "Speaker", V(2.4, 7, 2.4), corner(k, -1, dx, 3.5, 0), Color3.fromRGB(30, 30, 35))
			for _, y in { 2, 4.5 } do
				rod(m, "Cone", 0.2, 1.8, corner(k, -1, dx, y, -1.25) * CFrame.Angles(0, R90, 0), Color3.fromRGB(70, 70, 80), nil, true)
			end
			glow(m, "SpeakerLight", V(2.4, 0.2, 0.1), corner(k, -1, dx, 6.6, -1.25), k.theme.accent)
		end
		-- Gaming corner, back-right.
		box(m, "GameDesk", V(6, 0.4, 3), corner(k, 1, 0, 3, -1.4), DARK)
		for _, dx in { -2.6, 2.6 } do
			box(m, "DeskLeg", V(0.4, 3, 2.6), corner(k, 1, dx, 1.5, -1.4), DARK)
		end
		box(m, "Monitor", V(4, 2.4, 0.2), corner(k, 1, 0, 5, -2.4), DARK)
		glow(m, "MonitorScreen", V(3.7, 2.1, 0.1), corner(k, 1, 0, 5, -2.28), Color3.fromRGB(255, 90, 160))
		D.chair(m, corner(k, 1, 0, 0, 1.2), 0, Color3.fromRGB(220, 40, 60))
		glow(m, "DeskGlow", V(6, 0.1, 0.1), corner(k, 1, 0, 2.75, 0.1), k.theme.primary)
	end,
}

Kits.Bookstore = {
	back = "stock", station = "bookCart", counter = "shop", sign = "📚 CHECKOUT", register = "till", walls = "LR",
	product = "book",
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		local zs = back + 0.8
		box(m, "Bookshelf", V(10, 9, 0.4), c(0, 4.5, zs - 0.6), Color3.fromRGB(120, 80, 50), PLANKS)
		for _, x in { -4.8, 4.8 } do
			box(m, "ShelfSide", V(0.4, 9, 1.6), c(x, 4.5, zs), Color3.fromRGB(120, 80, 50), PLANKS)
		end
		local covers = { D.RED, D.BLUE, D.GREEN, D.YELLOW, Color3.fromRGB(150, 80, 50), D.PURPLE, WHITE }
		for row = 0, 3 do
			local y = 0.4 + row * 2.2
			box(m, "ShelfBoard", V(9.4, 0.25, 1.4), c(0, y, zs), Color3.fromRGB(150, 100, 60), PLANKS)
			for s = 0, 2 do
				box(m, "Books", V(2.8, 1.6, 1.1), c(-3.1 + s * 3.1, y + 0.95, zs), covers[(row * 3 + s + i) % #covers + 1], nil, true)
			end
		end
		-- Reading chair (Seating tiers) facing the shelf's middle.
		local tier = k.seatTier
		if tier == 0 then
			D.stool(m, c(3, 0, 0.5), 0)
		elseif tier == 1 then
			D.chair(m, turn(c(3, 0, 0.5), R90), 1)
		else
			local color = if tier == 2 then Color3.fromRGB(120, 70, 40) else Color3.fromRGB(110, 30, 50)
			armchair(m, turn(c(3, 0, 0.5), R90), color, if tier == 2 then Enum.Material.Leather else FABRIC, tier == 3)
		end
		box(m, "LampPole", V(0.25, 5.5, 0.25), c(5, 2.75, 2.4), GOLD, nil, true)
		local lamp = glow(m, "Lamp", V(1.2, 1, 1.2), c(5, 5.8, 2.4), D.WARM)
		local _ = lamp
		return { { x = -2, z = 0.4, yaw = 0, stand = true }, { x = 3, z = 0.5, yaw = R90 } }
	end,
	extras = function(k: any)
		local m = k.decor
		local covers = { D.RED, D.BLUE, D.GREEN, D.YELLOW, Color3.fromRGB(150, 80, 50), D.PURPLE, WHITE }
		for _, side in { -1, 1 } do
			wallBox(k, "WallShelf", side, 10, 6, 12, 22, 0.4, Color3.fromRGB(110, 70, 45), PLANKS)
			for _, dz in { -11, 11 } do
				box(m, "ShelfEnd", V(1.8, 12, 0.4), k.at(side * 38.5, 6, 10 + dz), Color3.fromRGB(110, 70, 45), PLANKS)
			end
			for row = 0, 4 do
				local y = 0.8 + row * 2.3
				box(m, "ShelfBoard", V(1.8, 0.25, 22), k.at(side * 38.5, y - 0.1, 10), Color3.fromRGB(140, 95, 60), PLANKS, true)
				for s = 0, 5 do
					box(m, "Books", V(1.2, 1.7, 3.2), k.at(side * 38.6, y + 0.9, 0.9 + s * 3.65), covers[(row + s + (if side > 0 then 3 else 0)) % #covers + 1], nil, true)
				end
			end
		end
		-- Rolling ladder on the left shelf.
		for _, dz in { -1, 1 } do
			box(m, "LadderRail", V(0.3, 12, 0.3), k.at(-36.6, 6, 14 + dz) * CFrame.Angles(0, 0, math.rad(-8)), WOOD, nil, true)
		end
		for j = 0, 5 do
			box(m, "Rung", V(0.25, 0.25, 2), k.at(-36.5 + j * 0.28, 1.5 + j * 1.9, 14), WOOD, nil, true)
		end
		-- Globe, back-right.
		box(m, "GlobeStand", V(0.4, 3, 0.4), corner(k, 1, 0, 1.5, 0), GOLD)
		cyl(m, "GlobeBase", 0.3, 2.4, corner(k, 1, 0, 0.15, 0), Color3.fromRGB(110, 70, 45))
		ball(m, "Globe", 3, corner(k, 1, 0, 4.4, 0), Color3.fromRGB(80, 150, 220), nil, true)
		box(m, "Land", V(1.6, 1.2, 0.4), corner(k, 1, 0.3, 4.7, -1.3), D.GREEN, nil, true)
		-- Beanbags, back-left.
		for j, dx in { -3.5, 0, 3.5 } do
			cyl(m, "Beanbag", 1.4, 3, corner(k, -1, dx, 0.7, 0), D.BRIGHT[j + 1], FABRIC)
			ball(m, "BeanTop", 2.4, corner(k, -1, dx, 1.4, 0.4), D.BRIGHT[j + 1], FABRIC, true)
		end
		local sign = box(m, "KidsSign", V(8, 1.6, 0.3), corner(k, -1, 0, 6, -2.8), D.YELLOW, nil, true)
		D.text(sign, Enum.NormalId.Back, "STORY CORNER", D.BLUE, 25)
	end,
}

Kits.SurfShop = {
	back = "stock", station = "shapingBench", counter = "shop", sign = "🏄 CHECKOUT", register = "till", walls = "LR",
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		local tier = k.seatTier
		local frame = ({ Color3.fromRGB(160, 160, 165), Color3.fromRGB(200, 180, 110), Color3.fromRGB(150, 135, 120), GOLD })[tier + 1]
		local material = ({ METAL, PLANKS, Enum.Material.Wood, Enum.Material.Foil })[tier + 1]
		local z = -1.6
		box(m, "RackBase", V(10.4, 0.6, 2.2), c(0, 0.3, z), frame, material)
		box(m, "RackBar", V(10.4, 0.4, 0.4), c(0, 5.4, z + 0.8), frame, material)
		for _, x in { -5, 5 } do
			box(m, "RackPost", V(0.4, 6, 0.4), c(x, 3, z + 0.8), frame, material)
		end
		local colors = { Color3.fromRGB(255, 140, 60), Color3.fromRGB(40, 190, 210), WHITE, Color3.fromRGB(255, 220, 80), Color3.fromRGB(230, 80, 120), Color3.fromRGB(110, 200, 120) }
		for j = 0, 4 do
			local x = -4 + j * 2
			local board = colors[(j + i) % #colors + 1]
			box(m, "Board", V(0.4, 7, 1.9), c(x, 3.9, z) * CFrame.Angles(math.rad(-8), 0, 0), board, nil, true)
			box(m, "BoardStripe", V(0.45, 6, 0.3), c(x, 3.9, z) * CFrame.Angles(math.rad(-8), 0, 0), board:Lerp(WHITE, 0.6), nil, true)
		end
		return { { x = -2, z = 1.6, yaw = 0, stand = true }, { x = 2, z = 1.6, yaw = 0, stand = true } }
	end,
	extras = function(k: any)
		local m = k.decor
		-- Boards on the left wall.
		local colors = { Color3.fromRGB(255, 140, 60), Color3.fromRGB(40, 190, 210), Color3.fromRGB(255, 220, 80), Color3.fromRGB(230, 80, 120), WHITE }
		for j = 0, 4 do
			box(m, "WallBoard", V(0.5, 11, 2.6), k.at(-39.1, 7, 1.5 + j * 4.3) * CFrame.Angles(math.rad(12), 0, 0), colors[j + 1], nil, true)
		end
		-- "Aloha" neon and a wave mural on the right wall.
		local mural = wallBox(k, "WaveMural", 1, 10, 4, 6, 22, 0.3, Color3.fromRGB(40, 150, 210))
		local _ = mural
		for j = 0, 5 do
			wallBox(k, "WaveCrest", 1, 0.5 + j * 3.8, 6.8, 1, 3, 0.35, WHITE)
		end
		local neon = wallBox(k, "Aloha", 1, 10, 12, 3.6, 14, 0.3, Color3.fromRGB(30, 30, 40))
		wallText(neon, 1, "ALOHA 🌺", Color3.fromRGB(255, 150, 210), 25)
		-- Palms in both back corners.
		D.palm(m, corner(k, -1, 0, 0, 0), 1.1)
		D.palm(m, corner(k, 1, 0, 0, 0), 1.1)
		cyl(m, "PalmPot", 1.4, 3.4, corner(k, -1, 0, 0.7, 0), Color3.fromRGB(200, 110, 70))
		cyl(m, "PalmPot", 1.4, 3.4, corner(k, 1, 0, 0.7, 0), Color3.fromRGB(200, 110, 70))
		-- Wetsuits hanging, back-right.
		for j = 0, 2 do
			box(m, "Wetsuit", V(1.8, 4.4, 0.4), corner(k, 1, 3.6 + j * 0.3, 4.6, -2 + j * 1.4) * CFrame.Angles(0, R90, 0), DARK, FABRIC, true)
		end
	end,
}

Kits.ToyStore = {
	back = "stock", station = "toyBench", counter = "shop", sign = "🧸 CHECKOUT", register = "till", walls = "R",
	product = "teddy",
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		local tier = k.seatTier
		local kind = i % 3
		local zb = back + 0.4
		if tier >= 1 then
			cyl(m, "PlayRug", 0.1, 10, c(0, 0.06, -0.2), D.BRIGHT[i % 6 + 1]:Lerp(WHITE, 0.4), FABRIC, true)
		end
		if kind == 1 then
			-- Train table.
			box(m, "TrainTable", V(9, 2.6, 4), c(0, 1.3, -1), Color3.fromRGB(80, 160, 90))
			for _, spec in { { V(7.4, 0.2, 0.4), c(0, 2.7, -2.4) }, { V(7.4, 0.2, 0.4), c(0, 2.7, 0.4) }, { V(0.4, 0.2, 2.8), c(-3.5, 2.7, -1) }, { V(0.4, 0.2, 2.8), c(3.5, 2.7, -1) } } do
				box(m, "Track", spec[1], spec[2], Color3.fromRGB(120, 85, 55), nil, true)
			end
			for j = 0, 2 do
				box(m, "Wagon", V(1.2, 0.9, 0.8), c(-1.6 + j * 1.4, 3.25, 0.4), D.BRIGHT[j + 1], nil, true)
			end
			box(m, "Engine", V(1.6, 1.4, 0.9), c(2.6, 3.5, 0.4), D.RED, nil, true)
			cyl(m, "Chimney", 0.8, 0.5, c(3, 4.6, 0.4), DARK, nil, true)
		elseif kind == 2 then
			-- Block towers.
			for t, x in { -0.8, 0.9 } do
				for j = 0, 4 + t do
					box(m, "Block", V(1.6, 1.6, 1.6), c(x, 0.8 + j * 1.6, -1.5) * CFrame.Angles(0, math.rad(j * 9), 0), D.BRIGHT[(j + t) % 6 + 1], nil, true)
				end
			end
			ball(m, "Ball", 1.8, c(4.2, 0.9, -1.8), D.RED, nil, true)
		else
			-- Teddy display shelf.
			box(m, "TeddyShelf", V(9, 0.4, 2.4), c(0, 2.6, zb + 1.2), Color3.fromRGB(255, 220, 120))
			box(m, "TeddyShelfTop", V(9, 0.4, 2.4), c(0, 5.4, zb + 1.2), Color3.fromRGB(255, 220, 120))
			for _, x in { -4.3, 4.3 } do
				box(m, "ShelfLeg", V(0.4, 5.6, 2.4), c(x, 2.8, zb + 1.2), Color3.fromRGB(255, 150, 150))
			end
			local furs = { Color3.fromRGB(170, 110, 60), Color3.fromRGB(240, 200, 150), Color3.fromRGB(255, 170, 200), WHITE }
			for j = 0, 2 do
				teddy(m, c(-2.8 + j * 2.8, 2.8, zb + 1.2), 0.6, furs[(j + i) % 4 + 1])
				teddy(m, c(-2.8 + j * 2.8, 5.6, zb + 1.2), 0.5, furs[(j + i + 1) % 4 + 1])
			end
		end
		if tier >= 2 then
			balloons(m, c(4.6, 0, -2.2), if tier == 3 then 6 else 3, if tier == 3 then 1.6 else 1.2)
		end
		if tier == 3 then
			local star = glow(m, "Star", V(1.6, 1.6, 0.3), c(0, 8.4, -1.8) * CFrame.Angles(0, 0, math.rad(45)), GOLD)
			local _ = star
		end
		return { { x = -2.5, z = 2.5, yaw = 0, stand = true }, { x = 2.5, z = 2.5, yaw = 0, stand = true } }
	end,
	extras = function(k: any)
		local m = k.decor
		D.bunting(m, k.at(-38, 17, 11).Position, k.at(38, 17, 11).Position, D.BRIGHT)
		-- Giant teddy, back-left.
		teddy(m, turn(corner(k, -1, 0, 0, 0), 0.3), 2.2, Color3.fromRGB(170, 110, 60))
		box(m, "Bow", V(2, 0.8, 0.6), corner(k, -1, 0, 5, -1.6), D.RED, nil, true)
		-- Balloons, back-right.
		balloons(m, corner(k, 1, 0, 0, 0), 8, 2)
		box(m, "BalloonWeight", V(1.4, 1.2, 1.4), corner(k, 1, 0, 0.6, 0), D.PINK)
		-- Toy shelves on the right wall.
		wallBox(k, "ToyShelf", 1, 10, 5, 10, 22, 0.4, Color3.fromRGB(255, 220, 120))
		for row, y in { 1.6, 4.6, 7.6 } do
			box(m, "ToyBoard", V(2.2, 0.3, 22), k.at(38.3, y - 0.15, 10), Color3.fromRGB(255, 150, 150), nil, true)
			for j = 0, 5 do
				local z = 0.5 + j * 3.8
				if (j + row) % 3 == 0 then
					ball(m, "ToyBall", 1.6, k.at(38.3, y + 0.8, z), D.BRIGHT[(j + row) % 6 + 1], nil, true)
				elseif (j + row) % 3 == 1 then
					box(m, "ToyBox", V(1.4, 2, 2.4), k.at(38.4, y + 1, z), D.BRIGHT[(j + row + 2) % 6 + 1], nil, true)
				else
					box(m, "ToyCar", V(1.4, 1, 2.4), k.at(38.4, y + 0.5, z), D.BRIGHT[(j + 4) % 6 + 1], nil, true)
				end
			end
		end
	end,
}

Kits.FishMarket = {
	back = "kitchen", station = "fishTable", counter = "shop", sign = "🐟 FRESH FISH", register = "till", walls = "LR",
	product = "fish",
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		local tier = k.seatTier
		local z = -1.2
		if tier == 0 then
			for _, x in { -3.4, 0, 3.4 } do
				box(m, "Crate", V(3.2, 2.6, 3), c(x, 1.3, z), Color3.fromRGB(180, 140, 90), PLANKS)
			end
		else
			box(m, "Display", V(10.4, 2.6, 3), c(0, 1.3, z), ({ STEEL, STEEL, WHITE, WHITE })[tier + 1], ({ METAL, METAL, MARBLE, MARBLE })[tier + 1])
			if tier == 3 then
				box(m, "GoldTrim", V(10.6, 0.3, 3.2), c(0, 2.7, z), GOLD, Enum.Material.Foil, true)
			end
		end
		wedge(m, "Ice", V(10.2, 1.2, 3), c(0, 3.2, z) * CFrame.Angles(0, PI, 0), Color3.fromRGB(225, 240, 255), Enum.Material.Ice)
		local fish = { Color3.fromRGB(150, 170, 190), Color3.fromRGB(240, 130, 90), Color3.fromRGB(110, 140, 170), Color3.fromRGB(230, 90, 80) }
		for j = 0, 4 do
			-- Lying flat on the sloped ice (front edge low).
			D.fish(m, c(-4 + j * 2, 3.35, z) * CFrame.Angles(math.rad(22), 0, 0) * CFrame.Angles(math.pi / 2, 0, 0), fish[(j + i) % #fish + 1], 1.4)
			if j < 4 then
				ball(m, "Lemon", 0.5, c(-3 + j * 2, 3.5, z + 0.9), D.YELLOW, nil, true)
			end
		end
		local tag = box(m, "PriceTag", V(1.6, 0.8, 0.1), c(0, 2.2, z + 1.55), WHITE, nil, true)
		D.text(tag, Enum.NormalId.Back, "$" .. tostring(4 + i), D.RED, 30)
		return { { x = -2.5, z = 1.8, yaw = 0, stand = true }, { x = 2.5, z = 1.8, yaw = 0, stand = true } }
	end,
	extras = function(k: any)
		local m = k.decor
		-- Stacked crates, back-left.
		for j = 0, 4 do
			local crate = box(m, "Crate", V(3, 2.4, 3), corner(k, -1, -4.5 + (j % 3) * 3.2, 1.2 + math.floor(j / 3) * 2.4, (j % 2) * 0.4), Color3.fromRGB(180, 140, 90), PLANKS)
			if j == 0 then
				D.text(crate, Enum.NormalId.Back, "ICE", Color3.fromRGB(60, 110, 170), 20)
			end
		end
		-- Nets on the left wall.
		local net = wallBox(k, "Net", -1, 10, 9, 9, 18, 0.2, Color3.fromRGB(60, 90, 70), FABRIC)
		net.Transparency = 0.35
		for j = 0, 3 do
			ball(m, "Float", 1, k.at(-39.1, 13.5, 3 + j * 4.5), D.ORANGE, nil, true)
		end
		-- Chalkboard on the right wall.
		local board = wallBox(k, "Chalkboard", 1, 10, 9.5, 7, 14, 0.3, Color3.fromRGB(40, 50, 45))
		wallText(board, 1, "FRESH CATCH\nSalmon · Tuna\nKing Crab", Color3.fromRGB(245, 240, 225), 22)
		wallBox(k, "ChalkFrame", 1, 10, 9.5, 7.6, 14.6, 0.2, WOOD)
		-- Lobster tank, back-right.
		box(m, "TankBase", V(8, 2.4, 4), corner(k, 1, 0, 1.2, 0), DARK)
		local water = glass(m, "TankWater", V(7.6, 4, 3.6), corner(k, 1, 0, 4.4, 0), 0.4, Color3.fromRGB(70, 160, 220))
		D.bubbles(water, 5)
		for j = 0, 2 do
			ball(m, "Lobster", 1, corner(k, 1, -2.4 + j * 2.4, 2.9, (j % 2) * 0.8 - 0.4), Color3.fromRGB(200, 60, 45), nil, true)
		end
	end,
}

Kits.Jewelry = {
	back = "office", station = "jewelerBench", counter = "desk", sign = "💎 BOUTIQUE", register = "desk", walls = "LR",
	product = "ringbox",
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		box(m, "CaseBase", V(4.6, 3, 2.4), c(-2, 1.5, -1.5), Color3.fromRGB(40, 35, 50))
		box(m, "CaseTrim", V(4.7, 0.2, 2.5), c(-2, 3.05, -1.5), GOLD, Enum.Material.Foil)
		box(m, "Velvet", V(4.2, 0.15, 2), c(-2, 3.2, -1.5), Color3.fromRGB(110, 20, 50), FABRIC, true)
		glass(m, "CaseGlass", V(4.6, 1.6, 2.4), c(-2, 4, -1.5), 0.75)
		local gems = { Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 90, 140), Color3.fromRGB(110, 230, 130), GOLD }
		for j = 0, 3 do
			cyl(m, "Ring", 0.15, 0.5, c(-3.4 + j * 0.9, 3.35, -1.2), GOLD, Enum.Material.Foil, true)
			ball(m, "Gem", 0.3, c(-3.4 + j * 0.9, 3.55, -1.2), gems[(j + i) % 4 + 1], NEON, true)
		end
		for j = 0, 4 do
			ball(m, "Pearl", 0.25, c(-3 + j * 0.5, 3.35, -2 + math.abs(j - 2) * 0.15), WHITE, nil, true)
		end
		glow(m, "CaseLight", V(4.4, 0.1, 0.1), c(-2, 4.75, -1.5), WHITE)
		-- Viewing chair (Seating tiers) facing the case.
		local cushion = ({ Color3.fromRGB(200, 200, 205), Color3.fromRGB(160, 140, 200), Color3.fromRGB(70, 40, 30), Color3.fromRGB(120, 20, 60) })[k.seatTier + 1]
		D.chair(m, turn(c(3.2, 0, 0), R90), math.max(k.seatTier, 2), Color3.fromRGB(40, 35, 50), cushion)
		-- Standing mirror.
		box(m, "MirrorFrame", V(1.4, 4.6, 0.3), c(4.6, 2.5, -2.3), GOLD, nil, true)
		glass(m, "Mirror", V(1.1, 4.2, 0.35), c(4.6, 2.5, -2.3), 0.15, Color3.fromRGB(220, 235, 245))
		return { { x = -2, z = 1.4, yaw = 0, stand = true }, { x = 3.2, z = 0, yaw = R90 } }
	end,
	extras = function(k: any)
		local m = k.decor
		-- Gold-framed mirrors on the left wall.
		for j = 0, 2 do
			local z = 2 + j * 8
			wallBox(k, "MirrorFrame", -1, z, 8, 9, 5, 0.3, GOLD, Enum.Material.Foil)
			wallBox(k, "Mirror", -1, z, 8, 8.2, 4.2, 0.35, Color3.fromRGB(215, 235, 245), Enum.Material.Glass)
		end
		-- Velvet curtains on the right wall.
		for j = 0, 3 do
			wallBox(k, "Drape", 1, j * 6.5 + 0.5, 8, 15, 3, 0.6 + (j % 2) * 0.3, Color3.fromRGB(110, 20, 50), FABRIC)
		end
		wallBox(k, "DrapeRail", 1, 10, 15.8, 0.4, 22, 0.8, GOLD)
		-- Giant glowing diamond, back-left.
		box(m, "Plinth", V(4, 3, 4), corner(k, -1, 0, 1.5, 0), WHITE, MARBLE)
		local core = glow(m, "DiamondCore", V(2, 2, 2), corner(k, -1, 0, 5.6, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), Color3.fromRGB(150, 230, 255))
		local _ = core
		glass(m, "Diamond", V(3, 3, 3), corner(k, -1, 0, 5.6, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), 0.4, Color3.fromRGB(200, 240, 255))
		-- Vault safe, back-right.
		box(m, "Safe", V(5, 6, 3.4), corner(k, 1, 0, 3, -0.6), Color3.fromRGB(70, 75, 85), METAL)
		rod(m, "SafeDial", 0.4, 2.2, corner(k, 1, 0, 3.4, -2.4) * CFrame.Angles(0, R90, 0), STEEL, METAL, true)
		box(m, "SafeHandle", V(0.4, 1.8, 0.4), corner(k, 1, 1.6, 3.4, -2.4), GOLD, nil, true)
	end,
}

Kits.Gym = {
	back = "stock", station = "juiceBar", counter = "shop", sign = "💪 FRONT DESK", register = "desk", walls = "LR",
	worker = { shirt = Color3.fromRGB(60, 60, 75), pants = Color3.fromRGB(40, 40, 50) },
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		local tier = k.seatTier
		local body = ({ Color3.fromRGB(150, 150, 155), Color3.fromRGB(70, 70, 80), Color3.fromRGB(35, 35, 40), Color3.fromRGB(25, 25, 30) })[tier + 1]
		local trim = ({ Color3.fromRGB(120, 120, 125), k.theme.accent, D.RED, GOLD })[tier + 1]
		box(m, "Mat", V(11, 0.1, 8.6), c(0, 0.05, -0.2), Color3.fromRGB(40, 40, 45), Enum.Material.Rubber, true)
		-- Treadmill (stand and run).
		box(m, "TreadBase", V(3.2, 0.35, 6), c(-2.8, 0.18, -0.6), body)
		box(m, "Belt", V(2.6, 0.1, 5.4), c(-2.8, 0.4, -0.4), Color3.fromRGB(30, 30, 30), Enum.Material.Rubber, true)
		for _, x in { -4.2, -1.4 } do
			box(m, "Upright", V(0.3, 4, 0.3), c(x, 2.2, -3.3), body)
		end
		box(m, "Console", V(3.2, 1.2, 0.6), c(-2.8, 4.4, -3.3), body)
		glow(m, "ConsoleScreen", V(2.2, 0.7, 0.1), c(-2.8, 4.5, -2.95), trim)
		-- Exercise bike (sit and pedal).
		box(m, "BikeFrame", V(1, 0.4, 4), c(2.8, 0.2, -0.6), body)
		box(m, "SeatPost", V(0.4, 1.6, 0.4), c(2.8, 1, 0.3), body)
		box(m, "BikeSeat", V(1.6, 0.4, 1.8), c(2.8, 1.9, 0.3), DARK, FABRIC)
		box(m, "BarPost", V(0.4, 3.2, 0.4), c(2.8, 1.8, -2.2), body)
		rod(m, "Handlebar", 2.4, 0.3, c(2.8, 3.5, -2.2), trim)
		rod(m, "Flywheel", 0.6, 2.2, c(2.8, 1.2, -2.8), trim, METAL)
		if tier >= 2 then
			glow(m, "BikeScreen", V(1.4, 0.8, 0.1), c(2.8, 4, -2.1), trim)
		end
		return { { x = -2.8, z = 0.6, yaw = 0, stand = true, busy = true }, { x = 2.8, z = 0.3, yaw = 0, busy = true } }
	end,
	extras = function(k: any)
		local m = k.decor
		-- Mirrors on the left wall.
		wallBox(k, "MirrorWall", -1, 10, 7, 11, 22, 0.3, Color3.fromRGB(215, 235, 245), Enum.Material.Glass)
		wallBox(k, "MirrorTrim", -1, 10, 12.7, 0.4, 22.4, 0.4, DARK)
		-- Dumbbell rack on the right wall.
		wallBox(k, "DumbbellRack", 1, 10, 1.6, 3.2, 20, 2.6, DARK)
		for j = 0, 7 do
			local z = 0.8 + j * 2.6
			local w = 0.5 + j * 0.1
			rod(m, "Handle", 1.6, 0.3, k.at(38.2, 3.6, z) * CFrame.Angles(0, R90, 0), STEEL, METAL, true)
			for _, dz in { -0.8, 0.8 } do
				rod(m, "Weight", 0.4, w + 0.6, k.at(38.2, 3.6, z + dz) * CFrame.Angles(0, R90, 0), DARK, nil, true)
			end
		end
		local sign = wallBox(k, "GymSign", 1, 10, 10, 3, 16, 0.3, k.theme.primary)
		wallText(sign, 1, "NO PAIN NO GAIN 💪", WHITE, 25)
		-- Punching bag, back-left.
		box(m, "BagChain", V(0.2, 6, 0.2), corner(k, -1, 0, 15, 0), STEEL, METAL, true)
		cyl(m, "PunchingBag", 5, 2.4, corner(k, -1, 0, 9.5, 0), D.RED, Enum.Material.Leather)
		cyl(m, "BagTop", 0.5, 2.5, corner(k, -1, 0, 12.1, 0), DARK, nil, true)
		box(m, "Mat", V(8, 0.1, 6), corner(k, -1, 0, 0.05, 0), Color3.fromRGB(40, 40, 45), Enum.Material.Rubber, true)
		-- Weight bench, back-right.
		box(m, "Bench", V(1.6, 1.8, 5), corner(k, 1, 0, 0.9, 0), DARK, FABRIC)
		for _, s in { -1, 1 } do
			box(m, "Rack", V(0.4, 4.4, 0.4), corner(k, 1, s * 3.2, 2.2, -2.2), STEEL)
		end
		rod(m, "Barbell", 7, 0.3, corner(k, 1, 0, 4.4, -2.2), STEEL, METAL, true)
		for _, dx in { -3, 3 } do
			rod(m, "Plate", 0.5, 2.6, corner(k, 1, dx, 4.4, -2.2), DARK, nil, true)
		end
	end,
}

Kits.CarDealership = {
	back = "stock", station = "carLift", counter = "desk", sign = "🚗 SALES", register = "desk", walls = "LR",
	worker = { shirt = Color3.fromRGB(60, 100, 170), pants = Color3.fromRGB(40, 60, 110), hat = Color3.fromRGB(255, 200, 40) },
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		local tier = k.seatTier
		local platformY = 0
		local cz = 0.3
		if tier == 0 then
			box(m, "FloorMat", V(8, 0.1, 8), c(0, 0.05, cz), Color3.fromRGB(210, 210, 215), nil, true)
		else
			local color = if tier == 3 then GOLD else STEEL
			cyl(m, "Turntable", 0.6, 8, c(0, 0.3, cz), color, if tier == 3 then Enum.Material.Foil else METAL)
			platformY = 0.6
			if tier >= 2 then
				cyl(m, "TurntableGlow", 0.1, 8.4, c(0, 0.08, cz), k.theme.accent, NEON, true)
			end
		end
		-- Car model origin is at its wheel bottoms' centre; scaled, the pivot sits 0.275 up.
		local car = Props.car(m, CAR_COLORS[(i - 1) % #CAR_COLORS + 1], true)
		car:ScaleTo(0.55)
		car:PivotTo(c(0, platformY + 0.275, cz) * CFrame.Angles(0, math.rad(if i % 2 == 0 then -30 else 30), 0))
		local tag = box(m, "PriceStand", V(1.6, 1.2, 0.2), c(-4.9, 3, 2.6), WHITE, nil, true)
		D.text(tag, Enum.NormalId.Back, "NEW!", D.RED, 30)
		box(m, "StandPole", V(0.2, 2.4, 0.2), c(-4.9, 1.2, 2.6), DARK, nil, true)
		return { { x = -3.4, z = 3.8, yaw = 0, stand = true }, { x = 3.4, z = 3.8, yaw = 0, stand = true } }
	end,
	extras = function(k: any)
		local m = k.decor
		-- Showroom glass on both side walls.
		for _, side in { -1, 1 } do
			wallBox(k, "ShowroomGlass", side, 10, 9, 14, 24, 0.3, Color3.fromRGB(170, 225, 255), NEON).Transparency = 0.25
			for j = 0, 4 do
				wallBox(k, "Mullion", side, -2 + j * 6, 9, 14.4, 0.5, 0.45, STEEL, METAL)
			end
		end
		D.bunting(m, k.at(-38, 18, 4).Position, k.at(38, 18, 4).Position, { D.RED, WHITE, D.BLUE, D.YELLOW })
		D.bunting(m, k.at(-38, 18, 18).Position, k.at(38, 18, 18).Position, { D.RED, WHITE, D.BLUE, D.YELLOW })
		-- Tyre rack, back-left.
		box(m, "TyreRack", V(8, 0.4, 2.6), corner(k, -1, 0, 3, 0), STEEL, METAL)
		for j = 0, 3 do
			rod(m, "Tyre", 1.1, 2.6, corner(k, -1, -3 + j * 2, 1.3, 0) * CFrame.Angles(0, R90, 0), DARK, Enum.Material.Rubber)
			rod(m, "Tyre", 1.1, 2.6, corner(k, -1, -3 + j * 2, 4.5, 0) * CFrame.Angles(0, R90, 0), DARK, Enum.Material.Rubber)
		end
		-- Sales desk with two chairs, back-right.
		box(m, "SalesDesk", V(6, 3, 2.6), corner(k, 1, 0, 1.5, -1.2), WHITE)
		box(m, "SalesTop", V(6.4, 0.3, 3), corner(k, 1, 0, 3.15, -1.2), Color3.fromRGB(40, 40, 50))
		box(m, "SalesMonitor", V(2.4, 1.6, 0.2), corner(k, 1, -1.2, 4.2, -2), DARK, nil, true)
		glow(m, "SalesScreen", V(2.2, 1.4, 0.1), corner(k, 1, -1.2, 4.2, -1.88), Color3.fromRGB(120, 200, 255))
		for _, dx in { -1.6, 1.6 } do
			D.chair(m, corner(k, 1, dx, 0, 1.6), 2, DARK, Color3.fromRGB(40, 60, 120))
		end
	end,
}

Kits.Cinema = {
	back = "dark", station = "popcorn", counter = "shop", sign = "🎟️ TICKETS & SNACKS", register = "ticket", walls = "LR",
	product = "popcorn",
	front = function(k: any): ({ WorldSeat }, { View })
		local m = k.decor
		local tier = k.seatTier
		-- Screen on the left wall with red curtains.
		box(m, "ScreenFrame", V(0.4, 15, 23), k.at(-39.5, 10, 11), Color3.fromRGB(20, 20, 25), nil, true)
		local screen = glow(m, "Screen", V(0.3, 13.6, 21.6), k.at(-39.2, 10, 11), Color3.fromRGB(190, 220, 255))
		local films = { "🦖 DINO PARK 3D", "🚀 SPACE RACE", "🧙 MAGIC CITY", "🐉 DRAGON BAY" }
		D.text(screen, Enum.NormalId.Right, films[(k.lv("ads") % #films) + 1], Color3.fromRGB(40, 60, 120), 12)
		for _, z in { -0.8, 22.8 } do
			box(m, "Curtain", V(1, 16, 1.2), k.at(-39, 9.5, z), Color3.fromRGB(170, 20, 35), FABRIC, true)
		end
		box(m, "Valance", V(1.2, 1.6, 25), k.at(-39, 17.6, 11), Color3.fromRGB(170, 20, 35), FABRIC, true)
		-- Projector on the right wall and its beam.
		box(m, "Projector", V(3, 2, 2.4), k.at(38, 17, 11), DARK)
		rod(m, "Lens", 0.6, 1.2, k.at(36.3, 17, 11), Color3.fromRGB(200, 230, 255), NEON, true)
		local beamFrom, beamTo = k.at(36, 17, 11).Position, k.at(-38.8, 10, 11).Position
		local beam = glow(m, "Beam", V(4, 3, (beamTo - beamFrom).Magnitude), CFrame.lookAt((beamFrom + beamTo) / 2, beamTo), Color3.fromRGB(210, 230, 255))
		beam.Transparency = 0.93
		-- Seat rows face the screen (-X). Fill the middle row first.
		local seatColor = ({ Color3.fromRGB(200, 40, 45), Color3.fromRGB(170, 25, 40), Color3.fromRGB(120, 20, 35), Color3.fromRGB(30, 30, 35) })[tier + 1]
		local order = {}
		for _, x in { -19, -26, -12 } do
			for _, z in { 7.5, 14.5, 4.5, 17.5, 1.5, 20.5 } do
				table.insert(order, V(x, 0, z))
			end
		end
		local seats: { WorldSeat } = {}
		local count = math.min(2 * k.units, #order)
		for n, spot in order do
			local cf = turn(k.at(spot.X, 0, spot.Z), R90)
			local built = n <= count
			-- Empty rows are still there, just without anyone allowed in them yet.
			local color = if built then seatColor else Color3.fromRGB(90, 90, 95)
			if tier >= 2 then
				box(m, "Recliner", V(2.8, 1.8, 2.8), cf * CFrame.new(0, 0.9, 0), color, FABRIC)
				box(m, "ReclinerBack", V(2.8, 3.6, 0.8), cf * CFrame.new(0, 2.6, 1.3) * CFrame.Angles(math.rad(12), 0, 0), color, FABRIC)
				if tier == 3 and built then
					glow(m, "PodLight", V(2.8, 0.15, 0.1), cf * CFrame.new(0, 0.3, -1.45), GOLD)
				end
			else
				box(m, "CinemaSeat", V(2.4, 0.6, 2.4), cf * CFrame.new(0, 1.7, 0), color, if tier == 1 then FABRIC else nil)
				box(m, "CinemaBack", V(2.4, 3, 0.4), cf * CFrame.new(0, 3, 1.1), color, if tier == 1 then FABRIC else nil)
				box(m, "CinemaLeg", V(2, 1.4, 1.6), cf * CFrame.new(0, 0.7, 0.3), DARK)
			end
			for _, s in { -1, 1 } do
				box(m, "Armrest", V(0.3, 0.8, 2.4), cf * CFrame.new(s * 1.45, 2.4, 0), DARK, nil, true)
			end
			if built then
				table.insert(seats, {
					position = k.world(spot.X, spot.Z),
					yaw = R90,
					aisle = k.world(spot.X - 2.2, 11),
					approach = k.world(spot.X - 2.2, spot.Z),
				})
			end
		end
		-- Standing room at the back (right side) for everyone else.
		local views: { View } = {}
		for _, x in { 26, 31 } do
			for _, z in { 3, 7, 15, 19 } do
				table.insert(views, { position = k.world(x, z), yaw = R90, aisle = k.world(x, 11) })
			end
		end
		return seats, views
	end,
	extras = function(k: any)
		local m = k.decor
		-- Movie posters on the right wall.
		local posters = { { "🦖", D.GREEN }, { "🚀", D.BLUE }, { "🧙", D.PURPLE }, { "🐉", D.RED } }
		for j, p in posters do
			local z = -0.5 + (j - 1) * 6
			wallBox(k, "PosterFrame", 1, z, 8, 7, 4.6, 0.3, GOLD)
			local poster = wallBox(k, "Poster", 1, z, 8, 6.4, 4, 0.35, p[2])
			wallText(poster, 1, p[1] .. "\nNOW\nSHOWING", WHITE, 25)
		end
		-- Aisle lights on the floor.
		for j = 0, 8 do
			glow(m, "AisleLight", V(1.2, 0.1, 0.4), k.at(-30 + j * 7, 0.06, 9.2), Color3.fromRGB(255, 200, 80))
			glow(m, "AisleLight", V(1.2, 0.1, 0.4), k.at(-30 + j * 7, 0.06, 12.8), Color3.fromRGB(255, 200, 80))
		end
		-- Snack stand, back-left; film reel, back-right.
		box(m, "CandyCounter", V(8, 3, 3), corner(k, -1, 0, 1.5, 0), Color3.fromRGB(180, 30, 40))
		for j = 0, 4 do
			box(m, "CandyBox", V(1.2, 1.6, 0.8), corner(k, -1, -2.8 + j * 1.4, 3.8, 0), D.BRIGHT[j + 1], nil, true)
		end
		rod(m, "FilmReel", 0.6, 6, corner(k, 1, 0, 4, 0) * CFrame.Angles(0, R90, 0), DARK)
		for j = 0, 5 do
			local a = j * math.pi / 3
			rod(m, "ReelHole", 0.7, 1.2, corner(k, 1, math.cos(a) * 1.6, 4 + math.sin(a) * 1.6, 0) * CFrame.Angles(0, R90, 0), STEEL, nil, true)
		end
		box(m, "ReelStand", V(1, 1.2, 1), corner(k, 1, 0, 0.6, 0), DARK)
	end,
}

Kits.Aquarium = {
	back = "tank", station = "tank", counter = "shop", sign = "🐠 TICKETS", register = "ticket", walls = "LR",
	worker = { shirt = Color3.fromRGB(40, 150, 200), pants = Color3.fromRGB(40, 60, 90), hat = Color3.fromRGB(255, 200, 60) },
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		local tier = k.seatTier
		local zt = back + 1.3
		box(m, "TankBase", V(10.4, 1, 2.6), c(0, 0.5, zt), Color3.fromRGB(40, 60, 80))
		local water = glass(m, "Water", V(10, 7, 2.2), c(0, 4.5, zt), 0.35, Color3.fromRGB(40, 150, 230))
		D.bubbles(water, 6)
		box(m, "TankTop", V(10.4, 0.6, 2.6), c(0, 8.3, zt), Color3.fromRGB(40, 60, 80))
		box(m, "Sand", V(9.8, 0.6, 2), c(0, 1.3, zt), Color3.fromRGB(240, 220, 160), nil, true)
		for j = 0, 2 do
			box(m, "Coral", V(0.8, 1.4 + j * 0.6, 0.6), c(-3.5 + j * 3.4, 2 + j * 0.3, zt), ({ D.PINK, D.ORANGE, D.PURPLE })[j + 1], nil, true)
		end
		for j = 1, 5 do
			D.fish(m, c(-4.5 + j * 1.6, 2.6 + ((j + i) % 4) * 1.3, zt), fishColor(j + i), 1.2)
		end
		if i % 2 == 0 then
			ball(m, "Turtle", 1.8, c(2.5, 5.5, zt), Color3.fromRGB(90, 160, 90), nil, true)
		end
		-- Viewing bench (Seating tiers).
		local bench = ({ Color3.fromRGB(140, 140, 135), WOOD, Color3.fromRGB(60, 110, 170), D.GLASS })[tier + 1]
		local material = ({ Enum.Material.Slate, PLANKS, FABRIC, D.GLASSMAT })[tier + 1]
		box(m, "Bench", V(6.4, 1.9, 1.8), c(0, 0.95, 1.5), bench, material)
		if tier == 3 then
			glow(m, "BenchGlow", V(6.4, 0.1, 0.1), c(0, 0.2, 2.45), Color3.fromRGB(110, 220, 255))
		end
		return { { x = -1.8, z = 1.5, yaw = 0 }, { x = 1.8, z = 1.5, yaw = 0 } }
	end,
	extras = function(k: any)
		local m = k.decor
		-- Jellyfish column, back-left.
		cyl(m, "JellyBase", 1, 5, corner(k, -1, 0, 0.5, 0), DARK)
		glass(m, "JellyTank", V(10, 4.6, 4.6), corner(k, -1, 0, 6, 0) * CFrame.Angles(0, 0, R90), 0.35, Color3.fromRGB(110, 60, 160)).Shape = Enum.PartType.Cylinder
		for j = 0, 2 do
			ball(m, "Jelly", 1.2, corner(k, -1, -1 + j, 4 + j * 2.2, (j % 2) - 0.5), Color3.fromRGB(255, 140, 230), NEON, true)
		end
		cyl(m, "JellyTop", 0.8, 5, corner(k, -1, 0, 11.4, 0), DARK)
		-- Big wall tanks on both side walls.
		for _, side in { -1, 1 } do
			local water = wallBox(k, "WallTank", side, 10, 7, 10, 22, 1.4, Color3.fromRGB(40, 150, 230), Enum.Material.Glass)
			water.Transparency = 0.3
			wallBox(k, "WallTankFrame", side, 10, 7, 10.8, 22.8, 1.2, Color3.fromRGB(30, 50, 70))
			for j = 1, 6 do
				D.fish(m, k.at(side * 38.6, 4 + (j % 3) * 2.5, -0.5 + j * 3.2) * CFrame.Angles(0, R90, 0), fishColor(j + (if side > 0 then 2 else 0)), 1.4)
			end
		end
		-- Shark hanging over the hall.
		local grey = Color3.fromRGB(120, 135, 150)
		box(m, "SharkBody", V(12, 2.6, 3), k.at(0, 16, 11), grey, nil, true)
		wedge(m, "SharkNose", V(3, 2.6, 3), k.at(-7.5, 16, 11) * CFrame.Angles(0, R90, 0), grey, nil, true)
		wedge(m, "SharkFin", V(0.4, 2.6, 2.6), k.at(0, 18.4, 11) * CFrame.Angles(0, R90, 0), grey, nil, true)
		wedge(m, "SharkTail", V(0.4, 3.4, 2.6), k.at(7.4, 16.6, 11) * CFrame.Angles(0, -R90, 0), grey, nil, true)
		box(m, "SharkWire", V(0.1, 4, 0.1), k.at(0, 19.6, 11), DARK, nil, true)
		-- Bubble column, back-right.
		local tube = glass(m, "BubbleTube", V(10, 2.6, 2.6), corner(k, 1, 0, 5, 0) * CFrame.Angles(0, 0, R90), 0.4, Color3.fromRGB(90, 190, 255))
		tube.Shape = Enum.PartType.Cylinder
		D.bubbles(tube, 14)
		cyl(m, "TubeBase", 0.6, 3.4, corner(k, 1, 0, 0.3, 0), DARK)
	end,
}

Kits.Arcade = {
	back = "dark", station = "tokenMachine", counter = "shop", sign = "🕹️ TOKENS", register = "ticket", walls = "R",
	worker = { shirt = Color3.fromRGB(40, 35, 60), pants = Color3.fromRGB(30, 30, 40), hat = Color3.fromRGB(60, 240, 200) },
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		local tier = k.seatTier
		local shell = ({ Color3.fromRGB(200, 170, 120), Color3.fromRGB(30, 30, 40), Color3.fromRGB(40, 40, 60), Color3.fromRGB(20, 20, 30) })[tier + 1]
		local screenColors = { Color3.fromRGB(110, 255, 160), Color3.fromRGB(255, 110, 200), Color3.fromRGB(110, 200, 255), Color3.fromRGB(255, 230, 100) }
		if i % 2 == 1 then
			-- Two game cabinets.
			for n, x in { -2.2, 2.2 } do
				box(m, "Cabinet", V(3.2, 7, 2.6), c(x, 3.5, -1.6), shell, if tier == 0 then PLANKS else nil)
				box(m, "Panel", V(3.2, 0.6, 1.4), c(x, 3.4, -0.1) * CFrame.Angles(math.rad(15), 0, 0), DARK)
				ball(m, "Stick", 0.5, c(x - 0.6, 3.9, 0), D.RED, nil, true)
				ball(m, "Button", 0.35, c(x + 0.6, 3.75, 0), D.YELLOW, NEON, true)
				glow(m, "GameScreen", V(2.6, if tier >= 2 then 2.6 else 2, 0.1), c(x, 5.3, -0.25), screenColors[(n + i) % 4 + 1])
				glow(m, "Marquee", V(3.2, 0.9, 0.2), c(x, 7.3, -0.3), k.theme.primary)
				if tier >= 1 then
					glow(m, "SideNeon", V(0.1, 7, 0.1), c(x - 1.65, 3.5, -0.3), k.theme.accent)
					glow(m, "SideNeon", V(0.1, 7, 0.1), c(x + 1.65, 3.5, -0.3), k.theme.accent)
				end
				if tier == 3 then
					box(m, "VRHeadset", V(1, 0.6, 0.8), c(x, 4.4, 0.4), WHITE, nil, true)
				end
			end
			return { { x = -2.2, z = 1, yaw = 0, stand = true, busy = true }, { x = 2.2, z = 1, yaw = 0, stand = true, busy = true } }
		end
		-- Claw machine and air hockey.
		box(m, "ClawBase", V(3.6, 3, 3.4), c(2.4, 1.5, -1.4), k.theme.primary)
		glass(m, "ClawGlass", V(3.6, 4, 3.4), c(2.4, 5, -1.4), 0.6)
		box(m, "ClawTop", V(3.8, 0.8, 3.6), c(2.4, 7.4, -1.4), k.theme.primary)
		for j = 0, 5 do
			ball(m, "Prize", 1, c(1.4 + (j % 3) * 1, 3.5 + math.floor(j / 3) * 0.6, -2.2 + math.floor(j / 3) * 1.2), D.BRIGHT[j + 1], nil, true)
		end
		box(m, "ClawWire", V(0.1, 1.4, 0.1), c(2.4, 6.3, -1.4), STEEL, nil, true)
		box(m, "Claw", V(0.8, 0.6, 0.8), c(2.4, 5.4, -1.4), STEEL, METAL, true)
		box(m, "HockeyTable", V(3.6, 2.8, 5.6), c(-2.5, 1.4, -1.2), shell)
		box(m, "HockeyTop", V(3.4, 0.1, 5.4), c(-2.5, 2.85, -1.2), Color3.fromRGB(230, 240, 255), nil, true)
		glow(m, "HockeyEdge", V(3.8, 0.2, 5.8), c(-2.5, 2.7, -1.2), k.theme.accent)
		cyl(m, "Puck", 0.15, 0.6, c(-2.5, 3, -1.6), D.RED, nil, true)
		return { { x = -2.5, z = 2.5, yaw = 0, stand = true, busy = true }, { x = 2.4, z = 1.4, yaw = 0, stand = true, busy = true } }
	end,
	extras = function(k: any)
		local m = k.decor
		-- Prize wall on the right wall.
		wallBox(k, "PrizeWall", 1, 10, 6, 12, 22, 0.4, Color3.fromRGB(40, 35, 60))
		for row, y in { 2, 5, 8, 11 } do
			wallBox(k, "PrizeShelf", 1, 10, y - 0.8, 0.3, 22, 2.4, Color3.fromRGB(70, 60, 100))
			for j = 0, 6 do
				local z = 0.5 + j * 3.2
				if (j + row) % 2 == 0 then
					teddy(m, k.at(38.4, y - 0.65, z), 0.45, D.BRIGHT[(j + row) % 6 + 1])
				else
					ball(m, "PrizeBall", 1.2, k.at(38.4, y - 0.05, z), D.BRIGHT[(j + row + 3) % 6 + 1], nil, true)
				end
			end
		end
		local sign = wallBox(k, "PrizeSign", 1, 10, 13.6, 2, 14, 0.3, Color3.fromRGB(20, 15, 30))
		wallText(sign, 1, "🏆 PRIZES 🏆", Color3.fromRGB(255, 220, 80), 25)
		-- Dance machine, back-left.
		box(m, "DancePad", V(6, 0.6, 5), corner(k, -1, 0, 0.3, 0.4), DARK)
		local arrows = { D.RED, D.BLUE, D.GREEN, D.YELLOW }
		for j, off in { V(-1.4, 0, 0), V(1.4, 0, 0), V(0, 0, -1.2), V(0, 0, 1.2) } do
			glow(m, "Arrow", V(1.2, 0.1, 1.2), corner(k, -1, off.X, 0.65, 0.4 + off.Z), arrows[j])
		end
		box(m, "DanceScreen", V(6, 5, 1), corner(k, -1, 0, 5, -2.6), DARK)
		glow(m, "DanceScreenGlow", V(5.4, 4.2, 0.1), corner(k, -1, 0, 5, -2.05), Color3.fromRGB(255, 100, 220))
		-- Neon strips along the walkway.
		for _, z in { 8.8, 13.2 } do
			glow(m, "FloorNeon", V(70, 0.08, 0.3), k.at(0, 0.06, z), k.theme.accent)
		end
		-- Racing seat, back-right.
		box(m, "RacerBody", V(4, 3, 5), corner(k, 1, 0, 1.5, 0), k.theme.primary)
		box(m, "RacerScreen", V(4.4, 3.4, 0.6), corner(k, 1, 0, 5, -2.6), DARK)
		glow(m, "RacerGlow", V(4, 3, 0.1), corner(k, 1, 0, 5, -2.25), Color3.fromRGB(110, 200, 255))
		rod(m, "Wheel", 0.3, 1.6, corner(k, 1, 0, 3.8, -1.6) * CFrame.Angles(0, R90, 0), DARK, nil, true)
	end,
}

Kits.Spa = {
	back = "spa", station = "towelWarmer", counter = "desk", sign = "🌿 RECEPTION", register = "desk", walls = "LR",
	worker = { shirt = WHITE, pants = Color3.fromRGB(200, 200, 200) },
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		local tier = k.seatTier
		local bamboo = Color3.fromRGB(200, 180, 120)
		-- Bamboo partitions on three sides (open toward the aisle).
		for _, x in { -5.3, 5.3 } do
			box(m, "Partition", V(0.3, 7, 4.5 - back - 1.6), c(x, 3.5, (back + 2.9) / 2), bamboo, PLANKS)
		end
		box(m, "PartitionBack", V(10.9, 7, 0.3), c(0, 3.5, back + 0.15), bamboo, PLANKS)
		for j = 0, 4 do
			box(m, "Slat", V(0.15, 7, 0.4), c(-4 + j * 2, 3.5, back + 0.35), Color3.fromRGB(150, 130, 80), nil, true)
		end
		-- Massage bed (Seating tiers).
		local bed = ({ WHITE, Color3.fromRGB(240, 200, 210), Color3.fromRGB(240, 200, 180), WHITE })[tier + 1]
		box(m, "BedFrame", V(7, 1.6, 2.6), c(0, 0.8, -0.4), Color3.fromRGB(150, 110, 70), PLANKS)
		box(m, "BedPad", V(7, if tier >= 1 then 0.6 else 0.4, 2.6), c(0, 1.9, -0.4), bed, FABRIC)
		rod(m, "TowelRoll", 2.6, 0.7, c(-3, 2.5, -0.4) * CFrame.Angles(0, R90, 0), k.theme.accent:Lerp(WHITE, 0.5), FABRIC, true)
		if tier == 2 then
			glow(m, "Heat", V(7, 0.15, 0.15), c(0, 1.55, 0.95), Color3.fromRGB(255, 140, 70))
		elseif tier == 3 then
			for j = 0, 5 do
				ball(m, "Cloud", 1.2, c(-3 + j * 1.2, 2.2, 0.85), WHITE, FABRIC, true)
			end
		end
		-- Candles and a little plant.
		box(m, "CandleStand", V(1.6, 2, 1.6), c(4, 1, back + 1.1), bamboo, PLANKS)
		for j = 0, 2 do
			cyl(m, "Candle", 0.6 + j * 0.2, 0.4, c(3.6 + j * 0.4, 2.3 + j * 0.1, back + 1.1), WHITE, nil, true)
			ball(m, "Flame", 0.25, c(3.6 + j * 0.4, 2.75 + j * 0.2, back + 1.1), D.ORANGE, NEON, true)
		end
		D.plant(m, c(-4, 0, back + 1.1).Position, 0.6)
		return { { x = 0, z = 0.3, yaw = PI } }
	end,
	extras = function(k: any)
		local m = k.decor
		-- Hot tub with steam, back-left.
		cyl(m, "TubRim", 2.4, 7, corner(k, -1, 0, 1.2, 0), Color3.fromRGB(150, 110, 70), PLANKS)
		local water = cyl(m, "TubWater", 0.2, 6, corner(k, -1, 0, 2.35, 0), Color3.fromRGB(110, 210, 230), D.GLASSMAT, true)
		D.bubbles(water, 10)
		D.smoke(water, WHITE, 0.06)
		-- Zen garden, back-right.
		box(m, "ZenFrame", V(9, 0.6, 5), corner(k, 1, 0, 0.3, 0), Color3.fromRGB(110, 80, 55), PLANKS)
		box(m, "ZenSand", V(8.4, 0.2, 4.4), corner(k, 1, 0, 0.65, 0), Color3.fromRGB(235, 225, 200), Enum.Material.Sand, true)
		for j = 0, 4 do
			box(m, "Rake", V(8, 0.05, 0.12), corner(k, 1, 0, 0.78, -1.6 + j * 0.8), Color3.fromRGB(205, 195, 170), nil, true)
		end
		for j, spec in { { -2.4, 1.6 }, { 1.2, 1.1 }, { 2.8, 0.8 } } do
			ball(m, "Stone", spec[2], corner(k, 1, spec[1], 0.9, (j % 2) - 0.5), Color3.fromRGB(110, 110, 105), Enum.Material.Slate, true)
		end
		-- Bamboo panels on the side walls.
		for _, side in { -1, 1 } do
			for j = 0, 10 do
				wallBox(k, "Bamboo", side, -0.5 + j * 2.1, 7, 14, 0.8, 0.5, Color3.fromRGB(150, 180, 90), Enum.Material.Wood)
			end
			local sign = wallBox(k, "SpaSign", side, 10, 15.4, 1.8, 10, 0.7, Color3.fromRGB(70, 110, 80))
			wallText(sign, side, "RELAX 🌿", WHITE, 25)
		end
	end,
}

Kits.Hotel = {
	back = "laundry", station = "washer", counter = "desk", sign = "🛎️ RECEPTION", register = "desk", walls = "",
	product = "towels",
	worker = { shirt = Color3.fromRGB(120, 170, 220), pants = Color3.fromRGB(240, 240, 240) },
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		local tier = k.seatTier
		local wallColor = Color3.fromRGB(245, 235, 215)
		local trim = Color3.fromRGB(150, 100, 60)
		local h = 9
		-- Walls: back, both sides, and a front wall with a doorway.
		box(m, "RoomBack", V(11, h, 0.4), c(0, h / 2, back + 0.2), wallColor)
		for _, x in { -5.3, 5.3 } do
			box(m, "RoomSide", V(0.4, h, 4.5 - back), c(x, h / 2, (back + 4.5) / 2), wallColor)
		end
		for _, x in { -3.85, 3.85 } do
			box(m, "RoomFront", V(3.3, h, 0.4), c(x, h / 2, 4.3), wallColor)
		end
		box(m, "Lintel", V(4.4, 1.6, 0.4), c(0, h - 0.8, 4.3), wallColor)
		box(m, "WallTrim", V(11.2, 0.4, 0.6), c(0, h + 0.2, 4.3), trim, nil, true)
		box(m, "Carpet", V(10.2, 0.1, 4.2 - back), c(0, 0.06, (back + 4.1) / 2), k.theme.accent:Lerp(Color3.new(0, 0, 0), 0.2), FABRIC, true)
		local plate = box(m, "RoomNumber", V(2, 0.8, 0.1), turn(c(0, h - 0.8, 4.55), PI), GOLD, nil, true)
		D.text(plate, Enum.NormalId.Front, tostring(100 + i), DARK, 30)
		-- Bed (Seating tiers: single, double, queen, king).
		local width = ({ 3.6, 5, 6, 7.4 })[tier + 1]
		local head = back + 0.6
		local length = 6
		box(m, "Headboard", V(width + 0.4, 4.2, 0.5), c(0, 2.1, head), if tier == 3 then GOLD else trim, if tier == 3 then Enum.Material.Foil else PLANKS)
		box(m, "BedFrame", V(width, 1.4, length), c(0, 0.7, head + 0.25 + length / 2), trim, PLANKS)
		box(m, "Mattress", V(width - 0.2, 0.8, length - 0.2), c(0, 1.8, head + 0.25 + length / 2), WHITE, FABRIC)
		box(m, "Blanket", V(width, 0.3, length * 0.55), c(0, 2.3, head + 0.25 + length * 0.7), k.theme.primary, FABRIC, true)
		local pillows = if width >= 5 then { -width / 4, width / 4 } else { 0 }
		for _, x in pillows do
			box(m, "Pillow", V(1.8, 0.6, 1.1), c(x, 2.5, head + 1), WHITE, FABRIC, true)
		end
		-- Nightstand with a lamp, and a TV on the front wall.
		local nx = width / 2 + 0.9
		if nx < 4.4 then
			box(m, "Nightstand", V(1.4, 2.2, 1.4), c(nx, 1.1, head + 0.9), trim, PLANKS)
			local lamp = glow(m, "Lamp", V(0.9, 0.9, 0.9), c(nx, 2.9, head + 0.9), D.WARM)
			local _ = lamp
		end
		box(m, "TV", V(2.8, 1.8, 0.2), c(-3.75, 5.2, 4), DARK, nil, true)
		glow(m, "TVScreen", V(2.5, 1.5, 0.05), c(-3.75, 5.2, 3.88), Color3.fromRGB(110, 180, 255))
		local foot = head + 0.25 + length
		if tier == 0 then
			return { { x = 0, z = foot - 0.4, yaw = PI } }
		end
		local seatX = if tier == 1 then 1.1 else 1.4
		return { { x = -seatX, z = foot - 0.4, yaw = PI }, { x = seatX, z = foot - 0.4, yaw = PI } }
	end,
	extras = function(k: any)
		local m = k.decor
		-- Elevator on the left wall, beside the reception.
		local door = Color3.fromRGB(190, 195, 205)
		wallBox(k, "ElevatorFrame", -1, -11, 5.5, 11, 8, 0.4, GOLD)
		for _, dz in { -1.6, 1.6 } do
			wallBox(k, "ElevatorDoor", -1, -11 + dz, 5, 9.6, 3.1, 0.5, door, METAL)
		end
		local indicator = wallBox(k, "ElevatorSign", -1, -11, 12, 1.4, 4, 0.5, DARK)
		wallText(indicator, -1, "▲ 1", Color3.fromRGB(255, 200, 80), 30)
		-- Luggage cart and lobby armchairs, back-right.
		box(m, "CartBase", V(4, 0.4, 2.6), corner(k, 1, 2.4, 0.8, 0), GOLD, Enum.Material.Foil)
		for _, dx in { -1.8, 1.8 } do
			box(m, "CartPole", V(0.3, 6, 0.3), corner(k, 1, 2.4 + dx, 3.8, 0), GOLD, Enum.Material.Foil)
		end
		rod(m, "CartBar", 4, 0.3, corner(k, 1, 2.4, 6.8, 0), GOLD, Enum.Material.Foil)
		for j, col in { D.RED, D.BLUE, DARK } do
			box(m, "Suitcase", V(1.6, 2.2 - j * 0.3, 1.2), corner(k, 1, 1.2 + j * 1.1, 2.1 - j * 0.15, 0), col, nil, true)
		end
		for j, dz in { -1.4, 1.4 } do
			local _ = j
			armchair(m, turn(corner(k, 1, -3.6, 0, dz), -R90), Color3.fromRGB(140, 30, 50), FABRIC)
		end
		-- Lobby chandelier sparkle over the lane.
		for _, z in { 14, 22 } do
			box(m, "ChandelierCord", V(0.15, 3, 0.15), k.at(0, 18.5, z), GOLD, nil, true)
			local crystal = ball(m, "Crystal", 2, k.at(0, 16.6, z), Color3.fromRGB(255, 240, 200), NEON, true)
			D.light(crystal, D.WARM, 20, 0.8)
		end
	end,
}

Kits.Mall = {
	back = "stock", station = "stockShelf", counter = "desk", sign = "ℹ️ INFO DESK", register = "desk", walls = "LR",
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		local tier = k.seatTier
		if i % 2 == 1 then
			-- Kiosk store.
			local names = { "SHOES", "TOYS", "PHONES", "FASHION", "SWEETS", "BOOKS", "GIFTS" }
			local color = D.BRIGHT[(i - 1) % #D.BRIGHT + 1]
			box(m, "KioskCounter", V(9, 3, 2.4), c(0, 1.5, -1.4), color)
			box(m, "KioskTop", V(9.4, 0.3, 2.8), c(0, 3.15, -1.4), WHITE)
			for _, x in { -4.3, 4.3 } do
				box(m, "KioskPost", V(0.3, 5, 0.3), c(x, 5.8, -1.4), DARK)
			end
			for j = 0, 5 do
				wedge(m, "Awning", V(1.55, 1.2, 2.4), c(-3.9 + j * 1.55, 8.6, -1) * CFrame.Angles(0, PI, 0), if j % 2 == 0 then color else WHITE, nil, true)
			end
			local sign = box(m, "KioskSign", V(6, 1.4, 0.2), c(0, 7.4, -0.3), DARK, nil, true)
			D.text(sign, Enum.NormalId.Back, names[(math.floor(i / 2)) % #names + 1], color:Lerp(WHITE, 0.4), 25)
			for j = 0, 3 do
				box(m, "Goods", V(1.4, 1.2, 1.2), c(-3 + j * 2, 3.9, -1.6), D.BRIGHT[(j + i) % 6 + 1], nil, true)
			end
			return { { x = -2.2, z = 1.2, yaw = 0, stand = true }, { x = 2.2, z = 1.2, yaw = 0, stand = true } }
		end
		-- Food court table.
		cyl(m, "FoodTable", 0.3, 4, c(0, 3.1, 0), WHITE)
		cyl(m, "FoodLeg", 3, 0.5, c(0, 1.5, 0), DARK, METAL)
		box(m, "Tray", V(1.6, 0.1, 1.2), c(0, 3.3, 0.4), D.RED, nil, true)
		cyl(m, "Drink", 0.9, 0.5, c(0.5, 3.7, -0.6), D.ORANGE, nil, true)
		if tier == 3 then
			armchair(m, turn(c(-4, 0, 0), -R90), Color3.fromRGB(60, 150, 140), FABRIC)
			armchair(m, turn(c(4, 0, 0), R90), Color3.fromRGB(60, 150, 140), FABRIC)
			return { { x = -4, z = 0, yaw = -R90 }, { x = 4, z = 0, yaw = R90 } }
		end
		return chairs(k, c, 3.8, tier, if tier == 0 then k.theme.primary else nil, k.theme.accent)
	end,
	extras = function(k: any)
		local m = k.decor
		-- Store facades on both side walls.
		local shops = { { "👟 SHOES", D.RED }, { "👗 FASHION", D.PINK }, { "🎮 GAMES", D.PURPLE }, { "🍭 SWEETS", D.ORANGE } }
		for n, side in { -1, 1 } do
			for j = 0, 1 do
				local shop = shops[(n - 1) * 2 + j + 1]
				local z = 4 + j * 12
				wallBox(k, "Facade", side, z, 7, 14, 10.6, 0.6, WHITE)
				local window = wallBox(k, "ShopWindow", side, z, 5, 7, 8.6, 0.8, Color3.fromRGB(170, 225, 255), NEON)
				window.Transparency = 0.3
				local sign = wallBox(k, "ShopSign", side, z, 11.8, 2.4, 9, 0.9, shop[2])
				wallText(sign, side, shop[1], WHITE, 25)
			end
		end
		-- Escalator, back-left.
		wedge(m, "Escalator", V(4, 9, 7), corner(k, -1, 0, 4.5, 0) * CFrame.Angles(0, R90, 0), STEEL, METAL)
		for _, dz in { -2.2, 2.2 } do
			wedge(m, "Handrail", V(0.4, 10, 7.4), corner(k, -1, 0, 5.4, dz) * CFrame.Angles(0, R90, 0), DARK, nil, true)
		end
		-- Map board, back-right.
		local map = box(m, "MapBoard", V(5, 6, 0.4), corner(k, 1, 0, 4, -1.6), Color3.fromRGB(240, 245, 250))
		D.text(map, Enum.NormalId.Back, "🗺️\nYOU ARE\nHERE", D.BLUE, 25)
		box(m, "MapPost", V(0.6, 1, 0.6), corner(k, 1, 0, 0.5, -1.6), DARK)
		-- "Mega Sale" banners hanging over the concourse.
		for _, x in { -20, 20 } do
			local banner = box(m, "SaleBanner", V(10, 3, 0.2), k.at(x, 16, 11), D.RED, FABRIC, true)
			D.text(banner, Enum.NormalId.Back, "MEGA SALE!", WHITE, 25)
			D.text(banner, Enum.NormalId.Front, "MEGA SALE!", WHITE, 25)
			box(m, "BannerCord", V(0.1, 3.4, 0.1), k.at(x, 19.2, 11), DARK, nil, true)
		end
	end,
}

Kits.TechCompany = {
	back = "dark", station = "serverRack", counter = "desk", sign = "💻 FRONT DESK", register = "desk", walls = "LR",
	worker = { shirt = Color3.fromRGB(60, 60, 75), pants = Color3.fromRGB(70, 90, 140) },
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		local tier = k.seatTier
		box(m, "Desk", V(10, 0.4, 3), c(0, 3, -1.4), WHITE)
		for _, x in { -4.7, 4.7 } do
			box(m, "DeskLeg", V(0.4, 3, 2.6), c(x, 1.5, -1.4), Color3.fromRGB(80, 80, 90))
		end
		box(m, "Divider", V(10, 1.6, 0.2), c(0, 4, -2.8), k.theme.primary:Lerp(WHITE, 0.4))
		for n, x in { -2.5, 2.5 } do
			box(m, "Monitor", V(2.8, 1.8, 0.2), c(x, 4.6, -2.3), DARK, nil, true)
			glow(m, "Code", V(2.5, 1.5, 0.05), c(x, 4.6, -2.18), if n == 1 then Color3.fromRGB(90, 255, 140) else k.theme.accent)
			box(m, "Keyboard", V(2, 0.1, 0.7), c(x, 3.25, -1), DARK, nil, true)
			cyl(m, "Mug", 0.6, 0.5, c(x + 1.4, 3.5, -1.2), D.BRIGHT[(n + i) % 6 + 1], nil, true)
		end
		D.plant(m, c(0, 3.2, -1.6).Position, 0.3)
		-- Office chairs (Seating tiers).
		local seatColor = ({ WOOD, Color3.fromRGB(60, 60, 70), Color3.fromRGB(40, 40, 50), D.RED })[tier + 1]
		for _, x in { -2.5, 2.5 } do
			if tier == 0 then
				D.stool(m, c(x, 0, 1.2), 0)
			else
				box(m, "ChairSeat", V(2.4, 0.4, 2.4), c(x, 1.85, 1.2), seatColor, FABRIC)
				box(m, "ChairBack", V(2.4, if tier >= 2 then 3.6 else 2.6, 0.4), c(x, 3.6, 2.3), seatColor, FABRIC)
				cyl(m, "ChairPost", 1.4, 0.4, c(x, 1, 1.2), DARK)
				for j = 0, 4 do
					box(m, "ChairFoot", V(0.3, 0.2, 1.2), turn(c(x, 0.1, 1.2), j * math.pi * 2 / 5) * CFrame.new(0, 0, -0.6), DARK, nil, true)
				end
				if tier == 3 then
					glow(m, "GamingTrim", V(0.1, 3.4, 0.1), c(x - 1.2, 3.6, 2.3), k.theme.accent)
					glow(m, "GamingTrim", V(0.1, 3.4, 0.1), c(x + 1.2, 3.6, 2.3), k.theme.accent)
				end
			end
		end
		return { { x = -2.5, z = 1.2, yaw = 0, busy = true }, { x = 2.5, z = 1.2, yaw = 0, busy = true } }
	end,
	extras = function(k: any)
		local m = k.decor
		-- Big graph screen on the left wall.
		wallBox(k, "GraphWall", -1, 10, 8, 10, 20, 0.4, Color3.fromRGB(20, 22, 30))
		local points = { 3, 4.5, 4, 6.5, 6, 8.5, 11 }
		for j = 1, #points - 1 do
			local a = k.at(-39.1, points[j] + 2, 1 + (j - 1) * 3).Position
			local b = k.at(-39.1, points[j + 1] + 2, 1 + j * 3).Position
			glow(m, "GraphLine", V(0.1, 0.3, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), Color3.fromRGB(90, 255, 140))
		end
		local title = wallBox(k, "GraphTitle", -1, 10, 14.3, 1.6, 12, 0.3, k.theme.primary)
		wallText(title, -1, "📈 USERS: 1,000,000", WHITE, 25)
		-- Whiteboard on the right wall.
		wallBox(k, "Whiteboard", 1, 10, 8, 7, 16, 0.3, WHITE)
		wallBox(k, "WhiteboardFrame", 1, 10, 8, 7.4, 16.4, 0.2, STEEL)
		for j = 0, 3 do
			wallBox(k, "Scribble", 1, 4 + j * 3.6, 8 + (j % 2), 0.3, 2.6, 0.35, D.BRIGHT[j + 1])
			wallBox(k, "Note", 1, 4.4 + j * 3.6, 10, 1.2, 1.2, 0.35, D.YELLOW)
		end
		-- Beanbags, back-right.
		for j, dx in { -3, 0.5, 4 } do
			cyl(m, "Beanbag", 1.4, 3, corner(k, 1, dx, 0.7, (j % 2) * 1.2 - 0.6), D.BRIGHT[j + 2], FABRIC)
			ball(m, "BeanTop", 2.4, corner(k, 1, dx, 1.4, (j % 2) * 1.2 - 0.2), D.BRIGHT[j + 2], FABRIC, true)
		end
		-- Meeting table, back-left.
		box(m, "MeetingTable", V(8, 0.4, 3.4), corner(k, -1, 0, 3, 0), Color3.fromRGB(240, 240, 245))
		box(m, "MeetingLeg", V(1, 3, 1), corner(k, -1, 0, 1.5, 0), DARK)
		for _, dx in { -2.6, 0, 2.6 } do
			D.chair(m, corner(k, -1, dx, 0, 2.6), 2, DARK, k.theme.primary)
		end
		glow(m, "MeetingLaptop", V(1.6, 1, 0.1), corner(k, -1, 0, 3.7, -0.4), k.theme.accent)
	end,
}

Kits.Bank = {
	back = "office", station = "cashCounter", counter = "desk", sign = "🏦 TELLERS", register = "teller", walls = "LR",
	worker = { shirt = Color3.fromRGB(45, 50, 65), pants = Color3.fromRGB(35, 38, 48) },
	unit = function(k: any, c: Frame, i: number, back: number): { Seat }
		local m = k.decor
		local tier = k.seatTier
		local seat = ({ Color3.fromRGB(170, 170, 175), WOOD, Color3.fromRGB(70, 40, 30), Color3.fromRGB(30, 90, 60) })[tier + 1]
		local material = ({ METAL, PLANKS, Enum.Material.Leather, FABRIC })[tier + 1]
		-- Waiting bench facing the aisle.
		box(m, "BenchSeat", V(5.6, 0.5, 2), c(-0.8, 1.75, 0.6), seat, material)
		box(m, "BenchBack", V(5.6, 2.8, 0.4), c(-0.8, 3.2, -0.5), seat, material)
		for _, x in { -3.2, 1.6 } do
			box(m, "BenchLeg", V(0.4, 1.5, 1.6), c(x, 0.75, 0.6), DARK)
		end
		if tier == 3 then
			box(m, "BenchTrim", V(5.7, 0.2, 0.5), c(-0.8, 4.7, -0.5), GOLD, nil, true)
		end
		-- ATM.
		box(m, "ATM", V(2.2, 5.6, 1.8), c(4, 2.8, -2.4), Color3.fromRGB(60, 65, 80), METAL)
		glow(m, "ATMScreen", V(1.4, 1, 0.1), c(4, 4.2, -1.45), Color3.fromRGB(110, 220, 140))
		box(m, "ATMPad", V(1.4, 0.6, 0.6), c(4, 3.1, -1.3), STEEL, nil, true)
		local sign = box(m, "ATMSign", V(2.2, 0.8, 0.2), c(4, 6, -1.45), k.theme.primary, nil, true)
		D.text(sign, Enum.NormalId.Back, "ATM", WHITE, 30)
		D.plant(m, c(-4.4, 0, -2.4).Position, 0.6)
		return { { x = -2.2, z = 0.6, yaw = PI }, { x = 0.6, z = 0.6, yaw = PI }, { x = 4, z = -0.4, yaw = 0, stand = true, busy = true } }
	end,
	extras = function(k: any)
		local m = k.decor
		-- Giant vault door on the right wall.
		-- (Kept between the back corner and the wall sconce at z -4.)
		rod(m, "VaultFrame", 1, 9.6, k.at(39.2, 7.5, -9.6), Color3.fromRGB(90, 95, 105), METAL, true)
		rod(m, "VaultDoor", 1.2, 8.2, k.at(38.9, 7.5, -9.6), GOLD, Enum.Material.Foil, true)
		for j = 0, 2 do
			box(m, "VaultSpoke", V(0.4, 5.6, 0.6), k.at(38.1, 7.5, -9.6) * CFrame.Angles(j * math.pi / 3, 0, 0), Color3.fromRGB(200, 160, 60), METAL, true)
		end
		rod(m, "VaultHub", 0.8, 2, k.at(38, 7.5, -9.6), Color3.fromRGB(200, 160, 60), METAL, true)
		-- Marble columns along both walls.
		for _, side in { -1, 1 } do
			for _, z in { 0, 10, 20 } do
				cyl(m, "Column", 21, 2.4, k.at(side * 37.6, 10.5, z), WHITE, MARBLE)
				box(m, "ColumnCap", V(3.2, 1, 3.2), k.at(side * 37.6, 20.5, z), WHITE, MARBLE)
				box(m, "ColumnBase", V(3.2, 1, 3.2), k.at(side * 37.6, 0.5, z), WHITE, MARBLE)
			end
		end
		-- Gold bars on a cart, back-left; rope barrier, back-right.
		box(m, "GoldCart", V(5, 2.4, 3), corner(k, -1, 0, 1.2, 0), DARK, METAL)
		for j = 0, 5 do
			box(m, "GoldBar", V(1.4, 0.6, 0.8), corner(k, -1, -1.6 + (j % 3) * 1.6, 2.7 + math.floor(j / 3) * 0.6, (j % 2) * 0.9 - 0.45), GOLD, Enum.Material.Foil, true)
		end
		for j = 0, 2 do
			cyl(m, "Stanchion", 3.4, 0.5, corner(k, 1, -4 + j * 4, 1.7, 0), GOLD, Enum.Material.Foil)
			if j < 2 then
				rod(m, "Rope", 4, 0.3, corner(k, 1, -2 + j * 4, 2.8, 0), Color3.fromRGB(150, 20, 40), FABRIC, true)
			end
		end
	end,
}

-- Fallback for any business without its own kit.
local DEFAULT = Kits.Pizza

function Kits.get(id: string): any
	return Kits[id] or DEFAULT
end

return Kits
