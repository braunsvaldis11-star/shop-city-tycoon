--!strict
-- CityLayout: the street plan, defined in ONE place.
-- The edit-time CityBuilder generates the city from it, the client traffic system drives
-- along its roads and the map UI draws it, so they can never disagree.
-- The tables below are written in "plan units" (roads drawn 24 wide) and multiplied by
-- SCALE when the module loads, so the whole city grows or shrinks from ONE number.
-- Roads keep their own width (ROAD_HALF) and road-facing block edges are re-fitted to it.
-- After loading, every coordinate in this module is in world studs on the XZ plane.
-- Container: ReplicatedStorage.Shared

local CityLayout = {}

CityLayout.SCALE = 1
CityLayout.ROAD_HALF = 12 -- roads are 24 studs wide in the world
CityLayout.COAST_X = -494 -- harbor quay edge; open sea lies west of it
CityLayout.BOUNDS = { minX = -620, maxX = 1020, minZ = -620, maxZ = 620 }
local PLAN_ROAD_HALF = 12 -- road half-width the plan numbers were drawn with

-- Road centre lines (axis aligned): { x1, z1, x2, z2 }
-- ONE connected city: a street grid with no walls. Streets run along the old district
-- borders too (x = ±206, z = ±206, x = 606), so every district flows into the next.
CityLayout.Roads = {
	-- North-south avenues, coast to the eastern edge
	{ -470, -606, -470, 606 }, { -400, -606, -400, 606 }, { -206, -606, -206, 606 },
	{ -70, -606, -70, 606 }, { 70, -606, 70, 606 }, { 206, -606, 206, 606 },
	{ 400, -606, 400, 606 }, { 606, -606, 606, 606 }, { 800, -606, 800, 606 },
	-- East-west streets (Main Street is z = 70)
	{ -470, -400, 1006, -400 }, { -470, -206, 1006, -206 }, { -470, -70, 206, -70 },
	{ -470, 70, 1006, 70 }, { -470, 206, 1006, 206 }, { -470, 400, 1006, 400 },
}

-- City blocks: { minX, maxX, minZ, maxZ, kind, fillStyle? }
-- kind decides the centrepiece (business lot, park, plaza...); fillStyle lines every
-- road-facing edge of the block with buildings of that style.
CityLayout.Blocks = {
	-- Old Town (Main Street runs along z = 70)
	{ -194, -82, 82, 194, "lot", "shops" }, { -58, 58, 82, 194, "lot", "shops" }, { 82, 194, 82, 194, "lot", "shops" },
	{ -194, -82, -58, 58, "lot", "shops" }, { -58, 58, -58, 58, "park" }, { 82, 194, -58, 58, "lot", "shops" },
	{ -194, -82, -194, -82, "parking", "shops" }, { -58, 58, -194, -82, "lot", "shops" }, { 82, 194, -194, -82, "playground", "shops" },
	-- Maple Hills
	{ -194, -82, 218, 388, "lot", "houses" }, { -58, 58, 218, 388, "maplepark" }, { 82, 194, 218, 388, "lot", "houses" },
	{ -194, -82, 412, 600, "fill", "houses" }, { -58, 58, 412, 600, "field" }, { 82, 194, 412, 600, "fill", "houses" },
	-- Downtown
	{ -194, -82, -388, -218, "lot", "towers" }, { -58, 58, -388, -218, "lot", "towers" }, { 82, 194, -388, -218, "lot", "towers" },
	{ -194, -82, -600, -412, "fill", "towers" }, { -58, 58, -600, -412, "plaza", "towers" }, { 82, 194, -600, -412, "fill", "towers" },
	-- Harbor Bay
	{ -388, -218, 82, 194, "lot", "harbor" }, { -388, -218, -58, 58, "market", "harbor" }, { -388, -218, -194, -82, "lot", "harbor" },
	{ -458, -412, 82, 194, "containers" }, { -458, -412, -58, 58, "fill", "harbor" }, { -458, -412, -194, -82, "containers" },
	-- The quay runs the whole waterfront
	{ -494, -482, -606, 606, "quay" },
	-- Seaside Village (north of the harbor)
	{ -388, -218, 218, 388, "lot", "houses" }, { -388, -218, 412, 600, "lot", "houses" },
	{ -458, -412, 218, 388, "fill", "shops" }, { -458, -412, 412, 600, "fill", "shops" },
	-- The Dockyards (south of the harbor)
	{ -388, -218, -388, -218, "lot", "harbor" }, { -388, -218, -600, -412, "parking", "harbor" },
	{ -458, -412, -388, -218, "containers" }, { -458, -412, -600, -412, "fill", "harbor" },
	-- Uptown Heights
	{ 218, 388, 82, 194, "lot", "luxury" }, { 218, 388, -194, 58, "lot", "luxury" },
	{ 412, 594, 82, 194, "fill", "luxury" }, { 412, 594, -194, 58, "pond", "luxury" },
	-- Sunset Hills
	{ 218, 388, 218, 388, "lot", "luxury" }, { 412, 594, 218, 388, "lot", "luxury" },
	{ 218, 388, 412, 600, "fill", "luxury" }, { 412, 594, 412, 600, "playground", "houses" },
	-- Financial District
	{ 218, 388, -388, -218, "lot", "glass" }, { 412, 594, -388, -218, "fill", "glass" },
	{ 218, 388, -600, -412, "exchange", "glass" }, { 412, 594, -600, -412, "fill", "glass" },
	-- Arts Quarter
	{ 618, 788, 218, 388, "lot", "shops" }, { 812, 994, 218, 388, "lot", "shops" },
	{ 618, 788, 412, 600, "plaza", "shops" }, { 812, 994, 412, 600, "fill", "houses" },
	-- Funland
	{ 618, 788, 82, 194, "lot", "shops" }, { 618, 788, -194, 58, "lot", "shops" },
	{ 812, 994, 82, 194, "fill", "shops" }, { 812, 994, -194, 58, "playground", "shops" },
	-- Business Park
	{ 618, 788, -388, -218, "lot", "glass" }, { 812, 994, -388, -218, "fill", "glass" },
	{ 618, 788, -600, -412, "fill", "towers" }, { 812, 994, -600, -412, "parking", "towers" },
}

-- Welcome arches and hedge walls between districts are gone: the city is one open
-- grid, and districts are just neighbourhoods on the map. (Kept as empty lists so the
-- builder and the pedestrian paths need no special cases.)
CityLayout.Gates = {} :: { { district: string, from: string, x: number, z: number, alongX: boolean } }
CityLayout.Boundaries = {} :: { { number } }

----- Scale the plan into world studs -----
do
	local S = CityLayout.SCALE
	local planRoads = CityLayout.Roads
	-- Is there a road centre line at `line` (plan units) running beside the span lo..hi?
	local function roadAt(axis: string, line: number, lo: number, hi: number): boolean
		for _, road in planRoads do
			if axis == "x" and road[1] == road[3] and road[1] == line
				and math.min(road[2], road[4]) < hi and math.max(road[2], road[4]) > lo then
				return true
			elseif axis == "z" and road[2] == road[4] and road[2] == line
				and math.min(road[1], road[3]) < hi and math.max(road[1], road[3]) > lo then
				return true
			end
		end
		return false
	end
	-- side = -1 for a block's min edge, +1 for its max edge.
	local function fit(axis: string, edge: number, side: number, lo: number, hi: number): number
		local line = edge + side * PLAN_ROAD_HALF
		if roadAt(axis, line, lo, hi) then
			return line * S - side * CityLayout.ROAD_HALF
		end
		return edge * S
	end
	for _, block in CityLayout.Blocks do
		local minX, maxX, minZ, maxZ = block[1], block[2], block[3], block[4]
		block[1] = fit("x", minX, -1, minZ, maxZ)
		block[2] = fit("x", maxX, 1, minZ, maxZ)
		block[3] = fit("z", minZ, -1, minX, maxX)
		block[4] = fit("z", maxZ, 1, minX, maxX)
	end
	for _, list in { planRoads, CityLayout.Boundaries } do
		for _, line in list do
			for i = 1, 4 do
				line[i] *= S
			end
		end
	end
	for _, gate in CityLayout.Gates do
		gate.x *= S
		gate.z *= S
	end
	CityLayout.COAST_X *= S
	local bounds = CityLayout.BOUNDS
	bounds.minX *= S
	bounds.maxX *= S
	bounds.minZ *= S
	bounds.maxZ *= S
end

function CityLayout.onRoad(x: number, z: number, margin: number?): boolean
	local half = CityLayout.ROAD_HALF + (margin or 0)
	for _, road in CityLayout.Roads do
		if x >= math.min(road[1], road[3]) - half and x <= math.max(road[1], road[3]) + half
			and z >= math.min(road[2], road[4]) - half and z <= math.max(road[2], road[4]) + half then
			return true
		end
	end
	return false
end

function CityLayout.roadLength(road: { number }): number
	return math.abs(road[3] - road[1]) + math.abs(road[4] - road[2])
end

return CityLayout
