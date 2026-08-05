--!strict
-- Opens barriers for areas this player has unlocked.
--
-- A barrier is one shared instance, but unlocking is per-player, so we can't
-- just delete it on the server. Character physics is simulated locally, so
-- clearing CanCollide on our own client lets us walk through while everyone
-- else still sees a solid wall. This is cosmetic only - AreaService refuses to
-- credit damage in a locked area no matter what the client does.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AreaConfig = require(Shared.Config.AreaConfig)
local Remotes = require(Shared.Remotes)

local UNLOCKED_TRANSPARENCY = 0

local Barriers = {}

local function applyTo(barrier: Instance, unlocked: boolean)
	for _, descendant in barrier:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = not unlocked
			descendant.Transparency = if unlocked then UNLOCKED_TRANSPARENCY else 0
		elseif descendant:IsA("ProximityPrompt") then
			descendant.Enabled = not unlocked
		end
	end

	if barrier:IsA("BasePart") then
		barrier.CanCollide = not unlocked
		barrier.Transparency = if unlocked then UNLOCKED_TRANSPARENCY else 0
	end
end

function Barriers.start()
	local folder = Workspace:FindFirstChild("Barriers")
	if not folder then
		return -- no gated areas built yet
	end

	local unlockedAreas: { [string]: boolean } = {}

	local function refresh()
		for _, barrier in folder:GetChildren() do
			local area = AreaConfig.get(barrier.Name)
			if area then
				applyTo(barrier, area.cost <= 0 or unlockedAreas[barrier.Name] == true)
			end
		end
	end

	Remotes.get("AreasUpdated").OnClientEvent:Connect(function(areas)
		unlockedAreas = areas or {}
		refresh()
	end)

	-- barriers streamed in after we unlocked them still need opening
	folder.ChildAdded:Connect(refresh)
	refresh()
end

return Barriers
