--!strict
-- Health bars over damaged breakables.
--
-- Reads the Health and MaxHealth attributes BreakableService publishes. Nothing
-- is sent per-player: attributes replicate on their own, so the server sets one
-- number and every client draws it, and two players hitting the same rock see
-- the same bar without either of them being told about the other.
--
-- Bars are built lazily on a rock's first hit and hidden again when it is back
-- to full. A world full of untouched breakables shows nothing at all, which
-- keeps the bar meaning "someone is working on this" rather than being scenery.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)

local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local WIDTH = 132
local HEIGHT = 34
local BAR_HEIGHT = 10
local VIEW_DISTANCE = 70 -- studs; past this the bar hides itself
local HEIGHT_ABOVE = 2.6 -- studs above the top of the part

-- Drains green through amber to red. Colour is doing the "nearly there" work,
-- so the number does not have to be read to know how it is going.
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

local BreakableHealth = {}

local bars: { [BasePart]: Bar } = {}

local function build(part: BasePart): Bar
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Adornee = part
	gui.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	-- half the part's height clears the top of a rock of any size
	gui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + HEIGHT_ABOVE, 0)
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
	track.ZIndex = 2
	track.Parent = gui

	-- ClipsDescendants so the fill can keep its pill ends while being cut off
	-- at whatever width it currently is
	track.ClipsDescendants = true

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

	-- untouched, or respawned: nothing worth showing
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

local function watch(part: BasePart)
	if part:GetAttribute("MaxHealth") == nil then
		return -- not a registered breakable
	end

	part:GetAttributeChangedSignal("Health"):Connect(function()
		refresh(part)
	end)
	refresh(part)
end

local function forget(part: BasePart)
	local bar = bars[part]
	if bar then
		bar.gui:Destroy()
		bars[part] = nil
	end
end

function BreakableHealth.start()
	local areas = Workspace:WaitForChild("Areas", 10)
	if not areas then
		return -- BreakableService already warns about this
	end

	local function bindFolder(folder: Instance)
		for _, descendant in folder:GetDescendants() do
			if descendant:IsA("BasePart") then
				watch(descendant)
			end
		end

		folder.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BasePart") then
				-- the server sets MaxHealth after the part exists, so a part
				-- added now may not be registered for another frame
				task.defer(watch, descendant)
			end
		end)

		folder.DescendantRemoving:Connect(function(descendant)
			if descendant:IsA("BasePart") then
				forget(descendant)
			end
		end)
	end

	for _, area in areas:GetChildren() do
		local folder = area:FindFirstChild("Breakables")
		if folder then
			bindFolder(folder)
		end
	end

	areas.ChildAdded:Connect(function(area)
		local folder = area:WaitForChild("Breakables", 10)
		if folder then
			bindFolder(folder)
		end
	end)
end

return BreakableHealth
