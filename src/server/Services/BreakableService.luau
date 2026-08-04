--!strict
-- Owns every breakable part: health, damage, destruction and respawning.
-- Expects: Workspace/Areas/<AreaName>/Breakables/<any parts>

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BreakableConfig = require(Shared.Config.BreakableConfig)
local Remotes = require(Shared.Remotes)

type Breakable = {
	part: BasePart,
	health: number,
	maxHealth: number,
	alive: boolean,
	baseColor: Color3,
	stats: BreakableConfig.BreakableStats,
}

local BreakableService = {}

local breakables: { [BasePart]: Breakable } = {}
local destroyedRemote: RemoteEvent

local function register(part: BasePart, areaName: string)
	if breakables[part] then
		return
	end

	local stats = BreakableConfig.forArea(areaName)
	part.Anchored = true
	part.CanQuery = true -- must be raycastable or the player can never click it

	breakables[part] = {
		part = part,
		health = stats.health,
		maxHealth = stats.health,
		alive = true,
		baseColor = part.Color,
		stats = stats,
	}
end

local function respawn(entry: Breakable)
	task.wait(entry.stats.respawnTime)
	if not entry.part.Parent then
		return -- part was deleted while we waited
	end

	entry.health = entry.maxHealth
	entry.alive = true
	entry.part.Color = entry.baseColor
	entry.part.Transparency = 0
	entry.part.CanCollide = true
	entry.part.CanQuery = true
end

local function destroyBreakable(entry: Breakable, attacker: Player?)
	entry.alive = false
	entry.part.Transparency = 1
	entry.part.CanCollide = false
	entry.part.CanQuery = false

	if attacker then
		destroyedRemote:FireClient(attacker, entry.part, entry.stats.coinReward)
	end

	task.spawn(respawn, entry)
end

-- Returns the coins awarded (0 if the target survived or was already dead).
function BreakableService.damage(part: BasePart, amount: number, attacker: Player?): number
	local entry = breakables[part]
	if not entry or not entry.alive then
		return 0
	end

	entry.health -= amount

	if entry.health <= 0 then
		destroyBreakable(entry, attacker)
		return entry.stats.coinReward
	end

	-- brief flash so hits read on screen
	local flash = TweenService:Create(entry.part, TweenInfo.new(0.12), { Color = Color3.new(1, 1, 1) })
	flash:Play()
	flash.Completed:Once(function()
		if entry.alive then
			TweenService:Create(entry.part, TweenInfo.new(0.12), { Color = entry.baseColor }):Play()
		end
	end)

	return 0
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
	destroyedRemote = Remotes.get("BreakableDestroyed")

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
