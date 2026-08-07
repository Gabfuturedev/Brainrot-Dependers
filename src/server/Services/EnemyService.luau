--!strict
-- Enemies: spawned at a plot's edge, walking at its core, killed by whatever
-- the owner has defending.
--
-- Deliberately built to the same shape as BreakableService - damage(),
-- isAlive(), findNearest(), per-player contribution and a split payout - so
-- PetService needed almost no changes to fight these instead of rocks. An enemy
-- really is a breakable that walks.
--
-- Anchored and moved by CFrame, like pets and drops: no physics, no network
-- ownership, no pathfinding. A plot is an open box and a straight line at the
-- core is the honest answer until it is not.
--
-- Health goes out as attributes, which HealthBars picks up without knowing or
-- caring what an enemy is.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EnemyConfig = require(Shared.Config.EnemyConfig)
local Remotes = require(Shared.Remotes)
local Rig = require(Shared.Rig)
local Sound = require(Shared.Sound)

local DropService = require(script.Parent.DropService)
local PlotService = require(script.Parent.PlotService)

local FOLDER_NAME = "Enemies" -- under ServerStorage
local ARRIVE_DISTANCE = 4 -- studs from the core before it counts as arrived
local GROUND_RAY_UP = 8
local GROUND_RAY_LENGTH = 200
local HEIGHT_SMOOTHING = 12
local PLACEHOLDER_SIZE = Vector3.new(3, 5, 3)

type Enemy = {
	model: Model,
	root: BasePart,
	stats: EnemyConfig.EnemyStats,
	owner: Player, -- whose plot it is walking across
	goal: Vector3,
	position: Vector3,
	rootHeight: number, -- feet to root centre, so it stands on the ground
	alive: boolean,
	lastAttack: number, -- os.clock() of its last swing at a brainrot
	contributions: { [Player]: number },
}

local EnemyService = {}

type Wave = {
	remaining: number, -- still to enter
	alive: number, -- on the field
	nextSpawn: number, -- os.clock() of the next entry
}

-- How EnemyService reaches brainrots without requiring PetService, which
-- requires this one. PetService injects it at start; a plain require in both
-- directions is a cycle and will not load.
export type PetLocator = {
	findNearest: (position: Vector3, radius: number, owner: Player) -> BasePart?,
	damage: (part: BasePart, amount: number) -> boolean,
}

local petLocator: PetLocator? = nil

local enemies: { [BasePart]: Enemy } = {}
local waves: { [Player]: Wave } = {}
local templates: { [string]: Model } = {}
local enemyFolder: Folder
local damagedRemote: RemoteEvent
local warnedRigs: { [string]: boolean } = {} -- one complaint per model, not per spawn

local waveEnded = Instance.new("BindableEvent")
-- Fires (player) when their wave is cleared, which is when downed brainrots
-- come back. PetService listens.
EnemyService.WaveEnded = waveEnded.Event

function EnemyService.setPetLocator(locator: PetLocator)
	petLocator = locator
end

function EnemyService.isWaveActive(player: Player): boolean
	return waves[player] ~= nil
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundHeight(position: Vector3, fallback: number): number
	groundParams.FilterDescendantsInstances = { enemyFolder, Workspace:FindFirstChild("Pets") }

	local origin = position + Vector3.new(0, GROUND_RAY_UP, 0)
	local result = Workspace:Raycast(origin, Vector3.new(0, -GROUND_RAY_LENGTH, 0), groundParams)
	return if result then result.Position.Y else fallback
end

local function indexTemplates()
	local folder = ServerStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		warn(`[EnemyService] ServerStorage has no '{FOLDER_NAME}' folder - using placeholder blocks`)
		return
	end

	local names: { string } = {}
	for _, descendant in folder:GetDescendants() do
		if descendant:IsA("Model") and descendant:FindFirstChild("HumanoidRootPart") then
			templates[descendant.Name] = descendant
			table.insert(names, descendant.Name)
		end
	end

	table.sort(names)
	print(`[EnemyService] indexed {#names} enemy model(s): {table.concat(names, ", ")}`)
end

-- A blank rig so the loop can be tested before any zombie models exist. Ugly on
-- purpose: it should be obvious this is a stand-in, not a design choice.
local function buildPlaceholder(stats: EnemyConfig.EnemyStats): (Model, BasePart)
	local model = Instance.new("Model")

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = PLACEHOLDER_SIZE
	root.Color = Color3.fromRGB(120, 160, 90)
	root.Material = Enum.Material.SmoothPlastic
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model

	model.Name = stats.displayName
	model.PrimaryPart = root
	return model, root
end

-- Always returns something: a missing or malformed model falls back to a
-- placeholder rather than failing, so the loop can be tested before any zombie
-- rigs exist.
local function buildEnemy(stats: EnemyConfig.EnemyStats): (Model, BasePart)
	local template = templates[stats.model]
	if not template then
		return buildPlaceholder(stats)
	end

	local model = template:Clone()
	Rig.stripScripts(model)

	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		model:Destroy()
		return buildPlaceholder(stats)
	end

	return model, root
end

-- Wave state rides on the plot as attributes rather than a remote: it
-- replicates on its own, and the owner's UI can just read its own plot. Same
-- pattern as plot ownership and breakable health.
local function publishWave(player: Player)
	local plot = PlotService.getPlot(player)
	if not plot then
		return
	end

	local wave = waves[player]
	plot:SetAttribute("WaveActive", wave ~= nil)
	plot:SetAttribute("WaveRemaining", if wave then wave.remaining + wave.alive else 0)
	plot:SetAttribute("WaveSize", if wave then EnemyConfig.Wave.size else 0)
end

local function despawn(entry: Enemy)
	if not entry.alive then
		return
	end
	entry.alive = false
	enemies[entry.root] = nil
	entry.model:Destroy()

	local wave = waves[entry.owner]
	if not wave then
		return
	end

	wave.alive -= 1
	if wave.remaining <= 0 and wave.alive <= 0 then
		waves[entry.owner] = nil
		publishWave(entry.owner)
		waveEnded:Fire(entry.owner) -- brings downed brainrots back
	else
		publishWave(entry.owner)
	end
end

-- Splits the reward across everyone who damaged it, in proportion. The last hit
-- gets no special treatment, so a passer-by cannot steal a kill someone else
-- spent the whole approach working on.
local function payContributors(entry: Enemy)
	local total = 0
	for _, dealt in entry.contributions do
		total += dealt
	end
	if total <= 0 then
		return
	end

	for player, dealt in entry.contributions do
		if player.Parent == Players then
			local share = math.max(1, math.floor(entry.stats.coinReward * (dealt / total) + 0.5))
			DropService.spawnReward(player, entry.root.Position, share)
		end
	end
end

-- Same signature as BreakableService.damage, which is why PetService could
-- point at these without being restructured. Returns true if this killed it.
function EnemyService.damage(part: BasePart, amount: number, attacker: Player?): boolean
	local entry = enemies[part]
	if not entry or not entry.alive then
		return false
	end

	local health = part:GetAttribute("Health")
	if typeof(health) ~= "number" then
		return false
	end

	-- credit only what was needed to finish it, so padding a killing blow with
	-- a huge hit cannot inflate a share
	local dealt = math.min(amount, health)
	local remaining = health - amount
	part:SetAttribute("Health", math.max(remaining, 0))

	if attacker then
		entry.contributions[attacker] = (entry.contributions[attacker] or 0) + dealt
	end

	if remaining <= 0 then
		-- playAt, not playOn: despawn destroys the model on the next line, and a
		-- Sound parented to it would go with it before playing a sample
		Sound.playAt("Break", part.Position)
		payContributors(entry)
		despawn(entry)
		return true
	end

	-- Hit feedback rides the same remote breakables use, which is what feeds
	-- the hit sound in Audio and the damage numbers in FloatingText. Missing
	-- this is why zombies were silent and showed no numbers.
	if attacker then
		damagedRemote:FireClient(attacker, part, amount)
	end

	return false
end

function EnemyService.isAlive(part: BasePart): boolean
	local entry = enemies[part]
	return entry ~= nil and entry.alive
end

-- Closest living enemy to `position` within `radius`, or nil.
function EnemyService.findNearest(position: Vector3, radius: number): BasePart?
	local closest: BasePart? = nil
	local closestDistance = radius

	for part, entry in enemies do
		if not entry.alive or not part.Parent then
			continue
		end
		local distance = (part.Position - position).Magnitude
		if distance < closestDistance then
			closest = part
			closestDistance = distance
		end
	end

	return closest
end

-- Returns nil on success, or the reason it could not spawn. A reason rather
-- than a bare false because "the folder is missing" and "the folder is empty"
-- are different jobs for whoever is building the plot, and a warning that
-- guesses wrong sends them to the wrong place.
local function spawnFor(player: Player): string?
	local core = PlotService.getPart(player, "Core")
	if not core then
		return "no Core part"
	end

	local spawns = PlotService.getFolder(player, "EnemySpawns")
	if not spawns then
		return "no EnemySpawns folder"
	end

	local points: { BasePart } = {}
	for _, child in spawns:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(points, child)
		end
	end
	if #points == 0 then
		return "EnemySpawns is empty - put at least one part in it"
	end

	local stats = EnemyConfig.get(EnemyConfig.Default)
	if not stats then
		return `no config for enemy '{EnemyConfig.Default}'`
	end

	local model, root = buildEnemy(stats)

	-- Weld before anything is unanchored, and before the model is parented, so
	-- a rig whose body is attached to nothing never gets a physics step to fall
	-- away in. This is the fix the pets needed and did not have.
	local loose = Rig.weldLoose(model, root)
	if loose > 0 and not warnedRigs[stats.model] then
		warnedRigs[stats.model] = true
		warn(
			`[EnemyService] '{stats.model}' had {loose} part(s) jointed to nothing - welded them to the HumanoidRootPart. Motor6D them in the model to silence this.`
		)
	end

	Rig.makeKinematic(model, root)

	-- An enemy is always walking, so there is no idle/walk state machine to
	-- run - just start the loop and let it play until the thing dies. The
	-- bundled Animate script was stripped, and an anchored root means the
	-- Humanoid would never trigger a walk cycle on its own anyway.
	local animator = Rig.resolveAnimator(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if animator and humanoid then
		local defaults = Rig.DefaultAnimations[humanoid.RigType]
		local walkId = if stats.walkAnimation ~= "" then stats.walkAnimation else defaults and defaults.walk
		local track = if walkId then Rig.loadLoop(animator, walkId, Enum.AnimationPriority.Movement) else nil
		if track then
			track:Play()
		end
	end

	-- Measured from the rig's own bounds rather than assumed, so a tall zombie
	-- and a squat one both stand on the floor instead of in it.
	local boundsCenter, boundsSize = model:GetBoundingBox()
	local rootHeight = root.Position.Y - (boundsCenter.Y - boundsSize.Y / 2)

	local origin = points[math.random(#points)]
	local start = origin.Position
	local position = Vector3.new(start.X, groundHeight(start, start.Y) + rootHeight, start.Z)
	root.CFrame = CFrame.new(position)

	-- set before parenting, so HealthBars sees a complete part when it arrives
	root:SetAttribute("MaxHealth", stats.health)
	root:SetAttribute("Health", stats.health)
	root:SetAttribute("OwnerUserId", player.UserId)

	model.Parent = enemyFolder

	enemies[root] = {
		model = model,
		root = root,
		stats = stats,
		owner = player,
		goal = core.Position,
		position = position,
		rootHeight = rootHeight,
		alive = true,
		lastAttack = 0,
		contributions = {},
	}
	return nil
end

local function step(deltaTime: number)
	local now = os.clock()

	for part, entry in enemies do
		if not entry.alive or not part.Parent then
			continue
		end

		local current = entry.position

		-- Anything in the way gets fought first. This is what makes brainrots
		-- blockers rather than turrets: an enemy only reaches the core when
		-- nothing living stands between it and there.
		local blocker = if petLocator
			then petLocator.findNearest(current, entry.stats.attackRange, entry.owner)
			else nil

		if blocker then
			part.CFrame = CFrame.lookAt(current, Vector3.new(blocker.Position.X, current.Y, blocker.Position.Z))

			if now - entry.lastAttack >= entry.stats.attackCooldown then
				entry.lastAttack = now
				assert(petLocator, "petLocator")
				petLocator.damage(blocker, entry.stats.damage)
			end
			continue -- stopped to fight; no walking this frame
		end

		local flat = Vector3.new(entry.goal.X - current.X, 0, entry.goal.Z - current.Z)
		local distance = flat.Magnitude

		if distance <= ARRIVE_DISTANCE then
			-- Step 3 gives the core health to take off here. For now it simply
			-- arrives and is gone, which is enough to see whether the defence
			-- was fast enough.
			despawn(entry)
			continue
		end

		local movement = math.min(entry.stats.moveSpeed * deltaTime, distance)
		local nextFlat = current + flat.Unit * movement

		local rise = entry.rootHeight
		local desiredY = groundHeight(nextFlat, current.Y - rise) + rise
		local smoothedY = current.Y + (desiredY - current.Y) * math.min(deltaTime * HEIGHT_SMOOTHING, 1)

		entry.position = Vector3.new(nextFlat.X, smoothedY, nextFlat.Z)
		part.CFrame = CFrame.lookAt(entry.position, Vector3.new(entry.goal.X, entry.position.Y, entry.goal.Z))
	end
end

function EnemyService.start()
	enemyFolder = Instance.new("Folder")
	enemyFolder.Name = "Enemies"
	enemyFolder.Parent = Workspace

	damagedRemote = Remotes.get("DamageDealt")

	indexTemplates()

	-- waves are per plot, so they stop with their owner
	PlotService.PlotReleased:Connect(function(player)
		waves[player] = nil
		for _, entry in enemies do
			if entry.owner == player then
				despawn(entry)
			end
		end
	end)

	PlotService.PlotAssigned:Connect(publishWave) -- seed the idle state

	Remotes.get("RequestStartWave").OnServerEvent:Connect(function(player)
		-- one wave at a time; a second press mid-fight is ignored rather than
		-- stacking, which the client also blocks but cannot be trusted to
		if waves[player] or not PlotService.getPlot(player) then
			return
		end

		waves[player] = { remaining = EnemyConfig.Wave.size, alive = 0, nextSpawn = 0 }
		publishWave(player)
	end)

	RunService.Heartbeat:Connect(function(deltaTime)
		local now = os.clock()

		for player, wave in waves do
			if wave.remaining <= 0 or now < wave.nextSpawn then
				continue
			end

			local problem = spawnFor(player)
			if problem then
				-- the plot cannot host enemies; abandon rather than retry every
				-- frame forever, and say exactly what to go and build
				waves[player] = nil
				publishWave(player)
				warn(`[EnemyService] wave cancelled for {player.Name}: {problem}`)
			else
				wave.remaining -= 1
				wave.alive += 1
				wave.nextSpawn = now + EnemyConfig.Wave.spawnInterval
				publishWave(player)
			end
		end

		step(deltaTime)
	end)
end

return EnemyService
