--!strict
-- Coin drops. Breakables no longer pay out directly - they spawn drops that pop
-- out, settle, and then fly to their owner once that player is near enough.
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
local SkillService = require(script.Parent.SkillService)

-- Drops pop out, settle, then fly to the owner once they are near enough. The
-- magnet radius is what the player experiences as "pickup range"; the collect
-- radius is only how close the coin has to get before it is absorbed, so it is
-- deliberately small - the coin should visibly arrive, not wink out mid-air.
local COLLECT_RADIUS = 3.5
local MAGNET_RADIUS = 26 -- studs; how close the owner must be to pull drops in
local MAGNET_ACCEL = 90 -- studs/sec^2
local MAGNET_MAX_SPEED = 70 -- studs/sec
local MAGNET_HEIGHT = 1 -- studs above the root, so coins fly into the chest

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
	-- Tracked rather than derived: once a drop is being pulled in it is no
	-- longer at a position the arc or the bob can describe.
	position: Vector3,
	speed: number, -- current magnet speed, 0 while it is sitting still
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
			position = position,
			speed = 0,
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

local function ownerRoot(drop: Drop): BasePart?
	local character = drop.owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function update(now: number, deltaTime: number)
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

		if age < ARC_TIME then
			-- Parabolic hop out of the breakable, and deliberately not
			-- collectable yet: the payout has to be seen leaving the rock, or
			-- the magnet just swallows it before the player registers it.
			local alpha = age / ARC_TIME
			drop.position = drop.origin:Lerp(drop.landing, alpha)
				+ Vector3.new(0, math.sin(alpha * math.pi) * ARC_HEIGHT, 0)
			part.CFrame = CFrame.new(drop.position) * CFrame.Angles(0, now * SPIN_SPEED, 0)
			continue
		end

		local root = ownerRoot(drop)
		local pull = if root then root.Position + Vector3.new(0, MAGNET_HEIGHT, 0) else nil
		local distance = if pull then (pull - drop.position).Magnitude else math.huge
		local reach = MAGNET_RADIUS + SkillService.value(drop.owner, "Magnetism")

		if pull and distance <= reach then
			if distance <= COLLECT_RADIUS then
				collect(drop)
				continue
			end

			-- Accelerate rather than travel at a fixed rate. A coin that starts
			-- slow and arrives fast reads as being pulled; a constant speed
			-- reads as being dragged along on a string.
			drop.speed = math.min(drop.speed + MAGNET_ACCEL * deltaTime, MAGNET_MAX_SPEED)
			drop.position += (pull - drop.position).Unit * math.min(drop.speed * deltaTime, distance)
		else
			-- out of range: sit and bob until they come closer
			drop.speed = 0
			drop.position = drop.landing + Vector3.new(0, math.sin(now * 3) * BOB_HEIGHT, 0)
		end

		part.CFrame = CFrame.new(drop.position) * CFrame.Angles(0, now * SPIN_SPEED, 0)
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

	RunService.Heartbeat:Connect(function(deltaTime)
		update(os.clock(), deltaTime)
	end)
end

return DropService
