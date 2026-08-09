--!strict
-- The things walking at your core.
--
-- Deliberately shaped like BreakableConfig: health, a coin reward, and a name.
-- An enemy is a breakable that walks, and keeping the two configs parallel is
-- what let EnemyService reuse BreakableService's damage, contribution and
-- payout logic rather than reinventing it.

export type EnemyStats = {
	displayName: string,
	model: string, -- model name under ServerStorage.Enemies
	health: number,
	moveSpeed: number, -- studs per second
	coinReward: number, -- split between whoever damaged it
	coreDamage: number, -- taken off the core if it arrives
	-- Enemies walk at the core and stop to fight whatever is in the way. That
	-- makes brainrots blockers rather than turrets: an enemy only reaches the
	-- core if nothing living is standing between it and there.
	damage: number, -- per hit, to a brainrot
	attackRange: number, -- studs at which it stops walking and swings
	attackCooldown: number, -- seconds between swings
	-- Empty falls back to Roblox's default walk for the rig type, which any
	-- place is allowed to play. Set this only for an animation you uploaded
	-- yourself; one bundled with a toolbox model belongs to its uploader and
	-- will fail to load.
	walkAnimation: string,
}

local EnemyConfig = {}

-- Tuned against a starter brainrot at 8 damage on a 0.5s cooldown, so ~16 DPS.
-- A Shambler takes about three seconds to kill and walks for roughly eight,
-- which is the window that makes one defender feel adequate and two feel
-- comfortable - the point where adding a brainrot has to be visibly worth it.
-- The key is identity and the `model` is a Studio asset name, kept apart for
-- the same reason PetConfig does it: renaming a toolbox model should be a
-- one-line edit here, not a hunt through the code.
EnemyConfig.Enemies = {
	Shambler = {
		displayName = "Shambler",
		model = "Drooling Zombie",
		health = 50,
		moveSpeed = 6,
		coinReward = 12,
		coreDamage = 5,
		-- 5 DPS against a 120 HP starter: one Shambler needs 24 seconds to down
		-- it, three need eight. Losing a brainrot should be the cost of being
		-- outnumbered, not of being looked at.
		damage = 6,
		attackRange = 7,
		attackCooldown = 1.2,
		walkAnimation = "",
	} :: EnemyStats,
}

EnemyConfig.Default = "Shambler"

-- A run is what a player starts, not something that happens to them: pressing
-- the button means the fight is something you chose. After that it does not
-- stop. Waves keep coming, each a little heavier, until every brainrot you
-- deployed is down - and how far you got is the score.
--
-- Endless with a fail state, rather than endless with none. A wave counter that
-- can only go up is a clock; one that can be lost is a run.
EnemyConfig.Wave = {
	baseSize = 4, -- enemies in wave 1
	sizeGrowth = 1, -- extra enemies per wave after that
	healthGrowth = 0.15, -- +15% enemy health per wave, compounding on wave 1
	spawnInterval = 1.6, -- seconds between each one entering
	intermission = 5, -- breathing room between a wave clearing and the next
}

-- Enemies in wave `n`, and what their health is multiplied by.
function EnemyConfig.waveSize(wave: number): number
	return EnemyConfig.Wave.baseSize + math.floor((wave - 1) * EnemyConfig.Wave.sizeGrowth)
end

function EnemyConfig.waveHealthScale(wave: number): number
	return 1 + (wave - 1) * EnemyConfig.Wave.healthGrowth
end

function EnemyConfig.get(enemyName: string): EnemyStats?
	return EnemyConfig.Enemies[enemyName]
end

return EnemyConfig
