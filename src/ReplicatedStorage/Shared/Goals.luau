--!strict
-- Goals: achievements (data only). Missions and daily quests were removed 2026-11-18.
-- Each goal is measured by a "metric" that ProgressionService knows how to read.
-- Container: ReplicatedStorage.Shared

local Businesses = require(script.Parent.Businesses)
local Config = require(script.Parent.Config)

local Goals = {}

local BUSINESS_COUNT = #Businesses.List
local DISTRICT_COUNT = #Config.Districts

export type Goal = {
	id: string?,
	name: string?,
	text: string,
	metric: string,
	param: string?,
	target: number,
	reward: number,
	emoji: string?,
}

Goals.Achievements = {
	{ id = "first_business", name = "Grand Opening", emoji = "🎉", text = "Own your first business", metric = "owned", target = 1, reward = 100 },
	{ id = "small_chain", name = "Small Chain", emoji = "🏪", text = "Own 3 businesses", metric = "owned", target = 3, reward = 1_500 },
	{ id = "monopoly", name = "Monopoly", emoji = "🏙️", text = "Own all " .. BUSINESS_COUNT .. " businesses", metric = "owned", target = BUSINESS_COUNT, reward = 250_000_000 },
	{ id = "main_street", name = "Main Street Mogul", emoji = "🏪", text = "Own 6 businesses", metric = "owned", target = 6, reward = 100_000 },
	{ id = "sweet_tooth", name = "Sweet Tooth", emoji = "🍦", text = "Get the Ice Cream Parlor to Level 10", metric = "specificLevel", param = "IceCream", target = 10, reward = 30_000_000 },
	{ id = "harbor_master", name = "Harbor Master", emoji = "⚓", text = "Buy the Aquarium", metric = "ownSpecific", param = "Aquarium", target = 1, reward = 50_000_000 },
	{ id = "tech_titan", name = "Tech Titan", emoji = "💻", text = "Buy the Tech Company", metric = "ownSpecific", param = "TechCompany", target = 1, reward = 200_000_000 },
	{ id = "pizza_master", name = "Pizza Master", emoji = "🍕", text = "Get the Pizza Restaurant to Level 10", metric = "specificLevel", param = "Pizza", target = 10, reward = 3_000_000 },
	{ id = "renovator", name = "Renovator", emoji = "🔨", text = "Buy 25 upgrades", metric = "upgradesBought", target = 25, reward = 3_000 },
	{ id = "makeover", name = "Makeover Maniac", emoji = "🛠️", text = "Buy 100 upgrades", metric = "upgradesBought", target = 100, reward = 400_000 },
	{ id = "designer", name = "Interior Designer", emoji = "🎨", text = "Max every decoration in one business", metric = "decorMax", target = 1, reward = 50_000 },
	{ id = "employer", name = "Big Employer", emoji = "👥", text = "Hire 10 employees", metric = "hires", target = 10, reward = 5_000 },
	{ id = "hands_on", name = "Hands-On Owner", emoji = "🙌", text = "Complete 100 mini games", metric = "served", target = 100, reward = 2_500 },
	{ id = "customer_hero", name = "Customer Hero", emoji = "🦸", text = "Complete 1,000 mini games", metric = "served", target = 1_000, reward = 100_000 },
	{ id = "money_machine", name = "Money Machine", emoji = "💸", text = "Earn $1,000/s", metric = "income", target = 1_000, reward = 100_000 },
	{ id = "cash_cannon", name = "Cash Cannon", emoji = "🚀", text = "Earn $100K/s", metric = "income", target = 100_000, reward = 15_000_000 },
	{ id = "millionaire", name = "Millionaire", emoji = "💰", text = "Earn $1M in total", metric = "lifetimeEarned", target = 1_000_000, reward = 50_000 },
	{ id = "billionaire", name = "Billionaire", emoji = "🤑", text = "Earn $1B in total", metric = "lifetimeEarned", target = 1_000_000_000, reward = 50_000_000 },
	{ id = "explorer", name = "City Explorer", emoji = "🗺️", text = "Own a business in all " .. DISTRICT_COUNT .. " districts", metric = "districtsOwned", target = DISTRICT_COUNT, reward = 300_000_000 },
	{ id = "empire", name = "Business Empire", emoji = "👑", text = "Reach the Business Empire rank", metric = "rank", target = 5, reward = 300_000_000 },
	{ id = "franchisor", name = "Fresh Start", emoji = "🌟", text = "Prestige once", metric = "prestige", target = 1, reward = 500 },
	{ id = "serial_founder", name = "Serial Founder", emoji = "🔁", text = "Prestige 5 times", metric = "prestige", target = 5, reward = 1_000_000 },
	{ id = "boom_town", name = "Boom Town", emoji = "👪", text = "Reach City Population 5", metric = "population", target = 5, reward = 400_000 },
	{ id = "metropolis", name = "Metropolis", emoji = "🌆", text = "Max out your City Population", metric = "population", target = Config.Population.maxLevel, reward = 60_000_000 },
} :: { Goal }

function Goals.formatText(goal: Goal, target: number, formatter: ((number) -> string)?): string
	local shown = if formatter then formatter(target) else tostring(target)
	return (goal.text:gsub("{target}", shown))
end

return Goals
