--!strict
-- The one-time starter pick, shown on first join. The server decides when this
-- appears and re-validates whatever comes back, so this only renders the
-- options it was handed and reports which one was clicked.
--
-- Built on the same stage as the hatch reveal: dimmed world, light bursting
-- from behind, models front and centre. No cards. A card puts a frame around a
-- pet and turns it into a menu item, which is exactly wrong for the first
-- screen anyone sees - the brainrots should be the interface, not the contents
-- of one.
--
-- Each starter gets its own burst so hovering can light it up individually,
-- which is what makes the choice feel like a choice rather than a form.
--
-- Model previews are optional. The client cannot see ServerStorage.Pets, so a
-- pod falls back to a large initial unless a copy of the rig is sitting in
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

local POD_SIZE = UDim2.fromOffset(236, 356)
local MODEL_SIZE = 210
local POD_GAP = 30
local STAGGER = 0.09 -- seconds between each starter arriving

local BURST_LENGTH = 420
local BURST_COUNT = 10
local BURST_WIDTH = 22
local BURST_REST = 0.72 -- ray transparency when idle
local BURST_HOVER = 0.34 -- and when hovered

local player = Players.LocalPlayer

local StarterPicker = {}

function StarterPicker.start()
	local playerGui = player:WaitForChild("PlayerGui")
	local requestStarter = Remotes.get("RequestStarter")

	local gui = Instance.new("ScreenGui")
	gui.Name = "StarterPicker"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 10 -- over every other panel; nothing else matters yet
	gui.Enabled = false

	-- Deliberately has no close button: the pick is the only way out, and a
	-- dismissed picker would leave a player with no pet at all.
	local scrim = Instance.new("Frame")
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = Theme.Color.Shadow
	scrim.BackgroundTransparency = 0.25
	scrim.BorderSizePixel = 0
	scrim.ZIndex = 1
	scrim.Parent = gui

	local title = UIKit.label({
		text = "PICK YOUR FIRST BRAINROT",
		color = Theme.Color.Text,
		size = Theme.TextSize.xl,
		font = Theme.Font.Heavy,
		outline = Theme.Stroke.heavy,
	})
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.fromScale(0.5, 0.11)
	title.Size = UDim2.fromOffset(780, 48)
	title.ZIndex = 6
	title.Parent = gui

	local subtitle = UIKit.label({
		text = "You only choose once — they are all equally strong",
		color = Theme.Color.TextMuted,
		size = Theme.TextSize.sm,
		outline = Theme.Stroke.thin,
	})
	subtitle.AnchorPoint = Vector2.new(0.5, 0)
	subtitle.Position = UDim2.fromScale(0.5, 0.11)
	subtitle.Size = UDim2.fromOffset(780, 90)
	subtitle.ZIndex = 6
	subtitle.Parent = gui

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.55)
	row.Size = UDim2.fromOffset(0, POD_SIZE.Y.Offset)
	row.AutomaticSize = Enum.AutomaticSize.X
	row.ZIndex = 3
	row.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, POD_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = row

	gui.Parent = playerGui

	-- Guards a double-click: the server ignores the second, but leaving the
	-- picker up while the first is granted reads as the click not landing.
	local picked = false

	local function addPod(order: number, petName: string)
		local stats = PetConfig.get(petName)
		if not stats then
			return -- config and server disagree; skip rather than render a blank
		end

		local accent = PetConfig.RarityColors[stats.rarity] or Theme.Color.Primary

		-- The pod itself is invisible: it exists only as a hit area, so hover
		-- and click cover the whole column rather than just the button.
		local pod = Instance.new("TextButton")
		pod.BackgroundTransparency = 1
		pod.Text = ""
		pod.AutoButtonColor = false
		pod.Size = POD_SIZE
		pod.LayoutOrder = order
		pod.ZIndex = 3
		pod.Parent = row

		local burst = UIKit.rayBurst({
			count = BURST_COUNT,
			length = BURST_LENGTH,
			width = BURST_WIDTH,
			color = accent,
			spin = 0.16,
		})
		burst.Position = UDim2.new(0.5, 0, 0, MODEL_SIZE / 2 + 10)
		burst.ZIndex = 2
		burst.Parent = pod

		for _, bar in burst:GetChildren() do
			if bar:IsA("Frame") then
				bar.BackgroundTransparency = BURST_REST
			end
		end

		local modelSlot = Instance.new("Frame")
		modelSlot.AnchorPoint = Vector2.new(0.5, 0)
		modelSlot.BackgroundTransparency = 1
		modelSlot.Position = UDim2.new(0.5, 0, 0, 10)
		modelSlot.Size = UDim2.fromOffset(MODEL_SIZE, MODEL_SIZE)
		modelSlot.ZIndex = 4
		modelSlot.Parent = pod

		local preview = PetViewport.create(stats.model, { hoverTarget = pod })
		if preview then
			preview.Size = UDim2.fromScale(1, 1)
			preview.ZIndex = 5
			preview.Parent = modelSlot
		else
			local initial = UIKit.label({
				text = string.sub(stats.displayName, 1, 1),
				color = accent,
				size = Theme.TextSize.hero,
				font = Theme.Font.Heavy,
				outline = Theme.Stroke.heavy,
			})
			initial.Size = UDim2.fromScale(1, 1)
			initial.ZIndex = 5
			initial.Parent = modelSlot
		end

		local name = UIKit.label({
			text = stats.displayName,
			color = Theme.Color.Text,
			size = Theme.TextSize.md,
			font = Theme.Font.Heavy,
			outline = Theme.Stroke.thick,
		})
		name.Position = UDim2.fromOffset(0, MODEL_SIZE + 18)
		name.Size = UDim2.new(1, 0, 0, 48)
		name.TextWrapped = true
		name.ZIndex = 5
		name.Parent = pod

		local choose = UIKit.button({ text = "CHOOSE", color = accent, textSize = Theme.TextSize.sm })
		choose.AnchorPoint = Vector2.new(0.5, 1)
		choose.Position = UDim2.fromScale(0.5, 1)
		choose.Size = UDim2.fromOffset(170, 46)
		choose.ZIndex = 5
		choose.Active = false -- the whole pod is the click target
		choose.Parent = pod

		pod.MouseEnter:Connect(function()
			if picked then
				return
			end
			for _, bar in burst:GetChildren() do
				if bar:IsA("Frame") then
					TweenService:Create(bar, Theme.Motion.Fast, { BackgroundTransparency = BURST_HOVER }):Play()
				end
			end
		end)
		pod.MouseLeave:Connect(function()
			for _, bar in burst:GetChildren() do
				if bar:IsA("Frame") then
					TweenService:Create(bar, Theme.Motion.Fast, { BackgroundTransparency = BURST_REST }):Play()
				end
			end
		end)

		pod.Activated:Connect(function()
			if picked then
				return
			end
			picked = true
			requestStarter:FireServer(petName)
			gui.Enabled = false
		end)

		-- staggered arrival, so three options read as dealt rather than as one
		-- block appearing
		modelSlot.Size = UDim2.fromOffset(0, 0)
		task.delay((order - 1) * STAGGER, function()
			if modelSlot.Parent then
				TweenService:Create(modelSlot, Theme.Motion.Enter, {
					Size = UDim2.fromOffset(MODEL_SIZE, MODEL_SIZE),
				}):Play()
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
			addPod(order, petName)
		end

		gui.Enabled = true
	end)
end

return StarterPicker
