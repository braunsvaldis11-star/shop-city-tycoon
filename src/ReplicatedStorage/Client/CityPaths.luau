--!strict
-- CityPaths (client): the sidewalk network that pedestrians walk, built from the shared
-- city layout. Nodes sit on the sidewalks SIDEWALK studs from each road's centre line,
-- edges follow the sidewalks, and roads are crossed at the zebra crossings (stepping
-- down off the kerb and back up). Every business door is spliced into the network, and
-- for each door the next step towards it is precomputed from every node, so a walker can
-- head for a shop with no path-finding at runtime.
-- Container: ReplicatedStorage.Client

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Businesses = require(Shared.Businesses)
local CityLayout = require(Shared.CityLayout)

local CityPaths = {}

local ROAD_HALF = CityLayout.ROAD_HALF
local SIDEWALK = ROAD_HALF + 5 -- walking line: 5 studs in from the kerb
local DEAD_END = 6 * CityLayout.SCALE + 3 -- pedestrians cross this far before a closed road end
local GAP = 6 * CityLayout.SCALE -- half-width of the strip between two districts (blocks stop either side)
local SIDEWALK_Y = 0.8 -- top of the raised sidewalks
local ROAD_Y = 0.2 -- top of the asphalt
local PLAZA_Y = 0.9 -- top of the lawns and plazas in front of the businesses

CityPaths.SIDEWALK = SIDEWALK

export type Edge = { to: number, length: number, road: boolean }
export type Node = { position: Vector3, edges: { Edge } }
export type Door = {
	id: string,
	entry: number, -- sidewalk node in front of the business
	approach: Vector3, -- on the plaza, lined up with the door
	inside: Vector3, -- just through the doorway, where the customer disappears
	next: { [number]: number }, -- node -> next node towards `entry`
	distance: { [number]: number }, -- node -> walking distance to `entry`
}

type Line = { alongX: boolean, fixed: number, from: number, to: number }
type Stop = { t: number, y: number, road: boolean } -- road: the stretch after this stop is asphalt

local nodes: { Node } = {}
local byKey: { [string]: number } = {}
local doors: { [string]: Door } = {}
local built = false

CityPaths.nodes = nodes
CityPaths.doors = doors

local function nodeAt(position: Vector3): number
	local key = string.format("%d,%d", math.round(position.X * 10), math.round(position.Z * 10))
	local existing = byKey[key]
	if existing then
		return existing
	end
	table.insert(nodes, { position = position, edges = {} })
	byKey[key] = #nodes
	return #nodes
end

local function link(a: number, b: number, road: boolean)
	if a == b then
		return
	end
	for _, edge in nodes[a].edges do
		if edge.to == b then
			return
		end
	end
	local pa, pb = nodes[a].position, nodes[b].position
	local length = Vector3.new(pb.X - pa.X, 0, pb.Z - pa.Z).Magnitude
	table.insert(nodes[a].edges, { to = b, length = length, road = road })
	table.insert(nodes[b].edges, { to = a, length = length, road = road })
end

local function unlink(a: number, b: number)
	for _, pair in { { a, b }, { b, a } } do
		local edges = nodes[pair[1]].edges
		for i = #edges, 1, -1 do
			if edges[i].to == pair[2] then
				table.remove(edges, i)
			end
		end
	end
end

-- Straight roads merged into continuous lines (a road that carries on into the next
-- district is one line).
local function buildLines(): { Line }
	local lines: { Line } = {}
	for _, road in CityLayout.Roads do
		local alongX = road[2] == road[4]
		table.insert(lines, {
			alongX = alongX,
			fixed = if alongX then road[2] else road[1],
			from = if alongX then math.min(road[1], road[3]) else math.min(road[2], road[4]),
			to = if alongX then math.max(road[1], road[3]) else math.max(road[2], road[4]),
		})
	end
	local merged = true
	while merged do
		merged = false
		for i = 1, #lines do
			for j = i + 1, #lines do
				local a, b = lines[i], lines[j]
				if a.alongX == b.alongX and math.abs(a.fixed - b.fixed) < 0.5 and a.from <= b.to + 0.5 and b.from <= a.to + 0.5 then
					a.from, a.to = math.min(a.from, b.from), math.max(a.to, b.to)
					table.remove(lines, j)
					merged = true
					break
				end
			end
			if merged then
				break
			end
		end
	end
	return lines
end

-- World position on a line: `t` along it, `offset` across it.
local function at(line: Line, t: number, offset: number, y: number): Vector3
	if line.alongX then
		return Vector3.new(t, y, line.fixed + offset)
	end
	return Vector3.new(line.fixed + offset, y, t)
end

-- Kerb-to-kerb crossing centred on `c`: down off the kerb, across, back up.
local function crossingStops(stops: { Stop }, c: number, keepBefore: boolean, keepAfter: boolean)
	if keepBefore then
		table.insert(stops, { t = c - SIDEWALK, y = SIDEWALK_Y, road = false })
	end
	if keepBefore and keepAfter then
		table.insert(stops, { t = c - ROAD_HALF, y = SIDEWALK_Y, road = false })
		table.insert(stops, { t = c - ROAD_HALF + 1, y = ROAD_Y, road = true })
		table.insert(stops, { t = c + ROAD_HALF - 1, y = ROAD_Y, road = false })
		table.insert(stops, { t = c + ROAD_HALF, y = SIDEWALK_Y, road = false })
	end
	if keepAfter then
		table.insert(stops, { t = c + SIDEWALK, y = SIDEWALK_Y, road = false })
	end
end

-- Crossing a line's own road where it ends (no junction): side -1 to side +1.
local function deadEndCrossing(line: Line, t: number)
	local offsets = {
		{ -SIDEWALK, SIDEWALK_Y }, { -ROAD_HALF, SIDEWALK_Y }, { -ROAD_HALF + 1, ROAD_Y },
		{ ROAD_HALF - 1, ROAD_Y }, { ROAD_HALF, SIDEWALK_Y }, { SIDEWALK, SIDEWALK_Y },
	}
	local previous: number? = nil
	for i, o in offsets do
		local id = nodeAt(at(line, t, o[1], o[2]))
		if previous then
			link(previous, id, i == 4)
		end
		previous = id
	end
end

local function buildSidewalks()
	local lines = buildLines()
	for _, line in lines do
		-- Junctions with every perpendicular line.
		local crossings = {}
		for _, other in lines do
			if other.alongX ~= line.alongX
				and other.fixed >= line.from - 0.5 and other.fixed <= line.to + 0.5
				and line.fixed >= other.from - 0.5 and line.fixed <= other.to + 0.5 then
				table.insert(crossings, {
					t = other.fixed,
					minus = other.from < line.fixed - 0.5, -- the other road reaches side -1
					plus = other.to > line.fixed + 0.5, -- the other road reaches side +1
				})
			end
		end
		local startsAtJunction, endsAtJunction = false, false
		for _, c in crossings do
			if math.abs(c.t - line.from) < 0.5 then
				startsAtJunction = true
			end
			if math.abs(c.t - line.to) < 0.5 then
				endsAtJunction = true
			end
		end
		for _, side in { -1, 1 } do
			local stops: { Stop } = {}
			for _, c in crossings do
				if (side < 0 and c.minus) or (side > 0 and c.plus) then
					crossingStops(stops, c.t, c.t - SIDEWALK > line.from, c.t + SIDEWALK < line.to)
				end
			end
			if not startsAtJunction then
				table.insert(stops, { t = line.from + DEAD_END, y = SIDEWALK_Y, road = false })
			end
			if not endsAtJunction then
				table.insert(stops, { t = line.to - DEAD_END, y = SIDEWALK_Y, road = false })
			end
			-- District borders: the sidewalk steps down onto the strip between the districts
			-- (through the opening in the hedge) and back up.
			for _, border in CityLayout.Boundaries do
				local horizontal = border[2] == border[4]
				if horizontal == not line.alongX then
					local b = if line.alongX then border[1] else border[2]
					local spanFrom = if line.alongX then math.min(border[2], border[4]) else math.min(border[1], border[3])
					local spanTo = if line.alongX then math.max(border[2], border[4]) else math.max(border[1], border[3])
					local cross = line.fixed + side * SIDEWALK
					if b > line.from + GAP and b < line.to - GAP and cross >= spanFrom - 0.5 and cross <= spanTo + 0.5 then
						table.insert(stops, { t = b - GAP, y = SIDEWALK_Y, road = false })
						table.insert(stops, { t = b - GAP + 0.6, y = ROAD_Y, road = false })
						table.insert(stops, { t = b + GAP - 0.6, y = ROAD_Y, road = false })
						table.insert(stops, { t = b + GAP, y = SIDEWALK_Y, road = false })
					end
				end
			end
			table.sort(stops, function(a, b)
				return a.t < b.t
			end)
			local previous: number? = nil
			local previousRoad = false
			for _, stop in stops do
				local id = nodeAt(at(line, stop.t, side * SIDEWALK, stop.y))
				if previous and previous ~= id then
					link(previous, id, previousRoad)
				end
				previous = id
				previousRoad = stop.road
			end
		end
		if not startsAtJunction then
			deadEndCrossing(line, line.from + DEAD_END)
		end
		if not endsAtJunction then
			deadEndCrossing(line, line.to - DEAD_END)
		end
	end
end

-- Dijkstra from a door's entry over the whole network (about a thousand nodes, once per
-- door), with a binary heap so a big city still builds in a few milliseconds.
local function flowTowards(entry: number): ({ [number]: number }, { [number]: number })
	local distance: { [number]: number } = { [entry] = 0 }
	local nextStep: { [number]: number } = {}
	local done: { [number]: boolean } = {}
	local heapIds: { number } = { entry }
	local heapKeys: { number } = { 0 }
	local function push(id: number, key: number)
		local i = #heapIds + 1
		heapIds[i], heapKeys[i] = id, key
		while i > 1 do
			local parent = i // 2
			if heapKeys[parent] <= key then
				break
			end
			heapIds[i], heapKeys[i] = heapIds[parent], heapKeys[parent]
			heapIds[parent], heapKeys[parent] = id, key
			i = parent
		end
	end
	local function pop(): (number, number)
		local id, key = heapIds[1], heapKeys[1]
		local n = #heapIds
		heapIds[1], heapKeys[1] = heapIds[n], heapKeys[n]
		heapIds[n], heapKeys[n] = nil :: any, nil :: any
		n -= 1
		local i = 1
		while true do
			local left, right, smallest = i * 2, i * 2 + 1, i
			if left <= n and heapKeys[left] < heapKeys[smallest] then
				smallest = left
			end
			if right <= n and heapKeys[right] < heapKeys[smallest] then
				smallest = right
			end
			if smallest == i then
				break
			end
			heapIds[i], heapIds[smallest] = heapIds[smallest], heapIds[i]
			heapKeys[i], heapKeys[smallest] = heapKeys[smallest], heapKeys[i]
			i = smallest
		end
		return id, key
	end
	while #heapIds > 0 do
		local best, bestDistance = pop()
		if not done[best] then
			done[best] = true
			for _, edge in nodes[best].edges do
				local d = bestDistance + edge.length
				if d < (distance[edge.to] or math.huge) then
					distance[edge.to] = d
					nextStep[edge.to] = best
					push(edge.to, d)
				end
			end
		end
	end
	return nextStep, distance
end

-- Splices each business's front door into the sidewalk running past it.
local function buildDoors()
	for _, definition in Businesses.List do
		local lot = definition.lot
		local cf = CFrame.new(lot.position.X, 0, lot.position.Z) * CFrame.Angles(0, math.rad(lot.yaw), 0)
		local front = -lot.size.Z / 2
		local approach = (cf * CFrame.new(0, 0, front - 8)).Position
		local inside = (cf * CFrame.new(0, 0, front + 5)).Position
		local forward = cf.LookVector
		local bestA, bestB, bestPoint, bestDistance = 0, 0, Vector3.zero, math.huge
		for a, node in nodes do
			for _, edge in node.edges do
				local b = edge.to
				if a < b and not edge.road then
					local pa, pb = node.position, nodes[b].position
					local along = Vector3.new(pb.X - pa.X, 0, pb.Z - pa.Z)
					local length = along.Magnitude
					if length > 0.5 then
						local dir = along / length
						if math.abs(dir:Dot(forward)) < 0.2 then
							local flat = Vector3.new(approach.X - pa.X, 0, approach.Z - pa.Z)
							local u = math.clamp(flat:Dot(dir), 0, length)
							local point = Vector3.new(pa.X, 0, pa.Z) + dir * u
							local toward = point - Vector3.new(approach.X, 0, approach.Z)
							local distance = toward.Magnitude
							if toward:Dot(forward) > 0 and distance < bestDistance then
								bestA, bestB, bestPoint, bestDistance = a, b, point, distance
							end
						end
					end
				end
			end
		end
		if bestA ~= 0 and bestDistance < 90 then
			local entry = nodeAt(Vector3.new(bestPoint.X, SIDEWALK_Y, bestPoint.Z))
			if entry ~= bestA and entry ~= bestB then
				unlink(bestA, bestB)
				link(bestA, entry, false)
				link(entry, bestB, false)
			end
			doors[definition.id] = {
				id = definition.id,
				entry = entry,
				approach = Vector3.new(approach.X, PLAZA_Y, approach.Z),
				inside = Vector3.new(inside.X, PLAZA_Y, inside.Z),
				next = {},
				distance = {},
			}
		else
			warn("[CityPaths] No sidewalk found in front of " .. definition.id)
		end
	end
	for _, door in doors do
		door.next, door.distance = flowTowards(door.entry)
		task.wait()
	end
end

function CityPaths.build()
	if built then
		return
	end
	built = true
	buildSidewalks()
	buildDoors()
end

function CityPaths.position(id: number): Vector3
	return nodes[id].position
end

function CityPaths.isRoad(a: number, b: number): boolean
	for _, edge in nodes[a].edges do
		if edge.to == b then
			return edge.road
		end
	end
	return false
end

-- A random neighbour to wander to, avoiding going straight back unless it is a dead end.
function CityPaths.wander(current: number, previous: number?, rng: Random): number
	local edges = nodes[current].edges
	if #edges == 0 then
		return current
	end
	local options = {}
	for _, edge in edges do
		if edge.to ~= previous then
			table.insert(options, edge.to)
		end
	end
	if #options == 0 then
		return edges[1].to
	end
	return options[rng:NextInteger(1, #options)]
end

-- A random sidewalk node (never one out on the asphalt).
function CityPaths.randomNode(rng: Random, near: Vector3?, minDistance: number?, maxDistance: number?): number
	for _ = 1, 120 do
		local id = rng:NextInteger(1, #nodes)
		local node = nodes[id]
		if node.position.Y > 0.5 and #node.edges > 0 then
			if not near then
				return id
			end
			local d = Vector3.new(node.position.X - near.X, 0, node.position.Z - near.Z).Magnitude
			if d >= (minDistance or 0) and d <= (maxDistance or math.huge) then
				return id
			end
		end
	end
	return rng:NextInteger(1, #nodes)
end

return CityPaths
