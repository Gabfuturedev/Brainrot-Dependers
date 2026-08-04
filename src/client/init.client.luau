--!strict
-- Click a breakable to send your pet at it. The server decides whether the
-- click is valid and tells us what the pet actually locked onto.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local MAX_CLICK_DISTANCE = 300
local DEBUG_CLICKS = true -- prints what you hit; turn off once targeting feels right

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local requestAttack = Remotes.get("RequestAttack")

local highlight = Instance.new("Highlight")
highlight.FillColor = Color3.fromRGB(255, 90, 90)
highlight.FillTransparency = 0.6
highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
highlight.Enabled = false
highlight.Parent = playerGui

-- Walk up the tree so parts grouped inside Models still count.
local function isBreakable(part: BasePart): boolean
	local node: Instance? = part
	while node and node ~= Workspace do
		if node.Name == "Breakables" then
			return true
		end
		node = node.Parent
	end
	return false
end

local function partUnderPointer(screenPosition: Vector3): BasePart?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end

	-- InputObject.Position includes the topbar inset, so this must be
	-- ScreenPointToRay - ViewportPointToRay would sit ~36px off vertically.
	local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)

	local ignore: { Instance } = {}
	local petFolder = Workspace:FindFirstChild("Pets")
	if petFolder then
		table.insert(ignore, petFolder)
	end
	if player.Character then
		table.insert(ignore, player.Character)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore

	local result = Workspace:Raycast(ray.Origin, ray.Direction * MAX_CLICK_DISTANCE, params)
	return result and result.Instance
end

UserInputService.InputBegan:Connect(function(input: InputObject, processedByUI: boolean)
	if processedByUI then
		return
	end
	if
		input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch
	then
		return
	end

	local part = partUnderPointer(input.Position)

	if DEBUG_CLICKS then
		if not part then
			print("[click] hit nothing")
		else
			print(`[click] hit {part:GetFullName()} | breakable: {isBreakable(part)}`)
		end
	end

	if part and isBreakable(part) then
		requestAttack:FireServer(part)
	end
end)

-- params left unannotated: the signal is typed `...any`, so annotating them
-- makes the callback unassignable under --!strict
Remotes.get("PetTargetChanged").OnClientEvent:Connect(function(part)
	highlight.Adornee = part
	highlight.Enabled = part ~= nil
end)

Remotes.get("BreakableDestroyed").OnClientEvent:Connect(function(part, coins)
	print(`Broke {part.Name} (+{coins} coins)`)
end)
