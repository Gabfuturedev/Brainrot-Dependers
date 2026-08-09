--!strict
-- Wave state and the button that starts a run.
--
-- Reads everything off the plot's attributes rather than a remote: the server
-- writes them, they replicate on their own, and this only has to find the plot
-- whose OwnerUserId is ours.
--
-- Right edge, vertically centred. The wave number is the largest thing on the
-- screen after the reveal, because during a run it is the only number that
-- matters - coins are a means and the wave is the score.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local PLOT_FOLDER = "Plots"
local PANEL_SIZE = UDim2.fromOffset(232, 196)
local SHOWN_POSITION = UDim2.new(1, -20, 0.5, 0)
local HIDDEN_POSITION = UDim2.new(1, 260, 0.5, 0) -- off the right edge
local TRACK_HEIGHT = 22

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

	local panel = UIKit.surface({
		color = Theme.Color.Surface,
		radius = Theme.Radius.lg,
		stroke = Theme.Stroke.heavy,
		shadow = 5,
	})
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = HIDDEN_POSITION
	panel.Size = PANEL_SIZE
	panel.Parent = gui

	-- How much of the wave is left, as a bar. A count alone makes you do the
	-- arithmetic; a bar draining tells you at a glance whether to hold or run
	-- for the hatchery.
	local track = UIKit.surface({
		color = Theme.Color.SurfaceSunken,
		radius = Theme.Radius.pill,
		stroke = Theme.Stroke.thin,
		gradient = Theme.Gradient.subtle,
	})
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.new(0.5, 0, 0, 14)
	track.Size = UDim2.new(1, -Theme.Space.xl, 0, TRACK_HEIGHT)
	track.ClipsDescendants = true -- lets the fill keep pill ends while cut short
	track.ZIndex = 3
	track.Parent = panel

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Theme.Color.Danger
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.ZIndex = 4
	fill.Parent = track
	UIKit.corner(fill, Theme.Radius.pill)
	UIKit.gradient(fill, Theme.Gradient.normal)

	local remainingLabel = UIKit.label({
		text = "",
		color = Theme.Color.Text,
		size = Theme.TextSize.xs,
		font = Theme.Font.Heavy,
		outline = Theme.Stroke.thin,
	})
	remainingLabel.Size = UDim2.fromScale(1, 1)
	remainingLabel.ZIndex = 5
	remainingLabel.Parent = track

	local waveLabel = UIKit.label({
		text = "DEFENCE",
		color = Theme.Color.Text,
		size = Theme.TextSize.lg,
		font = Theme.Font.Heavy,
		outline = Theme.Stroke.heavy,
	})
	waveLabel.Position = UDim2.fromOffset(0, 44)
	waveLabel.Size = UDim2.new(1, 0, 0, 40)
	waveLabel.ZIndex = 3
	waveLabel.Parent = panel

	local bestLabel = UIKit.label({
		text = "",
		color = Theme.Color.TextFaint,
		size = Theme.TextSize.xs,
		outline = Theme.Stroke.thin,
	})
	bestLabel.Position = UDim2.fromOffset(0, 84)
	bestLabel.Size = UDim2.new(1, 0, 0, 18)
	bestLabel.ZIndex = 3
	bestLabel.Parent = panel

	local start = UIKit.button({ text = "START", color = Theme.Color.Danger, textSize = Theme.TextSize.md })
	start.AnchorPoint = Vector2.new(0.5, 1)
	start.Position = UDim2.new(0.5, 0, 1, -Theme.Space.md)
	start.Size = UDim2.new(1, -Theme.Space.xl, 0, 50)
	start.ZIndex = 3
	start.Parent = panel

	start.Activated:Connect(function()
		Remotes.get("RequestStartWave"):FireServer()
	end)

	local shown = false
	local function setShown(visible: boolean)
		if visible == shown then
			return
		end
		shown = visible
		TweenService:Create(panel, Theme.Motion.Enter, {
			Position = if visible then SHOWN_POSITION else HIDDEN_POSITION,
		}):Play()
	end

	local function refresh(plot: Instance)
		local active = plot:GetAttribute("WaveActive") == true
		local wave = plot:GetAttribute("WaveNumber")
		local remaining = plot:GetAttribute("WaveRemaining")
		local size = plot:GetAttribute("WaveSize")
		local best = plot:GetAttribute("BestWave")

		if active and typeof(wave) == "number" and typeof(remaining) == "number" and typeof(size) == "number" then
			waveLabel.Text = `WAVE {wave}`
			waveLabel.TextColor3 = Theme.Color.Warning

			track.Visible = true
			local fraction = if size > 0 then math.clamp(remaining / size, 0, 1) else 0
			TweenService:Create(fill, Theme.Motion.Normal, { Size = UDim2.fromScale(fraction, 1) }):Play()

			-- During the pause between waves nothing is left to count, and
			-- "0 LEFT" reads as broken rather than as a breather.
			remainingLabel.Text = if remaining > 0 then `{remaining} LEFT` else "INCOMING"

			bestLabel.Text = if typeof(best) == "number" and best > 0 then `BEST  {best}` else ""
			start.Text = "IN PROGRESS"
			start.BackgroundTransparency = Theme.Transparency.Disabled
			start.TextTransparency = 0.4
			start.Active = false
		else
			waveLabel.Text = "DEFENCE"
			waveLabel.TextColor3 = Theme.Color.Text

			track.Visible = false
			bestLabel.Text = if typeof(best) == "number" and best > 0
				then `BEST  WAVE {best}`
				else "NO RECORD YET"

			start.Text = "START"
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

		for _, attribute in { "WaveActive", "WaveNumber", "WaveRemaining", "WaveSize", "BestWave" } do
			plot:GetAttributeChangedSignal(attribute):Connect(function()
				refresh(plot :: Instance)
			end)
		end
		refresh(plot)
	end)
end

return WaveBar
