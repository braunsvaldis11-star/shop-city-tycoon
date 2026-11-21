--!strict
-- MonetizationService: game passes and cash packs (Robux purchases).
--  * Game passes: ownership is asked from Roblox when a player joins, and set at once when
--    they buy one in game. It is never saved by us; Roblox is the record.
--  * Cash packs (developer products): ProcessReceipt adds the cash and records the receipt
--    in the player's data, then saves straight away. Roblox is only told the purchase is
--    granted once that save worked, so a purchase is never lost or paid out twice.
--  * Studio test mode: Config.STUDIO_TEST_PASSES lists passes to treat as owned, so their
--    effects can be tested without buying anything.
-- Container: ServerScriptService.Services

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Monetization = require(Shared.Monetization)

local MonetizationService = {}

local services: any
local owned: { [Player]: { [string]: boolean } } = {}

local RECEIPTS_KEPT = 50 -- newest receipt IDs remembered per player
local CHECK_TIMEOUT = 10 -- seconds a join waits for Roblox to answer the pass checks

function MonetizationService.has(player: Player, key: string): boolean
	local passes = owned[player]
	return passes ~= nil and passes[key] == true
end

-- For the state snapshot: the keys of the passes this player owns, sorted.
function MonetizationService.ownedKeys(player: Player): { string }
	local keys = {}
	for key in owned[player] or {} do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

function MonetizationService.incomeMultiplier(player: Player): number
	return if MonetizationService.has(player, "DoubleCash") then Monetization.DOUBLE_CASH_MULTIPLIER else 1
end

function MonetizationService.miniGameBonus(player: Player): number
	return if MonetizationService.has(player, "VIP") then Monetization.VIP_MINIGAME_BONUS else 1
end

-- Offline earnings: (cap in seconds, share of live income).
function MonetizationService.offlineTerms(player: Player): (number, number)
	if MonetizationService.has(player, "OfflineBoost") then
		return Monetization.OFFLINE_BOOST_CAP_SECONDS, Monetization.OFFLINE_BOOST_RATE
	end
	return Config.OFFLINE_CAP_SECONDS, Config.OFFLINE_RATE
end

local function setOwned(player: Player, key: string)
	local passes = owned[player]
	if not passes then
		passes = {}
		owned[player] = passes
	end
	if passes[key] then
		return
	end
	passes[key] = true
	if key == "VIP" then
		player:SetAttribute("VIP", true) -- clients add the chat tag
	elseif key == "DoubleCash" then
		services.Economy.recompute(player)
	end
	services.Sync.mark(player)
end

-- Asks Roblox which passes this player owns. Yields until every check has answered (or
-- CHECK_TIMEOUT), so offline earnings on join already include the passes.
function MonetizationService.loadPasses(player: Player)
	local studioTest = RunService:IsStudio() and Config.STUDIO_TEST_MODE
	local pending = 0
	for _, pass in Monetization.Passes do
		if studioTest and table.find(Config.STUDIO_TEST_PASSES, pass.key) then
			setOwned(player, pass.key)
		elseif pass.id ~= 0 then
			pending += 1
			task.spawn(function()
				for attempt = 1, 3 do
					local ok, result = pcall(function()
						return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
					end)
					if ok then
						if result == true and player.Parent then
							setOwned(player, pass.key)
						end
						break
					end
					warn(string.format("[Monetization] pass check %d failed for %s: %s", attempt, player.Name, tostring(result)))
					task.wait(attempt * 2)
				end
				pending -= 1
			end)
		end
	end
	local deadline = os.clock() + CHECK_TIMEOUT
	while pending > 0 and os.clock() < deadline and player.Parent do
		task.wait(0.1)
	end
end

-- Keep only the newest RECEIPTS_KEPT receipt IDs.
local function trimReceipts(receipts: { [string]: number })
	local list = {}
	for id, time in receipts do
		table.insert(list, { id = id, time = time })
	end
	if #list <= RECEIPTS_KEPT then
		return
	end
	table.sort(list, function(a, b)
		return a.time > b.time
	end)
	for i = RECEIPTS_KEPT + 1, #list do
		receipts[list[i].id] = nil
	end
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local pack = Monetization.packById(receipt.ProductId)
	if not pack then
		warn("[Monetization] receipt for an unknown product: " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local profile = if player then services.Data.get(player) else nil
	if not player or not profile then
		-- Left, or still loading: Roblox tries again later (also on their next join).
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local receipts = profile.data.receipts
	local purchaseId = tostring(receipt.PurchaseId)
	if receipts[purchaseId] == nil then
		local amount = Monetization.packAmount(pack, services.Economy.getCache(player).total)
		services.Economy.addMoney(player, amount, false) -- bought cash does not count toward rank
		receipts[purchaseId] = os.time()
		trimReceipts(receipts)
		services.Sync.mark(player)
		services.Net.fire(player, "CashPopup", amount, "reward")
		services.Net.notify(player, "reward", pack.emoji .. " Thank you! You got " .. Format.cash(amount) .. ".")
	end
	if services.Data.storeStatus() == "test" then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- Studio test purchase: nothing is saved
	end
	if services.Data.saveNow(player) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function MonetizationService.init(registry: any)
	services = registry
end

function MonetizationService.start()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		if not purchased then
			return
		end
		local pass = Monetization.passById(passId)
		if pass and not MonetizationService.has(player, pass.key) then
			setOwned(player, pass.key)
			services.Net.notify(player, "reward", "🎉 Thank you! " .. pass.name .. " is now active.")
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
	end)
end

return MonetizationService
