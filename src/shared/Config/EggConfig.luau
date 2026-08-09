--!strict
-- Eggs and their drop tables. Weights are relative, not percentages - they do
-- not need to add up to 100, which makes adding a pet to a table painless.
--
-- BasicEgg costs ~2 minutes of Area1 play. Expected damage per hatch is about
-- 15, so ~3x your starting pet: a visible jump without trivialising Area1.

local PetConfig = require(script.Parent.PetConfig)

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
		-- Descending, and matching PetConfig's rarity order. The two have to
		-- agree: the drop panel prints rarity and chance side by side, so a
		-- Legendary at 27% reads as a bug rather than as generosity.
		weights = {
			BonecaAmbalabu = 55, -- 55%  Common      5 dmg
			Madudung = 27, -- 27%  Uncommon   12 dmg
			Garamararam = 12, -- 12%  Rare       30 dmg
			BrrBrrPatapim = 5, -- 5%   Epic       75 dmg
			LiriliLarila = 1, -- 1%   Legendary 190 dmg
		},
	} :: Egg,
}

function EggConfig.get(eggName: string): Egg?
	return EggConfig.Eggs[eggName]
end

-- Weights turned into real percentages, strongest chance first. Lives here
-- rather than in the panel so the number a player is shown is derived from the
-- same table the roll uses, and cannot drift away from it.
function EggConfig.chances(egg: Egg): { { name: string, chance: number } }
	local total = 0
	for _, weight in egg.weights do
		total += weight
	end
	if total <= 0 then
		return {}
	end

	local rows: { { name: string, chance: number } } = {}
	for petName, weight in egg.weights do
		table.insert(rows, { name = petName, chance = weight / total * 100 })
	end

	table.sort(rows, function(a, b)
		if a.chance == b.chance then
			return a.name < b.name -- stable when two pets share a weight
		end
		return a.chance > b.chance
	end)

	return rows
end

-- Weighted random pick. Returns nil only if the table is empty.
--
-- `luck` biases the roll toward rarer pets by raising each weight to a power of
-- its rarity rank: a Common is rank 1 and untouched, a Legendary is rank 5 and
-- gets luck^4. Scaling by rank rather than flatly is what makes luck feel like
-- luck - it moves the tail without quietly making Commons rare too.
function EggConfig.roll(egg: Egg, luck: number?): string?
	local bias = luck or 1

	local weighted: { [string]: number } = {}
	local total = 0
	for petName, weight in egg.weights do
		local stats = PetConfig.get(petName)
		local rank = if stats then PetConfig.rarityRank(stats.rarity) else 1
		local adjusted = weight * bias ^ (rank - 1)
		weighted[petName] = adjusted
		total += adjusted
	end

	if total <= 0 then
		return nil
	end

	local pick = math.random() * total
	for petName, weight in weighted do
		pick -= weight
		if pick <= 0 then
			return petName
		end
	end

	return nil
end

return EggConfig
