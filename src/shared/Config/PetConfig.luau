--!strict
-- Stats for every pet in the game, keyed by the model name in ServerStorage.Pets

export type PetStats = {
	displayName: string,
	damage: number,
	attackCooldown: number, -- seconds between hits
	attackRange: number, -- studs from target before it can hit
	followDistance: number, -- studs behind the owner when idle
	moveSpeed: number, -- studs per second
	searchRadius: number, -- max distance from the owner a clicked target may be
	-- Optional. Omit to use Roblox's default R6/R15 animations for the rig.
	animations: { idle: string, walk: string }?,
}

local PetConfig = {}

PetConfig.Pets = {
	petTest = {
		displayName = "Test Pet",
		damage = 5,
		attackCooldown = 0.5,
		attackRange = 8,
		followDistance = 6,
		moveSpeed = 26,
		searchRadius = 60,
	} :: PetStats,
}

PetConfig.DefaultPet = "petTest"

function PetConfig.get(petName: string): PetStats?
	return PetConfig.Pets[petName]
end

return PetConfig
