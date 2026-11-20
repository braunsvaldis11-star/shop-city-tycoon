--!strict
-- InteriorService: physical entrances and private, per-player business interiors.
--
-- Architecture (shared city, personal businesses):
--  * The city and every business entrance are shared server objects.
--  * Each player is assigned a private "slot" far outside the city. When an owner walks
--    through a business door, the server tells ONLY that player's client to build the
--    interior in their slot, waits for the client to confirm, then moves the character.
--  * Interior geometry exists only on the owner's client, so other players can never
--    see or touch it. Everything that matters (money, upgrades, serving) is still decided
--    by the server, which also knows exactly which interior each player is in.
--  * A guard loop ejects anyone found in the interior zone without a valid session.
-- Container: ServerScriptService.Services

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Businesses = require(Shared.Businesses)
local Config = require(Shared.Config)
local Format = require(Shared.Format)

local InteriorService = {}

type Session = { businessId: string, origin: Vector3 }
type Pending = { businessId: string, token: string, expires: number }

local services: any
local slots: { [Player]: number } = {}
local usedSlots: { [number]: boolean } = {}
local inside: { [Player]: Session } = {}
local pending: { [Player]: Pending } = {}
local touchDebounce: { [Player]: number } = {}
local exitSpots: { [string]: BasePart } = {}

local READY_TIMEOUT = 8

local function assignSlot(player: Player): number
	local slot = 1
	while usedSlots[slot] do
		slot += 1
	end
	usedSlots[slot] = true
	slots[player] = slot
	return slot
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function moveCharacter(player: Player, target: CFrame)
	local character = player.Character
	if character then
		character:PivotTo(target)
	end
end

function InteriorService.getInsideBusiness(player: Player): string?
	local session = inside[player]
	return if session then session.businessId else nil
end

function InteriorService.getSlotOrigin(player: Player): Vector3
	return Config.getSlotOrigin(slots[player] or assignSlot(player))
end

local function sendToCity(player: Player, businessId: string?)
	local spot = if businessId then exitSpots[businessId] else nil
	if spot then
		moveCharacter(player, spot.CFrame + Vector3.new(0, 3, 0))
	else
		moveCharacter(player, CFrame.new(Config.CITY_SPAWN))
	end
end

function InteriorService.enter(player: Player, businessId: string)
	if inside[player] or pending[player] then
		return
	end
	local definition = Businesses.get(businessId)
	if not definition or not services.Business.owns(player, businessId) then
		return
	end
	if not getRoot(player) then
		return
	end
	local token = HttpService:GenerateGUID(false)
	pending[player] = { businessId = businessId, token = token, expires = os.clock() + READY_TIMEOUT }
	services.Net.fire(player, "EnterInterior", businessId, InteriorService.getSlotOrigin(player), token)
end

-- The client finished building the interior in its slot: move the character in.
local function onInteriorReady(player: Player, token: any)
	local request = pending[player]
	if not request or type(token) ~= "string" or token ~= request.token then
		return
	end
	pending[player] = nil
	if os.clock() > request.expires or not services.Business.owns(player, request.businessId) then
		services.Net.fire(player, "ExitInterior")
		return
	end
	local origin = InteriorService.getSlotOrigin(player)
	inside[player] = { businessId = request.businessId, origin = origin }
	local spawn = origin + Config.INTERIOR_SPAWN_OFFSET
	moveCharacter(player, CFrame.lookAt(spawn, spawn + Vector3.new(0, 0, -1)))

	local profile = services.Data.get(player)
	if profile and not profile.data.visited[request.businessId] then
		profile.data.visited[request.businessId] = true
		services.Data.markDirty(player)
		services.Progression.check(player)
		services.Sync.mark(player)
	end
	services.Sync.mark(player)
end

function InteriorService.exit(player: Player)
	local session = inside[player]
	pending[player] = nil
	if not session then
		return
	end
	inside[player] = nil
	sendToCity(player, session.businessId)
	services.Net.fire(player, "ExitInterior")
	services.Sync.mark(player)
end

-- Hook up every shared entrance in the city.
local function setupEntrance(model: Instance)
	local businessId = model:GetAttribute("BusinessId")
	if type(businessId) ~= "string" or not Businesses.get(businessId) then
		return
	end
	local definition = Businesses.get(businessId) :: Businesses.Definition

	local exitSpot = model:FindFirstChild("ExitSpot")
	if exitSpot and exitSpot:IsA("BasePart") then
		exitSpots[businessId] = exitSpot
	end

	local door = model:FindFirstChild("Door")
	local prompt = if door then door:FindFirstChildOfClass("ProximityPrompt") else nil
	if prompt then
		prompt.ActionText = "Buy " .. Format.cash(definition.price)
		prompt.ObjectText = definition.name
		prompt.Triggered:Connect(function(player: Player)
			if services.Business.owns(player, businessId) then
				InteriorService.enter(player, businessId)
			else
				services.Business.purchase(player, businessId)
			end
		end)
	end

	-- Walking through the (locally opened) door of an owned business enters it.
	local trigger = model:FindFirstChild("EntryTrigger")
	if trigger and trigger:IsA("BasePart") then
		trigger.Touched:Connect(function(hit: BasePart)
			local character = hit.Parent
			local player = if character then Players:GetPlayerFromCharacter(character) else nil
			if not player then
				return
			end
			local now = os.clock()
			if (touchDebounce[player] or 0) > now then
				return
			end
			touchDebounce[player] = now + 1.5
			if services.Business.owns(player, businessId) then
				InteriorService.enter(player, businessId)
			else
				-- A non-owner squeezed past the door: push them back outside.
				sendToCity(player, businessId)
			end
		end)
	end
end

local function onPlayerAdded(player: Player)
	assignSlot(player)
	player.CharacterAdded:Connect(function()
		-- Respawning always puts you back in the city.
		if inside[player] or pending[player] then
			inside[player] = nil
			pending[player] = nil
			services.Net.fire(player, "ExitInterior")
			services.Sync.mark(player)
		end
	end)
end

local function onPlayerRemoving(player: Player)
	local slot = slots[player]
	if slot then
		usedSlots[slot] = nil
	end
	slots[player] = nil
	inside[player] = nil
	pending[player] = nil
	touchDebounce[player] = nil
end

-- Security guard: nobody may be in the interior zone without a valid session, and a
-- session only covers the player's own slot.
local function guardTick()
	local now = os.clock()
	for player, request in pending do
		if now > request.expires then
			pending[player] = nil
			services.Net.fire(player, "ExitInterior")
		end
	end
	for _, player in Players:GetPlayers() do
		local root = getRoot(player)
		if root then
			local position = root.Position
			local session = inside[player]
			if position.Y > Config.INTERIOR_MIN_Y then
				if not session then
					if not pending[player] then
						sendToCity(player, nil)
					end
				else
					local offset = position - session.origin
					if Vector3.new(offset.X, 0, offset.Z).Magnitude > Config.INTERIOR_ROOM_RADIUS then
						InteriorService.exit(player)
					end
				end
			elseif session and position.Y < session.origin.Y - 60 then
				-- Fell out of the interior: bring them back to the city cleanly.
				InteriorService.exit(player)
			end
		end
	end
end

function InteriorService.init(registry: any)
	services = registry
end

function InteriorService.start()
	local city = Workspace:WaitForChild("City", 30)
	local folder = if city then city:WaitForChild("Businesses", 30) else nil
	if folder then
		for _, model in folder:GetChildren() do
			setupEntrance(model)
		end
	else
		warn("[InteriorService] Workspace.City.Businesses not found; entrances disabled.")
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	services.Net.on("InteriorReady", 2, onInteriorReady)
	services.Net.on("RequestExit", 2, function(player)
		InteriorService.exit(player)
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(guardTick)
			if not ok then
				warn("[InteriorService] guard error: " .. tostring(err))
			end
		end
	end)
end

return InteriorService
