--!strict
-- Owns every breakable part: health, damage, destruction and respawning.
-- Expects: Workspace/Areas/<AreaName>/Breakables/<any parts>

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BreakableConfig = require(Shared.Config.BreakableConfig)
local Remotes = require(Shared.Remotes)
local Sound = require(Shared.Sound)

-- Breaking is the moment the player earns something, and it used to be a part
-- blinking to Transparency 1. The shrink is what gives it weight; the particles
-- are what leave something on screen after the part has gone.
local SHRINK_TIME = 0.18
local SHRINK_SCALE = 0.1
local BURST_PARTICLES = 18

local AreaService = require(script.Parent.AreaService)
local DropService = require(script.Parent.DropService)

type Breakable = {
	part: BasePart,
	areaName: string,
	health: number,
	maxHealth: number,
	alive: boolean,
	baseColor: Color3,
	baseSize: Vector3, -- restored on respawn, since destroying shrinks the part
	stats: BreakableConfig.BreakableStats,
	-- damage each player has dealt this life, so the reward can be split
	contributions: { [Player]: number },
}

local BreakableService = {}

local breakables: { [BasePart]: Breakable } = {}
local damagedRemote: RemoteEvent

local function register(part: BasePart, areaName: string)
	if breakables[part] then
		return
	end

	local stats = BreakableConfig.forArea(areaName)
	part.Anchored = true
	part.CanQuery = true -- must be raycastable or the player can never click it

	breakables[part] = {
		part = part,
		areaName = areaName,
		health = stats.health,
		maxHealth = stats.health,
		alive = true,
		baseColor = part.Color,
		baseSize = part.Size,
		stats = stats,
		contributions = {},
	}
end

local function respawn(entry: Breakable)
	task.wait(entry.stats.respawnTime)
	if not entry.part.Parent then
		return -- part was deleted while we waited
	end

	entry.health = entry.maxHealth
	entry.alive = true
	entry.contributions = {}
	entry.part.Color = entry.baseColor
	entry.part.Size = entry.baseSize
	entry.part.Transparency = 0
	entry.part.CanCollide = true
	entry.part.CanQuery = true
end

-- Spawns drops for every player who damaged this breakable, in proportion to
-- how much they dealt. Whoever lands the last hit gets no special treatment -
-- otherwise a player can steal a rock someone else spent a minute on.
local function payContributors(entry: Breakable)
	local total = 0
	for _, dealt in entry.contributions do
		total += dealt
	end
	if total <= 0 then
		return
	end

	for player, dealt in entry.contributions do
		if player.Parent == Players then
			-- at least 1 coin, so a tiny contribution is never rounded to nothing
			local share = math.max(1, math.floor(entry.stats.coinReward * (dealt / total) + 0.5))
			DropService.spawnReward(player, entry.part.Position, share)
		end
	end
end

-- Debris in the part's own colour, so this reads correctly whatever a given
-- area's breakables are made of without needing per-area VFX config.
local function burst(part: BasePart, color: Color3)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new(0.6, 0.05)
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Lifetime = NumberRange.new(0.35, 0.7)
	emitter.Speed = NumberRange.new(9, 18)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-220, 220)
	emitter.Acceleration = Vector3.new(0, -45, 0) -- chunks fall, they don't drift
	emitter.Enabled = false -- one burst, not a stream
	emitter.Parent = part

	emitter:Emit(BURST_PARTICLES)
	-- outlives the longest particle, then goes; the part itself is reused
	Debris:AddItem(emitter, 2)
end

local function destroyBreakable(entry: Breakable)
	entry.alive = false
	entry.part.CanCollide = false
	entry.part.CanQuery = false

	burst(entry.part, entry.baseColor)
	Sound.playOn("Break", entry.part)

	-- Shrink out instead of blinking out. Nothing waits on this: alive is
	-- already false and the reward is paid below, so the visual is free to take
	-- its time. Back/In squashes the part slightly first, which sells the hit.
	TweenService:Create(
		entry.part,
		TweenInfo.new(SHRINK_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.In),
		{ Size = entry.baseSize * SHRINK_SCALE, Transparency = 1 }
	):Play()

	payContributors(entry)
	task.spawn(respawn, entry)
end

-- Returns true if this hit destroyed the breakable. Coins are paid out here,
-- not by the caller, because the reward is split between contributors.
function BreakableService.damage(part: BasePart, amount: number, attacker: Player?): boolean
	local entry = breakables[part]
	if not entry or not entry.alive then
		return false
	end

	-- the real area gate: opening a barrier is client-side cosmetics, but
	-- damage in a locked area is refused here regardless of how you got in
	if attacker and not AreaService.hasAccess(attacker, entry.areaName) then
		return false
	end

	-- credit only what was actually needed to finish it off, so padding a
	-- killing blow with a huge hit can't inflate your share
	local dealt = math.min(amount, entry.health)
	entry.health -= amount

	if attacker then
		entry.contributions[attacker] = (entry.contributions[attacker] or 0) + dealt
	end

	if entry.health <= 0 then
		destroyBreakable(entry)
		return true
	end

	if attacker then
		damagedRemote:FireClient(attacker, entry.part, amount)
	end

	-- brief flash so hits read on screen
	local flash = TweenService:Create(entry.part, TweenInfo.new(0.12), { Color = Color3.new(1, 1, 1) })
	flash:Play()
	flash.Completed:Once(function()
		if entry.alive then
			TweenService:Create(entry.part, TweenInfo.new(0.12), { Color = entry.baseColor }):Play()
		end
	end)

	return false
end

function BreakableService.isAlive(part: BasePart): boolean
	local entry = breakables[part]
	return entry ~= nil and entry.alive
end

-- Closest living breakable to `position` within `radius`, or nil.
function BreakableService.findNearest(position: Vector3, radius: number): BasePart?
	local closest: BasePart? = nil
	local closestDistance = radius

	for part, entry in breakables do
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

function BreakableService.start()
	damagedRemote = Remotes.get("BreakableDamaged")

	local areas = Workspace:WaitForChild("Areas", 10)
	if not areas then
		warn("[BreakableService] Workspace.Areas is missing - no breakables registered")
		return
	end

	for _, area in areas:GetChildren() do
		local folder = area:FindFirstChild("Breakables")
		if not folder then
			warn(`[BreakableService] {area.Name} has no Breakables folder`)
			continue
		end

		-- descendants, not children: parts grouped inside Models still count
		local count = 0
		for _, descendant in folder:GetDescendants() do
			if descendant:IsA("BasePart") then
				register(descendant, area.Name)
				count += 1
			end
		end
		print(`[BreakableService] registered {count} breakable part(s) in {area.Name}`)

		-- pick up parts added later (e.g. while editing in Studio)
		folder.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BasePart") then
				register(descendant, area.Name)
			end
		end)

		folder.DescendantRemoving:Connect(function(descendant)
			if descendant:IsA("BasePart") then
				breakables[descendant] = nil
			end
		end)
	end
end

return BreakableService
