--!strict
-- Drops are real server parts, so every player receives every drop. Each one
-- carries an OwnerUserId attribute and we simply hide the ones that aren't
-- ours, which keeps a busy area from looking like a coin blizzard.
--
-- This is presentation only. DropService measures the collect radius against
-- the owner's character, so hiding or revealing a part locally changes nothing
-- about who can actually pick it up.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local Drops = {}

local function apply(drop: Instance)
	if not drop:IsA("BasePart") then
		return
	end

	local ownerId = drop:GetAttribute("OwnerUserId")
	local mine = ownerId == player.UserId

	drop.LocalTransparencyModifier = if mine then 0 else 1
	for _, gui in drop:GetChildren() do
		if gui:IsA("BillboardGui") then
			gui.Enabled = mine
		end
	end
end

function Drops.start()
	local folder = Workspace:WaitForChild("Drops")

	for _, drop in folder:GetChildren() do
		apply(drop)
	end

	folder.ChildAdded:Connect(function(drop)
		-- the attribute may replicate a frame after the part itself
		if drop:GetAttribute("OwnerUserId") == nil then
			drop:GetAttributeChangedSignal("OwnerUserId"):Once(function()
				apply(drop)
			end)
		end
		apply(drop)
	end)
end

return Drops
