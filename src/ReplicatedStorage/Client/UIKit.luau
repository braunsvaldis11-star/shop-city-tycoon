--!strict
-- UIKit (client): building blocks for the Check-UI simulator look.
-- Solid slate windows, dark recessed cards, GothamBlack text with black outlines,
-- beveled gradient buttons with a checkerboard sheen, and centre-anchored hover/press
-- animations. Every button is Selectable so gamepad navigation works out of the box.
-- Container: ReplicatedStorage.Client

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UIKit = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

UIKit.Colors = {
	Panel = rgb(59, 88, 102), -- window canvas
	PanelLight = rgb(26, 44, 52), -- recessed card
	PanelDark = rgb(20, 30, 36), -- progress trough
	Stroke = rgb(24, 30, 34), -- window outline
	Ink = rgb(12, 18, 22), -- text and button outlines
	Highlight = rgb(75, 125, 145), -- card rim
	Text = rgb(255, 255, 255),
	Muted = rgb(170, 200, 212),
	Money = rgb(150, 255, 90),
	Green = rgb(105, 225, 0),
	Blue = rgb(0, 150, 250),
	Purple = rgb(140, 30, 240),
	Orange = rgb(255, 140, 0),
	Yellow = rgb(255, 205, 0),
	Red = rgb(225, 20, 45),
	Grey = rgb(150, 160, 176),
	Gold = rgb(255, 185, 0),
}
local C = UIKit.Colors

UIKit.Font = Enum.Font.GothamBlack
UIKit.BodyFont = Enum.Font.GothamBold
UIKit.CHECKER = "rbxassetid://385956923"

-- Set by the UI controller to play a click sound on every button press.
UIKit.onClick = nil :: (() -> ())?

export type Theme = { top: Color3, bottom: Color3, highlight: Color3, damier: Color3, divider: Color3 }

-- Header themes (Check-UI canonical gradients).
UIKit.Themes = {
	Lime = { top = rgb(152, 255, 0), bottom = rgb(80, 208, 0), highlight = rgb(224, 255, 176), damier = rgb(53, 128, 0), divider = rgb(37, 96, 0) },
	Cyan = { top = rgb(0, 205, 255), bottom = rgb(0, 130, 245), highlight = rgb(180, 240, 255), damier = rgb(0, 75, 150), divider = rgb(0, 50, 110) },
	Amber = { top = rgb(255, 208, 0), bottom = rgb(255, 140, 0), highlight = rgb(255, 240, 160), damier = rgb(176, 96, 0), divider = rgb(153, 76, 0) },
	Magenta = { top = rgb(255, 20, 150), bottom = rgb(225, 0, 25), highlight = rgb(255, 200, 225), damier = rgb(150, 0, 20), divider = rgb(125, 0, 18) },
	Purple = { top = rgb(160, 0, 255), bottom = rgb(96, 0, 200), highlight = rgb(224, 160, 255), damier = rgb(96, 0, 144), divider = rgb(80, 0, 120) },
	Silver = { top = rgb(255, 255, 255), bottom = rgb(215, 222, 232), highlight = rgb(255, 255, 255), damier = rgb(110, 120, 135), divider = rgb(90, 100, 112) },
} :: { [string]: Theme }

type ButtonStyle = { top: Color3, bottom: Color3, bevel: Color3, rim: Color3 }

local GOLD_STYLE = { top = rgb(255, 208, 0), bottom = rgb(255, 140, 0), bevel = rgb(153, 76, 0), rim = rgb(255, 240, 160) }
local STYLES: { [string]: ButtonStyle } = {
	[C.Green:ToHex()] = { top = rgb(180, 255, 25), bottom = rgb(105, 225, 0), bevel = rgb(15, 120, 15), rim = rgb(235, 255, 130) },
	[C.Grey:ToHex()] = { top = rgb(216, 222, 228), bottom = rgb(148, 160, 176), bevel = rgb(72, 82, 96), rim = rgb(255, 255, 255) },
	[C.Red:ToHex()] = { top = rgb(255, 32, 80), bottom = rgb(208, 0, 32), bevel = rgb(112, 0, 16), rim = rgb(255, 176, 200) },
	[C.Gold:ToHex()] = GOLD_STYLE,
	[C.Yellow:ToHex()] = GOLD_STYLE,
	[C.Orange:ToHex()] = { top = rgb(255, 170, 40), bottom = rgb(240, 100, 0), bevel = rgb(140, 50, 0), rim = rgb(255, 215, 150) },
	[C.Blue:ToHex()] = { top = rgb(0, 205, 255), bottom = rgb(0, 130, 245), bevel = rgb(0, 60, 130), rim = rgb(180, 240, 255) },
	[C.Purple:ToHex()] = { top = rgb(176, 32, 255), bottom = rgb(112, 0, 224), bevel = rgb(64, 0, 120), rim = rgb(224, 160, 255) },
	[C.PanelLight:ToHex()] = { top = rgb(64, 98, 114), bottom = rgb(38, 62, 74), bevel = rgb(16, 26, 32), rim = rgb(110, 160, 180) },
}

function UIKit.style(color: Color3): ButtonStyle
	return STYLES[color:ToHex()] or {
		top = color:Lerp(WHITE, 0.3),
		bottom = color,
		bevel = color:Lerp(BLACK, 0.55),
		rim = color:Lerp(WHITE, 0.6),
	}
end

-- Helper-only options that are not real Instance properties.
local META_KEYS = { Parent = true, MaxTextSize = true, Radius = true, Stroke = true }

function UIKit.new(className: string, props: { [string]: any }, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = props.Parent
	for key, value in props do
		if not META_KEYS[key] then
			(instance :: any)[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function UIKit.corner(radius: number?): UICorner
	return UIKit.new("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
end

function UIKit.stroke(color: Color3?, thickness: number?): UIStroke
	return UIKit.new("UIStroke", {
		Color = color or C.Stroke,
		Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

-- Labels already get an outline; this stays for odd cases (e.g. plain TextLabels).
function UIKit.textStroke(thickness: number?): UIStroke
	return UIKit.new("UIStroke", { Name = "TextStroke", Color = C.Ink, Thickness = thickness or 2 })
end

function UIKit.gradient(top: Color3, bottom: Color3): UIGradient
	return UIKit.new("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = 90 })
end

function UIKit.padding(all: number): UIPadding
	local u = UDim.new(0, all)
	return UIKit.new("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

function UIKit.list(direction: Enum.FillDirection?, spacing: number?, align: Enum.HorizontalAlignment?): UIListLayout
	return UIKit.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, spacing or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
	})
end

local function strokeFor(size: number): number
	if size >= 26 then
		return 2.6
	elseif size >= 17 then
		return 2
	end
	return 1.5
end

-- GothamBlack text with a black outline (pass Stroke = false for emoji or plain text).
function UIKit.label(props: { [string]: any }): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = UIKit.Font,
		TextColor3 = C.Text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in props do
		defaults[k] = v
	end
	local label = UIKit.new("TextLabel", defaults)
	local maxSize = props.MaxTextSize or 40
	if props.TextScaled ~= false then
		UIKit.new("UITextSizeConstraint", { MaxTextSize = maxSize, MinTextSize = 8, Parent = label })
	end
	if props.Stroke ~= false then
		UIKit.new("UIStroke", { Name = "TextStroke", Color = C.Ink, Thickness = strokeFor(maxSize), Parent = label })
	end
	return label
end

-- Solid slate window / HUD panel with the thick dark outline.
function UIKit.panel(props: { [string]: any }): Frame
	local defaults: { [string]: any } = { BackgroundColor3 = C.Panel, BorderSizePixel = 0 }
	for k, v in props do
		defaults[k] = v
	end
	local frame = UIKit.new("Frame", defaults)
	UIKit.corner(math.min(props.Radius or 6, 8)).Parent = frame
	UIKit.stroke(C.Stroke, 3.5).Parent = frame
	return frame
end

-- Dark recessed card with a soft highlight rim.
function UIKit.card(props: { [string]: any }): Frame
	local defaults: { [string]: any } = { BackgroundColor3 = C.PanelLight, BorderSizePixel = 0 }
	for k, v in props do
		defaults[k] = v
	end
	local frame = UIKit.new("Frame", defaults)
	UIKit.corner(math.min(props.Radius or 6, 8)).Parent = frame
	UIKit.new("UIStroke", { Name = "Rim", Color = C.Highlight, Thickness = 1.5, Transparency = 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = frame })
	return frame
end

local QUICK = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BOUNCE = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- Hover / press animation on a UIScale (the scaled frame is centre-anchored).
local function pressable(hitbox: GuiButton, scale: UIScale, hover: number, press: number, onHover: ((boolean) -> ())?)
	local hovering = false
	local function to(target: number, info: TweenInfo)
		TweenService:Create(scale, info, { Scale = target }):Play()
	end
	local function setHover(on: boolean)
		hovering = on
		to(if on then hover else 1, QUICK)
		if onHover then
			onHover(on)
		end
	end
	hitbox.MouseEnter:Connect(function()
		if UserInputService.MouseEnabled then
			setHover(true)
		end
	end)
	hitbox.MouseLeave:Connect(function()
		setHover(false)
	end)
	hitbox.SelectionGained:Connect(function()
		setHover(true)
	end)
	hitbox.SelectionLost:Connect(function()
		setHover(false)
	end)
	hitbox.MouseButton1Down:Connect(function()
		to(press, QUICK)
	end)
	hitbox.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			to(if hovering then hover else 1, BOUNCE)
		end
	end)
	hitbox.Activated:Connect(function()
		local sound = UIKit.onClick
		if sound then
			sound()
		end
	end)
end

local function applyStyle(face: Instance, color: Color3)
	local style = UIKit.style(color)
	local fill = face:FindFirstChild("Fill") :: UIGradient?
	if fill then
		fill.Color = ColorSequence.new(style.top, style.bottom)
	end
	local bevel = face:FindFirstChild("Bevel") :: Frame?
	if bevel then
		bevel.BackgroundColor3 = style.bevel
	end
	local rim = face:FindFirstChild("Rim1")
	local rimStroke = rim and rim:FindFirstChildOfClass("UIStroke")
	if rimStroke then
		rimStroke.Color = style.rim
	end
end

-- Content for an icon slot: an uploaded image when we have one, otherwise the emoji.
local function iconContent(parent: Instance, image: string?, emoji: string?, props: { [string]: any }): GuiObject
	if image and image ~= "" then
		local defaults: { [string]: any } = { Name = "Icon", Image = image, ScaleType = Enum.ScaleType.Fit, BackgroundTransparency = 1, Parent = parent }
		for k, v in props do
			defaults[k] = v
		end
		return UIKit.new("ImageLabel", defaults)
	end
	local defaults: { [string]: any } = { Name = "Icon", Text = emoji or "", TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 64, Stroke = false, Parent = parent }
	for k, v in props do
		defaults[k] = v
	end
	return UIKit.label(defaults)
end

-- Chunky Check-UI button: transparent hitbox with a centred, beveled "Face".
-- Optional Image / Emoji adds an icon (left of the text, or above it with Stack = true).
function UIKit.button(props: { [string]: any }, onClick: (() -> ())?): TextButton
	local color: Color3 = props.Color or C.Green
	local maxText: number = props.MaxTextSize or 28
	local size: UDim2 = props.Size or UDim2.fromOffset(160, 50)
	local button = UIKit.new("TextButton", {
		Name = props.Name or "Button",
		Size = size,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Selectable = true,
		Visible = if props.Visible == false then false else true,
		Parent = props.Parent,
	})
	local face = UIKit.new("Frame", {
		Name = "Face",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = button,
	})
	UIKit.new("UIStroke", { Name = "Outline", Color = C.Ink, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = face })
	UIKit.new("UIGradient", { Name = "Fill", Rotation = 90, Parent = face })
	local checker = UIKit.new("ImageLabel", {
		Name = "Checker",
		Image = UIKit.CHECKER,
		ImageColor3 = BLACK,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = face,
	})
	UIKit.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.91, 0.62), Parent = checker })
	UIKit.new("Frame", { Name = "Bevel", BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 4), Position = UDim2.new(0, 0, 1, -4), ZIndex = 2, Parent = face })
	for i, transparency in { 0.25, 0.5, 0.8 } do
		local rim = UIKit.new("Frame", {
			Name = "Rim" .. i,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -2 * i, 1, -2 * i),
			ZIndex = 3,
			Parent = face,
		})
		UIKit.new("UIStroke", { Color = WHITE, Thickness = 1, Transparency = transparency, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = rim })
	end

	local labelProps: { [string]: any } = {
		Name = "Label",
		Text = props.Text or "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -2),
		Size = UDim2.new(1, -12, 1, -12),
		TextXAlignment = Enum.TextXAlignment.Center,
		MaxTextSize = maxText,
		Stroke = false,
		ZIndex = 5,
		Parent = face,
	}
	if props.Image or props.Emoji then
		if props.Stack then
			iconContent(face, props.Image, props.Emoji, {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 4),
				Size = UDim2.new(1, -10, 0.64, -6),
				ZIndex = 4,
			})
			labelProps.AnchorPoint = Vector2.new(0.5, 1)
			labelProps.Position = UDim2.new(0.5, 0, 1, -6)
			labelProps.Size = UDim2.new(1, -6, 0.3, 0)
		else
			local px = math.floor(math.max(size.Y.Offset, 30) * 0.74)
			iconContent(face, props.Image, props.Emoji, {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 6, 0.5, -2),
				Size = UDim2.fromOffset(px, px),
				ZIndex = 4,
			})
			labelProps.AnchorPoint = Vector2.new(0, 0.5)
			labelProps.Position = UDim2.new(0, px + 10, 0.5, -2)
			labelProps.Size = UDim2.new(1, -(px + 16), 1, -12)
		end
	end
	local label = UIKit.label(labelProps)
	UIKit.new("UIStroke", { Name = "TextStroke", Color = rgb(17, 23, 26), Thickness = if maxText >= 24 then 3 elseif maxText >= 16 then 2.4 else 1.8, Parent = label })

	local scale = UIKit.new("UIScale", { Name = "Scale", Parent = face })
	pressable(button, scale, props.Hover or 1.05, 0.94)
	applyStyle(face, color)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

function UIKit.setButtonColor(button: GuiObject, color: Color3)
	local face = button:FindFirstChild("Face")
	if face then
		applyStyle(face, color)
	end
end

function UIKit.setButtonText(button: GuiObject, text: string)
	local label = button:FindFirstChild("Label", true) :: TextLabel?
	if label then
		label.Text = text
	end
end

-- A whole card that can be pressed (business list rows). Returns the hitbox and the
-- card face to put content in; the face scales from its centre on hover/press.
function UIKit.cardButton(props: { [string]: any }, onClick: (() -> ())?): (TextButton, Frame)
	local button = UIKit.new("TextButton", {
		Name = props.Name or "Card",
		Size = props.Size or UDim2.new(1, 0, 0, 72),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Selectable = true,
		Parent = props.Parent,
	})
	local face = UIKit.card({
		Name = "Face",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = props.Color or C.PanelLight,
		Parent = button,
	})
	local rim = face:FindFirstChild("Rim") :: UIStroke
	local scale = UIKit.new("UIScale", { Parent = face })
	pressable(button, scale, props.Hover or 1.012, 0.975, function(on)
		TweenService:Create(rim, QUICK, {
			Transparency = if on then 0 else 0.4,
			Color = if on then rgb(140, 210, 235) else C.Highlight,
		}):Play()
	end)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button, face
end

-- Recessed trough with an orange-gold fill (or the given colour). Returns the frame and
-- a setter (alpha 0..1, optional text). The first set is instant so re-renders never
-- replay the fill animation; later sets tween.
function UIKit.progressBar(props: { [string]: any }): (Frame, (number, string?) -> ())
	local back = UIKit.new("Frame", {
		Name = props.Name or "Progress",
		Size = props.Size or UDim2.new(1, 0, 0, 14),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundColor3 = C.PanelDark,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = props.Parent,
	})
	UIKit.new("UIStroke", { Color = C.Ink, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = back })
	local fill = UIKit.new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = back })
	local color: Color3? = props.Color
	local top = if color then color:Lerp(WHITE, 0.35) else rgb(255, 200, 0)
	local bottom = if color then color else rgb(255, 106, 0)
	UIKit.new("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = 90, Parent = fill })
	UIKit.new("Frame", { Name = "Shade", BackgroundColor3 = bottom:Lerp(BLACK, 0.45), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 1, -2), Parent = fill })
	local text: TextLabel? = nil
	if props.Text then
		text = UIKit.label({
			Name = "Text",
			Text = props.Text,
			Size = UDim2.new(1, -8, 1, 0),
			Position = UDim2.fromOffset(4, 0),
			TextXAlignment = Enum.TextXAlignment.Center,
			MaxTextSize = props.MaxTextSize or 16,
			ZIndex = 3,
			Parent = back,
		})
	end
	local first = true
	local function set(alpha: number, value: string?)
		if alpha ~= alpha then
			alpha = 0
		end
		alpha = math.clamp(alpha, 0, 1)
		if first then
			first = false
			fill.Size = UDim2.fromScale(alpha, 1)
		else
			TweenService:Create(fill, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(alpha, 1) }):Play()
		end
		if value and text then
			text.Text = value
		end
	end
	return back, set
end

-- Icon tile: a glossy coloured square holding an uploaded image (Image) or an emoji (Text).
function UIKit.icon(props: { [string]: any }): Frame
	local color: Color3 = props.Color or C.Green
	local radius = props.Radius or 6
	local frame = UIKit.new("Frame", {
		Name = props.Name or "Icon",
		Size = props.Size or UDim2.fromOffset(48, 48),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Parent = props.Parent,
	})
	UIKit.corner(radius).Parent = frame
	UIKit.new("UIStroke", { Color = C.Ink, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = frame })
	UIKit.new("UIGradient", { Name = "Fill", Color = ColorSequence.new(color:Lerp(WHITE, 0.3), color:Lerp(BLACK, 0.12)), Rotation = 90, Parent = frame })
	local checker = UIKit.new("ImageLabel", {
		Name = "Checker",
		Image = UIKit.CHECKER,
		ImageColor3 = BLACK,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(16, 16),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = frame,
	})
	UIKit.corner(radius).Parent = checker
	UIKit.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.94, 0.7), Parent = checker })
	UIKit.label({
		Name = "Emoji",
		Text = props.Text or "?",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.78, 0.78),
		TextXAlignment = Enum.TextXAlignment.Center,
		MaxTextSize = 64,
		Stroke = false,
		ZIndex = 2,
		Parent = frame,
	})
	UIKit.new("ImageLabel", {
		Name = "Image",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, 0.92),
		ZIndex = 2,
		Parent = frame,
	})
	UIKit.setIcon(frame, props.Text or "?", props.Image)
	return frame
end

-- Shows the image when there is one; the emoji stays visible until the image has
-- actually downloaded, so a tile is never blank on first load.
function UIKit.setIcon(frame: Instance, emoji: string, image: string?)
	local hasImage = image ~= nil and image ~= ""
	local emojiLabel = frame:FindFirstChild("Emoji") :: TextLabel?
	local imageLabel = frame:FindFirstChild("Image") :: ImageLabel?
	if emojiLabel then
		emojiLabel.Text = emoji
		emojiLabel.Visible = true
	end
	if not imageLabel then
		return
	end
	imageLabel.Image = image or ""
	imageLabel.Visible = hasImage
	if not hasImage or not emojiLabel then
		return
	end
	if imageLabel.IsLoaded then
		emojiLabel.Visible = false
	else
		local connection: RBXScriptConnection
		connection = imageLabel:GetPropertyChangedSignal("IsLoaded"):Connect(function()
			if imageLabel.IsLoaded and imageLabel.Image == image then
				emojiLabel.Visible = false
				connection:Disconnect()
			end
		end)
	end
end

function UIKit.setIconColor(frame: Instance, color: Color3)
	local fill = frame:FindFirstChild("Fill") :: UIGradient?
	if fill then
		fill.Color = ColorSequence.new(color:Lerp(WHITE, 0.3), color:Lerp(BLACK, 0.12))
	end
end

-- Window header: themed gradient, fading checkerboard, top shine and the 2-tier divider
-- (3px dark thematic bar + 3px black bar) drawn over the header's bottom edge.
function UIKit.header(parent: Instance, height: number, theme: Theme?): Frame
	local header = UIKit.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Parent = parent,
	})
	UIKit.corner(6).Parent = header
	UIKit.new("UIGradient", { Name = "Fill", Rotation = 90, Parent = header })
	local checker = UIKit.new("ImageLabel", {
		Name = "Checker",
		Image = UIKit.CHECKER,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(24, 24),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -6),
		Parent = header,
	})
	UIKit.corner(6).Parent = checker
	UIKit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.35, 0.85),
			NumberSequenceKeypoint.new(0.75, 0.55),
			NumberSequenceKeypoint.new(1, 0.35),
		}),
		Parent = checker,
	})
	UIKit.new("Frame", { Name = "TopShine", BackgroundTransparency = 0.15, BorderSizePixel = 0, Size = UDim2.new(1, -12, 0, 2), Position = UDim2.fromOffset(6, 2), ZIndex = 2, Parent = header })
	UIKit.new("Frame", { Name = "DividerDark", BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 3), Position = UDim2.new(0, 0, 1, -6), ZIndex = 2, Parent = header })
	UIKit.new("Frame", { Name = "DividerBlack", BackgroundColor3 = BLACK, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 3), Position = UDim2.new(0, 0, 1, -3), ZIndex = 2, Parent = header })
	UIKit.setHeaderTheme(header, theme or UIKit.Themes.Lime)
	return header
end

function UIKit.setHeaderTheme(header: Instance, theme: Theme)
	local fill = header:FindFirstChild("Fill") :: UIGradient?
	if fill then
		fill.Color = ColorSequence.new(theme.top, theme.bottom)
	end
	local checker = header:FindFirstChild("Checker") :: ImageLabel?
	if checker then
		checker.ImageColor3 = theme.damier
	end
	local shine = header:FindFirstChild("TopShine") :: Frame?
	if shine then
		shine.BackgroundColor3 = theme.highlight
	end
	local divider = header:FindFirstChild("DividerDark") :: Frame?
	if divider then
		divider.BackgroundColor3 = theme.divider
	end
end

-- The signature 38x38 beveled close button.
function UIKit.closeButton(props: { [string]: any }, onClick: (() -> ())?): ImageButton
	local button = UIKit.new("ImageButton", {
		Name = props.Name or "Close",
		Size = props.Size or UDim2.fromOffset(40, 40),
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5),
		Position = props.Position or UDim2.new(),
		BackgroundColor3 = rgb(115, 0, 16),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Selectable = true,
		ZIndex = 3,
		Parent = props.Parent,
	})
	UIKit.new("UIStroke", { Color = BLACK, Thickness = 2.8, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = button })
	local face = UIKit.new("Frame", { Name = "Face", Size = UDim2.new(1, 0, 1, -4), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3, Parent = button })
	UIKit.new("UIGradient", { Color = ColorSequence.new(rgb(255, 125, 175), rgb(255, 20, 40)), Rotation = 90, Parent = face })
	local rim = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -2, 1, -2),
		ZIndex = 4,
		Parent = face,
	})
	UIKit.new("UIStroke", { Color = rgb(255, 210, 235), Thickness = 1.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = rim })
	UIKit.new("Frame", { Name = "SepLine", BackgroundColor3 = rgb(70, 0, 10), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -4), ZIndex = 4, Parent = button })
	local x = UIKit.label({
		Name = "X",
		Text = "X",
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		MaxTextSize = 28,
		Stroke = false,
		ZIndex = 5,
		Parent = face,
	})
	UIKit.new("UIStroke", { Color = BLACK, Thickness = 3, Parent = x })
	local scale = UIKit.new("UIScale", { Parent = button })
	pressable(button, scale, 1.08, 0.92)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

function UIKit.tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	tween:Play()
	return tween
end

return UIKit
