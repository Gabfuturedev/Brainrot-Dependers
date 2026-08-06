--!strict
-- The one-time starter pick, shown on first join. The server decides when this
-- appears and re-validates whatever comes back, so this only renders the
-- options it was handed and reports which one was clicked.
--
-- This is the first screen anyone sees, so it is the loudest thing in the game:
-- oversized outlined type, cards that punch in one after another, and the whole
-- card tinted by rarity rather than a small coloured label on it.
--
-- Model previews are optional. The client cannot see ServerStorage.Pets, so a
-- card falls back to a large initial unless a copy of the rig is sitting in
-- ReplicatedStorage.PetPreviews under the same name.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared.Config.PetConfig)
local Remotes = require(Shared.Remotes)

local PetViewport = require(script.Parent.PetViewport)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local CARD_SIZE = UDim2.fromOffset(196, 300)
local STAGGER = 0.07 -- seconds between each card arriving

local player = Players.LocalPlayer

local StarterPicker = {}

-- Static three-quarter view that leans toward the cursor when its card is
-- hovered. Pass spin = true instead for a slow turntable.
local function addPreview(card: GuiObject, modelName: string): boolean
	local viewport = PetViewport.create(modelName, { hoverTarget = card })
	if not viewport then
		return false
	end

	viewport.Position = UDim2.fromOffset(0, 14)
	viewport.Size = UDim2.new(1, 0, 0, 156)
	viewport.ZIndex = 3
	viewport.Parent = card
	return true
end

function StarterPicker.start()
	local playerGui = player:WaitForChild("PlayerGui")
	local requestStarter = Remotes.get("RequestStarter")

	local gui = Instance.new("ScreenGui")
	gui.Name = "StarterPicker"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- so shadows sit behind
	gui.DisplayOrder = 10 -- over every other panel; nothing else matters yet
	gui.Enabled = false

	-- Full-screen scrim. Deliberately has no close button: the pick is the only
	-- way out, and a dismissed picker would leave a player with no pet at all.
	local scrim = Instance.new("Frame")
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = Theme.Color.Shadow
	scrim.BackgroundTransparency = Theme.Transparency.Scrim
	scrim.BorderSizePixel = 0
	scrim.Parent = gui

	local title = UIKit.label({
		text = "PICK YOUR FIRST BRAINROT",
		color = Theme.Color.Text,
		size = Theme.TextSize.xl,
		font = Theme.Font.Heavy,
		outline = Theme.Stroke.heavy,
	})
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.fromScale(0.5, 0.13)
	title.Size = UDim2.fromOffset(720, 48)
	title.Parent = scrim

	local subtitle = UIKit.label({
		text = "You only choose once — they are all equally strong",
		color = Theme.Color.TextMuted,
		size = Theme.TextSize.sm,
		outline = Theme.Stroke.thin,
	})
	subtitle.AnchorPoint = Vector2.new(0.5, 0)
	subtitle.Position = UDim2.fromScale(0.5, 0.13)
	subtitle.Size = UDim2.fromOffset(720, 86)
	subtitle.Parent = scrim

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.53)
	row.Size = UDim2.fromOffset(0, CARD_SIZE.Y.Offset)
	row.AutomaticSize = Enum.AutomaticSize.X
	row.Parent = scrim

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, Theme.Space.lg)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = row

	gui.Parent = playerGui

	-- Guards a double-click: the server ignores the second, but leaving the
	-- picker up while the first is granted reads as the click not landing.
	local picked = false

	local function addCard(order: number, petName: string)
		local stats = PetConfig.get(petName)
		if not stats then
			return -- config and server disagree; skip rather than render a blank
		end

		local accent = PetConfig.RarityColors[stats.rarity] or Theme.Color.Primary

		local card = Instance.new("TextButton")
		card.BackgroundColor3 = Theme.Color.SurfaceRaised
		card.BorderSizePixel = 0
		card.AutoButtonColor = false
		card.Text = ""
		card.Size = CARD_SIZE
		card.LayoutOrder = order
		card.ZIndex = 2
		card.Parent = row

		UIKit.corner(card, Theme.Radius.lg)
		UIKit.gradient(card, Theme.Gradient.normal)
		UIKit.shadow(card, 6)
		local outline = UIKit.stroke(card, Theme.Stroke.heavy, accent)

		if not addPreview(card, stats.model) then
			local initial = UIKit.label({
				text = string.sub(stats.displayName, 1, 1),
				color = accent,
				size = Theme.TextSize.hero,
				font = Theme.Font.Heavy,
				outline = Theme.Stroke.thick,
			})
			initial.Position = UDim2.fromOffset(0, 14)
			initial.Size = UDim2.new(1, 0, 0, 156)
			initial.ZIndex = 3
			initial.Parent = card
		end

		local name = UIKit.label({
			text = stats.displayName,
			color = Theme.Color.Text,
			size = Theme.TextSize.md,
			font = Theme.Font.Heavy,
			outline = Theme.Stroke.thin,
		})
		name.Position = UDim2.fromOffset(Theme.Space.sm, 178)
		name.Size = UDim2.new(1, -Theme.Space.sm * 2, 0, 46)
		name.TextWrapped = true
		name.ZIndex = 3
		name.Parent = card

		local damage = UIKit.label({
			text = `{stats.damage} DMG`,
			color = Theme.Color.TextMuted,
			size = Theme.TextSize.xs,
			outline = Theme.Stroke.thin,
		})
		damage.Position = UDim2.fromOffset(0, 224)
		damage.Size = UDim2.new(1, 0, 0, 18)
		damage.ZIndex = 3
		damage.Parent = card

		local choose = UIKit.button({ text = "CHOOSE", color = accent, textSize = Theme.TextSize.sm })
		choose.AnchorPoint = Vector2.new(0.5, 1)
		choose.Position = UDim2.new(0.5, 0, 1, -Theme.Space.md)
		choose.Size = UDim2.new(1, -Theme.Space.xl, 0, 40)
		choose.TextColor3 = Theme.Color.Text
		choose.ZIndex = 3
		choose.Active = false -- the whole card is the click target
		choose.Parent = card

		card.MouseEnter:Connect(function()
			if picked then
				return
			end
			outline.Thickness = Theme.Stroke.heavy + 1
			TweenService:Create(card, Theme.Motion.Fast, {
				BackgroundColor3 = Theme.Color.SurfaceHover,
			}):Play()
		end)
		card.MouseLeave:Connect(function()
			outline.Thickness = Theme.Stroke.heavy
			TweenService:Create(card, Theme.Motion.Fast, {
				BackgroundColor3 = Theme.Color.SurfaceRaised,
			}):Play()
		end)

		card.Activated:Connect(function()
			if picked then
				return
			end
			picked = true
			requestStarter:FireServer(petName)
			gui.Enabled = false
		end)

		-- staggered arrival, so three cards read as dealt rather than as one
		-- block appearing
		task.delay((order - 1) * STAGGER, function()
			if card.Parent then
				UIKit.popIn(card, CARD_SIZE)
			end
		end)
	end

	Remotes.get("ChooseStarter").OnClientEvent:Connect(function(petNames)
		-- the server re-offers on every spawn until one is picked, so ignore
		-- anything that arrives after the click
		if picked or typeof(petNames) ~= "table" then
			return
		end

		for _, child in row:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end

		for order, petName in petNames do
			addCard(order, petName)
		end

		gui.Enabled = true
	end)
end

return StarterPicker
