--!strict
-- Main: server bootstrap. Wires every service together (init), then starts them.
-- Services talk to each other through the shared registry instead of requiring each
-- other directly, which avoids circular requires.
-- Container: ServerScriptService

local ServerScriptService = game:GetService("ServerScriptService")

local folder = ServerScriptService:WaitForChild("Services")

local registry = {
	Net = require(folder:WaitForChild("Net")),
	Data = require(folder:WaitForChild("DataService")),
	Economy = require(folder:WaitForChild("EconomyService")),
	Business = require(folder:WaitForChild("BusinessService")),
	Interior = require(folder:WaitForChild("InteriorService")),
	Progression = require(folder:WaitForChild("ProgressionService")),
	Sync = require(folder:WaitForChild("SyncService")),
	Job = require(folder:WaitForChild("JobService")),
	MiniGame = require(folder:WaitForChild("MiniGameService")),
	Monetization = require(folder:WaitForChild("MonetizationService")),
}

local ORDER = { "Data", "Economy", "Business", "Interior", "Progression", "Sync", "Job", "MiniGame", "Monetization" }

for _, name in ORDER do
	local service = (registry :: any)[name]
	if service.init then
		service.init(registry)
	end
end

-- Start everything except Data first, so their onLoaded callbacks are registered
-- before any player's data finishes loading.
for _, name in { "Economy", "Business", "Interior", "Progression", "Sync", "Job", "MiniGame", "Monetization", "Data" } do
	local service = (registry :: any)[name]
	local ok, err = pcall(service.start)
	if not ok then
		warn("[Main] " .. name .. " failed to start: " .. tostring(err))
	end
end

print("[City Business Simulator] Server ready")
