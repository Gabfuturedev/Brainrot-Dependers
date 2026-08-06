--!strict
-- Element versions of UIKit, for React panels.
--
-- UIKit builds Instances and is what the imperative panels use; this returns
-- elements for the same visual language, so both halves of the UI look
-- identical while we migrate one panel at a time. Both read Theme, so there is
-- still exactly one place a colour or radius is defined.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages.React)

local Theme = require(script.Parent.Theme)

local e = React.createElement

local ReactKit = {}

function ReactKit.corner(radius: number?)
	return e("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Radius.md) })
end

function ReactKit.stroke(thickness: number?, color: Color3?)
	return e("UIStroke", {
		Color = color or Theme.Color.Outline,
		Thickness = thickness or Theme.Stroke.thin,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

-- Vertical light-to-dark. UIGradient multiplies the parent's BackgroundColor3,
-- so one strength works for every colour in the palette.
function ReactKit.gradient(strength: number?)
	local low = strength or Theme.Gradient.normal
	return e("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.new(low, low, low)),
		}),
	})
end

-- Roblox's built-in TextStroke is one hairline pixel; this is thick enough to
-- actually read against a bright 3D background.
function ReactKit.textStroke(thickness: number?)
	return e("UIStroke", {
		Color = Theme.Color.Outline,
		Thickness = thickness or Theme.Stroke.thin,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

function ReactKit.padding(all: number)
	return e("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, all),
		PaddingRight = UDim.new(0, all),
	})
end

function ReactKit.listLayout(props: {
	horizontal: boolean?,
	padding: number?,
	align: Enum.HorizontalAlignment?,
	vertical: Enum.VerticalAlignment?,
})
	return e("UIListLayout", {
		FillDirection = if props.horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, props.padding or Theme.Space.sm),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = props.align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = props.vertical or Enum.VerticalAlignment.Top,
	})
end

-- The three decorations every surface gets, as a children table ready to be
-- merged into a component's own children.
function ReactKit.surfaceParts(radius: number?, strokeThickness: number?, strokeColor: Color3?, gradient: number?)
	return {
		Corner = ReactKit.corner(radius),
		Stroke = ReactKit.stroke(strokeThickness, strokeColor),
		Gradient = ReactKit.gradient(gradient),
	}
end

-- Luau has no table spread, and children tables are built by hand often enough
-- here that a merge helper stops every component repeating the same loop.
function ReactKit.merge(into: { [any]: any }, from: { [any]: any }): { [any]: any }
	for key, value in from do
		into[key] = value
	end
	return into
end

return ReactKit
