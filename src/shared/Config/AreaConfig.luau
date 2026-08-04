--!strict
-- Which areas exist and what they cost to unlock. Breakable stats for each
-- area live in BreakableConfig.
--
-- Area2 costs ~10 Basic Eggs of play. Its breakables pay 50% more per point of
-- damage dealt, but have 10x the health - so it rewards stronger pets without
-- ever being strictly worse, and the long breaks are what make eggs feel
-- necessary rather than optional.

export type Area = {
	displayName: string,
	cost: number, -- 0 means unlocked from the start
	order: number,
}

local AreaConfig = {}

AreaConfig.Areas = {
	Area1 = { displayName = "Green Fields", cost = 0, order = 1 } :: Area,
	Area2 = { displayName = "Stone Quarry", cost = 1000, order = 2 } :: Area,
}

function AreaConfig.get(areaName: string): Area?
	return AreaConfig.Areas[areaName]
end

return AreaConfig
