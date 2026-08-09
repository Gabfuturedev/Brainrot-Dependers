--!strict
-- Upgrades, one per sign standing on the plot.
--
-- Levelled rather than a tree: a sign you walk up to and press E on wants a
-- single escalating price, not a graph. The tree was the wrong shape for this
-- interaction - a board of nodes only earns its complexity if choosing a PATH
-- matters, and here every plot has every sign standing on it anyway.
--
-- Two kinds:
--   multiplier - value is 1 + level * perLevel. Coins, luck, damage.
--   flat       - value is level * perLevel. Slots, extra enemies.
--
-- Cost grows geometrically, so the tenth level of a cheap upgrade competes with
-- the first of an expensive one and there is always a decision rather than an
-- obvious next purchase.

export type Upgrade = {
	displayName: string,
	description: string, -- one line, shown on the sign
	kind: "multiplier" | "flat",
	maxLevel: number,
	baseCost: number,
	costGrowth: number, -- cost of the next level = baseCost * costGrowth^level
	perLevel: number,
	suffix: string, -- how a level's worth is written on the sign
}

local SkillConfig = {}

SkillConfig.Upgrades = {
	Ferocity = {
		displayName = "Ferocity",
		description = "Brainrots hit harder",
		kind = "multiplier",
		maxLevel = 25,
		baseCost = 150,
		costGrowth = 1.32,
		perLevel = 0.12,
		suffix = "% damage",
	} :: Upgrade,

	Vigour = {
		displayName = "Vigour",
		description = "Brainrots last longer",
		kind = "multiplier",
		maxLevel = 25,
		baseCost = 150,
		costGrowth = 1.32,
		perLevel = 0.15,
		suffix = "% health",
	} :: Upgrade,

	Fortune = {
		displayName = "Fortune",
		description = "Enemies drop more coins",
		kind = "multiplier",
		maxLevel = 25,
		baseCost = 200,
		costGrowth = 1.3,
		perLevel = 0.1,
		suffix = "% coins",
	} :: Upgrade,

	Luck = {
		displayName = "Luck",
		description = "Rarer brainrots hatch more often",
		kind = "multiplier",
		maxLevel = 20,
		baseCost = 400,
		costGrowth = 1.38,
		perLevel = 0.08,
		suffix = "% luck",
	} :: Upgrade,

	-- The expensive one. Another brainrot beats any percentage on the plot, so
	-- it has to cost like it or nothing else is ever worth buying.
	Squad = {
		displayName = "Squad",
		description = "Deploy another brainrot",
		kind = "flat",
		maxLevel = 5,
		baseCost = 3000,
		costGrowth = 3.4,
		perLevel = 1,
		suffix = " slots",
	} :: Upgrade,

	Magnetism = {
		displayName = "Magnetism",
		description = "Coins fly to you from further away",
		kind = "flat",
		maxLevel = 15,
		baseCost = 150,
		costGrowth = 1.26,
		perLevel = 3,
		suffix = " stud pull",
	} :: Upgrade,

	-- Risk sold as an upgrade: more enemies is more coins AND a harder wave.
	-- The only thing here a player can regret buying, which is what makes it
	-- interesting rather than just another number going up.
	Horde = {
		displayName = "Horde",
		description = "More enemies per wave, and more coins",
		kind = "flat",
		maxLevel = 10,
		baseCost = 800,
		costGrowth = 1.6,
		perLevel = 1,
		suffix = " enemies",
	} :: Upgrade,
}

function SkillConfig.get(upgradeId: string): Upgrade?
	return SkillConfig.Upgrades[upgradeId]
end

-- What the upgrade is worth at a level. The identity at level 0 is what lets a
-- consumer multiply or add unconditionally, without asking whether the player
-- has bought anything.
function SkillConfig.valueAt(upgrade: Upgrade, level: number): number
	if upgrade.kind == "multiplier" then
		return 1 + level * upgrade.perLevel
	end
	return level * upgrade.perLevel
end

function SkillConfig.identity(upgrade: Upgrade): number
	return if upgrade.kind == "multiplier" then 1 else 0
end

-- Cost of going from `level` to the next, or nil at maximum.
function SkillConfig.costOf(upgrade: Upgrade, level: number): number?
	if level >= upgrade.maxLevel then
		return nil
	end
	return math.floor(upgrade.baseCost * upgrade.costGrowth ^ level)
end

-- How a level reads on the sign: "+36% coins", "+2 slots".
function SkillConfig.describeLevel(upgrade: Upgrade, level: number): string
	if upgrade.kind == "multiplier" then
		return `+{math.floor(level * upgrade.perLevel * 100 + 0.5)}{upgrade.suffix}`
	end
	return `+{level * upgrade.perLevel}{upgrade.suffix}`
end

return SkillConfig
