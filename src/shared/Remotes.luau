--!strict
-- Shared remote registry. The server creates them, the client waits for them,
-- so both sides just do: Remotes.get("DropCollected")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_NAMES = {
	"BreakableDamaged", -- server -> client: (part, damage) for hit numbers
	"DropCollected", -- server -> client: (position, value) when a drop is picked up
	"RequestAttack", -- client -> server: (part) the player clicked
	"PetTargetChanged", -- server -> client: (part?) what the pet is actually attacking
	"HatchResult", -- server -> client: (petName, rarity) or (nil, reason) on failure
	"InventoryUpdated", -- server -> client: (entries, maxEquipped)
	"RequestEquip", -- client -> server: (petId, shouldEquip)
	"RequestDeletePet", -- client -> server: (petId)
	"AreasUpdated", -- server -> client: (unlockedAreas) so barriers can open
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
