--!strict
-- Start button for the next wave, and the count while one is running.
--
-- The wave is something the player starts, not something that happens to them.
-- Enemies arriving on a timer means never being ready and never choosing to
-- watch; a button makes the fight a thing you set off and then decide whether
-- to stand and see, or walk to the hatchery and trust your defence.
--
-- Reads wave state off the plot's attributes rather than a remote. The server
-- writes them, they replicate on their own, and this only has to find the plot
-- whose OwnerUserId is ours.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local PLOT_FOLDER = "Plots"
local BAR_SIZE = UDim2.fromOffset(206, 92)
local SHOWN_POSITION = UDim2.new(1, -22, 1, -22)
local HIDDEN_POSITION = UDim2.new(1, -22, 1, 160)

local player = Players.LocalPlayer

local WaveBar = {}

-- The plot is claimed a moment after we join, so this retries rather than
-- resolving once and giving up.
local function findOwnPlot(): Instance?
	local folder = Workspace:FindFirstChild(PLOT_FOLDER)
	if not folder then
		return nil
	end
	for _, plot in folder:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			return plot
		end
	end
	return nil
end

function WaveBar.start()
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "WaveBar"
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
	bar.AnchorPoint = Vector2.new(1, 1)
	bar.Position = HIDDEN_POSITION
	bar.Size = BAR_SIZE
	bar.Parent = gui

	local title = UIKit.label({
		text = "DEFENCE",
		color = Theme.Color.TextMuted,
		size = Theme.TextSize.xs,
		outline = Theme.Stroke.thin,
	})
	title.Position = UDim2.fromOffset(0, 10)
	title.Size = UDim2.new(1, 0, 0, 18)
	title.ZIndex = 3
	title.Parent = bar

	local start = UIKit.button({ text = "START WAVE", color = Theme.Color.Danger, textSize = Theme.TextSize.sm })
	start.AnchorPoint = Vector2.new(0.5, 1)
	start.Position = UDim2.new(0.5, 0, 1, -Theme.Space.md)
	start.Size = UDim2.new(1, -Theme.Space.xl, 0, 44)
	start.ZIndex = 3
	start.Parent = bar

	start.Activated:Connect(function()
		Remotes.get("RequestStartWave"):FireServer()
	end)

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

	local function refresh(plot: Instance)
		local active = plot:GetAttribute("WaveActive") == true
		local remaining = plot:GetAttribute("WaveRemaining")
		local size = plot:GetAttribute("WaveSize")

		if active and typeof(remaining) == "number" and typeof(size) == "number" then
			title.Text = `{remaining} LEFT OF {size}`
			title.TextColor3 = Theme.Color.Warning
			start.Text = "IN PROGRESS"
			start.BackgroundTransparency = Theme.Transparency.Disabled
			start.TextTransparency = 0.4
			start.Active = false
		else
			title.Text = "DEFENCE"
			title.TextColor3 = Theme.Color.TextMuted
			start.Text = "START WAVE"
			start.BackgroundTransparency = 0
			start.TextTransparency = 0
			start.Active = true
		end

		setShown(true)
	end

	task.spawn(function()
		local plot: Instance? = nil
		while not plot do
			plot = findOwnPlot()
			if not plot then
				task.wait(0.5)
			end
		end
		assert(plot, "plot")

		for _, attribute in { "WaveActive", "WaveRemaining", "WaveSize" } do
			plot:GetAttributeChangedSignal(attribute):Connect(function()
				refresh(plot :: Instance)
			end)
		end
		refresh(plot)
	end)
end

return WaveBar
