--!strict
-- Floating numbers above breakables: white damage on every hit, gold coins on
-- the killing blow. Purely local - these are never replicated to other players.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local RISE_TIME = 0.9
local RISE_HEIGHT = 5
local JITTER = 1.5 -- sideways spread so rapid hits don't stack into one blur
local POP_SCALE = 1.35 -- overshoot on spawn, so a number lands rather than fades in

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

	-- A real UIStroke rather than Roblox's TextStroke: the built-in one is a
	-- single hairline pixel and disappears against a bright rock, which is
	-- exactly when a damage number most needs to be readable.
	local label = UIKit.label({
		text = text,
		color = color,
		size = size,
		font = Theme.Font.Heavy,
	})
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = billboard

	local outline = UIKit.textStroke(label, Theme.Stroke.thick)

	-- Punch out to oversized and settle back. Numbers that simply appear get
	-- lost in peripheral vision; ones that move are caught without looking.
	local base = billboard.Size
	billboard.Size = UDim2.fromOffset(base.X.Offset * POP_SCALE, base.Y.Offset * POP_SCALE)
	TweenService:Create(billboard, Theme.Motion.Pop, { Size = base }):Play()

	local rise = TweenInfo.new(RISE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(billboard, rise, { StudsOffset = Vector3.new(0, RISE_HEIGHT, 0) }):Play()
	TweenService:Create(label, rise, { TextTransparency = 1 }):Play()
	TweenService:Create(outline, rise, { Transparency = 1 }):Play()

	Debris:AddItem(anchor, RISE_TIME)
end

function FloatingText.start()
	Remotes.get("BreakableDamaged").OnClientEvent:Connect(function(part, damage)
		popup(part.Position, `-{damage}`, Theme.Color.Text, Theme.TextSize.lg)
	end)

	-- coins now read out where the drop was picked up, not where it spawned
	Remotes.get("DropCollected").OnClientEvent:Connect(function(position, value)
		popup(position, `+{value}`, Theme.Color.Coin, Theme.TextSize.xl)
	end)
end

return FloatingText
