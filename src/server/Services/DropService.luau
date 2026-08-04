--!strict
-- Coin drops. Breakables no longer pay out directly - they spawn drops that
-- the owner walks over to collect.
--
-- Drops are anchored and animated by hand rather than thrown with physics:
-- unanchored parts roll down slopes, fall through gaps and cost far more to
-- simulate once a busy server has hundreds of them.
--
-- A drop belongs to one player. The client hides drops it doesn't own (see
-- client/Drops), but ownership is enforced here - the collect check only ever
-- measures against the owner's character.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local CurrencyService = require(script.Parent.CurrencyService)

local COLLECT_RADIUS = 7 -- studs; generous so collecting never feels fiddly
local LIFETIME = 45 -- seconds before an uncollected drop vanishes
local MAX_DROPS_PER_REWARD = 4
local COINS_PER_DROP = 50 -- target value of one drop, before clamping
local ARC_TIME = 0.45 -- seconds spent popping out of the breakable
local ARC_HEIGHT = 4
local SCATTER = 3.5 -- studs of random spread around the break point
local BOB_HEIGHT = 0.15
local SPIN_SPEED = 2.5

type Drop = {
	part: BasePart,
	owner: Player,
	value: number,
	origin: Vector3,
	landing: Vector3,
	spawnedAt: number,
}

local DropService = {}

local drops: { [BasePart]: Drop } = {}
local dropFolder: Folder
local collectedRemote: RemoteEvent

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundBelow(position: Vector3): Vector3
	local ignore: { Instance } = { dropFolder }
	local petFolder = Workspace:FindFirstChild("Pets")
	if petFolder then
		table.insert(ignore, petFolder)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	groundParams.FilterDescendantsInstances = ignore

	local result = Workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -100, 0), groundParams)
	return if result then result.Position + Vector3.new(0, 1.2, 0) else position
end

local function createPart(value: number, position: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = "CoinDrop"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * 1.4
	part.Color = Color3.fromRGB(255, 205, 70)
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- must not block clicks on breakables behind it
	part.CanTouch = false
	part.CFrame = CFrame.new(position)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(70, 24)
	billboard.StudsOffset = Vector3.new(0, 1.4, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = tostring(value)
	label.TextColor3 = Color3.fromRGB(255, 226, 140)
	label.TextSize = 16
	label.TextStrokeTransparency = 0.4
	label.Parent = billboard

	part.Parent = dropFolder
	return part
end

-- Splits a reward across a few drops so a big break feels like a payout
-- rather than a single coin.
function DropService.spawnReward(player: Player, position: Vector3, total: number)
	if total <= 0 then
		return
	end

	local count = math.clamp(math.ceil(total / COINS_PER_DROP), 1, MAX_DROPS_PER_REWARD)
	local each = math.floor(total / count)
	local remainder = total - each * count

	for index = 1, count do
		local value = each + (if index == 1 then remainder else 0)
		if value <= 0 then
			continue
		end

		local scatter = Vector3.new(
			(math.random() - 0.5) * 2 * SCATTER,
			0,
			(math.random() - 0.5) * 2 * SCATTER
		)
		local landing = groundBelow(position + scatter)
		local part = createPart(value, position)

		-- the owner is an attribute so the client can filter on it without
		-- needing a remote per drop
		part:SetAttribute("OwnerUserId", player.UserId)
		part:SetAttribute("Value", value)

		drops[part] = {
			part = part,
			owner = player,
			value = value,
			origin = position,
			landing = landing,
			spawnedAt = os.clock(),
		}
	end
end

local function collect(drop: Drop)
	drops[drop.part] = nil
	drop.part:Destroy()

	CurrencyService.addCoins(drop.owner, drop.value)
	collectedRemote:FireClient(drop.owner, drop.landing, drop.value)
end

local function update(now: number)
	for part, drop in drops do
		if not part.Parent then
			drops[part] = nil
			continue
		end

		local age = now - drop.spawnedAt

		if age >= LIFETIME then
			drops[part] = nil
			part:Destroy()
			continue
		end

		local position: Vector3
		if age < ARC_TIME then
			-- parabolic hop out of the breakable
			local alpha = age / ARC_TIME
			position = drop.origin:Lerp(drop.landing, alpha)
				+ Vector3.new(0, math.sin(alpha * math.pi) * ARC_HEIGHT, 0)
		else
			position = drop.landing + Vector3.new(0, math.sin(now * 3) * BOB_HEIGHT, 0)
		end

		part.CFrame = CFrame.new(position) * CFrame.Angles(0, now * SPIN_SPEED, 0)

		-- only collectable once it has landed, so drops can't be vacuumed up
		-- mid-flight before the player sees them
		if age < ARC_TIME then
			continue
		end

		local character = drop.owner.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - position).Magnitude <= COLLECT_RADIUS then
			collect(drop)
		end
	end
end

function DropService.start()
	dropFolder = Instance.new("Folder")
	dropFolder.Name = "Drops"
	dropFolder.Parent = Workspace

	collectedRemote = Remotes.get("DropCollected")

	Players.PlayerRemoving:Connect(function(player)
		for part, drop in drops do
			if drop.owner == player then
				drops[part] = nil
				part:Destroy()
			end
		end
	end)

	RunService.Heartbeat:Connect(function()
		update(os.clock())
	end)
end

return DropService
