--!strict
-- Area unlocking. Barriers live in Workspace.Barriers, named after the area
-- they block, and the server puts a purchase prompt on each one.
--
-- Unlocking is per-player but a barrier is one shared instance, so the wall
-- is opened locally on the owner's client (see UI/Barriers). That is purely
-- cosmetic - hasAccess() below is the real gate, checked before any damage is
-- credited, so walking through a barrier some other way earns nothing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AreaConfig = require(Shared.Config.AreaConfig)
local Remotes = require(Shared.Remotes)

local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)

local PROMPT_DISTANCE = 14

local AreaService = {}

local areasUpdated: RemoteEvent

function AreaService.hasAccess(player: Player, areaName: string): boolean
	local area = AreaConfig.get(areaName)
	if not area then
		return false -- unknown area: fail closed
	end
	if area.cost <= 0 then
		return true
	end

	local data = DataService.getData(player)
	return data ~= nil and data.unlockedAreas[areaName] == true
end

local function push(player: Player)
	local data = DataService.getData(player)
	if data then
		areasUpdated:FireClient(player, data.unlockedAreas)
	end
end

local function unlock(player: Player, areaName: string)
	local area = AreaConfig.get(areaName)
	if not area or area.cost <= 0 then
		return
	end

	local data = DataService.getData(player)
	if not data or data.unlockedAreas[areaName] then
		return -- already owned; never charge twice
	end

	if not CurrencyService.spendCoins(player, area.cost) then
		return
	end

	data.unlockedAreas[areaName] = true
	push(player)
end

local function setupBarrier(barrier: Instance, areaName: string)
	local area = AreaConfig.get(areaName)
	if not area then
		warn(`[AreaService] Workspace.Barriers.{areaName} has no matching config`)
		return
	end
	if area.cost <= 0 then
		return -- free area, nothing to sell
	end

	local host: BasePart? = if barrier:IsA("BasePart")
		then barrier
		else (barrier :: Model).PrimaryPart or barrier:FindFirstChildWhichIsA("BasePart", true)

	if not host then
		warn(`[AreaService] Workspace.Barriers.{areaName} has no BasePart to attach a prompt to`)
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = `Unlock ({area.cost} coins)`
	prompt.ObjectText = area.displayName
	prompt.HoldDuration = 0.5 -- long enough that nobody buys it by accident
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = host

	prompt.Triggered:Connect(function(player)
		unlock(player, areaName)
	end)
end

function AreaService.start()
	areasUpdated = Remotes.get("AreasUpdated")

	DataService.ProfileLoaded:Connect(push)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			-- barriers are re-evaluated client-side on respawn
			push(player)
		end)
	end)

	local barriers = Workspace:FindFirstChild("Barriers")
	if not barriers then
		warn("[AreaService] no Workspace.Barriers folder - every area is walk-in")
		return
	end

	for _, barrier in barriers:GetChildren() do
		setupBarrier(barrier, barrier.Name)
	end
	barriers.ChildAdded:Connect(function(barrier)
		setupBarrier(barrier, barrier.Name)
	end)
end

return AreaService
