--!strict
-- Coin counter HUD. Reads leaderstats.Coins, which the server keeps in sync
-- with the saved profile, and rolls the number up instead of snapping so gains
-- are readable.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local COUNT_SPEED = 6 -- higher rolls the number up faster
local REST_SIZE = UDim2.fromOffset(206, 56)
local PUNCH_SIZE = UDim2.fromOffset(222, 62)

local player = Players.LocalPlayer

local CoinDisplay = {}

-- 1234567 -> "1.2M". Simulators outgrow plain numbers fast.
local function abbreviate(value: number): string
	local n = math.floor(value)
	if n >= 1_000_000_000 then
		return string.format("%.1fB", n / 1_000_000_000)
	elseif n >= 1_000_000 then
		return string.format("%.1fM", n / 1_000_000)
	elseif n >= 1_000 then
		return string.format("%.1fK", n / 1_000)
	end
	return tostring(n)
end

function CoinDisplay.start()
	local playerGui = player:WaitForChild("PlayerGui")
	local leaderstats = player:WaitForChild("leaderstats")
	local coins = leaderstats:WaitForChild("Coins") :: IntValue

	local gui = Instance.new("ScreenGui")
	gui.Name = "CoinDisplay"
	gui.ResetOnSpawn = false -- survive respawns
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Sunken body with a gold coin disc sitting proud of it, rather than a flat
	-- bar with an emoji in it. The disc is what makes this read as currency at
	-- a glance instead of as a number in a box.
	local container = UIKit.surface({
		color = Theme.Color.SurfaceSunken,
		radius = Theme.Radius.pill,
		stroke = Theme.Stroke.heavy,
		shadow = 4,
	})
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.Position = UDim2.new(0.5, 0, 0, 16)
	container.Size = REST_SIZE
	container.Parent = gui

	local disc = UIKit.surface({
		color = Theme.Color.Coin,
		radius = Theme.Radius.pill,
		stroke = Theme.Stroke.thick,
		gradient = Theme.Gradient.strong,
	})
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0, 0.5)
	disc.Position = UDim2.new(0, 6, 0.5, 0)
	disc.Size = UDim2.fromOffset(44, 44)
	disc.ZIndex = 3
	disc.Parent = container

	local symbol = UIKit.label({
		text = "$",
		color = Theme.Color.Outline,
		size = Theme.TextSize.lg,
		font = Theme.Font.Heavy,
	})
	symbol.Name = "Symbol"
	symbol.Size = UDim2.fromScale(1, 1)
	symbol.ZIndex = 4
	symbol.Parent = disc

	local amount = UIKit.label({
		text = abbreviate(coins.Value),
		color = Theme.Color.Text,
		font = Theme.Font.Heavy,
		align = Enum.TextXAlignment.Left,
		outline = Theme.Stroke.thick,
	})
	amount.Name = "Amount"
	amount.Position = UDim2.fromOffset(60, 0)
	amount.Size = UDim2.new(1, -74, 1, 0)
	amount.TextScaled = true
	amount.ZIndex = 3
	amount.Parent = container

	local sizeConstraint = Instance.new("UITextSizeConstraint")
	sizeConstraint.MaxTextSize = Theme.TextSize.lg
	sizeConstraint.Parent = amount

	gui.Parent = playerGui

	-- roll the displayed value toward the real one
	local displayed = coins.Value
	RunService.RenderStepped:Connect(function(deltaTime)
		local target = coins.Value
		if math.abs(target - displayed) < 0.5 then
			displayed = target
		else
			displayed += (target - displayed) * math.min(deltaTime * COUNT_SPEED, 1)
		end
		amount.Text = abbreviate(displayed)
	end)

	-- small pop each time coins come in, so gains register in peripheral vision
	coins.Changed:Connect(function()
		container.Size = REST_SIZE
		TweenService:Create(container, Theme.Motion.Pop, { Size = PUNCH_SIZE }):Play()
		task.delay(Theme.Motion.Pop.Time, function()
			TweenService:Create(container, Theme.Motion.Pop, { Size = REST_SIZE }):Play()
		end)
	end)
end

return CoinDisplay
