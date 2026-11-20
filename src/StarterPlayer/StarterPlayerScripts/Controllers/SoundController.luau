--!strict
-- SoundController (client): UI and feedback sounds (SFX setting), a shuffled playlist of
-- relaxed background music (Music setting) and a soft city ambience loop that drops
-- away inside businesses. The music dips while you stand near the street busker.
-- Container: StarterPlayerScripts.Controllers

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local SoundController = {}

-- Roblox licensed library tracks (APM Music / ProSoundEffects), free to use in experiences.
local PLAYLIST = {
	"rbxassetid://1839821481", -- Optimistic Side
	"rbxassetid://1846927121", -- Saucepan Sally
	"rbxassetid://9046862941", -- Sunset Chill (Bed Version)
	"rbxassetid://1835291471", -- Time Flies
}
local MUSIC_VOLUME = 0.22
local AMBIENCE_ID = "rbxassetid://9112758500" -- City Ambience 3
local AMBIENCE_VOLUME = 0.14
local AMBIENCE_INSIDE = 0.03

local sounds: { [string]: Sound } = {}
local enabled = true
local musicEnabled = true
local settingsKnown = false
local store: any
local controllers: any
local music: Sound
local ambience: Sound
local order: { number } = {}
local trackIndex = 0

local function shuffle()
	local last = order[#order]
	table.clear(order)
	for i = 1, #PLAYLIST do
		order[i] = i
	end
	for i = #order, 2, -1 do
		local j = math.random(1, i)
		order[i], order[j] = order[j], order[i]
	end
	-- Never play the same track twice in a row across a reshuffle.
	if #order > 1 and order[1] == last then
		order[1], order[2] = order[2], order[1]
	end
	trackIndex = 0
end

local function nextTrack()
	trackIndex += 1
	if trackIndex > #order then
		shuffle()
		trackIndex = 1
	end
	music.SoundId = PLAYLIST[order[trackIndex]]
	music.TimePosition = 0
	if musicEnabled then
		music:Play()
	end
end

local function applySettings(state: any)
	local settings = state and state.settings
	if not settings then
		return
	end
	enabled = settings.sfx ~= false
	musicEnabled = settings.music ~= false
	if not settingsKnown then
		settingsKnown = true
		music.Volume = 0
		nextTrack()
	end
	if musicEnabled and not music.IsPlaying then
		music:Resume()
	elseif not musicEnabled and music.IsPlaying then
		music:Pause()
	end
	if enabled and not ambience.IsPlaying then
		ambience:Play()
	elseif not enabled and ambience.IsPlaying then
		ambience:Stop()
	end
end

-- Smoothly steers both loops towards their target volumes.
local function mix(dt: number)
	if not settingsKnown then
		return
	end
	local inside = controllers.Interior ~= nil and controllers.Interior.isInside()
	local musicTarget = MUSIC_VOLUME
	local life = controllers.Life
	if life and life.buskerDistance then
		local distance = life.buskerDistance()
		if distance < 80 then
			musicTarget *= math.clamp((distance - 15) / 65, 0.08, 1)
		end
	end
	local ambienceTarget = if inside then AMBIENCE_INSIDE else AMBIENCE_VOLUME
	local blend = math.min(1, dt * 2.5)
	music.Volume += (musicTarget - music.Volume) * blend
	ambience.Volume += (ambienceTarget - ambience.Volume) * blend
end

function SoundController.play(name: string, volume: number?)
	if not enabled then
		return
	end
	local sound = sounds[name]
	if sound then
		sound.Volume = volume or 0.5
		SoundService:PlayLocalSound(sound)
	end
end

function SoundController.init(registry: any)
	controllers = registry
	store = registry.Store
	local folder = Instance.new("Folder")
	folder.Name = "GameSounds"
	for name, id in Config.Sounds do
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = id
		sound.Parent = folder
		sounds[name] = sound
	end
	music = Instance.new("Sound")
	music.Name = "BackgroundMusic"
	music.Volume = 0
	music.Parent = folder
	ambience = Instance.new("Sound")
	ambience.Name = "CityAmbience"
	ambience.SoundId = AMBIENCE_ID
	ambience.Looped = true
	ambience.Volume = AMBIENCE_VOLUME
	ambience.Parent = folder
	folder.Parent = SoundService
end

function SoundController.start()
	shuffle()
	music.Ended:Connect(nextTrack)
	store.onChange(applySettings)
	RunService.Heartbeat:Connect(mix)
end

return SoundController
