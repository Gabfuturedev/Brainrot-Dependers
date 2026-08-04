--!strict
-- Every pet in the game. Pets only override what makes them different; BASE
-- fills in the rest, so adding a pet is three lines instead of ten.
--
-- Damage tuning (see EggConfig for how often each is rolled):
--   Common 5 -> 10 DPS -> ~55 coins/min in Area1
--   each tier is roughly 2.5x the last, so a Legendary is ~18x a Common

export type PetStats = {
	displayName: string,
	model: string, -- model name under ServerStorage.Pets
	rarity: string,
	damage: number,
	attackCooldown: number, -- seconds between hits
	attackRange: number, -- studs from target before it can hit
	followDistance: number, -- radius of the orbit around the owner when idle
	moveSpeed: number, -- studs per second
	searchRadius: number, -- max distance from the owner a clicked target may be
	-- Optional. Omit to use Roblox's default R6/R15 animations for the rig.
	animations: { idle: string, walk: string }?,
}

local BASE = {
	-- until you build more rigs, every pet uses the petTest model
	model = "petTest",
	rarity = "Common",
	damage = 500,
	attackCooldown = 0.5,
	attackRange = 8,
	followDistance = 7,
	moveSpeed = 26,
	searchRadius = 60,
}

local OVERRIDES: { [string]: { [string]: any } } = {
	petTest = { displayName = "Test Pet", rarity = "Common", damage = 5 },
	Rocky = { displayName = "Rocky", rarity = "Uncommon", damage = 12, moveSpeed = 27 },
	Blaze = { displayName = "Blaze", rarity = "Rare", damage = 30, moveSpeed = 29 },
	Zephyr = {
		displayName = "Zephyr",
		rarity = "Legendary",
		damage = 90,
		moveSpeed = 32,
		attackCooldown = 0.4,
	},
}

local PetConfig = {}

PetConfig.DefaultPet = "petTest" -- granted free so a new player always has one

PetConfig.RarityColors = {
	Common = Color3.fromRGB(200, 200, 200),
	Uncommon = Color3.fromRGB(120, 220, 120),
	Rare = Color3.fromRGB(100, 170, 255),
	Legendary = Color3.fromRGB(255, 190, 60),
}

local cache: { [string]: PetStats } = {}

function PetConfig.get(petName: string): PetStats?
	if cache[petName] then
		return cache[petName]
	end

	local overrides = OVERRIDES[petName]
	if not overrides then
		return nil
	end

	local stats = {}
	for key, value in BASE do
		stats[key] = value
	end
	for key, value in overrides do
		stats[key] = value
	end

	cache[petName] = stats :: any
	return cache[petName]
end

function PetConfig.exists(petName: string): boolean
	return OVERRIDES[petName] ~= nil
end

return PetConfig
