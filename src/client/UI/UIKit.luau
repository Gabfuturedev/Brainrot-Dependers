--!strict
-- Builders for the look described in Theme. Every panel and button in the game
-- comes from here, which is the only way the look stays consistent once there
-- are a dozen screens.
--
-- These return plain Instances rather than a component tree on purpose: the
-- imperative panels can use them today, and a React port can call the same
-- functions from inside a ref, so adopting React later is not a rewrite of the
-- visual language too.

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local UIKit = {}

-- Rounds a corner. Passing Theme.Radius.pill gives a capsule, since UICorner
-- clamps a scale radius to half the shorter side.
function UIKit.corner(parent: GuiObject, radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or Theme.Radius.md)
	corner.Parent = parent
	return corner
end

-- The near-black outline that every surface gets. This is the single biggest
-- difference between "Roblox game" and "web dashboard" - without it, saturated
-- fills sit on the background with nothing separating them and read as flat.
function UIKit.stroke(parent: GuiObject, thickness: number?, color: Color3?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.Color.Outline
	stroke.Thickness = thickness or Theme.Stroke.thin
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

-- Vertical light-to-dark. UIGradient multiplies the parent's BackgroundColor3,
-- so `strength` is a brightness multiplier at the bottom edge and one call
-- works for every colour in the palette.
function UIKit.gradient(parent: GuiObject, strength: number?): UIGradient
	local low = strength or Theme.Gradient.normal

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.new(low, low, low)),
	})
	gradient.Parent = parent
	return gradient
end

function UIKit.padding(parent: GuiObject, all: number): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, all)
	padding.PaddingBottom = UDim.new(0, all)
	padding.PaddingLeft = UDim.new(0, all)
	padding.PaddingRight = UDim.new(0, all)
	padding.Parent = parent
	return padding
end

-- Outlines text the same way surfaces are outlined. Roblox's built-in
-- TextStroke is a single hairline pixel and vanishes on a busy 3D background;
-- a real UIStroke can be thick enough to actually read.
function UIKit.textStroke(label: TextLabel | TextButton, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Color.Outline
	stroke.Thickness = thickness or Theme.Stroke.thin
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	return stroke
end

-- Hard offset shadow, as a child rather than a sibling so it tracks the
-- parent's size and position for free - which matters because things here get
-- tweened. Needs the ScreenGui on ZIndexBehavior.Sibling for the lower ZIndex
-- to actually render behind.
function UIKit.shadow(parent: GuiObject, offset: number?): Frame
	local distance = offset or 5

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = Vector2.zero
	shadow.Position = UDim2.fromOffset(distance, distance)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.BackgroundColor3 = Theme.Color.Shadow
	shadow.BorderSizePixel = 0
	shadow.ZIndex = parent.ZIndex - 1
	shadow.Parent = parent

	UIKit.corner(shadow, Theme.Radius.md)
	return shadow
end

export type SurfaceProps = {
	color: Color3?,
	radius: number?,
	stroke: number?,
	gradient: number?,
	shadow: number?,
}

-- A filled, outlined, gradiented rectangle: the base every panel, card and row
-- is built from.
function UIKit.surface(props: SurfaceProps): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = props.color or Theme.Color.Surface
	frame.BorderSizePixel = 0
	frame.ZIndex = 2 -- leaves room beneath for shadow()

	UIKit.corner(frame, props.radius or Theme.Radius.lg)
	UIKit.stroke(frame, props.stroke or Theme.Stroke.thick)
	UIKit.gradient(frame, props.gradient)

	if props.shadow then
		UIKit.shadow(frame, props.shadow)
	end

	return frame
end

export type ButtonProps = {
	text: string,
	color: Color3?,
	textColor: Color3?,
	textSize: number?,
	radius: number?,
	size: UDim2?,
}

-- Buttons get the strong gradient and the thick stroke. They are the loudest
-- thing on any screen by design; if a button does not look pressable at a
-- glance, players do not press it.
function UIKit.button(props: ButtonProps): TextButton
	local base = props.color or Theme.Color.Primary

	local button = Instance.new("TextButton")
	button.BackgroundColor3 = base
	button.BorderSizePixel = 0
	button.AutoButtonColor = false -- hover is handled below, with motion
	button.Font = Theme.Font.Regular
	button.Text = props.text
	button.TextColor3 = props.textColor or Theme.Color.OnAccent
	button.TextSize = props.textSize or Theme.TextSize.sm
	button.ZIndex = 2

	if props.size then
		button.Size = props.size
	end

	UIKit.corner(button, props.radius or Theme.Radius.md)
	UIKit.stroke(button, Theme.Stroke.thick)
	UIKit.gradient(button, Theme.Gradient.strong)
	UIKit.textStroke(button, Theme.Stroke.thin)

	-- Brighten and lift on hover. Scaling the button itself would fight any
	-- layout it sits in, so this only touches colour.
	button.MouseEnter:Connect(function()
		TweenService:Create(button, Theme.Motion.Fast, {
			BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.18),
		}):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, Theme.Motion.Fast, { BackgroundColor3 = base }):Play()
	end)

	return button
end

export type LabelProps = {
	text: string,
	color: Color3?,
	size: number?,
	font: Enum.Font?,
	align: Enum.TextXAlignment?,
	outline: number?,
}

function UIKit.label(props: LabelProps): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = props.font or Theme.Font.Regular
	label.Text = props.text
	label.TextColor3 = props.color or Theme.Color.Text
	label.TextSize = props.size or Theme.TextSize.md
	label.TextXAlignment = props.align or Enum.TextXAlignment.Center
	label.ZIndex = 2

	if props.outline then
		UIKit.textStroke(label, props.outline)
	end

	return label
end

-- Scale-in from slightly small. Called on anything that appears: the overshoot
-- is what makes a panel feel like it arrived rather than switched on.
function UIKit.popIn(object: GuiObject, finalSize: UDim2)
	object.Size = UDim2.fromOffset(0, 0)
	TweenService:Create(object, Theme.Motion.Enter, { Size = finalSize }):Play()
end

return UIKit
