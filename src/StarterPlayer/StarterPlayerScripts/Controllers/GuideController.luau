--!strict
-- GuideController (client): the getting-started guide for new players.
-- A chip at the bottom of the screen walks a brand-new player through their first
-- minutes, one step at a time:
--   1. Buy your first shop (the Pizza Restaurant; you start with exactly its price)
--   2. Go inside and play the mini game at the counter (a bouncing arrow marks it)
--   3. Buy an upgrade (or level the shop up)
--   4. Save up for your 2nd shop and buy it
-- Every step is worked out from the state the server already syncs (shops owned, stats,
-- money), so nothing extra is saved: the guide ends once you own two shops, and players
-- past that never see it. After a prestige only step 1 comes back, as a "fresh start".
-- Container: StarterPlayerScripts.Controllers

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Businesses = require(Shared.Businesses)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local MiniGames = require(Shared.MiniGames)
local UIKit = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("UIKit"))

local GuideController = {}

local controllers: any
local player = Players.LocalPlayer

type Step = "buy" | "play" | "upgrade" | "second"

type Content = {
	title: string,
	text: string,
	progress: number?,
	progressText: string?,
	button: string,
	color: Color3,
	action: () -> (),
}

local STEP_NUMBER: { [Step]: number } = { buy = 1, play = 2, upgrade = 3, second = 4 }
local STEP_COUNT = 4
-- Shown when a step is finished (the first purchase has its own Grand Opening).
local STEP_DONE: { [Step]: string } = {
	play = "✅ Nice! Every mini game pays you extra cash.",
	upgrade = "✅ Upgraded! Your shop earns more now.",
}
local CHIP_W, CHIP_H = 480, 80
local YELLOW = Color3.fromRGB(255, 220, 60)
local C = UIKit.Colors

----- Working out the step -----
local function ownedIds(state: any): { string }
	local ids = {}
	for id in state.businesses do
		table.insert(ids, id)
	end
	return ids
end

-- The step this player is on and the business it is about, or nil when the guide is
-- finished (or was never for them).
local function currentStep(state: any): (Step?, string?)
	if not state or not state.businesses then
		return nil, nil
	end
	if state.starterShop then
		return "buy", state.starterShop
	end
	local owned = ownedIds(state)
	if #owned ~= 1 or (state.prestige or 0) > 0 then
		return nil, nil
	end
	local stats = state.stats or {}
	if (stats.served or 0) < 1 then
		return "play", owned[1]
	end
	if (stats.upgradesBought or 0) < 1 and (stats.levelUps or 0) < 1 then
		return "upgrade", owned[1]
	end
	return "second", owned[1]
end

-- The cheapest upgrade this business can buy right now.
local function cheapestUpgrade(definition: Businesses.Definition, business: any): number?
	local best: number? = nil
	for _, upgrade in Businesses.Upgrades do
		local level = business.upgrades[upgrade.id] or 0
		local cap = Formulas.upgradeCap(upgrade, business.level)
		if level < cap then
			local cost = Formulas.upgradeCost(definition, upgrade, level)
			if best == nil or cost < best then
				best = cost
			end
		end
	end
	return best
end

-- The cheapest shop the player does not own yet.
local function nextShop(state: any): Businesses.Definition?
	local best: Businesses.Definition? = nil
	for _, definition in Businesses.List do
		if not state.businesses[definition.id] and (best == nil or definition.price < best.price) then
			best = definition
		end
	end
	return best
end

-- Instructions name the right button for the device in use.
local function pick(pc: string, pad: string, touch: string): string
	if controllers.UI.isTouch() then
		return touch
	end
	if UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad" then
		return pad
	end
	return pc
end

local function showMe(businessId: string): () -> ()
	return function()
		controllers.City.setWaypoint(businessId)
	end
end

local function content(step: Step, id: string, state: any): Content?
	local definition = Businesses.get(id)
	if not definition then
		return nil
	end
	local money = controllers.Store.money()
	local title = if (state.prestige or 0) > 0
		then "🌟 FRESH START"
		else string.format("GETTING STARTED  •  STEP %d OF %d", STEP_NUMBER[step], STEP_COUNT)

	if step == "buy" then
		local text = if money >= definition.price
			then definition.emoji .. " Buy your first shop, the " .. definition.name .. "! " .. pick("Hold E at its door.", "Hold X at its door.", "Hold Buy at its door.")
			else definition.emoji .. " Your first shop: the " .. definition.name .. " (" .. Format.cash(definition.price) .. ")"
		return { title = title, text = text, button = "📍 Show me", color = C.Green, action = showMe(id) }
	elseif step == "play" then
		if controllers.Interior.currentBusiness() == id then
			local action = MiniGames.get(id).action
			return {
				title = title,
				text = definition.emoji .. " Play the mini game at the counter! " .. pick("Press F there.", "Press Y there.", "Tap " .. action .. " there."),
				button = "▶ Play",
				color = C.Orange,
				action = function()
					controllers.MiniGame.open(id)
				end,
			}
		end
		return {
			title = title,
			text = definition.emoji .. " Go inside your " .. definition.name .. ". " .. pick("Press E at the door.", "Press X at the door.", "Tap Enter at the door."),
			button = "📍 Show me",
			color = C.Green,
			action = showMe(id),
		}
	elseif step == "upgrade" then
		local cost = cheapestUpgrade(definition, state.businesses[id]) or 0
		local result: Content = {
			title = title,
			text = "⬆️ Make your shop better: buy an upgrade! " .. pick("Press U.", "Use this button.", "Tap Upgrades."),
			button = "⬆️ Upgrades",
			color = C.Purple,
			action = function()
				controllers.UI.openManage(id)
			end,
		}
		if money < cost then
			result.text = "⬆️ Earn " .. Format.cash(cost) .. " for your first upgrade!"
			result.progress = money / cost
			result.progressText = Format.cash(money) .. " / " .. Format.cash(cost)
		end
		return result
	else
		local target = nextShop(state)
		if not target then
			return nil
		end
		local result: Content = {
			title = title,
			text = target.emoji .. " You can buy your 2nd shop: the " .. target.name .. "!",
			button = "📍 Show me",
			color = C.Green,
			action = showMe(target.id),
		}
		if money < target.price then
			result.text = target.emoji .. " Save up for your 2nd shop: the " .. target.name .. "!"
			result.progress = money / target.price
			result.progressText = Format.cash(money) .. " / " .. Format.cash(target.price)
		end
		return result
	end
end

----- Chip -----
local chip: Frame? = nil
local chipScale: UIScale? = nil
local stepLabel: TextLabel? = nil
local textLabel: TextLabel? = nil
local actionButton: TextButton? = nil
local progressBar: Frame? = nil
local setProgress: ((number, string?) -> ())? = nil
local onAction: (() -> ())? = nil
local shown = { title = "", text = "", button = "", color = C.Green, progress = -1, progressText = "" }

local function buildChip()
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("CityHUD", 15)
	local root = gui and gui:WaitForChild("Root", 10)
	if not root then
		return
	end
	local frame = UIKit.panel({
		Name = "Guide", -- UIController places it (bottom centre, above the business bar)
		Size = UDim2.fromOffset(CHIP_W, CHIP_H),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -112),
		Visible = false,
	})
	frame:SetAttribute("ChipWidth", CHIP_W)
	frame:SetAttribute("ChipHeight", CHIP_H)
	chipScale = UIKit.new("UIScale", { Name = "Pop", Parent = frame })
	stepLabel = UIKit.label({ Name = "Step", Text = "", TextColor3 = YELLOW, Size = UDim2.new(1, -156, 0, 16), Position = UDim2.fromOffset(12, 6), MaxTextSize = 13, Parent = frame })
	textLabel = UIKit.label({ Name = "Text", Text = "", TextWrapped = true, Size = UDim2.new(1, -156, 0, 50), Position = UDim2.fromOffset(12, 24), MaxTextSize = 18, Parent = frame })
	local bar, set = UIKit.progressBar({ Name = "Progress", Text = "", Color = C.Money, Size = UDim2.new(1, -156, 0, 16), Position = UDim2.fromOffset(12, 58), MaxTextSize = 12, Parent = frame })
	bar.Visible = false
	progressBar, setProgress = bar, set
	actionButton = UIKit.button({
		Name = "Action",
		Text = "📍 Show me",
		Color = C.Green,
		Size = UDim2.fromOffset(128, 54),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		MaxTextSize = 17,
		Parent = frame,
	}, function()
		if onAction then
			onAction()
		end
	end)
	frame.Parent = root
	chip = frame
end

local function pop()
	local scale = chipScale
	if scale then
		scale.Scale = 0.82
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

local function render(info: Content?, visible: boolean)
	local frame = chip
	if not frame then
		return
	end
	if info and stepLabel and textLabel and actionButton and progressBar and setProgress then
		onAction = info.action
		if shown.title ~= info.title then
			shown.title = info.title
			stepLabel.Text = info.title
		end
		if shown.text ~= info.text then
			shown.text = info.text
			textLabel.Text = info.text
		end
		if shown.button ~= info.button then
			shown.button = info.button
			UIKit.setButtonText(actionButton, info.button)
		end
		if shown.color ~= info.color then
			shown.color = info.color
			UIKit.setButtonColor(actionButton, info.color)
		end
		local hasBar = info.progress ~= nil
		if progressBar.Visible ~= hasBar then
			progressBar.Visible = hasBar
			textLabel.Size = UDim2.new(1, -156, 0, if hasBar then 32 else 50)
		end
		if info.progress then
			local alpha = math.floor(math.clamp(info.progress, 0, 1) * 200) / 200
			if alpha ~= shown.progress or info.progressText ~= shown.progressText then
				shown.progress = alpha
				shown.progressText = info.progressText or ""
				setProgress(alpha, info.progressText)
			end
		end
	end
	local show = visible and info ~= nil
	if frame.Visible ~= show then
		frame.Visible = show
	end
end

----- Arrow over the counter (step 2, inside your shop) -----
local arrow: BillboardGui? = nil

local function buildArrow()
	local gui = Instance.new("BillboardGui")
	gui.Name = "GuideArrow"
	gui.Size = UDim2.fromOffset(140, 104)
	gui.StudsOffset = Vector3.new(0, 4.2, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Enabled = false
	UIKit.label({ Name = "Title", Text = "PLAY HERE", TextColor3 = YELLOW, Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 24, Parent = gui })
	local tip = UIKit.label({ Name = "Arrow", Text = "\u{25BC}", TextColor3 = YELLOW, Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 30), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 54, Parent = gui })
	TweenService:Create(tip, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromOffset(0, 46) }):Play()
	gui.Parent = player:WaitForChild("PlayerGui")
	arrow = gui
end

local function updateArrow(step: Step?, id: string?, miniGameOpen: boolean)
	local gui = arrow
	if not gui then
		return
	end
	local prompt: ProximityPrompt? = nil
	if step == "play" and not miniGameOpen and controllers.Interior.currentBusiness() == id then
		prompt = controllers.Interior.workPrompt()
	end
	local anchor = prompt and prompt.Parent
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local show = false
	if prompt and anchor and anchor:IsA("BasePart") then
		-- Once you are close enough for the prompt, the prompt itself takes over.
		show = not root or (root.Position - anchor.Position).Magnitude > prompt.MaxActivationDistance
		if gui.Adornee ~= anchor then
			gui.Adornee = anchor
		end
	end
	if gui.Enabled ~= show then
		gui.Enabled = show
	end
end

----- Step changes -----
local lastKey: string? = nil
local lastStep: Step? = nil
local announcedSecond = false

local function onStepChanged(previous: Step?, step: Step?, id: string?, first: boolean)
	if step == "buy" or (first and step == "play") then
		-- Point the way (new player, fresh prestige, or rejoining before step 2 is done).
		task.delay(2.5, function()
			local now, nowId = currentStep(controllers.Store.state)
			if now == step and nowId == id and id and not controllers.Interior.isInside() then
				controllers.City.setWaypoint(id)
			end
		end)
	end
	if first then
		return
	end
	if previous and STEP_DONE[previous] then
		controllers.UI.notify("success", STEP_DONE[previous])
	end
	if step then
		pop()
	elseif previous == "second" then
		controllers.UI.notify("reward", "🎉 Guide done! Keep buying shops and upgrading them.")
	end
end

local function refresh()
	local state = controllers.Store.state
	if not state then
		return
	end
	local step, id = currentStep(state)
	local key = tostring(step) .. ":" .. tostring(id)
	if key ~= lastKey then
		local first = lastKey == nil
		lastKey = key
		local previous = lastStep
		lastStep = step
		onStepChanged(previous, step, id, first)
	end
	local miniGameOpen = controllers.MiniGame ~= nil and controllers.MiniGame.isOpen()
	local info = if step and id then content(step, id, state) else nil
	-- When the 2nd shop becomes affordable, say so once and show the way there.
	if step == "second" and info and info.progress == nil and not announcedSecond then
		announcedSecond = true
		local target = nextShop(state)
		if target then
			controllers.UI.notify("info", "🎉 You have enough for the " .. target.name .. "!")
			if not controllers.Interior.isInside() then
				controllers.City.setWaypoint(target.id)
			end
		end
	end
	render(info, not controllers.UI.isOpen() and not miniGameOpen)
	updateArrow(step, id, miniGameOpen)
end

function GuideController.init(registry: any)
	controllers = registry
end

function GuideController.start()
	buildChip()
	buildArrow()
	controllers.Store.onChange(function()
		refresh()
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.25 then
			elapsed = 0
			refresh()
		end
	end)
end

return GuideController
