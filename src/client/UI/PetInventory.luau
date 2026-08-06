--!strict
-- Pet inventory: a grid of cards with a detail pane, plus equip-best and bulk
-- delete. The server is authoritative; this renders what it sends.
--
-- Grid rather than a list because a list wastes most of the panel on empty
-- space per row, and because selecting into a detail pane solves a real
-- problem: a ViewportFrame is its own render pass, so one preview of the
-- selected pet costs the same whether you own eight pets or two hundred.
-- Putting a preview on every card would not.
--
-- React, unlike the rest of the UI, for two reasons specific to this panel:
--
--   The old version destroyed and rebuilt every row on each update, resetting
--   the scroll position. Keying cards by pet id lets React patch in place.
--
--   The two-click delete confirm needed a hand-rolled generation counter to
--   stop a stale timer disarming a newly armed button. That is what useEffect
--   cleanup does for free.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages.React)
local ReactRoblox = require(Packages.ReactRoblox)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared.Config.PetConfig)
local Remotes = require(Shared.Remotes)

local PetViewport = require(script.Parent.PetViewport)
local ReactKit = require(script.Parent.ReactKit)
local Theme = require(script.Parent.Theme)

local e = React.createElement

local TOGGLE_KEY = Enum.KeyCode.P
local ARM_TIME = 3 -- seconds an armed bulk-delete button waits before giving up
local NEARLY_FULL = 0.9 -- fraction of the cap at which the counter starts warning
local ALL_KEY = "\0all" -- sentinel for the "everything" bulk button
local CELL = Vector2.new(96, 112)
local PANEL = UDim2.fromOffset(646, 494)
local DETAIL_WIDTH = 196

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
		ZIndex = 4,
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

type CardProps = {
	entry: Entry,
	selected: boolean,
	layoutOrder: number,
	onSelect: () -> (),
}

local function PetCard(props: CardProps)
	local entry = props.entry
	local accent = PetConfig.RarityColors[entry.rarity] or Theme.Color.TextMuted

	-- Selection is the thicker outline, equipped is the badge. Keeping them on
	-- different channels means a card can show both at once without ambiguity.
	local outlineColor = if props.selected then Theme.Color.Text else accent
	local outlineWidth = if props.selected then Theme.Stroke.heavy else Theme.Stroke.thin

	local children: { [any]: any } = {
		Corner = ReactKit.corner(Theme.Radius.md),
		Stroke = ReactKit.stroke(outlineWidth, outlineColor),
		Gradient = ReactKit.gradient(Theme.Gradient.subtle),

		-- A rarity-tinted initial rather than a model preview: see the note at
		-- the top about viewports being a per-instance render pass.
		Initial = e("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 46),
			Font = Theme.Font.Heavy,
			Text = string.sub(entry.displayName, 1, 1),
			TextColor3 = accent,
			TextSize = Theme.TextSize.xl,
			ZIndex = 3,
		}, { Stroke = ReactKit.textStroke(Theme.Stroke.thick) }),

		Name = e("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(4, 56),
			Size = UDim2.new(1, -8, 0, 30),
			Font = Theme.Font.Regular,
			Text = entry.displayName,
			TextColor3 = Theme.Color.Text,
			TextSize = Theme.TextSize.xs,
			TextWrapped = true,
			ZIndex = 3,
		}),

		Damage = e("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 88),
			Size = UDim2.new(1, 0, 0, 18),
			Font = Theme.Font.Regular,
			Text = `{entry.damage}`,
			TextColor3 = accent,
			TextSize = Theme.TextSize.xs,
			ZIndex = 3,
		}),
	}

	if entry.equipped then
		children.Badge = e("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -5, 0, 5),
			Size = UDim2.fromOffset(20, 20),
			BackgroundColor3 = Theme.Color.Positive,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, {
			Corner = ReactKit.corner(Theme.Radius.pill),
			Stroke = ReactKit.stroke(Theme.Stroke.thin),
			Mark = e("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Font = Theme.Font.Heavy,
				Text = "E",
				TextColor3 = Theme.Color.Text,
				TextSize = Theme.TextSize.xs,
				ZIndex = 5,
			}),
		})
	end

	return e("TextButton", {
		BackgroundColor3 = if props.selected then Theme.Color.SurfaceHover else Theme.Color.SurfaceRaised,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder,
		ZIndex = 2,
		[React.Event.Activated] = props.onSelect,
	}, children)
end

--------------------------------------------------------------------------------

local function App()
	local entries: { Entry }, setEntries = React.useState({} :: { Entry })
	local maxEquipped, setMaxEquipped = React.useState(3)
	local maxOwned, setMaxOwned = React.useState(200)
	local open, setOpen = React.useState(false)
	local armed: string?, setArmed = React.useState(nil :: string?)
	local selectedId: string?, setSelectedId = React.useState(nil :: string?)

	local previewRef = React.useRef(nil :: Frame?)

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
				-- the counts on an armed button were what the player agreed to
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

	-- The reason this panel is in React: arming a different button re-runs this
	-- effect, and its cleanup cancels the previous timer. The old hand-rolled
	-- generation counter was faking exactly this.
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

	local selected = React.useMemo(function()
		for _, entry in entries do
			if entry.id == selectedId then
				return entry
			end
		end
		return nil
	end, { entries, selectedId } :: { any })

	-- One viewport, rebuilt only when the selection actually changes. Mounted
	-- imperatively because PetViewport hands back an Instance, and there is no
	-- sense rewriting a working camera rig as a component just to place it.
	React.useEffect(function()
		local container = previewRef.current
		if not container then
			return
		end

		for _, child in container:GetChildren() do
			if child:IsA("ViewportFrame") then
				child:Destroy()
			end
		end

		if not selected then
			return
		end

		local stats = PetConfig.get(selected.name)
		local viewport = if stats then PetViewport.create(stats.model) else nil
		if viewport then
			viewport.Size = UDim2.fromScale(1, 1)
			viewport.ZIndex = 4
			viewport.Parent = container
		end
	end, { selected } :: { any })

	local equippedCount = React.useMemo(function()
		local count = 0
		for _, entry in entries do
			if entry.equipped then
				count += 1
			end
		end
		return count
	end, { entries })

	-- Unequipped pets grouped by rarity: the only ones bulk delete touches.
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

	-- cards keyed by pet id, which is what holds the scroll position across an
	-- update instead of the grid being torn down and rebuilt
	local cards: { [any]: any } = {
		Layout = e("UIGridLayout", {
			CellSize = UDim2.fromOffset(CELL.X, CELL.Y),
			CellPadding = UDim2.fromOffset(Theme.Space.sm, Theme.Space.sm),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for index, entry in entries do
		cards[entry.id] = e(PetCard, {
			entry = entry,
			selected = entry.id == selectedId,
			layoutOrder = index,
			onSelect = function()
				setSelectedId(entry.id)
			end,
		})
	end

	local bulkChildren: { [any]: any } = {
		Layout = ReactKit.listLayout({
			horizontal = true,
			padding = Theme.Space.sm,
			vertical = Enum.VerticalAlignment.Center,
		}),
		EquipBest = e(Button, {
			text = "EQUIP BEST",
			color = Theme.Color.Primary,
			size = UDim2.fromOffset(108, 30),
			layoutOrder = 0,
			onClick = function()
				Remotes.get("RequestEquipBest"):FireServer()
			end,
		}),
	}

	for index, rarity in bulk.order do
		local key = rarity
		local accent = PetConfig.RarityColors[rarity] or Theme.Color.Danger
		bulkChildren[`bulk_{rarity}`] = e(Button, {
			text = if armed == key then "SURE?" else `{string.upper(rarity)} {bulk.counts[rarity]}`,
			color = if armed == key then Theme.Color.Danger else accent:Lerp(Theme.Color.Surface, 0.55),
			size = UDim2.fromOffset(if armed == key then 82 else 106, 30),
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
			size = UDim2.fromOffset(82, 30),
			layoutOrder = #bulk.order + 1,
			onClick = function()
				fireBulk(ALL_KEY, nil)
			end,
		})
	end

	local owned = #entries
	local capacityColor = if owned >= maxOwned
		then Theme.Color.Danger
		elseif owned >= maxOwned * NEARLY_FULL then Theme.Color.Warning
		else Theme.Color.TextFaint

	local selectedAccent = if selected
		then (PetConfig.RarityColors[selected.rarity] or Theme.Color.TextMuted)
		else Theme.Color.TextFaint

	local canEquipSelected = selected ~= nil and (selected.equipped or equippedCount < maxEquipped)

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
			Size = PANEL,
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
				Size = UDim2.new(1, -260, 0, 32),
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
				Size = UDim2.fromOffset(160, 26),
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

			Toolbar = e("ScrollingFrame", {
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

			Grid = e("ScrollingFrame", {
				Position = UDim2.fromOffset(16, 96),
				Size = UDim2.new(1, -32 - DETAIL_WIDTH - Theme.Space.md, 1, -112),
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
				Cells = e("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
				}, cards),
			}),

			Detail = e("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -16, 0, 96),
				Size = UDim2.new(0, DETAIL_WIDTH, 1, -112),
				BackgroundColor3 = Theme.Color.SurfaceSunken,
				BackgroundTransparency = 0.35,
				BorderSizePixel = 0,
				ZIndex = 3,
			}, {
				Corner = ReactKit.corner(Theme.Radius.md),
				Stroke = ReactKit.stroke(Theme.Stroke.thin, selectedAccent),

				Preview = e("Frame", {
					ref = previewRef,
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(0, 12),
					Size = UDim2.new(1, 0, 0, 150),
					ZIndex = 4,
				}),

				Empty = e("TextLabel", {
					Visible = selected == nil,
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(12, 12),
					Size = UDim2.new(1, -24, 0, 150),
					Font = Theme.Font.Regular,
					Text = "Select a pet",
					TextColor3 = Theme.Color.TextFaint,
					TextSize = Theme.TextSize.xs,
					TextWrapped = true,
					ZIndex = 4,
				}),

				Name = e("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(10, 168),
					Size = UDim2.new(1, -20, 0, 42),
					Font = Theme.Font.Heavy,
					Text = if selected then selected.displayName else "",
					TextColor3 = selectedAccent,
					TextSize = Theme.TextSize.md,
					TextWrapped = true,
					ZIndex = 4,
				}, { Stroke = ReactKit.textStroke(Theme.Stroke.thin) }),

				Stats = e("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(10, 210),
					Size = UDim2.new(1, -20, 0, 20),
					Font = Theme.Font.Regular,
					Text = if selected then `{string.upper(selected.rarity)}  •  {selected.damage} DMG` else "",
					TextColor3 = Theme.Color.TextMuted,
					TextSize = Theme.TextSize.xs,
					ZIndex = 4,
				}),

				Equip = e(Button, {
					text = if selected and selected.equipped then "UNEQUIP" else "EQUIP",
					color = if selected and selected.equipped then Theme.Color.Warning else Theme.Color.Positive,
					size = UDim2.new(1, -24, 0, 40),
					position = UDim2.new(0.5, 0, 1, -62),
					anchor = Vector2.new(0.5, 1),
					textSize = Theme.TextSize.sm,
					enabled = canEquipSelected,
					onClick = function()
						if selected then
							Remotes.get("RequestEquip"):FireServer(selected.id, not selected.equipped)
						end
					end,
				}),

				Delete = e(Button, {
					text = "DELETE",
					color = Theme.Color.Danger,
					size = UDim2.new(1, -24, 0, 34),
					position = UDim2.new(0.5, 0, 1, -14),
					anchor = Vector2.new(0.5, 1),
					enabled = selected ~= nil,
					onClick = function()
						if selected then
							Remotes.get("RequestDeletePet"):FireServer(selected.id)
						end
					end,
				}),
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
