--!strict
-- Health bars over anything with Health and MaxHealth attributes.
--
-- Attribute-driven and location-agnostic: it does not know what a breakable is
-- or what an enemy is, only that something published a number. The server sets
-- one value and every client draws it, with no per-player traffic.
--
-- Bars appear on first damage and hide again at full. A world of untouched
-- things shows nothing, which keeps a visible bar meaning "this is being worked
-- on" rather than becoming scenery you stop seeing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)

local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

-- Top-level Workspace folders to watch. Breakables live under Areas, enemies
-- under Enemies, brainrots under Pets, and none is guaranteed to exist when
-- this runs. Adding a folder here is all it takes to give a new kind of thing
-- a health bar - this module never learns what any of them are.
local WATCHED = { "Areas", "Enemies", "Pets", "Plots" }

local WIDTH = 132
local HEIGHT = 34
local BAR_HEIGHT = 10
local VIEW_DISTANCE = 70 -- studs; past this the bar hides itself
local HEIGHT_ABOVE = 2.6 -- studs above the top of whatever it labels

-- Drains green through amber to red. Colour does the "nearly there" work, so
-- the number does not have to be read to know how it is going.
local function healthColor(fraction: number): Color3
	if fraction > 0.5 then
		return Theme.Color.Warning:Lerp(Theme.Color.Positive, (fraction - 0.5) * 2)
	end
	return Theme.Color.Danger:Lerp(Theme.Color.Warning, fraction * 2)
end

type Bar = {
	gui: BillboardGui,
	fill: Frame,
	label: TextLabel,
}

local HealthBars = {}

local bars: { [BasePart]: Bar } = {}
local watched: { [BasePart]: boolean } = {}

-- How high to float the bar. A rig's HumanoidRootPart is a fraction of the
-- height of the body hanging off it, so measuring the part alone would bury the
-- bar inside a zombie's chest.
local function clearance(part: BasePart): number
	local model = part:FindFirstAncestorOfClass("Model")
	if model then
		local _, size = model:GetBoundingBox()
		return size.Y / 2 + HEIGHT_ABOVE
	end
	return part.Size.Y / 2 + HEIGHT_ABOVE
end

local function build(part: BasePart): Bar
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Adornee = part
	gui.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	gui.StudsOffsetWorldSpace = Vector3.new(0, clearance(part), 0)
	gui.MaxDistance = VIEW_DISTANCE
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ResetOnSpawn = false
	gui.Parent = part

	local label = UIKit.label({
		text = "",
		color = Theme.Color.Text,
		size = Theme.TextSize.xs,
		font = Theme.Font.Heavy,
		outline = Theme.Stroke.thin,
	})
	label.Size = UDim2.new(1, 0, 0, HEIGHT - BAR_HEIGHT - 2)
	label.ZIndex = 3
	label.Parent = gui

	local track = UIKit.surface({
		color = Theme.Color.SurfaceSunken,
		radius = Theme.Radius.pill,
		stroke = Theme.Stroke.thin,
		gradient = Theme.Gradient.subtle,
	})
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.fromScale(0.5, 1)
	track.Size = UDim2.new(1, 0, 0, BAR_HEIGHT)
	track.ClipsDescendants = true -- lets the fill keep pill ends while cut short
	track.ZIndex = 2
	track.Parent = gui

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Theme.Color.Positive
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.ZIndex = 3
	fill.Parent = track
	UIKit.corner(fill, Theme.Radius.pill)
	UIKit.gradient(fill, Theme.Gradient.normal)

	return { gui = gui, fill = fill, label = label }
end

local function refresh(part: BasePart)
	local health = part:GetAttribute("Health")
	local maxHealth = part:GetAttribute("MaxHealth")
	if typeof(health) ~= "number" or typeof(maxHealth) ~= "number" or maxHealth <= 0 then
		return
	end

	-- untouched, or dead, or respawned: nothing worth showing
	if health >= maxHealth or health <= 0 then
		local existing = bars[part]
		if existing then
			existing.gui.Enabled = false
		end
		return
	end

	local bar = bars[part]
	if not bar then
		bar = build(part)
		bars[part] = bar
	end

	local fraction = math.clamp(health / maxHealth, 0, 1)
	bar.fill.Size = UDim2.fromScale(fraction, 1)
	bar.fill.BackgroundColor3 = healthColor(fraction)
	bar.label.Text = `{Format.abbreviate(health)} / {Format.abbreviate(maxHealth)}`
	bar.gui.Enabled = true
end

-- Connected unconditionally rather than only for parts that already have the
-- attributes: a breakable is registered by the server after the client has
-- already seen the part, so checking up front would miss every one of them.
local function watch(part: BasePart)
	if watched[part] then
		return
	end
	watched[part] = true

	part:GetAttributeChangedSignal("Health"):Connect(function()
		refresh(part)
	end)
	refresh(part)
end

local function forget(part: BasePart)
	watched[part] = nil
	local bar = bars[part]
	if bar then
		bar.gui:Destroy()
		bars[part] = nil
	end
end

local function bindRoot(root: Instance)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			watch(descendant)
		end
	end

	root.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			watch(descendant)
		end
	end)

	root.DescendantRemoving:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			forget(descendant)
		end
	end)
end

function HealthBars.start()
	for _, name in WATCHED do
		local existing = Workspace:FindFirstChild(name)
		if existing then
			bindRoot(existing)
		end
	end

	-- Workspace.Enemies is created by EnemyService at server start, which may
	-- land either side of this running
	Workspace.ChildAdded:Connect(function(child)
		if table.find(WATCHED, child.Name) then
			bindRoot(child)
		end
	end)
end

return HealthBars
