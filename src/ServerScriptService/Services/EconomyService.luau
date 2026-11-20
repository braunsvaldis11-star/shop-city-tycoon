--!strict
-- EconomyService: the only code allowed to change a player's money.
-- Pays income customer by customer, pays offline earnings on join, and caches each
-- player's computed business stats.
--
-- Customers: every owned business gets customers at its sales rate (stats.throughput
-- per minute, with random gaps), and each one pays the average sale, so the long-run
-- income is exactly stats.income per second. The owner's client is told about each
-- customer CUSTOMER_LEAD seconds before they pay, so it can walk a pedestrian in
-- through the door (and into the interior) right as the money arrives. The client
-- only animates; the server decides who comes and what they pay.
-- Container: ServerScriptService.Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Businesses = require(Shared.Businesses)
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)

local EconomyService = {}

export type Cache = { total: number, perBusiness: { [string]: Formulas.Stats } }

type Visit = { due: number, id: string, amount: number }

local services: any
local caches: { [Player]: Cache } = {}
local nextCustomer: { [Player]: { [string]: number } } = {} -- os.clock() of each shop's next customer
local visits: { [Player]: { Visit } } = {} -- customers on their way to the till
local lastCheck: { [Player]: number } = {}
local rng = Random.new()

local MAX_PER_ROLL = 40 -- customers one shop may get in a single tick

-- What one sale is worth, so that sales per second x sale value = income per second.
local function saleValue(stats: Formulas.Stats): number
	return stats.income * 60 / math.max(stats.throughput, 0.01)
end

local function updateLeaderstats(player: Player, data: any)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	local cash = leaderstats:FindFirstChild("Cash") :: StringValue?
	if cash then
		cash.Value = Format.money(data.money)
	end
	local rank = leaderstats:FindFirstChild("Rank") :: StringValue?
	if rank then
		local index = Config.getRankIndex(data.runEarned)
		rank.Value = Config.Ranks[index].name
	end
	local prestige = leaderstats:FindFirstChild("Prestige") :: IntValue?
	if prestige then
		prestige.Value = data.prestige
	end
end

local function publish(player: Player, data: any)
	-- Attributes replicate cheaply and let the HUD tick smoothly between full syncs.
	player:SetAttribute("Money", data.money)
	local cache = caches[player]
	player:SetAttribute("Income", if cache then cache.total else 0)
	updateLeaderstats(player, data)
end

function EconomyService.getCache(player: Player): Cache
	return caches[player] or { total = 0, perBusiness = {} }
end

function EconomyService.recompute(player: Player)
	local profile = services.Data.get(player)
	if not profile then
		return
	end
	local data = profile.data
	local cache: Cache = { total = 0, perBusiness = {} }
	for id, state in data.businesses do
		local definition = Businesses.get(id)
		if definition then
			local stats = Formulas.computeStats(definition, state, data.prestige, data.population)
			cache.perBusiness[id] = stats
			cache.total += stats.income
		end
	end
	caches[player] = cache
	publish(player, data)
end

function EconomyService.getMoney(player: Player): number
	local profile = services.Data.get(player)
	return if profile then profile.data.money else 0
end

-- countsAsEarned: income and rewards raise rank progress; refunds would not.
function EconomyService.addMoney(player: Player, amount: number, countsAsEarned: boolean)
	local profile = services.Data.get(player)
	if not profile or amount ~= amount or amount <= 0 or amount == math.huge then
		return
	end
	local data = profile.data
	data.money += amount
	if countsAsEarned then
		data.runEarned += amount
		data.lifetimeEarned += amount
	end
	profile.dirty = true
	publish(player, data)
end

-- Atomic check-and-spend. Returns false (and spends nothing) if the player cannot afford it.
function EconomyService.trySpend(player: Player, amount: number): boolean
	local profile = services.Data.get(player)
	if not profile or amount ~= amount or amount < 0 then
		return false
	end
	if profile.data.money < amount then
		return false
	end
	profile.data.money -= amount
	profile.dirty = true
	publish(player, profile.data)
	return true
end

local function setupLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "Cash"
	cash.Parent = leaderstats
	local prestige = Instance.new("IntValue")
	prestige.Name = "Prestige"
	prestige.Parent = leaderstats
	local rank = Instance.new("StringValue")
	rank.Name = "Rank"
	rank.Parent = leaderstats
	leaderstats.Parent = player
end

local function onLoaded(player: Player, profile: any)
	setupLeaderstats(player)
	EconomyService.recompute(player)

	-- Offline earnings: half of live income, capped at two hours.
	local data = profile.data
	local away = os.time() - (tonumber(data.lastOnline) or os.time())
	local cache = caches[player]
	if away > 60 and cache and cache.total > 0 then
		local seconds = math.min(away, Config.OFFLINE_CAP_SECONDS)
		local earned = math.floor(cache.total * seconds * Config.OFFLINE_RATE)
		if earned > 0 then
			EconomyService.addMoney(player, earned, true)
			task.delay(4, function()
				if player.Parent then
					services.Net.notify(player, "reward", string.format(
						"Welcome back! Your businesses earned %s while you were away (%s).",
						Format.cash(earned), Format.duration(seconds)))
				end
			end)
		end
	end
	data.lastOnline = os.time()
end

-- Rolls new customers for every shop, tells the client who is coming, and pays the
-- ones who have reached the till.
function EconomyService.serveCustomers(player: Player, profile: any, cache: Cache, now: number)
	local schedule = nextCustomer[player]
	if not schedule then
		schedule = {}
		nextCustomer[player] = schedule
	end
	local list = visits[player]
	if not list then
		list = {}
		visits[player] = list
	end

	local coming = {}
	for id, stats in cache.perBusiness do
		if stats.throughput > 0 and stats.income > 0 then
			local gap = 60 / stats.throughput
			local at = schedule[id]
			if not at or at < now - 5 then
				at = now + gap * rng:NextNumber() -- new shop, or the server stalled
			end
			local count = 0
			while at <= now and count < MAX_PER_ROLL do
				count += 1
				at += gap * rng:NextNumber(0.5, 1.5) -- averages one gap, so income is unchanged
			end
			schedule[id] = at
			if count > 0 then
				local amount = saleValue(stats) * count
				-- Attractions are paid at the door; shops when the customer walks out with their item.
				local definition = Businesses.get(id)
				local visit = if definition and definition.entryFee then 0 else Config.SHOP_VISIT_SECONDS
				table.insert(list, { due = now + Config.CUSTOMER_LEAD + visit, id = id, amount = amount })
				table.insert(coming, { id, count, amount })
			end
		else
			schedule[id] = nil
		end
	end
	if #coming > 0 then
		services.Net.fire(player, "Customers", coming, Config.CUSTOMER_LEAD)
	end

	local paid = false
	local i = 1
	while i <= #list do
		local visit = list[i]
		if visit.due <= now then
			local business = profile.data.businesses[visit.id]
			if business then -- still owned (prestige or a reset may have removed it)
				EconomyService.addMoney(player, visit.amount, true)
				business.earned = (business.earned or 0) + visit.amount
				paid = true
			end
			list[i] = list[#list]
			list[#list] = nil
		else
			i += 1
		end
	end
	if paid and now - (lastCheck[player] or 0) >= 1 then
		lastCheck[player] = now
		services.Progression.check(player)
	end
end

function EconomyService.init(registry: any)
	services = registry
end

function EconomyService.start()
	services.Data.onLoaded(onLoaded)
	Players.PlayerRemoving:Connect(function(player)
		caches[player] = nil
		nextCustomer[player] = nil
		visits[player] = nil
		lastCheck[player] = nil
	end)

	-- Customers: one loop for the whole server.
	task.spawn(function()
		while true do
			task.wait(Config.CUSTOMER_TICK)
			local now = os.clock()
			for player, cache in caches do
				local profile = if player.Parent then services.Data.get(player) else nil
				if profile then
					EconomyService.serveCustomers(player, profile, cache, now)
				end
			end
		end
	end)
end

return EconomyService
