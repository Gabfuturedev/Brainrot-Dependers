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

-- A wave is what a player starts, not something that happens to them. Enemies
-- arriving on a timer whether you are ready or not means never being ready;
-- pressing a button means the fight is something you chose to watch.
EnemyConfig.Wave = {
	size = 6, -- enemies in a wave
	spawnInterval = 1.6, -- seconds between each one entering
}

function EnemyConfig.get(enemyName: string): EnemyStats?
	return EnemyConfig.Enemies[enemyName]
end

return EnemyConfig
