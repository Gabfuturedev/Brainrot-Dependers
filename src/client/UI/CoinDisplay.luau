--!strict
-- Coin counter HUD. Reads leaderstats.Coins, which the server keeps in sync
-- with the saved profile, and rolls the number up instead of snapping so gains
-- are readable.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local COUNT_SPEED = 6 -- higher rolls the number up faster
local PUNCH_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

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

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.Position = UDim2.new(0.5, 0, 0, 16)
	container.Size = UDim2.fromOffset(190, 48)
	container.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
	container.BackgroundTransparency = 0.15
	container.BorderSizePixel = 0
	container.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 200, 60)
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = container

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.fromOffset(10, 0)
	icon.Size = UDim2.new(0, 34, 1, 0)
	icon.Font = Enum.Font.GothamBold
	icon.Text = "🪙"
	icon.TextSize = 24
	icon.Parent = container

	local amount = Instance.new("TextLabel")
	amount.Name = "Amount"
	amount.BackgroundTransparency = 1
	amount.Position = UDim2.fromOffset(46, 0)
	amount.Size = UDim2.new(1, -56, 1, 0)
	amount.Font = Enum.Font.GothamBold
	amount.TextColor3 = Color3.fromRGB(255, 214, 92)
	amount.TextScaled = true
	amount.TextXAlignment = Enum.TextXAlignment.Left
	amount.Text = abbreviate(coins.Value)
	amount.Parent = container

	local sizeConstraint = Instance.new("UITextSizeConstraint")
	sizeConstraint.MaxTextSize = 28
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
		container.Size = UDim2.fromOffset(190, 48)
		TweenService:Create(container, PUNCH_TWEEN, { Size = UDim2.fromOffset(204, 52) }):Play()
		task.delay(PUNCH_TWEEN.Time, function()
			TweenService:Create(container, PUNCH_TWEEN, { Size = UDim2.fromOffset(190, 48) }):Play()
		end)
	end)
end

return CoinDisplay
