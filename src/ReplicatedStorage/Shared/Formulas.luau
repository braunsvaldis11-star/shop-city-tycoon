--!strict
-- Formulas: the business simulation maths. Pure functions, no side effects.
-- The server uses these to pay players; the client uses the same functions only to
-- preview numbers in the UI.
--
-- Model: customers arrive, are limited by seats, by how fast staff can serve them and
-- by how fast the station line can produce. Throughput is a SOFT minimum of the four
-- (a power mean with a negative exponent): the weakest stat (the "bottleneck") dominates,
-- but every upgrade still adds some income, so no purchase ever feels wasted.
-- Container: ReplicatedStorage.Shared

local Businesses = require(script.Parent.Businesses)
local Config = require(script.Parent.Config)

local Formulas = {}

export type BusinessState = {
	level: number,
	upgrades: { [string]: number },
	earned: number?,
}

export type Stats = {
	customers: number, -- arrivals per minute
	seats: number, -- capacity per minute
	service: number, -- served per minute
	production: number, -- produced per minute
	throughput: number, -- actual sales per minute
	spend: number, -- average $ per sale
	reputation: number, -- 0..1
	income: number, -- $ per second (includes level + prestige multipliers)
	bottleneck: string,
}

local function level(state: BusinessState, id: string): number
	return state.upgrades[id] or 0
end

function Formulas.reputation(state: BusinessState): number
	local decor = level(state, "floor") + level(state, "walls") + level(state, "lighting") + level(state, "furniture")
	local value = 0.35
		+ 0.06 * level(state, "reputation")
		+ 0.05 * level(state, "cleaners")
		+ 0.02 * decor
		+ 0.08 * level(state, "premium")
	return math.clamp(value, 0, 1)
end

-- `population` is the player's City Population level (more people on the streets means
-- more customers walking in at every business they own). `boost` multiplies income (the
-- 2× Cash game pass); leave it out for 1.
function Formulas.computeStats(definition: Businesses.Definition, state: BusinessState, prestige: number, population: number?, boost: number?): Stats
	local businessLevel = state.level
	local reputation = Formulas.reputation(state)
	local decor = level(state, "floor") + level(state, "walls") + level(state, "lighting") + level(state, "furniture")
	local people = math.clamp(population or 0, 0, Config.Population.maxLevel)

	local customers = definition.base.customers
		* (1 + 0.25 * level(state, "ads"))
		* (1 + 0.1 * (businessLevel - 1))
		* (0.6 + reputation * 0.8)
		* (1 + Config.Population.customerBonus * people)
	local seats = 8 + 8 * level(state, "tables")
	local service = definition.base.serve * (1 + level(state, "cashiers")) * (1 + 0.2 * level(state, "training"))
	local production = definition.base.produce
		* (1 + level(state, "stations"))
		* (1 + 0.35 * level(state, "equipment"))
		* (1 + 0.2 * level(state, "workers"))
		* (1 + 0.15 * level(state, "prep"))

	local lowest = customers
	local bottleneck = "Customers"
	if seats < lowest then
		lowest = seats
		bottleneck = "Seats"
	end
	if service < lowest then
		lowest = service
		bottleneck = "Service"
	end
	if production < lowest then
		lowest = production
		bottleneck = "Production"
	end
	local SOFTNESS = 3
	local sum = customers ^ -SOFTNESS + seats ^ -SOFTNESS + service ^ -SOFTNESS + production ^ -SOFTNESS
	local throughput = (sum / 4) ^ (-1 / SOFTNESS)

	local spend = definition.base.spend
		* (1 + 0.2 * level(state, "pricing"))
		* (1 + 0.1 * level(state, "seating"))
		* (1 + 0.03 * decor)
		* (1 + 0.05 * level(state, "premium"))

	local levelMultiplier = 1 + 0.25 * (businessLevel - 1)
	local income = throughput * spend / 60 * levelMultiplier * Config.prestigeMultiplier(prestige)
		* (1 + Config.Population.incomeBonus * people)
		* (boost or 1)

	return {
		customers = customers,
		seats = seats,
		service = service,
		production = production,
		throughput = throughput,
		spend = spend,
		reputation = reputation,
		income = income,
		bottleneck = bottleneck,
	}
end

-- The cheapest business: the one every new (or freshly prestiged) player starts with.
local STARTER_ID = (function(): string
	local best = Businesses.List[1]
	for _, definition in Businesses.List do
		if definition.order < best.order then
			best = definition
		end
	end
	return best.id
end)()
Formulas.STARTER_ID = STARTER_ID

-- The shop a player who owns nothing is guided to (new players and fresh prestiges),
-- or nil once they own a business.
function Formulas.starterShop(businesses: { [string]: any }): string?
	if next(businesses) == nil then
		return STARTER_ID
	end
	return nil
end

-- Estimated income of a freshly bought business (used on purchase signs).
function Formulas.startingIncome(definition: Businesses.Definition, prestige: number, population: number?, boost: number?): number
	return Formulas.computeStats(definition, { level = 1, upgrades = {} }, prestige, population, boost).income
end

function Formulas.upgradeCost(definition: Businesses.Definition, upgrade: Businesses.Upgrade, currentLevel: number): number
	return math.floor(definition.price * upgrade.costFactor * Config.UPGRADE_COST_SCALE * upgrade.growth ^ currentLevel)
end

function Formulas.levelUpCost(definition: Businesses.Definition, currentLevel: number): number
	return math.floor(definition.price * Config.LEVEL_UP_COST * Config.LEVEL_UP_GROWTH ^ (currentLevel - 1))
end

-- The highest level an upgrade may reach right now (business level gates upgrades).
-- Returns the cap and, when the next level is locked, the business level it needs.
function Formulas.upgradeCap(upgrade: Businesses.Upgrade, businessLevel: number): (number, number?)
	local cap = math.min(upgrade.max, businessLevel + 1)
	local nextRequirement: number? = nil
	if upgrade.levelReq then
		cap = 0
		for i, required in upgrade.levelReq do
			if businessLevel >= required then
				cap = i
			elseif nextRequirement == nil then
				nextRequirement = required
			end
		end
		cap = math.min(cap, upgrade.max)
	elseif cap < upgrade.max then
		nextRequirement = cap -- next level needs business level = current cap
	end
	return cap, nextRequirement
end

return Formulas
