--!strict
-- Store (client): read-only copy of this player's state, pushed by the server.
-- Controllers subscribe with Store.onChange. The client never edits this state;
-- it only sends requests that the server validates.
-- Container: StarterPlayerScripts.Controllers

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Store = {}

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local listeners: { (any) -> () } = {}

Store.state = nil :: any
Store.localPlayer = Players.LocalPlayer

function Store.onChange(callback: (any) -> ())
	table.insert(listeners, callback)
	if Store.state then
		task.spawn(callback, Store.state)
	end
end

function Store.money(): number
	local value = Store.localPlayer:GetAttribute("Money")
	if type(value) == "number" then
		return value
	end
	return if Store.state then Store.state.money else 0
end

function Store.income(): number
	local value = Store.localPlayer:GetAttribute("Income")
	return if type(value) == "number" then value else 0
end

function Store.owns(businessId: string): boolean
	return Store.state ~= nil and Store.state.businesses[businessId] ~= nil
end

function Store.send(remoteName: string, ...: any)
	local remote = remotes:FindFirstChild(remoteName)
	if remote and remote:IsA("RemoteEvent") then
		remote:FireServer(...)
	end
end

function Store.remote(name: string): RemoteEvent
	return remotes:WaitForChild(name) :: RemoteEvent
end

function Store.start()
	Store.remote("StateSync").OnClientEvent:Connect(function(state)
		if type(state) ~= "table" then
			return
		end
		Store.state = state
		for _, callback in listeners do
			local ok, err = pcall(callback, state)
			if not ok then
				warn("[Store] listener error: " .. tostring(err))
			end
		end
	end)
	-- Ask for a snapshot in case the first one arrived before we connected.
	Store.send("StateSync")
end

return Store
