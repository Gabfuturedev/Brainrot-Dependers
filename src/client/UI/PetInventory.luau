--!strict
-- Pet inventory panel: equip, unequip and delete. The server is authoritative;
-- this only renders what it sends and asks for changes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared.Config.PetConfig)
local Remotes = require(Shared.Remotes)

local TOGGLE_KEY = Enum.KeyCode.P
local ROW_HEIGHT = 46
local ARM_TIME = 3 -- seconds an armed bulk-delete button waits before giving up
local NEARLY_FULL = 0.9 -- fraction of the cap at which the counter starts warning

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

local function button(text: string, color: Color3, width: number): TextButton
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromOffset(width, 30)
	btn.BackgroundColor3 = color
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBold
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 13
	btn.AutoButtonColor = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = btn

	return btn
end

function PetInventory.start()
	local playerGui = player:WaitForChild("PlayerGui")
	local requestEquip = Remotes.get("RequestEquip")
	local requestDelete = Remotes.get("RequestDeletePet")
	local requestBulkDelete = Remotes.get("RequestBulkDelete")

	local gui = Instance.new("ScreenGui")
	gui.Name = "PetInventory"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local toggle = button("🐾 Pets", Color3.fromRGB(58, 92, 190), 110)
	toggle.AnchorPoint = Vector2.new(0, 1)
	toggle.Position = UDim2.new(0, 16, 1, -16)
	toggle.Size = UDim2.fromOffset(110, 42)
	toggle.TextSize = 16
	toggle.Parent = gui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(420, 420)
	panel.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 14)
	panelCorner.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(18, 12)
	title.Size = UDim2.new(1, -210, 0, 28)
	title.Font = Enum.Font.GothamBold
	title.Text = "Pets"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	-- How close they are to MAX_OWNED. Worth surfacing before they hit it,
	-- because the first sign otherwise is an egg prompt that refuses to hatch.
	local capacity = Instance.new("TextLabel")
	capacity.AnchorPoint = Vector2.new(1, 0)
	capacity.BackgroundTransparency = 1
	capacity.Position = UDim2.new(1, -54, 0, 12)
	capacity.Size = UDim2.fromOffset(150, 28)
	capacity.Font = Enum.Font.GothamMedium
	capacity.Text = ""
	capacity.TextColor3 = Color3.fromRGB(150, 150, 165)
	capacity.TextSize = 14
	capacity.TextXAlignment = Enum.TextXAlignment.Right
	capacity.Parent = panel

	local close = button("✕", Color3.fromRGB(80, 80, 96), 30)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 12)
	close.Parent = panel

	-- Bulk-delete bar, rebuilt on every render from the rarities that actually
	-- have unequipped pets. Scrolls sideways so adding rarities to PetConfig
	-- never overflows the panel.
	local toolbar = Instance.new("ScrollingFrame")
	toolbar.Position = UDim2.fromOffset(14, 48)
	toolbar.Size = UDim2.new(1, -28, 0, 32)
	toolbar.BackgroundTransparency = 1
	toolbar.BorderSizePixel = 0
	toolbar.ScrollBarThickness = 3
	toolbar.ScrollingDirection = Enum.ScrollingDirection.X
	toolbar.CanvasSize = UDim2.new()
	toolbar.AutomaticCanvasSize = Enum.AutomaticSize.X
	toolbar.Parent = panel

	local toolbarLayout = Instance.new("UIListLayout")
	toolbarLayout.FillDirection = Enum.FillDirection.Horizontal
	toolbarLayout.Padding = UDim.new(0, 6)
	toolbarLayout.SortOrder = Enum.SortOrder.LayoutOrder
	toolbarLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	toolbarLayout.Parent = toolbar

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(14, 86)
	list.Size = UDim2.new(1, -28, 1, -100)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 5
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	gui.Parent = playerGui

	local function setOpen(open: boolean)
		panel.Visible = open
	end

	toggle.Activated:Connect(function()
		setOpen(not panel.Visible)
	end)
	close.Activated:Connect(function()
		setOpen(false)
	end)

	UserInputService.InputBegan:Connect(function(input, processedByUI)
		if not processedByUI and input.KeyCode == TOGGLE_KEY then
			setOpen(not panel.Visible)
		end
	end)

	-- Bulk deletion is irreversible and these buttons sit one row above the pet
	-- list, so they take two clicks: the first arms, the second commits. Only
	-- one can be armed at a time, and an armed button gives up after ARM_TIME.
	local disarmCurrent: (() -> ())? = nil
	local armGeneration = 0

	local function addBulkButton(order: number, text: string, count: number, rarity: string?, color: Color3)
		local idle = `{text}  {count}`

		local btn = button(idle, color, 0)
		btn.AutomaticSize = Enum.AutomaticSize.X
		btn.Size = UDim2.fromOffset(0, 28)
		btn.TextSize = 12
		btn.LayoutOrder = order
		btn.Parent = toolbar

		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 10)
		padding.PaddingRight = UDim.new(0, 10)
		padding.Parent = btn

		local armed = false

		local function disarm()
			armed = false
			btn.Text = idle
			btn.BackgroundColor3 = color
		end

		btn.Activated:Connect(function()
			if armed then
				disarm()
				disarmCurrent = nil
				requestBulkDelete:FireServer(rarity)
				return
			end

			if disarmCurrent then
				disarmCurrent()
			end

			armed = true
			btn.Text = "Delete?"
			btn.BackgroundColor3 = Color3.fromRGB(190, 55, 55)
			disarmCurrent = disarm

			armGeneration += 1
			local generation = armGeneration
			task.delay(ARM_TIME, function()
				-- generation check: a later arm on another button owns the state now
				if armed and generation == armGeneration then
					disarm()
					disarmCurrent = nil
				end
			end)
		end)
	end

	local function render(entries: { Entry }, maxEquipped: number, maxOwned: number)
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		-- any inventory change invalidates a pending confirmation: the counts on
		-- those buttons are what the player was agreeing to
		for _, child in toolbar:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		disarmCurrent = nil
		armGeneration += 1

		local equippedCount = 0
		-- unequipped pets are the only ones bulk delete will touch
		local perRarity: { [string]: number } = {}
		local weakestOf: { [string]: number } = {}
		local rarities: { string } = {}
		local deletable = 0

		for _, entry in entries do
			if entry.equipped then
				equippedCount += 1
				continue
			end

			deletable += 1
			if perRarity[entry.rarity] == nil then
				perRarity[entry.rarity] = 1
				weakestOf[entry.rarity] = entry.damage
				table.insert(rarities, entry.rarity)
			else
				perRarity[entry.rarity] += 1
				weakestOf[entry.rarity] = math.min(weakestOf[entry.rarity], entry.damage)
			end
		end

		-- PetConfig has no rarity ordering, so derive one: weakest pet first,
		-- which puts the rarity a player most wants to clear out on the left
		table.sort(rarities, function(a, b)
			if weakestOf[a] == weakestOf[b] then
				return a < b
			end
			return weakestOf[a] < weakestOf[b]
		end)

		if deletable > 0 then
			local hint = Instance.new("TextLabel")
			hint.AutomaticSize = Enum.AutomaticSize.X
			hint.BackgroundTransparency = 1
			hint.Size = UDim2.fromOffset(0, 28)
			hint.Font = Enum.Font.GothamMedium
			hint.Text = "Bulk delete:"
			hint.TextColor3 = Color3.fromRGB(120, 120, 135)
			hint.TextSize = 12
			hint.LayoutOrder = 0
			hint.Parent = toolbar

			for index, rarity in rarities do
				local color = PetConfig.RarityColors[rarity]
				addBulkButton(
					index,
					rarity,
					perRarity[rarity],
					rarity,
					-- tint toward the rarity so the button reads at a glance,
					-- but stay dark enough that it isn't mistaken for equip
					if color then color:Lerp(Color3.fromRGB(70, 30, 36), 0.72) else Color3.fromRGB(90, 50, 60)
				)
			end

			-- an "All" button next to a single rarity button would do the same
			-- thing under a different name
			if #rarities > 1 then
				addBulkButton(#rarities + 1, "All unequipped", deletable, nil, Color3.fromRGB(130, 45, 45))
			end
		end

		local owned = #entries
		capacity.Text = `{owned} / {maxOwned} stored`
		capacity.TextColor3 = if owned >= maxOwned
			then Color3.fromRGB(255, 110, 110)
			elseif owned >= maxOwned * NEARLY_FULL then Color3.fromRGB(255, 190, 90)
			else Color3.fromRGB(150, 150, 165)

		title.Text = `Pets  ({equippedCount}/{maxEquipped} equipped)`
		toggle.Text = `🐾 Pets {equippedCount}/{maxEquipped}`

		for index, entry in entries do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
			row.BackgroundColor3 = if entry.equipped
				then Color3.fromRGB(40, 52, 40)
				else Color3.fromRGB(34, 34, 44)
			row.BorderSizePixel = 0
			row.LayoutOrder = index
			row.Parent = list

			local rowCorner = Instance.new("UICorner")
			rowCorner.CornerRadius = UDim.new(0, 8)
			rowCorner.Parent = row

			local rarityColor = PetConfig.RarityColors[entry.rarity] or Color3.fromRGB(200, 200, 200)

			local pip = Instance.new("Frame")
			pip.Position = UDim2.fromOffset(10, 13)
			pip.Size = UDim2.fromOffset(6, 20)
			pip.BackgroundColor3 = rarityColor
			pip.BorderSizePixel = 0
			pip.Parent = row

			local pipCorner = Instance.new("UICorner")
			pipCorner.CornerRadius = UDim.new(1, 0)
			pipCorner.Parent = pip

			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Position = UDim2.fromOffset(26, 0)
			label.Size = UDim2.new(1, -170, 1, 0)
			label.Font = Enum.Font.GothamMedium
			label.Text = `{entry.displayName}   <font color="#888888">{entry.damage} dmg</font>`
			label.RichText = true
			label.TextColor3 = rarityColor
			label.TextSize = 15
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.Parent = row

			local canEquip = entry.equipped or equippedCount < maxEquipped
			local action = button(
				if entry.equipped then "Unequip" else "Equip",
				if entry.equipped then Color3.fromRGB(150, 90, 60) elseif canEquip then Color3.fromRGB(60, 140, 80) else Color3.fromRGB(60, 60, 70),
				78
			)
			action.AnchorPoint = Vector2.new(1, 0.5)
			action.Position = UDim2.new(1, -46, 0.5, 0)
			action.Active = canEquip
			action.Parent = row

			action.Activated:Connect(function()
				if canEquip then
					requestEquip:FireServer(entry.id, not entry.equipped)
				end
			end)

			local remove = button("✕", Color3.fromRGB(120, 50, 50), 30)
			remove.AnchorPoint = Vector2.new(1, 0.5)
			remove.Position = UDim2.new(1, -10, 0.5, 0)
			remove.Parent = row

			remove.Activated:Connect(function()
				requestDelete:FireServer(entry.id)
			end)
		end
	end

	Remotes.get("InventoryUpdated").OnClientEvent:Connect(render)
end

return PetInventory
