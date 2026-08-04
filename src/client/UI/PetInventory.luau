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
	btn.Size = UDim2.new(0, width, 0, 30)
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
	title.Size = UDim2.new(1, -36, 0, 28)
	title.Font = Enum.Font.GothamBold
	title.Text = "Pets"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	local close = button("✕", Color3.fromRGB(80, 80, 96), 30)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 12)
	close.Parent = panel

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(14, 50)
	list.Size = UDim2.new(1, -28, 1, -64)
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

	local function render(entries: { Entry }, maxEquipped: number)
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		local equippedCount = 0
		for _, entry in entries do
			if entry.equipped then
				equippedCount += 1
			end
		end

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
