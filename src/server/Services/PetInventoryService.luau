--!strict
-- Owns which pets a player has and which are equipped, plus egg hatching.
-- All state lives in the saved profile - this service is just the rules.
--
-- Hatching is driven by ProximityPrompts the server creates on the eggs in
-- Workspace.Eggs, so there is no client remote to exploit: the player can only
-- ask by standing next to a real egg. Equipping does need remotes, so every
-- handler re-validates the petId against the player's own profile.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggConfig = require(Shared.Config.EggConfig)
local PetConfig = require(Shared.Config.PetConfig)
local Remotes = require(Shared.Remotes)

local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)

local MAX_EQUIPPED = 3
-- Hard ceiling on the collection. Without one, ownedPets grows for as long as a
-- player keeps hatching: the profile gets slower to save every session and the
-- inventory panel turns into a list nobody can use. Hitting the cap refuses the
-- hatch rather than auto-deleting, so nothing disappears without being asked.
local MAX_OWNED = 200
local PROMPT_DISTANCE = 12

export type Entry = {
	id: string,
	name: string,
	displayName: string,
	rarity: string,
	damage: number,
	equipped: boolean,
}

local PetInventoryService = {}

local equippedChanged = Instance.new("BindableEvent")
-- Fires (player) whenever the equipped list changes, so PetService can respawn.
PetInventoryService.EquippedChanged = equippedChanged.Event

local chooseStarterRemote: RemoteEvent
local hatchResult: RemoteEvent
local inventoryUpdated: RemoteEvent

PetInventoryService.MaxEquipped = MAX_EQUIPPED
PetInventoryService.MaxOwned = MAX_OWNED

local function isEquipped(data: any, petId: string): boolean
	return table.find(data.equipped, petId) ~= nil
end

-- ownedPets is keyed by id, so there is no # to read.
--
-- Only pets that still resolve in PetConfig count. A pet whose name was dropped
-- from the config is invisible in the panel and can't be deleted by id, so
-- charging storage for it would let a config edit permanently wall someone off
-- from hatching. Note this deliberately does NOT prune them: a typo in
-- PetConfig would then wipe collections, where ignoring them is recoverable the
-- moment the name comes back.
local function countOwned(data: any): number
	local count = 0
	for _, petName in data.ownedPets do
		if PetConfig.exists(petName) then
			count += 1
		end
	end
	return count
end

-- Pet config names of everything currently equipped, in slot order.
function PetInventoryService.getEquippedPetNames(player: Player): { string }
	local data = DataService.getData(player)
	if not data then
		return {}
	end

	local names = {}
	for _, petId in data.equipped do
		local petName = data.ownedPets[petId]
		-- skip ids that no longer resolve, e.g. a pet removed from the config
		if petName and PetConfig.exists(petName) then
			table.insert(names, petName)
		end
	end
	return names
end

function PetInventoryService.getInventory(player: Player): { Entry }
	local data = DataService.getData(player)
	if not data then
		return {}
	end

	local entries: { Entry } = {}
	for petId, petName in data.ownedPets do
		local stats = PetConfig.get(petName)
		if stats then
			table.insert(entries, {
				id = petId,
				name = petName,
				displayName = stats.displayName,
				rarity = stats.rarity,
				damage = stats.damage,
				equipped = isEquipped(data, petId),
			})
		end
	end

	-- strongest first, so the list is useful without any sorting controls
	table.sort(entries, function(a, b)
		if a.damage == b.damage then
			return a.id < b.id -- stable order for identical pets
		end
		return a.damage > b.damage
	end)

	return entries
end

local function pushInventory(player: Player)
	inventoryUpdated:FireClient(player, PetInventoryService.getInventory(player), MAX_EQUIPPED, MAX_OWNED)
end

-- Returns nil if the pet doesn't exist or the player is at MAX_OWNED. Callers
-- that charged for this should check capacity first and report it themselves.
function PetInventoryService.grantPet(player: Player, petName: string): string?
	local data = DataService.getData(player)
	if not data or not PetConfig.exists(petName) then
		return nil
	end
	if countOwned(data) >= MAX_OWNED then
		return nil
	end

	local petId = HttpService:GenerateGUID(false)
	data.ownedPets[petId] = petName

	if #data.equipped < MAX_EQUIPPED then
		table.insert(data.equipped, petId)
		equippedChanged:Fire(player)
	end

	pushInventory(player)
	return petId
end

-- petId/shouldEquip come straight off a remote, so they are validated below
local function setEquipped(player: Player, petId: any, shouldEquip: any)
	local data = DataService.getData(player)
	if not data or typeof(petId) ~= "string" then
		return
	end
	if not data.ownedPets[petId] then
		return -- not theirs, or doesn't exist
	end

	local index = table.find(data.equipped, petId)

	if shouldEquip == true then
		if index then
			return -- already equipped
		end
		if #data.equipped >= MAX_EQUIPPED then
			return -- full; the client greys these out, but never trust that
		end
		table.insert(data.equipped, petId)
	else
		if not index then
			return
		end
		table.remove(data.equipped, index)
	end

	equippedChanged:Fire(player)
	pushInventory(player)
end

local function deletePet(player: Player, petId: any)
	local data = DataService.getData(player)
	if not data or typeof(petId) ~= "string" then
		return
	end
	if not data.ownedPets[petId] then
		return
	end

	-- never let someone strand themselves with no pets at all
	if countOwned(data) <= 1 then
		return
	end

	local index = table.find(data.equipped, petId)
	if index then
		table.remove(data.equipped, index)
		equippedChanged:Fire(player)
	end

	data.ownedPets[petId] = nil
	pushInventory(player)
end

-- Clears out every unequipped pet of `rarity`, or of every rarity when nil.
-- Equipped pets are deliberately never touched: they are the ones the player
-- chose, and skipping them means PetService needs no rebuild afterwards.
--
-- The same floor as deletePet applies. Candidates go weakest-first so that if
-- the floor does stop us part-way, what survives is the best of the batch
-- rather than whichever id the hash happened to yield last.
local function bulkDelete(player: Player, rarity: any)
	if rarity ~= nil and typeof(rarity) ~= "string" then
		return
	end

	local data = DataService.getData(player)
	if not data then
		return
	end

	-- `counts` mirrors countOwned: pets missing from PetConfig don't occupy
	-- storage, so clearing one must not move us toward the floor either. The
	-- unfiltered sweep takes them anyway, since it is the only thing that can.
	local candidates: { { id: string, damage: number, counts: boolean } } = {}
	for petId, petName in data.ownedPets do
		if isEquipped(data, petId) then
			continue
		end

		local stats = PetConfig.get(petName)
		if not stats then
			if rarity == nil then
				table.insert(candidates, { id = petId, damage = -1, counts = false })
			end
		elseif rarity == nil or stats.rarity == rarity then
			table.insert(candidates, { id = petId, damage = stats.damage, counts = true })
		end
	end

	table.sort(candidates, function(a, b)
		if a.damage == b.damage then
			return a.id < b.id
		end
		return a.damage < b.damage
	end)

	local remaining = countOwned(data)
	local deleted = 0
	for _, candidate in candidates do
		if candidate.counts then
			if remaining <= 1 then
				break
			end
			remaining -= 1
		end

		data.ownedPets[candidate.id] = nil
		deleted += 1
	end

	-- nothing matched: say nothing rather than echoing an unchanged inventory,
	-- which also keeps a spammed remote from generating traffic
	if deleted > 0 then
		pushInventory(player)
	end
end

local function hatch(player: Player, eggName: string)
	local egg = EggConfig.get(eggName)
	if not egg then
		warn(`[PetInventoryService] no config for egg '{eggName}'`)
		return
	end

	local data = DataService.getData(player)
	if not data then
		return
	end

	-- capacity before coins: being full is the harder blocker of the two, and
	-- checking here means we never charge for a pet grantPet would refuse
	if countOwned(data) >= MAX_OWNED then
		hatchResult:FireClient(player, nil, `Pet storage full ({MAX_OWNED}) - delete some`)
		return
	end

	if data.coins < egg.cost then
		hatchResult:FireClient(player, nil, `Need {egg.cost - data.coins} more coins`)
		return
	end

	local petName = EggConfig.roll(egg)
	if not petName or not PetConfig.exists(petName) then
		warn(`[PetInventoryService] {eggName} rolled an invalid pet: {petName}`)
		return
	end

	-- roll first, charge second: never take coins for a hatch we can't deliver
	if not CurrencyService.spendCoins(player, egg.cost) then
		return
	end

	PetInventoryService.grantPet(player, petName)

	local stats = PetConfig.get(petName)
	hatchResult:FireClient(player, petName, stats and stats.rarity or "Common")
end

-- petName arrives on a remote, so it is checked against the starter list rather
-- than trusted - otherwise this is a free hatch of anything in PetConfig.
local function chooseStarter(player: Player, petName: any)
	if typeof(petName) ~= "string" or not PetConfig.isStarter(petName) then
		return
	end

	local data = DataService.getData(player)
	if not data or data.starterChosen then
		return -- one time only, however many times the remote is fired
	end

	-- flag only once the pet is actually theirs: marking it first would strand
	-- a player with no pet and no way to be offered one again
	if PetInventoryService.grantPet(player, petName) then
		data.starterChosen = true
	end
end

local function offerStarter(player: Player)
	local data = DataService.getData(player)
	if data and not data.starterChosen then
		chooseStarterRemote:FireClient(player, PetConfig.Starters)
	end
end

local function onProfileLoaded(player: Player)
	local data = DataService.getData(player)
	if not data then
		return
	end

	if not data.starterChosen then
		if next(data.ownedPets) == nil then
			-- brand new: let them pick one rather than handing them one
			offerStarter(player)
			return
		end
		-- a profile from before starters existed, so there is nothing to
		-- choose - they already have pets
		data.starterChosen = true
	end

	-- returning player: their equipped list is already in the profile
	equippedChanged:Fire(player)
	pushInventory(player)
end

local function setupEgg(model: Instance, eggName: string)
	local egg = EggConfig.get(eggName)
	if not egg then
		warn(`[PetInventoryService] Workspace.Eggs.{eggName} has no matching config`)
		return
	end

	-- the prompt needs a part to hang off; a Model can hold it on its root
	local host: BasePart? = if model:IsA("BasePart")
		then model
		else (model :: Model).PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)

	if not host then
		warn(`[PetInventoryService] Workspace.Eggs.{eggName} has no BasePart to attach a prompt to`)
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = `Hatch ({egg.cost} coins)`
	prompt.ObjectText = egg.displayName
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = host

	prompt.Triggered:Connect(function(player)
		hatch(player, eggName)
	end)
end

function PetInventoryService.start()
	chooseStarterRemote = Remotes.get("ChooseStarter")
	hatchResult = Remotes.get("HatchResult")
	inventoryUpdated = Remotes.get("InventoryUpdated")

	Remotes.get("RequestStarter").OnServerEvent:Connect(function(player, petName)
		chooseStarter(player, petName)
	end)

	Remotes.get("RequestEquip").OnServerEvent:Connect(function(player, petId, shouldEquip)
		setEquipped(player, petId, shouldEquip)
	end)
	Remotes.get("RequestDeletePet").OnServerEvent:Connect(function(player, petId)
		deletePet(player, petId)
	end)
	Remotes.get("RequestBulkDelete").OnServerEvent:Connect(function(player, rarity)
		bulkDelete(player, rarity)
	end)

	DataService.ProfileLoaded:Connect(onProfileLoaded)

	-- The profile can finish loading before the client has connected its
	-- handler, in which case the offer above lands on nobody. Re-offering each
	-- time a character spawns costs nothing and self-heals that race, and it is
	-- a no-op the moment they have picked.
	local function bind(player: Player)
		player.CharacterAdded:Connect(function()
			offerStarter(player)
		end)
	end

	-- in Studio the local player can already exist by the time this runs, so
	-- PlayerAdded alone would never bind them
	for _, player in Players:GetPlayers() do
		bind(player)
	end
	Players.PlayerAdded:Connect(bind)

	Players.PlayerRemoving:Connect(function(player)
		equippedChanged:Fire(player) -- lets PetService clean up
	end)

	local eggs = Workspace:FindFirstChild("Eggs")
	if not eggs then
		warn("[PetInventoryService] no Workspace.Eggs folder - nothing to hatch from")
		return
	end

	for _, model in eggs:GetChildren() do
		setupEgg(model, model.Name)
	end
	eggs.ChildAdded:Connect(function(model)
		setupEgg(model, model.Name)
	end)
end

return PetInventoryService
