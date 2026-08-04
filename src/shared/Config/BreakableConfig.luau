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
}

function BreakableConfig.forArea(areaName: string): BreakableStats
	return BreakableConfig.Areas[areaName] or BreakableConfig.Default
end

return BreakableConfig
