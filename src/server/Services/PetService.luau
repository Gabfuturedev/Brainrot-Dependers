--!strict
-- Spawns one pet per player, makes it follow the owner, and attacks whatever
-- the player clicks. The pet's root is anchored and moved with CFrame - no
-- physics, no network ownership problems, and it stays cheap with many pets.
-- Because it is anchored we also drive the walk/idle animations ourselves and
-- clamp the pet to the ground with a downward raycast.

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

local ATTACK_REQUEST_COOLDOWN = 0.1 -- cheap guard against remote spam
local GROUND_RAY_UP = 8 -- start the ground ray this far above the pet
local GROUND_RAY_LENGTH = 200
-- Locomotion is driven by the pet's REAL speed, not its distance to the goal:
-- while following, the goal travels with the owner, so the gap stays small
-- even at a full run. Two thresholds give hysteresis so the animation can't
-- flicker when the speed sits right on the boundary.
local WALK_START_SPEED = 1.5 -- studs/sec
local WALK_STOP_SPEED = 0.8
local WALK_ANIMATION_SPEED = 16 -- studs/sec the default walk cycle is authored for
local HEIGHT_SMOOTHING = 12 -- how fast the pet settles onto a new ground height

-- Roblox's default animations, used when a pet has no override in PetConfig.
local DEFAULT_ANIMATIONS = {
	[Enum.HumanoidRigType.R15] = { idle = "rbxassetid://507766388", walk = "rbxassetid://507777826" },
	[Enum.HumanoidRigType.R6] = { idle = "rbxassetid://180435571", walk = "rbxassetid://180426354" },
}

type Pet = {
	owner: Player,
	model: Model,
	root: BasePart,
	stats: PetConfig.PetStats,
	target: BasePart?,
	lastAttack: number,
	rootHeight: number, -- studs from the pet's feet up to its root's centre
	idleTrack: AnimationTrack?,
	walkTrack: AnimationTrack?,
	walking: boolean,
}

local PetService = {}

local pets: { [Player]: Pet } = {}
local petFolder: Folder
local targetChangedRemote: RemoteEvent
local lastRequest: { [Player]: number } = {}

-- Single place that mutates pet.target, so the client is always told.
local function assignTarget(pet: Pet, part: BasePart?)
	if pet.target == part then
		return
	end
	pet.target = part
	targetChangedRemote:FireClient(pet.owner, part)
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

local function despawn(player: Player)
	local pet = pets[player]
	if pet then
		pet.model:Destroy()
		pets[player] = nil
	end
end

local function spawnPet(player: Player, character: Model)
	despawn(player)

	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not root then
		return
	end

	local petsFolder = ServerStorage:FindFirstChild("Pets")
	if not petsFolder then
		warn("[PetService] ServerStorage has no 'Pets' folder (check spelling and capitalisation)")
		return
	end

	local template = petsFolder:FindFirstChild(PetConfig.DefaultPet)
	if not template then
		local found = {}
		for _, child in petsFolder:GetChildren() do
			table.insert(found, child.Name)
		end
		warn(
			`[PetService] ServerStorage.Pets has no '{PetConfig.DefaultPet}'. Found: `
				.. (if #found > 0 then table.concat(found, ", ") else "<empty>")
		)
		return
	end

	if not template:IsA("Model") then
		warn(`[PetService] ServerStorage.Pets.{PetConfig.DefaultPet} is a {template.ClassName}, expected a Model`)
		return
	end

	local stats = PetConfig.get(PetConfig.DefaultPet)
	if not stats then
		warn(`[PetService] no stats configured for {PetConfig.DefaultPet}`)
		return
	end

	local model = template:Clone()
	model.Name = `{player.Name}_Pet`
	prepareModel(model)

	local petRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not petRoot then
		warn(`[PetService] {PetConfig.DefaultPet} has no HumanoidRootPart`)
		model:Destroy()
		return
	end

	-- Measure the rig before we anchor it, so we know how high above the
	-- ground the root has to sit for the feet to touch. Works for R6, R15
	-- and any scaled rig without hardcoding hip heights.
	local boundsCenter, boundsSize = model:GetBoundingBox()
	local rootHeight = petRoot.Position.Y - (boundsCenter.Y - boundsSize.Y / 2)

	-- anchoring the rig's root moves the whole body, since limbs hang off Motor6Ds
	petRoot.Anchored = true
	model.PrimaryPart = petRoot

	local spawnPosition = root.Position - root.CFrame.LookVector * stats.followDistance
	petRoot.CFrame = CFrame.new(
		Vector3.new(spawnPosition.X, groundHeight(spawnPosition, root.Position.Y) + rootHeight, spawnPosition.Z)
	)
	model.Parent = petFolder

	local pet: Pet = {
		owner = player,
		model = model,
		root = petRoot,
		stats = stats,
		target = nil,
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

	pets[player] = pet
end

-- Where the pet wants to be this frame, on the horizontal plane.
local function goalPosition(pet: Pet, ownerRoot: BasePart): Vector3
	local target = pet.target
	if target then
		-- stop just short of the target instead of standing inside it
		local fromTarget = pet.root.Position - target.Position
		local flat = Vector3.new(fromTarget.X, 0, fromTarget.Z)
		local direction = if flat.Magnitude > 0.1 then flat.Unit else ownerRoot.CFrame.LookVector
		local standoff = target.Size.Magnitude / 2 + pet.stats.attackRange * 0.4
		return target.Position + direction * standoff
	end

	return ownerRoot.Position - ownerRoot.CFrame.LookVector * pet.stats.followDistance
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

-- `character and character:FindFirstChild(..) :: BasePart?` type-checks badly
-- under --!strict, because the cast binds to the FindFirstChild call only.
local function rootOf(character: Model?): BasePart?
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function updatePet(pet: Pet, deltaTime: number, now: number)
	local ownerRoot = rootOf(pet.owner.Character)
	if not ownerRoot then
		return
	end

	-- drop the target if it died, was removed, or the owner walked away.
	-- Nothing re-acquires automatically - the player has to click again.
	local target = pet.target
	if
		target
		and (
			not target.Parent
			or not BreakableService.isAlive(target)
			or (target.Position - ownerRoot.Position).Magnitude > pet.stats.searchRadius
		)
	then
		assignTarget(pet, nil)
	end

	local current = pet.root.Position
	local goal = goalPosition(pet, ownerRoot)

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
	local lookAt = if pet.target
		then (pet.target :: BasePart).Position
		else nextPosition + ownerRoot.CFrame.LookVector * 10
	local flatLook = Vector3.new(lookAt.X, nextPosition.Y, lookAt.Z)
	if (flatLook - nextPosition).Magnitude > 0.1 then
		pet.root.CFrame = CFrame.lookAt(nextPosition, flatLook)
	else
		pet.root.CFrame = CFrame.new(nextPosition) * (pet.root.CFrame - pet.root.Position)
	end

	-- attack
	local attackTarget = pet.target
	if not attackTarget then
		return
	end
	if now - pet.lastAttack < pet.stats.attackCooldown then
		return
	end
	-- measure to the target's surface, not its centre, so big parts still work
	local reach = (attackTarget.Position - pet.root.Position).Magnitude - attackTarget.Size.Magnitude / 2
	if reach > pet.stats.attackRange then
		return
	end

	pet.lastAttack = now
	local reward = BreakableService.damage(attackTarget, pet.stats.damage, pet.owner)
	if reward > 0 then
		CurrencyService.addCoins(pet.owner, reward)
		assignTarget(pet, nil)
	end
end

-- Client asked the pet to attack something. Never trust the part it sent.
local function onAttackRequested(player: Player, part: unknown)
	local pet = pets[player]
	if not pet then
		warn(`[PetService] {player.Name} clicked but has no pet spawned`)
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
		warn(`[PetService] {part:GetFullName()} is not a registered/living breakable - ignoring click`)
		return
	end

	local ownerRoot = rootOf(player.Character)
	if not ownerRoot then
		return
	end

	local distance = (part.Position - ownerRoot.Position).Magnitude
	if distance > pet.stats.searchRadius then
		warn(`[PetService] {part.Name} is {math.floor(distance)} studs away, max is {pet.stats.searchRadius}`)
		return
	end

	assignTarget(pet, part)
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

	local function bind(player: Player)
		player.CharacterAdded:Connect(function(character)
			spawnPet(player, character)
		end)
		if player.Character then
			spawnPet(player, player.Character)
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
		for _, pet in pets do
			updatePet(pet, deltaTime, now)
		end
	end)
end

return PetService
