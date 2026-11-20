--!strict
-- DayNightController (client): a gentle 12-minute day with a golden sunset, a short
-- starry night and a pink sunrise. It runs on server time, so every player in the
-- server sees the same sky. Nights stay bright enough to play (cartoon blue, not black).
-- Inside a business it is always midday so interiors stay readable.
-- Only Lighting colours, Brightness and ClockTime change: ExposureCompensation is left to
-- InteriorController.
-- Container: StarterPlayerScripts.Controllers

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DayNightController = {}

local CYCLE = 720 -- seconds for a full day
local UPDATE_EVERY = 0.1
local INSIDE_CLOCK = 14.5

-- phase (0..1 of the cycle) -> clock time and mood weights (golden, night).
type Key = { phase: number, clock: number, golden: number, night: number }
local KEYS: { Key } = {
	{ phase = 0.00, clock = 6.6, golden = 0.6, night = 0.15 },
	{ phase = 0.05, clock = 8.0, golden = 0, night = 0 },
	{ phase = 0.60, clock = 15.8, golden = 0, night = 0 },
	{ phase = 0.68, clock = 17.2, golden = 1, night = 0 },
	{ phase = 0.73, clock = 18.2, golden = 0.5, night = 0.5 },
	{ phase = 0.78, clock = 19.5, golden = 0, night = 1 },
	{ phase = 0.93, clock = 28.8, golden = 0, night = 1 },
	{ phase = 0.97, clock = 29.8, golden = 0.6, night = 0.4 },
	{ phase = 1.00, clock = 30.6, golden = 0.6, night = 0.15 },
}

type Look = { brightness: number, outdoor: Color3, ambient: Color3, tint: Color3, air: Color3, decay: Color3 }
local GOLDEN: Look = {
	brightness = 2.5,
	outdoor = Color3.fromRGB(170, 150, 150),
	ambient = Color3.fromRGB(135, 120, 125),
	tint = Color3.fromRGB(255, 230, 205),
	air = Color3.fromRGB(255, 205, 170),
	decay = Color3.fromRGB(210, 150, 150),
}
local NIGHT: Look = {
	brightness = 1.6,
	outdoor = Color3.fromRGB(110, 118, 162),
	ambient = Color3.fromRGB(100, 104, 140),
	tint = Color3.fromRGB(210, 220, 255),
	air = Color3.fromRGB(70, 80, 125),
	decay = Color3.fromRGB(40, 45, 80),
}

local controllers: any
local day: Look
local color: ColorCorrectionEffect? = nil
type AirDay = { atmosphere: Atmosphere, color: Color3, decay: Color3 }
local atmospheres: { AirDay } = {}
local currentNight = 0
local currentGolden = 0
local currentClock = INSIDE_CLOCK

-- Street lamps shine brighter and wider once it gets dark.
local LAMP_DAY = { brightness = 1.2, range = 24 }
local LAMP_NIGHT = { brightness = 3.2, range = 30 }
local lamps: { SpotLight }? = nil
local lampsLit = false

local function setLamps(lit: boolean)
	if lit == lampsLit then
		return
	end
	lampsLit = lit
	if not lamps then
		local found: { SpotLight } = {}
		local city = Workspace:FindFirstChild("City")
		if city then
			for _, descendant in city:GetDescendants() do
				if descendant:IsA("SpotLight") and descendant.Parent and descendant.Parent.Name == "Lamp" then
					table.insert(found, descendant)
				end
			end
		end
		lamps = found
	end
	local look = if lit then LAMP_NIGHT else LAMP_DAY
	for _, light in lamps :: { SpotLight } do
		light.Brightness = look.brightness
		light.Range = look.range
	end
end

local function mixColor(base: Color3, golden: Color3, night: Color3, g: number, n: number): Color3
	local d = math.max(0, 1 - g - n)
	return Color3.new(
		base.R * d + golden.R * g + night.R * n,
		base.G * d + golden.G * g + night.G * n,
		base.B * d + golden.B * g + night.B * n
	)
end

-- Where the shared clock is right now: clock time and mood weights.
local function sample(): (number, number, number)
	local phase = (Workspace:GetServerTimeNow() % CYCLE) / CYCLE
	for i = 1, #KEYS - 1 do
		local a, b = KEYS[i], KEYS[i + 1]
		if phase >= a.phase and phase <= b.phase then
			local t = (phase - a.phase) / math.max(b.phase - a.phase, 1e-6)
			return a.clock + (b.clock - a.clock) * t, a.golden + (b.golden - a.golden) * t, a.night + (b.night - a.night) * t
		end
	end
	return KEYS[1].clock, KEYS[1].golden, KEYS[1].night
end

local function apply(clock: number, g: number, n: number)
	currentClock, currentGolden, currentNight = clock, g, n
	Lighting.ClockTime = clock % 24
	local d = math.max(0, 1 - g - n)
	Lighting.Brightness = day.brightness * d + GOLDEN.brightness * g + NIGHT.brightness * n
	Lighting.OutdoorAmbient = mixColor(day.outdoor, GOLDEN.outdoor, NIGHT.outdoor, g, n)
	Lighting.Ambient = mixColor(day.ambient, GOLDEN.ambient, NIGHT.ambient, g, n)
	if color then
		color.TintColor = mixColor(day.tint, GOLDEN.tint, NIGHT.tint, g, n)
	end
	for _, entry in atmospheres do
		entry.atmosphere.Color = mixColor(entry.color, GOLDEN.air, NIGHT.air, g, n)
		entry.atmosphere.Decay = mixColor(entry.decay, GOLDEN.decay, NIGHT.decay, g, n)
	end
	setLamps(n > 0.35)
end

-- 1 in full daylight, 0 at night. Other controllers use it (butterflies sleep at night).
function DayNightController.daylight(): number
	return 1 - currentNight
end

-- Hour of the day (0..24) currently shown.
function DayNightController.clock(): number
	return currentClock % 24
end

function DayNightController.init(registry: any)
	controllers = registry
end

function DayNightController.start()
	day = {
		brightness = Lighting.Brightness,
		outdoor = Lighting.OutdoorAmbient,
		ambient = Lighting.Ambient,
		tint = Color3.new(1, 1, 1),
		air = Color3.new(1, 1, 1),
		decay = Color3.new(1, 1, 1),
	}
	local correction = Lighting:FindFirstChild("CityColor")
	if correction and correction:IsA("ColorCorrectionEffect") then
		color = correction
		day.tint = correction.TintColor
	end
	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") then
			table.insert(atmospheres, { atmosphere = child, color = child.Color, decay = child.Decay })
		end
	end
	local elapsed = UPDATE_EVERY
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < UPDATE_EVERY then
			return
		end
		elapsed = 0
		if controllers.Interior and controllers.Interior.isInside() then
			apply(INSIDE_CLOCK, 0, 0)
		else
			apply(sample())
		end
	end)
end

return DayNightController
