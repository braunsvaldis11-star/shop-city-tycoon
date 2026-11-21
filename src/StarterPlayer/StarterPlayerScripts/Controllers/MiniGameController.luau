--!strict
-- MiniGameController (client): draws and plays the owner's mini game (F at the counter
-- inside your own business). The server makes each order and checks the answer
-- (MiniGameService); this window only draws it and reports what the player did.
-- The five kinds of game come from Shared.MiniGames: recipe, pick, cash, timing, memory.
-- Container: StarterPlayerScripts.Controllers

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientModules = ReplicatedStorage:WaitForChild("Client")
local Format = require(Shared.Format)
local MiniGames = require(Shared.MiniGames)
local UIKit = require(ClientModules.UIKit)

local MiniGameController = {}

local C = UIKit.Colors
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local SOFT_RED = Color3.fromRGB(255, 120, 120)
local CENTER = Enum.TextXAlignment.Center
local BORDER = Enum.ApplyStrokeMode.Border
local WIDTH, HEIGHT = 700, 450
local BODY_TOP, BODY_H = 72, 332
local WORK_W = WIDTH - 250
local THEMES: { [string]: string } = { recipe = "Amber", pick = "Cyan", cash = "Lime", timing = "Magenta", memory = "Purple" }
local ORDER_TIMEOUT = 4 -- seconds to wait for the server's order / verdict
local PRIORITY = Enum.ContextActionPriority.High.Value + 10

local controllers: any
local player = Players.LocalPlayer
local rng = Random.new()

type Session = {
	businessId: string,
	game: MiniGames.Game,
	token: string?,
	order: MiniGames.Order?,
	sale: number,
	mistakes: number,
	submitted: boolean,
}

local session: Session? = nil
local roundId = 0 -- bumps on every new order / close, so old timers and loops stop
local roundCleanup: { () -> () } = {}

-- Window (built on first use)
local screen: ScreenGui? = nil
local windowScale: UIScale? = nil
local window: Frame
local header: Frame
local title: TextLabel
local ticketBody: Frame
local workBody: Frame
local statusLabel: TextLabel
local splash: Frame? = nil
local mistakesLabel: TextLabel? = nil
local refreshTicket: (() -> ())? = nil

----- Helpers -----
local function playSound(name: string, volume: number?)
	local sound = controllers and controllers.Sound
	if sound and sound.play then
		sound.play(name, volume)
	end
end

local function setStatus(text: string, color: Color3?)
	statusLabel.Text = text
	statusLabel.TextColor3 = color or WHITE
end

local function addCleanup(fn: () -> ())
	table.insert(roundCleanup, fn)
end

local function runCleanup()
	local list = roundCleanup
	roundCleanup = {}
	for _, fn in list do
		pcall(fn)
	end
end

local function redrawTicket()
	local refresh = refreshTicket
	if refresh then
		refresh()
	end
end

local function circle(parent: Instance, diameter: number, color: Color3, transparency: number?): Frame
	local frame = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(diameter, diameter),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency or 0,
		BorderSizePixel = 0,
		Parent = parent,
	})
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = frame })
	UIKit.new("UIStroke", { Color = C.Ink, Thickness = 2, Transparency = 0.35, ApplyStrokeMode = BORDER, Parent = frame })
	return frame
end

local function popIn(object: GuiObject, from: number)
	local scale = object:FindFirstChildOfClass("UIScale") or UIKit.new("UIScale", { Parent = object })
	scale.Scale = from
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function grid(parent: Instance, position: UDim2, size: UDim2, cell: Vector2, gap: number): Frame
	local frame = UIKit.new("Frame", { BackgroundTransparency = 1, Position = position, Size = size, Parent = parent })
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(cell.X, cell.Y),
		CellPadding = UDim2.fromOffset(gap, gap),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})
	return frame
end

local function well(parent: Instance, position: UDim2, size: UDim2): Frame
	local frame = UIKit.new("Frame", {
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Position = position,
		Size = size,
		ClipsDescendants = true,
		Parent = parent,
	})
	UIKit.corner(6).Parent = frame
	return frame
end

local function itemButton(parent: Instance, item: MiniGames.Item, order: number, onClick: () -> ()): TextButton
	return UIKit.button({
		Name = item.id,
		Text = item.name,
		Emoji = item.emoji,
		Stack = true,
		Color = item.color,
		LayoutOrder = order,
		MaxTextSize = 14,
		Size = UDim2.fromOffset(82, 74),
		Parent = parent,
	}, onClick)
end

local function focusFirst(container: Instance)
	if not UserInputService.GamepadEnabled then
		return
	end
	for _, child in container:GetChildren() do
		if child:IsA("GuiButton") then
			GuiService.SelectedObject = child
			return
		end
	end
end

-- Wrong answer: the button wobbles and flashes red.
local function shake(button: GuiObject, color: Color3)
	local face = button:FindFirstChild("Face") :: Frame?
	if not face then
		return
	end
	UIKit.setButtonColor(button, C.Red)
	face.Rotation = -7
	TweenService:Create(face, TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true), { Rotation = 7 }):Play()
	task.delay(0.36, function()
		face.Rotation = 0
		UIKit.setButtonColor(button, color)
	end)
end

local function mistake(button: GuiObject?, color: Color3?, text: string)
	local s = session
	if not s then
		return
	end
	s.mistakes += 1
	if button and color then
		shake(button, color)
	end
	playSound("Error", 0.5)
	setStatus(text, SOFT_RED)
	if mistakesLabel then
		mistakesLabel.Text = "❌ Mistakes: " .. s.mistakes
	end
end

----- Result splash -----
local newRound: () -> ()

local function hideSplash()
	if splash then
		splash:Destroy()
		splash = nil
	end
end

local function showSplash(gradeIndex: number?, reward: number)
	hideSplash()
	setStatus("")
	local grade = if gradeIndex then MiniGames.GRADES[gradeIndex] else nil
	local frame = UIKit.new("Frame", {
		Name = "Splash",
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.03,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(6, 62),
		Size = UDim2.new(1, -12, 1, -68),
		ZIndex = 20,
		Parent = window,
	})
	UIKit.corner(6).Parent = frame
	local content = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 300),
		Parent = frame,
	})
	local pop = UIKit.new("UIScale", { Scale = 0.6, Parent = content })
	TweenService:Create(pop, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local function line(text: string, y: number, height: number, size: number, color: Color3, stroke: boolean?)
		UIKit.label({ Text = text, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, height), TextXAlignment = CENTER, MaxTextSize = size, TextColor3 = color, Stroke = stroke ~= false, Parent = content })
	end
	if grade then
		line(string.rep("⭐", grade.stars), 0, 50, 46, WHITE, false)
		line(grade.name, 52, 64, 58, grade.color)
		line("+" .. Format.money(reward), 122, 50, 44, C.Money)
		local note = if gradeIndex == 1 then "No mistakes: double pay!" elseif gradeIndex == 2 then "Almost perfect: x1.5 pay" else "Fewer mistakes pay more!"
		line(note, 176, 28, 20, C.Muted)
	else
		line("😕", 0, 60, 54, WHITE, false)
		line("That order didn't count", 70, 48, 36, SOFT_RED)
		line("Take your time and try another one!", 126, 30, 20, C.Muted)
	end
	local nextButton = UIKit.button({
		Name = "Next", Text = "NEXT ▶", Color = C.Green, MaxTextSize = 26,
		Size = UDim2.fromOffset(190, 58), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(0.5, -8, 0, 222), Parent = content,
	}, function()
		newRound()
	end)
	UIKit.button({
		Name = "Done", Text = "DONE", Color = C.Grey, MaxTextSize = 26,
		Size = UDim2.fromOffset(190, 58), Position = UDim2.new(0.5, 8, 0, 222), Parent = content,
	}, function()
		MiniGameController.close()
	end)
	splash = frame
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = nextButton
	end
end

-- The player finished: send the answer and wait for the server's verdict.
local function finish(answer: any)
	local s = session
	if not s or s.submitted or not s.token then
		return
	end
	s.submitted = true
	local token = s.token
	local myRound = roundId
	setStatus("✨ Done! Checking...", C.Gold)
	task.delay(0.3, function()
		if roundId == myRound and session == s then
			controllers.Store.send("MiniGameSubmit", token, answer, s.mistakes)
		end
	end)
	task.delay(0.3 + ORDER_TIMEOUT, function()
		if roundId == myRound and session == s and not splash then
			showSplash(nil, 0)
		end
	end)
end

----- Ticket (left card) -----
local function ticketRow(parent: Instance, index: number, text: string, state: string)
	local current = state == "current"
	local row = UIKit.new("Frame", {
		Name = "Row" .. index,
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = if current then Color3.fromRGB(255, 205, 0) else C.PanelDark,
		BackgroundTransparency = if current then 0.55 else 0.3,
		BorderSizePixel = 0,
		Parent = parent,
	})
	UIKit.corner(5).Parent = row
	if current then
		UIKit.new("UIStroke", { Color = C.Gold, Thickness = 2, ApplyStrokeMode = BORDER, Parent = row })
	end
	UIKit.label({
		Text = text,
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, -38, 1, -8),
		MaxTextSize = 16,
		TextColor3 = if state == "done" then C.Muted else WHITE,
		Parent = row,
	})
	local mark = if state == "done" then "✅" elseif state == "miss" then "❌" elseif current then "👉" else ""
	UIKit.label({
		Text = mark,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -5, 0.5, 0),
		Size = UDim2.fromOffset(22, 22),
		TextXAlignment = CENTER,
		MaxTextSize = 18,
		Stroke = false,
		Parent = row,
	})
end

-- Builds the ticket; `rows` returns { text, state } pairs and is re-run on every change.
local function buildTicket(headline: string, rows: () -> { { any } })
	local s = session :: Session
	ticketBody:ClearAllChildren()
	UIKit.label({ Text = headline, Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 0, 26), MaxTextSize = 21, Parent = ticketBody })
	local list = UIKit.new("Frame", { Name = "Rows", BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 40), Size = UDim2.new(1, -16, 0, 196), Parent = ticketBody })
	UIKit.list(nil, 4).Parent = list
	UIKit.new("Frame", { BackgroundColor3 = C.Highlight, BackgroundTransparency = 0.5, BorderSizePixel = 0, Position = UDim2.fromOffset(10, 242), Size = UDim2.new(1, -20, 0, 2), Parent = ticketBody })
	local sale = math.max(s.sale, 10)
	UIKit.label({ Text = "💵 Sale: " .. Format.money(sale), Position = UDim2.fromOffset(10, 250), Size = UDim2.new(1, -20, 0, 22), MaxTextSize = 17, TextColor3 = C.Money, Parent = ticketBody })
	UIKit.label({ Text = "⭐ Perfect: " .. Format.money(sale * 2), Position = UDim2.fromOffset(10, 275), Size = UDim2.new(1, -20, 0, 20), MaxTextSize = 15, TextColor3 = C.Gold, Parent = ticketBody })
	mistakesLabel = UIKit.label({ Text = "❌ Mistakes: 0", Position = UDim2.fromOffset(10, 299), Size = UDim2.new(1, -20, 0, 20), MaxTextSize = 15, TextColor3 = C.Muted, Parent = ticketBody })
	refreshTicket = function()
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for i, entry in rows() do
			ticketRow(list, i, entry[1], entry[2])
		end
	end
	redrawTicket()
end

local function itemText(game: MiniGames.Game, id: string): string
	local item = MiniGames.item(game, id)
	return if item then item.emoji .. " " .. item.name else id
end

----- Recipe: what is being made, drawn as it grows -----
local function recipePreview(parent: Instance, game: MiniGames.Game): (MiniGames.Item) -> ()
	local area = well(parent, UDim2.fromOffset(8, 8), UDim2.new(1, -16, 0, 150))
	local layers = 0
	if game.look == "round" then
		circle(area, 146, Color3.fromRGB(196, 146, 92), 0.15) -- wooden peel
		return function(item: MiniGames.Item)
			layers += 1
			local piece: GuiObject
			if layers == 1 then
				piece = circle(area, 132, item.color)
			elseif layers == 2 then
				piece = circle(area, 114, item.color)
			elseif layers == 3 then
				piece = circle(area, 106, item.color, 0.08)
			else
				-- Toppings: scattered over the cheese.
				piece = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(106, 106), Parent = area })
				local turn = rng:NextNumber(0, math.pi * 2)
				for k = 1, 6 do
					local angle = turn + k * math.pi / 3
					local radius = if k % 2 == 0 then 34 else 19
					UIKit.label({
						Text = item.emoji,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(0.5, math.cos(angle) * radius, 0.5, math.sin(angle) * radius),
						Size = UDim2.fromOffset(24, 24),
						TextXAlignment = CENTER,
						MaxTextSize = 24,
						Stroke = false,
						Parent = piece,
					})
				end
			end
			popIn(piece, 1.25)
		end
	end
	-- Stacked look: each ingredient is a layer on the plate.
	local plate = UIKit.new("Frame", { BackgroundColor3 = Color3.fromRGB(205, 212, 220), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.fromOffset(236, 10), Parent = area })
	UIKit.corner(5).Parent = plate
	return function(item: MiniGames.Item)
		layers += 1
		local bar = UIKit.new("Frame", {
			BackgroundColor3 = item.color,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -16 - (layers - 1) * 20),
			Size = UDim2.fromOffset(196 - (layers % 2) * 14, 19),
			Parent = area,
		})
		UIKit.corner(8).Parent = bar
		UIKit.new("UIStroke", { Color = C.Ink, Thickness = 2, ApplyStrokeMode = BORDER, Parent = bar })
		UIKit.label({ Text = item.emoji .. " " .. item.name, Position = UDim2.fromOffset(6, 1), Size = UDim2.new(1, -12, 1, -2), TextXAlignment = CENTER, MaxTextSize = 14, Parent = bar })
		popIn(bar, 1.3)
	end
end

----- Game kinds -----
local builders: { [string]: (Session, MiniGames.Order) -> () } = {}

builders.recipe = function(s: Session, order: MiniGames.Order)
	local game = s.game
	local list = order.list or {}
	local done = 0
	local answer: { string } = {}
	buildTicket("🧾 ORDER", function()
		local rows = {}
		for i, id in list do
			table.insert(rows, { i .. ". " .. itemText(game, id), if i <= done then "done" elseif i == done + 1 then "current" else "todo" })
		end
		return rows
	end)
	local addLayer = recipePreview(workBody, game)
	local buttons = grid(workBody, UDim2.fromOffset(8, 166), UDim2.new(1, -16, 0, 158), Vector2.new(82, 74), 6)
	for index, item in game.items do
		local button: TextButton
		button = itemButton(buttons, item, index, function()
			if s.submitted or session ~= s then
				return
			end
			local expected = list[done + 1]
			if item.id == expected then
				done += 1
				table.insert(answer, item.id)
				addLayer(item)
				redrawTicket()
				if done >= #list then
					finish(answer)
				else
					setStatus("Next: " .. itemText(game, list[done + 1]))
				end
			else
				mistake(button, item.color, "Oops! The ticket says " .. itemText(game, expected) .. " next.")
			end
		end)
	end
	focusFirst(buttons)
end

builders.pick = function(s: Session, order: MiniGames.Order)
	local game = s.game
	local list = order.list or {}
	local found: { string } = {}
	buildTicket("📝 SHOPPING LIST", function()
		local rows = {}
		for _, id in list do
			table.insert(rows, { itemText(game, id), if table.find(found, id) then "done" else "todo" })
		end
		return rows
	end)
	local bag = well(workBody, UDim2.fromOffset(8, 8), UDim2.new(1, -16, 0, 58))
	UIKit.label({ Text = "🧺 Bag", Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0, 84, 1, 0), MaxTextSize = 20, Parent = bag })
	local slots = UIKit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(96, 6), Size = UDim2.new(1, -104, 1, -12), Parent = bag })
	local slotList = UIKit.list(Enum.FillDirection.Horizontal, 6)
	slotList.VerticalAlignment = Enum.VerticalAlignment.Center
	slotList.Parent = slots
	-- The shelf: every item, shuffled each order. Five tiles to a row (the width of the
	-- recipe buttons); tiles get shorter if a game ever needs more than two rows.
	local SHELF_HEIGHT, SHELF_GAP = 240, 6
	local shelfRows = math.max(1, math.ceil(#game.items / 5))
	local tileHeight = math.min(112, math.floor((SHELF_HEIGHT - SHELF_GAP * (shelfRows - 1)) / shelfRows))
	local shelf = grid(workBody, UDim2.fromOffset(8, 78), UDim2.new(1, -16, 0, SHELF_HEIGHT), Vector2.new(82, tileHeight), SHELF_GAP)
	local shown = table.clone(game.items)
	for i = #shown, 2, -1 do
		local j = rng:NextInteger(1, i)
		shown[i], shown[j] = shown[j], shown[i]
	end
	for index, item in shown do
		local button: TextButton
		button = itemButton(shelf, item, index, function()
			if s.submitted or session ~= s or table.find(found, item.id) then
				return
			end
			if table.find(list, item.id) then
				table.insert(found, item.id)
				UIKit.setButtonColor(button, C.Grey)
				UIKit.setButtonText(button, "✓ " .. item.name)
				local icon = UIKit.icon({ Text = item.emoji, Color = item.color, Size = UDim2.fromOffset(44, 44), LayoutOrder = #found, Parent = slots })
				popIn(icon, 1.4)
				redrawTicket()
				local left = #list - #found
				if left <= 0 then
					finish(table.clone(found))
				else
					setStatus(string.format("Got it! %d more to find.", left), C.Money)
				end
			else
				mistake(button, item.color, item.emoji .. " " .. item.name .. " isn't on the list!")
			end
		end)
	end
	focusFirst(shelf)
end

builders.cash = function(s: Session, order: MiniGames.Order)
	local game = s.game
	local target = order.target or 0
	local given: { number } = {}
	local total = 0
	buildTicket("🏦 WITHDRAWAL", function()
		return {
			{ "Wants: $" .. target, if total == target then "done" else "current" },
			{ "Given: $" .. total, "todo" },
			{ "Left: $" .. math.max(target - total, 0), "todo" },
		}
	end)
	UIKit.label({ Text = "Hand over exactly $" .. target, Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 36), TextXAlignment = CENTER, MaxTextSize = 28, TextColor3 = C.Money, Parent = workBody })
	local _, setBar = UIKit.progressBar({ Text = "$0 / $" .. target, Color = C.Green, Position = UDim2.fromOffset(20, 50), Size = UDim2.new(1, -40, 0, 26), MaxTextSize = 16, Parent = workBody })
	local tray = well(workBody, UDim2.fromOffset(8, 86), UDim2.new(1, -16, 0, 84))
	UIKit.padding(6).Parent = tray
	UIKit.new("UIGridLayout", { CellSize = UDim2.fromOffset(56, 22), CellPadding = UDim2.fromOffset(4, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tray })
	local function redraw()
		for _, child in tray:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for i, bill in given do
			local item = MiniGames.item(game, tostring(bill))
			local chip = UIKit.new("Frame", { BackgroundColor3 = if item then item.color else C.Green, BorderSizePixel = 0, LayoutOrder = i, Parent = tray })
			UIKit.corner(4).Parent = chip
			UIKit.new("UIStroke", { Color = C.Ink, Thickness = 1.5, ApplyStrokeMode = BORDER, Parent = chip })
			UIKit.label({ Text = "$" .. bill, Size = UDim2.fromScale(1, 1), TextXAlignment = CENTER, MaxTextSize = 14, Parent = chip })
		end
		setBar(total / math.max(target, 1), "$" .. total .. " / $" .. target)
		redrawTicket()
	end
	local function startOver()
		table.clear(given)
		total = 0
		redraw()
	end
	local bills = grid(workBody, UDim2.fromOffset(8, 178), UDim2.new(1, -16, 0, 112), Vector2.new(132, 52), 8)
	for index, bill in MiniGames.BILLS do
		local item = MiniGames.item(game, tostring(bill))
		UIKit.button({
			Name = "Bill" .. bill, Text = "$" .. bill, Emoji = "💵", Color = if item then item.color else C.Green,
			LayoutOrder = index, MaxTextSize = 22, Size = UDim2.fromOffset(132, 52), Parent = bills,
		}, function()
			if s.submitted or session ~= s then
				return
			end
			if #given >= MiniGames.MAX_BILLS then
				startOver()
				mistake(nil, nil, "Too many bills! Use bigger ones.")
				return
			end
			table.insert(given, bill)
			total += bill
			if total > target then
				startOver()
				mistake(nil, nil, "Too much! That's over $" .. target .. ". Start again.")
			elseif total == target then
				redraw()
				finish(table.clone(given))
			else
				redraw()
				setStatus("$" .. (target - total) .. " to go.")
			end
		end)
	end
	UIKit.button({
		Name = "StartOver", Text = "🔄 Start over", Color = C.Red, MaxTextSize = 16,
		Size = UDim2.fromOffset(170, 32), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 296), Parent = workBody,
	}, function()
		if not s.submitted and session == s then
			startOver()
			setStatus("Counting from $0 again.", C.Muted)
		end
	end)
	redraw()
	focusFirst(bills)
end

builders.timing = function(s: Session, order: MiniGames.Order)
	local game = s.game
	local zones = order.zones or {}
	local round = 1
	local results: { [number]: boolean } = {}
	local hits = 0
	buildTicket("🎯 ROUNDS", function()
		local rows = {}
		for i = 1, #zones do
			local result = results[i]
			table.insert(rows, { "Round " .. i, if result == true then "done" elseif result == false then "miss" elseif i == round then "current" else "todo" })
		end
		return rows
	end)
	local hitsLabel = mistakesLabel
	if hitsLabel then
		hitsLabel.Text = "🎯 Hits: 0 / " .. #zones
	end
	local big = UIKit.label({ Text = game.emoji, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(110, 96), TextXAlignment = CENTER, MaxTextSize = 90, Stroke = false, Parent = workBody })
	local bigScale = UIKit.new("UIScale", { Parent = big })
	local roundLabel = UIKit.label({ Text = "", Position = UDim2.fromOffset(8, 104), Size = UDim2.new(1, -16, 0, 26), TextXAlignment = CENTER, MaxTextSize = 20, Parent = workBody })
	local track = UIKit.new("Frame", { BackgroundColor3 = C.PanelDark, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 140), Size = UDim2.fromOffset(400, 44), Parent = workBody })
	UIKit.corner(8).Parent = track
	UIKit.new("UIStroke", { Color = C.Ink, Thickness = 3, ApplyStrokeMode = BORDER, Parent = track })
	local zone = UIKit.new("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromScale(0.2, 1), Parent = track })
	UIKit.corner(6).Parent = zone
	UIKit.gradient(Color3.fromRGB(180, 255, 25), Color3.fromRGB(80, 200, 0)).Parent = zone
	local marker = UIKit.new("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0, 10, 1, 16), ZIndex = 3, Parent = track })
	UIKit.corner(4).Parent = marker
	UIKit.new("UIStroke", { Color = C.Ink, Thickness = 2.5, ApplyStrokeMode = BORDER, Parent = marker })

	local roundStart = os.clock()
	local waiting = false
	local x = 0
	local function setupRound()
		local z = zones[round]
		zone.Position = UDim2.fromScale(z[1], 0)
		zone.Size = UDim2.fromScale(z[2], 1)
		roundLabel.Text = string.format("Round %d of %d", round, #zones)
		roundStart = os.clock()
		waiting = false
	end
	local function tap()
		if waiting or s.submitted or session ~= s then
			return
		end
		local z = zones[round]
		local hit = math.abs(x - z[1]) <= z[2] / 2
		waiting = true
		results[round] = hit
		if hit then
			hits += 1
			playSound("Click", 0.7)
			setStatus("✅ Nice timing!", C.Money)
			bigScale.Scale = 1.35
			TweenService:Create(bigScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		else
			playSound("Error", 0.5)
			setStatus("❌ Missed! Wait for the green zone.", SOFT_RED)
		end
		if hitsLabel then
			hitsLabel.Text = string.format("🎯 Hits: %d / %d", hits, #zones)
		end
		redrawTicket()
		local myRound = roundId
		task.delay(0.6, function()
			if roundId ~= myRound or session ~= s then
				return
			end
			if round >= #zones then
				finish(hits)
			else
				round += 1
				setupRound()
				redrawTicket()
				setStatus(game.hint)
			end
		end)
	end
	UIKit.button({
		Name = "Tap", Text = game.verb or "TAP!", Color = C.Orange, MaxTextSize = 34,
		Size = UDim2.fromOffset(240, 70), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 204), Parent = workBody,
	}, tap)
	local keys = if UserInputService.GamepadEnabled then "or press A" elseif UserInputService.KeyboardEnabled then "or press Space" else ""
	UIKit.label({ Text = keys, Position = UDim2.fromOffset(8, 284), Size = UDim2.new(1, -16, 0, 22), TextXAlignment = CENTER, MaxTextSize = 16, TextColor3 = C.Muted, Parent = workBody })
	ContextActionService:BindActionAtPriority("MiniGameTap", function(_, state)
		if state == Enum.UserInputState.Begin then
			tap()
		end
		return Enum.ContextActionResult.Sink
	end, false, PRIORITY, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	addCleanup(function()
		ContextActionService:UnbindAction("MiniGameTap")
	end)
	local connection = RunService.RenderStepped:Connect(function()
		if waiting then
			return
		end
		local phase = (os.clock() - roundStart) / zones[round][3]
		x = 1 - math.abs((phase % 2) - 1) -- sweeps left -> right -> left
		marker.Position = UDim2.fromScale(x, 0.5)
	end)
	addCleanup(function()
		connection:Disconnect()
	end)
	setupRound()
end

builders.memory = function(s: Session, order: MiniGames.Order)
	local game = s.game
	local list = order.list or {}
	local step = 0
	local accepting = false
	buildTicket("🧠 SEQUENCE", function()
		local rows = {}
		for i = 1, #list do
			table.insert(rows, { "Step " .. i, if i <= step then "done" elseif accepting and i == step + 1 then "current" else "todo" })
		end
		return rows
	end)
	local phase = UIKit.label({ Text = "", Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 0, 32), TextXAlignment = CENTER, MaxTextSize = 24, Parent = workBody })
	local pads = grid(workBody, UDim2.fromOffset(8, 46), UDim2.new(1, -16, 0, 276), Vector2.new(205, 130), 10)
	local buttons: { [string]: TextButton } = {}
	local myRound = roundId
	local function flash(id: string)
		local button = buttons[id]
		local item = MiniGames.item(game, id)
		if not button or not item then
			return
		end
		UIKit.setButtonColor(button, item.color:Lerp(WHITE, 0.6))
		local face = button:FindFirstChild("Face")
		local faceScale = face and face:FindFirstChildOfClass("UIScale")
		if faceScale then
			faceScale.Scale = 1.08
		end
		task.delay(0.32, function()
			UIKit.setButtonColor(button, item.color)
			if faceScale then
				TweenService:Create(faceScale, TweenInfo.new(0.12), { Scale = 1 }):Play()
			end
		end)
	end
	local function playback()
		accepting = false
		step = 0
		redrawTicket()
		phase.Text = "👀 Watch closely..."
		phase.TextColor3 = C.Gold
		task.spawn(function()
			task.wait(0.7)
			for _, id in list do
				if roundId ~= myRound or session ~= s then
					return
				end
				flash(id)
				playSound("Click", 0.5)
				task.wait(0.55)
			end
			if roundId ~= myRound or session ~= s then
				return
			end
			accepting = true
			phase.Text = "👉 Your turn!"
			phase.TextColor3 = C.Money
			redrawTicket()
		end)
	end
	for index, item in game.items do
		local button: TextButton
		button = UIKit.button({
			Name = item.id, Text = item.name, Emoji = item.emoji, Stack = true, Color = item.color,
			LayoutOrder = index, MaxTextSize = 20, Size = UDim2.fromOffset(205, 130), Parent = pads,
		}, function()
			if not accepting or s.submitted or session ~= s then
				return
			end
			if item.id == list[step + 1] then
				step += 1
				flash(item.id)
				redrawTicket()
				if step >= #list then
					accepting = false
					phase.Text = "🎉 Got it!"
					finish(table.clone(list))
				end
			else
				mistake(button, item.color, "Oops! Watch again...")
				playback()
			end
		end)
		buttons[item.id] = button
	end
	playback()
	focusFirst(pads)
end

----- Rounds -----
newRound = function()
	local s = session
	if not s then
		return
	end
	roundId += 1
	runCleanup()
	hideSplash()
	ticketBody:ClearAllChildren()
	workBody:ClearAllChildren()
	mistakesLabel = nil
	refreshTicket = nil
	s.token = nil
	s.order = nil
	s.mistakes = 0
	s.submitted = false
	setStatus("📋 Getting the next order...", C.Muted)
	local myRound = roundId
	controllers.Store.send("MiniGameStart", s.businessId)
	task.delay(ORDER_TIMEOUT, function()
		if roundId == myRound and session == s and not s.token then
			showSplash(nil, 0)
		end
	end)
end

local function onOrder(token: any, businessId: any, order: any, sale: any)
	local s = session
	if not s or s.token or businessId ~= s.businessId or type(token) ~= "string" then
		return
	end
	if type(order) ~= "table" or order.kind ~= s.game.kind then
		return
	end
	s.token = token
	s.order = order
	s.sale = if type(sale) == "number" then sale else 0
	setStatus(s.game.hint)
	local build = builders[order.kind]
	if build then
		build(s, order)
	end
	local line = MiniGames.describe(s.game, order)
	local interior = controllers.Interior
	if line and interior and interior.customerSays then
		interior.customerSays(line)
	end
end

local function onResult(token: any, ok: any, reward: any, gradeIndex: any)
	local s = session
	if not s or token ~= s.token or splash then
		return
	end
	if ok == true and type(reward) == "number" and type(gradeIndex) == "number" and MiniGames.GRADES[gradeIndex] then
		showSplash(gradeIndex, reward)
		playSound(if gradeIndex == 1 then "LevelUp" else "Cash", 0.6)
		local interior = controllers.Interior
		if interior and interior.serveFront then
			interior.serveFront()
		end
	else
		showSplash(nil, 0)
		playSound("Error", 0.5)
	end
end

----- Window -----
local function fit()
	local camera = Workspace.CurrentCamera
	local scale = windowScale
	if not camera or not scale then
		return
	end
	local size = camera.ViewportSize
	scale.Scale = math.clamp(math.min((size.X - 20) / WIDTH, (size.Y - 20) / HEIGHT), 0.4, 1.1)
end

local function ensureGui()
	if screen then
		return
	end
	local gui = UIKit.new("ScreenGui", {
		Name = "MiniGame",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 40,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	UIKit.new("Frame", { Name = "Dim", BackgroundColor3 = BLACK, BackgroundTransparency = 0.72, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = gui })
	window = UIKit.panel({ Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(WIDTH, HEIGHT), Parent = gui })
	windowScale = UIKit.new("UIScale", { Parent = window })
	header = UIKit.header(window, 58)
	title = UIKit.label({ Name = "Title", Text = "", Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -90, 0, 38), MaxTextSize = 30, ZIndex = 3, Parent = header })
	UIKit.closeButton({ Position = UDim2.new(1, -32, 0, 27), Parent = header }, function()
		MiniGameController.close()
	end)
	local ticketCard = UIKit.card({ Name = "Ticket", Position = UDim2.fromOffset(14, BODY_TOP), Size = UDim2.fromOffset(212, BODY_H), Parent = window })
	ticketBody = UIKit.new("Frame", { Name = "Body", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = ticketCard })
	local workCard = UIKit.card({ Name = "Work", Position = UDim2.fromOffset(236, BODY_TOP), Size = UDim2.fromOffset(WORK_W, BODY_H), Parent = window })
	workBody = UIKit.new("Frame", { Name = "Body", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = workCard })
	statusLabel = UIKit.label({ Name = "Status", Text = "", Position = UDim2.new(0, 16, 1, -42), Size = UDim2.new(1, -32, 0, 32), TextXAlignment = CENTER, MaxTextSize = 20, Parent = window })
	screen = gui
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
end

function MiniGameController.isOpen(): boolean
	return session ~= nil
end

-- Opens the mini game of the business the player is standing in.
function MiniGameController.open(businessId: string)
	if session then
		return
	end
	local interior = controllers.Interior
	if not interior or interior.currentBusiness() ~= businessId then
		return
	end
	ensureGui()
	local game = MiniGames.get(businessId)
	pcall(function()
		controllers.UI.close()
	end)
	session = { businessId = businessId, game = game, token = nil, order = nil, sale = 0, mistakes = 0, submitted = false }
	title.Text = game.emoji .. "  " .. string.upper(game.action)
	UIKit.setHeaderTheme(header, UIKit.Themes[THEMES[game.kind] or "Amber"])
	local gui = screen :: ScreenGui
	gui.Enabled = true
	fit()
	local scale = windowScale :: UIScale
	local target = scale.Scale
	scale.Scale = target * 0.85
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
	ContextActionService:BindActionAtPriority("MiniGameBack", function(_, state)
		if state == Enum.UserInputState.Begin then
			MiniGameController.close()
		end
		return Enum.ContextActionResult.Sink
	end, false, PRIORITY, Enum.KeyCode.ButtonB)
	newRound()
end

function MiniGameController.close()
	if not session then
		return
	end
	session = nil
	roundId += 1
	runCleanup()
	hideSplash()
	ContextActionService:UnbindAction("MiniGameBack")
	local gui = screen
	if gui then
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(gui) then
			GuiService.SelectedObject = nil
		end
		gui.Enabled = false
		ticketBody:ClearAllChildren()
		workBody:ClearAllChildren()
	end
	mistakesLabel = nil
	refreshTicket = nil
end

function MiniGameController.init(registry: any)
	controllers = registry
end

function MiniGameController.start()
	local Store = controllers.Store
	Store.remote("MiniGameOrder").OnClientEvent:Connect(function(...)
		local ok, err = pcall(onOrder, ...)
		if not ok then
			warn("[MiniGameController] order: " .. tostring(err))
		end
	end)
	Store.remote("MiniGameResult").OnClientEvent:Connect(function(...)
		local ok, err = pcall(onResult, ...)
		if not ok then
			warn("[MiniGameController] result: " .. tostring(err))
		end
	end)
end

return MiniGameController
