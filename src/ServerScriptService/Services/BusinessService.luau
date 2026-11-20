--!strict
-- BusinessService: buying, upgrading and levelling businesses (the owner's hands-on
-- mini games live in MiniGameService). Every request is validated here: types,
-- ownership, district access, upgrade caps and price are all checked on the server.
-- Container: ServerScriptService.Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Businesses = require(Shared.Businesses)
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)

local BusinessService = {}

local services: any

local HIRE_UPGRADES = { cashiers = true, workers = true, cleaners = true }

local function changed(player: Player)
	services.Data.markDirty(player)
	services.Economy.recompute(player)
	services.Progression.check(player)
	services.Sync.mark(player)
end

function BusinessService.owns(player: Player, businessId: string): boolean
	local profile = services.Data.get(player)
	return profile ~= nil and profile.data.businesses[businessId] ~= nil
end

function BusinessService.purchase(player: Player, businessId: any): boolean
	if type(businessId) ~= "string" then
		return false
	end
	local definition = Businesses.get(businessId)
	local profile = services.Data.get(player)
	if not definition or not profile then
		return false
	end
	local data = profile.data
	if data.businesses[businessId] then
		services.Net.notify(player, "info", "You already own the " .. definition.name .. ".")
		return false
	end
	local price = definition.price
	if not services.Economy.trySpend(player, price) then
		services.Net.notify(player, "error", "You need " .. Format.cash(price) .. " to buy the " .. definition.name .. ".")
		return false
	end
	local first = next(data.businesses) == nil
	data.businesses[businessId] = { level = 1, upgrades = {}, earned = 0 }
	changed(player)
	services.Net.fire(player, "CashPopup", -price, "purchase")
	if first then
		services.Net.notify(player, "success", definition.emoji .. " Your first shop! Walk through the door to go inside and watch it earn.")
	else
		services.Net.notify(player, "success", definition.emoji .. " You bought the " .. definition.name .. "! Walk through the door to enter.")
	end
	return true
end

-- Nobody gets stuck before their first business: a player who owns no shop (an old
-- save, or anyone short after a prestige) is topped up to the first shop's price.
function BusinessService.starterGrant(player: Player): boolean
	local profile = services.Data.get(player)
	local starter = Businesses.get(Formulas.STARTER_ID)
	if not profile or not starter then
		return false
	end
	local data = profile.data
	if next(data.businesses) ~= nil or data.money >= starter.price then
		return false
	end
	local gift = starter.price - data.money
	services.Economy.addMoney(player, gift, false)
	services.Data.markDirty(player)
	services.Sync.mark(player)
	task.delay(3, function()
		if player.Parent then
			services.Net.notify(player, "reward", string.format("🎁 Here's %s for your first shop! Follow the golden trail to the %s.", Format.cash(gift), starter.name))
		end
	end)
	return true
end

function BusinessService.upgrade(player: Player, businessId: any, upgradeId: any): boolean
	if type(businessId) ~= "string" or type(upgradeId) ~= "string" then
		return false
	end
	local definition = Businesses.get(businessId)
	local upgrade = Businesses.getUpgrade(upgradeId)
	local profile = services.Data.get(player)
	if not definition or not upgrade or not profile then
		return false
	end
	local state = profile.data.businesses[businessId]
	if not state then
		services.Net.notify(player, "error", "You don't own the " .. definition.name .. ".")
		return false
	end
	local current = state.upgrades[upgradeId] or 0
	if current >= upgrade.max then
		services.Net.notify(player, "info", "That upgrade is already maxed.")
		return false
	end
	local cap, requirement = Formulas.upgradeCap(upgrade, state.level)
	if current >= cap then
		services.Net.notify(player, "error", "Reach business Level " .. tostring(requirement or state.level + 1) .. " to unlock this.")
		return false
	end
	local cost = Formulas.upgradeCost(definition, upgrade, current)
	if not services.Economy.trySpend(player, cost) then
		services.Net.notify(player, "error", "Not enough cash! You need " .. Format.cash(cost) .. ".")
		return false
	end

	state.upgrades[upgradeId] = current + 1
	local stats = profile.data.stats
	stats.upgradesBought += 1
	if HIRE_UPGRADES[upgradeId] then
		stats.hires += 1
	end
	changed(player)
	services.Net.fire(player, "CashPopup", -cost, "upgrade")
	return true
end

function BusinessService.levelUp(player: Player, businessId: any): boolean
	if type(businessId) ~= "string" then
		return false
	end
	local definition = Businesses.get(businessId)
	local profile = services.Data.get(player)
	if not definition or not profile then
		return false
	end
	local state = profile.data.businesses[businessId]
	if not state then
		return false
	end
	if state.level >= Config.MAX_BUSINESS_LEVEL then
		services.Net.notify(player, "info", definition.name .. " is already at max level!")
		return false
	end
	local cost = Formulas.levelUpCost(definition, state.level)
	if not services.Economy.trySpend(player, cost) then
		services.Net.notify(player, "error", "Not enough cash! Level up costs " .. Format.cash(cost) .. ".")
		return false
	end
	state.level += 1
	profile.data.stats.levelUps += 1
	changed(player)
	services.Net.notify(player, "levelup", definition.emoji .. " " .. definition.name .. " reached Level " .. state.level .. "!")
	services.Net.fire(player, "CashPopup", -cost, "levelup")
	return true
end

-- City Population: a city-wide upgrade. More people walk the player's streets and every
-- business they own gets more customers (see Formulas.computeStats).
function BusinessService.growPopulation(player: Player): boolean
	local profile = services.Data.get(player)
	if not profile then
		return false
	end
	local data = profile.data
	local current = data.population or 0
	if current >= Config.Population.maxLevel then
		services.Net.notify(player, "info", "Your city is already at its maximum population!")
		return false
	end
	local cost = Config.populationCost(current)
	if not services.Economy.trySpend(player, cost) then
		services.Net.notify(player, "error", "Not enough cash! Growing the city costs " .. Format.cash(cost) .. ".")
		return false
	end
	data.population = current + 1
	changed(player)
	services.Net.notify(player, "levelup", string.format("🏙️ City Population %d! %d people now walk your streets.", data.population, Config.pedestrianCount(data.population)))
	services.Net.fire(player, "CashPopup", -cost, "upgrade")
	return true
end

function BusinessService.init(registry: any)
	services = registry
end

function BusinessService.start()
	local Net = services.Net
	Net.on("PurchaseBusiness", 2, function(player, businessId)
		BusinessService.purchase(player, businessId)
	end)
	Net.on("UpgradeBusiness", 8, function(player, businessId, upgradeId)
		BusinessService.upgrade(player, businessId, upgradeId)
	end)
	Net.on("LevelUpBusiness", 4, function(player, businessId)
		BusinessService.levelUp(player, businessId)
	end)
	Net.on("GrowPopulation", 4, function(player)
		BusinessService.growPopulation(player)
	end)
end

return BusinessService
