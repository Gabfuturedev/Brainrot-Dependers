--!strict
-- Pet inventory panel: equip, unequip, delete, and bulk delete by rarity. The
-- server is authoritative; this renders what it sends and asks for changes.
--
-- React, unlike the rest of the UI, for two reasons that are specific to this
-- panel rather than general enthusiasm:
--
--   The old version destroyed and rebuilt every row on each update, which reset
--   the scroll position. Deleting a pet from the bottom of a 200-item list threw
--   you back to the top. Keying rows by pet id lets React patch in place.
--
--   The two-click delete confirm needed a hand-rolled generation counter to stop
--   a stale timer disarming a newly armed button. That is what useEffect cleanup
--   does for free, and getting it right by hand is a bug waiting to happen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages.React)
local ReactRoblox = require(Packages.ReactRoblox)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared.Config.PetConfig)
local Remotes = require(Shared.Remotes)

local ReactKit = require(script.Parent.ReactKit)
local Theme = require(script.Parent.Theme)

local e = React.createElement

local TOGGLE_KEY = Enum.KeyCode.P
local ROW_HEIGHT = 56
local ARM_TIME = 3 -- seconds an armed bulk-delete button waits before giving up
local NEARLY_FULL = 0.9 -- fraction of the cap at which the counter starts warning
local ALL_KEY = "\0all" -- sentinel for the "everything" bulk button; no rarity can collide

local player = Players.LocalPlayer

local PetInventory = {}

type Entry = {
	id: string,
	name: string,
	displayName: string,
	rarity: string,
	damage: number,
	equipped: boolean,
}

--------------------------------------------------------------------------------

type ButtonProps = {
	text: string,
	color: Color3,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	layoutOrder: number?,
	textSize: number?,
	enabled: boolean?,
	onClick: () -> (),
}

local function Button(props: ButtonProps)
	local enabled = props.enabled ~= false

	return e("TextButton", {
		BackgroundColor3 = props.color,
		BackgroundTransparency = if enabled then 0 else Theme.Transparency.Disabled,
		BorderSizePixel = 0,
		AutoButtonColor = enabled,
		Text = props.text,
		Font = Theme.Font.Regular,
		TextColor3 = Theme.Color.Text,
		TextSize = props.textSize or Theme.TextSize.xs,
		TextTransparency = if enabled then 0 else 0.4,
		Size = props.size,
		Position = props.position,
		AnchorPoint = props.anchor,
		LayoutOrder = props.layoutOrder,
		Active = enabled,
		ZIndex = 3,
		[React.Event.Activated] = function()
			if enabled then
				props.onClick()
			end
		end,
	}, {
		Corner = ReactKit.corner(Theme.Radius.sm),
		Stroke = ReactKit.stroke(Theme.Stroke.thin),
		Gradient = ReactKit.gradient(Theme.Gradient.strong),
		Label = ReactKit.textStroke(Theme.Stroke.thin),
	})
end

--------------------------------------------------------------------------------

type RowProps = {
	entry: Entry,
	canEquip: boolean,
	layoutOrder: number,
	onEquip: () -> (),
	onDelete: () -> (),
}

local function PetRow(props: RowProps)
	local entry = props.entry
	local accent = PetConfig.RarityColors[entry.rarity] or Theme.Color.TextMuted

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundColor3 = if entry.equipped then Theme.Color.SurfaceHover else Theme.Color.SurfaceRaised,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		ZIndex = 2,
	}, {
		Corner = ReactKit.corner(Theme.Radius.md),
		-- equipped rows are outlined in their rarity colour rather than given a
		-- different fill, so "which are equipped" survives a glance
		Stroke = ReactKit.stroke(
			if entry.equipped then Theme.Stroke.thick else Theme.Stroke.thin,
			if entry.equipped then accent else Theme.Color.Outline
		),
		Gradient = ReactKit.gradient(Theme.Gradient.subtle),

		Pip = e("Frame", {
			Position = UDim2.fromOffset(10, 12),
			Size = UDim2.fromOffset(8, ROW_HEIGHT - 24),
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, {
			Corner = ReactKit.corner(Theme.Radius.pill),
			Stroke = ReactKit.stroke(Theme.Stroke.thin),
		}),

		Name = e("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(28, 8),
			Size = UDim2.new(1, -196, 0, 22),
			Font = Theme.Font.Heavy,
			Text = entry.displayName,
			TextColor3 = accent,
			TextSize = Theme.TextSize.sm,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 3,
		}, { Stroke = ReactKit.textStroke(Theme.Stroke.thin) }),

		Damage = e("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(28, 28),
			Size = UDim2.new(1, -196, 0, 18),
			Font = Theme.Font.Regular,
			Text = `{entry.damage} DMG`,
			TextColor3 = Theme.Color.TextMuted,
			TextSize = Theme.TextSize.xs,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		}),

		Action = e(Button, {
			text = if entry.equipped then "UNEQUIP" else "EQUIP",
			color = if entry.equipped then Theme.Color.Warning else Theme.Color.Positive,
			size = UDim2.fromOffset(92, 34),
			position = UDim2.new(1, -54, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			enabled = props.canEquip,
			onClick = props.onEquip,
		}),

		Delete = e(Button, {
			text = "X",
			color = Theme.Color.Danger,
			size = UDim2.fromOffset(38, 34),
			position = UDim2.new(1, -10, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			textSize = Theme.TextSize.sm,
			onClick = props.onDelete,
		}),
	})
end

--------------------------------------------------------------------------------

local function App()
	local entries: { Entry }, setEntries = React.useState({} :: { Entry })
	local maxEquipped, setMaxEquipped = React.useState(3)
	local maxOwned, setMaxOwned = React.useState(200)
	local open, setOpen = React.useState(false)
	local armed: string?, setArmed = React.useState(nil :: string?)

	React.useEffect(function()
		local connection = Remotes.get("InventoryUpdated").OnClientEvent:Connect(
			function(newEntries, newMaxEquipped, newMaxOwned)
				setEntries(if typeof(newEntries) == "table" then newEntries else {})
				if typeof(newMaxEquipped) == "number" then
					setMaxEquipped(newMaxEquipped)
				end
				if typeof(newMaxOwned) == "number" then
					setMaxOwned(newMaxOwned)
				end
				-- the counts on an armed button were what the player was
				-- agreeing to, so any change invalidates the confirmation
				setArmed(nil)
			end
		)
		return function()
			connection:Disconnect()
		end
	end, {})

	React.useEffect(function()
		local connection = UserInputService.InputBegan:Connect(function(input, processedByUI)
			if not processedByUI and input.KeyCode == TOGGLE_KEY then
				setOpen(function(previous)
					return not previous
				end)
			end
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	-- The whole reason this panel is in React. Arming a different button
	-- re-runs this effect, whose cleanup cancels the previous timer - which is
	-- exactly what the old hand-rolled generation counter was faking.
	React.useEffect(function()
		if not armed then
			return
		end

		local cancelled = false
		task.delay(ARM_TIME, function()
			if not cancelled then
				setArmed(nil)
			end
		end)

		return function()
			cancelled = true
		end
	end, { armed })

	local equippedCount = React.useMemo(function()
		local count = 0
		for _, entry in entries do
			if entry.equipped then
				count += 1
			end
		end
		return count
	end, { entries })

	-- Unequipped pets grouped by rarity: the only ones bulk delete will touch.
	-- Ordered by the weakest pet in each group, since PetConfig has no rarity
	-- ordering and the group you most want to clear belongs on the left.
	local bulk = React.useMemo(function()
		local counts: { [string]: number } = {}
		local weakest: { [string]: number } = {}
		local order: { string } = {}
		local total = 0

		for _, entry in entries do
			if entry.equipped then
				continue
			end
			total += 1
			if counts[entry.rarity] then
				counts[entry.rarity] += 1
				weakest[entry.rarity] = math.min(weakest[entry.rarity], entry.damage)
			else
				counts[entry.rarity] = 1
				weakest[entry.rarity] = entry.damage
				table.insert(order, entry.rarity)
			end
		end

		table.sort(order, function(a, b)
			if weakest[a] == weakest[b] then
				return a < b
			end
			return weakest[a] < weakest[b]
		end)

		return { counts = counts, order = order, total = total }
	end, { entries })

	local function fireBulk(key: string, rarity: string?)
		if armed == key then
			setArmed(nil)
			Remotes.get("RequestBulkDelete"):FireServer(rarity)
		else
			setArmed(key)
		end
	end

	-- rows keyed by pet id, which is what keeps the scroll position across an
	-- update instead of the list being torn down and rebuilt
	local rows: { [string]: any } = {}
	for index, entry in entries do
		rows[entry.id] = e(PetRow, {
			entry = entry,
			canEquip = entry.equipped or equippedCount < maxEquipped,
			layoutOrder = index,
			onEquip = function()
				Remotes.get("RequestEquip"):FireServer(entry.id, not entry.equipped)
			end,
			onDelete = function()
				Remotes.get("RequestDeletePet"):FireServer(entry.id)
			end,
		})
	end
	rows.Layout = ReactKit.listLayout({ padding = Theme.Space.sm })

	local bulkChildren: { [any]: any } = {
		Layout = ReactKit.listLayout({ horizontal = true, padding = Theme.Space.sm, vertical = Enum.VerticalAlignment.Center }),
	}

	if bulk.total > 0 then
		bulkChildren.Hint = e("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(0, 30),
			Font = Theme.Font.Regular,
			Text = "CLEAR",
			TextColor3 = Theme.Color.TextFaint,
			TextSize = Theme.TextSize.xs,
			LayoutOrder = 0,
			ZIndex = 3,
		})

		for index, rarity in bulk.order do
			local key = rarity
			local accent = PetConfig.RarityColors[rarity] or Theme.Color.Danger
			bulkChildren[`bulk_{rarity}`] = e(Button, {
				text = if armed == key then "SURE?" else `{string.upper(rarity)} {bulk.counts[rarity]}`,
				color = if armed == key then Theme.Color.Danger else accent:Lerp(Theme.Color.Surface, 0.55),
				size = UDim2.fromOffset(if armed == key then 86 else 108, 30),
				layoutOrder = index,
				onClick = function()
					fireBulk(key, rarity)
				end,
			})
		end

		if #bulk.order > 1 then
			bulkChildren.bulk_all = e(Button, {
				text = if armed == ALL_KEY then "SURE?" else `ALL {bulk.total}`,
				color = if armed == ALL_KEY then Theme.Color.Danger else Theme.Color.Danger:Lerp(Theme.Color.Surface, 0.4),
				size = UDim2.fromOffset(86, 30),
				layoutOrder = #bulk.order + 1,
				onClick = function()
					fireBulk(ALL_KEY, nil)
				end,
			})
		end
	end

	local owned = #entries
	local capacityColor = if owned >= maxOwned
		then Theme.Color.Danger
		elseif owned >= maxOwned * NEARLY_FULL then Theme.Color.Warning
		else Theme.Color.TextFaint

	return e(React.Fragment, nil, {
		Toggle = e(Button, {
			text = `PETS {equippedCount}/{maxEquipped}`,
			color = Theme.Color.Primary,
			size = UDim2.fromOffset(138, 50),
			position = UDim2.new(0, 16, 1, -16),
			anchor = Vector2.new(0, 1),
			textSize = Theme.TextSize.sm,
			onClick = function()
				setOpen(function(previous)
					return not previous
				end)
			end,
		}),

		Panel = e("Frame", {
			Visible = open,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(470, 470),
			BackgroundColor3 = Theme.Color.Surface,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, {
			Corner = ReactKit.corner(Theme.Radius.lg),
			Stroke = ReactKit.stroke(Theme.Stroke.heavy),
			Gradient = ReactKit.gradient(Theme.Gradient.subtle),

			Title = e("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(20, 14),
				Size = UDim2.new(1, -220, 0, 32),
				Font = Theme.Font.Heavy,
				Text = "PETS",
				TextColor3 = Theme.Color.Text,
				TextSize = Theme.TextSize.lg,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 3,
			}, { Stroke = ReactKit.textStroke(Theme.Stroke.thick) }),

			-- worth showing before they hit the cap, because the first sign
			-- otherwise is an egg prompt that refuses to hatch
			Capacity = e("TextLabel", {
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Position = UDim2.new(1, -62, 0, 18),
				Size = UDim2.fromOffset(150, 26),
				Font = Theme.Font.Regular,
				Text = `{owned} / {maxOwned}`,
				TextColor3 = capacityColor,
				TextSize = Theme.TextSize.xs,
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 3,
			}),

			Close = e(Button, {
				text = "X",
				color = Theme.Color.SurfaceHover,
				size = UDim2.fromOffset(38, 34),
				position = UDim2.new(1, -16, 0, 14),
				anchor = Vector2.new(1, 0),
				textSize = Theme.TextSize.sm,
				onClick = function()
					setOpen(false)
				end,
			}),

			BulkBar = e("ScrollingFrame", {
				Position = UDim2.fromOffset(16, 56),
				Size = UDim2.new(1, -32, 0, 32),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 3,
				ScrollingDirection = Enum.ScrollingDirection.X,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.X,
				ZIndex = 3,
			}, bulkChildren),

			List = e("ScrollingFrame", {
				Position = UDim2.fromOffset(16, 96),
				Size = UDim2.new(1, -32, 1, -112),
				BackgroundColor3 = Theme.Color.SurfaceSunken,
				BackgroundTransparency = 0.35,
				BorderSizePixel = 0,
				ScrollBarThickness = 5,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ZIndex = 3,
			}, {
				Corner = ReactKit.corner(Theme.Radius.md),
				Padding = ReactKit.padding(Theme.Space.sm),
				Rows = e("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
				}, rows),
			}),
		}),
	})
end

--------------------------------------------------------------------------------

function PetInventory.start()
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "PetInventory"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	ReactRoblox.createRoot(gui):render(e(App))
end

return PetInventory
