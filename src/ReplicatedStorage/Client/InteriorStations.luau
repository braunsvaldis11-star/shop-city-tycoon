--!strict
-- InteriorStations (client only): the production stations along the back wall of an
-- interior, one style per kind of business, plus prep counters and the small product
-- props that staff and customers carry.
-- Station frame: origin on the floor at the station's centre, local -Z faces the worker.
-- Footprint about x -4.5..4.5, z -3..3.8. Equipment tier (0..4) sets tint and material.
-- Each builder returns its "glow" part (the bit that lights up).
-- Container: ReplicatedStorage.Client

local D = require(script.Parent.InteriorDraw)

local InteriorStations = {}

local V = Vector3.new
local box, glow, glass, cyl, rod, ball, wedge = D.box, D.glow, D.glass, D.cyl, D.rod, D.ball, D.wedge
local WHITE, WOOD, DARK, STEEL, GOLD = D.WHITE, D.WOOD, D.DARK, D.STEEL, D.GOLD

type Builder = (m: Model, c: (number, number, number) -> CFrame, tint: Color3, mat: Enum.Material, tier: number, theme: any) -> BasePart

local function fire(part: BasePart)
	local f = Instance.new("Fire")
	f.Size = 2.5
	f.Heat = 2
	f.Color = Color3.fromRGB(255, 150, 50)
	f.SecondaryColor = Color3.fromRGB(255, 220, 90)
	f.Parent = part
end

-- Neon trim around the base on Turbo and Golden equipment.
local function trim(m: Model, c: (number, number, number) -> CFrame, tier: number, w: number, d: number)
	if tier >= 3 then
		glow(m, "Trim", V(w + 0.4, 0.4, d + 0.4), c(0, 0.2, 0), if tier >= 4 then GOLD else Color3.fromRGB(80, 230, 255))
	end
end

local B: { [string]: Builder } = {}

B.pizzaOven = function(m, c, tint, mat, tier)
	box(m, "Body", V(7, 6, 5), c(0, 3, 0.5), tint, mat)
	ball(m, "Dome", 7, c(0, 6, 0.5), tint, mat)
	cyl(m, "Chimney", 6, 1.4, c(0, 10, 1.3), DARK)
	local g = glow(m, "Opening", V(4, 2.4, 0.3), c(0, 3.2, -2.05), Color3.fromRGB(255, 140, 40))
	fire(g)
	box(m, "Peel", V(0.3, 0.3, 4), c(3.2, 2.2, -2.6) * CFrame.Angles(math.rad(-30), 0, 0), WOOD, nil, true)
	cyl(m, "Logs", 1.2, 1.6, c(-3.9, 0.6, -1.6), Color3.fromRGB(120, 80, 50))
	trim(m, c, tier, 7, 5)
	return g
end

B.breadOven = function(m, c, tint, mat, tier)
	box(m, "Body", V(8, 7.5, 4.6), c(0, 3.75, 0.6), tint, mat)
	box(m, "Top", V(8.4, 0.5, 5), c(0, 7.75, 0.6), STEEL, D.METAL)
	local g
	for i, y in { 1.8, 3.9, 6 } do
		local door = glow(m, "Deck", V(6.4, 1.2, 0.2), c(0, y, -1.75), Color3.fromRGB(255, 160, 60))
		box(m, "Handle", V(6, 0.25, 0.25), c(0, y + 0.85, -2), STEEL, D.METAL, true)
		if i == 2 then
			g = door
		end
	end
	cyl(m, "Flue", 3, 1.2, c(2.6, 9.5, 1.6), STEEL, D.METAL)
	-- Basket of baguettes on top.
	box(m, "Basket", V(3, 1, 1.8), c(-1.8, 8.5, 0.6), Color3.fromRGB(200, 150, 90), Enum.Material.Fabric)
	for i = 0, 2 do
		rod(m, "Baguette", 3.6, 0.6, c(-1.8, 9.2 + i * 0.15, -0.1 + i * 0.6) * CFrame.Angles(0, 0, math.rad(25)), Color3.fromRGB(225, 170, 95), nil, true)
	end
	trim(m, c, tier, 8, 4.6)
	return g :: BasePart
end

B.espresso = function(m, c, tint, mat, tier)
	box(m, "Base", V(7, 4, 4), c(0, 2, 0), WOOD, D.PLANKS)
	box(m, "Machine", V(5, 3.5, 3), c(0, 5.75, 0.2), tint, mat)
	local g = glow(m, "Lights", V(4, 0.5, 0.2), c(0, 6.8, -1.4), Color3.fromRGB(255, 220, 120))
	for _, x in { -1.3, 1.3 } do
		cyl(m, "Cup", 0.8, 0.8, c(x, 4.4, -1.4), WHITE)
	end
	ball(m, "Grinder", 1.6, c(-2.8, 5, 0.8), DARK)
	cyl(m, "Hopper", 1.6, 1.2, c(-2.8, 6.4, 0.8), Color3.fromRGB(110, 70, 45))
	trim(m, c, tier, 7, 4)
	return g
end

B.softServe = function(m, c, tint, mat, tier, theme)
	box(m, "Cabinet", V(8, 3.6, 4), c(0, 1.8, 0), tint, mat)
	box(m, "Machine", V(4.4, 4.2, 3), c(-0.8, 5.7, 0.4), WHITE)
	box(m, "Hopper", V(4, 1, 2.6), c(-0.8, 8.3, 0.4), STEEL, D.METAL)
	for _, x in { -2, 0.4 } do
		cyl(m, "Nozzle", 1, 0.7, c(x, 4.4, -1.4), STEEL, D.METAL)
		cyl(m, "Swirl", 0.8, 0.9, c(x, 3.95, -1.4), if x < 0 then Color3.fromRGB(255, 240, 215) else Color3.fromRGB(255, 170, 205), nil, true)
	end
	cyl(m, "Cones", 2.4, 0.9, c(2.9, 4.8, -0.6), Color3.fromRGB(225, 165, 90))
	local g = glow(m, "Neon", V(7.6, 0.4, 0.2), c(0, 3.3, -2.05), theme.accent)
	trim(m, c, tier, 8, 4)
	return g
end

B.grill = function(m, c, tint, mat, tier)
	box(m, "Base", V(8, 3.6, 4), c(0, 1.8, 0), STEEL, D.METAL)
	local g = glow(m, "Plate", V(7.4, 0.3, 3.4), c(0, 3.75, 0), Color3.fromRGB(255, 120, 40))
	for i = 1, 3 do
		box(m, "Patty", V(1.4, 0.4, 1.4), c(-3 + i * 1.6, 4.05, 0), Color3.fromRGB(110, 60, 35), nil, true)
	end
	box(m, "Hood", V(8.4, 1.4, 4.4), c(0, 9.5, 0.4), tint, mat)
	box(m, "Duct", V(2, 3, 2), c(0, 11.5, 0.8), STEEL)
	D.smoke(g)
	trim(m, c, tier, 8, 4)
	return g
end

B.seafoodGrill = function(m, c, tint, mat, tier)
	box(m, "Base", V(8, 3.4, 4), c(0, 1.7, 0), Color3.fromRGB(70, 70, 78), D.METAL)
	local g = glow(m, "Coals", V(5.2, 0.3, 3.2), c(-1.2, 3.55, 0), Color3.fromRGB(255, 90, 30))
	for i = 0, 2 do
		rod(m, "Skewer", 5.4, 0.15, c(-1.2, 3.9, -1 + i), STEEL, nil, true)
		for j = 0, 2 do
			ball(m, "Shrimp", 0.7, c(-3 + j * 1.6, 3.95, -1 + i), Color3.fromRGB(255, 140, 110), nil, true)
		end
	end
	local pot = cyl(m, "LobsterPot", 2.4, 2.4, c(2.7, 4.6, 0.2), Color3.fromRGB(60, 60, 70), D.METAL)
	ball(m, "Lobster", 1.2, c(2.7, 6, 0.2), Color3.fromRGB(230, 70, 50), nil, true)
	D.smoke(pot, Color3.fromRGB(245, 245, 245), 0.12)
	box(m, "Hood", V(8.4, 1.2, 4.4), c(0, 9.4, 0.4), tint, mat)
	trim(m, c, tier, 8, 4)
	return g
end

B.sushiPrep = function(m, c, tint, mat, tier)
	box(m, "Counter", V(8.4, 3.4, 4), c(0, 1.7, 0), Color3.fromRGB(215, 180, 130), D.PLANKS)
	box(m, "Board", V(4, 0.3, 2.4), c(-1, 3.55, -0.2), Color3.fromRGB(240, 220, 180), D.PLANKS)
	box(m, "Salmon", V(2, 0.6, 1), c(-2, 3.95, -0.4), Color3.fromRGB(255, 140, 90), nil, true)
	box(m, "Tuna", V(1.6, 0.6, 1), c(0, 3.95, -0.4), Color3.fromRGB(200, 40, 60), nil, true)
	box(m, "Mat", V(2, 0.1, 2), c(2.6, 3.45, -0.3), Color3.fromRGB(170, 190, 100), nil, true)
	cyl(m, "RiceTub", 1.4, 2, c(2.6, 4.2, 1.2), tint, mat)
	cyl(m, "Rice", 0.2, 1.7, c(2.6, 4.95, 1.2), WHITE, nil, true)
	box(m, "Knife", V(2, 0.1, 0.3), c(-1, 3.75, -1.1), STEEL, D.METAL, true)
	box(m, "Cord", V(0.1, 3, 0.1), c(0, 9.5, 0.5), DARK, nil, true)
	local g = ball(m, "Lantern", 1.8, c(0, 7.4, 0.5), Color3.fromRGB(240, 60, 50), D.NEON, true)
	D.light(g, Color3.fromRGB(255, 140, 110), 10, 0.8)
	trim(m, c, tier, 8.4, 4)
	return g
end

B.sewing = function(m, c, tint, mat, tier, theme)
	box(m, "Table", V(8, 0.4, 4), c(0, 3.2, 0), WOOD, D.PLANKS)
	for _, x in { -3.6, 3.6 } do
		box(m, "Leg", V(0.4, 3, 3.4), c(x, 1.5, 0), DARK)
	end
	box(m, "Machine", V(3, 1.4, 1.2), c(-1, 4.1, 0), tint, mat)
	box(m, "Arm", V(0.9, 1.6, 1.2), c(0.1, 5.4, 0), tint, mat)
	box(m, "Head", V(2.4, 0.8, 1.2), c(-0.6, 6.2, 0), tint, mat)
	box(m, "Needle", V(0.1, 0.8, 0.1), c(-1.5, 5.4, 0), STEEL, nil, true)
	box(m, "Fabric", V(3, 0.1, 2.4), c(-1.2, 3.45, -0.6), theme.primary, Enum.Material.Fabric, true)
	for i, col in { theme.accent, D.YELLOW, D.BLUE } do
		rod(m, "Roll", 3, 0.9, c(2.4, 3.85, -1.4 + i * 0.95), col, Enum.Material.Fabric)
	end
	box(m, "LampArm", V(0.2, 3, 0.2), c(-3.4, 4.9, 1.4), DARK, nil, true)
	local g = glow(m, "Lamp", V(1.2, 0.5, 1.2), c(-3, 6.4, 1), D.WARM)
	trim(m, c, tier, 8, 4)
	return g
end

B.stockShelf = function(m, c, tint, mat, tier)
	box(m, "Back", V(8.6, 9, 0.4), c(0, 4.5, 1.9), tint, mat)
	for _, x in { -4.1, 4.1 } do
		box(m, "Upright", V(0.4, 9, 3.4), c(x, 4.5, 0.4), tint, mat)
	end
	local cardboard = { Color3.fromRGB(200, 155, 100), Color3.fromRGB(180, 135, 85), Color3.fromRGB(215, 175, 120) }
	for row, y in { 0.3, 3.2, 6.1 } do
		box(m, "Shelf", V(8, 0.3, 3.2), c(0, y, 0.4), STEEL, D.METAL)
		for i = 0, 2 do
			local h = 1.6 + ((i + row) % 3) * 0.5
			box(m, "Carton", V(2.2, h, 2.2), c(-2.7 + i * 2.7, y + 0.15 + h / 2, 0.5), cardboard[(i + row) % 3 + 1])
		end
	end
	local g = glow(m, "Label", V(8, 0.35, 0.1), c(0, 0.3, -1.25), Color3.fromRGB(255, 210, 80))
	trim(m, c, tier, 8.6, 3.4)
	return g
end

B.grooming = function(m, c, tint, mat, tier, theme)
	box(m, "Table", V(5, 0.5, 3.4), c(-1.4, 3, 0), tint, mat)
	box(m, "Stand", V(1, 2.8, 1), c(-1.4, 1.4, 0), STEEL, D.METAL)
	box(m, "Mat", V(4.4, 0.15, 2.8), c(-1.4, 3.3, 0), Color3.fromRGB(60, 150, 200), nil, true)
	box(m, "Post", V(0.3, 4, 0.3), c(-3.6, 5.3, 1.4), STEEL, D.METAL, true)
	box(m, "PostArm", V(2.4, 0.3, 0.3), c(-2.5, 7.2, 1.4), STEEL, D.METAL, true)
	-- Little dog getting a trim.
	local fur = Color3.fromRGB(235, 205, 150)
	box(m, "DogBody", V(2, 1.1, 1), c(-1.2, 4, 0), fur, nil, true)
	box(m, "DogHead", V(0.9, 0.9, 0.9), c(-2.4, 4.6, 0), fur, nil, true)
	box(m, "DogEar", V(0.3, 0.6, 0.5), c(-2.4, 5.2, 0), Color3.fromRGB(180, 130, 80), nil, true)
	for _, x in { -1.9, -0.5 } do
		box(m, "DogLeg", V(0.3, 0.6, 0.3), c(x, 3.4, 0), fur, nil, true)
	end
	-- Bath tub with bubbles.
	box(m, "Tub", V(3, 2.6, 3), c(2.8, 1.3, 0.4), WHITE)
	local water = box(m, "Water", V(2.6, 0.2, 2.6), c(2.8, 2.55, 0.4), Color3.fromRGB(150, 220, 255), nil, true)
	D.bubbles(water, 4)
	local g = glow(m, "Light", V(0.8, 0.8, 0.8), c(2.8, 6, 1.6), theme.accent)
	trim(m, c, tier, 8, 3.4)
	return g
end

B.repairBench = function(m, c, tint, mat, tier, theme)
	box(m, "Bench", V(8, 0.5, 3.6), c(0, 3.2, 0.2), tint, mat)
	box(m, "Cabinet", V(8, 3, 3.4), c(0, 1.5, 0.3), DARK)
	box(m, "Laptop", V(2.6, 0.2, 1.8), c(-2, 3.55, -0.3), Color3.fromRGB(60, 60, 70), nil, true)
	local g = glow(m, "Screen", V(2.6, 1.7, 0.1), c(-2, 4.4, 0.6) * CFrame.Angles(math.rad(-12), 0, 0), theme.primary:Lerp(WHITE, 0.3))
	box(m, "Phone", V(0.8, 0.1, 1.5), c(0.6, 3.5, -0.4), DARK, nil, true)
	box(m, "Parts", V(1.4, 0.3, 1), c(1.8, 3.6, -0.6), D.GREEN, nil, true)
	box(m, "LampArm", V(0.2, 3, 0.2), c(3, 5, 1.2), STEEL, nil, true)
	cyl(m, "Magnifier", 0.2, 1.6, c(2.2, 6.4, 0.4), D.GLASS, D.GLASSMAT, true)
	box(m, "Pegboard", V(8, 3.4, 0.3), c(0, 6.6, 1.95), Color3.fromRGB(190, 160, 120))
	for i = 0, 4 do
		box(m, "Tool", V(0.3, 1.6, 0.2), c(-3 + i * 1.5, 6.6, 1.75), D.BRIGHT[i + 1], nil, true)
	end
	trim(m, c, tier, 8, 3.6)
	return g
end

B.bookCart = function(m, c, tint, mat, tier, theme)
	box(m, "Table", V(7, 0.5, 3.6), c(-0.6, 3.2, 0.3), tint, mat)
	for _, x in { -3.7, 2.5 } do
		box(m, "Leg", V(0.5, 3, 3), c(x, 1.5, 0.3), DARK)
	end
	local covers = { theme.primary, theme.accent, D.RED, D.GREEN, D.BLUE, D.YELLOW }
	for s = 0, 2 do
		for i = 0, 3 do
			box(m, "Book", V(1.8, 0.45, 2.4), c(-3 + s * 2.3, 3.7 + i * 0.47, 0.3) * CFrame.Angles(0, math.rad((i % 2) * 8 - 4), 0), covers[(s + i) % #covers + 1], nil, true)
		end
	end
	-- Book cart beside the table.
	box(m, "Cart", V(2, 3, 3), c(3.6, 2, 0.3), WOOD, D.PLANKS)
	for i = 0, 4 do
		box(m, "Spine", V(0.35, 1.6, 2.4), c(2.9 + i * 0.35, 4.3, 0.3), covers[i + 1], nil, true)
	end
	local g = glow(m, "Lamp", V(1, 0.6, 1), c(-3, 6, 1.2), D.WARM)
	box(m, "LampPole", V(0.2, 2.2, 0.2), c(-3, 4.6, 1.2), D.GOLD, nil, true)
	trim(m, c, tier, 8, 3.6)
	return g
end

B.shapingBench = function(m, c, tint, mat, tier, theme)
	for _, x in { -2.6, 2.6 } do
		box(m, "Horse", V(0.6, 3, 3), c(x, 1.5, 0.2), tint, mat)
	end
	-- Surfboard lying on the sawhorses (long and rounded).
	box(m, "Board", V(8.4, 0.35, 2.2), c(0, 3.2, 0.2), WHITE)
	cyl(m, "Nose", 0.35, 2.2, c(-4.2, 3.2, 0.2), WHITE, nil, true)
	cyl(m, "Tail", 0.35, 2.2, c(4.2, 3.2, 0.2), WHITE, nil, true)
	box(m, "Stripe", V(8, 0.05, 0.4), c(0, 3.4, 0.2), theme.accent, nil, true)
	local g = glow(m, "Light", V(5, 0.3, 0.3), c(0, 8.4, 1), D.WARM)
	box(m, "Planer", V(1.2, 0.6, 0.8), c(1.6, 3.7, 0.2), D.RED, nil, true)
	for i = 0, 2 do
		box(m, "Wax", V(0.8, 0.6, 0.8), c(-3.4 + i, 0.3, -1.8), D.BRIGHT[i + 2])
	end
	box(m, "Foam", V(2, 1, 1.6), c(3.4, 0.5, -1.5), Color3.fromRGB(240, 240, 220))
	trim(m, c, tier, 8, 3)
	return g
end

B.toyBench = function(m, c, tint, mat, tier, theme)
	box(m, "Bench", V(8, 0.5, 3.6), c(0, 3.2, 0.2), tint, mat)
	box(m, "Base", V(8, 3, 3.4), c(0, 1.5, 0.3), theme.accent:Lerp(WHITE, 0.3))
	for i = 0, 4 do
		box(m, "Block", V(1, 1, 1), c(-3.4 + i * 0.9, 3.95 + (i % 2) * 1, -0.5), D.BRIGHT[i + 1], nil, true)
	end
	box(m, "Gift", V(1.6, 1.4, 1.6), c(1.4, 4.15, 0), D.RED, nil, true)
	box(m, "Ribbon", V(0.3, 1.45, 1.65), c(1.4, 4.15, 0), D.YELLOW, nil, true)
	rod(m, "Paper", 3, 0.8, c(2.4, 3.85, 1.2), D.PINK, nil, true)
	ball(m, "Teddy", 1.4, c(3.3, 4.2, -0.4), Color3.fromRGB(170, 110, 60), nil, true)
	local g = glow(m, "Lamp", V(1.2, 0.5, 1.2), c(-2.6, 6.6, 1.2), D.WARM)
	box(m, "LampArm", V(0.2, 3, 0.2), c(-3, 5, 1.6), DARK, nil, true)
	trim(m, c, tier, 8, 3.6)
	return g
end

B.fishTable = function(m, c, tint, mat, tier)
	box(m, "Table", V(8, 0.4, 3.8), c(0, 3.3, 0.2), STEEL, D.METAL)
	box(m, "Base", V(7.6, 3.1, 3.4), c(0, 1.55, 0.2), tint, mat)
	box(m, "Board", V(3, 0.2, 2), c(-1.6, 3.6, -0.2), WHITE, nil, true)
	D.fish(m, c(-1.6, 3.9, -0.2) * CFrame.Angles(math.pi / 2, 0, 0), Color3.fromRGB(150, 170, 190), 1.6)
	local ice = box(m, "Ice", V(3, 0.5, 3), c(2.3, 3.75, 0.2), Color3.fromRGB(220, 240, 255), Enum.Material.Ice, true)
	for i = 0, 1 do
		D.fish(m, c(2.3, 4.2, -0.4 + i * 1.2) * CFrame.Angles(math.pi / 2, 0, 0), Color3.fromRGB(240, 130, 90), 1.2)
	end
	box(m, "Scale", V(1.4, 1, 1.4), c(-3.4, 4, 1.2), WHITE)
	local g = glow(m, "ScaleScreen", V(1, 0.4, 0.1), c(-3.4, 4.1, 0.45), Color3.fromRGB(120, 230, 160))
	box(m, "Cleaver", V(1.6, 0.1, 0.8), c(0.2, 3.55, -1.2), STEEL, D.METAL, true)
	local _ = ice
	trim(m, c, tier, 8, 3.8)
	return g
end

B.jewelerBench = function(m, c, tint, mat, tier)
	box(m, "Bench", V(7.6, 0.5, 3.6), c(0, 3.2, 0.2), Color3.fromRGB(120, 80, 55), D.PLANKS)
	box(m, "Drawers", V(7.6, 3, 3.4), c(0, 1.5, 0.3), tint, mat)
	for i = 0, 2 do
		box(m, "Knob", V(0.6, 0.3, 0.2), c(-2.5 + i * 2.5, 2, -1.45), GOLD, nil, true)
	end
	box(m, "Tray", V(2.6, 0.3, 1.6), c(-1.6, 3.6, -0.3), Color3.fromRGB(40, 30, 60), Enum.Material.Fabric, true)
	for i = 0, 3 do
		ball(m, "Gem", 0.5, c(-2.5 + i * 0.6, 3.95, -0.3), ({ Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 90, 140), Color3.fromRGB(110, 230, 130), GOLD })[i + 1], D.NEON, true)
	end
	box(m, "LampArm", V(0.2, 3.2, 0.2), c(2.6, 5, 1.2), GOLD, nil, true)
	local g = glow(m, "Lamp", V(1.8, 0.4, 0.9), c(2, 6.6, 0.6), Color3.fromRGB(110, 255, 160))
	cyl(m, "Loupe", 0.4, 0.8, c(0.8, 3.65, -0.6), DARK, nil, true)
	trim(m, c, tier, 7.6, 3.6)
	return g
end

B.juiceBar = function(m, c, tint, mat, tier)
	box(m, "Counter", V(8, 3.6, 4), c(0, 1.8, 0), tint, mat)
	box(m, "Top", V(8.4, 0.3, 4.4), c(0, 3.75, 0), WHITE, D.MARBLE)
	local colors = { Color3.fromRGB(120, 255, 120), Color3.fromRGB(255, 110, 190), Color3.fromRGB(255, 200, 70) }
	local g
	for i, x in { -2.6, 0, 2.6 } do
		box(m, "BlenderBase", V(1.4, 1, 1.4), c(x, 4.4, 0.4), DARK)
		local jug = glow(m, "Jug", V(1.1, 2, 1.1), c(x, 5.9, 0.4), colors[i])
		jug.Transparency = 0.25
		if i == 2 then
			g = jug
		end
	end
	for i = 0, 3 do
		ball(m, "Fruit", 0.8, c(-3 + i * 0.7, 4.3, -1.4), ({ D.ORANGE, D.YELLOW, D.RED, D.GREEN })[i + 1], nil, true)
	end
	trim(m, c, tier, 8, 4)
	return g :: BasePart
end

B.popcorn = function(m, c, tint, mat, tier)
	box(m, "Cart", V(6, 3.4, 3.6), c(0, 2.1, 0.2), Color3.fromRGB(210, 40, 45))
	for _, x in { -2.6, 2.6 } do
		rod(m, "Wheel", 0.4, 1.6, c(x, 0.8, -1.7), DARK)
	end
	for _, x in { -2.8, 2.8 } do
		for _, z in { -1.6, 1.6 } do
			box(m, "Post", V(0.2, 4.6, 0.2), c(x, 6.1, z + 0.2), tint, mat, true)
		end
	end
	local g = glow(m, "Popcorn", V(5.4, 1.6, 3), c(0, 4.6, 0.2), Color3.fromRGB(255, 235, 120))
	glass(m, "Glass", V(5.8, 4.6, 3.4), c(0, 6.1, 0.2), 0.7)
	box(m, "Roof", V(6.4, 0.5, 4), c(0, 8.6, 0.2), Color3.fromRGB(210, 40, 45))
	cyl(m, "Kettle", 1.2, 1.4, c(0, 7.6, 0.2), STEEL, D.METAL, true)
	local sign = box(m, "Sign", V(5, 1.4, 0.2), c(0, 9.6, 0.2), Color3.fromRGB(255, 220, 60), nil, true)
	D.text(sign, Enum.NormalId.Front, "POPCORN", Color3.fromRGB(210, 40, 45), 20)
	for _, x in { -1.6, 0, 1.6 } do
		box(m, "Bucket", V(1, 1.4, 1), c(x, 4.5, -1.95), WHITE, nil, true)
	end
	trim(m, c, tier, 6, 3.6)
	return g
end

B.tank = function(m, c, tint, mat, tier)
	box(m, "Cabinet", V(8, 2.4, 4), c(0, 1.2, 0), tint, mat)
	local g = glass(m, "Water", V(7.6, 5, 3.6), c(0, 4.9, 0), 0.35, Color3.fromRGB(60, 170, 255))
	box(m, "Sand", V(7.4, 0.5, 3.4), c(0, 2.65, 0), Color3.fromRGB(240, 220, 160), nil, true)
	local fishColours = { Color3.fromRGB(255, 140, 40), Color3.fromRGB(255, 230, 60), Color3.fromRGB(255, 90, 120) }
	for i = 1, 3 do
		D.fish(m, c(-3 + i * 1.6, 3.6 + (i % 2) * 1.6, -0.4), fishColours[i])
	end
	box(m, "Coral", V(0.8, 1.6, 0.8), c(2.6, 3.6, 0.6), Color3.fromRGB(255, 120, 150), nil, true)
	box(m, "Lid", V(8, 0.4, 4), c(0, 7.6, 0), DARK)
	D.bubbles(g, 5)
	trim(m, c, tier, 8, 4)
	return g
end

B.tokenMachine = function(m, c, tint, mat, tier, theme)
	box(m, "Cabinet", V(4, 8.4, 3.4), c(-1.6, 4.2, 0.4), tint, mat)
	local g = glow(m, "Screen", V(3.2, 2.4, 0.1), c(-1.6, 6.6, -1.35), theme.accent)
	glow(m, "Slot", V(1.4, 0.5, 0.1), c(-1.6, 4.2, -1.35), D.YELLOW)
	box(m, "Tray", V(2, 0.6, 0.8), c(-1.6, 2.6, -1.6), STEEL, D.METAL, true)
	for i = 0, 2 do
		cyl(m, "Coins", 0.5, 0.9, c(-2.2 + i * 0.6, 3.05, -1.6), GOLD, Enum.Material.Foil, true)
	end
	local top = glow(m, "Topper", V(4.2, 1, 3.6), c(-1.6, 8.9, 0.4), theme.primary)
	local _ = top
	box(m, "Changer", V(3, 5, 2.6), c(2.6, 2.5, 0.6), DARK)
	glow(m, "ChangerLight", V(2.4, 0.6, 0.1), c(2.6, 4.2, -0.75), Color3.fromRGB(120, 255, 160))
	trim(m, c, tier, 8, 3.4)
	return g
end

B.towelWarmer = function(m, c, tint, mat, tier, theme)
	box(m, "Cabinet", V(5, 6.4, 3.4), c(-1.4, 3.2, 0.4), tint, mat)
	glass(m, "Door", V(4.2, 5, 0.2), c(-1.4, 3.6, -1.35), 0.4)
	local g = glow(m, "Heat", V(4.2, 0.3, 0.2), c(-1.4, 0.9, -1.35), Color3.fromRGB(255, 150, 80))
	for row = 0, 2 do
		for i = 0, 1 do
			rod(m, "Towel", 3, 1.2, c(-2.4 + i * 2, 1.8 + row * 1.6, 0.2) * CFrame.Angles(0, math.pi / 2, 0), if (row + i) % 2 == 0 then WHITE else theme.accent:Lerp(WHITE, 0.5), D.FABRIC, true)
		end
	end
	box(m, "Shelf", V(3, 3, 3), c(2.6, 1.5, 0.4), Color3.fromRGB(200, 175, 130), D.PLANKS)
	for i = 0, 2 do
		cyl(m, "Oil", 1, 0.5, c(1.8 + i * 0.8, 3.5, 0), ({ Color3.fromRGB(160, 220, 140), Color3.fromRGB(240, 180, 220), Color3.fromRGB(250, 220, 120) })[i + 1], D.GLASSMAT, true)
	end
	D.smoke(g, WHITE, 0.05)
	trim(m, c, tier, 8, 3.4)
	return g
end

B.washer = function(m, c, tint, mat, tier)
	local g
	for _, x in { -2.1, 2.1 } do
		for row, y in { 2, 6 } do
			box(m, "Washer", V(3.8, 3.8, 3.6), c(x, y, 0.5), if row == 1 then tint else WHITE, if row == 1 then mat else nil)
			box(m, "Rim", V(2.8, 2.8, 0.2), c(x, y, -1.35), STEEL, D.METAL, true)
			local window = rod(m, "Window", 0.1, 2.2, c(x, y, -1.45) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(110, 190, 255), D.NEON, true)
			if not g then
				g = window
			end
		end
	end
	box(m, "Basket", V(2.4, 1.6, 1.8), c(4.6, 0.8, -1.4), Color3.fromRGB(210, 180, 120), D.FABRIC)
	box(m, "Laundry", V(2, 0.6, 1.4), c(4.6, 1.8, -1.4), WHITE, D.FABRIC, true)
	trim(m, c, tier, 8, 3.6)
	return g :: BasePart
end

B.carLift = function(m, c, tint, mat, tier, theme)
	for _, x in { -4, 4 } do
		box(m, "Post", V(0.8, 8, 0.8), c(x, 4, 1), tint, mat)
		box(m, "Arm", V(3, 0.4, 0.6), c(x * 0.75, 3, 1), STEEL, D.METAL)
	end
	box(m, "Beam", V(8.8, 0.6, 0.8), c(0, 8.2, 1), tint, mat)
	-- A small car up on the lift (scaled so it fits the bay).
	local car = Instance.new("Model")
	car.Parent = m
	local body = theme.primary
	box(car, "Body", V(5, 1.6, 2.6), c(0, 4, 0.2), body)
	box(car, "Cabin", V(2.8, 1.3, 2.3), c(0.3, 5.4, 0.2), body:Lerp(WHITE, 0.2))
	glass(car, "Windows", V(2.9, 1, 2.4), c(0.3, 5.45, 0.2), 0.3, Color3.fromRGB(150, 200, 235))
	for _, x in { -1.6, 1.6 } do
		for _, z in { -1.3, 1.6 } do
			rod(car, "Wheel", 0.6, 1.4, c(x, 3.2, z) * CFrame.Angles(0, math.pi / 2, 0), DARK)
		end
	end
	for i = 0, 2 do
		rod(m, "Tire", 0.8, 2.2, c(-3.5, 0.4 + i * 0.8, -2) * CFrame.Angles(0, 0, math.pi / 2), DARK)
	end
	box(m, "Toolbox", V(1.6, 2.6, 1.2), c(3.6, 1.3, -1.8), D.RED)
	local g = glow(m, "Warning", V(0.8, 0.8, 0.8), c(4, 8.8, 1), Color3.fromRGB(255, 170, 40))
	trim(m, c, tier, 8.8, 2)
	return g
end

B.cashCounter = function(m, c, tint, mat, tier)
	box(m, "Desk", V(6, 3.4, 3.6), c(-1, 1.7, 0.2), Color3.fromRGB(90, 60, 40), D.PLANKS)
	box(m, "Top", V(6.4, 0.3, 4), c(-1, 3.55, 0.2), Color3.fromRGB(40, 110, 70), Enum.Material.Fabric)
	box(m, "Counter", V(2.4, 1.4, 1.8), c(-2.4, 4.4, 0.4), tint, mat)
	local g = glow(m, "Display", V(1.6, 0.5, 0.1), c(-2.4, 4.6, -0.55), Color3.fromRGB(120, 255, 140))
	for i = 0, 2 do
		box(m, "Cash", V(1.6, 0.6, 0.8), c(0.2, 3.95 + i * 0.6, -0.3), Color3.fromRGB(110, 190, 110), nil, true)
		box(m, "Band", V(0.3, 0.62, 0.82), c(0.2, 3.95 + i * 0.6, -0.3), WHITE, nil, true)
	end
	-- Small safe.
	box(m, "Safe", V(2.6, 3.4, 2.6), c(3.3, 1.7, 0.6), Color3.fromRGB(70, 75, 85), D.METAL)
	cyl(m, "Dial", 0.3, 1.2, c(3.3, 2, -0.75) * CFrame.Angles(math.pi / 2, 0, 0), STEEL, D.METAL, true)
	box(m, "Gold", V(1.6, 0.6, 0.8), c(3.3, 3.7, 0.6), GOLD, Enum.Material.Foil, true)
	trim(m, c, tier, 8, 3.6)
	return g
end

B.serverRack = function(m, c, tint, mat, tier, theme)
	local g
	for _, x in { -2.2, 2.2 } do
		box(m, "Rack", V(4, 9, 3.6), c(x, 4.5, 0.4), Color3.fromRGB(35, 38, 48))
		box(m, "Frame", V(4.2, 9.2, 0.3), c(x, 4.6, -1.45), tint, mat, true)
		for row = 0, 6 do
			local led = glow(m, "Leds", V(3, 0.25, 0.1), c(x, 1.2 + row * 1.15, -1.55), if row % 3 == 0 then theme.accent else Color3.fromRGB(90, 255, 130))
			if not g then
				g = led
			end
		end
	end
	rod(m, "Cables", 4.4, 0.5, c(0, 8.4, -1.3), D.BLUE, nil, true)
	trim(m, c, tier, 8.4, 3.6)
	return g :: BasePart
end

-- Builds one station. `cf` is the station frame (local -Z toward the worker).
function InteriorStations.build(parent: Instance, style: string, cf: CFrame, tier: number, theme: any): BasePart
	local builder = B[style] or B.pizzaOven
	local model = Instance.new("Model")
	model.Name = "Station"
	local function c(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local index = math.clamp(tier, 0, 4) + 1
	local part = builder(model, c, D.TIER_TINTS[index], D.TIER_MATERIALS[index], tier, theme)
	model.Parent = parent
	return part
end

-- Prep counter (Production: prep). `cf`: local -Z faces the counter / customers.
function InteriorStations.prep(parent: Instance, style: string, cf: CFrame, theme: any)
	if style == "kitchen" then
		box(parent, "PrepCounter", V(7, 2.8, 3), cf * CFrame.new(0, 1.4, 0), STEEL, D.METAL)
		box(parent, "CuttingBoard", V(3, 0.3, 2), cf * CFrame.new(0, 2.95, 0), WOOD, nil, true)
		ball(parent, "Tomato", 0.7, cf * CFrame.new(2.2, 3.15, 0.3), D.RED, nil, true)
		return
	end
	local top = if style == "spa" then Color3.fromRGB(215, 190, 150) elseif style == "dark" then DARK else WOOD
	box(parent, "PrepTable", V(7, 0.4, 3), cf * CFrame.new(0, 2.8, 0), top, if style == "dark" then nil else D.PLANKS)
	for _, x in { -3.1, 3.1 } do
		box(parent, "PrepLeg", V(0.5, 2.6, 2.6), cf * CFrame.new(x, 1.3, 0), DARK)
	end
	box(parent, "PrepBox", V(1.8, 1.2, 1.6), cf * CFrame.new(-1.8, 3.6, 0), theme.primary:Lerp(WHITE, 0.25), nil, true)
	box(parent, "PrepItem", V(1.2, 0.8, 1.2), cf * CFrame.new(1.4, 3.4, 0), theme.accent, nil, true)
end

-- Small product prop that staff and customers carry (one part).
function InteriorStations.product(style: string, theme: any): BasePart
	local function p(name: string, size: Vector3, color: Color3, shape: Enum.PartType?, material: Enum.Material?): BasePart
		local part = D.box(nil :: any, name, size, CFrame.new(), color, material, true)
		part.CastShadow = false
		if shape then
			part.Shape = shape
		end
		return part
	end
	if style == "pizza" then
		return p("PizzaBox", V(2.6, 0.5, 2.6), Color3.fromRGB(235, 205, 150))
	elseif style == "cup" then
		return p("Cup", V(1.2, 1.2, 1.2), WHITE, Enum.PartType.Cylinder)
	elseif style == "bottle" then
		return p("Bottle", V(0.9, 1.8, 0.9), Color3.fromRGB(90, 190, 255))
	elseif style == "key" then
		return p("Key", V(1.4, 0.4, 0.6), GOLD)
	elseif style == "box" then
		return p("Box", V(1.8, 1.2, 1.8), theme.primary:Lerp(WHITE, 0.35))
	elseif style == "cone" then
		return p("Cone", V(1, 1, 1), theme.primary, Enum.PartType.Ball)
	elseif style == "book" then
		return p("Book", V(1.6, 2, 0.5), theme.primary)
	elseif style == "teddy" then
		return p("Teddy", V(1.4, 1.4, 1.4), Color3.fromRGB(170, 110, 60), Enum.PartType.Ball)
	elseif style == "ringbox" then
		return p("RingBox", V(0.9, 0.8, 0.9), Color3.fromRGB(140, 30, 60), nil, D.FABRIC)
	elseif style == "popcorn" then
		return p("Popcorn", V(1.2, 1.6, 1.2), Color3.fromRGB(215, 45, 50))
	elseif style == "fish" then
		return p("Fish", V(2.2, 0.7, 0.9), Color3.fromRGB(235, 225, 200))
	elseif style == "towels" then
		return p("Towels", V(1.8, 1, 1.4), WHITE, nil, D.FABRIC)
	end
	return p("Bag", V(1.8, 2, 0.8), theme.primary)
end

return InteriorStations
