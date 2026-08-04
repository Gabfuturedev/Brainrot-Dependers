--!strict
-- Eggs and their drop tables. Weights are relative, not percentages - they do
-- not need to add up to 100, which makes adding a pet to a table painless.
--
-- BasicEgg costs ~2 minutes of Area1 play. Expected damage per hatch is about
-- 13, so ~2.5x your starting pet: a visible jump without trivialising Area1.

export type Egg = {
	displayName: string,
	cost: number,
	weights: { [string]: number }, -- petName -> relative chance
}

local EggConfig = {}

EggConfig.Eggs = {
	BasicEgg = {
		displayName = "Basic Egg",
		cost = 100,
		weights = {
			petTest = 60, -- 60%
			Rocky = 27, -- 27%
			Blaze = 11, -- 11%
			Zephyr = 2, -- 2%
		},
	} :: Egg,
}

function EggConfig.get(eggName: string): Egg?
	return EggConfig.Eggs[eggName]
end

-- Weighted random pick. Returns nil only if the table is empty.
function EggConfig.roll(egg: Egg): string?
	local total = 0
	for _, weight in egg.weights do
		total += weight
	end
	if total <= 0 then
		return nil
	end

	local pick = math.random() * total
	for petName, weight in egg.weights do
		pick -= weight
		if pick <= 0 then
			return petName
		end
	end

	return nil
end

return EggConfig
