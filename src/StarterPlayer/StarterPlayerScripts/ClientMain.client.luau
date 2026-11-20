--!strict
-- ClientMain: boots every client controller. init() wires references (no yielding),
-- start() connects events. Store starts first so the others can read state.
-- Container: StarterPlayerScripts

local folder = script.Parent:WaitForChild("Controllers")

local ORDER = {
	{ key = "Store", module = "Store" },
	{ key = "Sound", module = "SoundController" },
	{ key = "UI", module = "UIController" },
	{ key = "Interior", module = "InteriorController" },
	{ key = "City", module = "CityController" },
	{ key = "Ambient", module = "AmbientController" },
	{ key = "DayNight", module = "DayNightController" },
	{ key = "Job", module = "JobController" },
	{ key = "MiniGame", module = "MiniGameController" },
	{ key = "Opening", module = "OpeningController" },
	{ key = "Life", module = "LifeController" },
}

local registry: { [string]: any } = {}

for _, entry in ORDER do
	local ok, result = pcall(require, folder:WaitForChild(entry.module))
	if ok then
		registry[entry.key] = result
	else
		warn("[ClientMain] failed to load " .. entry.module .. ": " .. tostring(result))
	end
end

for _, entry in ORDER do
	local controller = registry[entry.key]
	if controller and controller.init then
		local ok, err = pcall(controller.init, registry)
		if not ok then
			warn("[ClientMain] " .. entry.module .. ".init failed: " .. tostring(err))
		end
	end
end

for _, entry in ORDER do
	local controller = registry[entry.key]
	if controller and controller.start then
		task.spawn(function()
			local ok, err = pcall(controller.start)
			if not ok then
				warn("[ClientMain] " .. entry.module .. ".start failed: " .. tostring(err))
			end
		end)
	end
end
