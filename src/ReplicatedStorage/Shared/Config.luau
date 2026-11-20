--!strict
-- Config: global game tuning. Server and client both read it; only the server acts on it.
-- Container: ReplicatedStorage.Shared

local CityLayout = require(script.Parent.CityLayout)

local Config = {}

----- Economy -----
-- Balance: small numbers and a slow, steady climb. Every business pays back a little
-- slower than the one before it (Businesses: BASE_SPEND_RATE / SPEND_DECAY) and upgrades
-- cost a real chunk of income, so an expert needs ~14 hours to own the whole city.
Config.STARTING_MONEY = 1_000 -- exactly the price of the first shop (the Pizza Restaurant)

-- The paper route (News Stand + mailboxes) is switched off: new players start with cash
-- for their first shop instead. Set true to bring the side job back.
Config.PAPER_ROUTE_ENABLED = false

-- Starter job: grab a bag at the News Stand (spawn park), throw papers at the marked
-- mailboxes. About 4 bags (~5 minutes) buys the Pizza Restaurant. Later on, pay
-- scales with income so the route stays a small active bonus.
Config.PaperJob = {
	bagSize = 8,
	payPerPaper = 25,
	bagBonus = 50,
	incomeSecondsPerPaper = 2, -- late game: a paper is worth this many seconds of income
	incomeSecondsPerBag = 4,
	tipChance = 0.2,
	tip = 10,
	throwRange = 26, -- studs from the mailbox (prompt range is a little less)
	standRange = 16,
	minInterval = 0.6, -- seconds between deliveries
	routeRadius = 190, -- mailboxes this close to the stand can be on a route
	pickFrom = 5, -- each next stop is one of the N nearest unvisited mailboxes
	sneakerRoutes = 1, -- finished routes before the Delivery Sneakers unlock
	sneakerSpeed = 24, -- WalkSpeed while carrying papers with sneakers (default 16)
}
Config.UPGRADE_COST_SCALE = 5 -- upgrade cost = price * costFactor * this * growth^level
Config.LEVEL_UP_COST = 2 -- level-up cost = price * this * LEVEL_UP_GROWTH^(level - 1)
Config.LEVEL_UP_GROWTH = 2.3
-- Income is paid per customer: every business gets customers at its sales rate
-- (Formulas: throughput per minute), each paying its average sale. A customer sets off
-- for the shop and pays at the till CUSTOMER_LEAD seconds later, which gives the client
-- time to walk a pedestrian in through the door before the cash arrives.
Config.CUSTOMER_TICK = 0.25 -- seconds between customer rolls on the server
Config.CUSTOMER_LEAD = 12 -- seconds from a customer setting off to reaching the door
-- Shops: the customer goes in, picks up their item and pays on the way out, this many
-- seconds after reaching the door. Attractions (entryFee) are paid at the door.
Config.SHOP_VISIT_SECONDS = 6
Config.OFFLINE_CAP_SECONDS = 2 * 60 * 60 -- offline earnings capped at 2 hours
Config.OFFLINE_RATE = 0.5 -- offline earnings pay 50% of live income
Config.MAX_BUSINESS_LEVEL = 10

----- Saving -----
-- v2: fresh saves for the rebalanced economy (2026-11-17). The old v1 saves are left
-- untouched in their own store, so they can be restored by switching back.
Config.DATASTORE_NAME = "CityBusinessSim_PlayerData_v2"
Config.DATA_VERSION = 1
Config.AUTOSAVE_INTERVAL = 90
Config.SESSION_LOCK_EXPIRY = 600 -- seconds before a stale session lock may be taken over

----- Private interiors -----
-- Every player gets a private "slot" far away from the shared city. The player's own
-- client builds the interior there, so nobody else ever sees or touches it.
Config.INTERIOR_ORIGIN = Vector3.new(20_000, 1_500, 0)
Config.INTERIOR_SLOT_SPACING = 1_000
Config.INTERIOR_MIN_Y = 1_000 -- anything above this height counts as "inside an interior"
Config.INTERIOR_SPAWN_OFFSET = Vector3.new(0, 4, 22)
Config.INTERIOR_ROOM_RADIUS = 90 -- the guard ejects players further than this from their slot

----- Progression -----
export type Rank = { name: string, minEarned: number, color: Color3, emoji: string }
Config.Ranks = {
	{ name = "Beginner Business Owner", minEarned = 0, color = Color3.fromRGB(150, 220, 120), emoji = "🌱" },
	{ name = "Local Entrepreneur", minEarned = 100_000, color = Color3.fromRGB(90, 190, 255), emoji = "💼" },
	{ name = "Business Tycoon", minEarned = 50_000_000, color = Color3.fromRGB(190, 120, 255), emoji = "🎩" },
	{ name = "City Investor", minEarned = 2_000_000_000, color = Color3.fromRGB(255, 170, 60), emoji = "🏙️" },
	{ name = "Business Empire", minEarned = 40_000_000_000, color = Color3.fromRGB(255, 215, 70), emoji = "👑" },
} :: { Rank }

export type District = {
	id: string,
	name: string,
	color: Color3,
	description: string,
	-- map rectangle (min/max X and Z) used by the city map UI
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
}
Config.Districts = {
	{
		id = "Starter",
		name = "Old Town",
		color = Color3.fromRGB(120, 210, 110),
		description = "The cozy starter district: a park, Main Street and six shops.",
		minX = -206, maxX = 206, minZ = -206, maxZ = 206,
	},
	{
		id = "Maple",
		name = "Maple Hills",
		color = Color3.fromRGB(255, 165, 80),
		description = "Leafy suburbs with a pet shop, a burger diner and a sports field.",
		minX = -206, maxX = 206, minZ = 206, maxZ = 606,
	},
	{
		id = "Downtown",
		name = "Downtown",
		color = Color3.fromRGB(90, 170, 255),
		description = "Skyscrapers and busy streets: a gym, an electronics store and a car dealership.",
		minX = -206, maxX = 206, minZ = -606, maxZ = -206,
	},
	{
		id = "Harbor",
		name = "Harbor Bay",
		color = Color3.fromRGB(60, 200, 220),
		description = "Docks, boats and a lighthouse, with a seafood restaurant and an aquarium.",
		minX = -606, maxX = -206, minZ = -206, maxZ = 206,
	},
	{
		id = "Uptown",
		name = "Uptown Heights",
		color = Color3.fromRGB(200, 130, 255),
		description = "Luxury district with a grand hotel and the shopping mall.",
		minX = 206, maxX = 606, minZ = -206, maxZ = 206,
	},
	{
		id = "Financial",
		name = "Financial District",
		color = Color3.fromRGB(255, 210, 80),
		description = "Glass skyscrapers around the stock exchange, home of the Tech Company.",
		minX = 206, maxX = 606, minZ = -606, maxZ = -206,
	},
	{
		id = "Seaside",
		name = "Seaside Village",
		color = Color3.fromRGB(240, 215, 150),
		description = "Beach houses by the water, with a surf shop and a sushi bar.",
		minX = -606, maxX = -206, minZ = 206, maxZ = 606,
	},
	{
		id = "Dockyards",
		name = "The Dockyards",
		color = Color3.fromRGB(150, 160, 180),
		description = "Cranes, containers and warehouses around the fish market.",
		minX = -606, maxX = -206, minZ = -606, maxZ = -206,
	},
	{
		id = "Sunset",
		name = "Sunset Hills",
		color = Color3.fromRGB(255, 120, 110),
		description = "Mansions on the hill, with a day spa and a jewelry boutique.",
		minX = 206, maxX = 606, minZ = 206, maxZ = 606,
	},
	{
		id = "Arts",
		name = "Arts Quarter",
		color = Color3.fromRGB(235, 100, 200),
		description = "Galleries and cafés around a bookstore and the cinema.",
		minX = 606, maxX = 1006, minZ = 206, maxZ = 606,
	},
	{
		id = "Funland",
		name = "Funland",
		color = Color3.fromRGB(170, 230, 60),
		description = "The fun part of town: a toy store and a neon arcade.",
		minX = 606, maxX = 1006, minZ = -206, maxZ = 206,
	},
	{
		id = "BizPark",
		name = "Business Park",
		color = Color3.fromRGB(40, 170, 150),
		description = "Office towers and the City Bank, the most valuable business in town.",
		minX = 606, maxX = 1006, minZ = -606, maxZ = -206,
	},
} :: { District }
-- District rectangles above are in plan units, like CityLayout; scale them to studs.
for _, district in Config.Districts do
	district.minX *= CityLayout.SCALE
	district.maxX *= CityLayout.SCALE
	district.minZ *= CityLayout.SCALE
	district.maxZ *= CityLayout.SCALE
end

-- Prestige: start over with a permanent income boost (+50% per prestige). You lose your
-- cash, shops and City Population. No cash is needed: you just have to OWN enough shops
-- (any shops). There are 5 prestiges in total; the last one needs 11 shops (x3.5 income).
Config.Prestige = {
	shopsNeeded = { 1, 3, 5, 8, 11 }, -- shops owned for the 1st, 2nd, 3rd, 4th and 5th (last) prestige
	multiplierPerLevel = 0.5, -- each prestige adds +50% to all income (1st = x1.5)
}
Config.MAX_PRESTIGE = #Config.Prestige.shopsNeeded

-- Anyone who owns no shop and has less than the first shop's price is topped up to it
-- (BusinessService.starterGrant), so nobody gets stuck before their first business.

----- City -----
Config.CITY_SPAWN = Vector3.new(0, 4, 34 * CityLayout.SCALE)

-- City Population: a city-wide upgrade. Every level adds pedestrians to the player's
-- own (client-side) streets and more customers to every business they own.
Config.Population = {
	maxLevel = 10,
	baseCost = 2_500, -- cost of the first level
	growth = 3.2, -- every further level costs this many times more
	customerBonus = 0.12, -- +12% customers at every business per level
	incomeBonus = 0.04, -- +4% income at every business per level (busier streets spend more)
	basePedestrians = 110,
	pedestriansPerLevel = 14,
}

function Config.populationCost(level: number): number
	return math.floor(Config.Population.baseCost * Config.Population.growth ^ level)
end

function Config.pedestrianCount(level: number): number
	return Config.Population.basePedestrians + Config.Population.pedestriansPerLevel * level
end

----- Audio (Roblox stock sounds that ship with every client) -----
Config.Sounds = {
	Click = "rbxasset://sounds/clickfast.wav",
	Purchase = "rbxasset://sounds/electronicpingshort.wav",
	Cash = "rbxasset://sounds/button.wav",
	Error = "rbxasset://sounds/snap.wav",
	LevelUp = "rbxasset://sounds/victory.wav",
	Whoosh = "rbxasset://sounds/action_get_up.mp3",
	Firework = "rbxassetid://134947109312227", -- Creator Store: "Firework explosion"
	Cheer = "rbxassetid://105154404054447", -- Creator Store: small crowd cheering and clapping
}

function Config.getRankIndex(earned: number): number
	local index = 1
	for i, rank in Config.Ranks do
		if earned >= rank.minEarned then
			index = i
		end
	end
	return index
end

function Config.getDistrict(id: string): District?
	for _, district in Config.Districts do
		if district.id == id then
			return district
		end
	end
	return nil
end

function Config.getSlotOrigin(slot: number): Vector3
	return Config.INTERIOR_ORIGIN + Vector3.new((slot - 1) * Config.INTERIOR_SLOT_SPACING, 0, 0)
end

function Config.prestigeMultiplier(prestige: number): number
	return 1 + prestige * Config.Prestige.multiplierPerLevel
end

-- Shops you must own for the NEXT prestige when you have `prestige` already, or nil once
-- every prestige is done.
function Config.prestigeShops(prestige: number): number?
	return Config.Prestige.shopsNeeded[math.max(math.floor(prestige), 0) + 1]
end

-- How many shops a player owns (works on the saved data and on the synced client state).
function Config.countShops(businesses: { [any]: any }?): number
	local count = 0
	if businesses then
		for _ in businesses do
			count += 1
		end
	end
	return count
end

return Config
