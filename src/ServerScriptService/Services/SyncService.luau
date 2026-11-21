--!strict
-- SyncService: sends each player a read-only snapshot of their own state.
-- Changes are batched: services call Sync.mark(player) and one loop sends at most
-- one snapshot per player every SYNC_INTERVAL seconds. Clients never send state back.
-- Container: ServerScriptService.Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)

local SyncService = {}

local SYNC_INTERVAL = 0.2

local services: any
local dirty: { [Player]: boolean } = {}
local warned: { [Player]: boolean } = {}

function SyncService.mark(player: Player)
	dirty[player] = true
end

local function buildSnapshot(player: Player, profile: any): any
	local data = profile.data
	local cache = services.Economy.getCache(player)
	local businesses = {}
	for id, state in data.businesses do
		businesses[id] = {
			level = state.level,
			upgrades = state.upgrades,
			earned = state.earned,
			stats = cache.perBusiness[id],
		}
	end
	local progression = services.Progression.describe(player, data)
	return {
		money = data.money,
		income = cache.total,
		runEarned = data.runEarned,
		lifetimeEarned = data.lifetimeEarned,
		prestige = data.prestige,
		population = data.population,
		prestigeMultiplier = Config.prestigeMultiplier(data.prestige),
		prestigeShops = progression.prestigeShops, -- shops needed for the next prestige (nil = all done)
		nextMultiplier = Config.prestigeMultiplier(data.prestige + 1),
		rank = Config.getRankIndex(data.runEarned),
		businesses = businesses,
		starterShop = Formulas.starterShop(data.businesses),
		achievements = progression.achievements,
		stats = data.stats,
		settings = data.settings,
		inside = services.Interior.getInsideBusiness(player),
		job = if services.Job then services.Job.describe(player) else nil,
		saving = profile.canSave,
		passes = if services.Monetization then services.Monetization.ownedKeys(player) else {},
		incomeBoost = if services.Monetization then services.Monetization.incomeMultiplier(player) else 1,
	}
end

local function flush()
	for player in dirty do
		dirty[player] = nil
		local profile = services.Data.get(player)
		if profile and player.Parent then
			local ok, result = pcall(buildSnapshot, player, profile)
			if ok then
				services.Net.fire(player, "StateSync", result)
			else
				warn("[SyncService] snapshot failed: " .. tostring(result))
			end
			if not warned[player] and profile.runtime.saveWarning then
				warned[player] = true
				services.Net.notify(player, "warning", profile.runtime.saveWarning)
			end
		end
	end
end

local SETTING_KEYS = { music = true, sfx = true, ambient = true }

function SyncService.init(registry: any)
	services = registry
end

function SyncService.start()
	services.Data.onLoaded(function(player)
		SyncService.mark(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
		warned[player] = nil
	end)
	services.Net.on("UpdateSetting", 5, function(player, key, value)
		if type(key) ~= "string" or not SETTING_KEYS[key] or type(value) ~= "boolean" then
			return
		end
		local profile = services.Data.get(player)
		if profile then
			profile.data.settings[key] = value
			services.Data.markDirty(player)
			SyncService.mark(player)
		end
	end)
	-- A late-joining client asks for a fresh snapshot by firing StateSync once.
	services.Net.on("StateSync", 1, function(player)
		SyncService.mark(player)
	end)
	task.spawn(function()
		while true do
			task.wait(SYNC_INTERVAL)
			flush()
		end
	end)
end

return SyncService
