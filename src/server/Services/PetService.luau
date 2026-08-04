--!strict
-- Spawns each player's equipped pets, orbits them around their owner, and
-- sends the whole group at whatever the player clicks.
--
-- Pets are anchored and moved with CFrame - no physics, no network ownership
-- problems, and it stays cheap with several pets per player. Because they are
-- anchored we drive the walk/idle animations ourselves and clamp them to the
-- ground with a downward raycast.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared.Config.PetConfig)
local Remotes = require(Shared.Remotes)

local BreakableService = require(script.Parent.BreakableService)
local CurrencyService = require(script.Parent.CurrencyService)
local PetInventoryService = require(script.Parent.PetInventoryService)

local ATTACK_REQUEST_COOLDOWN = 0.1 -- cheap guard against remote spam
local GROUND_RAY_UP = 8 -- start the ground ray this far above the pet
local GROUND_RAY_LENGTH = 200
local HEIGHT_SMOOTHING = 12 -- how fast a pet settles onto a new ground height

-- Locomotion is driven by the pet's REAL speed, not its distance to the goal:
-- while following, the goal travels with the owner, so the gap stays small
-- even at a full run. Two thresholds give hysteresis so the animation can't
-- flicker when the speed sits right on the boundary.
local WALK_START_SPEED = 1.5 -- studs/sec
local WALK_STOP_SPEED = 0.8
local WALK_ANIMATION_SPEED = 16 -- studs/sec the default walk cycle is authored for

-- Roblox's default animations, used when a pet has no override in PetConfig.
local DEFAULT_ANIMATIONS = {
	[Enum.HumanoidRigType.R15] = { idle = "rbxassetid://507766388", walk = "rbxassetid://507777826" },
	[Enum.HumanoidRigType.R6] = { idle = "rbxassetid://180435571", walk = "rbxassetid://180426354" },
}

type Pet = {
	model: Model,
	root: BasePart,
	stats: PetConfig.PetStats,
	slot: number, -- 1-based position in the orbit
	lastAttack: number,
	rootHeight: number, -- studs from the pet's feet up to its root's centre
	idleTrack: AnimationTrack?,
	walkTrack: AnimationTrack?,
	walking: boolean,
}

-- One target per player, not per pet: clicking commands the whole group.
type PetGroup = {
	owner: Player,
	pets: { Pet },
	target: BasePart?,
}

local PetService = {}

local groups: { [Player]: PetGroup } = {}
local petFolder: Folder
local targetChangedRemote: RemoteEvent
local lastRequest: { [Player]: number } = {}

-- Single place that mutates the target, so the client is always told.
local function assignTarget(group: PetGroup, part: BasePart?)
	if group.target == part then
		return
	end
	group.target = part
	targetChangedRemote:FireClient(group.owner, part)
end

-- `character and character:FindFirstChild(..) :: BasePart?` type-checks badly
-- under --!strict, because the cast binds to the FindFirstChild call only.
local function rootOf(character: Model?): BasePart?
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function prepareModel(model: Model)
	-- the default avatar Animate script would fight the tracks we play below
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			descendant.Anchored = false
		end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- stop the state machine from fighting our CFrame movement.
		-- NOTE: don't use PlatformStand here, it suppresses animations.
		pcall(function()
			humanoid.EvaluateStateMachine = false
		end)
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

local function loadAnimations(pet: Pet, humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	assert(animator, "animator")

	local ids = pet.stats.animations or DEFAULT_ANIMATIONS[humanoid.RigType]
	if not ids then
		return
	end

	local function load(id: string, priority: Enum.AnimationPriority): AnimationTrack?
		local animation = Instance.new("Animation")
		animation.AnimationId = id

		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(animation)
		end)
		if not ok or not track then
			warn(`[PetService] could not load animation {id}: {track}`)
			return nil
		end

		track.Looped = true
		track.Priority = priority
		return track
	end

	pet.idleTrack = load(ids.idle, Enum.AnimationPriority.Idle)
	pet.walkTrack = load(ids.walk, Enum.AnimationPriority.Movement)

	if pet.idleTrack then
		pet.idleTrack:Play()
	end
end

-- Height of the ground under `position`, ignoring pets and characters.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundHeight(position: Vector3, fallback: number): number
	local ignore: { Instance } = { petFolder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	groundParams.FilterDescendantsInstances = ignore

	local origin = position + Vector3.new(0, GROUND_RAY_UP, 0)
	local result = Workspace:Raycast(origin, Vector3.new(0, -GROUND_RAY_LENGTH, 0), groundParams)
	return if result then result.Position.Y else fallback
end

-- Evenly spaced point on a ring, so pets never pile onto the same spot.
local function slotOffset(slot: number, count: number, radius: number): Vector3
	local angle = (slot - 1) / math.max(count, 1) * math.pi * 2
	return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

local function despawn(player: Player)
	local group = groups[player]
	if not group then
		return
	end
	for _, pet in group.pets do
		pet.model:Destroy()
	end
	groups[player] = nil
end

local function buildPet(petName: string, slot: number, ownerRoot: BasePart): Pet?
	local stats = PetConfig.get(petName)
	if not stats then
		warn(`[PetService] no stats configured for '{petName}'`)
		return nil
	end

	local petsFolder = ServerStorage:FindFirstChild("Pets")
	if not petsFolder then
		warn("[PetService] ServerStorage has no 'Pets' folder (check spelling and capitalisation)")
		return nil
	end

	-- fall back to the default model so a pet with no rig yet still works
	local template = petsFolder:FindFirstChild(stats.model) or petsFolder:FindFirstChild(PetConfig.DefaultPet)
	if not template or not template:IsA("Model") then
		warn(`[PetService] no usable model for '{petName}' (wanted '{stats.model}')`)
		return nil
	end

	local model = template:Clone()
	model.Name = petName
	prepareModel(model)

	local petRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not petRoot then
		warn(`[PetService] {template.Name} has no HumanoidRootPart`)
		model:Destroy()
		return nil
	end

	-- Measure the rig before we anchor it, so we know how high above the
	-- ground the root has to sit for the feet to touch. Works for R6, R15
	-- and any scaled rig without hardcoding hip heights.
	local boundsCenter, boundsSize = model:GetBoundingBox()
	local rootHeight = petRoot.Position.Y - (boundsCenter.Y - boundsSize.Y / 2)

	-- anchoring the rig's root moves the whole body, since limbs hang off Motor6Ds
	petRoot.Anchored = true
	model.PrimaryPart = petRoot

	local spawnPosition = ownerRoot.Position + slotOffset(slot, slot, stats.followDistance)
	petRoot.CFrame = CFrame.new(
		Vector3.new(spawnPosition.X, groundHeight(spawnPosition, ownerRoot.Position.Y) + rootHeight, spawnPosition.Z)
	)
	model.Parent = petFolder

	local pet: Pet = {
		model = model,
		root = petRoot,
		stats = stats,
		slot = slot,
		lastAttack = 0,
		rootHeight = rootHeight,
		idleTrack = nil,
		walkTrack = nil,
		walking = false,
	}

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		loadAnimations(pet, humanoid)
	end

	return pet
end

-- Rebuild a player's pets from their equipped list. Cheap enough to call on
-- every equip change, and it keeps world state and saved state in lockstep.
local function refresh(player: Player)
	local previousTarget = groups[player] and groups[player].target
	despawn(player)

	if player.Parent ~= Players then
		return
	end

	local ownerRoot = rootOf(player.Character)
	if not ownerRoot then
		return -- respawning; CharacterAdded will call us again
	end

	local names = PetInventoryService.getEquippedPetNames(player)
	if #names == 0 then
		return
	end

	local group: PetGroup = { owner = player, pets = {}, target = nil }
	for slot, petName in names do
		local pet = buildPet(petName, slot, ownerRoot)
		if pet then
			table.insert(group.pets, pet)
		end
	end

	if #group.pets == 0 then
		return
	end

	groups[player] = group

	-- keep hitting what they were hitting before they equipped something
	if previousTarget and BreakableService.isAlive(previousTarget) then
		assignTarget(group, previousTarget)
	end
end

local function updateLocomotion(pet: Pet, speed: number)
	local walking = pet.walking
	if walking and speed < WALK_STOP_SPEED then
		walking = false
	elseif not walking and speed > WALK_START_SPEED then
		walking = true
	end

	if walking ~= pet.walking then
		pet.walking = walking
		if walking then
			if pet.idleTrack then
				pet.idleTrack:Stop(0.15)
			end
			if pet.walkTrack then
				pet.walkTrack:Play(0.15)
			end
		else
			if pet.walkTrack then
				pet.walkTrack:Stop(0.15)
			end
			if pet.idleTrack then
				pet.idleTrack:Play(0.15)
			end
		end
	end

	-- match the stride to the actual speed so the feet don't skate
	if walking and pet.walkTrack then
		pet.walkTrack:AdjustSpeed(math.clamp(speed / WALK_ANIMATION_SPEED, 0.5, 2))
	end
end

local function updatePet(pet: Pet, group: PetGroup, ownerRoot: BasePart, deltaTime: number, now: number)
	local count = #group.pets
	local target = group.target

	-- ring around the target while attacking, around the owner while idle
	local goal: Vector3
	if target then
		local standoff = target.Size.Magnitude / 2 + pet.stats.attackRange * 0.4
		goal = target.Position + slotOffset(pet.slot, count, standoff)
	else
		goal = ownerRoot.Position + slotOffset(pet.slot, count, pet.stats.followDistance)
	end

	local current = pet.root.Position

	-- move horizontally only; height comes from the ground below us
	local offset = Vector3.new(goal.X - current.X, 0, goal.Z - current.Z)
	local distance = offset.Magnitude
	local step = math.min(pet.stats.moveSpeed * deltaTime, distance)
	local nextFlat = if distance > 0.05 then current + offset.Unit * step else current

	-- how far we actually travelled this frame, not how far we still have to go
	local travelled = (nextFlat - current).Magnitude
	updateLocomotion(pet, if deltaTime > 0 then travelled / deltaTime else 0)

	local desiredY = groundHeight(nextFlat, current.Y - pet.rootHeight) + pet.rootHeight
	local smoothedY = current.Y + (desiredY - current.Y) * math.min(deltaTime * HEIGHT_SMOOTHING, 1)
	local nextPosition = Vector3.new(nextFlat.X, smoothedY, nextFlat.Z)

	-- face the target, or the way the owner is facing while idling
	local lookAt = if target then target.Position else nextPosition + ownerRoot.CFrame.LookVector * 10
	local flatLook = Vector3.new(lookAt.X, nextPosition.Y, lookAt.Z)
	if (flatLook - nextPosition).Magnitude > 0.1 then
		pet.root.CFrame = CFrame.lookAt(nextPosition, flatLook)
	else
		pet.root.CFrame = CFrame.new(nextPosition) * (pet.root.CFrame - pet.root.Position)
	end

	if not target then
		return
	end
	if now - pet.lastAttack < pet.stats.attackCooldown then
		return
	end
	-- measure to the target's surface, not its centre, so big parts still work
	local reach = (target.Position - pet.root.Position).Magnitude - target.Size.Magnitude / 2
	if reach > pet.stats.attackRange then
		return
	end

	pet.lastAttack = now
	local reward = BreakableService.damage(target, pet.stats.damage, group.owner)
	if reward > 0 then
		CurrencyService.addCoins(group.owner, reward)
		assignTarget(group, nil)
	end
end

local function updateGroup(group: PetGroup, deltaTime: number, now: number)
	local ownerRoot = rootOf(group.owner.Character)
	if not ownerRoot then
		return
	end

	-- drop the target if it died, was removed, or the owner walked away.
	-- Nothing re-acquires automatically - the player has to click again.
	local target = group.target
	if target then
		local range = group.pets[1] and group.pets[1].stats.searchRadius or 60
		if
			not target.Parent
			or not BreakableService.isAlive(target)
			or (target.Position - ownerRoot.Position).Magnitude > range
		then
			assignTarget(group, nil)
		end
	end

	for _, pet in group.pets do
		updatePet(pet, group, ownerRoot, deltaTime, now)
	end
end

-- Client asked the pets to attack something. Never trust the part it sent.
local function onAttackRequested(player: Player, part: any)
	local group = groups[player]
	if not group then
		return
	end

	local now = os.clock()
	if now - (lastRequest[player] or 0) < ATTACK_REQUEST_COOLDOWN then
		return
	end
	lastRequest[player] = now

	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return
	end
	if not BreakableService.isAlive(part) then
		return
	end

	local ownerRoot = rootOf(player.Character)
	if not ownerRoot then
		return
	end

	local range = group.pets[1] and group.pets[1].stats.searchRadius or 60
	if (part.Position - ownerRoot.Position).Magnitude > range then
		return
	end

	assignTarget(group, part)
end

function PetService.start()
	petFolder = Instance.new("Folder")
	petFolder.Name = "Pets"
	petFolder.Parent = Workspace

	targetChangedRemote = Remotes.get("PetTargetChanged")
	-- wrapped rather than passed directly: a typed callback is not assignable
	-- to the signal's `(...any) -> ()` under --!strict
	Remotes.get("RequestAttack").OnServerEvent:Connect(function(player, part)
		onAttackRequested(player, part)
	end)

	PetInventoryService.EquippedChanged:Connect(refresh)

	local function bind(player: Player)
		player.CharacterAdded:Connect(function()
			refresh(player)
		end)
		if player.Character then
			refresh(player)
		end
	end

	for _, player in Players:GetPlayers() do
		bind(player)
	end
	Players.PlayerAdded:Connect(bind)
	Players.PlayerRemoving:Connect(function(player)
		despawn(player)
		lastRequest[player] = nil
	end)

	RunService.Heartbeat:Connect(function(deltaTime)
		local now = os.clock()
		for _, group in groups do
			updateGroup(group, deltaTime, now)
		end
	end)
end

return PetService
