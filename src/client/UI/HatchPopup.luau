--!strict
-- The hatch reveal. Full screen, and unapologetic about it.
--
-- A card in the corner is a notification. This is the moment the entire economy
-- exists to produce, so it takes the screen: everything else dims, light rays
-- burst from behind the pet, and the rig itself lands front and centre at a
-- size you cannot miss.
--
-- The drama scales with rarity. A Common gets a brief, dim version of the same
-- sequence a Legendary gets in full - brighter rays, a harder landing, and a
-- longer hold. That is what makes a good pull feel different BEFORE any text is
-- read, which is the whole trick in this genre.
--
-- Failures deliberately do not get any of this. An error should be quiet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared.Config.PetConfig)

local EggFx = require(script.Parent.EggFx)
local PetViewport = require(script.Parent.PetViewport)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

-- Hold time by rarity rank. A Legendary earns nearly twice the screen time of
-- a Common, which matters more than any single visual for how big it feels.
local HOLD_BY_RANK = { 1.4, 1.6, 1.9, 2.3, 2.9 }
local FAIL_HOLD = 1.3

local RAY_COUNT = 14
local RAY_LENGTH = 1100
local RAY_WIDTH = 34
local RAY_SPIN = 0.22 -- radians/sec, so the burst never sits perfectly still

local MODEL_SIZE = 300
local CELL = 96
local GRID_PAD = 10
local MAX_COLS = 5
local TILE_STAGGER = 0.07

local player = Players.LocalPlayer

local HatchPopup = {}

type Result = { name: string, rarity: string }

function HatchPopup.start()
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "HatchPopup"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 20 -- over everything; this is the moment
	gui.Enabled = false

	local scrim = Instance.new("Frame")
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = Theme.Color.Shadow
	scrim.BackgroundTransparency = 1
	scrim.BorderSizePixel = 0
	scrim.ZIndex = 1
	scrim.Parent = gui

	local rays = UIKit.rayBurst({
		count = RAY_COUNT,
		length = RAY_LENGTH,
		width = RAY_WIDTH,
		spin = RAY_SPIN,
	})
	rays.Position = UDim2.fromScale(0.5, 0.46)
	rays.Size = UDim2.fromOffset(0, 0) -- grown by openStage
	rays.ZIndex = 2
	rays.Parent = gui

	local content = Instance.new("Frame")
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = 3
	content.Parent = gui

	local modelSlot = Instance.new("Frame")
	modelSlot.AnchorPoint = Vector2.new(0.5, 0.5)
	modelSlot.BackgroundTransparency = 1
	modelSlot.Position = UDim2.fromScale(0.5, 0.44)
	modelSlot.Size = UDim2.fromOffset(MODEL_SIZE, MODEL_SIZE)
	modelSlot.ZIndex = 4
	modelSlot.Parent = content

	local rarityLabel = UIKit.label({
		text = "",
		color = Theme.Color.Text,
		size = Theme.TextSize.lg,
		font = Theme.Font.Heavy,
		outline = Theme.Stroke.heavy,
	})
	rarityLabel.AnchorPoint = Vector2.new(0.5, 0)
	rarityLabel.Position = UDim2.fromScale(0.5, 0.17)
	rarityLabel.Size = UDim2.fromOffset(700, 40)
	rarityLabel.ZIndex = 5
	rarityLabel.Parent = content

	local nameLabel = UIKit.label({
		text = "",
		color = Theme.Color.Text,
		size = Theme.TextSize.hero,
		font = Theme.Font.Heavy,
		outline = Theme.Stroke.heavy,
	})
	nameLabel.AnchorPoint = Vector2.new(0.5, 0)
	nameLabel.Position = UDim2.fromScale(0.5, 0.68)
	nameLabel.Size = UDim2.fromOffset(820, 60)
	nameLabel.ZIndex = 5
	nameLabel.Parent = content

	local grid = Instance.new("Frame")
	grid.AnchorPoint = Vector2.new(0.5, 0.5)
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromScale(0.5, 0.5)
	grid.Visible = false
	grid.ZIndex = 4
	grid.Parent = content

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(CELL, CELL)
	gridLayout.CellPadding = UDim2.fromOffset(GRID_PAD, GRID_PAD)
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	gui.Parent = playerGui

	----------------------------------------------------------------------------

	-- Each reveal invalidates the last, so hatching in quick succession never
	-- strands a half-faded burst or lands tiles over a newer pull.
	local generation = 0

	local function clearGrid()
		for _, child in grid:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
	end

	local function dismiss(mine: number)
		if generation ~= mine then
			return
		end

		-- the sequence is over here, not when the server replied: this is what
		-- releases the hatch lock and lets the next pull start
		EggFx.endReveal()

		TweenService:Create(scrim, Theme.Motion.Normal, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(rays, Theme.Motion.Normal, { Size = UDim2.fromOffset(0, 0) }):Play()

		for _, label in { rarityLabel, nameLabel } do
			TweenService:Create(label, Theme.Motion.Normal, { TextTransparency = 1 }):Play()
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				TweenService:Create(stroke, Theme.Motion.Normal, { Transparency = 1 }):Play()
			end
		end

		local exit = TweenService:Create(modelSlot, Theme.Motion.Normal, { Size = UDim2.fromOffset(0, 0) })
		exit:Play()
		exit.Completed:Once(function()
			if generation == mine then
				gui.Enabled = false
				modelSlot:ClearAllChildren()
				clearGrid()
			end
		end)
	end

	-- Everything the two reveal shapes share: dim the world, light the burst in
	-- the rarity's colour, scale both by how good the pull was.
	local function openStage(accent: Color3, rank: number, mine: number)
		local intensity = rank / #HOLD_BY_RANK

		gui.Enabled = true
		scrim.BackgroundTransparency = 1
		TweenService:Create(scrim, Theme.Motion.Fast, {
			BackgroundTransparency = 0.35 - intensity * 0.15,
		}):Play()

		UIKit.tintBurst(rays, accent)
		rays.Size = UDim2.fromOffset(0, 0)
		TweenService:Create(rays, Theme.Motion.Enter, {
			Size = UDim2.fromOffset(RAY_LENGTH, RAY_LENGTH),
		}):Play()

		for _, label in { rarityLabel, nameLabel } do
			label.TextTransparency = 0
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = 0
			end
		end

		return HOLD_BY_RANK[rank] or HOLD_BY_RANK[1], mine
	end

	local function showSingle(result: Result)
		generation += 1
		local mine = generation

		local stats = PetConfig.get(result.name)
		local accent = PetConfig.RarityColors[result.rarity] or Theme.Color.TextMuted
		local rank = PetConfig.rarityRank(result.rarity)

		grid.Visible = false
		modelSlot.Visible = true
		modelSlot:ClearAllChildren()

		local preview = if stats then PetViewport.create(stats.model, { spin = true }) else nil
		if preview then
			preview.Size = UDim2.fromScale(1, 1)
			preview.ZIndex = 5
			preview.Parent = modelSlot
		end

		rarityLabel.Text = string.upper(result.rarity)
		rarityLabel.TextColor3 = accent
		nameLabel.Text = if stats then stats.displayName else result.name
		nameLabel.TextColor3 = Theme.Color.Text

		local hold = openStage(accent, rank, mine)

		-- lands oversized and settles: the overshoot is the "slam"
		modelSlot.Size = UDim2.fromOffset(0, 0)
		TweenService:Create(modelSlot, Theme.Motion.Enter, {
			Size = UDim2.fromOffset(MODEL_SIZE, MODEL_SIZE),
		}):Play()

		task.delay(hold, function()
			dismiss(mine)
		end)
	end

	local function showMany(results: { Result }, requested: number)
		generation += 1
		local mine = generation

		-- best first, so the eye lands on the prize before scanning the rest
		local sorted = table.clone(results)
		table.sort(sorted, function(a, b)
			return PetConfig.rarityRank(a.rarity) > PetConfig.rarityRank(b.rarity)
		end)

		local best = sorted[1]
		local accent = PetConfig.RarityColors[best.rarity] or Theme.Color.TextMuted
		local rank = PetConfig.rarityRank(best.rarity)

		modelSlot.Visible = false
		modelSlot:ClearAllChildren()
		clearGrid()

		local columns = math.min(#sorted, MAX_COLS)
		local rows = math.ceil(#sorted / columns)
		grid.Size = UDim2.fromOffset(
			columns * CELL + (columns - 1) * GRID_PAD,
			rows * CELL + (rows - 1) * GRID_PAD
		)
		grid.Visible = true

		rarityLabel.Text = if #sorted < requested then `{#sorted} OF {requested}` else `x{#sorted}`
		rarityLabel.TextColor3 = accent
		nameLabel.Text = ""

		local hold = openStage(accent, rank, mine)

		for index, result in sorted do
			local stats = PetConfig.get(result.name)
			local tileColor = PetConfig.RarityColors[result.rarity] or Theme.Color.TextMuted

			-- the whole tile takes the rarity colour, so a Legendary is
			-- unmissable in a field of Commons without reading a word
			local tile = UIKit.surface({
				color = tileColor,
				radius = Theme.Radius.md,
				stroke = Theme.Stroke.thick,
				gradient = Theme.Gradient.strong,
			})
			tile.LayoutOrder = index
			tile.ZIndex = 4
			tile.Size = UDim2.fromOffset(0, 0)
			tile.Parent = grid

			local initial = UIKit.label({
				text = string.sub(if stats then stats.displayName else result.name, 1, 1),
				color = Theme.Color.Text,
				size = Theme.TextSize.xl,
				font = Theme.Font.Heavy,
				outline = Theme.Stroke.thick,
			})
			initial.Position = UDim2.fromOffset(0, 8)
			initial.Size = UDim2.new(1, 0, 0, 48)
			initial.ZIndex = 5
			initial.Parent = tile

			local label = UIKit.label({
				text = if stats then stats.displayName else result.name,
				color = Theme.Color.Text,
				size = Theme.TextSize.xs,
				outline = Theme.Stroke.thin,
			})
			label.Position = UDim2.fromOffset(4, 56)
			label.Size = UDim2.new(1, -8, 0, 34)
			label.TextWrapped = true
			label.ZIndex = 5
			label.Parent = tile

			-- staggered landing: this is the part people watch
			task.delay(index * TILE_STAGGER, function()
				if generation == mine and tile.Parent then
					UIKit.popIn(tile, UDim2.fromOffset(CELL, CELL))
				end
			end)
		end

		task.delay(hold + #sorted * TILE_STAGGER, function()
			dismiss(mine)
		end)
	end

	-- Quiet by design: an error is not an event, and dimming the whole screen
	-- to say "you need 40 more coins" would be absurd.
	local function showFailure(reason: string)
		generation += 1
		local mine = generation

		grid.Visible = false
		modelSlot.Visible = false
		modelSlot:ClearAllChildren()

		rarityLabel.Text = "CAN'T HATCH"
		rarityLabel.TextColor3 = Theme.Color.Danger
		nameLabel.Text = reason
		nameLabel.TextColor3 = Theme.Color.Text

		gui.Enabled = true
		scrim.BackgroundTransparency = 1
		rays.Size = UDim2.fromOffset(0, 0)
		for _, label in { rarityLabel, nameLabel } do
			label.TextTransparency = 0
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = 0
			end
		end

		task.delay(FAIL_HOLD, function()
			dismiss(mine)
		end)
	end

	-- EggFx, not the remote: it holds the result back until the egg has finished
	-- shaking, so the reveal lands on the flash rather than before it
	EggFx.Finished:Connect(function(results, detail)
		if typeof(results) ~= "table" or #results == 0 then
			showFailure(if typeof(detail) == "string" then detail else "Something went wrong")
			return
		end

		if #results == 1 then
			showSingle(results[1])
		else
			showMany(results, if typeof(detail) == "number" then detail else #results)
		end
	end)
end

return HatchPopup
