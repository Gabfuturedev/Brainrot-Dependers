--!strict
-- Shared remote registry. The server creates them, the client waits for them,
-- so both sides just do: Remotes.get("DropCollected")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_NAMES = {
	-- The two halves of a fight, from the owner's point of view. Dealt is your
	-- side hurting something; Taken is something hurting yours. Both carry
	-- (part, amount) and both are sent only to the player they concern.
	"DamageDealt", -- server -> client: (part, amount) your brainrots landed a hit
	"DamageTaken", -- server -> client: (part, amount) one of your brainrots was hit
	"DropCollected", -- server -> client: (position, value) when a drop is picked up
	"RequestAttack", -- client -> server: (part) the player clicked
	"PetTargetChanged", -- server -> client: (part?) what the pet is actually attacking
	"HatchResult", -- server -> client: (petName, rarity) or (nil, reason) on failure
	"InventoryUpdated", -- server -> client: (entries, maxEquipped)
	"RequestEquip", -- client -> server: (petId, shouldEquip)
	"RequestDeletePet", -- client -> server: (petId)
	"RequestBulkDelete", -- client -> server: (rarity?) every unequipped pet of that rarity, nil for all
	"RequestEquipBest", -- client -> server: () swap the equipped set to the strongest owned
	"RequestHatch", -- client -> server: (eggName, count) hatch from an egg you are standing at
	"RequestStartWave", -- client -> server: () send the next wave at your own core
	"RequestUpgrade", -- client -> server: (upgradeId) buy from a sign you are stood at
	"SkillsUpdated", -- server -> client: (skills) skillId -> level
	"AreasUpdated", -- server -> client: (unlockedAreas) so barriers can open
	"ChooseStarter", -- server -> client: (petNames) offer the one-time starter pick
	"RequestStarter", -- client -> server: (petName) the starter they picked
}

local Remotes = {}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in REMOTE_NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Remotes.get(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
