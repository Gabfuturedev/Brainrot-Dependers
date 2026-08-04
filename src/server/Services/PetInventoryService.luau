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

local hatchResult: RemoteEvent
local inventoryUpdated: RemoteEvent

PetInventoryService.MaxEquipped = MAX_EQUIPPED

local function isEquipped(data: any, petId: string): boolean
	return table.find(data.equipped, petId) ~= nil
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
	inventoryUpdated:FireClient(player, PetInventoryService.getInventory(player), MAX_EQUIPPED)
end

function PetInventoryService.grantPet(player: Player, petName: string): string?
	local data = DataService.getData(player)
	if not data or not PetConfig.exists(petName) then
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
	local owned = 0
	for _ in data.ownedPets do
		owned += 1
	end
	if owned <= 1 then
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

-- Give brand new players their starter pet so the game is playable at once.
local function onProfileLoaded(player: Player)
	local data = DataService.getData(player)
	if not data then
		return
	end

	if next(data.ownedPets) == nil then
		PetInventoryService.grantPet(player, PetConfig.DefaultPet)
	else
		-- returning player: their equipped list is already in the profile
		equippedChanged:Fire(player)
		pushInventory(player)
	end
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
	hatchResult = Remotes.get("HatchResult")
	inventoryUpdated = Remotes.get("InventoryUpdated")

	Remotes.get("RequestEquip").OnServerEvent:Connect(function(player, petId, shouldEquip)
		setEquipped(player, petId, shouldEquip)
	end)
	Remotes.get("RequestDeletePet").OnServerEvent:Connect(function(player, petId)
		deletePet(player, petId)
	end)

	DataService.ProfileLoaded:Connect(onProfileLoaded)
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
