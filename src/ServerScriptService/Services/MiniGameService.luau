--!strict
-- MiniGameService: the owner's hands-on mini games inside their own business (make
-- the pizza, pack the groceries, count the cash...). This replaced the old "Serve
-- Customer" button, which paid for one key press.
--  * The server makes every order with its own random numbers (MiniGames.makeOrder)
--    and remembers it under a one-time token.
--  * The answer is checked against that order, and a game finished faster than a
--    real player could is refused, so a script gains nothing over playing.
--  * The pay is one sale of that business times the grade (PERFECT x2, GREAT x1.5,
--    GOOD x1). The client only reports mistakes, which can only lower the pay.
-- Container: ServerScriptService.Services

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Businesses = require(Shared.Businesses)
local MiniGames = require(Shared.MiniGames)

local MiniGameService = {}

local services: any
local rng = Random.new()

type Session = { token: string, businessId: string, order: MiniGames.Order, startedAt: number }
local sessions: { [Player]: Session } = {}
local lastStart: { [Player]: number } = {}

local START_COOLDOWN = 0.4 -- seconds between new orders
local SESSION_TIMEOUT = 180 -- an order left open longer than this pays nothing
local MIN_REWARD = 10

-- One average sale of this business (the same value its customers pay).
local function saleValue(player: Player, businessId: string): number
	local stats = services.Economy.getCache(player).perBusiness[businessId]
	if not stats or stats.income <= 0 then
		return 0
	end
	return stats.income * 60 / math.max(stats.throughput, 0.01)
end

local function ownsAndInside(player: Player, businessId: string): boolean
	local profile = services.Data.get(player)
	return profile ~= nil
		and profile.data.businesses[businessId] ~= nil
		and services.Interior.getInsideBusiness(player) == businessId
end

-- A new order for the business the player is standing in.
function MiniGameService.begin(player: Player, businessId: any)
	if type(businessId) ~= "string" or not Businesses.get(businessId) then
		return
	end
	if not ownsAndInside(player, businessId) then
		return
	end
	local now = os.clock()
	if now - (lastStart[player] or 0) < START_COOLDOWN then
		return
	end
	lastStart[player] = now
	local order = MiniGames.makeOrder(MiniGames.get(businessId), rng)
	local token = HttpService:GenerateGUID(false)
	sessions[player] = { token = token, businessId = businessId, order = order, startedAt = now }
	services.Net.fire(player, "MiniGameOrder", token, businessId, order, math.floor(saleValue(player, businessId)))
end

function MiniGameService.submit(player: Player, token: any, answer: any, mistakes: any)
	local session = sessions[player]
	if not session or type(token) ~= "string" or token ~= session.token then
		return
	end
	sessions[player] = nil -- one answer per order
	local function refuse()
		services.Net.fire(player, "MiniGameResult", token, false, 0, 0)
	end
	local elapsed = os.clock() - session.startedAt
	if elapsed > SESSION_TIMEOUT or not ownsAndInside(player, session.businessId) then
		return refuse()
	end
	local ok, hits = MiniGames.check(session.order, answer)
	if not ok or elapsed < MiniGames.minSeconds(session.order, answer) then
		return refuse()
	end
	local misses = if type(mistakes) == "number" and mistakes == mistakes then math.clamp(math.floor(mistakes), 0, 99) else 99
	local gradeIndex = MiniGames.grade(session.order, misses, hits)
	local grade = MiniGames.GRADES[gradeIndex]
	local reward = math.max(MIN_REWARD, math.floor(saleValue(player, session.businessId) * grade.multiplier))

	local profile = services.Data.get(player)
	services.Economy.addMoney(player, reward, true)
	profile.data.stats.served += 1
	services.Progression.check(player)
	services.Sync.mark(player)
	services.Net.fire(player, "CashPopup", reward, "serve")
	services.Net.fire(player, "MiniGameResult", token, true, reward, gradeIndex)
end

function MiniGameService.init(registry: any)
	services = registry
end

function MiniGameService.start()
	local Net = services.Net
	Net.declare("MiniGameOrder")
	Net.declare("MiniGameResult")
	Net.on("MiniGameStart", 3, function(player, businessId)
		MiniGameService.begin(player, businessId)
	end)
	Net.on("MiniGameSubmit", 3, function(player, token, answer, mistakes)
		MiniGameService.submit(player, token, answer, mistakes)
	end)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		lastStart[player] = nil
	end)
end

return MiniGameService
