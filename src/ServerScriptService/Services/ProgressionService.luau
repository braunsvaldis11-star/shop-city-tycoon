--!strict
-- ProgressionService: ranks, achievements and prestige.
-- Prestige: own enough shops (1, 3, 5, 8, then 11 for the last one) to start over with a
-- permanent income boost. No cash needed (see Config.Prestige).
-- Container: ServerScriptService.Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Businesses = require(Shared.Businesses)
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Goals = require(Shared.Goals)

local ProgressionService = {}

local services: any

local DECOR_IDS = { "floor", "walls", "lighting", "furniture", "premium" }

-- Reads one progress number for a goal metric.
local function readMetric(player: Player, data: any, metric: string, param: string?): number
	if metric == "owned" then
		local count = 0
		for _ in data.businesses do
			count += 1
		end
		return count
	elseif metric == "ownSpecific" then
		return if param and data.businesses[param] then 1 else 0
	elseif metric == "visited" then
		return if param and data.visited[param] then 1 else 0
	elseif metric == "upgradeLevel" then
		local best = 0
		for _, business in data.businesses do
			best = math.max(best, business.upgrades[param :: string] or 0)
		end
		return best
	elseif metric == "businessLevel" then
		local best = 0
		for _, business in data.businesses do
			best = math.max(best, business.level)
		end
		return best
	elseif metric == "specificLevel" then
		local business = if param then data.businesses[param] else nil
		return if business then business.level else 0
	elseif metric == "income" then
		return services.Economy.getCache(player).total
	elseif metric == "rank" then
		return Config.getRankIndex(data.runEarned)
	elseif metric == "districtsOwned" then
		local seen, count = {}, 0
		for id in data.businesses do
			local definition = Businesses.get(id)
			if definition and not seen[definition.district] then
				seen[definition.district] = true
				count += 1
			end
		end
		return count
	elseif metric == "prestige" then
		return data.prestige
	elseif metric == "population" then
		return data.population or 0
	elseif metric == "lifetimeEarned" then
		return data.lifetimeEarned
	elseif metric == "decorMax" then
		for _, business in data.businesses do
			local maxed = true
			for _, id in DECOR_IDS do
				local upgrade = Businesses.getUpgrade(id)
				if upgrade and (business.upgrades[id] or 0) < upgrade.max then
					maxed = false
					break
				end
			end
			if maxed then
				return 1
			end
		end
		return 0
	elseif data.stats[metric] ~= nil then
		return data.stats[metric]
	end
	return 0
end

----- Snapshot helpers used by SyncService -----
function ProgressionService.describe(player: Player, data: any): any
	local achievements = {}
	for _, achievement in Goals.Achievements do
		local id = achievement.id :: string
		achievements[id] = {
			unlocked = data.achievements[id] == true,
			progress = math.min(readMetric(player, data, achievement.metric, achievement.param), achievement.target),
		}
	end
	return {
		achievements = achievements,
		prestigeShops = Config.prestigeShops(data.prestige), -- nil once every prestige is done
	}
end

----- Checks (cheap; called after any change and once per income tick) -----
function ProgressionService.check(player: Player)
	local profile = services.Data.get(player)
	if not profile then
		return
	end
	local data = profile.data
	local runtime = profile.runtime

	-- Rank ups
	local rank = Config.getRankIndex(data.runEarned)
	if runtime.rank and rank > runtime.rank then
		local info = Config.Ranks[rank]
		services.Net.notify(player, "rankup", info.emoji .. " New rank: " .. info.name .. "!")
		services.Sync.mark(player)
	end
	runtime.rank = rank

	-- Achievements are awarded automatically.
	for _, achievement in Goals.Achievements do
		local id = achievement.id :: string
		if not data.achievements[id] and readMetric(player, data, achievement.metric, achievement.param) >= achievement.target then
			data.achievements[id] = true
			services.Data.markDirty(player)
			services.Economy.addMoney(player, achievement.reward, true)
			services.Net.notify(player, "achievement", string.format("%s Achievement: %s! +%s",
				achievement.emoji or "🏆", achievement.name or id, Format.cash(achievement.reward)))
			services.Sync.mark(player)
		end
	end

	-- The prestige button lights up the moment you own enough shops for the next prestige.
	local needed = Config.prestigeShops(data.prestige)
	local ready = needed ~= nil and Config.countShops(data.businesses) >= needed
	if runtime.prestigeReady ~= ready then
		if ready and runtime.prestigeReady == false then
			services.Net.notify(player, "levelup", string.format("🌟 You can Prestige! Start over with x%.1f income.", Config.prestigeMultiplier(data.prestige + 1)))
		end
		runtime.prestigeReady = ready
		services.Sync.mark(player)
	end
end

-- Prestige: pay nothing, but you must own enough shops. Everything resets
-- (cash, shops, City Population, rank) except achievements, stats and settings.
local function prestige(player: Player)
	local profile = services.Data.get(player)
	if not profile then
		return
	end
	local needed = Config.prestigeShops(profile.data.prestige)
	if not needed then
		services.Net.notify(player, "info", "👑 You've done every Prestige - your income is maxed out!")
		return
	end
	local owned = Config.countShops(profile.data.businesses)
	if owned < needed then
		services.Net.notify(player, "error", string.format("Own %d shop%s to Prestige (you have %d).", needed, if needed == 1 then "" else "s", owned))
		return
	end
	services.Interior.exit(player)
	services.Data.resetForPrestige(profile)
	profile.runtime.rank = 1
	profile.runtime.prestigeReady = false
	services.Economy.recompute(player)
	ProgressionService.check(player)
	services.Sync.mark(player)
	services.Net.fire(player, "Prestiged", profile.data.prestige)
	local multiplier = Config.prestigeMultiplier(profile.data.prestige)
	services.Business.starterGrant(player)
	local starter = Businesses.get(Formulas.STARTER_ID)
	local final = Config.prestigeShops(profile.data.prestige) == nil
	services.Net.notify(player, "rankup", string.format("🌟 Prestige %d%s All income is now x%.1f.", profile.data.prestige, if final then " - the final one!" else "!", multiplier))
	if starter then
		task.delay(1.5, function()
			if player.Parent then
				services.Net.notify(player, "reward", string.format("%s You start with %s - buy the %s again and grow faster!", starter.emoji, Format.cash(profile.data.money), starter.name))
			end
		end)
	end
end

function ProgressionService.init(registry: any)
	services = registry
end

function ProgressionService.start()
	local Net = services.Net
	Net.on("Prestige", 0.5, prestige)
	services.Data.onLoaded(function(player)
		services.Business.starterGrant(player)
		ProgressionService.check(player)
	end)
end

return ProgressionService
