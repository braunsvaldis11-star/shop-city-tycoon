--!strict
-- Bubble (client only): little cartoon speech bubbles over NPC heads and props.
-- Container: ReplicatedStorage.Client

local TweenService = game:GetService("TweenService")

local Bubble = {}

local POP = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(0.25)

-- Shows `text` above `adornee` for `seconds`. Returns the BillboardGui.
function Bubble.say(adornee: BasePart, text: string, seconds: number?, offset: number?): BillboardGui
	local old = adornee:FindFirstChild("SpeechBubble")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "SpeechBubble"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(190, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offset or 2.6, 0)
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.fromScale(0.5, 1)
	frame.Size = UDim2.fromScale(1, 1)
	frame.AutomaticSize = Enum.AutomaticSize.None
	frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(24, 30, 34)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -16, 1, -8)
	label.Position = UDim2.fromOffset(8, 4)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(35, 40, 50)
	label.Text = text
	label.Parent = frame
	local tail = Instance.new("TextLabel")
	tail.BackgroundTransparency = 1
	tail.AnchorPoint = Vector2.new(0.5, 0)
	tail.Position = UDim2.new(0.5, 0, 1, -6)
	tail.Size = UDim2.fromOffset(18, 14)
	tail.Font = Enum.Font.GothamBlack
	tail.Text = "\u{25BC}"
	tail.TextScaled = true
	tail.TextColor3 = Color3.fromRGB(255, 255, 255)
	tail.TextStrokeTransparency = 0.4
	tail.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = frame
	frame.Parent = gui
	gui.Parent = adornee
	TweenService:Create(scale, POP, { Scale = 1 }):Play()
	task.delay(seconds or 2.6, function()
		if gui.Parent then
			TweenService:Create(scale, FADE, { Scale = 0 }):Play()
			task.wait(0.26)
			gui:Destroy()
		end
	end)
	return gui
end

return Bubble
