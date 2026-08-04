--!strict
-- Owns every breakable part: health, damage, destruction and respawning.
-- Expects: Workspace/Areas/<AreaName>/Breakables/<any parts>

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BreakableConfig = require(Shared.Config.BreakableConfig)
local Remotes = require(Shared.Remotes)

local AreaService = require(script.Parent.AreaService)
local DropService = require(script.Parent.DropService)

type Breakable = {
	part: BasePart,
	areaName: string,
	health: number,
	maxHealth: number,
	alive: boolean,
	baseColor: Color3,
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

local function destroyBreakable(entry: Breakable)
	entry.alive = false
	entry.part.Transparency = 1
	entry.part.CanCollide = false
	entry.part.CanQuery = false

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
