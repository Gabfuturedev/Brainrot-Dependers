--!strict
-- Plays the sounds named in SoundConfig. Works from either side: the server
-- uses playOn for things the whole area should hear, the client uses play2d for
-- things that happened to you personally.
--
-- Every Sound instance here is created, played and thrown away. Pooling would
-- save allocations, but these are short one-shots and Roblox already caches the
-- decoded asset - the instance is the cheap part.

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local SoundConfig = require(script.Parent.Config.SoundConfig)

-- Sounds are one-shots; nothing here should outlive this by much even if the
-- Ended signal never arrives because the asset failed to load.
local CLEANUP_AFTER = 10
local ROLLOFF_MAX = 90 -- studs; past this a break is someone else's business

local Sound = {}

local announced: { [string]: boolean } = {}

-- Returns nil when the sound has no id yet, which is the normal state until
-- someone fills SoundConfig in. Mentioned once per name so it is discoverable
-- without turning into per-frame noise.
local function build(name: string, pitch: number?): Sound?
	local def = SoundConfig.get(name)
	if not def then
		warn(`[Sound] no entry named '{name}' in SoundConfig`)
		return nil
	end

	if def.id == "" then
		if not announced[name] then
			announced[name] = true
			print(`[Sound] '{name}' has no asset id yet - add one in SoundConfig to hear it`)
		end
		return nil
	end

	local sound = Instance.new("Sound")
	sound.SoundId = def.id
	sound.Volume = def.volume

	local speed = 1
	if def.pitchRange then
		local low, high = def.pitchRange[1], def.pitchRange[2]
		speed = low + math.random() * (high - low)
	end
	sound.PlaybackSpeed = speed * (pitch or 1)

	return sound
end

local function playAndDiscard(sound: Sound)
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, CLEANUP_AFTER)
end

-- Non-positional: for things that happened to you, wherever you happen to be.
function Sound.play2d(name: string, pitch: number?)
	local sound = build(name, pitch)
	if not sound then
		return
	end

	sound.Parent = SoundService
	playAndDiscard(sound)
end

-- Positional, parented to the part it belongs to. Parenting rather than
-- spawning a carrier part means it follows and dies with whatever made it, and
-- it still works on a part that has been made invisible.
function Sound.playOn(name: string, part: BasePart, pitch: number?)
	local sound = build(name, pitch)
	if not sound then
		return
	end

	sound.RollOffMaxDistance = ROLLOFF_MAX
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.Parent = part
	playAndDiscard(sound)
end

return Sound
