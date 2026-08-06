--!strict
-- Every pet in the game. Pets only override what makes them different; BASE
-- fills in the rest, so adding a pet is three lines instead of ten.
--
-- Damage tuning (see EggConfig for how often each is rolled):
--   Common 5 -> 10 DPS -> ~55 coins/min in Area1
--   each tier is roughly 2.5x the last, so a Legendary is ~38x a Common

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
	-- Hover and bob instead of walking. The bob is what sells a pet as alive,
	-- so a floating pet needs no rig animation at all - which also sidesteps
	-- Roblox only letting a place play animation assets it owns. Set false for
	-- a pet that has a real walk cycle you uploaded yourself.
	float: boolean,
	hoverHeight: number, -- studs of clearance under a floating pet
	-- Effect names under ServerStorage.VFX, one picked at random per hit. Three
	-- variants is enough that a pet working on the same rock for a minute stops
	-- looking like a looping GIF. Set to {} for a pet that hits without one.
	attackVfx: { string },
	-- Optional, and unnecessary for a floating pet. Set only for a rig with
	-- real tracks; a walker with none falls back to Roblox's R6/R15 defaults.
	animations: { idle: string, walk: string }?,
}

local BASE = {
	-- only reached by a pet that names no model of its own; PetService warns
	-- when it has to fall back here rather than substituting in silence
	model = "petTest",
	rarity = "Common",
	damage = 500,
	attackCooldown = 0.5,
	attackRange = 8,
	followDistance = 7,
	moveSpeed = 26,
	searchRadius = 60,
	float = true,
	hoverHeight = 1.5,
	-- Off: an impact effect twice a second per pet, three pets deep, is visual
	-- noise on top of the lunge that already reads the hit. VfxService still
	-- works - put names back here for a boss pet that has earned one.
	attackVfx = {},
}

-- The key is save-data identity: it is written into profiles and into
-- EggConfig's weight tables, so it must never change once anyone has hatched
-- one. `model` is a Studio asset name and is free to be renamed. Keeping the
-- two apart is what makes renaming a model a one-line edit here instead of a
-- data migration - which is also why the keys carry no spaces even though the
-- models do.
local OVERRIDES: { [string]: { [string]: any } } = {
	BonecaAmbalabu = {
		displayName = "Boneca Ambalabu",
		model = "Boneca Ambalabu",
		rarity = "Common",
		damage = 5,
	},
	Madudung = {
		displayName = "Madudung",
		model = "Madudung",
		rarity = "Uncommon",
		damage = 12,
		moveSpeed = 27,
	},
	Garamararam = {
		displayName = "Garamararam",
		model = "Garamararam",
		rarity = "Rare",
		damage = 30,
		moveSpeed = 29,
	},
	BrrBrrPatapim = {
		displayName = "Brr Brr Patapim",
		model = "Brr Brr Patapim",
		rarity = "Epic",
		damage = 75,
		moveSpeed = 30,
		attackCooldown = 0.45,
	},
	LiriliLarila = {
		displayName = "Lirili Larila",
		model = "Lirili Larila",
		rarity = "Legendary",
		damage = 190,
		moveSpeed = 32,
		attackCooldown = 0.4,
	},

	-- Starters. Offered as a one-time choice on first join and obtainable no
	-- other way, so they are deliberately identical on damage and cooldown -
	-- the pick should be about which brainrot you want following you around,
	-- not about which one turns out to have been the right answer 20 hatches
	-- later. Only the way they move differs.
	BallerinaCappuccina = {
		displayName = "Ballerina Cappuccina",
		model = "Ballerina Cappuccina",
		rarity = "Starter",
		damage = 8,
		moveSpeed = 30, -- keeps up best
	},
	TralaleroTralala = {
		displayName = "Tralalero Tralala",
		model = "Tralalero Tralala",
		rarity = "Starter",
		damage = 8,
		attackRange = 11, -- reaches furthest
	},
	TungSahur = {
		displayName = "Tung Sahur",
		model = "Tung Sahur",
		rarity = "Starter",
		damage = 8,
		followDistance = 5, -- sticks closest
	},

	-- In no egg, so unobtainable: this is the rig PetService falls back to when
	-- a pet's model is missing, and a handy thing to test against. Keep a model
	-- of this name in ServerStorage.Pets.
	petTest = { displayName = "Test Pet", rarity = "Common", damage = 5 },
}

local PetConfig = {}

-- The rig PetService falls back to when a pet's model is missing. Nothing is
-- granted from it any more - new players choose a starter instead - but its
-- model still has to exist, since it is the last resort when every other one
-- is absent.
PetConfig.DefaultPet = "BonecaAmbalabu"

-- Offered on first join, in this order. Adding a fourth is one line here plus a
-- model in ServerStorage.Pets.
PetConfig.Starters = { "BallerinaCappuccina", "TralaleroTralala", "TungSahur" }

PetConfig.RarityColors = {
	Starter = Color3.fromRGB(90, 220, 210),
	Common = Color3.fromRGB(200, 200, 200),
	Uncommon = Color3.fromRGB(120, 220, 120),
	Rare = Color3.fromRGB(100, 170, 255),
	Epic = Color3.fromRGB(180, 120, 255),
	Legendary = Color3.fromRGB(255, 190, 60),
}

function PetConfig.isStarter(petName: string): boolean
	return table.find(PetConfig.Starters, petName) ~= nil
end

local cache: { [string]: PetStats } = {}

function PetConfig.get(petName: string): PetStats?
	if cache[petName] then
		return cache[petName]
	end

	local overrides = OVERRIDES[petName]
	if not overrides then
		return nil
	end

	local stats = table.clone(BASE)
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
