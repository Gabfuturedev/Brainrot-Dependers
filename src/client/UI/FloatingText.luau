--!strict
-- Floating numbers above breakables: white damage on every hit, gold coins on
-- the killing blow. Purely local - these are never replicated to other players.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local RISE_TIME = 0.9
local RISE_HEIGHT = 5
local JITTER = 1.5 -- sideways spread so rapid hits don't stack into one blur

local FloatingText = {}

local function popup(position: Vector3, text: string, color: Color3, size: number)
	local anchor = Instance.new("Part")
	anchor.Name = "FloatingTextAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(
		position + Vector3.new(math.random(-100, 100) / 100 * JITTER, 0, math.random(-100, 100) / 100 * JITTER)
	)
	anchor.Parent = Workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(120, 40)
	billboard.AlwaysOnTop = true
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = color
	label.TextSize = size
	label.TextStrokeTransparency = 0.4
	label.Parent = billboard

	local tweenInfo = TweenInfo.new(RISE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(billboard, tweenInfo, { StudsOffset = Vector3.new(0, RISE_HEIGHT, 0) }):Play()
	TweenService:Create(label, tweenInfo, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()

	Debris:AddItem(anchor, RISE_TIME)
end

function FloatingText.start()
	Remotes.get("BreakableDamaged").OnClientEvent:Connect(function(part, damage)
		popup(part.Position, `-{damage}`, Color3.fromRGB(255, 255, 255), 20)
	end)

	-- coins now read out where the drop was picked up, not where it spawned
	Remotes.get("DropCollected").OnClientEvent:Connect(function(position, value)
		popup(position, `+{value}`, Color3.fromRGB(255, 214, 92), 28)
	end)
end

return FloatingText
