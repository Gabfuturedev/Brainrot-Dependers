--!strict
-- Centre-screen reveal for hatch results, coloured by rarity.
--
-- This is the payoff of the entire economy, so it gets more than a line of
-- text: the card punches in oversized, the rarity is called out above the name,
-- and the whole thing is tinted by what came out. A player should be able to
-- tell a Legendary from a Common with the sound off and without reading a word.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared.Config.PetConfig)
local Remotes = require(Shared.Remotes)

local PetViewport = require(script.Parent.PetViewport)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local HOLD_TIME = 1.8
local CARD_SIZE = UDim2.fromOffset(430, 156)
local FAIL_HOLD = 1.2
local TEXT_LEFT = 158 -- clears the preview slot
local TEXT_LEFT_BARE = 40 -- when there is no model to show

local player = Players.LocalPlayer

local HatchPopup = {}

function HatchPopup.start()
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "HatchPopup"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- so shadows sit behind
	gui.DisplayOrder = 5

	local card = UIKit.surface({
		color = Theme.Color.Surface,
		radius = Theme.Radius.lg,
		stroke = Theme.Stroke.heavy,
		shadow = 6,
	})
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.34)
	card.Size = CARD_SIZE
	card.Visible = false
	card.Parent = gui

	-- Rarity band down the left edge. Cheaper to read than coloured text and it
	-- survives being seen out of the corner of your eye.
	local band = UIKit.surface({
		color = Theme.Color.Primary,
		radius = Theme.Radius.sm,
		stroke = Theme.Stroke.thin,
		gradient = Theme.Gradient.strong,
	})
	band.Name = "Band"
	band.AnchorPoint = Vector2.new(0, 0.5)
	band.Position = UDim2.new(0, 14, 0.5, 0)
	band.Size = UDim2.new(0, 12, 1, -28)
	band.ZIndex = 3
	band.Parent = card

	-- Holds one viewport at a time, replaced per hatch. Exactly one model is
	-- ever on screen here, so the render cost never scales with anything.
	local previewSlot = Instance.new("Frame")
	previewSlot.Name = "PreviewSlot"
	previewSlot.BackgroundTransparency = 1
	previewSlot.AnchorPoint = Vector2.new(0, 0.5)
	previewSlot.Position = UDim2.new(0, 36, 0.5, 0)
	previewSlot.Size = UDim2.fromOffset(112, 112)
	previewSlot.ZIndex = 3
	previewSlot.Parent = card

	local rarity = UIKit.label({
		text = "",
		color = Theme.Color.TextMuted,
		size = Theme.TextSize.sm,
		align = Enum.TextXAlignment.Left,
		outline = Theme.Stroke.thin,
	})
	rarity.Name = "Rarity"
	rarity.Position = UDim2.fromOffset(TEXT_LEFT, 38)
	rarity.Size = UDim2.new(1, -TEXT_LEFT - 20, 0, 22)
	rarity.ZIndex = 3
	rarity.Parent = card

	local name = UIKit.label({
		text = "",
		color = Theme.Color.Text,
		size = Theme.TextSize.lg,
		font = Theme.Font.Heavy,
		align = Enum.TextXAlignment.Left,
		outline = Theme.Stroke.thick,
	})
	name.Name = "Name"
	name.Position = UDim2.fromOffset(TEXT_LEFT, 62)
	name.Size = UDim2.new(1, -TEXT_LEFT - 20, 0, 56)
	name.TextScaled = true
	name.ZIndex = 3
	name.Parent = card

	local nameConstraint = Instance.new("UITextSizeConstraint")
	nameConstraint.MaxTextSize = Theme.TextSize.xl
	nameConstraint.Parent = name

	gui.Parent = playerGui

	-- Each show cancels the previous one's hide, so hatching in quick
	-- succession never leaves the card stuck half-faded.
	local generation = 0

	local function show(accent: Color3, kicker: string, headline: string, hold: number, modelName: string?)
		generation += 1
		local mine = generation

		previewSlot:ClearAllChildren()

		local preview = if modelName then PetViewport.create(modelName) else nil
		if preview then
			preview.Size = UDim2.fromScale(1, 1)
			preview.ZIndex = 4
			preview.Parent = previewSlot
		end

		-- slide the text over when there is nothing to show, rather than
		-- leaving a hole where the model would have been
		local left = if preview then TEXT_LEFT else TEXT_LEFT_BARE
		rarity.Position = UDim2.fromOffset(left, 38)
		rarity.Size = UDim2.new(1, -left - 20, 0, 22)
		name.Position = UDim2.fromOffset(left, 62)
		name.Size = UDim2.new(1, -left - 20, 0, 56)

		band.BackgroundColor3 = accent
		rarity.Text = kicker
		rarity.TextColor3 = accent
		name.Text = headline

		card.Visible = true
		card.Position = UDim2.fromScale(0.5, 0.36)
		UIKit.popIn(card, CARD_SIZE)
		TweenService:Create(card, Theme.Motion.Enter, { Position = UDim2.fromScale(0.5, 0.34) }):Play()

		task.delay(hold, function()
			if generation ~= mine then
				return -- a newer hatch owns the card now
			end

			local exit = TweenService:Create(card, Theme.Motion.Normal, {
				Size = UDim2.fromOffset(CARD_SIZE.X.Offset, 0),
				Position = UDim2.fromScale(0.5, 0.31),
			})
			exit:Play()
			exit.Completed:Once(function()
				if generation == mine then
					card.Visible = false
				end
			end)
		end)
	end

	Remotes.get("HatchResult").OnClientEvent:Connect(function(petName, detail)
		if not petName then
			-- failure: `detail` is the reason, e.g. "Need 40 more coins"
			show(Theme.Color.Danger, "CAN'T HATCH", detail or "Something went wrong", FAIL_HOLD)
			return
		end

		local stats = PetConfig.get(petName)
		local rarityName = if typeof(detail) == "string" then detail else "Common"
		local accent = PetConfig.RarityColors[rarityName] or Theme.Color.TextMuted

		show(
			accent,
			string.upper(rarityName),
			stats and stats.displayName or petName,
			HOLD_TIME,
			stats and stats.model
		)
	end)
end

return HatchPopup
