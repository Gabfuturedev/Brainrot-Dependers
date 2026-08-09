--!strict
-- The upgrade printed on the face of its own sign, with a button on it.
--
-- A SurfaceGui rather than a billboard: a billboard turns to face you wherever
-- you stand, which is right for a floating label and wrong for a sign. Painted
-- on the surface it stays part of the world - you walk round to read it, and it
-- sits at whatever angle you built the sign at.
--
-- Lives in PlayerGui with Adornee pointing at the part, not parented to the
-- part. A GUI in Workspace renders perfectly well and never receives input,
-- which is the same trap the egg billboard's buttons fell into.
--
-- Built for your own plot only: every plot has the same signs, and six players
-- worth of other people's levels hanging around the map is noise.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local SkillConfig = require(Shared.Config.SkillConfig)

local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local PLOT_FOLDER = "Plots"
local UPGRADES_FOLDER = "Upgrades"
local PIXELS_PER_STUD = 48 -- canvas resolution; the layout is all scale-based
local DEFAULT_FACE = Enum.NormalId.Top

local player = Players.LocalPlayer

local UpgradeSigns = {}

local levels: { [string]: number } = {}
local coins = 0
local refreshers: { () -> () } = {}

local function hostPartOf(sign: Instance): BasePart?
	if sign:IsA("BasePart") then
		return sign
	end
	if sign:IsA("Model") then
		return sign.PrimaryPart or sign:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

-- Which way the sign reads. An attribute rather than config, because it is a
-- property of how the part was rotated in Studio and nothing else needs to know.
local function faceOf(sign: Instance): Enum.NormalId
	local named = sign:GetAttribute("Face")
	if typeof(named) == "string" then
		local face = (Enum.NormalId :: any)[named]
		if face then
			return face
		end
	end
	return DEFAULT_FACE
end

local function build(sign: Instance, upgradeId: string, playerGui: PlayerGui)
	local upgrade = SkillConfig.get(upgradeId)
	if not upgrade then
		return -- the server already warns about a sign with no config
	end

	local host = hostPartOf(sign)
	if not host then
		return
	end

	local surface = Instance.new("SurfaceGui")
	surface.Name = `Upgrade_{upgradeId}`
	surface.Adornee = host
	surface.Face = faceOf(sign)
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = PIXELS_PER_STUD
	surface.LightInfluence = 0
	surface.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	surface.ResetOnSpawn = false
	surface.Active = true -- off by default, and without it the button is inert
	surface.Parent = playerGui

	local panel = UIKit.surface({
		color = Theme.Color.Surface,
		radius = Theme.Radius.md,
		stroke = Theme.Stroke.thick,
	})
	panel.Size = UDim2.fromScale(1, 1)
	panel.Parent = surface

	-- Everything below is scale-sized, so a sign built 4x6 studs and one built
	-- 8x12 both lay out correctly instead of one clipping.
	local title = UIKit.label({
		text = string.upper(upgrade.displayName),
		color = Theme.Color.Text,
		size = Theme.TextSize.lg,
		font = Theme.Font.Heavy,
		outline = Theme.Stroke.thick,
	})
	title.Position = UDim2.fromScale(0, 0.04)
	title.Size = UDim2.fromScale(1, 0.18)
	title.TextScaled = true
	title.ZIndex = 3
	title.Parent = panel

	local effect = UIKit.label({
		text = "",
		color = Theme.Color.Positive,
		size = Theme.TextSize.md,
		font = Theme.Font.Heavy,
		outline = Theme.Stroke.thin,
	})
	effect.Position = UDim2.fromScale(0.06, 0.24)
	effect.Size = UDim2.fromScale(0.88, 0.16)
	effect.TextScaled = true
	effect.ZIndex = 3
	effect.Parent = panel

	local levelLabel = UIKit.label({
		text = "",
		color = Theme.Color.TextFaint,
		size = Theme.TextSize.sm,
		outline = Theme.Stroke.thin,
	})
	levelLabel.Position = UDim2.fromScale(0, 0.42)
	levelLabel.Size = UDim2.fromScale(1, 0.12)
	levelLabel.TextScaled = true
	levelLabel.ZIndex = 3
	levelLabel.Parent = panel

	local buy = UIKit.button({ text = "", color = Theme.Color.Positive })
	buy.AnchorPoint = Vector2.new(0.5, 1)
	buy.Position = UDim2.fromScale(0.5, 0.94)
	buy.Size = UDim2.fromScale(0.84, 0.3)
	buy.TextScaled = true
	buy.ZIndex = 3
	buy.Parent = panel

	buy.Activated:Connect(function()
		Remotes.get("RequestUpgrade"):FireServer(upgradeId)
	end)

	local function refresh()
		local level = levels[upgradeId] or 0
		local cost = SkillConfig.costOf(upgrade, level)

		-- At level zero the effect line would read "+0%", which describes what
		-- you have rather than what is on sale. Show the pitch instead.
		effect.Text = if level > 0 then SkillConfig.describeLevel(upgrade, level) else upgrade.description
		effect.TextColor3 = if level > 0 then Theme.Color.Positive else Theme.Color.TextMuted

		levelLabel.Text = `LEVEL {level} / {upgrade.maxLevel}`

		if not cost then
			buy.Text = "MAXED"
			buy.BackgroundColor3 = Theme.Color.SurfaceHover
			buy.BackgroundTransparency = 0
			buy.TextTransparency = 0
			buy.Active = false
			return
		end

		local affordable = coins >= cost
		buy.Text = Format.abbreviate(cost)
		buy.BackgroundColor3 = if affordable then Theme.Color.Positive else Theme.Color.SurfaceHover
		buy.BackgroundTransparency = if affordable then 0 else Theme.Transparency.Disabled
		buy.TextTransparency = if affordable then 0 else 0.4
		buy.Active = affordable
	end

	-- A bought upgrade should visibly land on the sign that sold it, not just
	-- change a number.
	local previousLevel = levels[upgradeId] or 0
	table.insert(refreshers, function()
		local level = levels[upgradeId] or 0
		refresh()
		if level > previousLevel then
			panel.Size = UDim2.fromScale(1, 1)
			TweenService:Create(panel, Theme.Motion.Pop, { Size = UDim2.fromScale(1.06, 1.06) }):Play()
			task.delay(Theme.Motion.Pop.Time, function()
				TweenService:Create(panel, Theme.Motion.Pop, { Size = UDim2.fromScale(1, 1) }):Play()
			end)
		end
		previousLevel = level
	end)

	refresh()
end

-- The plot is claimed a moment after joining, so this retries rather than
-- resolving once and giving up - the mistake that made the egg billboards
-- vanish at random.
local function waitForOwnPlot(): Instance
	while true do
		local folder = Workspace:FindFirstChild(PLOT_FOLDER)
		if folder then
			for _, plot in folder:GetChildren() do
				if plot:GetAttribute("OwnerUserId") == player.UserId then
					return plot
				end
			end
		end
		task.wait(0.5)
	end
end

local function refreshAll()
	for _, refresh in refreshers do
		refresh()
	end
end

function UpgradeSigns.start()
	local playerGui = player:WaitForChild("PlayerGui")

	Remotes.get("SkillsUpdated").OnClientEvent:Connect(function(newLevels)
		if typeof(newLevels) ~= "table" then
			return
		end
		levels = newLevels
		refreshAll()
	end)

	-- affordability is why the buttons are live, so track the count the server
	-- already replicates rather than duplicating it
	task.spawn(function()
		local leaderstats = player:WaitForChild("leaderstats", 20)
		local value = leaderstats and leaderstats:FindFirstChild("Coins")
		if not value or not value:IsA("IntValue") then
			return
		end

		coins = value.Value
		refreshAll()
		value.Changed:Connect(function(amount)
			coins = amount
			refreshAll()
		end)
	end)

	task.spawn(function()
		local plot = waitForOwnPlot()

		local folder = plot:WaitForChild(UPGRADES_FOLDER, 10)
		if not folder then
			warn(`[UpgradeSigns] plot '{plot.Name}' has no {UPGRADES_FOLDER} folder - no signs to label`)
			return
		end

		for _, sign in folder:GetChildren() do
			build(sign, sign.Name, playerGui)
		end
		folder.ChildAdded:Connect(function(sign)
			build(sign, sign.Name, playerGui)
		end)
	end)
end

return UpgradeSigns
