--!strict
-- Every sound the game plays, in one place.
--
-- Ids start blank on purpose. An unset sound is a silent no-op rather than an
-- error, so the game runs perfectly well without audio and gains it the moment
-- you paste ids in - no code changes, same as adding a pet.
--
-- To fill one in: Creator Store -> Audio, find a sound, copy its asset id, and
-- write it here as "rbxassetid://123456789". The same ownership rule that bit
-- us on animations does NOT apply to audio from the Creator Store, but private
-- uploads still have to belong to you or the group that owns the place.

export type SoundDef = {
	id: string,
	volume: number,
	-- Randomised per play. A sound heard hundreds of times a session becomes
	-- grating fast when it is the identical waveform every time; a few percent
	-- of pitch wobble is most of what stops that.
	pitchRange: { number }?,
}

local SoundConfig = {}

SoundConfig.Sounds = {
	-- Positional, played on the breakable itself, so everyone nearby hears it.
	Break = { id = "rbxassetid://130093389037577", volume = 0.5, pitchRange = { 0.92, 1.08 } } :: SoundDef,

	-- You will hear this one more than any other sound in the game - several
	-- times a second with three pets equipped. Keep it short and quiet.
	Hit = { id = "rbxassetid://139697578472716", volume = 0.12, pitchRange = { 0.9, 1.12 } } :: SoundDef,

	Collect = { id = "rbxassetid://8646410774", volume = 0.25, pitchRange = { 0.95, 1.15 } } :: SoundDef,

	-- The payoff of the entire economy. Worth spending the most time picking.
	Hatch = { id = "rbxassetid://7309105153", volume = 0.6 } :: SoundDef,

	Unlock = { id = "rbxassetid://127199850989931", volume = 0.7 } :: SoundDef,
}

-- Hatching plays one sound pitched by what came out, which is far cheaper than
-- five separate stings and reads instantly: the higher it rings, the better the
-- pull. Rarities missing from here just play at normal pitch.
SoundConfig.HatchPitch = {
	Starter = 1,
	Common = 0.85,
	Uncommon = 0.95,
	Rare = 1.05,
	Epic = 1.2,
	Legendary = 1.4,
}

function SoundConfig.get(name: string): SoundDef?
	return SoundConfig.Sounds[name]
end

return SoundConfig
