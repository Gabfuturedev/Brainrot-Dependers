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
local SkillService = require(script.Parent.SkillService)

-- Base deployment slots. The Squad skill adds to this, so nothing outside
-- maxEquipped() should ever read the constant directly.
local MAX_EQUIPPED = 3
-- Hard ceiling on the collection. Without one, ownedPets grows for as long as a
-- player keeps hatching: the profile gets slower to save every session and the
-- inventory panel turns into a list nobody can use. Hitting the cap refuses the
-- hatch rather than auto-deleting, so nothing disappears without being asked.
local MAX_OWNED = 200
local PROMPT_DISTANCE = 12
local HATCH_RANGE_SLACK = 6 -- studs of grace over the prompt's own range
-- The client locks its buttons for the length of the reveal, but that is UX and
-- an exploiter has no such lock. This is deliberately much shorter than the
-- animation: it exists to stop a script draining a balance in one frame, not to
-- pace a legitimate player, who is already paced by their own UI.
local HATCH_COOLDOWN = 0.3
-- The batch sizes the panel offers. Anything not in here is refused, so the
-- remote cannot be talked into a thousand-pull.
local HATCH_COUNTS = { 1, 3, 10 }

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

-- eggName -> the part its prompt hangs off, so a hatch request can be checked
-- against where the player actually is
local eggHosts: { [string]: BasePart } = {}
local lastHatchAt: { [Player]: number } = {}

-- How many brainrots this player may deploy, base plus whatever Squad adds.
function PetInventoryService.maxEquipped(player: Player): number
	return MAX_EQUIPPED + math.floor(SkillService.value(player, "Squad"))
end
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

-- Ids as well as names, in slot order. The id matters because a brainrot downed
-- during a wave has to stay down until it ends, and "which one" cannot be
-- answered by a name when three of them are the same pet.
function PetInventoryService.getEquippedPets(player: Player): { { id: string, name: string } }
	local data = DataService.getData(player)
	if not data then
		return {}
	end

	local equipped: { { id: string, name: string } } = {}
	for _, petId in data.equipped do
		local petName = data.ownedPets[petId]
		-- skip ids that no longer resolve, e.g. a pet removed from the config
		if petName and PetConfig.exists(petName) then
			table.insert(equipped, { id = petId, name = petName })
		end
	end
	return equipped
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
	local data = DataService.getData(player)
	inventoryUpdated:FireClient(
		player,
		PetInventoryService.getInventory(player),
		PetInventoryService.maxEquipped(player),
		MAX_OWNED,
		if data then data.discovered else {}
	)
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
	data.discovered[petName] = true

	if #data.equipped < PetInventoryService.maxEquipped(player) then
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
		if #data.equipped >= PetInventoryService.maxEquipped(player) then
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

-- Swaps the equipped set to the strongest pets owned. Ties break on id so the
-- result is stable, which matters because an unstable order would look like a
-- different answer every press.
local function equipBest(player: Player)
	local data = DataService.getData(player)
	if not data then
		return
	end

	local ranked: { { id: string, damage: number } } = {}
	for petId, petName in data.ownedPets do
		local stats = PetConfig.get(petName)
		if stats then
			table.insert(ranked, { id = petId, damage = stats.damage })
		end
	end

	table.sort(ranked, function(a, b)
		if a.damage == b.damage then
			return a.id < b.id
		end
		return a.damage > b.damage
	end)

	local chosen: { string } = {}
	for index = 1, math.min(PetInventoryService.maxEquipped(player), #ranked) do
		table.insert(chosen, ranked[index].id)
	end

	-- Bail when nothing would change. equippedChanged makes PetService despawn
	-- and rebuild the whole group, so a repeated press would visibly strobe the
	-- player's pets for no reason.
	if #chosen == #data.equipped then
		local identical = true
		for index, petId in chosen do
			if data.equipped[index] ~= petId then
				identical = false
				break
			end
		end
		if identical then
			return
		end
	end

	data.equipped = chosen
	equippedChanged:Fire(player)
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

-- Hatching used to be prompt-only, with no remote at all, so a client could
-- never ask for a pet it had not walked to. Multi-hatch needs buttons and so
-- needs a remote, and this is what keeps the original guarantee: the server
-- checks you really are stood at the egg you claim to be at.
local function isNearEgg(player: Player, eggName: string): boolean
	local host = eggHosts[eggName]
	if not host or not host.Parent then
		return false
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end

	-- a little slack over the prompt's own range, so a hatch is not rejected
	-- for a step taken between pressing the button and the remote arriving
	return (root.Position - host.Position).Magnitude <= PROMPT_DISTANCE + HATCH_RANGE_SLACK
end

-- Hatches up to `count` pets. Partial success is deliberate: refusing a ten-pull
-- outright because the player can afford nine, or has room for nine, feels far
-- worse than delivering nine and saying so.
local function hatch(player: Player, eggName: string, count: number)
	local egg = EggConfig.get(eggName)
	if not egg then
		warn(`[PetInventoryService] no config for egg '{eggName}'`)
		return
	end

	local data = DataService.getData(player)
	if not data then
		return
	end

	local room = MAX_OWNED - countOwned(data)
	if room <= 0 then
		hatchResult:FireClient(player, nil, `Pet storage full ({MAX_OWNED}) - delete some`)
		return
	end

	local affordable = math.floor(data.coins / egg.cost)
	if affordable <= 0 then
		hatchResult:FireClient(player, nil, `Need {egg.cost - data.coins} more coins`)
		return
	end

	local toHatch = math.min(count, room, affordable)
	local results: { { name: string, rarity: string } } = {}

	for _ = 1, toHatch do
		local petName = EggConfig.roll(egg, SkillService.value(player, "Luck"))
		local stats = if petName then PetConfig.get(petName) else nil
		if not petName or not stats then
			warn(`[PetInventoryService] {eggName} rolled an invalid pet: {petName}`)
			break
		end

		-- charge per pet, after the roll: never take coins for one we cannot
		-- deliver, and never deliver one we did not charge for
		if not CurrencyService.spendCoins(player, egg.cost) then
			break
		end
		if not PetInventoryService.grantPet(player, petName) then
			-- refund: the pet did not land, so the coins should not have gone
			CurrencyService.addCoins(player, egg.cost)
			break
		end

		table.insert(results, { name = petName, rarity = stats.rarity })
	end

	if #results == 0 then
		hatchResult:FireClient(player, nil, "Could not hatch")
		return
	end

	hatchResult:FireClient(player, results, count)
end

-- eggName and count arrive on a remote, so neither is trusted.
local function onHatchRequested(player: Player, eggName: any, count: any)
	if typeof(eggName) ~= "string" or not EggConfig.get(eggName) then
		return
	end

	-- Silent, not an error toast: a legitimate client never trips this, so
	-- anything that does is a script and does not deserve a reply.
	local now = os.clock()
	if now - (lastHatchAt[player] or 0) < HATCH_COOLDOWN then
		return
	end
	lastHatchAt[player] = now
	if not isNearEgg(player, eggName) then
		hatchResult:FireClient(player, nil, "Walk back to the egg")
		return
	end

	local requested = if typeof(count) == "number" then math.floor(count) else 1
	if not table.find(HATCH_COUNTS, requested) then
		return -- not one of the offered batch sizes
	end

	hatch(player, eggName, requested)
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

	-- Backfill for profiles that predate the index: anything they still own has
	-- obviously been discovered. Pets they owned and deleted before this
	-- existed are unrecoverable, which is the best that can be done.
	if next(data.discovered) == nil then
		for _, petName in data.ownedPets do
			data.discovered[petName] = true
		end
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

	-- No prompt: the drop table and the hatch buttons live on a billboard the
	-- client builds over this part, so there is nothing to open. All this side
	-- needs is where the egg is, to check a hatch request came from someone
	-- actually standing at it.
	eggHosts[eggName] = host
end

function PetInventoryService.start()
	chooseStarterRemote = Remotes.get("ChooseStarter")
	hatchResult = Remotes.get("HatchResult")
	inventoryUpdated = Remotes.get("InventoryUpdated")

	Remotes.get("RequestHatch").OnServerEvent:Connect(onHatchRequested)

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
	Remotes.get("RequestEquipBest").OnServerEvent:Connect(equipBest)

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
		lastHatchAt[player] = nil
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
