--!strict
-- NpcRig (client only): cheap animated characters for customers, staff and pedestrians.
-- No Humanoids, no physics: every rig is anchored parts posed with CFrame maths, and
-- all rigs are moved together with one workspace:BulkMoveTo call per frame.
-- Container: ReplicatedStorage.Client

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Props = require(ReplicatedStorage:WaitForChild("Shared").Props)

local NpcRig = {}
NpcRig.__index = NpcRig

-- Personal space: NPCs never walk through the local player. Moving NPCs slide around
-- them; standing ones lean out of the way until the player moves on.
local AVOID_RADIUS = 2.8
local avoidPoint: Vector3? = nil
if RunService:IsClient() then
	RunService.Heartbeat:Connect(function()
		local player = Players.LocalPlayer
		local character = player and player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		avoidPoint = if root then root.Position else nil
	end)
end

local function avoidance(position: Vector3): Vector3
	local point = avoidPoint
	if not point or math.abs(point.Y - 3 - position.Y) > 6 then
		return Vector3.zero
	end
	local offset = Vector3.new(position.X - point.X, 0, position.Z - point.Z)
	local distance = offset.Magnitude
	if distance >= AVOID_RADIUS then
		return Vector3.zero
	end
	local direction = if distance > 0.05 then offset / distance else Vector3.xAxis
	return direction * (AVOID_RADIUS - distance)
end

export type Rig = typeof(setmetatable({} :: {
	model: Model,
	parts: { [string]: BasePart },
	headParts: { BasePart }, -- hair and hats, posed relative to the head
	headOffsets: { CFrame },
	position: Vector3, -- feet position
	yaw: number,
	phase: number,
	moving: boolean,
	sitting: boolean,
	working: boolean,
	carrying: BasePart?,
	scale: number,
	speed: number,
	path: { Vector3 },
}, NpcRig))

function NpcRig.new(parent: Instance, rng: Random, look: Props.NpcLook?, position: Vector3): Rig
	local model = Props.npc(parent, rng, look)
	local parts = {}
	local headParts: { BasePart } = {}
	local headOffsets: { CFrame } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			local offset = child:GetAttribute("HeadOffset")
			if typeof(offset) == "CFrame" then
				table.insert(headParts, child)
				table.insert(headOffsets, offset)
			else
				parts[child.Name] = child
			end
		end
	end
	local self = setmetatable({
		model = model,
		parts = parts,
		headParts = headParts,
		headOffsets = headOffsets,
		position = position,
		yaw = 0,
		phase = rng:NextNumber(0, 6),
		moving = false,
		sitting = false,
		working = false,
		carrying = nil,
		scale = 1,
		speed = 9,
		path = {},
	}, NpcRig)
	return self
end

function NpcRig.setPath(self: Rig, points: { Vector3 })
	self.path = points
end

-- Walks along the path. Returns true once the last point is reached.
function NpcRig.step(self: Rig, dt: number): boolean
	local target = self.path[1]
	if not target then
		self.moving = false
		return true
	end
	local offset = Vector3.new(target.X - self.position.X, 0, target.Z - self.position.Z)
	local distance = offset.Magnitude
	local travel = self.speed * dt
	if distance <= travel then
		self.position = Vector3.new(target.X, target.Y, target.Z)
		table.remove(self.path, 1)
	else
		local direction = offset / distance
		self.position += direction * travel
		self.yaw = math.atan2(-direction.X, -direction.Z)
	end
	self.moving = #self.path > 0
	return not self.moving
end

function NpcRig.face(self: Rig, point: Vector3)
	local d = point - self.position
	if d.Magnitude > 0.01 then
		self.yaw = math.atan2(-d.X, -d.Z)
	end
end

-- Appends this rig's parts and target CFrames to the batch lists.
function NpcRig.collect(self: Rig, dt: number, partsOut: { BasePart }, cframesOut: { CFrame })
	if self.moving then
		self.phase += dt * 9
	elseif self.working then
		self.phase += dt * 6
	end
	local swing = if self.moving then math.sin(self.phase) * 0.6 else 0
	local bob = if self.working then math.abs(math.sin(self.phase)) * 0.15 else 0
	local shown = self.position
	if not self.sitting then
		local push = avoidance(self.position)
		if self.moving then
			self.position += push -- walk around the player
			shown = self.position
		else
			shown += push -- just lean aside, keep our spot in line
		end
	end
	local root = CFrame.new(shown + Vector3.new(0, 3 + bob, 0)) * CFrame.Angles(0, self.yaw, 0)
	local p = self.parts
	local legAngle = if self.sitting then math.pi / 2 else swing
	local leftArm = -swing
	local rightArm = swing
	if self.carrying then
		leftArm, rightArm = math.pi / 2.2, math.pi / 2.2
	elseif self.working then
		leftArm = math.sin(self.phase) * 0.8 + 0.6
		rightArm = -math.sin(self.phase) * 0.8 + 0.6
	end
	local function add(part: BasePart?, cf: CFrame)
		if part then
			table.insert(partsOut, part)
			table.insert(cframesOut, cf)
		end
	end
	add(p.Root, root)
	add(p.Torso, root)
	local head = root * CFrame.new(0, 1.5, 0)
	add(p.Head, head)
	for i, part in self.headParts do
		add(part, head * self.headOffsets[i])
	end
	add(p.LeftLeg, root * CFrame.new(-0.5, -1, 0) * CFrame.Angles(legAngle, 0, 0) * CFrame.new(0, -1, 0))
	add(p.RightLeg, root * CFrame.new(0.5, -1, 0) * CFrame.Angles(if self.sitting then legAngle else -legAngle, 0, 0) * CFrame.new(0, -1, 0))
	add(p.LeftArm, root * CFrame.new(-1.5, 1, 0) * CFrame.Angles(leftArm, 0, 0) * CFrame.new(0, -1, 0))
	add(p.RightArm, root * CFrame.new(1.5, 1, 0) * CFrame.Angles(rightArm, 0, 0) * CFrame.new(0, -1, 0))
	if self.carrying then
		add(self.carrying, root * CFrame.new(0, 0.4, -1.9))
	end
end

function NpcRig.destroy(self: Rig)
	if self.carrying then
		self.carrying:Destroy()
		self.carrying = nil
	end
	self.model:Destroy()
end

-- Moves every rig in one engine call.
function NpcRig.flush(parts: { BasePart }, cframes: { CFrame })
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

return NpcRig
