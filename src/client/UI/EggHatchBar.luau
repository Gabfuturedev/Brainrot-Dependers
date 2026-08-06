--!strict
-- The hatch buttons, pinned to the bottom of the screen.
--
-- Split out of the billboard on purpose. Buttons living inside a world-space
-- bubble are a small target that slides around as you walk and shrinks as you
-- back away - fine for reading odds, miserable for clicking. Screen space gives
-- them a fixed size in a fixed place, which is most of what made hatching feel
-- fiddly.
--
-- This owns "which egg am I standing at", since it is the only thing that needs
-- the answer: the billboard hides itself by distance, and the server re-checks
-- range on every request regardless.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggConfig = require(Shared.Config.EggConfig)
local Remotes = require(Shared.Remotes)

local EggFx = require(script.Parent.EggFx)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local BAR_SIZE = UDim2.fromOffset(372, 104)
local SHOWN_POSITION = UDim2.new(0.5, 0, 1, -22)
local HIDDEN_POSITION = UDim2.new(0.5, 0, 1, 150) -- fully off the bottom edge
local BUTTON_SIZE = UDim2.fromOffset(108, 48)

local HATCH_RANGE = 16 -- studs; how close you must be for the bar to appear
local RANGE_POLL = 0.2 -- seconds between checks; this only tracks walking

-- Shortcut keys and the batch each fires. Must stay within the server's
-- HATCH_COUNTS, which refuses anything else.
local HATCH_KEYS: { { key: Enum.KeyCode, label: string, count: number } } = {
	{ key = Enum.KeyCode.E, label = "E", count = 1 },
	{ key = Enum.KeyCode.R, label = "R", count = 3 },
	{ key = Enum.KeyCode.Q, label = "Q", count = 10 },
}

local player = Players.LocalPlayer

local EggHatchBar = {}

local activeEgg: string? = nil

-- Silently does nothing while a pull is still playing. beginHatch is the gate;
-- it also records which egg the animation should shake.
local function hatch(eggName: string, count: number)
	if not EggFx.beginHatch(eggName) then
		return
	end
	Remotes.get("RequestHatch"):FireServer(eggName, count)
end

function EggHatchBar.start()
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "EggHatchBar"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 4
	gui.Parent = playerGui

	local bar = UIKit.surface({
		color = Theme.Color.Surface,
		radius = Theme.Radius.lg,
		stroke = Theme.Stroke.heavy,
		shadow = 5,
	})
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = HIDDEN_POSITION
	bar.Size = BAR_SIZE
	bar.Parent = gui

	local title = UIKit.label({
		text = "",
		color = Theme.Color.Text,
		size = Theme.TextSize.sm,
		font = Theme.Font.Heavy,
		outline = Theme.Stroke.thin,
	})
	title.Position = UDim2.fromOffset(0, 10)
	title.Size = UDim2.new(1, 0, 0, 22)
	title.ZIndex = 3
	title.Parent = bar

	local buttonRow = Instance.new("Frame")
	buttonRow.AnchorPoint = Vector2.new(0.5, 1)
	buttonRow.BackgroundTransparency = 1
	buttonRow.Position = UDim2.new(0.5, 0, 1, -Theme.Space.md)
	buttonRow.Size = UDim2.new(1, -Theme.Space.lg, 0, BUTTON_SIZE.Y.Offset)
	buttonRow.ZIndex = 3
	buttonRow.Parent = bar

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, Theme.Space.sm)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = buttonRow

	local buttons: { TextButton } = {}
	for order, shortcut in HATCH_KEYS do
		local button = UIKit.button({
			text = `x{shortcut.count}`,
			color = if shortcut.count == 1 then Theme.Color.Positive else Theme.Color.Primary,
			textSize = Theme.TextSize.md,
		})
		button.Size = BUTTON_SIZE
		button.LayoutOrder = order
		button.ZIndex = 3
		button.Parent = buttonRow

		-- The key printed on the button is the only reliable way a player
		-- discovers the shortcut exists. A corner badge keeps it out of the way
		-- of the number, which is what they are actually aiming at.
		local badge = UIKit.surface({
			color = Theme.Color.SurfaceSunken,
			radius = Theme.Radius.sm,
			stroke = Theme.Stroke.thin,
			gradient = Theme.Gradient.subtle,
		})
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, -4, 0, 4)
		badge.Size = UDim2.fromOffset(20, 18)
		badge.ZIndex = 4
		badge.Parent = button

		local badgeLabel = UIKit.label({
			text = shortcut.label,
			color = Theme.Color.TextMuted,
			size = Theme.TextSize.xs,
			font = Theme.Font.Heavy,
		})
		badgeLabel.Size = UDim2.fromScale(1, 1)
		badgeLabel.ZIndex = 5
		badgeLabel.Parent = badge

		button.Activated:Connect(function()
			if activeEgg then
				hatch(activeEgg, shortcut.count)
			end
		end)

		table.insert(buttons, button)
	end

	-- Two independent reasons a button is dead: you cannot afford one hatch, or
	-- a pull is still playing. Affordability greys out only on the single
	-- price - the server hatches as many as fit and reports a short delivery,
	-- so a x10 with enough for three should still be pressable.
	local affordable = true
	local function refreshButtons()
		local usable = affordable and not EggFx.isBusy()
		for _, button in buttons do
			button.BackgroundTransparency = if usable then 0 else Theme.Transparency.Disabled
			button.TextTransparency = if usable then 0 else 0.4
			button.Active = usable
		end
	end

	-- so the bar visibly locks for the length of the reveal rather than
	-- swallowing presses with no explanation
	EggFx.BusyChanged:Connect(refreshButtons)

	local coins = 0
	local leaderstats = player:WaitForChild("leaderstats", 10)
	local coinValue = leaderstats and leaderstats:FindFirstChild("Coins")
	if coinValue and coinValue:IsA("IntValue") then
		coins = coinValue.Value
		coinValue.Changed:Connect(function(value)
			coins = value
			local egg = if activeEgg then EggConfig.get(activeEgg) else nil
			affordable = egg == nil or coins >= egg.cost
			refreshButtons()
		end)
	end

	local shown = false
	local function setShown(visible: boolean)
		if visible == shown then
			return
		end
		shown = visible
		TweenService:Create(bar, Theme.Motion.Enter, {
			Position = if visible then SHOWN_POSITION else HIDDEN_POSITION,
		}):Play()
	end

	-- Polled rather than per-frame: this only has to keep up with walking.
	local elapsed = 0
	RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime
		if elapsed < RANGE_POLL then
			return
		end
		elapsed = 0

		local eggs = Workspace:FindFirstChild("Eggs")
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not eggs or not root or not root:IsA("BasePart") then
			activeEgg = nil
			setShown(false)
			return
		end

		local closest: string? = nil
		local closestDistance = HATCH_RANGE
		for _, model in eggs:GetChildren() do
			if not EggConfig.get(model.Name) then
				continue
			end
			local host = EggFx.hostPartOf(model)
			if host then
				local distance = (host.Position - root.Position).Magnitude
				if distance < closestDistance then
					closest = model.Name
					closestDistance = distance
				end
			end
		end

		if closest ~= activeEgg then
			activeEgg = closest
			local egg = if closest then EggConfig.get(closest) else nil
			if egg then
				title.Text = `{string.upper(egg.displayName)}  ·  {egg.cost} EACH`
				affordable = coins >= egg.cost
				refreshButtons()
			end
		end

		setShown(activeEgg ~= nil)
	end)

	UserInputService.InputBegan:Connect(function(input, processedByUI)
		if processedByUI or not activeEgg then
			return
		end
		for _, shortcut in HATCH_KEYS do
			if input.KeyCode == shortcut.key then
				hatch(activeEgg, shortcut.count)
				return
			end
		end
	end)
end

return EggHatchBar
