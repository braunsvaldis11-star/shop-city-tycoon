--!strict
-- UIPanels (client): contents of each page in the menu window.
-- Businesses has two levels: a scrollable list of every business, and a detail page
-- (stats, level up, upgrade categories) that slides in when a card is pressed.
-- Every button only SENDS a request; the server validates and answers with a new state
-- snapshot. Panels.signature tells the controller whether a snapshot changes what the
-- open page shows (then it re-renders); otherwise the updater returned by render
-- refreshes live numbers in place, so hover animations and scrolling stay smooth.
-- Container: StarterPlayerScripts.Controllers

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Businesses = require(Shared.Businesses)
local CityLayout = require(Shared.CityLayout)
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Goals = require(Shared.Goals)
local Client = ReplicatedStorage:WaitForChild("Client")
local UIKit = require(Client:WaitForChild("UIKit"))
local Icons = require(Client:WaitForChild("Icons"))

local C = UIKit.Colors
local new = UIKit.new

local Panels = {}

export type Updater = (state: any) -> ()

Panels.Tabs = {
	{ id = "Businesses", name = "Businesses", short = "Shops", emoji = "🏪", color = C.Green, theme = "Lime" },
	{ id = "Map", name = "City Map", short = "Map", emoji = "🗺️", color = C.Blue, theme = "Cyan" },
	{ id = "Prestige", name = "Prestige", short = "Prestige", emoji = "🌟", color = C.Purple, theme = "Purple" },
	{ id = "Achievements", name = "Awards", short = "Awards", emoji = "🏆", color = Color3.fromRGB(235, 30, 140), theme = "Magenta" },
	{ id = "Settings", name = "Settings", short = "Settings", emoji = "⚙️", color = C.Grey, theme = "Silver" },
}

function Panels.getTab(id: string): any
	for _, tab in Panels.Tabs do
		if tab.id == id then
			return tab
		end
	end
	return Panels.Tabs[1]
end

local mapConnections: { RBXScriptConnection } = {}
local prestigeArmedUntil = 0

local SORTED = table.clone(Businesses.List)
table.sort(SORTED, function(a, b)
	return a.order < b.order
end)

local SKY = Color3.fromRGB(190, 225, 255)

----- Small building blocks -----
local function scroll(parent: Instance, layout: Instance?): ScrollingFrame
	local frame = new("ScrollingFrame", {
		Name = "Scroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.Highlight,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.Always,
		Selectable = false,
		Parent = parent,
	})
	;(layout or UIKit.list(Enum.FillDirection.Vertical, 8)).Parent = frame
	new("UIPadding", {
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 4),
		Parent = frame,
	})
	return frame
end

local function row(parent: Instance, height: number, order: number, color: Color3?): Frame
	return UIKit.card({
		Name = "Row" .. order,
		Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = order,
		BackgroundColor3 = color or C.PanelLight,
		Parent = parent,
	})
end

local function text(parent: Instance, value: string, x: number, y: number, w: number, h: number, size: number?, color: Color3?, body: boolean?): TextLabel
	return UIKit.label({
		Text = value,
		Font = if body then UIKit.BodyFont else UIKit.Font,
		TextColor3 = color or C.Text,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.new(0, w, 0, h),
		MaxTextSize = size or 20,
		TextWrapped = true,
		Parent = parent,
	})
end

-- Right-aligned text whose right edge sits `right` px from the parent's right edge.
local function rightText(parent: Instance, value: string, right: number, y: number, w: number, h: number, size: number?, color: Color3?, body: boolean?): TextLabel
	local label = text(parent, value, 0, y, w, h, size, color, body)
	label.AnchorPoint = Vector2.new(1, 0)
	label.Position = UDim2.new(1, -right, 0, y)
	label.TextXAlignment = Enum.TextXAlignment.Right
	return label
end

local function businessIcon(definition: any, props: { [string]: any }): Frame
	props.Text = definition.emoji
	props.Image = Icons.business(definition.id)
	props.Color = props.Color or definition.theme.primary
	return UIKit.icon(props)
end

local function chevron(face: Instance)
	UIKit.label({
		Name = "Chevron",
		Text = "▶",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(20, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Muted,
		MaxTextSize = 20,
		Parent = face,
	})
end

local function waypoint(ctx: any, id: string)
	ctx.controllers.City.setWaypoint(id)
	ctx.ui.close()
end

local function ownedIds(state: any): { string }
	local ids = {}
	for _, definition in SORTED do
		if state.businesses[definition.id] then
			table.insert(ids, definition.id)
		end
	end
	return ids
end

local function districtName(definition: any): string
	local district = Config.getDistrict(definition.district)
	return if district then district.name else "City"
end

----- Businesses: list -----
local CARD_HEIGHT = 78
local FILTERS = {
	{ id = "All", name = "All" },
	{ id = "Mine", name = "My Shops" },
	{ id = "Sale", name = "For Sale" },
}

-- City Population: the city-wide upgrade (more pedestrians, more customers everywhere).
local function renderPopulation(list: Instance, ctx: any, order: number)
	local level = ctx.state.population or 0
	local P = Config.Population
	local card = row(list, 98, order, Color3.fromRGB(24, 56, 82))
	card.Name = "Population"
	UIKit.icon({ Text = "🏙️", Image = Icons.menu("Population"), Color = C.Blue, Size = UDim2.fromOffset(70, 70), Position = UDim2.fromOffset(12, 14), Parent = card })
	text(card, "City Population", 96, 8, 300, 26, 22)
	local effect = string.format("🚶 %d people on your streets  •  +%d%% customers  •  +%d%% income at every business",
		Config.pedestrianCount(level), math.round(P.customerBonus * level * 100), math.round(P.incomeBonus * level * 100))
	text(card, effect, 96, 36, 390, 30, 13, SKY, true)
	local _, set = UIKit.progressBar({
		Size = UDim2.fromOffset(300, 18),
		Position = UDim2.fromOffset(96, 70),
		Text = string.format("Level %d / %d", level, P.maxLevel),
		MaxTextSize = 12,
		Parent = card,
	})
	set(level / P.maxLevel)
	local buttonProps: { [string]: any } = {
		Name = "GrowPopulation",
		Size = UDim2.fromOffset(176, 64),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		MaxTextSize = 20,
		Parent = card,
	}
	if level >= P.maxLevel then
		buttonProps.Text = "MAX"
		buttonProps.Color = C.Gold
		UIKit.button(buttonProps)
	else
		local cost = Config.populationCost(level)
		buttonProps.Text = "Grow City\n" .. Format.cash(cost)
		buttonProps.Color = C.Green
		local button = UIKit.button(buttonProps, function()
			ctx.controllers.Store.send("GrowPopulation")
		end)
		ctx.ui.registerCostButton(button, cost, C.Green)
	end
end

local function ownedCard(list: Instance, ctx: any, definition: any, order: number)
	local biz = ctx.state.businesses[definition.id]
	local _, face = UIKit.cardButton({
		Name = definition.id,
		Size = UDim2.new(1, 0, 0, CARD_HEIGHT),
		LayoutOrder = order,
		Parent = list,
	}, function()
		ctx.ui.openBusiness(definition.id)
	end)
	local accent = new("Frame", {
		Name = "Accent",
		BackgroundColor3 = definition.theme.primary,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 6, 1, -16),
		Position = UDim2.fromOffset(8, 8),
		Parent = face,
	})
	UIKit.corner(3).Parent = accent
	businessIcon(definition, { Size = UDim2.fromOffset(60, 60), Position = UDim2.fromOffset(22, 9), Parent = face })
	text(face, definition.name, 96, 8, 300, 26, 22)
	text(face, string.format("Level %d  •  %s", biz.level, districtName(definition)), 96, 36, 300, 18, 14, C.Muted, true)
	local _, set = UIKit.progressBar({ Size = UDim2.fromOffset(220, 8), Position = UDim2.fromOffset(96, 60), Parent = face })
	set(biz.level / Config.MAX_BUSINESS_LEVEL)
	rightText(face, Format.cash(if biz.stats then biz.stats.income else 0) .. "/s", 44, 12, 220, 30, 26, C.Money)
	rightText(face, if ctx.state.inside == definition.id then "📍 You're inside" else "Tap to upgrade", 44, 46, 220, 18, 13, C.Muted, true)
	chevron(face)
end

local function saleCard(list: Instance, ctx: any, definition: any, order: number): (number) -> ()
	local _, face = UIKit.cardButton({
		Name = definition.id,
		Size = UDim2.new(1, 0, 0, CARD_HEIGHT),
		LayoutOrder = order,
		Parent = list,
	}, function()
		ctx.ui.openBusiness(definition.id)
	end)
	businessIcon(definition, { Size = UDim2.fromOffset(60, 60), Position = UDim2.fromOffset(12, 9), Parent = face })
	text(face, definition.name, 86, 8, 300, 26, 22)
	text(face, "📍 " .. districtName(definition), 86, 36, 300, 18, 14, C.Muted, true)
	local income = Formulas.startingIncome(definition, ctx.state.prestige, ctx.state.population)
	text(face, "Earns about " .. Format.cash(income) .. "/s", 86, 56, 300, 16, 13, SKY, true)
	local starter = ctx.state.starterShop == definition.id
	local price = rightText(face, Format.cash(definition.price), 44, 12, 220, 30, 26)
	local status = rightText(face, "", 44, 46, 220, 18, 13, C.Muted, true)
	chevron(face)
	return function(money: number)
		local can = money >= definition.price
		price.TextColor3 = if can then C.Money else C.Text
		if starter then
			status.Text = if can then "🎁 Your first shop - buy it!" else "🎁 Your first shop"
			status.TextColor3 = SKY
			return
		end
		status.Text = if can then "✅ You can buy it!" else "Need " .. Format.cash(definition.price - money) .. " more"
		status.TextColor3 = if can then C.Money else C.Muted
	end
end

local function sectionTitle(list: Instance, title: string, order: number)
	local holder = new("Frame", { Name = "Section" .. order, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = order, Parent = list })
	text(holder, title, 4, 4, 420, 22, 20, C.Muted)
end

local function renderList(container: Frame, ctx: any): Updater
	local state = ctx.state
	local filter = ctx.view.filter
	local owned = ownedIds(state)

	local top = new("Frame", { Name = "Top", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), Parent = container })
	text(top, string.format("%d / %d businesses", #owned, #SORTED), 2, 0, 300, 24, 22)
	text(top, "Total income " .. Format.cash(state.income) .. "/s", 2, 26, 300, 18, 15, C.Money, true)
	local chips = new("Frame", {
		Name = "Filters",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -2, 0, 3),
		Size = UDim2.fromOffset(3 * 118 + 12, 40),
		Parent = top,
	})
	UIKit.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right).Parent = chips
	for i, f in FILTERS do
		UIKit.button({
			Name = "Filter_" .. f.id,
			Text = f.name,
			Color = if filter == f.id then C.Green else C.PanelLight,
			Size = UDim2.fromOffset(118, 40),
			LayoutOrder = i,
			MaxTextSize = 17,
			Parent = chips,
		}, function()
			ctx.ui.setFilter(f.id)
		end)
	end

	local holder = new("Frame", { Name = "ListHolder", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 1, -54), Parent = container })
	local list = scroll(holder)
	local live: { (number) -> () } = {}
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	if filter ~= "Sale" then
		renderPopulation(list, ctx, nextOrder())
		if #owned > 0 then
			sectionTitle(list, "🏪 My Businesses", nextOrder())
			for _, id in owned do
				ownedCard(list, ctx, Businesses.get(id), nextOrder())
			end
		elseif filter == "Mine" then
			local card = row(list, 112, nextOrder())
			text(card, "🍕 You don't own a business yet!", 16, 14, 460, 30, 24)
			local starter = Businesses.get(Formulas.STARTER_ID)
			text(card, string.format("You have the cash for your first shop! Walk to the %s door and hold E (or tap the prompt) to buy it.", starter.name), 16, 50, 440, 44, 14, C.Muted, true)
			UIKit.button({ Name = "LocatePizza", Text = "📍 Show me", Color = C.Green, Size = UDim2.fromOffset(170, 58), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), MaxTextSize = 20, Parent = card }, function()
				waypoint(ctx, Formulas.STARTER_ID)
			end)
		end
	end
	if filter ~= "Mine" then
		local any = false
		for _, definition in SORTED do
			if not state.businesses[definition.id] then
				if not any then
					any = true
					sectionTitle(list, "🏷️ For Sale", nextOrder())
				end
				table.insert(live, saleCard(list, ctx, definition, nextOrder()))
			end
		end
		if not any and filter == "Sale" then
			local card = row(list, 70, nextOrder())
			text(card, "🏆 You own every business in the city!", 16, 20, 600, 30, 24, C.Gold)
		end
	end

	local function update(_state: any)
		local money = ctx.controllers.Store.money()
		for _, fn in live do
			fn(money)
		end
	end
	update(state)
	return update
end

----- Businesses: detail page -----
local BOTTLENECK = {
	Customers = { hint = "Not enough customers. Buy Marketing or level up.", category = "Marketing" },
	Seats = { hint = "Out of seats. Add more tables.", category = "Dining" },
	Service = { hint = "Lines are long. Hire cashiers or train staff.", category = "Employees" },
	Production = { hint = "Production is too slow. Add stations and workers.", category = "Kitchen" },
}

local function detailTop(container: Frame, ctx: any, definition: any, biz: any)
	local bar = UIKit.card({
		Name = "DetailTop",
		Size = UDim2.new(1, 0, 0, 82),
		BackgroundColor3 = definition.theme.primary:Lerp(C.PanelLight, 0.72),
		Parent = container,
	})
	UIKit.button({ Name = "Back", Text = "◀ Back", Color = C.Grey, Size = UDim2.fromOffset(96, 52), Position = UDim2.fromOffset(12, 15), MaxTextSize = 18, Parent = bar }, function()
		ctx.ui.openBusiness(nil)
	end)
	businessIcon(definition, { Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(122, 9), Parent = bar })
	text(bar, definition.name, 198, 10, 215, 32, 28)
	local sub = if biz
		then string.format("Level %d / %d  •  %s", biz.level, Config.MAX_BUSINESS_LEVEL, districtName(definition))
		else "For sale  •  " .. districtName(definition)
	text(bar, sub, 198, 46, 215, 20, 15, C.Muted, true)
	if biz then
		local ids = ownedIds(ctx.state)
		local index = table.find(ids, definition.id) or 1
		local right = 16
		if #ids > 1 then
			right = 120
			UIKit.button({ Name = "PrevBusiness", Text = "◀", Color = C.PanelLight, Size = UDim2.fromOffset(46, 52), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -64, 0, 15), MaxTextSize = 20, Parent = bar }, function()
				ctx.ui.switchBusiness(ids[((index - 2) % #ids) + 1], -1)
			end)
			UIKit.button({ Name = "NextBusiness", Text = "▶", Color = C.PanelLight, Size = UDim2.fromOffset(46, 52), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 15), MaxTextSize = 20, Parent = bar }, function()
				ctx.ui.switchBusiness(ids[(index % #ids) + 1], 1)
			end)
		end
		rightText(bar, Format.cash(if biz.stats then biz.stats.income else 0) .. "/s", right, 12, 180, 34, 30, C.Money)
		rightText(bar, "income per second", right, 48, 180, 18, 13, C.Muted, true)
	else
		rightText(bar, Format.cash(definition.price), 16, 12, 220, 34, 30)
		rightText(bar, "price", 16, 48, 220, 18, 13, C.Muted, true)
	end
end

local function renderOverview(list: Instance, ctx: any, definition: any, biz: any): Updater
	local stats = biz.stats or Formulas.computeStats(definition, biz, ctx.state.prestige, ctx.state.population)

	-- Level card
	local levelRow = row(list, 106, 1)
	UIKit.icon({ Text = "⭐", Color = C.Purple, Size = UDim2.fromOffset(70, 70), Position = UDim2.fromOffset(12, 18), Parent = levelRow })
	text(levelRow, "Business Level", 96, 10, 300, 28, 24)
	local _, setLevel = UIKit.progressBar({
		Size = UDim2.fromOffset(330, 22),
		Position = UDim2.fromOffset(96, 44),
		Text = string.format("%d / %d", biz.level, Config.MAX_BUSINESS_LEVEL),
		MaxTextSize = 15,
		Parent = levelRow,
	})
	setLevel(biz.level / Config.MAX_BUSINESS_LEVEL)
	text(levelRow, "+25% income per level and unlocks higher upgrades.", 96, 74, 340, 20, 13, C.Muted, true)
	local levelProps: { [string]: any } = {
		Name = "LevelUp",
		Size = UDim2.fromOffset(196, 70),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		MaxTextSize = 22,
		Parent = levelRow,
	}
	if biz.level >= Config.MAX_BUSINESS_LEVEL then
		levelProps.Text = "MAX LEVEL"
		levelProps.Color = C.Gold
		UIKit.button(levelProps)
	else
		local cost = Formulas.levelUpCost(definition, biz.level)
		levelProps.Text = "Level Up\n" .. Format.cash(cost)
		levelProps.Color = C.Green
		local button = UIKit.button(levelProps, function()
			ctx.controllers.Store.send("LevelUpBusiness", definition.id)
		end)
		ctx.ui.registerCostButton(button, cost, C.Green)
	end

	-- Stats grid (the bottleneck is outlined in orange)
	local grid = new("Frame", { Name = "StatsGrid", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 160), LayoutOrder = 2, Parent = list })
	new("UIGridLayout", { CellSize = UDim2.new(0.25, -6, 0, 76), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	local entries = {
		{ key = "Income", label = "💵 Income", value = Format.cash(stats.income) .. "/s", color = C.Money },
		{ key = "Customers", label = "🚶 Customers", value = string.format("%.1f/min", stats.customers), color = Color3.fromRGB(120, 200, 255) },
		{ key = "Seats", label = "🪑 Seats", value = string.format("%d/min", math.floor(stats.seats)), color = Color3.fromRGB(255, 190, 100) },
		{ key = "Service", label = "💳 Service", value = string.format("%.1f/min", stats.service), color = Color3.fromRGB(210, 160, 255) },
		{ key = "Production", label = "🔥 Production", value = string.format("%.1f/min", stats.production), color = Color3.fromRGB(255, 140, 120) },
		{ key = "Spend", label = "🧾 Avg. spend", value = Format.cash(stats.spend), color = C.Yellow },
		{ key = "Reputation", label = "⭐ Reputation", value = Format.percent(stats.reputation), color = C.Gold },
		{ key = "Earned", label = "💰 Earned", value = Format.money(biz.earned or 0), color = C.Money },
	}
	local earnedLabel: TextLabel? = nil
	for i, entry in entries do
		local isNeck = entry.key == stats.bottleneck
		local cell = UIKit.card({ Name = entry.key, LayoutOrder = i, BackgroundColor3 = if isNeck then Color3.fromRGB(72, 42, 16) else C.PanelLight, Parent = grid })
		if isNeck then
			local rim = cell:FindFirstChild("Rim") :: UIStroke
			rim.Color = C.Orange
			rim.Transparency = 0
			rim.Thickness = 2.5
		end
		text(cell, entry.label, 10, 8, 150, 18, 14, C.Muted, true)
		local value = text(cell, entry.value, 10, 32, 150, 34, 26, entry.color)
		if entry.key == "Earned" then
			earnedLabel = value
		end
	end

	-- Bottleneck tip with a shortcut to the right upgrades
	local neck = BOTTLENECK[stats.bottleneck]
	if neck then
		local hint = row(list, 60, 3, Color3.fromRGB(80, 50, 20))
		text(hint, "⚠️ Bottleneck: " .. stats.bottleneck, 14, 7, 420, 24, 19, Color3.fromRGB(255, 210, 120))
		text(hint, neck.hint, 14, 34, 460, 18, 14, Color3.fromRGB(255, 230, 190), true)
		UIKit.button({ Name = "FixBottleneck", Text = "Fix it ▶", Color = C.Orange, Size = UDim2.fromOffset(130, 44), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), MaxTextSize = 18, Parent = hint }, function()
			ctx.ui.setCategory(neck.category)
		end)
	end

	local actions = row(list, 66, 4)
	UIKit.button({ Name = "Walk", Text = "📍 Walk there", Color = C.Blue, Size = UDim2.fromOffset(190, 50), Position = UDim2.fromOffset(10, 8), MaxTextSize = 18, Parent = actions }, function()
		waypoint(ctx, definition.id)
	end)
	text(actions, "Shoppers pay on the way out, attractions at the door. Fix the bottleneck first for the biggest boost.", 214, 13, 470, 40, 13, C.Muted, true)

	return function(state: any)
		local current = state.businesses[definition.id]
		if current and earnedLabel then
			earnedLabel.Text = Format.money(current.earned or 0)
		end
	end
end

local function renderUpgradeRows(list: Instance, ctx: any, definition: any, biz: any, category: string)
	local order = 0
	for _, upgrade in Businesses.Upgrades do
		if upgrade.category == category then
			order += 1
			local level = biz.upgrades[upgrade.id] or 0
			local cap, requirement = Formulas.upgradeCap(upgrade, biz.level)
			local r = row(list, 102, order)
			r.Name = "Upgrade_" .. upgrade.id
			UIKit.icon({ Text = upgrade.emoji, Color = definition.theme.primary, Size = UDim2.fromOffset(66, 66), Position = UDim2.fromOffset(12, 18), Parent = r })
			text(r, Businesses.label(definition, upgrade.name), 90, 8, 330, 26, 21)
			local description = Businesses.label(definition, upgrade.desc)
			if upgrade.tiers then
				local current = upgrade.tiers[level + 1] or ""
				local nextTier = upgrade.tiers[level + 2]
				description = "Now: " .. current .. (if nextTier then "  →  Next: " .. nextTier else "") .. "\n" .. description
			end
			text(r, description, 90, 34, 360, 42, 14, C.Muted, true)
			-- Segmented level bar
			local segments = new("Frame", { Name = "Levels", BackgroundTransparency = 1, Size = UDim2.fromOffset(220, 12), Position = UDim2.fromOffset(90, 82), Parent = r })
			UIKit.list(Enum.FillDirection.Horizontal, 4).Parent = segments
			local each = math.floor((220 - (upgrade.max - 1) * 4) / upgrade.max)
			for i = 1, upgrade.max do
				local filled = i <= level
				local segment = new("Frame", {
					Size = UDim2.fromOffset(each, 12),
					BackgroundColor3 = if filled then Color3.new(1, 1, 1) else C.PanelDark,
					BorderSizePixel = 0,
					LayoutOrder = i,
					Parent = segments,
				})
				UIKit.stroke(C.Ink, 1.5).Parent = segment
				if filled then
					UIKit.gradient(Color3.fromRGB(180, 255, 25), Color3.fromRGB(105, 225, 0)).Parent = segment
				end
			end
			text(r, string.format("%d/%d", level, upgrade.max), 318, 78, 60, 20, 15, C.Muted)

			local buttonProps: { [string]: any } = {
				Name = "Up_" .. upgrade.id,
				Size = UDim2.fromOffset(180, 64),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				MaxTextSize = 20,
				Parent = r,
			}
			if level >= upgrade.max then
				buttonProps.Text = "✅ MAXED"
				buttonProps.Color = C.Gold
				UIKit.button(buttonProps)
			elseif level >= cap then
				buttonProps.Text = "🔒 Needs Lv " .. tostring(requirement or biz.level + 1)
				buttonProps.Color = C.Red
				UIKit.button(buttonProps, function()
					ctx.ui.notify("info", "Level up the business (Overview) to unlock this upgrade.")
				end)
			else
				local cost = Formulas.upgradeCost(definition, upgrade, level)
				local verb = if upgrade.category == "Employees" and upgrade.id ~= "training" then "Hire" else "Buy"
				buttonProps.Text = verb .. "\n" .. Format.cash(cost)
				buttonProps.Color = C.Green
				local button = UIKit.button(buttonProps, function()
					ctx.controllers.Store.send("UpgradeBusiness", definition.id, upgrade.id)
				end)
				ctx.ui.registerCostButton(button, cost, C.Green)
			end
		end
	end
end

local function renderForSale(container: Frame, ctx: any, definition: any): Updater
	local state = ctx.state
	local starter = state.starterShop == definition.id
	local income = Formulas.startingIncome(definition, state.prestige, state.population)
	local card = UIKit.card({ Name = "Info", Size = UDim2.new(1, 0, 0, 236), Position = UDim2.fromOffset(0, 92), Parent = container })
	businessIcon(definition, { Size = UDim2.fromOffset(150, 150), Position = UDim2.fromOffset(18, 18), Radius = 8, Parent = card })
	local facts = {
		{ "💰 Price", Format.cash(definition.price), C.Text },
		{ "📈 Income when opened", "about " .. Format.cash(income) .. "/s", C.Money },
		{ "⏱️ Pays for itself in", "about " .. Format.duration(definition.price / math.max(income, 0.01)), SKY },
		{ "📍 District", districtName(definition), C.Text },
	}
	for i, fact in facts do
		local y = 16 + (i - 1) * 38
		text(card, fact[1], 190, y + 4, 230, 20, 15, C.Muted, true)
		rightText(card, fact[2], 18, y, 280, 28, 22, fact[3])
	end
	text(card, "Your cash", 190, 172, 200, 18, 13, C.Muted, true)
	local _, set = UIKit.progressBar({ Size = UDim2.new(1, -208, 0, 26), Position = UDim2.fromOffset(190, 194), Text = "", MaxTextSize = 15, Parent = card })

	local actions = UIKit.card({ Name = "Actions", Size = UDim2.new(1, 0, 0, 132), Position = UDim2.fromOffset(0, 340), Parent = container })
	text(actions, if starter then "🎁 Your first shop!" else "How to buy it", 16, 14, 300, 26, 22)
	text(actions, "Walk to the " .. definition.name .. " door and hold E (or tap the prompt). The golden trail shows you the way.", 16, 46, 420, 64, 14, C.Muted, true)
	UIKit.button({ Name = "Locate", Text = "📍 Show the way", Color = C.Green, Size = UDim2.fromOffset(240, 70), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), MaxTextSize = 20, Parent = actions }, function()
		waypoint(ctx, definition.id)
	end)

	local function update(_state: any)
		local money = ctx.controllers.Store.money()
		set(money / definition.price, Format.cash(math.min(money, definition.price)) .. " / " .. Format.cash(definition.price))
	end
	update(state)
	return update
end

local function renderDetail(container: Frame, ctx: any, definition: any): Updater?
	local biz = ctx.state.businesses[definition.id]
	detailTop(container, ctx, definition, biz)
	if not biz then
		return renderForSale(container, ctx, definition)
	end
	local category = ctx.view.category
	local categories = { { id = "Overview", name = "Overview", emoji = "📊" } }
	for _, c in Businesses.Categories do
		table.insert(categories, { id = c.id, name = Businesses.categoryName(definition, c.id), emoji = c.emoji })
	end
	local chips = new("Frame", { Name = "Categories", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 54), Position = UDim2.fromOffset(0, 92), Parent = container })
	UIKit.list(Enum.FillDirection.Horizontal, 6).Parent = chips
	for i, cat in categories do
		UIKit.button({
			Name = "Cat_" .. cat.id,
			Text = cat.name,
			Emoji = cat.emoji,
			Stack = true,
			Color = if category == cat.id then C.Orange else C.PanelLight,
			Size = UDim2.new(1 / #categories, -5, 1, 0),
			LayoutOrder = i,
			MaxTextSize = 14,
			Parent = chips,
		}, function()
			ctx.ui.setCategory(cat.id)
		end)
	end
	local body = new("Frame", { Name = "Body", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -156), Position = UDim2.fromOffset(0, 156), Parent = container })
	local list = scroll(body)
	if category == "Overview" then
		return renderOverview(list, ctx, definition, biz)
	end
	renderUpgradeRows(list, ctx, definition, biz, category)
	return nil
end

local function renderBusinesses(container: Frame, ctx: any): Updater?
	local id = ctx.view.business
	local definition = if id then Businesses.get(id) else nil
	if definition then
		return renderDetail(container, ctx, definition)
	end
	return renderList(container, ctx)
end

----- Map tab -----
-- A zoomable, draggable plan of the whole city, north (-Z) up like a real top-down view.
-- Scroll / pinch / + - to zoom, drag to pan, click a shop for its card (Manage / Go).
-- Zoom, pan and the selected shop survive re-renders, so buying something keeps the view.
local MAP_MIN_X, MAP_MAX_X = CityLayout.BOUNDS.minX, CityLayout.BOUNDS.maxX
local MAP_MIN_Z, MAP_MAX_Z = CityLayout.BOUNDS.minZ, CityLayout.BOUNDS.maxZ
local MAP_TOOLBAR = 48
local MAP_VIEW = Vector2.new(720, 476 - MAP_TOOLBAR) -- the page is 720 x 476
local MAP_BASE = (function(): Vector2
	-- The whole city fits the view at zoom 1.
	local aspect = (MAP_MAX_X - MAP_MIN_X) / (MAP_MAX_Z - MAP_MIN_Z)
	local width, height = MAP_VIEW.X, MAP_VIEW.X / aspect
	if height > MAP_VIEW.Y then
		height = MAP_VIEW.Y
		width = height * aspect
	end
	return Vector2.new(math.floor(width), math.floor(height))
end)()
local MAP_ZOOM_MIN, MAP_ZOOM_MAX = 1, 5
local SEA = Color3.fromRGB(60, 160, 225)
local SAND = Color3.fromRGB(240, 220, 160)
local ASPHALT = Color3.fromRGB(84, 92, 110)
-- Map colour for each kind of block (anything else shows as plain sidewalk).
local BLOCK_COLORS: { [string]: Color3 } = {
	park = Color3.fromRGB(120, 205, 100),
	maplepark = Color3.fromRGB(120, 205, 100),
	field = Color3.fromRGB(100, 190, 90),
	pond = Color3.fromRGB(120, 205, 100),
	playground = Color3.fromRGB(130, 210, 110),
	plaza = Color3.fromRGB(240, 220, 170),
	market = Color3.fromRGB(240, 220, 170),
	exchange = Color3.fromRGB(240, 220, 170),
	parking = Color3.fromRGB(150, 155, 165),
	containers = Color3.fromRGB(190, 160, 120),
	quay = Color3.fromRGB(190, 145, 95),
}

local mapZoom = 1
local mapCentre = Vector2.new(0.5, 0.5) -- canvas fraction shown at the middle of the view
local mapSelected: string? = nil
local mapOpened = false -- the first time, the map opens zoomed in on the player
local mapTween: Tween? = nil

local function cleanupMap()
	for _, connection in mapConnections do
		connection:Disconnect()
	end
	table.clear(mapConnections)
end

-- Canvas fraction of a world position: +X to the right, +Z down (north = -Z is up).
local function mapFraction(position: Vector3): Vector2
	return Vector2.new(
		(position.X - MAP_MIN_X) / (MAP_MAX_X - MAP_MIN_X),
		(position.Z - MAP_MIN_Z) / (MAP_MAX_Z - MAP_MIN_Z)
	)
end

local function mapPoint(position: Vector3): UDim2
	local fraction = mapFraction(position)
	return UDim2.fromScale(fraction.X, fraction.Y)
end

local function within(gui: GuiObject, point: Vector2): boolean
	local position, size = gui.AbsolutePosition, gui.AbsoluteSize
	return point.X >= position.X and point.Y >= position.Y and point.X <= position.X + size.X and point.Y <= position.Y + size.Y
end

-- Real map detail: building footprints with a soft shadow, trees, ponds, pitches, piers
-- and boats, scanned from Workspace.City once. Every render clones the cached layer,
-- which is far cheaper than creating ~1,000 frames again.
local MAP_BUILDINGS = { Shop = true, GlassTower = true, Tower = true, House = true, Warehouse = true, StockExchange = true, Lighthouse = true }
local MAP_TREES: { [string]: Color3 } = { Tree = Color3.fromRGB(78, 168, 72), Pine = Color3.fromRGB(52, 132, 78) }
local MAP_PARTS: { [string]: Color3 } = {
	Pond = Color3.fromRGB(90, 185, 245),
	Pitch = Color3.fromRGB(95, 185, 85),
	ParkingLot = Color3.fromRGB(150, 156, 168),
	Pier = Color3.fromRGB(200, 160, 110),
	Boardwalk = Color3.fromRGB(200, 160, 110),
}
local MAP_SHADOW = 2.5 -- studs toward the south-east
local mapLayer: Frame? = nil
local shellBounds: { [string]: { number } } = {}

-- Axis-aligned world X/Z bounds of a (possibly rotated) box.
local function worldBounds(cf: CFrame, size: Vector3): (number, number, number, number)
	local half = size / 2
	local ex = math.abs(cf.RightVector.X) * half.X + math.abs(cf.UpVector.X) * half.Y + math.abs(cf.LookVector.X) * half.Z
	local ez = math.abs(cf.RightVector.Z) * half.X + math.abs(cf.UpVector.Z) * half.Y + math.abs(cf.LookVector.Z) * half.Z
	return cf.X - ex, cf.X + ex, cf.Z - ez, cf.Z + ez
end

-- What a building shows from above: its roof if it has one, else its biggest part.
local function topColor(model: Model): Color3
	local best: BasePart? = nil
	local bestScore = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.5 then
			local score = d.Size.X * d.Size.Z * (if string.find(d.Name, "Roof") then 4 else 1)
			if score > bestScore then
				best, bestScore = d, score
			end
		end
	end
	return if best then best.Color else Color3.fromRGB(225, 225, 232)
end

local function mapShape(parent: Instance, minX: number, maxX: number, minZ: number, maxZ: number, color: Color3, round: number?, z: number?): Frame
	local a = mapFraction(Vector3.new(minX, 0, minZ))
	local b = mapFraction(Vector3.new(maxX, 0, maxZ))
	local frame = new("Frame", {
		Position = UDim2.fromScale(a.X, a.Y),
		Size = UDim2.fromScale(b.X - a.X, b.Y - a.Y),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = z or 2,
		Parent = parent,
	})
	if round then
		new("UICorner", { CornerRadius = UDim.new(round, 0), Parent = frame })
	end
	return frame
end

local function building(layer: Instance, shadows: Instance, x0: number, x1: number, z0: number, z1: number, color: Color3)
	local shadow = mapShape(shadows, x0 + MAP_SHADOW, x1 + MAP_SHADOW, z0 + MAP_SHADOW, z1 + MAP_SHADOW, Color3.new(0, 0, 0), 0.1, 1)
	shadow.BackgroundTransparency = 0.72
	mapShape(layer, x0, x1, z0, z1, color, 0.1, 2)
end

local function buildMapLayer(): Frame?
	local city = Workspace:FindFirstChild("City")
	local blocks = city and city:FindFirstChild("Blocks")
	if not blocks then
		return nil
	end
	local layer = new("Frame", { Name = "Detail", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3 })
	local shadows = new("Frame", { Name = "Shadows", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = layer })
	for _, block in blocks:GetChildren() do
		for _, child in block:GetChildren() do
			if child:IsA("Model") then
				local tree = MAP_TREES[child.Name]
				if MAP_BUILDINGS[child.Name] then
					local cf, size = child:GetBoundingBox()
					local x0, x1, z0, z1 = worldBounds(cf, size)
					local color = topColor(child)
					if child.Name == "GlassTower" then
						color = color:Lerp(Color3.fromRGB(120, 190, 245), 0.55)
					end
					building(layer, shadows, x0, x1, z0, z1, color:Lerp(Color3.new(1, 1, 1), 0.12))
				elseif tree then
					local cf, size = child:GetBoundingBox()
					local r = math.min(size.X, size.Z) * 0.45
					mapShape(layer, cf.X - r, cf.X + r, cf.Z - r, cf.Z + r, tree, 0.5, 3)
				elseif child.Name == "Boat" then
					local cf, size = child:GetBoundingBox()
					local x0, x1, z0, z1 = worldBounds(cf, size)
					mapShape(layer, x0, x1, z0, z1, Color3.fromRGB(245, 245, 250), 0.45, 2)
				end
			elseif child:IsA("BasePart") then
				local color = MAP_PARTS[child.Name] or (if child.Name == "Container" then child.Color else nil)
				if color then
					local x0, x1, z0, z1 = worldBounds(child.CFrame, child.Size)
					local shape = mapShape(layer, x0, x1, z0, z1, color, if child.Name == "Pond" then 0.5 else nil, 1)
					if child.Name == "Pitch" then
						new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.5, Transparency = 0.2, Parent = shape })
					end
				end
			end
		end
	end
	return layer
end

local function renderMap(container: Frame, ctx: any)
	cleanupMap()
	local state = ctx.state
	local window = container:FindFirstAncestor("Menu") :: GuiObject?

	-- Toolbar: summary on the left, view buttons on the right.
	local bar = new("Frame", { Name = "MapToolbar", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, MAP_TOOLBAR - 6), Parent = container })
	text(bar, string.format("🗺️ %d / %d shops owned", #ownedIds(state), #SORTED), 4, 0, 330, 24, 20)
	text(bar, "🟩 Owned   ⬜ For sale   🔴 You   •   Scroll or pinch to zoom, drag to move", 4, 24, 420, 16, 13, C.Muted, true)

	local view = UIKit.card({
		Name = "MapView",
		BackgroundColor3 = SEA,
		Size = UDim2.fromOffset(MAP_VIEW.X, MAP_VIEW.Y),
		Position = UDim2.fromOffset(0, MAP_TOOLBAR),
		ClipsDescendants = true,
		Active = true, -- keeps the mouse wheel from zooming the camera while over the map
		Parent = container,
	})
	local rim = view:FindFirstChild("Rim") :: UIStroke
	rim.Color = C.Ink
	rim.Transparency = 0
	rim.Thickness = 3

	local canvas = new("Frame", { Name = "Canvas", BackgroundTransparency = 1, ZIndex = 1, Parent = view })
	-- Sea texture (Check-UI checker, very faint) and a compass.
	new("ImageLabel", {
		Name = "Waves",
		Image = "rbxassetid://385956923",
		ImageTransparency = 0.88,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(28, 28),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Parent = view,
	})
	local compass = new("Frame", { Name = "Compass", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = C.Panel, ZIndex = 15, Parent = view })
	UIKit.corner(17).Parent = compass
	UIKit.stroke(C.Ink, 2).Parent = compass
	UIKit.label({ Text = "N", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 18, ZIndex = 16, Parent = compass })

	local function rect(minX: number, maxX: number, minZ: number, maxZ: number, color: Color3, z: number?): Frame
		local a = mapFraction(Vector3.new(minX, 0, minZ))
		local b = mapFraction(Vector3.new(maxX, 0, maxZ))
		return new("Frame", {
			Position = UDim2.fromScale(a.X, a.Y),
			Size = UDim2.fromScale(b.X - a.X, b.Y - a.Y),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = z or 1,
			Parent = canvas,
		})
	end
	-- Land: asphalt under every district (roads show between the blocks), a beach on the coast.
	local coastMinZ, coastMaxZ = math.huge, -math.huge
	for _, district in Config.Districts do
		rect(math.max(district.minX, CityLayout.COAST_X), district.maxX, district.minZ, district.maxZ, ASPHALT, 1)
		if district.minX < CityLayout.COAST_X then
			coastMinZ = math.min(coastMinZ, district.minZ)
			coastMaxZ = math.max(coastMaxZ, district.maxZ)
		end
	end
	if coastMinZ < coastMaxZ then
		rect(CityLayout.COAST_X - 10, CityLayout.COAST_X, coastMinZ, coastMaxZ, SAND, 1)
	end
	for _, b in CityLayout.Blocks do
		local kindColor = BLOCK_COLORS[b[5]]
		local color = kindColor or Color3.fromRGB(225, 225, 232)
		if not kindColor and (b[6] == "houses" or b[6] == "luxury") then
			color = Color3.fromRGB(205, 230, 190)
		end
		rect(b[1], b[2], b[3], b[4], color, 2)
	end
	-- Real detail on top of the blocks, then the business buildings coloured by ownership.
	if not mapLayer then
		mapLayer = buildMapLayer()
	end
	local template = mapLayer
	if template then
		local detail = template:Clone()
		local shadows = detail:FindFirstChild("Shadows") :: Frame
		local cityFolder = Workspace:FindFirstChild("City")
		local lots = cityFolder and cityFolder:FindFirstChild("Businesses")
		for _, definition in SORTED do
			local bounds = shellBounds[definition.id]
			if not bounds then
				local model = lots and lots:FindFirstChild(definition.id)
				local shell = model and model:FindFirstChild("Shell")
				if shell and shell:IsA("Model") then
					local cf, size = shell:GetBoundingBox()
					local x0, x1, z0, z1 = worldBounds(cf, size)
					bounds = { x0, x1, z0, z1 }
					shellBounds[definition.id] = bounds
				end
			end
			if bounds then
				local primary = definition.theme.primary
				local color = if state.businesses[definition.id] then primary else primary:Lerp(Color3.fromRGB(205, 205, 215), 0.55)
				building(detail, shadows, bounds[1], bounds[2], bounds[3], bounds[4], color)
			end
		end
		detail.Parent = canvas
	end
	-- Each district outlined in its own colour, with a name tag on its north edge.
	for _, district in Config.Districts do
		local west = math.max(district.minX, CityLayout.COAST_X)
		local outline = rect(west, district.maxX, district.minZ, district.maxZ, district.color, 3)
		outline.BackgroundTransparency = 1
		local stroke = UIKit.stroke(district.color, 2)
		stroke.Transparency = 0.3
		stroke.Parent = outline
		local tag = new("Frame", {
			Name = "District_" .. district.id,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = mapPoint(Vector3.new((west + district.maxX) / 2, 0, district.minZ + 6)),
			Size = UDim2.fromOffset(108, 18),
			BackgroundColor3 = district.color:Lerp(Color3.new(0, 0, 0), 0.45),
			BackgroundTransparency = 0.1,
			ZIndex = 4,
			Parent = canvas,
		})
		UIKit.corner(9).Parent = tag
		UIKit.label({ Text = district.name, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 12, ZIndex = 5, Parent = tag })
	end

	-- Zoom and pan maths, in view units (the page's own pixels before UIScale).
	local function unitsPerPixel(): number
		local absolute = view.AbsoluteSize.X
		return if absolute > 0 then MAP_VIEW.X / absolute else 1
	end
	local function layout(animate: boolean?)
		local size = MAP_BASE * mapZoom
		local position = MAP_VIEW / 2 - mapCentre * size
		local function axis(p: number, s: number, v: number): number
			return if s <= v then (v - s) / 2 else math.clamp(p, v - s, 0)
		end
		position = Vector2.new(axis(position.X, size.X, MAP_VIEW.X), axis(position.Y, size.Y, MAP_VIEW.Y))
		mapCentre = (MAP_VIEW / 2 - position) / size
		local goal = { Size = UDim2.fromOffset(size.X, size.Y), Position = UDim2.fromOffset(position.X, position.Y) }
		if mapTween then
			mapTween:Cancel()
			mapTween = nil
		end
		if animate then
			mapTween = UIKit.tween(canvas, 0.22, goal, Enum.EasingStyle.Quad)
		else
			canvas.Size = goal.Size
			canvas.Position = goal.Position
		end
	end
	-- Zooms keeping the point under `screen` (absolute pixels) fixed; nil = the middle.
	local function zoomAt(screen: Vector2?, zoom: number, animate: boolean?)
		local size = MAP_BASE * mapZoom
		local focus = if screen then (screen - view.AbsolutePosition) * unitsPerPixel() else MAP_VIEW / 2
		local fraction = (focus - (MAP_VIEW / 2 - mapCentre * size)) / size
		mapZoom = math.clamp(zoom, MAP_ZOOM_MIN, MAP_ZOOM_MAX)
		local newSize = MAP_BASE * mapZoom
		mapCentre = (MAP_VIEW / 2 - (focus - fraction * newSize)) / newSize
		layout(animate)
	end
	local function pan(deltaPixels: Vector2)
		mapCentre -= deltaPixels * unitsPerPixel() / (MAP_BASE * mapZoom)
		layout(false)
	end
	layout(false)

	-- Shop markers: owned ones in their colours with a level badge, the rest grey.
	local markers: { [string]: TextButton } = {}
	local dragMoved = false
	local tappedMarker = false
	local tooltip = UIKit.label({
		Name = "Tooltip",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(180, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		MaxTextSize = 14,
		Visible = false,
		ZIndex = 9,
		Parent = canvas,
	})
	local info = UIKit.card({
		Name = "MapInfo",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(460, 84),
		BackgroundColor3 = C.PanelLight,
		Visible = false,
		ZIndex = 20,
		Parent = view,
	})
	local function showSelection()
		for id, marker in markers do
			local scale = marker:FindFirstChild("Scale") :: UIScale
			UIKit.tween(scale, 0.15, { Scale = if id == mapSelected then 1.35 else 1 }, Enum.EasingStyle.Back)
			marker.ZIndex = if id == mapSelected then 7 else 6
		end
		local old = info:FindFirstChild("Body")
		if old then
			old:Destroy()
		end
		local definition = if mapSelected then Businesses.get(mapSelected) else nil
		info.Visible = definition ~= nil
		if not definition then
			return
		end
		local biz = state.businesses[definition.id]
		local body = new("Frame", { Name = "Body", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = info })
		businessIcon(definition, { Size = UDim2.fromOffset(62, 62), Position = UDim2.fromOffset(11, 11), Parent = body })
		text(body, definition.name, 84, 8, 190, 24, 19)
		if biz then
			local income = if biz.stats then biz.stats.income else 0
			text(body, string.format("Owned • Level %d • %s/s", biz.level, Format.cash(income)), 84, 34, 190, 18, 14, C.Money, true)
		else
			text(body, "For sale • " .. Format.cash(definition.price), 84, 34, 190, 18, 14, C.Orange, true)
		end
		text(body, "📍 " .. districtName(definition), 84, 56, 190, 16, 13, C.Muted, true)
		UIKit.button({ Name = "MapOpen", Text = if biz then "Manage" else "View", Color = C.Green, Size = UDim2.fromOffset(84, 56), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -104, 0.5, 0), MaxTextSize = 16, Parent = body }, function()
			ctx.ui.openBusiness(definition.id)
		end)
		UIKit.button({ Name = "MapGo", Text = "📍 Go", Color = C.Blue, Size = UDim2.fromOffset(84, 56), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), MaxTextSize = 16, Parent = body }, function()
			waypoint(ctx, definition.id)
		end)
	end
	for _, definition in SORTED do
		local biz = state.businesses[definition.id]
		local marker = new("TextButton", {
			Name = definition.id,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = mapPoint(definition.lot.position),
			Size = UDim2.fromOffset(30, 30),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 6,
			Parent = canvas,
		})
		new("UIScale", { Name = "Scale", Parent = marker })
		local tile = businessIcon(definition, {
			Size = UDim2.fromScale(1, 1),
			Radius = 15,
			Color = if biz then definition.theme.primary else C.Grey,
			Parent = marker,
		})
		local stroke = tile:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if biz then Color3.fromRGB(150, 255, 60) else C.Ink
		end
		if state.starterShop == definition.id then
			-- Your first shop: gold ring and a flag so it is easy to find.
			if stroke then
				stroke.Color = C.Yellow
				stroke.Thickness = 3
			end
			UIKit.label({ Name = "Start", Text = "🎁 START HERE", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -4), Size = UDim2.fromOffset(120, 18), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Yellow, MaxTextSize = 14, ZIndex = 8, Parent = marker })
		end
		if biz then
			local badge = new("Frame", {
				Name = "Level",
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, 7, 1, 5),
				Size = UDim2.fromOffset(18, 16),
				BackgroundColor3 = C.Green,
				ZIndex = 8,
				Parent = marker,
			})
			UIKit.corner(8).Parent = badge
			UIKit.stroke(C.Ink, 1.5).Parent = badge
			UIKit.label({ Text = tostring(biz.level), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 11, ZIndex = 9, Parent = badge })
		end
		marker.MouseEnter:Connect(function()
			tooltip.Text = definition.name
			tooltip.Position = marker.Position - UDim2.fromOffset(0, 20)
			tooltip.Visible = true
		end)
		marker.MouseLeave:Connect(function()
			tooltip.Visible = false
		end)
		marker.Activated:Connect(function()
			if dragMoved then
				return
			end
			tappedMarker = true
			mapSelected = if mapSelected == definition.id then nil else definition.id
			showSelection()
		end)
		markers[definition.id] = marker
	end
	if mapSelected and not markers[mapSelected] then
		mapSelected = nil
	end
	showSelection()

	-- You: a red dot with an arrow showing which way you face.
	local ping = new("Frame", { Name = "Ping", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = C.Red, BackgroundTransparency = 0.3, ZIndex = 11, Visible = false, Parent = canvas })
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ping })
	TweenService:Create(ping, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1), { Size = UDim2.fromOffset(48, 48), BackgroundTransparency = 1 }):Play()
	local me = new("Frame", { Name = "Me", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = C.Red, ZIndex = 12, Visible = false, Parent = canvas })
	UIKit.corner(9).Parent = me
	UIKit.stroke(Color3.new(1, 1, 1), 3).Parent = me
	local heading = UIKit.label({ Name = "Heading", Text = "▲", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(16, 14), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 13, ZIndex = 13, Parent = me })
	local function playerRoot(): BasePart?
		local character = Players.LocalPlayer.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart and rootPart.Position.Y < Config.INTERIOR_MIN_Y then
			return rootPart
		end
		return nil
	end
	table.insert(mapConnections, RunService.Heartbeat:Connect(function()
		if not me.Parent then
			cleanupMap()
			return
		end
		local rootPart = playerRoot()
		me.Visible = rootPart ~= nil
		ping.Visible = me.Visible
		if rootPart then
			me.Position = mapPoint(rootPart.Position)
			ping.Position = me.Position
			local look = rootPart.CFrame.LookVector
			local angle = math.atan2(look.X, -look.Z) -- clockwise from north (-Z)
			heading.Rotation = math.deg(angle)
			heading.Position = UDim2.new(0.5, math.sin(angle) * 15, 0.5, -math.cos(angle) * 15)
		end
	end))

	if not mapOpened then
		mapOpened = true
		local rootPart = playerRoot()
		if rootPart then
			mapCentre = mapFraction(rootPart.Position)
			mapZoom = 1.8
			layout(false)
		end
	end

	-- View buttons.
	local function toolButton(name: string, label: string, color: Color3, width: number, right: number, onClick: () -> ())
		UIKit.button({ Name = name, Text = label, Color = color, Size = UDim2.fromOffset(width, 40), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -right, 0, 0), MaxTextSize = 18, Parent = bar }, onClick)
	end
	toolButton("MapAll", "🏙️ All", C.Purple, 90, 0, function()
		mapCentre = Vector2.new(0.5, 0.5)
		zoomAt(nil, 1, true)
	end)
	toolButton("MapMe", "📍 Me", C.Red, 84, 98, function()
		local rootPart = playerRoot()
		if rootPart then
			mapCentre = mapFraction(rootPart.Position)
			zoomAt(nil, math.max(mapZoom, 2.5), true)
		end
	end)
	toolButton("MapZoomIn", "+", C.Blue, 46, 190, function()
		zoomAt(nil, mapZoom * 1.5, true)
	end)
	toolButton("MapZoomOut", "–", C.Blue, 46, 244, function()
		zoomAt(nil, mapZoom / 1.5, true)
	end)

	-- Mouse wheel and pinch zoom; drag (mouse or one finger) to pan.
	local dragInput: InputObject? = nil
	local dragStart, dragLast = Vector2.zero, Vector2.zero
	local pinchLast: number? = nil
	table.insert(mapConnections, view.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			zoomAt(Vector2.new(input.Position.X, input.Position.Y), mapZoom * (if input.Position.Z > 0 then 1.25 else 0.8), false)
		end
	end))
	table.insert(mapConnections, view.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if dragInput == nil then
				dragInput = input
				dragStart = Vector2.new(input.Position.X, input.Position.Y)
				dragLast = dragStart
				dragMoved = false
			end
		end
	end))
	table.insert(mapConnections, UserInputService.InputChanged:Connect(function(input)
		if not view.Parent then
			cleanupMap()
			return
		end
		local current = dragInput
		if current and pinchLast == nil and (input.UserInputType == Enum.UserInputType.MouseMovement and current.UserInputType == Enum.UserInputType.MouseButton1 or input == current) then
			local point = Vector2.new(input.Position.X, input.Position.Y)
			if not dragMoved and (point - dragStart).Magnitude > 6 then
				dragMoved = true
				tooltip.Visible = false
			end
			if dragMoved then
				pan(point - dragLast)
			end
			dragLast = point
		end
	end))
	table.insert(mapConnections, UserInputService.InputEnded:Connect(function(input)
		local current = dragInput
		if current and (input == current or (input.UserInputType == Enum.UserInputType.MouseButton1 and current.UserInputType == Enum.UserInputType.MouseButton1)) then
			dragInput = nil
			local point = Vector2.new(input.Position.X, input.Position.Y)
			local wasDrag = dragMoved
			task.defer(function()
				-- A tap on empty map (not a shop, not the card) closes the card.
				if not wasDrag and not tappedMarker and mapSelected and not within(info, point) then
					mapSelected = nil
					showSelection()
				end
				tappedMarker = false
				dragMoved = false
			end)
		end
	end))
	table.insert(mapConnections, UserInputService.TouchPinch:Connect(function(positions, scale, _, inputState)
		if not view.Parent or (window and not window.Visible) or #positions < 2 then
			pinchLast = nil
			return
		end
		if inputState == Enum.UserInputState.Begin then
			if within(view, positions[1]) then
				pinchLast = scale
				dragInput = nil
			end
		elseif inputState == Enum.UserInputState.Change and pinchLast then
			zoomAt((positions[1] + positions[2]) / 2, mapZoom * scale / pinchLast, false)
			pinchLast = scale
		else
			pinchLast = nil
		end
	end))
end

----- Prestige tab (Check-UI "Rebirth" archetype) -----
-- Showcase of the income multiplier now vs after, the cash requirement with a live
-- progress bar, what you lose / keep, and one big button (tap twice to confirm).
local REQ_BG = Color3.fromRGB(20, 34, 42)
local REQ_BORDER = Color3.fromRGB(85, 140, 160)
local SUNBURST = "rbxassetid://130563114903838"

local function glossyTile(parent: Instance, props: { [string]: any }, top: Color3, bottom: Color3): Frame
	local defaults: { [string]: any } = { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = parent }
	for k, v in props do
		defaults[k] = v
	end
	local tile = new("Frame", defaults)
	UIKit.corner(8).Parent = tile
	new("UIStroke", { Color = C.Ink, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = tile })
	UIKit.gradient(top, bottom).Parent = tile
	local checker = new("ImageLabel", {
		Name = "Checker",
		Image = UIKit.CHECKER,
		ImageColor3 = Color3.new(0, 0, 0),
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(18, 18),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = tile.ZIndex,
		Parent = tile,
	})
	UIKit.corner(8).Parent = checker
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.92, 0.65), Parent = checker })
	local rim = new("Frame", { Name = "Rim", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -6, 1, -6), ZIndex = tile.ZIndex, Parent = tile })
	UIKit.corner(6).Parent = rim
	new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.5, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = rim })
	return tile
end

local function multiplierTile(parent: Instance, caption: string, value: string, top: Color3, bottom: Color3, x: number, big: boolean): Frame
	local tile = glossyTile(parent, {
		Name = caption,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, 0.5),
		Size = UDim2.fromOffset(if big then 236 else 204, if big then 136 else 116),
		ZIndex = 2,
	}, top, bottom)
	UIKit.label({ Text = caption, Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(8, 8), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 17, ZIndex = 3, Parent = tile })
	local number = UIKit.label({
		Text = value,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -16, 0, if big then 74 else 62),
		TextXAlignment = Enum.TextXAlignment.Center,
		MaxTextSize = if big then 68 else 56,
		ZIndex = 3,
		Parent = tile,
	})
	local stroke = number:FindFirstChild("TextStroke") :: UIStroke?
	if stroke then
		stroke.Thickness = 3.5
	end
	return tile
end

local function renderPrestige(container: Frame, ctx: any): Updater
	local state = ctx.state
	local level = state.prestige or 0
	-- Shops you must own for the next prestige (1, 3, 5, 8, 11); nil once all are done.
	local needed: number? = state.prestigeShops
	local maxed = needed == nil
	local owned = Config.countShops(state.businesses)
	local now = state.prestigeMultiplier or Config.prestigeMultiplier(level)
	local after = state.nextMultiplier or Config.prestigeMultiplier(level + 1)

	-- Showcase: x now -> x after, on a slowly spinning purple sunburst.
	local show = UIKit.card({ Name = "Showcase", Size = UDim2.new(1, 0, 0, 168), BackgroundColor3 = Color3.fromRGB(40, 22, 66), ClipsDescendants = true, Parent = container })
	local glow = new("ImageLabel", {
		Name = "Sunburst",
		Image = SUNBURST,
		ImageColor3 = Color3.fromRGB(200, 120, 255),
		ImageTransparency = 0.2,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.72, 0.5),
		Size = UDim2.fromOffset(360, 360),
		Parent = show,
	})
	TweenService:Create(glow, TweenInfo.new(16, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 }):Play()
	multiplierTile(show, "YOUR INCOME NOW", string.format("x%.1f", now), Color3.fromRGB(0, 205, 255), Color3.fromRGB(0, 130, 245), 0.25, false)
	UIKit.label({ Text = "▶", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.485, 0.5), Size = UDim2.fromOffset(56, 56), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Yellow, MaxTextSize = 48, ZIndex = 3, Parent = show })
	multiplierTile(show, if maxed then "ALL DONE" else "AFTER PRESTIGE", if maxed then "MAX" else string.format("x%.1f", after), Color3.fromRGB(180, 255, 25), Color3.fromRGB(105, 225, 0), 0.72, true)

	-- Requirement box (recessed, Check-UI requirements colours).
	local req = new("Frame", { Name = "Requirement", BackgroundColor3 = REQ_BG, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 84), Position = UDim2.fromOffset(0, 178), Parent = container })
	UIKit.corner(6).Parent = req
	new("UIStroke", { Color = REQ_BORDER, Thickness = 1.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = req })
	text(req, "REQUIREMENT", 14, 7, 220, 18, 14, REQ_BORDER)
	local requirement = if needed == nil then "Every Prestige is done!" elseif needed == 1 then "Own any shop" else string.format("Own %d shops (any shops)", needed)
	text(req, requirement, 14, 25, 420, 26, 22)
	local status = rightText(req, "", 14, 14, 300, 24, 18, C.Muted)
	local _, setBar = UIKit.progressBar({ Name = "CashBar", Size = UDim2.new(1, -28, 0, 22), Position = UDim2.fromOffset(14, 55), Text = "", MaxTextSize = 14, Parent = req })

	-- What you lose / keep.
	local info = new("Frame", { Name = "Info", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 108), Position = UDim2.fromOffset(0, 272), Parent = container })
	local function column(name: string, title: string, color: Color3, items: { string }, right: boolean)
		local card = UIKit.card({ Name = name, Size = UDim2.new(0.5, -5, 1, 0), Position = UDim2.new(if right then 0.5 else 0, if right then 5 else 0, 0, 0), Parent = info })
		text(card, title, 12, 7, 300, 22, 18, color)
		for i, item in items do
			text(card, item, 14, 8 + i * 24, 330, 20, 15, C.Text, true)
		end
	end
	column("Lose", "YOU LOSE", Color3.fromRGB(255, 110, 120), { "💵  All your cash", "🏪  All your shops", "🏙️  Your City Population" }, false)
	column("Keep", "YOU KEEP", C.Money, { string.format("🌟  x%.1f income, forever", if maxed then now else after), "🏆  Awards, stats and settings", "💵  " .. Format.cash(Config.STARTING_MONEY) .. " to start again" }, true)

	-- Bottom row: level info + the big button.
	local bottom = new("Frame", { Name = "Bottom", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 84), Position = UDim2.new(0, 0, 1, -84), Parent = container })
	text(bottom, string.format("Prestige level %d / %d", level, Config.MAX_PRESTIGE), 4, 12, 330, 28, 24, Color3.fromRGB(215, 160, 255))
	local following = Config.prestigeShops(level + 1)
	local nextLine = if maxed then "You've done every Prestige - legendary!"
		elseif following then string.format("Next one: own %d shops for x%.1f", following, Config.prestigeMultiplier(level + 2))
		else "This is the last Prestige!"
	text(bottom, nextLine, 4, 44, 380, 22, 14, C.Muted, true)
	local update: (any?) -> ()
	local button = UIKit.button({
		Name = "PrestigeButton",
		Text = "",
		Color = C.Grey,
		Size = UDim2.fromOffset(300, 76),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		MaxTextSize = 26,
		Parent = bottom,
	}, function()
		if needed == nil then
			ctx.ui.notify("info", "👑 You've done every Prestige!")
			return
		end
		if owned < needed then
			ctx.ui.notify("error", string.format("Own %d shop%s to Prestige (you have %d).", needed, if needed == 1 then "" else "s", owned))
			return
		end
		if os.clock() < prestigeArmedUntil then
			prestigeArmedUntil = 0
			ctx.controllers.Store.send("Prestige")
		else
			prestigeArmedUntil = os.clock() + 4
			task.delay(4.05, function()
				update()
			end)
		end
		update()
	end)
	local lastLook = ""
	update = function(_state: any?)
		if not button.Parent then
			return
		end
		local ready = needed ~= nil and owned >= needed
		local armed = ready and os.clock() < prestigeArmedUntil
		if needed then
			setBar(math.min(owned / needed, 1), string.format("🏪 %d / %d shop%s", math.min(owned, needed), needed, if needed == 1 then "" else "s"))
		else
			setBar(1, "👑 MAX PRESTIGE")
		end
		local missing = if needed then math.max(needed - owned, 0) else 0
		status.Text = if needed == nil then "👑 All done" elseif ready then "✅ Ready!" else string.format("%d more shop%s", missing, if missing == 1 then "" else "s")
		status.TextColor3 = if ready then C.Money else C.Muted
		local look = if armed then "armed" elseif ready then "ready" elseif maxed then "max" else "locked"
		if look ~= lastLook then
			lastLook = look
			UIKit.setButtonColor(button, if armed then C.Red elseif ready then C.Green elseif maxed then C.Purple else C.Grey)
			UIKit.setButtonText(button, if armed then "TAP AGAIN TO CONFIRM" elseif ready then "🌟 PRESTIGE!" elseif needed == nil then "👑 MAX PRESTIGE" else string.format("🔒 Need %d shop%s", needed, if needed == 1 then "" else "s"))
		end
	end
	update()
	return update
end

----- Awards tab -----
-- A trophy-case grid: closest-to-done awards first, unlocked ones (gold) at the end.
local GOLD_TOP, GOLD_BOTTOM = Color3.fromRGB(255, 214, 60), Color3.fromRGB(255, 150, 0)

local function awardCard(list: Instance, achievement: any, info: any, ratio: number, order: number)
	local unlocked = info.unlocked == true
	local card = UIKit.card({
		Name = achievement.id,
		LayoutOrder = order,
		BackgroundColor3 = if unlocked then Color3.fromRGB(64, 52, 18) else C.PanelLight,
		Parent = list,
	})
	if unlocked then
		local rim = card:FindFirstChild("Rim") :: UIStroke?
		if rim then
			rim.Color = Color3.fromRGB(255, 200, 60)
			rim.Transparency = 0
			rim.Thickness = 2
		end
	end
	local started = ratio > 0
	local tile = glossyTile(card, { Name = "Badge", Size = UDim2.fromOffset(54, 54), Position = UDim2.fromOffset(10, 10) },
		if unlocked then GOLD_TOP elseif started then Color3.fromRGB(176, 32, 255) else Color3.fromRGB(150, 160, 176),
		if unlocked then GOLD_BOTTOM elseif started then Color3.fromRGB(112, 0, 224) else Color3.fromRGB(96, 104, 120))
	UIKit.label({ Text = achievement.emoji or "🏆", Size = UDim2.fromScale(0.74, 0.74), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 40, Stroke = false, ZIndex = 3, TextTransparency = if unlocked or started then 0 else 0.35, Parent = tile })
	if unlocked then
		local check = new("Frame", { Name = "Done", BackgroundColor3 = C.Green, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -2, 1, -2), Size = UDim2.fromOffset(22, 22), ZIndex = 4, Parent = tile })
		UIKit.corner(11).Parent = check
		new("UIStroke", { Color = C.Ink, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = check })
		UIKit.label({ Text = "✓", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 16, ZIndex = 5, Parent = check })
	end
	UIKit.label({ Name = "Title", Text = achievement.name or achievement.id, Size = UDim2.new(1, -80, 0, 22), Position = UDim2.fromOffset(72, 9), MaxTextSize = 18, TextColor3 = if unlocked then Color3.fromRGB(255, 220, 90) else C.Text, Parent = card })
	UIKit.label({
		Name = "Desc",
		Text = Goals.formatText(achievement, achievement.target, Format.short),
		Font = UIKit.BodyFont,
		TextColor3 = C.Muted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -80, 0, 34),
		Position = UDim2.fromOffset(72, 33),
		MaxTextSize = 13,
		Parent = card,
	})
	local reward = new("Frame", { Name = "Reward", BackgroundColor3 = Color3.fromRGB(16, 30, 22), Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 74), Parent = card })
	UIKit.corner(6).Parent = reward
	UIKit.label({ Text = "REWARD", Font = UIKit.BodyFont, TextColor3 = C.Muted, Size = UDim2.new(0.45, 0, 1, -6), Position = UDim2.fromOffset(8, 3), MaxTextSize = 12, Parent = reward })
	UIKit.label({ Text = "+" .. Format.cash(achievement.reward), TextColor3 = C.Money, AnchorPoint = Vector2.new(1, 0), Size = UDim2.new(0.6, 0, 1, -6), Position = UDim2.new(1, -8, 0, 3), TextXAlignment = Enum.TextXAlignment.Right, MaxTextSize = 15, Parent = reward })
	local progressText = if achievement.target >= 1000
		then Format.short(info.progress) .. " / " .. Format.short(achievement.target)
		else math.floor(info.progress) .. " / " .. achievement.target
	local _, set = UIKit.progressBar({
		Name = "Progress",
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.fromOffset(10, 108),
		Text = if unlocked then "UNLOCKED!" else progressText,
		MaxTextSize = 13,
		Color = if unlocked then C.Green else nil,
		Parent = card,
	})
	set(ratio)
end

local function renderAchievements(container: Frame, ctx: any)
	local state = ctx.state
	type Entry = { achievement: any, info: any, index: number, ratio: number }
	local entries: { Entry } = {}
	local unlockedCount = 0
	for i, achievement in Goals.Achievements do
		local info = state.achievements and state.achievements[achievement.id] or { unlocked = false, progress = 0 }
		if info.unlocked then
			unlockedCount += 1
		end
		local ratio = if info.unlocked then 1 else math.clamp(info.progress / math.max(achievement.target, 1), 0, 1)
		table.insert(entries, { achievement = achievement, info = info, index = i, ratio = ratio })
	end
	table.sort(entries, function(a: Entry, b: Entry): boolean
		local ua, ub = a.info.unlocked == true, b.info.unlocked == true
		if ua ~= ub then
			return not ua
		end
		if a.ratio ~= b.ratio then
			return a.ratio > b.ratio
		end
		return a.index < b.index
	end)

	-- Summary strip.
	local top = glossyTile(container, { Name = "Summary", Size = UDim2.new(1, -4, 0, 64), Position = UDim2.fromOffset(2, 2) }, Color3.fromRGB(255, 20, 150), Color3.fromRGB(200, 0, 60))
	local trophy = new("ImageLabel", { Name = "Trophy", Image = Icons.menu("Achievements") or "", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromOffset(62, 62), Position = UDim2.fromOffset(8, 0), ZIndex = 3, Parent = top })
	trophy.Rotation = -8
	local title = UIKit.label({ Text = string.format("%d / %d Awards", unlockedCount, #Goals.Achievements), Size = UDim2.new(0, 300, 0, 30), Position = UDim2.fromOffset(78, 6), MaxTextSize = 28, ZIndex = 3, Parent = top })
	local titleStroke = title:FindFirstChild("TextStroke") :: UIStroke?
	if titleStroke then
		titleStroke.Thickness = 3
	end
	UIKit.label({ Text = "Awards unlock on their own and pay you cash.", Font = UIKit.BodyFont, Size = UDim2.new(0, 330, 0, 18), Position = UDim2.fromOffset(78, 38), MaxTextSize = 14, ZIndex = 3, Parent = top })
	local _, setAll = UIKit.progressBar({
		Name = "Total",
		Size = UDim2.fromOffset(230, 24),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Text = string.format("%d%% complete", math.floor(unlockedCount / math.max(#Goals.Achievements, 1) * 100)),
		MaxTextSize = 14,
		Parent = top,
	})
	;(top:FindFirstChild("Total") :: Frame).ZIndex = 3
	setAll(unlockedCount / math.max(#Goals.Achievements, 1))

	-- Grid of award cards.
	local holder = new("Frame", { Name = "GridHolder", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 1, -76), Parent = container })
	local grid = new("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -8, 0, 138),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	local list = scroll(holder, grid)
	for order, entry in entries do
		awardCard(list, entry.achievement, entry.info, entry.ratio, order)
	end
end

----- Settings tab -----
local function renderSettings(container: Frame, ctx: any)
	local state = ctx.state
	local list = scroll(container)
	local settings = state.settings or {}
	local options = {
		{ key = "music", name = "🎵 Music", desc = "Relaxed background music." },
		{ key = "sfx", name = "🔊 Sound effects", desc = "Clicks, cash, city and park sounds." },
		{ key = "ambient", name = "🚗 City traffic & pedestrians", desc = "Turn off for better performance on older devices." },
	}
	for i, option in options do
		local on = settings[option.key] ~= false
		local r = row(list, 76, i)
		text(r, option.name, 14, 10, 420, 28, 22)
		text(r, option.desc, 14, 42, 440, 22, 14, C.Muted, true)
		UIKit.button({ Name = "Toggle_" .. option.key, Text = if on then "ON" else "OFF", Color = if on then C.Green else C.Red, Size = UDim2.fromOffset(124, 54), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Parent = r }, function()
			ctx.controllers.Store.send("UpdateSetting", option.key, not on)
		end)
	end
	local save = row(list, 60, 6, if state.saving then Color3.fromRGB(30, 74, 40) else Color3.fromRGB(96, 50, 24))
	text(save, if state.saving then "💾 Progress saves automatically." else "⚠️ Saving is OFF for this session.", 14, 15, 600, 30, 20)
	local help = row(list, 150, 7)
	text(help, "Controls", 14, 10, 300, 26, 22, C.Yellow)
	text(help, "PC: E to buy / enter, F plays the mini game, B Shops, U Upgrades, M Map, P Prestige, K Awards.\nConsole: Select opens the menu, B goes back / closes, X uses doors, Y plays the mini game.\nMobile: tap the on-screen prompts and buttons.", 14, 42, 660, 100, 15, C.Muted, true)
end

----- Change detection -----
-- A short string of everything a page shows. The controller re-renders the open page
-- only when this changes; anything else (cash, earned totals) updates in place.
function Panels.signature(tabId: string, state: any, view: any): string
	local parts: { string } = { tabId }
	if tabId == "Businesses" or tabId == "Manage" then
		table.insert(parts, tostring(view.business) .. "/" .. tostring(view.filter) .. "/" .. tostring(view.category))
		table.insert(parts, tostring(state.population) .. "/" .. tostring(state.prestige) .. "/" .. tostring(state.inside) .. "/" .. tostring(state.starterShop))
		for _, definition in SORTED do
			local biz = state.businesses[definition.id]
			if biz then
				local upgrades = {}
				for key, value in biz.upgrades do
					table.insert(upgrades, key .. value)
				end
				table.sort(upgrades)
				table.insert(parts, definition.id .. biz.level .. table.concat(upgrades))
			end
		end
	elseif tabId == "Map" then
		for _, definition in SORTED do
			local biz = state.businesses[definition.id]
			if biz then
				table.insert(parts, definition.id .. biz.level)
			end
		end
	elseif tabId == "Prestige" then
		table.insert(parts, tostring(state.prestige) .. "/" .. tostring(state.prestigeShops) .. "/" .. tostring(Config.countShops(state.businesses)))
	elseif tabId == "Achievements" then
		for _, achievement in Goals.Achievements do
			local info = state.achievements and state.achievements[achievement.id]
			if info then
				table.insert(parts, (if info.unlocked then "U" else "") .. math.floor(info.progress / math.max(achievement.target, 1) * 50))
			end
		end
	else
		local settings = state.settings or {}
		table.insert(parts, tostring(settings.sfx) .. tostring(settings.ambient) .. tostring(settings.music) .. tostring(state.saving))
	end
	return table.concat(parts, "|")
end

function Panels.render(tabId: string, container: Frame, ctx: any): Updater?
	if tabId ~= "Map" then
		cleanupMap()
	end
	if tabId == "Businesses" or tabId == "Manage" then
		return renderBusinesses(container, ctx)
	elseif tabId == "Map" then
		renderMap(container, ctx)
	elseif tabId == "Prestige" then
		return renderPrestige(container, ctx)
	elseif tabId == "Achievements" then
		renderAchievements(container, ctx)
	else
		renderSettings(container, ctx)
	end
	return nil
end

return Panels
