--!strict
-- Owns upgrade levels, and answers "what is this player's value for X".
--
-- The single lookup is the point. Without it every system grows its own idea of
-- how upgrades work and adding one means editing five files; with it a consumer
-- multiplies by SkillService.value(player, "Fortune") and never learns that
-- upgrades exist beyond that call.
--
-- Buying is a button on the sign's own face, which needs a remote - a prompt
-- did not. The guarantee is kept the same way the hatch buttons keep it: the
-- server re-checks that the sign is on the caller's plot and that they are
-- actually stood at it. A remote that validates position is as good as no
-- remote; one that trusts the client is a free upgrade button.
--
-- Values are precomputed per player. Pet damage is read on every swing, and
-- walking the upgrade table to answer that would be work done thousands of
-- times for a number that only moves on a purchase.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local SkillConfig = require(Shared.Config.SkillConfig)

local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

local FOLDER_NAME = "Upgrades" -- inside a plot
-- Generous: the client only shows a sign's button when you are close enough to
-- read it, so this only has to catch someone who is not there at all.
local CLICK_RANGE = 24

local SkillService = {}

local values: { [Player]: { [string]: number } } = {}
local warnedIds: { [string]: boolean } = {}
-- plot -> upgradeId -> the part its sign hangs on, so a purchase can be checked
-- against where the player actually is
local signs: { [Instance]: { [string]: BasePart } } = {}
local skillsUpdated: RemoteEvent

local changed = Instance.new("BindableEvent")
-- Fires (player) after a purchase, so anything holding a derived number can
-- recompute rather than poll.
SkillService.Changed = changed.Event

function SkillService.levelOf(player: Player, upgradeId: string): number
	local data = DataService.getData(player)
	return if data then data.skillLevels[upgradeId] or 0 else 0
end

-- The multiplier or flat bonus for an upgrade. Returns the identity value for
-- an unknown id or unloaded profile, so a caller never guards the result.
function SkillService.value(player: Player, upgradeId: string): number
	local cached = values[player]
	if cached and cached[upgradeId] then
		return cached[upgradeId]
	end

	local upgrade = SkillConfig.get(upgradeId)
	if upgrade then
		return SkillConfig.identity(upgrade)
	end

	-- An id nobody configured returns 1 and the upgrade quietly does nothing
	-- forever, which is exactly what a rename causes and what makes it so hard
	-- to spot. Say it once rather than per swing.
	if not warnedIds[upgradeId] then
		warnedIds[upgradeId] = true
		warn(`[SkillService] no upgrade called '{upgradeId}' - whatever asked for it gets no effect`)
	end
	return 1
end

local function recompute(player: Player)
	local data = DataService.getData(player)
	if not data then
		values[player] = nil
		return
	end

	local computed: { [string]: number } = {}
	for id, upgrade in SkillConfig.Upgrades do
		computed[id] = SkillConfig.valueAt(upgrade, data.skillLevels[id] or 0)
	end
	values[player] = computed
end

local function push(player: Player)
	local data = DataService.getData(player)
	if data then
		skillsUpdated:FireClient(player, data.skillLevels)
	end
end

-- Records where each sign is. Nothing is created here - the face UI is built
-- client-side - but the server has to know the position to check a purchase
-- came from someone stood at it.
local function setupPlot(plot: Instance)
	local folder = plot:FindFirstChild(FOLDER_NAME)
	if not folder then
		return -- no signs on this plot yet; PlotService already lists the gaps
	end

	local byId: { [string]: BasePart } = {}
	signs[plot] = byId

	for _, sign in folder:GetChildren() do
		local upgradeId = sign.Name
		if not SkillConfig.get(upgradeId) then
			warn(`[SkillService] {plot.Name}.{FOLDER_NAME}.{upgradeId} has no matching upgrade`)
			continue
		end

		local host: BasePart? = if sign:IsA("BasePart")
			then sign
			else (sign :: Model).PrimaryPart or sign:FindFirstChildWhichIsA("BasePart", true)
		if not host then
			warn(`[SkillService] {plot.Name}.{FOLDER_NAME}.{upgradeId} has no BasePart`)
			continue
		end

		byId[upgradeId] = host
	end
end

-- upgradeId arrives on a remote, so nothing about it is trusted: not that the
-- upgrade exists, not that the sign is on this player's plot, and not that they
-- are anywhere near it.
local function onUpgradeRequested(player: Player, upgradeId: any)
	if typeof(upgradeId) ~= "string" then
		return
	end

	local upgrade = SkillConfig.get(upgradeId)
	local data = DataService.getData(player)
	local plot = PlotService.getPlot(player)
	if not upgrade or not data or not plot then
		return
	end

	local byId = signs[plot]
	local sign = byId and byId[upgradeId]
	if not sign then
		return -- no such sign on their own plot
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	if (root.Position - sign.Position).Magnitude > CLICK_RANGE then
		return
	end

	local level = data.skillLevels[upgradeId] or 0
	local cost = SkillConfig.costOf(upgrade, level)
	if not cost then
		return -- already at maximum
	end
	if not CurrencyService.spendCoins(player, cost) then
		return
	end

	data.skillLevels[upgradeId] = level + 1
	recompute(player)
	push(player)
	changed:Fire(player)
end

function SkillService.start()
	skillsUpdated = Remotes.get("SkillsUpdated")

	Remotes.get("RequestUpgrade").OnServerEvent:Connect(onUpgradeRequested)

	DataService.ProfileLoaded:Connect(function(player)
		recompute(player)
		push(player)
	end)

	PlotService.PlotAssigned:Connect(function(_player, plot)
		if not signs[plot] then
			setupPlot(plot)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		values[player] = nil
	end)
end

return SkillService
