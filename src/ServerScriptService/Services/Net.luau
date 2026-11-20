--!strict
-- Net: RemoteEvent access with per-player rate limiting and error isolation.
-- Every client request goes through Net.on, so no handler can be spammed or crash
-- the server loop. Handlers still validate their own arguments.
-- Container: ServerScriptService.Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder

type Bucket = { tokens: number, last: number }
local buckets: { [Player]: { [string]: Bucket } } = {}

local function getRemote(name: string): RemoteEvent
	local remote = remotes:FindFirstChild(name)
	if not remote then
		local created = Instance.new("RemoteEvent")
		created.Name = name
		created.Parent = remotes
		remote = created
	end
	return remote :: RemoteEvent
end

-- Token bucket: `rate` requests per second, bursts up to rate * 2.
local function allow(player: Player, name: string, rate: number): boolean
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local now = os.clock()
	local bucket = playerBuckets[name]
	if not bucket then
		bucket = { tokens = rate * 2, last = now }
		playerBuckets[name] = bucket
	end
	bucket.tokens = math.min(rate * 2, bucket.tokens + (now - bucket.last) * rate)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function Net.on(name: string, ratePerSecond: number, handler: (Player, ...any) -> ())
	getRemote(name).OnServerEvent:Connect(function(player: Player, ...)
		if not allow(player, name, ratePerSecond) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(string.format("[Net] %s handler failed for %s: %s", name, player.Name, tostring(err)))
		end
	end)
end

-- Creates a server-to-client remote up front, so clients can wait for it at startup.
function Net.declare(name: string)
	getRemote(name)
end

function Net.fire(player: Player, name: string, ...: any)
	getRemote(name):FireClient(player, ...)
end

function Net.fireAll(name: string, ...: any)
	getRemote(name):FireAllClients(...)
end

-- Validation helpers
function Net.isString(value: any, maxLength: number?): boolean
	return type(value) == "string" and #value > 0 and #value <= (maxLength or 64)
end

function Net.isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Net.notify(player: Player, kind: string, text: string)
	Net.fire(player, "Notify", kind, text)
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

return Net
