--!strict
-- The drop table, floating over the egg it belongs to.
--
-- Deliberately small. This sits in the world over an egg the player is standing
-- at, so it competes with the game for screen space - the earlier version was
-- twice this size and read as a menu that had escaped onto the map.
--
-- Pets and percentages only, no names: the model IS the name, and a pet you
-- have not hatched yet renders as a black silhouette. You can see there is
-- something to find without seeing what, which turns a price list into a
-- collection you are missing pieces of.
--
-- Purely informational. The hatch buttons live in EggHatchBar, pinned to the
-- bottom of the screen, because a button inside a world-space bubble is a small
-- target that moves as you walk and shrinks as you back away.
--
-- Built on the client so each player sees their own silhouettes - one shared
-- billboard could not do that.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggConfig = require(Shared.Config.EggConfig)
local PetConfig = require(Shared.Config.PetConfig)
local Remotes = require(Shared.Remotes)

local EggFx = require(script.Parent.EggFx)
local PetViewport = require(script.Parent.PetViewport)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local TILE = 46
local TILE_GAP = 6
local HEADER_HEIGHT = 26
local CHANCE_HEIGHT = 15
local TAIL_SIZE = 20 -- the speech-bubble point, a square turned 45 degrees
local VIEW_DISTANCE = 40 -- studs; past this the billboard hides itself
local HEIGHT_ABOVE = 8 -- studs above the egg

local player = Players.LocalPlayer

local EggBillboard = {}

-- Which pets this player has ever hatched, and the tiles waiting to be told.
local discovered: { [string]: boolean } = {}
local refreshers: { () -> () } = {}

local hostPartOf = EggFx.hostPartOf

-- One pet: its rig over its odds. Returns a refresh so the silhouette can lift
-- the moment the player finally pulls it.
local function buildTile(petName: string, chance: number, order: number): (Frame?, () -> ())
	local stats = PetConfig.get(petName)
	if not stats then
		return nil, function() end -- weights and PetConfig disagree
	end

	local accent = PetConfig.RarityColors[stats.rarity] or Theme.Color.TextMuted

	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(TILE, TILE + CHANCE_HEIGHT)
	holder.LayoutOrder = order

	local slot = UIKit.surface({
		color = Theme.Color.SurfaceSunken,
		radius = Theme.Radius.sm,
		stroke = Theme.Stroke.thin,
		gradient = Theme.Gradient.subtle,
	})
	slot.Size = UDim2.fromOffset(TILE, TILE)
	slot.ZIndex = 4
	slot.Parent = holder

	local slotStroke = slot:FindFirstChildOfClass("UIStroke")

	local percent = UIKit.label({
		text = if chance < 1 then string.format("%.1f%%", chance) else string.format("%.0f%%", chance),
		color = accent,
		size = Theme.TextSize.xs,
		outline = Theme.Stroke.thin,
	})
	percent.Position = UDim2.fromOffset(0, TILE)
	percent.Size = UDim2.fromOffset(TILE, CHANCE_HEIGHT)
	percent.ZIndex = 4
	percent.Parent = holder

	local function refresh()
		local found = discovered[petName] == true

		for _, child in slot:GetChildren() do
			if child:IsA("ViewportFrame") then
				child:Destroy()
			end
		end

		local preview = PetViewport.create(stats.model, { silhouette = not found })
		if preview then
			preview.Size = UDim2.fromScale(1, 1)
			preview.ZIndex = 5
			preview.Parent = slot
		end

		-- an undiscovered pet keeps its rarity colour on the odds but loses it
		-- on the frame, so the row still reads as locked at a glance
		if slotStroke then
			slotStroke.Color = if found then accent else Theme.Color.Outline
		end
		percent.TextTransparency = if found then 0 else 0.25
	end

	refresh()
	return holder, refresh
end

local function build(model: Instance, eggName: string, playerGui: PlayerGui)
	local egg = EggConfig.get(eggName)
	if not egg then
		return -- an egg in Workspace with no config; the server already warns
	end

	local host = hostPartOf(model)
	if not host then
		return
	end

	local rows = EggConfig.chances(egg)
	local width = #rows * TILE + (#rows - 1) * TILE_GAP + Theme.Space.lg * 2
	local bodyHeight = HEADER_HEIGHT + TILE + CHANCE_HEIGHT + Theme.Space.md
	local height = bodyHeight + TAIL_SIZE / 2

	local billboard = Instance.new("BillboardGui")
	billboard.Name = `EggBillboard_{eggName}`
	billboard.Adornee = host
	billboard.Size = UDim2.fromOffset(width, height)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, HEIGHT_ABOVE, 0)
	billboard.MaxDistance = VIEW_DISTANCE -- the "only when close" rule, for free
	billboard.AlwaysOnTop = false -- let walls occlude it, so it sits in the world
	billboard.LightInfluence = 0
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- so the tail sits behind
	billboard.ResetOnSpawn = false -- built once at start; must survive respawns
	billboard.Active = true -- off by default, and without it every button is inert

	-- Speech-bubble point: a square turned 45 degrees, sitting behind the body
	-- so only its bottom corner shows. Roblox GUI has no triangle, and this
	-- reads as one while inheriting the same fill and outline as the panel.
	local tail = UIKit.surface({
		color = Theme.Color.Surface,
		radius = 2,
		stroke = Theme.Stroke.thick,
		gradient = Theme.Gradient.subtle,
	})
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.new(0.5, 0, 0, bodyHeight)
	tail.Size = UDim2.fromOffset(TAIL_SIZE, TAIL_SIZE)
	tail.Rotation = 45
	tail.ZIndex = 1 -- behind the body, which UIKit.surface puts at 2
	tail.Parent = billboard

	local panel = UIKit.surface({
		color = Theme.Color.Surface,
		radius = Theme.Radius.md,
		stroke = Theme.Stroke.thick,
	})
	panel.Size = UDim2.new(1, 0, 0, bodyHeight)
	panel.Parent = billboard

	-- name and price on one line; two lines of header on a panel this size was
	-- most of what made the old one feel oversized
	local title = UIKit.label({
		text = `{string.upper(egg.displayName)}  ·  {egg.cost}`,
		color = Theme.Color.Text,
		size = Theme.TextSize.xs,
		font = Theme.Font.Heavy,
		outline = Theme.Stroke.thin,
	})
	title.Position = UDim2.fromOffset(0, 6)
	title.Size = UDim2.new(1, 0, 0, 18)
	title.ZIndex = 3
	title.Parent = panel

	local strip = Instance.new("Frame")
	strip.BackgroundTransparency = 1
	strip.AnchorPoint = Vector2.new(0.5, 0)
	strip.Position = UDim2.new(0.5, 0, 0, HEADER_HEIGHT)
	strip.Size = UDim2.fromOffset(#rows * TILE + (#rows - 1) * TILE_GAP, TILE + CHANCE_HEIGHT)
	strip.ZIndex = 3
	strip.Parent = panel

	local stripLayout = Instance.new("UIListLayout")
	stripLayout.FillDirection = Enum.FillDirection.Horizontal
	stripLayout.Padding = UDim.new(0, TILE_GAP)
	stripLayout.SortOrder = Enum.SortOrder.LayoutOrder
	stripLayout.Parent = strip

	for order, entry in rows do
		local tile, refresh = buildTile(entry.name, entry.chance, order)
		if tile then
			tile.Parent = strip
			table.insert(refreshers, refresh)
		end
	end

	-- PlayerGui with Adornee, rather than parented to the part. A BillboardGui
	-- in Workspace renders perfectly well but never receives input - and while
	-- nothing here is clickable any more, keeping it here means adding
	-- something clickable later does not silently fail.
	billboard.Parent = playerGui

	-- and since it no longer lives with the egg, it has to be cleaned up by hand
	host.Destroying:Once(function()
		billboard:Destroy()
	end)
end

function EggBillboard.start()
	local playerGui = player:WaitForChild("PlayerGui")

	Remotes.get("InventoryUpdated").OnClientEvent:Connect(function(_entries, _maxEquipped, _maxOwned, newDiscovered)
		if typeof(newDiscovered) ~= "table" then
			return
		end
		discovered = newDiscovered
		for _, refresh in refreshers do
			refresh()
		end
	end)

	local eggs = Workspace:WaitForChild("Eggs", 10)
	if not eggs then
		warn("[EggBillboard] no Workspace.Eggs folder - no drop tables to show")
		return
	end

	for _, model in eggs:GetChildren() do
		build(model, model.Name, playerGui)
	end
	eggs.ChildAdded:Connect(function(model)
		build(model, model.Name, playerGui)
	end)
end

return EggBillboard
