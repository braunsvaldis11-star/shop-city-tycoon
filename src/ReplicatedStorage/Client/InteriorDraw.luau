--!strict
-- InteriorDraw (client only): small drawing helpers shared by the interior builder,
-- the station builders and the per-business kits. Everything is anchored parts.
-- Container: ReplicatedStorage.Client

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Props = require(ReplicatedStorage:WaitForChild("Shared").Props)

local D = {}

D.WHITE = Color3.fromRGB(250, 250, 250)
D.WOOD = Color3.fromRGB(170, 115, 70)
D.DARKWOOD = Color3.fromRGB(110, 70, 45)
D.DARK = Color3.fromRGB(55, 55, 65)
D.BLACK = Color3.fromRGB(30, 30, 36)
D.STEEL = Color3.fromRGB(200, 205, 212)
D.GOLD = Color3.fromRGB(255, 200, 60)
D.GLASS = Color3.fromRGB(200, 235, 255)
D.WARM = Color3.fromRGB(255, 220, 170)
D.RED = Color3.fromRGB(220, 60, 55)
D.GREEN = Color3.fromRGB(80, 180, 90)
D.BLUE = Color3.fromRGB(70, 150, 235)
D.YELLOW = Color3.fromRGB(250, 205, 70)
D.PINK = Color3.fromRGB(255, 150, 190)
D.PURPLE = Color3.fromRGB(150, 90, 220)
D.ORANGE = Color3.fromRGB(255, 150, 50)
D.CREAM = Color3.fromRGB(250, 240, 220)
D.FABRIC = Enum.Material.Fabric
D.METAL = Enum.Material.Metal
D.NEON = Enum.Material.Neon
D.PLANKS = Enum.Material.WoodPlanks
D.MARBLE = Enum.Material.Marble
D.GLASSMAT = Enum.Material.Glass

D.BRIGHT = {
	Color3.fromRGB(240, 80, 80), Color3.fromRGB(80, 160, 240), Color3.fromRGB(90, 200, 120),
	Color3.fromRGB(250, 205, 70), Color3.fromRGB(180, 100, 230), Color3.fromRGB(255, 140, 60),
}

-- Equipment tier looks (index = tier + 1): basic, stone, deluxe, turbo, golden.
D.TIER_TINTS = {
	Color3.fromRGB(175, 100, 80), Color3.fromRGB(150, 150, 160), Color3.fromRGB(210, 60, 55),
	Color3.fromRGB(60, 140, 235), D.GOLD,
}
D.TIER_MATERIALS = {
	Enum.Material.Brick, Enum.Material.Slate, Enum.Material.SmoothPlastic, Enum.Material.Metal, Enum.Material.Foil,
}

local V = Vector3.new

-- Box. `ghost` parts do not collide (decor the player should walk through or past).
function D.box(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, ghost: boolean?): Part
	return Props.part(parent, name, size, cf, color, { material = material, collide = if ghost then false else nil })
end

-- Glowing box (never collides, casts no shadow).
function D.glow(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	return Props.part(parent, name, size, cf, color, { material = Enum.Material.Neon, collide = false, shadow = false })
end

-- See-through box.
function D.glass(parent: Instance, name: string, size: Vector3, cf: CFrame, transparency: number?, color: Color3?): Part
	return Props.part(parent, name, size, cf, color or D.GLASS, { material = Enum.Material.Glass, transparency = transparency or 0.6, collide = false })
end

-- Vertical cylinder standing at `cf` (centre).
function D.cyl(parent: Instance, name: string, height: number, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?, ghost: boolean?): Part
	return Props.part(parent, name, V(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.pi / 2), color,
		{ shape = Enum.PartType.Cylinder, material = material, collide = if ghost then false else nil })
end

-- Cylinder lying along the local X axis of `cf`.
function D.rod(parent: Instance, name: string, length: number, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?, ghost: boolean?): Part
	return Props.part(parent, name, V(length, diameter, diameter), cf, color,
		{ shape = Enum.PartType.Cylinder, material = material, collide = if ghost then false else nil })
end

function D.ball(parent: Instance, name: string, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?, ghost: boolean?): Part
	return Props.part(parent, name, Vector3.one * diameter, cf, color,
		{ shape = Enum.PartType.Ball, material = material, collide = if ghost then false else nil })
end

function D.wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, ghost: boolean?): WedgePart
	return Props.wedge(parent, name, size, cf, color, { material = material, collide = if ghost then false else nil })
end

function D.light(part: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = part
end

-- Big cartoon text on one face of a part.
function D.text(part: BasePart, face: Enum.NormalId, text: string, color: Color3, pixels: number?, font: Enum.Font?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixels or 25
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = font or Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(30, 25, 25)
	stroke.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.Parent = label
	label.Parent = gui
	gui.Parent = part
	return label
end

-- A sign board facing local -Z of `cf` (its Front face), with text.
function D.sign(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, text: string, textColor: Color3?, pixels: number?): Part
	local board = D.box(parent, name, size, cf, color, nil, true)
	D.text(board, Enum.NormalId.Front, text, textColor or D.WHITE, pixels or 25)
	return board
end

function D.plant(parent: Instance, position: Vector3, scale: number)
	Props.cylinder(parent, "Pot", 2.4 * scale, 2.6 * scale, position + V(0, 1.2 * scale, 0), Color3.fromRGB(200, 110, 70))
	Props.ball(parent, "Leaves", 4 * scale, position + V(0, 3.8 * scale, 0), Color3.fromRGB(80, 180, 80), { collide = false })
	Props.ball(parent, "Leaves", 2.8 * scale, position + V(0.8 * scale, 5.4 * scale, 0.4 * scale), Color3.fromRGB(100, 200, 90), { collide = false })
end

-- Palm tree (surf shop, aquarium lobby ...).
function D.palm(parent: Instance, cf: CFrame, scale: number)
	for i = 0, 4 do
		D.cyl(parent, "Trunk", 2.2 * scale, (1.3 - i * 0.1) * scale, cf * CFrame.new(i * 0.25 * scale, (1.1 + i * 2) * scale, 0), Color3.fromRGB(150, 105, 65))
	end
	for i = 0, 5 do
		local leaf = CFrame.new((cf * CFrame.new(1.2 * scale, 10.5 * scale, 0)).Position) * CFrame.Angles(0, i * math.pi / 3, 0)
		D.box(parent, "Leaf", V(1.6 * scale, 0.3 * scale, 5 * scale), leaf * CFrame.new(0, 0, -2.2 * scale) * CFrame.Angles(math.rad(-22), 0, 0), Color3.fromRGB(70, 170, 80), nil, true)
	end
end

-- Simple chair facing local -Z of `cf` (backrest at +Z). Tier 0..3 = plastic, wood,
-- cushioned, velvet. `colors` lets a business restyle the frame / cushion.
function D.chair(parent: Instance, cf: CFrame, tier: number, frame: Color3?, cushion: Color3?)
	if tier >= 3 then
		local velvet = cushion or Color3.fromRGB(120, 40, 140)
		D.box(parent, "Seat", V(3, 1.6, 3), cf * CFrame.new(0, 1.1, 0), velvet, D.FABRIC)
		D.box(parent, "Back", V(3, 3.6, 0.9), cf * CFrame.new(0, 3, 1.3), velvet, D.FABRIC)
		D.box(parent, "Trim", V(3.1, 0.3, 1), cf * CFrame.new(0, 4.9, 1.3), D.GOLD)
		return
	end
	local color = frame or (if tier == 0 then Color3.fromRGB(230, 90, 80) else D.WOOD)
	local material = if tier == 0 then Enum.Material.SmoothPlastic else D.PLANKS
	D.box(parent, "Seat", V(2.6, 0.5, 2.6), cf * CFrame.new(0, 1.75, 0), color, material)
	D.box(parent, "Back", V(2.6, 3, 0.4), cf * CFrame.new(0, 3.4, 1.1), color, material)
	D.box(parent, "Leg", V(0.4, 1.5, 0.4), cf * CFrame.new(0, 0.75, 0), D.DARK)
	if tier == 2 then
		D.box(parent, "Cushion", V(2.3, 0.35, 2.3), cf * CFrame.new(0, 2.15, -0.1), cushion or Color3.fromRGB(220, 60, 70), D.FABRIC, true)
	end
end

-- Stool facing nowhere in particular (round).
function D.stool(parent: Instance, cf: CFrame, tier: number, color: Color3?)
	local top = color or (if tier >= 2 then Color3.fromRGB(200, 60, 70) else D.WOOD)
	D.cyl(parent, "StoolTop", 0.5, 2.4, cf * CFrame.new(0, 1.85, 0), top, if tier >= 2 then D.FABRIC else D.PLANKS)
	D.cyl(parent, "StoolLeg", 1.6, 0.4, cf * CFrame.new(0, 0.8, 0), if tier >= 3 then D.GOLD else D.STEEL)
	D.cyl(parent, "StoolFoot", 0.2, 1.6, cf * CFrame.new(0, 0.1, 0), D.DARK)
end

-- Row of hanging pennants between two points (y included).
function D.bunting(parent: Instance, from: Vector3, to: Vector3, colors: { Color3 })
	local span = to - from
	local count = math.max(2, math.floor(span.Magnitude / 2.2))
	local dir = CFrame.lookAt(from, to)
	D.box(parent, "BuntingLine", V(0.1, 0.1, span.Magnitude), dir * CFrame.new(0, 0, -span.Magnitude / 2), D.DARK, nil, true)
	for i = 1, count do
		local p = from + span * ((i - 0.5) / count)
		-- Flipped wedge: full edge on top along the line, point hanging down.
		D.wedge(parent, "Pennant", V(0.1, 1.4, 1.4), CFrame.new(p - V(0, 0.7, 0)) * dir.Rotation * CFrame.Angles(math.pi, 0, 0),
			colors[(i - 1) % #colors + 1], nil, true)
	end
end

-- Smoke / steam puff on a part.
function D.smoke(part: BasePart, color: Color3?, opacity: number?)
	local smoke = Instance.new("Smoke")
	smoke.Size = 0.6
	smoke.RiseVelocity = 2
	smoke.Opacity = opacity or 0.08
	smoke.Color = color or Color3.fromRGB(230, 230, 230)
	smoke.Parent = part
end

-- Rising bubbles (tanks, hot tubs).
function D.bubbles(part: BasePart, rate: number?)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(Color3.fromRGB(220, 245, 255))
	e.Size = NumberSequence.new(0.25, 0.1)
	e.Transparency = NumberSequence.new(0.3, 0.8)
	e.Lifetime = NumberRange.new(1.2, 2)
	e.Rate = rate or 6
	e.Speed = NumberRange.new(1.5, 2.5)
	e.SpreadAngle = Vector2.new(15, 15)
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = part
end

-- Little fish (flat diamond with a tail) facing local -X.
function D.fish(parent: Instance, cf: CFrame, color: Color3, size: number?)
	local s = size or 1
	D.box(parent, "Fish", V(1.2 * s, 0.7 * s, 0.25 * s), cf, color, nil, true)
	D.wedge(parent, "Tail", V(0.2 * s, 0.7 * s, 0.6 * s), cf * CFrame.new(0.8 * s, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), color, nil, true)
end

return D
