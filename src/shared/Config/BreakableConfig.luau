--!strict
-- Stats for breakable parts, keyed by the area folder they live in.
-- Anything not listed falls back to Default.

export type BreakableStats = {
	health: number,
	coinReward: number,
	respawnTime: number,
}

local BreakableConfig = {}

BreakableConfig.Default = {
	health = 100,
	coinReward = 10,
	respawnTime = 3,
} :: BreakableStats

BreakableConfig.Areas = {
	Area1 = {
		health = 100,
		coinReward = 10,
		respawnTime = 3,
	} :: BreakableStats,
	-- The number that matters is coins per damage, not per break:
	--   Area1 = 10/100  = 0.10
	--   Area2 = 150/1000 = 0.15  (50% better)
	-- 10x the health also means a starter pet needs ~100s per break here, so
	-- it only feels good once eggs have given you something stronger.
	Area2 = {
		health = 1_000,
		coinReward = 150,
		respawnTime = 4,
	} :: BreakableStats,
}

function BreakableConfig.forArea(areaName: string): BreakableStats
	return BreakableConfig.Areas[areaName] or BreakableConfig.Default
end

return BreakableConfig
