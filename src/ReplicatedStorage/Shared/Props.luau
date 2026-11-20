--!strict
-- Props: low-poly cartoon prop factory (parts only, no uploaded assets).
-- Used at edit time by the CityBuilder and at runtime by client systems
-- (interiors, NPCs, ambient traffic).
-- Container: ReplicatedStorage.Shared

local Props = {}

local SMOOTH = Enum.SurfaceType.Smooth

export type PartOptions = {
	material: Enum.Material?,
	shape: Enum.PartType?,
	transparency: number?,
	collide: boolean?,
	shadow: boolean?,
}

function Props.part(parent: Instance?, name: string, size: Vector3, cframe: CFrame, color: Color3, options: PartOptions?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.TopSurface = SMOOTH
	p.BottomSurface = SMOOTH
	if options and options.shape then
		p.Shape = options.shape
	end
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = if options and options.material then options.material else Enum.Material.SmoothPlastic
	if options then
		if options.transparency then
			p.Transparency = options.transparency
		end
		if options.collide == false then
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
		end
		if options.shadow == false then
			p.CastShadow = false
		end
	end
	p.Parent = parent
	return p
end

function Props.wedge(parent: Instance?, name: string, size: Vector3, cframe: CFrame, color: Color3, options: PartOptions?): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.TopSurface = SMOOTH
	w.BottomSurface = SMOOTH
	w.Size = size
	w.CFrame = cframe
	w.Color = color
	w.Material = if options and options.material then options.material else Enum.Material.SmoothPlastic
	if options and options.collide == false then
		w.CanCollide = false
		w.CanTouch = false
		w.CanQuery = false
	end
	w.Parent = parent
	return w
end

-- Vertical cylinder (Roblox cylinders run along X, so rotate onto Y).
function Props.cylinder(parent: Instance?, name: string, height: number, diameter: number, position: Vector3, color: Color3, options: PartOptions?): Part
	local opts: PartOptions = options or {}
	opts.shape = Enum.PartType.Cylinder
	return Props.part(parent, name, Vector3.new(height, diameter, diameter),
		CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2), color, opts)
end

function Props.ball(parent: Instance?, name: string, diameter: number, position: Vector3, color: Color3, options: PartOptions?): Part
	local opts: PartOptions = options or {}
	opts.shape = Enum.PartType.Ball
	return Props.part(parent, name, Vector3.one * diameter, CFrame.new(position), color, opts)
end

----- Nature -----
local LEAF_COLORS = {
	Color3.fromRGB(95, 190, 75),
	Color3.fromRGB(70, 170, 70),
	Color3.fromRGB(120, 205, 85),
	Color3.fromRGB(60, 150, 80),
}

function Props.tree(parent: Instance?, position: Vector3, scale: number?, seed: number?): Model
	local s = scale or 1
	local rng = Random.new(seed or math.floor(position.X * 7 + position.Z * 13))
	local model = Instance.new("Model")
	model.Name = "Tree"
	local trunkHeight = 7 * s
	Props.cylinder(model, "Trunk", trunkHeight, 1.6 * s, position + Vector3.new(0, trunkHeight / 2, 0), Color3.fromRGB(125, 85, 55))
	local leaf = LEAF_COLORS[rng:NextInteger(1, #LEAF_COLORS)]
	local top = position + Vector3.new(0, trunkHeight + 2.5 * s, 0)
	Props.ball(model, "Leaves", 8.5 * s, top, leaf)
	Props.ball(model, "Leaves", 6 * s, top + Vector3.new(2.2 * s, 2.2 * s, 0.8 * s), leaf:Lerp(Color3.new(1, 1, 1), 0.08))
	Props.ball(model, "Leaves", 5.5 * s, top + Vector3.new(-1.8 * s, 1.6 * s, -1.6 * s), leaf:Lerp(Color3.new(0, 0, 0), 0.06))
	model.Parent = parent
	return model
end

function Props.pine(parent: Instance?, position: Vector3, scale: number?): Model
	local s = scale or 1
	local model = Instance.new("Model")
	model.Name = "Pine"
	Props.cylinder(model, "Trunk", 4 * s, 1.4 * s, position + Vector3.new(0, 2 * s, 0), Color3.fromRGB(115, 80, 50))
	local green = Color3.fromRGB(50, 140, 80)
	for i = 0, 2 do
		local size = (9 - i * 2.4) * s
		local y = position.Y + (4 + i * 3.4) * s
		Props.part(model, "Layer", Vector3.new(size, 3.2 * s, size),
			CFrame.new(position.X, y + 1.6 * s, position.Z) * CFrame.Angles(0, math.rad(i * 30), 0),
			green:Lerp(Color3.new(1, 1, 1), i * 0.06))
	end
	model.Parent = parent
	return model
end

function Props.bush(parent: Instance?, position: Vector3, scale: number?): Part
	local s = scale or 1
	return Props.ball(parent, "Bush", 4 * s, position + Vector3.new(0, 1.2 * s, 0), Color3.fromRGB(80, 175, 75))
end

function Props.flowerBed(parent: Instance?, cframe: CFrame, length: number): Model
	local model = Instance.new("Model")
	model.Name = "FlowerBed"
	Props.part(model, "Soil", Vector3.new(length, 1, 3), cframe * CFrame.new(0, 0.5, 0), Color3.fromRGB(120, 85, 60))
	local colors = { Color3.fromRGB(255, 90, 120), Color3.fromRGB(255, 210, 60), Color3.fromRGB(180, 110, 255), Color3.fromRGB(255, 255, 255) }
	local count = math.max(1, math.floor(length / 2))
	for i = 1, count do
		local x = -length / 2 + (i - 0.5) * (length / count)
		Props.ball(model, "Flower", 1.3, (cframe * CFrame.new(x, 1.4, 0)).Position, colors[(i % #colors) + 1], { collide = false, shadow = false })
	end
	model.Parent = parent
	return model
end

----- Street furniture -----
function Props.streetLight(parent: Instance?, cframe: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "StreetLight"
	local dark = Color3.fromRGB(55, 60, 75)
	local base = cframe.Position
	Props.cylinder(model, "Pole", 15, 0.8, base + Vector3.new(0, 7.5, 0), dark)
	Props.part(model, "Arm", Vector3.new(0.6, 0.6, 4), cframe * CFrame.new(0, 15, -1.8), dark)
	local lamp = Props.part(model, "Lamp", Vector3.new(1.8, 0.8, 2.2), cframe * CFrame.new(0, 14.6, -3.6),
		Color3.fromRGB(255, 236, 170), { material = Enum.Material.Neon })
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Range = 24
	light.Angle = 100
	light.Brightness = 1.2
	light.Color = Color3.fromRGB(255, 225, 160)
	light.Parent = lamp
	model.Parent = parent
	return model
end

function Props.bench(parent: Instance?, cframe: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Bench"
	local wood = Color3.fromRGB(190, 125, 70)
	local metal = Color3.fromRGB(60, 60, 70)
	Props.part(model, "Seat", Vector3.new(6, 0.5, 2), cframe * CFrame.new(0, 1.8, 0), wood)
	Props.part(model, "Back", Vector3.new(6, 1.8, 0.4), cframe * CFrame.new(0, 3, 0.9), wood)
	Props.part(model, "LegL", Vector3.new(0.4, 1.6, 1.8), cframe * CFrame.new(-2.5, 0.8, 0), metal)
	Props.part(model, "LegR", Vector3.new(0.4, 1.6, 1.8), cframe * CFrame.new(2.5, 0.8, 0), metal)
	model.Parent = parent
	return model
end

function Props.trashCan(parent: Instance?, position: Vector3): Part
	return Props.cylinder(parent, "TrashCan", 3, 2, position + Vector3.new(0, 1.5, 0), Color3.fromRGB(70, 150, 90))
end

function Props.hydrant(parent: Instance?, position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Hydrant"
	local red = Color3.fromRGB(225, 50, 45)
	Props.cylinder(model, "Body", 2.2, 1.2, position + Vector3.new(0, 1.1, 0), red)
	Props.ball(model, "Cap", 1.3, position + Vector3.new(0, 2.3, 0), red)
	model.Parent = parent
	return model
end

----- Vehicles -----
-- Car model: origin on the ground at its centre, facing -Z. PrimaryPart "Root".
function Props.car(parent: Instance?, color: Color3, collide: boolean?): Model
	local model = Instance.new("Model")
	model.Name = "Car"
	local opts: PartOptions = { collide = collide == true }
	local function o(extra: PartOptions?): PartOptions
		local t: PartOptions = { collide = opts.collide }
		if extra then
			for k, v in extra :: any do
				(t :: any)[k] = v
			end
		end
		return t
	end
	local root = Props.part(model, "Root", Vector3.new(6, 1, 12), CFrame.new(0, 0.5, 0), color, { transparency = 1, collide = false })
	model.PrimaryPart = root
	Props.part(model, "Body", Vector3.new(6, 2.2, 12), CFrame.new(0, 2, 0), color, o())
	Props.part(model, "Cabin", Vector3.new(5.4, 2.1, 6.4), CFrame.new(0, 4.1, 0.6), color:Lerp(Color3.new(1, 1, 1), 0.15), o())
	Props.part(model, "Windows", Vector3.new(5.6, 1.5, 6.6), CFrame.new(0, 4.2, 0.6), Color3.fromRGB(150, 200, 235), o({ material = Enum.Material.Glass, transparency = 0.2 }))
	Props.part(model, "Bumper", Vector3.new(6.2, 0.8, 0.6), CFrame.new(0, 1.3, -6.1), Color3.fromRGB(220, 220, 225), o())
	Props.part(model, "BumperBack", Vector3.new(6.2, 0.8, 0.6), CFrame.new(0, 1.3, 6.1), Color3.fromRGB(220, 220, 225), o())
	for _, side in { -1, 1 } do
		Props.part(model, "Headlight", Vector3.new(1.2, 0.6, 0.3), CFrame.new(side * 2, 2.3, -6.05), Color3.fromRGB(255, 250, 200), o({ material = Enum.Material.Neon }))
		Props.part(model, "Taillight", Vector3.new(1.2, 0.6, 0.3), CFrame.new(side * 2, 2.3, 6.05), Color3.fromRGB(255, 60, 60), o({ material = Enum.Material.Neon }))
		for _, z in { -3.8, 3.8 } do
			Props.part(model, "Wheel", Vector3.new(1.2, 2.6, 2.6), CFrame.new(side * 2.8, 1.3, z), Color3.fromRGB(35, 35, 40), o({ shape = Enum.PartType.Cylinder }))
		end
	end
	model.Parent = parent
	return model
end

----- Characters -----
local SKIN = {
	Color3.fromRGB(255, 220, 180), Color3.fromRGB(240, 195, 150), Color3.fromRGB(200, 150, 110),
	Color3.fromRGB(150, 100, 70), Color3.fromRGB(110, 75, 55), Color3.fromRGB(255, 205, 80),
}
local SHIRTS = {
	Color3.fromRGB(240, 80, 80), Color3.fromRGB(80, 160, 240), Color3.fromRGB(90, 200, 120), Color3.fromRGB(250, 200, 60),
	Color3.fromRGB(180, 100, 230), Color3.fromRGB(255, 140, 60), Color3.fromRGB(240, 240, 240), Color3.fromRGB(60, 70, 90),
}
local PANTS = {
	Color3.fromRGB(50, 70, 130), Color3.fromRGB(40, 40, 50), Color3.fromRGB(120, 90, 60), Color3.fromRGB(90, 90, 100),
}
local HAIR = {
	Color3.fromRGB(60, 40, 30), Color3.fromRGB(20, 20, 25), Color3.fromRGB(200, 150, 70), Color3.fromRGB(150, 70, 40),
	Color3.fromRGB(110, 72, 44), Color3.fromRGB(235, 205, 125), Color3.fromRGB(185, 85, 50), Color3.fromRGB(45, 30, 25),
}
local FUN_HAIR = { Color3.fromRGB(255, 130, 190), Color3.fromRGB(110, 170, 255), Color3.fromRGB(170, 120, 255) }
local CAP_COLORS = {
	Color3.fromRGB(230, 70, 70), Color3.fromRGB(60, 130, 230), Color3.fromRGB(250, 200, 60),
	Color3.fromRGB(70, 180, 110), Color3.fromRGB(245, 245, 245), Color3.fromRGB(255, 140, 190),
}
local HAIR_STYLES = { "short", "fringe", "spiky", "bun", "ponytail", "long", "afro", "cap", "beanie" }

-- Hair and hats: every piece carries a HeadOffset attribute (its CFrame relative to the
-- head), and NpcRig re-poses those pieces from the head each frame so they walk and bob
-- with it. -Z is the face side.
local HEAD_AT = CFrame.new(0, 4.5, 0)
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

local function headPiece(model: Model, name: string, size: Vector3, offset: CFrame, color: Color3, shape: string?): Part
	local p = Props.part(model, name, size, HEAD_AT * offset, color, {
		collide = false,
		shadow = false,
		shape = if shape == "cylinder" then Enum.PartType.Cylinder else nil,
	})
	if shape == "ball" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p:SetAttribute("HeadOffset", offset)
	return p
end

local function at(x: number, y: number, z: number, pitch: number?, roll: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(pitch or 0, 0, roll or 0)
end

local UPRIGHT = math.pi / 2 -- turns a Cylinder part's X axis to vertical

local function hairBack(model: Model, color: Color3)
	headPiece(model, "HairBack", Vector3.new(1.36, 1.05, 0.8), at(0, 0.02, 0.3), color, "ball")
end

local function hairBase(model: Model, color: Color3)
	headPiece(model, "HairTop", Vector3.new(1.42, 0.86, 1.42), at(0, 0.36, 0.08), color, "ball")
	hairBack(model, color)
end

local function baseballCap(model: Model, color: Color3)
	headPiece(model, "CapDome", Vector3.new(1.46, 0.84, 1.46), at(0, 0.42, 0.04), color, "ball")
	headPiece(model, "CapBrim", Vector3.new(1.1, 0.12, 0.75), at(0, 0.36, -0.8, -0.1), color:Lerp(BLACK, 0.18))
	headPiece(model, "CapButton", Vector3.new(0.22, 0.14, 0.22), at(0, 0.84, 0.04), color:Lerp(WHITE, 0.35), "ball")
end

local function chefHat(model: Model, color: Color3)
	headPiece(model, "ChefBand", Vector3.new(0.5, 1.44, 1.44), at(0, 0.55, 0.04, 0, UPRIGHT), color, "cylinder")
	headPiece(model, "ChefPuff", Vector3.new(1.75, 1.05, 1.75), at(0, 1.1, 0.04), color, "ball")
end

local function beanie(model: Model, color: Color3)
	headPiece(model, "Beanie", Vector3.new(1.48, 0.95, 1.48), at(0, 0.48, 0.06), color, "ball")
	headPiece(model, "BeanieFold", Vector3.new(0.26, 1.5, 1.5), at(0, 0.3, 0.06, 0, UPRIGHT), color:Lerp(BLACK, 0.18), "cylinder")
	headPiece(model, "Pompom", Vector3.new(0.44, 0.44, 0.44), at(0, 0.98, 0.06), color:Lerp(WHITE, 0.55), "ball")
end

-- Picks a hairstyle (or a uniform hat when `hat` is given) and builds it.
local function dressHead(model: Model, rng: Random, hat: Color3?)
	local hair = if rng:NextNumber() < 0.1 then FUN_HAIR[rng:NextInteger(1, #FUN_HAIR)] else HAIR[rng:NextInteger(1, #HAIR)]
	if hat then
		hairBack(model, hair)
		if hat.R > 0.95 and hat.G > 0.95 and hat.B > 0.95 then
			chefHat(model, hat)
		else
			baseballCap(model, hat)
		end
		return
	end
	local style = HAIR_STYLES[rng:NextInteger(1, #HAIR_STYLES)]
	if style == "short" then
		hairBase(model, hair)
	elseif style == "fringe" then
		hairBase(model, hair)
		headPiece(model, "Fringe", Vector3.new(1.25, 0.36, 0.55), at(0.1, 0.5, -0.48, 0.45, -0.15), hair, "ball")
	elseif style == "spiky" then
		headPiece(model, "HairTop", Vector3.new(1.36, 0.72, 1.36), at(0, 0.4, 0.08), hair, "ball")
		hairBack(model, hair)
		local diamond = CFrame.Angles(0, math.rad(45), 0)
		for _, spike in {
			{ 0, 0.82, 0.12, 0, 0 },
			{ -0.38, 0.7, -0.02, 0, 0.5 },
			{ 0.38, 0.7, -0.02, 0, -0.5 },
			{ 0, 0.68, -0.36, -0.5, 0 },
			{ 0, 0.68, 0.48, 0.5, 0 },
		} do
			headPiece(model, "Spike", Vector3.new(0.42, 0.62, 0.42), at(spike[1], spike[2], spike[3], spike[4], spike[5]) * diamond, hair)
		end
	elseif style == "bun" then
		hairBase(model, hair)
		headPiece(model, "Bun", Vector3.new(0.8, 0.8, 0.8), at(0, 0.88, 0.3), hair, "ball")
	elseif style == "ponytail" then
		hairBase(model, hair)
		headPiece(model, "HairTie", Vector3.new(0.36, 0.36, 0.36), at(0, 0.35, 0.74), CAP_COLORS[rng:NextInteger(1, #CAP_COLORS)], "ball")
		headPiece(model, "Ponytail", Vector3.new(0.55, 1.3, 0.55), at(0, -0.25, 0.86, 0.22), hair, "ball")
	elseif style == "long" then
		hairBase(model, hair)
		headPiece(model, "HairLong", Vector3.new(1.5, 2, 0.75), at(0, -0.4, 0.36), hair, "ball")
		for _, side in { -1, 1 } do
			headPiece(model, "SideLock", Vector3.new(0.3, 1.2, 0.55), at(side * 0.66, -0.2, 0), hair, "ball")
		end
	elseif style == "afro" then
		headPiece(model, "Afro", Vector3.new(1.95, 1.65, 1.9), at(0, 0.45, 0.3), hair, "ball")
	elseif style == "cap" then
		hairBack(model, hair)
		baseballCap(model, CAP_COLORS[rng:NextInteger(1, #CAP_COLORS)])
	else
		hairBack(model, hair)
		beanie(model, CAP_COLORS[rng:NextInteger(1, #CAP_COLORS)])
	end
end

export type NpcLook = { shirt: Color3?, pants: Color3?, hat: Color3? }

-- Blocky Roblox-style character built from anchored, non-colliding parts so it can
-- be animated cheaply with CFrames (see Client.NpcRig).
function Props.npc(parent: Instance?, rng: Random, look: NpcLook?): Model
	local model = Instance.new("Model")
	model.Name = "Npc"
	local skin = SKIN[rng:NextInteger(1, #SKIN)]
	local shirt = (look and look.shirt) or SHIRTS[rng:NextInteger(1, #SHIRTS)]
	local pants = (look and look.pants) or PANTS[rng:NextInteger(1, #PANTS)]
	local opts: PartOptions = { collide = false, shadow = false }
	local root = Props.part(model, "Root", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), shirt, { transparency = 1, collide = false, shadow = false })
	model.PrimaryPart = root
	Props.part(model, "Torso", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), shirt, opts)
	Props.part(model, "LeftArm", Vector3.new(1, 2, 1), CFrame.new(-1.5, 3, 0), skin, opts)
	Props.part(model, "RightArm", Vector3.new(1, 2, 1), CFrame.new(1.5, 3, 0), skin, opts)
	Props.part(model, "LeftLeg", Vector3.new(1, 2, 1), CFrame.new(-0.5, 1, 0), pants, opts)
	Props.part(model, "RightLeg", Vector3.new(1, 2, 1), CFrame.new(0.5, 1, 0), pants, opts)
	local head = Props.part(model, "Head", Vector3.new(2, 1, 1), CFrame.new(0, 4.5, 0), skin, opts)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head
	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	dressHead(model, rng, look and look.hat)
	model.Parent = parent
	return model
end

return Props
