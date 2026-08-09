--!strict
-- Design tokens. Every colour, gap, radius and text size comes from here.
--
-- The genre matters more than the individual values. Roblox game UI is loud:
-- saturated fills, near-black outlines on everything, vertical gradients, fat
-- corners, oversized bold type, bouncy motion. Restraint reads as unfinished to
-- this audience - a thin grey 1px border on a muted card looks like a settings
-- menu, not like something you want to click.
--
-- Two rules hold the look together:
--   every surface gets Outline, at Stroke.thin or thicker
--   every surface gets a gradient, because a flat fill is the tell
--
-- Deliberately pure data with no Instance helpers - UIKit builds things, this
-- only describes them, so React components can read the same tokens later.

local Theme = {}

Theme.Color = {
	-- Deep indigo rather than neutral grey. A coloured dark reads as chosen;
	-- neutral grey reads as nobody having picked anything.
	Shadow = Color3.fromRGB(14, 12, 28),
	Outline = Color3.fromRGB(20, 17, 38), -- near-black; every stroke is this
	Surface = Color3.fromRGB(46, 42, 82), -- panel body
	SurfaceRaised = Color3.fromRGB(64, 58, 112), -- cards and rows on a panel
	SurfaceSunken = Color3.fromRGB(34, 31, 62), -- wells, list backgrounds
	SurfaceHover = Color3.fromRGB(82, 74, 140),

	Text = Color3.fromRGB(255, 255, 255),
	TextMuted = Color3.fromRGB(188, 182, 226),
	TextFaint = Color3.fromRGB(134, 128, 176),

	-- Named by meaning, not hue, so a button's colour follows from what it
	-- does. Danger is the only red in the palette for exactly that reason.
	Primary = Color3.fromRGB(96, 140, 255),
	Positive = Color3.fromRGB(74, 204, 118),
	Warning = Color3.fromRGB(255, 164, 56),
	Danger = Color3.fromRGB(240, 78, 88),
	Coin = Color3.fromRGB(255, 206, 66), -- matches the drop part in DropService
	OnAccent = Color3.fromRGB(255, 255, 255),
}

Theme.Transparency = {
	Scrim = 0.35,
	Disabled = 0.6,
}

-- Chunky. These are roughly double a desktop app's, which is what makes a
-- button look pressable rather than like a table cell.
Theme.Radius = {
	sm = 8,
	md = 12,
	lg = 20,
	pill = 999, -- UICorner clamps to half the height
}

Theme.Stroke = {
	thin = 2, -- rows, chips, small controls
	thick = 3, -- panels, buttons, anything you click
	heavy = 4, -- modals and hero elements
}

-- How far a gradient darkens toward the bottom, as a brightness multiplier.
-- UIGradient multiplies the parent's BackgroundColor3, so one value works for
-- every colour in the palette - no per-colour gradient definitions.
Theme.Gradient = {
	subtle = 0.86,
	normal = 0.74,
	strong = 0.58,
}

-- 4pt scale. Sticking to it does more for coherence than the colours do.
Theme.Space = {
	xs = 4,
	sm = 8,
	md = 12,
	lg = 18,
	xl = 26,
	xxl = 38,
}

-- Uploaded sprites, blank until they exist.
--
-- Everything that reads these falls back to a drawn shape, so the UI works
-- without any of them and gets better the moment one lands - same rule as the
-- sound ids. Upload them WHITE or greyscale: they are tinted with ImageColor3
-- at runtime, and a coloured sprite cannot be recoloured.
Theme.Image = {
	-- A filled hexagon, transparent background. Roblox has no hexagon
	-- primitive, so this is the only way to get the skill-tree tile shape.
	-- Asset type 1 (Image), not 13 (Decal) - an ImageLabel will not render a
	-- decal id, which is the usual reason a pasted id shows nothing.
	HexNode = "rbxassetid://3113323162",
}

Theme.Font = {
	Regular = Enum.Font.GothamBold, -- yes, bold: nothing here is body copy
	Heavy = Enum.Font.GothamBlack,
}

Theme.TextSize = {
	xs = 13,
	sm = 15,
	md = 18,
	lg = 24,
	xl = 34,
	hero = 46,
}

-- Back easing on anything that appears. Overshoot is most of what separates
-- "game" from "form" - a panel that scales past its size and settles reads as
-- physical, where a linear fade reads as a loading screen.
Theme.Motion = {
	Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Normal = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Pop = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Enter = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
}

return Theme
