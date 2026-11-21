--!strict
-- DataService: loads, session-locks, autosaves and releases player data.
--  * UpdateAsync everywhere, so a save never blindly overwrites newer data.
--  * A session lock (jobId + timestamp) stops two servers editing one player at once.
--  * If data fails to load, the player keeps playing on defaults but that session is
--    NEVER saved, so a hiccup cannot wipe a real save.
-- Container: ServerScriptService.Services

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local DataService = {}

export type Profile = {
	data: any,
	canSave: boolean,
	dirty: boolean,
	loaded: boolean,
	runtime: { [string]: any }, -- per-session values that are never saved
}

local profiles: { [Player]: Profile } = {}
local loadedCallbacks: { (Player, Profile) -> () } = {}
local services: any
local store: DataStore? = nil
local storeStatus = "ok" -- "ok" | "unavailable" | "test" (Studio test mode: no DataStore at all)

local KEY_PREFIX = "Player_"
local LOAD_ATTEMPTS = 6

----- Helpers -----
local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end
DataService.deepCopy = deepCopy

function DataService.defaults(): any
	return {
		version = Config.DATA_VERSION,
		money = Config.STARTING_MONEY,
		runEarned = 0, -- earned since the last prestige (drives rank)
		lifetimeEarned = 0,
		prestige = 0,
		population = 0, -- City Population upgrade level (resets on prestige)
		businesses = {}, -- [businessId] = { level, upgrades = { [upgradeId] = level }, earned }
		visited = {}, -- [businessId] = true once the player walked inside
		achievements = {},
		stats = { upgradesBought = 0, hires = 0, served = 0, levelUps = 0, papers = 0, bags = 0, routes = 0 },
		settings = { music = true, sfx = true, ambient = true },
		receipts = {}, -- [purchaseId] = os.time() of cash packs already paid out (MonetizationService)
		lastOnline = os.time(),
	}
end

-- Fill in fields added after a player's data was first saved.
local function reconcile(data: any, template: any)
	for key, value in template do
		if data[key] == nil then
			data[key] = deepCopy(value)
		elseif type(value) == "table" and type(data[key]) == "table" and next(value) ~= nil then
			reconcile(data[key], value)
		end
	end
end

-- Never trust stored values blindly: a corrupt number would poison the economy.
local function sanitize(data: any)
	local function finite(n: any, fallback: number): number
		if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
			return fallback
		end
		return n
	end
	data.money = math.max(0, finite(data.money, Config.STARTING_MONEY))
	data.runEarned = math.max(0, finite(data.runEarned, 0))
	data.lifetimeEarned = math.max(0, finite(data.lifetimeEarned, 0))
	data.prestige = math.max(0, math.floor(finite(data.prestige, 0)))
	data.population = math.clamp(math.floor(finite(data.population, 0)), 0, Config.Population.maxLevel)
	-- Missions and daily quests were removed (2026-11-18): drop their old save fields.
	data.mission = nil
	data.daily = nil
	data.jobVersion = nil
	if type(data.receipts) ~= "table" then
		data.receipts = {}
	end
	for id, business in data.businesses do
		if type(business) ~= "table" then
			data.businesses[id] = nil
		else
			business.level = math.clamp(math.floor(finite(business.level, 1)), 1, Config.MAX_BUSINESS_LEVEL)
			business.upgrades = if type(business.upgrades) == "table" then business.upgrades else {}
			business.earned = finite(business.earned, 0)
		end
	end
end

local function isStudioAccessError(message: string): boolean
	message = message:lower()
	return message:find("publish") ~= nil
		or message:find("studioaccesstoapis") ~= nil
		or message:find("api services") ~= nil
		or message:find("403") ~= nil
end

----- Load / save -----
local function loadAsync(player: Player): (any?, boolean)
	local dataStore = store
	if not dataStore then
		return nil, false
	end
	local key = KEY_PREFIX .. player.UserId
	for attempt = 1, LOAD_ATTEMPTS do
		local lockedElsewhere = false
		local ok, result = pcall(function()
			return dataStore:UpdateAsync(key, function(old: any)
				lockedElsewhere = false
				local lock = if type(old) == "table" then old.lock else nil
				if type(lock) == "table" and lock.jobId ~= game.JobId
					and os.time() - (tonumber(lock.time) or 0) < Config.SESSION_LOCK_EXPIRY
					and attempt < LOAD_ATTEMPTS then
					-- Another server still holds this player (e.g. they just switched servers).
					lockedElsewhere = true
					return nil
				end
				local data = if type(old) == "table" then old else DataService.defaults()
				data.lock = { jobId = game.JobId, time = os.time() }
				return data
			end)
		end)
		if ok and not lockedElsewhere and type(result) == "table" then
			return result, true
		end
		if not ok then
			warn(string.format("[DataService] Load attempt %d failed for %s: %s", attempt, player.Name, tostring(result)))
			if isStudioAccessError(tostring(result)) then
				storeStatus = "unavailable"
				return nil, false
			end
		end
		if not player.Parent then
			return nil, false
		end
		task.wait(math.min(2 * attempt, 8))
	end
	return nil, false
end

local function writeAsync(player: Player, profile: Profile, release: boolean): boolean
	local dataStore = store
	if not dataStore or not profile.canSave or not profile.loaded then
		return false
	end
	profile.data.lastOnline = os.time()
	local snapshot = deepCopy(profile.data)
	-- Clear the flag now: anything that changes while this write is in flight marks it again.
	profile.dirty = false
	local key = KEY_PREFIX .. player.UserId
	for attempt = 1, 3 do
		local lostLock = false
		local ok, err = pcall(function()
			dataStore:UpdateAsync(key, function(old: any)
				lostLock = false
				local lock = if type(old) == "table" then old.lock else nil
				if type(lock) == "table" and lock.jobId ~= game.JobId then
					-- Another server took over this player: never overwrite its newer data.
					lostLock = true
					return nil
				end
				snapshot.lock = if release then nil else { jobId = game.JobId, time = os.time() }
				return snapshot
			end)
		end)
		if ok then
			if lostLock then
				warn("[DataService] Session lock lost for " .. player.Name .. "; this session will no longer save.")
				profile.canSave = false
				return false
			end
			return true
		end
		warn(string.format("[DataService] Save attempt %d failed for %s: %s", attempt, player.Name, tostring(err)))
		task.wait(attempt)
	end
	profile.dirty = true
	return false
end

-- One save at a time per player, so an older snapshot can never land after a newer one
-- (an autosave started before a Robux purchase must not overwrite the purchase's save).
local saving: { [Player]: boolean } = {}
local function saveAsync(player: Player, profile: Profile, release: boolean): boolean
	while saving[player] do
		task.wait(0.1)
	end
	saving[player] = true
	local ok, result = pcall(writeAsync, player, profile, release)
	saving[player] = nil
	if not ok then
		warn("[DataService] Save failed for " .. player.Name .. ": " .. tostring(result))
	end
	return ok and result == true
end

----- Public API -----
function DataService.get(player: Player): Profile?
	local profile = profiles[player]
	if profile and profile.loaded then
		return profile
	end
	return nil
end

function DataService.all(): { [Player]: Profile }
	return profiles
end

function DataService.markDirty(player: Player)
	local profile = profiles[player]
	if profile then
		profile.dirty = true
	end
end

-- Saves this player right away (MonetizationService, after paying out a Robux purchase).
-- Returns true once the data is safely written.
function DataService.saveNow(player: Player): boolean
	local profile = profiles[player]
	if not profile or not profile.loaded then
		return false
	end
	return saveAsync(player, profile, false)
end

function DataService.onLoaded(callback: (Player, Profile) -> ())
	table.insert(loadedCallbacks, callback)
end

function DataService.storeStatus(): string
	return storeStatus
end

-- Used by prestige: keep only what survives a reset (cash, shops, City Population and
-- rank progress all start over).
function DataService.resetForPrestige(profile: Profile)
	local old = profile.data
	local fresh = DataService.defaults()
	fresh.prestige = old.prestige + 1
	fresh.lifetimeEarned = old.lifetimeEarned
	fresh.achievements = old.achievements
	fresh.stats = old.stats
	fresh.settings = old.settings
	fresh.visited = old.visited
	fresh.receipts = old.receipts
	profile.data = fresh
	profile.dirty = true
end

local function onPlayerAdded(player: Player)
	local profile: Profile = { data = nil, canSave = false, dirty = false, loaded = false, runtime = {} }
	profiles[player] = profile

	local data, canSave = loadAsync(player)
	if not player.Parent then
		-- Left while loading: release the lock we may have taken.
		if data and canSave then
			profile.data = data
			profile.loaded = true
			profile.canSave = true
			saveAsync(player, profile, true)
		end
		profiles[player] = nil
		return
	end

	if data == nil then
		data = DataService.defaults()
		canSave = false
		if storeStatus == "test" then
			data.money = Config.STUDIO_TEST_MONEY
			profile.runtime.saveWarning = "Studio test mode: nothing is loaded or saved, and you start with test cash."
		elseif storeStatus == "unavailable" then
			profile.runtime.saveWarning = "Saving is off in this Studio session (enable Studio API access after publishing)."
		else
			profile.runtime.saveWarning = "Your data could not be loaded. Progress this session will NOT be saved - please rejoin later."
		end
	end
	data.lock = nil
	reconcile(data, DataService.defaults())
	sanitize(data)

	profile.data = data
	profile.canSave = canSave
	profile.loaded = true

	for _, callback in loadedCallbacks do
		task.spawn(callback, player, profile)
	end
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	if profile.loaded then
		saveAsync(player, profile, true)
	end
	profiles[player] = nil
end

function DataService.init(registry: any)
	services = registry
	if RunService:IsStudio() and Config.STUDIO_TEST_MODE then
		-- Never open the real store in a Studio test session, so nothing can be read or written.
		storeStatus = "test"
		return
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DATASTORE_NAME)
	end)
	if ok then
		store = result
	else
		storeStatus = "unavailable"
		warn("[DataService] DataStore unavailable: " .. tostring(result))
	end
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Autosave: staggered so a full server does not burst the DataStore budget.
	task.spawn(function()
		while true do
			task.wait(Config.AUTOSAVE_INTERVAL)
			for player, profile in profiles do
				if profile.loaded and profile.canSave and player.Parent then
					task.spawn(saveAsync, player, profile, false)
					task.wait(1)
				end
			end
		end
	end)

	-- Server shutdown: save everyone in parallel and wait for all of them.
	game:BindToClose(function()
		if RunService:IsStudio() and storeStatus ~= "ok" then
			return
		end
		local pending = 0
		for player, profile in profiles do
			if profile.loaded then
				pending += 1
				task.spawn(function()
					saveAsync(player, profile, true)
					pending -= 1
				end)
			end
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
