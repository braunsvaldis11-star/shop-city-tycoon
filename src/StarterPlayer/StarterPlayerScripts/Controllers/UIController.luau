--!strict
-- UIController (client): HUD, the menu window (side tabs + sliding pages), toasts, cash
-- popups and the screen fade used by doors. Works on PC (mouse + hotkeys), mobile
-- (touch layout, larger scale) and console (gamepad selection, Select = menu,
-- B = back / close).
-- Container: StarterPlayerScripts.Controllers

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Businesses = require(Shared.Businesses)
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Client = ReplicatedStorage:WaitForChild("Client")
local UIKit = require(Client:WaitForChild("UIKit"))
local Icons = require(Client:WaitForChild("Icons"))

local C = UIKit.Colors
local new = UIKit.new

local UIController = {}

local WINDOW_SIZE = Vector2.new(880, 560)
local HEADER_HEIGHT = 64
local SIDEBAR_WIDTH = 116
local SLIDE_TIME = 0.32

local player = Players.LocalPlayer
local controllers: any
local Panels: any

local hud: ScreenGui
local overlay: ScreenGui
local root: Frame
local uiScale: UIScale
local window: Frame
local windowScale: UIScale
local header: Frame
local windowIcon: Frame
local windowTitle: TextLabel
local tabBar: Frame
local content: Frame
local page: Frame? = nil
local fadeFrame: Frame
local toastList: Frame
local popupLayer: Frame

local cashPill: Frame
local cashLabel: TextLabel
local incomeLabel: TextLabel
local boostBadge: Frame
local boostLabel: TextLabel
local cityCard: Frame
local cityRows: { [string]: TextLabel } = {}
local cityExtras: { GuiObject } = {} -- hidden in the compact (phone) card
local rankBar: Frame
local rankBarSet: (number, string?) -> ()
local menuGrid: Frame
local menuButtons: { [string]: TextButton } = {}
local prestigeBadge: Frame? = nil
local windowFit = 1
local contextScale: UIScale
local toastWidth = 470
local maxToasts = 5
local contextBar: Frame
local contextIcon: Frame
local contextName: TextLabel
local contextInfo: TextLabel
local contextLevelButton: TextButton
local contextManageButton: TextButton

-- Menu navigation state
local currentTab: string? = nil
local selectedBusiness: string? = nil -- Businesses tab: nil = list, id = detail page
local listFilter = "All"
local category = "Overview"
local listScroll = Vector2.zero
local pendingScroll: Vector2? = nil
local lastSignature = ""
local currentUpdater: ((any) -> ())? = nil

local insideBusinessId: string? = nil
local contextBusinessId: string? = nil
local displayedMoney = 0
local costButtons: { { button: TextButton, cost: number, color: Color3, affordable: boolean } } = {}
local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local TOAST_COLORS = {
	success = C.Green, error = C.Red, info = C.Blue, reward = C.Gold, levelup = C.Purple,
	rankup = C.Orange, achievement = C.Yellow, warning = C.Orange,
}
local TOAST_SOUNDS = {
	success = "Purchase", error = "Error", reward = "Cash", levelup = "LevelUp", rankup = "LevelUp", achievement = "LevelUp",
}

----- Shared helpers for panels -----
function UIController.registerCostButton(button: TextButton, cost: number, color: Color3)
	local affordable = controllers.Store.money() >= cost
	table.insert(costButtons, { button = button, cost = cost, color = color, affordable = affordable })
	UIKit.setButtonColor(button, if affordable then color else C.Grey)
end

local function runUpdater()
	local updater = currentUpdater
	local state = controllers.Store.state
	if updater and state and window.Visible then
		local ok, err = pcall(updater, state)
		if not ok then
			warn("[UI] page update failed: " .. tostring(err))
		end
	end
end

local function refreshAffordability()
	local money = controllers.Store.money()
	for _, entry in costButtons do
		local affordable = money >= entry.cost
		if affordable ~= entry.affordable and entry.button.Parent then
			entry.affordable = affordable
			UIKit.setButtonColor(entry.button, if affordable then entry.color else C.Grey)
		end
	end
	runUpdater()
end

function UIController.isTouch(): boolean
	return isTouch
end

----- Toasts and popups -----
function UIController.notify(kind: string, text: string)
	local color = TOAST_COLORS[kind] or C.Blue
	local toast = UIKit.panel({
		Name = "Toast",
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = color:Lerp(C.Panel, 0.62),
		Parent = toastList,
	})
	local accent = new("Frame", { Name = "Accent", BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.new(0, 8, 1, 0), Parent = toast })
	UIKit.corner(4).Parent = accent
	UIKit.label({
		Text = text,
		Size = UDim2.new(1, -34, 1, -12),
		Position = UDim2.fromOffset(20, 6),
		TextXAlignment = Enum.TextXAlignment.Center,
		MaxTextSize = 20,
		Parent = toast,
	})
	local scale = new("UIScale", { Scale = 0.6, Parent = toast })
	UIKit.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	local sound = TOAST_SOUNDS[kind]
	if sound then
		controllers.Sound.play(sound, 0.5)
	end
	local children = toastList:GetChildren()
	local count = 0
	for _, child in children do
		if child:IsA("Frame") then
			count += 1
		end
	end
	if count > maxToasts then
		for _, child in children do
			if child:IsA("Frame") and child ~= toast then
				child:Destroy()
				break
			end
		end
	end
	task.delay(if kind == "warning" then 8 else 3.5, function()
		if toast.Parent then
			UIKit.tween(scale, 0.2, { Scale = 0 })
			task.wait(0.22)
			toast:Destroy()
		end
	end)
end

local function cashPopup(amount: number, kind: string?)
	local positive = amount >= 0
	local label = UIKit.label({
		Text = (if positive then "+" else "-") .. Format.cash(math.abs(amount)),
		TextColor3 = if positive then C.Money else Color3.fromRGB(255, 120, 120),
		Size = UDim2.fromOffset(220, 34),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, math.random(-60, 60), 0, 90),
		TextXAlignment = Enum.TextXAlignment.Center,
		MaxTextSize = 30,
		Parent = popupLayer,
	})
	local stroke = label:FindFirstChild("TextStroke") :: UIStroke?
	UIKit.tween(label, 1.1, { Position = label.Position + UDim2.fromOffset(0, if positive then 50 else 40), TextTransparency = 1 })
	if stroke then
		UIKit.tween(stroke, 1.1, { Transparency = 1 })
	end
	task.delay(1.15, function()
		label:Destroy()
	end)
	if positive and kind ~= "serve" then
		controllers.Sound.play("Cash", 0.4)
	elseif not positive then
		controllers.Sound.play("Purchase", 0.4)
	end
end

function UIController.fade(on: boolean)
	if on then
		fadeFrame.Visible = true
		UIKit.tween(fadeFrame, 0.22, { BackgroundTransparency = 0 })
	else
		local tween = UIKit.tween(fadeFrame, 0.4, { BackgroundTransparency = 1 })
		tween.Completed:Once(function()
			if fadeFrame.BackgroundTransparency >= 0.99 then
				fadeFrame.Visible = false
			end
		end)
	end
end

----- Menu window -----
local function selectFirst(container: Instance)
	if not UserInputService.GamepadEnabled then
		return
	end
	for _, d in container:GetDescendants() do
		if d:IsA("GuiButton") and d.Selectable and d.Visible then
			GuiService.SelectedObject = d
			return
		end
	end
end

local function view(): any
	return { business = selectedBusiness, filter = listFilter, category = category }
end

local function updateTabButtons()
	for _, tab in tabBar:GetChildren() do
		if tab:IsA("TextButton") then
			local info = Panels.getTab(tab.Name)
			UIKit.setButtonColor(tab, if tab.Name == currentTab then info.color else C.PanelLight)
		end
	end
end

-- Builds the open page from scratch. `slide` animates it in from that offset; with
-- `slideTarget` only that descendant slides (e.g. the body when switching categories).
local function renderTab(slide: Vector2?, slideTarget: string?)
	local tabId = currentTab
	if not tabId then
		return
	end
	local state = controllers.Store.state
	local oldScroll = if page then page:FindFirstChild("Scroll", true) :: ScrollingFrame? else nil
	local keepScroll = if oldScroll and not slide then oldScroll.CanvasPosition else nil
	local selected = GuiService.SelectedObject
	local selectedName = if selected and selected:IsDescendantOf(content) and not slide then selected.Name else nil
	table.clear(costButtons)
	currentUpdater = nil
	if page then
		page:Destroy()
	end
	local newPage = new("Frame", { Name = "Page", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = content })
	page = newPage
	updateTabButtons()
	local info = Panels.getTab(tabId)
	windowTitle.Text = info.name
	UIKit.setHeaderTheme(header, UIKit.Themes[info.theme] or UIKit.Themes.Lime)
	UIKit.setIcon(windowIcon, info.emoji, Icons.menu(info.id))
	UIKit.setIconColor(windowIcon, info.color)
	if state then
		lastSignature = Panels.signature(tabId, state, view())
		local ok, result = pcall(Panels.render, tabId, newPage, {
			state = state,
			controllers = controllers,
			ui = UIController,
			view = view(),
			insideBusinessId = insideBusinessId,
		})
		if ok then
			currentUpdater = result
		else
			warn("[UI] render failed: " .. tostring(result))
		end
	else
		lastSignature = ""
		UIKit.label({ Text = "Loading your empire...", Size = UDim2.new(1, 0, 0, 40), Parent = newPage })
	end

	local newScroll = newPage:FindFirstChild("Scroll", true) :: ScrollingFrame?
	local scrollTo = keepScroll or pendingScroll
	pendingScroll = nil
	if newScroll and scrollTo then
		newScroll.CanvasPosition = scrollTo
		-- The canvas grows a frame later (AutomaticCanvasSize), so set it again then.
		task.defer(function()
			if newScroll.Parent then
				newScroll.CanvasPosition = scrollTo
			end
		end)
	end

	if slide then
		local moving: GuiObject = newPage
		if slideTarget then
			local found = newPage:FindFirstChild(slideTarget, true)
			if found and found:IsA("GuiObject") then
				moving = found
			end
		end
		local home = moving.Position
		moving.Position = home + UDim2.fromOffset(slide.X, slide.Y)
		UIKit.tween(moving, SLIDE_TIME, { Position = home }, Enum.EasingStyle.Quint)
		selectFirst(newPage)
	elseif selectedName then
		local match = content:FindFirstChild(selectedName, true)
		if match and match:IsA("GuiObject") then
			GuiService.SelectedObject = match
		else
			selectFirst(content)
		end
	end
end

function UIController.refresh()
	renderTab()
end

function UIController.open(tabId: string, slide: Vector2?)
	if tabId == "Manage" then
		tabId = "Businesses"
	end
	local wasOpen = window.Visible
	local changed = currentTab ~= tabId
	currentTab = tabId
	window.Visible = true
	if not wasOpen then
		windowScale.Scale = 0.85 * windowFit
		UIKit.tween(windowScale, 0.3, { Scale = windowFit }, Enum.EasingStyle.Back)
		renderTab()
		selectFirst(content)
	else
		renderTab(slide or (if changed then Vector2.new(0, 24) else nil))
	end
end

function UIController.close()
	if not window.Visible then
		return
	end
	currentTab = nil
	currentUpdater = nil
	local tween = UIKit.tween(windowScale, 0.15, { Scale = 0.85 * windowFit })
	tween.Completed:Once(function()
		if currentTab == nil then
			window.Visible = false
		end
	end)
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(window) then
		GuiService.SelectedObject = nil
	end
end

function UIController.isOpen(): boolean
	return window.Visible and currentTab ~= nil
end

function UIController.toggle(tabId: string)
	if window.Visible and currentTab == tabId then
		UIController.close()
	else
		UIController.open(tabId)
	end
end

-- Businesses tab navigation: nil shows the list, an id slides its detail page in.
function UIController.openBusiness(businessId: string?)
	if businessId and not Businesses.get(businessId) then
		businessId = nil
	end
	local onBusinesses = window.Visible and currentTab == "Businesses"
	if onBusinesses and businessId and not selectedBusiness and page then
		local scroll = page:FindFirstChild("Scroll", true) :: ScrollingFrame?
		if scroll then
			listScroll = scroll.CanvasPosition
		end
	end
	local goingBack = businessId == nil and selectedBusiness ~= nil
	if selectedBusiness == nil and businessId ~= nil then
		category = "Overview"
	end
	selectedBusiness = businessId
	if goingBack then
		pendingScroll = listScroll
	end
	if onBusinesses then
		renderTab(if businessId then Vector2.new(80, 0) else Vector2.new(-80, 0))
	else
		UIController.open("Businesses")
	end
end

function UIController.switchBusiness(businessId: string, direction: number)
	selectedBusiness = businessId
	if window.Visible and currentTab == "Businesses" then
		renderTab(Vector2.new(80 * direction, 0))
	end
end

function UIController.setCategory(categoryId: string)
	if category == categoryId then
		return
	end
	category = categoryId
	renderTab(Vector2.new(0, 20), "Body")
end

function UIController.setFilter(filter: string)
	if listFilter == filter then
		return
	end
	listFilter = filter
	renderTab(Vector2.new(0, 20), "ListHolder")
end

-- Opens the upgrade page of a business (the one you're in or near, else your first).
function UIController.openManage(businessId: string?)
	local state = controllers.Store.state
	local id = businessId or insideBusinessId or contextBusinessId or selectedBusiness
	if not id and state then
		local best: any = nil
		for _, definition in Businesses.List do
			if state.businesses[definition.id] and (best == nil or definition.order < best.order) then
				best = definition
			end
		end
		id = if best then best.id else nil
	end
	UIController.openBusiness(id)
end

function UIController.setManageBusiness(businessId: string)
	UIController.switchBusiness(businessId, 1)
end

function UIController.setInside(businessId: string?)
	insideBusinessId = businessId
end

----- HUD construction -----
local MARGIN = 10
local GUIDE_CHIPS = { "Guide", "PaperJob" } -- bottom-centre hint chips, lowest first
local CITY_W = 236
local MENU_CELL = 74
local MENU_GAP = 10
local MENU_COLUMNS = 2
local INK_TEXT = Color3.fromRGB(17, 23, 26)

-- A bare icon: the Check-UI image once it has loaded, the emoji until then.
local function bareIcon(parent: Instance, emoji: string, image: string?, props: { [string]: any }): Frame
	local defaults: { [string]: any } = { Name = "IconHolder", BackgroundTransparency = 1, Parent = parent }
	for k, v in props do
		defaults[k] = v
	end
	local holder = new("Frame", defaults)
	local z = holder.ZIndex
	UIKit.label({ Name = "Emoji", Text = emoji, Size = UDim2.fromScale(0.8, 0.8), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 64, Stroke = false, ZIndex = z, Parent = holder })
	new("ImageLabel", { Name = "Image", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromScale(1, 1), ZIndex = z, Parent = holder })
	UIKit.setIcon(holder, emoji, image)
	return holder
end

-- Centre-anchored hover / press bounce on a UIScale.
local function bounce(button: GuiButton, scale: UIScale, hover: number, onHover: ((boolean) -> ())?)
	local hovering = false
	local function set(on: boolean)
		hovering = on
		UIKit.tween(scale, 0.1, { Scale = if on then hover else 1 })
		if onHover then
			onHover(on)
		end
	end
	button.MouseEnter:Connect(function()
		if UserInputService.MouseEnabled then
			set(true)
		end
	end)
	button.MouseLeave:Connect(function()
		set(false)
	end)
	button.SelectionGained:Connect(function()
		set(true)
	end)
	button.SelectionLost:Connect(function()
		set(false)
	end)
	button.MouseButton1Down:Connect(function()
		UIKit.tween(scale, 0.08, { Scale = 0.9 })
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			UIKit.tween(scale, 0.18, { Scale = if hovering then hover else 1 }, Enum.EasingStyle.Back)
		end
	end)
end

-- Cash counter: a slate pill with the cash stack popping out on the left and a purple
-- prestige boost badge on the right.
local function buildCash()
	cashPill = UIKit.panel({ Name = "Cash", Size = UDim2.fromOffset(300, 62), Position = UDim2.fromOffset(0, MARGIN), Parent = root })
	local well = UIKit.card({ Name = "Well", Size = UDim2.new(1, -58, 1, -12), Position = UDim2.fromOffset(52, 6), Parent = cashPill })
	bareIcon(cashPill, "💵", Icons.menu("Cash"), { Size = UDim2.fromOffset(76, 76), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 20, 0.5, 0), ZIndex = 3 })
	cashLabel = UIKit.label({ Name = "Amount", Text = "$0", Size = UDim2.new(1, -18, 0, 28), Position = UDim2.fromOffset(12, 2), MaxTextSize = 30, Parent = well })
	incomeLabel = UIKit.label({ Name = "Income", Text = "+$0/s", TextColor3 = C.Money, Size = UDim2.new(1, -18, 0, 16), Position = UDim2.fromOffset(12, 30), MaxTextSize = 16, Parent = well })
	boostBadge = new("Frame", {
		Name = "Boost",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(64, 30),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
		ZIndex = 2,
		Parent = well,
	})
	UIKit.corner(8).Parent = boostBadge
	UIKit.gradient(Color3.fromRGB(190, 80, 255), Color3.fromRGB(110, 0, 210)).Parent = boostBadge
	new("UIStroke", { Color = C.Ink, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = boostBadge })
	boostLabel = UIKit.label({ Name = "Value", Text = "x1.0", Size = UDim2.new(1, -8, 1, -6), Position = UDim2.fromOffset(4, 3), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 18, ZIndex = 3, Parent = boostBadge })
end

-- My City: rank, progress to the next rank, shops owned and income. On short (phone)
-- screens only the rank and its bar stay (see setCityCompact).
local function buildCityCard()
	cityCard = UIKit.panel({ Name = "MyCity", Size = UDim2.fromOffset(CITY_W, 140), Position = UDim2.fromOffset(0, MARGIN), Parent = root })
	local headerIcon = bareIcon(cityCard, "🏙️", Icons.menu("City"), { Size = UDim2.fromOffset(42, 42), Position = UDim2.fromOffset(4, -10), ZIndex = 3 })
	local title = UIKit.label({ Name = "Title", Text = "My City", Size = UDim2.new(1, -60, 0, 24), Position = UDim2.fromOffset(50, 6), MaxTextSize = 22, Parent = cityCard })
	cityRows.rank = UIKit.label({ Name = "Rank", Text = "-", Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 36), MaxTextSize = 18, Parent = cityCard })
	local bar, set = UIKit.progressBar({ Name = "RankBar", Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 60), Text = "", MaxTextSize = 12, Parent = cityCard })
	rankBar = bar
	rankBarSet = set
	local stats = new("Frame", { Name = "Stats", BackgroundTransparency = 1, Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 86), Parent = cityCard })
	UIKit.list(Enum.FillDirection.Horizontal, 6).Parent = stats
	local function chip(name: string, emoji: string, order: number)
		local c = UIKit.card({ Name = name, Size = UDim2.new(0.5, -3, 1, 0), LayoutOrder = order, Parent = stats })
		UIKit.label({ Text = emoji, Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(4, 4), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 18, Stroke = false, Parent = c })
		cityRows[name] = UIKit.label({ Name = "Value", Text = "-", Size = UDim2.new(1, -32, 1, -8), Position = UDim2.fromOffset(28, 4), MaxTextSize = 15, Parent = c })
	end
	chip("businesses", "🏪", 1)
	chip("income", "💵", 2)
	cityRows.next = UIKit.label({
		Name = "Next", Text = "", Font = UIKit.BodyFont, TextColor3 = C.Muted, Size = UDim2.new(1, -20, 0, 14), Position = UDim2.fromOffset(10, 120),
		TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 12, Parent = cityCard,
	})
	cityExtras = { headerIcon, title, stats, cityRows.next }
end

local function setCityCompact(compact: boolean)
	for _, item in cityExtras do
		item.Visible = not compact
	end
	cityRows.rank.Position = UDim2.fromOffset(10, if compact then 7 else 36)
	rankBar.Position = UDim2.fromOffset(10, if compact then 31 else 60)
	cityCard.Size = UDim2.fromOffset(CITY_W, if compact then 58 else 140)
end

local MENU_BUTTONS = {
	{ tab = "Businesses", text = "Shops", key = Enum.KeyCode.B, hint = "B" },
	{ tab = "Map", text = "Map", key = Enum.KeyCode.M, hint = "M" },
	{ tab = "Prestige", text = "Prestige", key = Enum.KeyCode.P, hint = "P" },
	{ tab = "Achievements", text = "Awards", key = Enum.KeyCode.K, hint = "K" },
	{ tab = "Store", text = "Store", key = nil, hint = nil },
	{ tab = "Settings", text = "Settings", key = nil, hint = nil },
}

-- Simulator-style app tile: glossy gradient square, a big outlined icon popping out of
-- it, the name overlapping the bottom edge and (PC) the hotkey in the corner.
local function menuButton(info: any, order: number): TextButton
	local tab = Panels.getTab(info.tab)
	local style = UIKit.style(tab.color)
	local button = new("TextButton", {
		Name = info.tab .. "Button",
		Size = UDim2.fromOffset(MENU_CELL, MENU_CELL),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Selectable = true,
		LayoutOrder = order,
		Parent = menuGrid,
	})
	local face = new("Frame", {
		Name = "Face",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = button,
	})
	UIKit.corner(12).Parent = face
	new("UIStroke", { Name = "Outline", Color = C.Ink, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = face })
	new("UIGradient", { Name = "Fill", Color = ColorSequence.new(style.top, style.bottom), Rotation = 90, Parent = face })
	local checker = new("ImageLabel", {
		Name = "Checker",
		Image = UIKit.CHECKER,
		ImageColor3 = Color3.new(0, 0, 0),
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = face,
	})
	UIKit.corner(12).Parent = checker
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.93, 0.62), Parent = checker })
	local shine = new("Frame", { Name = "Shine", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.8, BorderSizePixel = 0, Size = UDim2.new(1, -8, 0.4, 0), Position = UDim2.fromOffset(4, 4), Parent = face })
	UIKit.corner(9).Parent = shine
	local rim = new("Frame", { Name = "Rim", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -5, 1, -5), Parent = face })
	UIKit.corner(10).Parent = rim
	new("UIStroke", { Color = style.rim, Thickness = 1.5, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = rim })
	local icon = bareIcon(face, tab.emoji, Icons.menu(info.tab), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.88, 0.88),
		ZIndex = 3,
	})
	local label = UIKit.label({
		Name = "Label",
		Text = info.text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -7),
		Size = UDim2.new(1, 14, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		MaxTextSize = 17,
		Stroke = false,
		ZIndex = 4,
		Parent = face,
	})
	new("UIStroke", { Name = "TextStroke", Color = INK_TEXT, Thickness = 2.6, Parent = label })
	if info.hint and not isTouch then
		local key = new("Frame", { Name = "Key", BackgroundColor3 = C.Ink, Size = UDim2.fromOffset(20, 20), Position = UDim2.fromOffset(-6, -6), ZIndex = 5, Parent = face })
		UIKit.corner(5).Parent = key
		new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.5, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = key })
		UIKit.label({ Text = info.hint, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 13, Stroke = false, ZIndex = 6, Parent = key })
	end
	local scale = new("UIScale", { Name = "Scale", Parent = face })
	bounce(button, scale, 1.08, function(on)
		UIKit.tween(icon, 0.15, { Rotation = if on then -8 else 0 }, Enum.EasingStyle.Back)
	end)
	button.Activated:Connect(function()
		controllers.Sound.play("Click", 0.3)
		UIController.toggle(info.tab)
	end)
	return button
end

local function buildMenuButtons()
	-- Positioned by layout(): left edge (centred on PC, top-left on touch so the
	-- thumbstick keeps the bottom-left corner).
	menuGrid = new("Frame", { Name = "MenuButtons", BackgroundTransparency = 1, Parent = root })
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(MENU_CELL, MENU_CELL),
		CellPadding = UDim2.fromOffset(MENU_GAP, MENU_GAP + 8),
		FillDirectionMaxCells = MENU_COLUMNS,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = menuGrid,
	})
	for i, info in MENU_BUTTONS do
		menuButtons[info.tab] = menuButton(info, i)
	end
	-- "!" badge on Prestige while you can afford it.
	local prestigeButton = menuButtons.Prestige
	local face = prestigeButton and prestigeButton:FindFirstChild("Face")
	if face then
		local badge = new("Frame", {
			Name = "Badge",
			BackgroundColor3 = C.Red,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -4, 0, 4),
			Size = UDim2.fromOffset(26, 26),
			Visible = false,
			ZIndex = 6,
			Parent = face,
		})
		UIKit.corner(13).Parent = badge
		new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = badge })
		UIKit.label({ Text = "!", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 20, ZIndex = 7, Parent = badge })
		local pulse = new("UIScale", { Name = "Pulse", Parent = badge })
		TweenService:Create(pulse, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.22 }):Play()
		prestigeBadge = badge
	end
end

local function buildContextBar()
	contextBar = UIKit.panel({
		Name = "BusinessBar",
		Size = UDim2.fromOffset(540, 90),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Visible = false,
		Parent = root,
	})
	contextScale = new("UIScale", { Name = "Fit", Parent = contextBar })
	contextIcon = UIKit.icon({ Text = "🍕", Color = C.Orange, Size = UDim2.fromOffset(68, 68), Position = UDim2.fromOffset(11, 11), Parent = contextBar })
	contextName = UIKit.label({ Text = "", Size = UDim2.new(0, 190, 0, 30), Position = UDim2.fromOffset(90, 12), MaxTextSize = 22, Parent = contextBar })
	contextInfo = UIKit.label({ Text = "", Font = UIKit.BodyFont, TextColor3 = C.Money, Size = UDim2.new(0, 190, 0, 34), Position = UDim2.fromOffset(90, 44), MaxTextSize = 15, TextWrapped = true, Parent = contextBar })
	contextLevelButton = UIKit.button({ Name = "LevelUp", Text = "Upgrade", Color = C.Green, Size = UDim2.fromOffset(124, 68), Position = UDim2.fromOffset(288, 11), MaxTextSize = 19, Parent = contextBar }, function()
		if contextBusinessId then
			controllers.Store.send("LevelUpBusiness", contextBusinessId)
		end
	end)
	contextManageButton = UIKit.button({ Name = "Manage", Text = "Upgrades", Emoji = "⬆️", Color = C.Purple, Size = UDim2.fromOffset(114, 68), Position = UDim2.fromOffset(418, 11), Stack = true, MaxTextSize = 15, Parent = contextBar }, function()
		if contextBusinessId then
			UIController.openManage(contextBusinessId)
		end
	end)
end

local function buildWindow()
	window = UIKit.panel({
		Name = "Menu",
		Size = UDim2.fromOffset(WINDOW_SIZE.X, WINDOW_SIZE.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Visible = false,
		Parent = root,
	})
	window.ZIndex = 5
	windowScale = new("UIScale", { Parent = window })
	header = UIKit.header(window, HEADER_HEIGHT)
	windowIcon = UIKit.icon({ Text = "🏪", Color = C.Green, Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(12, 6), Parent = header })
	windowTitle = UIKit.label({ Text = "", Size = UDim2.new(1, -150, 0, 38), Position = UDim2.fromOffset(70, 10), MaxTextSize = 32, Parent = header })
	local titleStroke = windowTitle:FindFirstChild("TextStroke") :: UIStroke?
	if titleStroke then
		titleStroke.Thickness = 3
	end
	UIKit.closeButton({ Position = UDim2.new(1, -32, 0, 29), Parent = header }, function()
		UIController.close()
	end)

	tabBar = new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, SIDEBAR_WIDTH, 1, -(HEADER_HEIGHT + 20)),
		Position = UDim2.fromOffset(12, HEADER_HEIGHT + 10),
		Parent = window,
	})
	UIKit.list(Enum.FillDirection.Vertical, 8).Parent = tabBar
	for i, tab in Panels.Tabs do
		UIKit.button({
			Name = tab.id,
			Text = tab.short,
			Emoji = tab.emoji,
			Image = Icons.menu(tab.id),
			Stack = true,
			Color = C.PanelLight,
			Size = UDim2.fromOffset(SIDEBAR_WIDTH, 70), -- six tabs fit the 476px page
			LayoutOrder = i,
			MaxTextSize = 16,
			Parent = tabBar,
		}, function()
			if tab.id == "Businesses" and currentTab == "Businesses" and selectedBusiness then
				UIController.openBusiness(nil)
			else
				UIController.open(tab.id)
			end
		end)
	end
	new("Frame", {
		Name = "Divider",
		BackgroundColor3 = C.Stroke,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 3, 1, -(HEADER_HEIGHT + 20)),
		Position = UDim2.fromOffset(SIDEBAR_WIDTH + 19, HEADER_HEIGHT + 10),
		Parent = window,
	})
	-- Content clips sliding pages; the padding leaves room for card outlines.
	content = new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Size = UDim2.new(1, -(SIDEBAR_WIDTH + 32), 1, -(HEADER_HEIGHT + 8)),
		Position = UDim2.fromOffset(SIDEBAR_WIDTH + 26, HEADER_HEIGHT + 2),
		Parent = window,
	})
	UIKit.padding(6).Parent = content
end

----- Responsive layout -----
-- Everything in the HUD lives in `root`, which is scaled by one UIScale. layout() works
-- in those scaled "canvas" units and places every element so nothing overlaps on any
-- screen: big PC monitors, small laptop windows, tablets and phones.
-- Dev aid: set CityHUD attributes SimViewport (Vector2) / SimTouch (bool) to preview
-- another screen size in the top-left corner of this one.

local function touchLayout(): boolean
	local simulated = hud:GetAttribute("SimTouch")
	if type(simulated) == "boolean" then
		return simulated
	end
	return isTouch
end

local function viewportSize(): Vector2
	local simulated = hud:GetAttribute("SimViewport")
	if typeof(simulated) == "Vector2" then
		return simulated
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 760)
end

local function updateScale()
	local size = viewportSize()
	local scale
	if touchLayout() or size.Y < 560 then
		-- Phones: size by height so buttons stay thumb-sized.
		scale = math.clamp(math.min(size.Y / 480, size.X / 900), 0.55, 1.2)
	else
		scale = math.clamp(math.min(size.X / 1280, size.Y / 760), 0.6, 1.25)
	end
	uiScale.Scale = scale
	local simulated = hud:GetAttribute("SimViewport")
	if typeof(simulated) == "Vector2" then
		root.Size = UDim2.fromOffset(simulated.X / scale, simulated.Y / scale)
	else
		-- The root must stay full-screen after UIScale: grow it by 1/scale.
		root.Size = UDim2.fromScale(1 / scale, 1 / scale)
	end
end

local function layout()
	if not menuGrid or not cashPill or not cityCard then
		return
	end
	local s = uiScale.Scale
	local absolute = root.AbsoluteSize
	if absolute.X <= 1 or s <= 0 then
		return
	end
	local cw, ch = absolute.X / s, absolute.Y / s
	local touch = touchLayout()
	local short = ch < 600

	-- Menu tiles: left edge. Centred on PC; top-left on touch / short screens (the
	-- thumbstick owns the bottom-left corner).
	local rows = math.ceil(#MENU_BUTTONS / MENU_COLUMNS)
	local menuW = MENU_COLUMNS * MENU_CELL + (MENU_COLUMNS - 1) * MENU_GAP
	local menuH = rows * MENU_CELL + (rows - 1) * (MENU_GAP + 8) + 8
	local menuTop = if touch or short then MARGIN + 6 else math.floor(ch / 2 - menuH / 2 + 30)
	menuGrid.Size = UDim2.fromOffset(menuW, menuH)
	menuGrid.Position = UDim2.fromOffset(MARGIN + 6, menuTop)
	local menuRight = MARGIN + 6 + menuW
	local menuBottom = menuTop + menuH

	-- My City: top-right, compact on short screens.
	setCityCompact(short)
	local cityH = cityCard.Size.Y.Offset
	local cityLeft = cw - MARGIN - CITY_W
	cityCard.Position = UDim2.fromOffset(cityLeft, MARGIN + 6)

	-- Cash: centred when there is room, otherwise right next to the menu tiles.
	local cashTop = MARGIN + 6
	local cashW = 300
	local leftLimit = (if menuTop < cashTop + 62 then menuRight else MARGIN) + 26 -- the cash icon pops out 16px
	local rightLimit = cityLeft - 12
	local cashX = math.max(math.floor(cw / 2 - cashW / 2), leftLimit)
	if cashX + cashW > rightLimit then
		cashW = math.max(210, rightLimit - cashX)
	end
	cashPill.Size = UDim2.fromOffset(cashW, 62)
	cashPill.Position = UDim2.fromOffset(cashX, cashTop)

	-- Toasts: under the cash, centred in the free space between menu and city card.
	maxToasts = if short then 3 else 5
	local toastTop = cashTop + 62 + 10
	local toastBottom = toastTop + maxToasts * 56
	local leftBound = if menuTop < toastBottom and menuBottom > toastTop then menuRight else MARGIN
	local rightBound = if toastTop < MARGIN + 6 + cityH then cityLeft else cw - MARGIN
	local half = math.min(cw / 2 - leftBound, rightBound - cw / 2) - 10
	local width, centre
	if half * 2 >= 320 then
		width, centre = math.min(470, half * 2), cw / 2
	else
		width = math.min(470, rightBound - leftBound - 20)
		centre = (leftBound + rightBound) / 2
	end
	toastWidth = math.floor(width)
	toastList.AnchorPoint = Vector2.zero
	toastList.Size = UDim2.fromOffset(toastWidth, maxToasts * 56)
	toastList.Position = UDim2.fromOffset(math.floor(centre - width / 2), toastTop)

	-- Bottom centre: the business bar, and the guide chips just above it. On touch
	-- both stay clear of the thumbstick (left) and the jump button (right).
	local sideReserve = if touch then 180 else MARGIN
	local bottom = ch - MARGIN - (if touch then 6 else 2)
	local available = math.max(240, cw - 2 * sideReserve)
	local fit = math.clamp(available / 540, 0.62, 1)
	contextScale.Scale = fit
	contextBar.AnchorPoint = Vector2.new(0.5, 1)
	contextBar.Position = UDim2.fromOffset(math.floor(cw / 2), bottom)
	local chipBottom = bottom
	if contextBar.Visible then
		chipBottom -= math.floor(90 * fit) + 10
	end
	-- Guide chips (the new-player guide, the optional paper route) stack upward. A chip
	-- may ask for its own size with the ChipWidth / ChipHeight attributes.
	for _, name in GUIDE_CHIPS do
		local chip = root:FindFirstChild(name)
		if chip and chip:IsA("Frame") then
			local width = chip:GetAttribute("ChipWidth")
			local height = chip:GetAttribute("ChipHeight")
			local chipHeight = if type(height) == "number" then height else 50
			chip.AnchorPoint = Vector2.new(0.5, 1)
			chip.Size = UDim2.fromOffset(math.floor(math.min(if type(width) == "number" then width else 430, available)), chipHeight)
			chip.Position = UDim2.fromOffset(math.floor(cw / 2), chipBottom)
			if chip.Visible then
				chipBottom -= chipHeight + 8
			end
		end
	end

	-- Menu window: shrink to fit short screens, always centred.
	windowFit = math.min(1, (cw - 16) / WINDOW_SIZE.X, (ch - 16) / WINDOW_SIZE.Y)
	window.Position = UDim2.fromOffset(math.floor(cw / 2), math.floor(ch / 2 + (if windowFit < 1 then 0 else 12)))
	if window.Visible and currentTab then
		windowScale.Scale = windowFit
	end
end
UIController.layout = layout

----- HUD updates -----
local function updateContextBar()
	local state = controllers.Store.state
	local id = insideBusinessId
	if not id and state then
		-- Outside: show the bar when standing near the door of a business you own.
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			for _, definition in Businesses.List do
				if state.businesses[definition.id] then
					local cf = CFrame.new(definition.lot.position) * CFrame.Angles(0, math.rad(definition.lot.yaw), 0)
					local door = (cf * CFrame.new(0, 0, -definition.lot.size.Z / 2 - 8)).Position
					if (Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z) - Vector3.new(door.X, 0, door.Z)).Magnitude < 26 then
						id = definition.id
						break
					end
				end
			end
		end
	end
	local changed = id ~= contextBusinessId
	contextBusinessId = id
	local biz = if id and state then state.businesses[id] else nil
	local definition = if id then Businesses.get(id) else nil
	if not biz or not definition then
		contextBar.Visible = false
		return
	end
	if changed or not contextBar.Visible then
		UIKit.setIcon(contextIcon, definition.emoji, Icons.business(definition.id))
		UIKit.setIconColor(contextIcon, definition.theme.primary)
	end
	contextBar.Visible = true
	contextName.Text = definition.name
	local income = if biz.stats then biz.stats.income else 0
	contextInfo.Text = string.format("Level %d  •  %s/s", biz.level, Format.cash(income))
	if biz.level >= Config.MAX_BUSINESS_LEVEL then
		UIKit.setButtonText(contextLevelButton, "MAX LEVEL")
		UIKit.setButtonColor(contextLevelButton, C.Gold)
	else
		local cost = Formulas.levelUpCost(definition, biz.level)
		UIKit.setButtonText(contextLevelButton, "Level Up\n" .. Format.cash(cost))
		UIKit.setButtonColor(contextLevelButton, if controllers.Store.money() >= cost then C.Green else C.Grey)
	end
end

local function updateHud(state: any)
	local ownedCount = 0
	for _ in state.businesses do
		ownedCount += 1
	end
	cityRows.income.Text = Format.cash(state.income) .. "/s"
	cityRows.businesses.Text = ownedCount .. "/" .. #Businesses.List
	local rank = Config.Ranks[state.rank]
	cityRows.rank.Text = rank.emoji .. " " .. rank.name
	cityRows.rank.TextColor3 = rank.color
	local nextRank = Config.Ranks[state.rank + 1]
	if nextRank then
		rankBarSet((state.runEarned - rank.minEarned) / (nextRank.minEarned - rank.minEarned), "Next: " .. nextRank.name)
		cityRows.next.Text = Format.money(state.runEarned) .. " / " .. Format.money(nextRank.minEarned) .. " earned"
	else
		rankBarSet(1, "MAX RANK")
		cityRows.next.Text = if state.prestigeShops then "Top rank! Prestige for a bigger boost" else "Top rank! Every Prestige done 👑"
	end

	-- Prestige boost badge on the cash counter.
	local boosted = (state.prestige or 0) > 0
	boostBadge.Visible = boosted
	if boosted then
		boostLabel.Text = string.format("x%.1f", state.prestigeMultiplier)
	end
	local textWidth = if boosted then -88 else -18
	cashLabel.Size = UDim2.new(1, textWidth, 0, 28)
	incomeLabel.Size = UDim2.new(1, textWidth, 0, 16)
end

local function onState(state: any)
	updateHud(state)
	updateContextBar()
	if window.Visible and currentTab then
		if Panels.signature(currentTab, state, view()) ~= lastSignature then
			renderTab()
		else
			runUpdater()
		end
	end
end

----- Input -----
local function bindInput()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.U then
			if window.Visible and currentTab == "Businesses" and selectedBusiness then
				UIController.close()
			else
				UIController.openManage()
			end
			controllers.Sound.play("Click", 0.4)
			return
		end
		for _, info in MENU_BUTTONS do
			if info.key and input.KeyCode == info.key then
				UIController.toggle(info.tab)
				controllers.Sound.play("Click", 0.4)
			end
		end
	end)
	ContextActionService:BindActionAtPriority("CBS_ToggleMenu", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			if window.Visible then
				UIController.close()
			else
				UIController.open("Businesses")
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.ButtonSelect)
	ContextActionService:BindActionAtPriority("CBS_CloseMenu", function(_, inputState)
		if window.Visible then
			if inputState == Enum.UserInputState.Begin then
				if currentTab == "Businesses" and selectedBusiness then
					UIController.openBusiness(nil)
				else
					UIController.close()
				end
			end
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, 3000, Enum.KeyCode.ButtonB)
end

----- Lifecycle -----
function UIController.init(registry: any)
	controllers = registry
	Panels = require(script.Parent:WaitForChild("UIPanels"))
	UIKit.onClick = function()
		controllers.Sound.play("Click", 0.3)
	end

	hud = new("ScreenGui", {
		Name = "CityHUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		Parent = player:WaitForChild("PlayerGui"),
	})
	root = new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = hud })
	uiScale = new("UIScale", { Parent = root })

	overlay = new("ScreenGui", {
		Name = "CityOverlay",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
		Parent = player:WaitForChild("PlayerGui"),
	})
	fadeFrame = new("Frame", { Name = "Fade", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = overlay })

	buildCash()
	buildCityCard()
	buildMenuButtons()
	buildContextBar()
	buildWindow()

	toastList = new("Frame", { Name = "Toasts", BackgroundTransparency = 1, Size = UDim2.fromOffset(470, 280), Position = UDim2.fromOffset(0, 92), Parent = root })
	UIKit.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center).Parent = toastList
	popupLayer = new("Frame", { Name = "Popups", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root })
end

-- Big celebration when the server confirms a prestige.
local function prestigeCelebration(level: number)
	local holder = new("Frame", {
		Name = "PrestigeBurst",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(560, 560),
		ZIndex = 40,
		Parent = popupLayer,
	})
	local burst = new("ImageLabel", {
		Name = "Sunburst",
		Image = "rbxassetid://130563114903838",
		ImageColor3 = Color3.fromRGB(205, 130, 255),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 40,
		Parent = holder,
	})
	local title = UIKit.label({
		Text = "PRESTIGE " .. level .. "!",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(1, 0, 0, 74),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(240, 210, 255),
		MaxTextSize = 66,
		ZIndex = 42,
		Parent = holder,
	})
	local stroke = title:FindFirstChild("TextStroke") :: UIStroke?
	if stroke then
		stroke.Thickness = 4
	end
	local sub = UIKit.label({
		Text = string.format("All income x%.1f  •  Build it again!", Config.prestigeMultiplier(level)),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.57),
		Size = UDim2.new(1, 0, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Money,
		MaxTextSize = 30,
		ZIndex = 42,
		Parent = holder,
	})
	local scale = new("UIScale", { Scale = 0.2, Parent = holder })
	UIKit.tween(scale, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)
	UIKit.tween(burst, 3.2, { Rotation = 140 }, Enum.EasingStyle.Linear)
	controllers.Sound.play("LevelUp", 0.6)
	controllers.Sound.play("Firework", 0.5)
	task.delay(0.5, function()
		controllers.Sound.play("Cheer", 0.5)
	end)
	task.delay(2.7, function()
		UIKit.tween(scale, 0.35, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		UIKit.tween(burst, 0.35, { ImageTransparency = 1 })
		for _, label in { title, sub } do
			UIKit.tween(label, 0.35, { TextTransparency = 1 })
		end
		task.wait(0.4)
		holder:Destroy()
	end)
end

function UIController.start()
	local Store = controllers.Store
	-- Re-fit on any screen change; layout runs once the root has its new size.
	local function fitRoot()
		updateScale()
		layout()
	end
	fitRoot()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitRoot)
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	hud:GetAttributeChangedSignal("SimViewport"):Connect(fitRoot)
	hud:GetAttributeChangedSignal("SimTouch"):Connect(fitRoot)
	contextBar:GetPropertyChangedSignal("Visible"):Connect(layout)
	-- Guide chips are built by other controllers: place them when they appear.
	local function watchChip(child: Instance)
		if table.find(GUIDE_CHIPS, child.Name) and child:IsA("GuiObject") then
			child:GetPropertyChangedSignal("Visible"):Connect(layout)
			layout()
		end
	end
	root.ChildAdded:Connect(watchChip)
	for _, child in root:GetChildren() do
		watchChip(child)
	end
	Store.remote("Prestiged").OnClientEvent:Connect(function(level)
		if type(level) == "number" then
			UIController.close()
			prestigeCelebration(level)
		end
	end)

	Store.onChange(onState)
	Store.remote("Notify").OnClientEvent:Connect(function(kind, text)
		if type(kind) == "string" and type(text) == "string" then
			UIController.notify(kind, text)
		end
	end)
	Store.remote("CashPopup").OnClientEvent:Connect(function(amount, kind)
		if type(amount) == "number" then
			cashPopup(amount, kind)
		end
	end)
	player:GetAttributeChangedSignal("Money"):Connect(refreshAffordability)
	bindInput()

	-- VIP game pass: a golden tag in front of the owner's chat messages (the server sets
	-- the VIP attribute on the player once it has checked the pass).
	TextChatService.OnIncomingMessage = function(message: TextChatMessage): TextChatMessageProperties?
		local source = message.TextSource
		local speaker = if source then Players:GetPlayerByUserId(source.UserId) else nil
		if speaker and speaker:GetAttribute("VIP") == true then
			local properties = Instance.new("TextChatMessageProperties")
			properties.PrefixText = '<font color="#FFD23C">[⭐ VIP]</font> ' .. message.PrefixText
			return properties
		end
		return nil
	end

	-- Download the icon images up front so menus never open with empty tiles.
	task.spawn(function()
		local images = {}
		for _, image in Icons.Business do
			table.insert(images, image)
		end
		for _, image in Icons.Menu do
			table.insert(images, image)
		end
		table.insert(images, UIKit.CHECKER)
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync(images)
		end)
	end)

	-- Smooth cash counter + periodic context bar check.
	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		local target = Store.money()
		displayedMoney += (target - displayedMoney) * math.min(1, dt * 8)
		if math.abs(target - displayedMoney) < 1 then
			displayedMoney = target
		end
		cashLabel.Text = Format.cash(math.floor(displayedMoney + 0.5))
		local boosted = Store.state ~= nil and (tonumber(Store.state.incomeBoost) or 1) > 1
		incomeLabel.Text = "+" .. Format.cash(Store.income()) .. "/s" .. (if boosted then "  💰2×" else "")
		local badge = prestigeBadge
		if badge then
			local state = Store.state
			local needed = if state ~= nil then state.prestigeShops else nil
			local ready = type(needed) == "number" and Config.countShops(state.businesses) >= needed
			if badge.Visible ~= ready then
				badge.Visible = ready
			end
		end
		accumulator += dt
		if accumulator > 0.4 then
			accumulator = 0
			if Store.state then
				updateContextBar()
			end
		end
	end)
end

return UIController
