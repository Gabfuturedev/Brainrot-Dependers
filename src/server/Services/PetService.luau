--!strict
-- Spawns each player's equipped pets, orbits them around their owner, and
-- sends the whole group at whatever the player clicks.
--
-- Pets are anchored and moved with CFrame - no physics, no network ownership
-- problems, and it stays cheap with several pets per player. A downward raycast
-- keeps them the right distance off the ground whatever it is doing underneath.
--
-- By default a pet floats (PetConfig.float): it hovers, bobs, and leans into
-- its travel, which needs no rig animation and so no animation assets to own.
-- A pet with float = false walks instead, and because it is anchored we drive
-- its idle/walk tracks ourselves rather than letting a Humanoid do it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared.Config.PetConfig)
local Remotes = require(Shared.Remotes)

local BreakableService = require(script.Parent.BreakableService)
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

-- Floating pets. The bob replaces the walk/idle cycle outright, and the lean is
-- what stops a drifting pet from reading as a model being slid across the map.
local BOB_HEIGHT = 0.4 -- studs above and below the hover height
local BOB_SPEED = 3 -- radians/sec through the bob cycle
local MAX_LEAN = math.rad(14) -- forward tilt at full speed

-- Attack tell. With no rig animation to play, the strike has to come out of the
-- movement itself: the pet lunges at what it is hitting and eases back out.
local LUNGE_DISTANCE = 2.5 -- studs toward the target at full extension
local LUNGE_TIME = 0.28 -- seconds for the whole out-and-back
local LUNGE_OUT = 0.35 -- fraction of that spent striking outward, so the
-- recovery is the slower half - snapping back as fast as it struck reads as a
-- twitch rather than a hit

-- Pets trail in a row across the owner's back rather than ringing them.
local FOLLOW_SPACING = 4 -- studs between neighbours in the row

-- Both of these exist to stop twitching. A pet's frame-to-frame speed swings
-- wildly once it is sitting on its goal - it alternates between a full step and
-- none - so anything driven directly off that speed strobes. Easing the lean
-- and the turn rather than setting them outright is what makes it look alive.
local TURN_SMOOTHING = 10
local LEAN_SMOOTHING = 6

-- Roblox's default animations. These address R6/R15 joint names, so they are
-- only a sensible fallback for an actual avatar rig - see animationIds below.
local DEFAULT_ANIMATIONS = {
	[Enum.HumanoidRigType.R15] = { idle = "rbxassetid://507766388", walk = "rbxassetid://507777826" },
	[Enum.HumanoidRigType.R6] = { idle = "rbxassetid://180435571", walk = "rbxassetid://180426354" },
}

-- Folder of Animation instances a rig ships with, if it has one.
local ANIM_FOLDER_NAME = "Anim"
local IDLE_PATTERNS = { "idle" }
local WALK_PATTERNS = { "walk", "run", "move" }

type Pet = {
	model: Model,
	root: BasePart,
	stats: PetConfig.PetStats,
	slot: number, -- 1-based position in the orbit
	lastAttack: number,
	rootHeight: number, -- studs from the pet's feet up to its root's centre
	-- Where the pet has actually moved to. Bob and lunge are added on top of
	-- this when the CFrame is written, never folded back in - a decoration that
	-- feeds into the movement state makes the pet chase its own animation.
	basePosition: Vector3,
	bobPhase: number, -- so a group doesn't bob in lockstep
	lean: number, -- eased forward tilt, radians
	lungeDirection: Vector3, -- flat heading of the strike in progress
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

-- Rig problems are a property of the model, not of the spawn, but pets rebuild
-- on every equip change and every respawn. Saying it once per model keeps the
-- output readable.
local warned: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn(message)
end

-- Anchoring the root only carries the body with it if the body is jointed to
-- it. Skinned and Motor6D rigs are fine; a model whose parts are merely
-- positioned next to each other comes apart the moment we unanchor them below.
local function warnIfUnjointed(model: Model)
	local parts, joints = 0, 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts += 1
		elseif descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") then
			joints += 1
		end
	end

	if parts > 1 and joints == 0 then
		warnOnce(
			`{model.Name}/joints`,
			`[PetService] {model.Name} has {parts} parts and no joints - everything but the HumanoidRootPart will fall off. Motor6D the body to the root.`
		)
	end
end

local function prepareModel(model: Model)
	-- Pet models come out of the toolbox with scripts of their own - an avatar
	-- Animate, or a rig's own animation player. Every part of a pet's behaviour
	-- is driven by this service, so none of them have anything to do: they would
	-- fight the tracks we play, and a free-model Script running on our server is
	-- exactly how backdoors get in. Nothing here needs to survive.
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end

	warnIfUnjointed(model)

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

-- A model needs exactly one animation driver. Toolbox rigs frequently ship with
-- both a Humanoid and an AnimationController, and with both present each
-- applies its own pose every frame and the pet twitches between them. The
-- Humanoid wins: the rest of this service already looks one up, and it carries
-- the RigType that the avatar fallback needs.
local function resolveAnimator(model: Model): Animator?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local controller = model:FindFirstChildOfClass("AnimationController")

	if humanoid and controller then
		controller:Destroy()
		controller = nil
	end

	local source: Instance? = humanoid or controller
	if not source then
		-- no driver at all: a plain rig gets the non-avatar one
		local created = Instance.new("AnimationController")
		created.Parent = model
		source = created
	end
	assert(source, "animation source")

	local animator = source:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = source
	end
	return animator :: Animator
end

-- R6 has a Torso, R15 an UpperTorso. A single-mesh rig has neither.
local function isAvatarRig(model: Model): boolean
	return model:FindFirstChild("Torso") ~= nil or model:FindFirstChild("UpperTorso") ~= nil
end

local function animationIdOf(instance: Instance): string?
	if instance:IsA("Animation") then
		return instance.AnimationId
	elseif instance:IsA("StringValue") then
		return instance.Value
	elseif instance:IsA("IntValue") or instance:IsA("NumberValue") then
		return `rbxassetid://{instance.Value}`
	end
	return nil
end

local function findAnimation(folder: Instance, patterns: { string }): string?
	for _, child in folder:GetDescendants() do
		local name = child.Name:lower()
		for _, pattern in patterns do
			if string.find(name, pattern, 1, true) then
				local id = animationIdOf(child)
				if id and id ~= "" then
					return id
				end
			end
		end
	end
	return nil
end

-- Where a pet's tracks come from, most specific first:
--   1. an `animations` override in PetConfig - explicit, so it wins even for a
--      floating pet
--   2. nothing at all, if the pet floats: the bob in updatePet is its
--      animation. This has to come before the Anim folder below, or a toolbox
--      rig that ships with animations we can't play would drag them back in.
--   3. an Anim folder inside the model, for a walker that shipped with tracks
--   4. Roblox's defaults, but only for a real avatar rig. On a single-mesh rig
--      those load without error and then visibly do nothing, because there are
--      no R6/R15 joints for them to address - a warning is far more useful.
local function animationIds(model: Model, stats: PetConfig.PetStats): (string?, string?)
	if stats.animations then
		return stats.animations.idle, stats.animations.walk
	end

	if stats.float then
		return nil, nil
	end

	local folder = model:FindFirstChild(ANIM_FOLDER_NAME)
	if folder then
		local idle = findAnimation(folder, IDLE_PATTERNS)
		local walk = findAnimation(folder, WALK_PATTERNS)
		if idle or walk then
			return idle, walk
		end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and isAvatarRig(model) then
		local defaults = DEFAULT_ANIMATIONS[humanoid.RigType]
		if defaults then
			return defaults.idle, defaults.walk
		end
	end

	warnOnce(
		`{model.Name}/animations`,
		`[PetService] {model.Name} has no usable animations - give it an '{ANIM_FOLDER_NAME}' folder holding Animation instances named 'Idle' and 'Walk', or an 'animations' entry in PetConfig`
	)
	return nil, nil
end

local function loadAnimations(pet: Pet, model: Model)
	-- ids first: a floating pet has nothing to play, so there is no driver
	-- conflict to resolve and no Animator worth creating
	local idleId, walkId = animationIds(model, pet.stats)
	if not idleId and not walkId then
		return
	end

	local animator = resolveAnimator(model)
	if not animator then
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

	pet.idleTrack = if idleId then load(idleId, Enum.AnimationPriority.Idle) else nil
	pet.walkTrack = if walkId then load(walkId, Enum.AnimationPriority.Movement) else nil

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

-- Row across the owner's back, in their local space rather than the world's, so
-- the group swings round as they turn instead of sitting at a fixed compass
-- point. A pet still only closes at moveSpeed, so a turn reads as the row
-- trailing round after you rather than snapping to its new spot.
-- 0 at rest, 1 at full extension. The two halves meet at the peak with zero
-- gradient, so there is no visible corner where the strike becomes the recovery.
local function lungeAmount(elapsed: number): number
	if elapsed < 0 or elapsed >= LUNGE_TIME then
		return 0
	end

	local alpha = elapsed / LUNGE_TIME
	if alpha < LUNGE_OUT then
		return math.sin(alpha / LUNGE_OUT * (math.pi / 2))
	end
	return math.cos((alpha - LUNGE_OUT) / (1 - LUNGE_OUT) * (math.pi / 2))
end

local function followOffset(ownerRoot: BasePart, slot: number, count: number, distance: number): Vector3
	local look = ownerRoot.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	-- looking straight up or down leaves nothing to derive a facing from
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)

	local right = Vector3.new(-flat.Z, 0, flat.X)
	local lateral = (slot - (count + 1) / 2) * FOLLOW_SPACING

	return -flat * distance + right * lateral
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

	-- hoverHeight is clearance under the pet, so it reads the same on a rig of
	-- any size; rootHeight converts it to where the root has to sit
	local hover = rootHeight + stats.hoverHeight
	local spawnPosition = ownerRoot.Position + followOffset(ownerRoot, slot, slot, stats.followDistance)
	local spawnY = groundHeight(spawnPosition, ownerRoot.Position.Y) + hover
	local basePosition = Vector3.new(spawnPosition.X, spawnY, spawnPosition.Z)
	petRoot.CFrame = CFrame.new(basePosition)
	model.Parent = petFolder

	local pet: Pet = {
		model = model,
		root = petRoot,
		stats = stats,
		slot = slot,
		lastAttack = 0,
		rootHeight = rootHeight,
		basePosition = basePosition,
		bobPhase = math.random() * math.pi * 2,
		lean = 0,
		lungeDirection = Vector3.zero,
		idleTrack = nil,
		walkTrack = nil,
		walking = false,
	}

	-- works for both rig kinds: the animator is resolved from whatever driver
	-- the model actually has
	loadAnimations(pet, model)

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

	-- ring around the target while attacking, row behind the owner while idle
	local goal: Vector3
	if target then
		local standoff = target.Size.Magnitude / 2 + pet.stats.attackRange * 0.4
		goal = target.Position + slotOffset(pet.slot, count, standoff)
	else
		goal = ownerRoot.Position + followOffset(ownerRoot, pet.slot, count, pet.stats.followDistance)
	end

	-- movement works off basePosition, not the rendered root: reading back a
	-- position that already has bob and lunge baked in makes the pet chase them
	local current = pet.basePosition

	-- move horizontally only; height comes from the ground below us
	local offset = Vector3.new(goal.X - current.X, 0, goal.Z - current.Z)
	local distance = offset.Magnitude
	local step = math.min(pet.stats.moveSpeed * deltaTime, distance)
	local nextFlat = if distance > 0.05 then current + offset.Unit * step else current

	-- how far we actually travelled this frame, not how far we still have to go.
	-- nextFlat shares current's Y, so the bob never leaks into this.
	local travelled = (nextFlat - current).Magnitude
	local speed = if deltaTime > 0 then travelled / deltaTime else 0

	-- a hovering pet doing a walk cycle looks wrong; the bob is its locomotion
	if not pet.stats.float then
		updateLocomotion(pet, speed)
	end

	-- Ground tracking is smoothed so slopes and steps don't jolt the pet. The
	-- bob rides on top of the smoothed value instead of being fed through it -
	-- run it through the smoothing and it damps away to nothing.
	local hover = pet.rootHeight + pet.stats.hoverHeight
	local targetBase = groundHeight(nextFlat, current.Y - hover) + hover
	local baseY = current.Y + (targetBase - current.Y) * math.min(deltaTime * HEIGHT_SMOOTHING, 1)

	pet.basePosition = Vector3.new(nextFlat.X, baseY, nextFlat.Z)

	-- everything from here is decoration layered onto basePosition
	local bob = if pet.stats.float then math.sin(now * BOB_SPEED + pet.bobPhase) * BOB_HEIGHT else 0
	local lunge = lungeAmount(now - pet.lastAttack) * LUNGE_DISTANCE
	local nextPosition = pet.basePosition + Vector3.new(0, bob, 0) + pet.lungeDirection * lunge

	-- Nose down into the direction of travel, eased rather than set: the raw
	-- speed strobes between a full step and none once the pet is sitting on its
	-- goal, and driving the tilt straight off it makes the pet vibrate.
	local targetLean = if pet.stats.float
		then math.clamp(speed / math.max(pet.stats.moveSpeed, 1), 0, 1) * MAX_LEAN
		else 0
	pet.lean += (targetLean - pet.lean) * math.min(deltaTime * LEAN_SMOOTHING, 1)

	-- face the target, or the way the owner is facing while idling
	local lookAt = if target then target.Position else nextPosition + ownerRoot.CFrame.LookVector * 10
	local flatLook = Vector3.new(lookAt.X, nextPosition.Y, lookAt.Z)

	local rotation = pet.root.CFrame - pet.root.Position
	if (flatLook - nextPosition).Magnitude > 0.1 then
		-- turn toward the new facing instead of snapping onto it, so a pet
		-- whipping round behind a turning owner swings rather than teleports
		local goalRotation = CFrame.lookAt(nextPosition, flatLook) * CFrame.Angles(-pet.lean, 0, 0)
		rotation = rotation:Lerp(goalRotation - goalRotation.Position, math.min(deltaTime * TURN_SMOOTHING, 1))
	end

	pet.root.CFrame = CFrame.new(nextPosition) * rotation

	if not target then
		return
	end
	if now - pet.lastAttack < pet.stats.attackCooldown then
		return
	end
	-- measure to the target's surface, not its centre, so big parts still work.
	-- basePosition rather than the root, or a pet at the limit of its range
	-- would flicker in and out of reach as it bobs and lunges.
	local reach = (target.Position - pet.basePosition).Magnitude - target.Size.Magnitude / 2
	if reach > pet.stats.attackRange then
		return
	end

	pet.lastAttack = now

	-- Aim the strike now and keep it, rather than re-deriving it each frame: a
	-- killing blow clears the target immediately, and the lunge should still
	-- play out instead of being cut off on the hit that mattered most.
	local toTarget = target.Position - pet.basePosition
	local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
	pet.lungeDirection = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zero

	-- BreakableService pays out: the reward is split between everyone who
	-- damaged it, so we only care whether this hit finished it off
	if BreakableService.damage(target, pet.stats.damage, group.owner) then
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
