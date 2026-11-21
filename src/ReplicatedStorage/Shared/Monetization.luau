--!strict
-- Monetization: the game passes and cash packs sold in the Store (data only).
-- Create each one on the Creator Dashboard (the experience > Monetization > Passes, or
-- Developer Products), then paste its ID below. Anything with id = 0 shows as "Coming
-- soon" in the Store and is ignored by the server, so the game works before they exist.
-- Prices are set on the Creator Dashboard; the Store reads them from Roblox
-- (suggestedPrice is only the price marketing/store/README.md recommends).
-- Container: ReplicatedStorage.Shared

local Monetization = {}

export type Pass = {
	key: string,
	id: number,
	name: string,
	emoji: string,
	icon: string,
	color: Color3,
	desc: string,
	suggestedPrice: number,
}

export type Pack = {
	key: string,
	id: number,
	name: string,
	emoji: string,
	icon: string,
	color: Color3,
	minutes: number, -- the pack pays this many minutes of the player's current income...
	minimum: number, -- ...but never less than this
	suggestedPrice: number,
}

Monetization.Passes = {
	{
		key = "DoubleCash", id = 0, name = "2× Cash", emoji = "💰", icon = "rbxassetid://89267825858001",
		color = Color3.fromRGB(255, 185, 0), suggestedPrice = 199,
		desc = "Every shop earns double, forever. Mini games and offline earnings too!",
	},
	{
		key = "VIP", id = 0, name = "VIP", emoji = "⭐", icon = "rbxassetid://87880162965828",
		color = Color3.fromRGB(140, 30, 240), suggestedPrice = 149,
		desc = "+50% cash from every mini game, and a golden [⭐ VIP] tag in chat.",
	},
	{
		key = "OfflineBoost", id = 0, name = "Offline Tycoon", emoji = "💤", icon = "rbxassetid://138525712797372",
		color = Color3.fromRGB(0, 150, 250), suggestedPrice = 99,
		desc = "Earn while you're away for up to 8 hours (not 2), at full speed (not half).",
	},
} :: { Pass }

Monetization.Packs = {
	{
		key = "CashSmall", id = 0, name = "Stack of Cash", emoji = "💵", icon = "rbxassetid://88694661500877",
		color = Color3.fromRGB(105, 225, 0), minutes = 10, minimum = 5_000, suggestedPrice = 25,
	},
	{
		key = "CashMedium", id = 0, name = "Bag of Cash", emoji = "💰", icon = "rbxassetid://104524954351557",
		color = Color3.fromRGB(0, 150, 250), minutes = 60, minimum = 25_000, suggestedPrice = 99,
	},
	{
		key = "CashLarge", id = 0, name = "Vault of Cash", emoji = "🏦", icon = "rbxassetid://107813190306329",
		color = Color3.fromRGB(140, 30, 240), minutes = 360, minimum = 150_000, suggestedPrice = 299,
	},
} :: { Pack }

-- What the passes do.
Monetization.DOUBLE_CASH_MULTIPLIER = 2 -- all income (customers, mini games, offline)
Monetization.VIP_MINIGAME_BONUS = 1.5 -- mini-game pay
Monetization.OFFLINE_BOOST_CAP_SECONDS = 8 * 60 * 60 -- instead of Config.OFFLINE_CAP_SECONDS
Monetization.OFFLINE_BOOST_RATE = 1 -- instead of Config.OFFLINE_RATE

-- The cash a pack pays a player who earns `incomePerSecond` right now.
function Monetization.packAmount(pack: Pack, incomePerSecond: number): number
	return math.floor(math.max(pack.minimum, incomePerSecond * pack.minutes * 60))
end

function Monetization.passByKey(key: string): Pass?
	for _, pass in Monetization.Passes do
		if pass.key == key then
			return pass
		end
	end
	return nil
end

function Monetization.passById(id: number): Pass?
	for _, pass in Monetization.Passes do
		if pass.id ~= 0 and pass.id == id then
			return pass
		end
	end
	return nil
end

function Monetization.packById(id: number): Pack?
	for _, pack in Monetization.Packs do
		if pack.id ~= 0 and pack.id == id then
			return pack
		end
	end
	return nil
end

return Monetization
