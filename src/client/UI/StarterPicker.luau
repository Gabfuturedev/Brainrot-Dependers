--!strict
-- The one-time starter pick, shown on first join. The server decides when this
-- appears and re-validates whatever comes back, so this only renders the
-- options it was handed and reports which one was clicked.
--
-- Model previews are optional. The client cannot see ServerStorage.Pets, so a
-- card falls back to a plain label unless a copy of the rig is sitting in
-- ReplicatedStorage.StarterPreviews under the same name.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared.Config.PetConfig)
local Remotes = require(Shared.Remotes)

local PREVIEW_FOLDER = "StarterPreviews"
local CARD_WIDTH = 180
local CARD_HEIGHT = 280

local player = Players.LocalPlayer

local StarterPicker = {}

-- Frames the whole rig whatever its proportions, so a tall pet and a wide one
-- both fill the card instead of one overflowing and the other sitting tiny.
local function addPreview(card: Frame, modelName: string): boolean
	local folder = ReplicatedStorage:FindFirstChild(PREVIEW_FOLDER)
	local template = folder and folder:FindFirstChild(modelName)
	if not template or not template:IsA("Model") then
		return false
	end

	local viewport = Instance.new("ViewportFrame")
	viewport.BackgroundTransparency = 1
	viewport.Position = UDim2.fromOffset(0, 10)
	viewport.Size = UDim2.new(1, 0, 0, 150)
	viewport.Parent = card

	local model = template:Clone()
	model.Parent = viewport

	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local center, size = model:GetBoundingBox()
	local distance = math.max(size.Magnitude, 1) * 1.1
	camera.CFrame = CFrame.lookAt(
		center.Position + Vector3.new(distance * 0.55, size.Y * 0.35, distance),
		center.Position
	)

	return true
end

function StarterPicker.start()
	local playerGui = player:WaitForChild("PlayerGui")
	local requestStarter = Remotes.get("RequestStarter")

	local gui = Instance.new("ScreenGui")
	gui.Name = "StarterPicker"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10 -- over every other panel; nothing else matters yet
	gui.Enabled = false

	-- Full-screen scrim. Deliberately has no close button: the pick is the only
	-- way out, and a dismissed picker would leave a player with no pet at all.
	local scrim = Instance.new("Frame")
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	scrim.BackgroundTransparency = 0.4
	scrim.BorderSizePixel = 0
	scrim.Parent = gui

	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.5, 0.16)
	title.Size = UDim2.fromOffset(600, 44)
	title.Font = Enum.Font.GothamBold
	title.Text = "Pick your first brainrot"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 30
	title.TextStrokeTransparency = 0.4
	title.Parent = scrim

	local subtitle = Instance.new("TextLabel")
	subtitle.AnchorPoint = Vector2.new(0.5, 0)
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromScale(0.5, 0.16)
	subtitle.Size = UDim2.fromOffset(600, 76)
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.Text = "You only get to choose once. They are all equally strong."
	subtitle.TextColor3 = Color3.fromRGB(190, 190, 205)
	subtitle.TextSize = 15
	subtitle.Parent = scrim

	local row = Instance.new("Frame")
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromScale(0.5, 0.52)
	row.Size = UDim2.fromOffset(0, CARD_HEIGHT)
	row.AutomaticSize = Enum.AutomaticSize.X
	row.Parent = scrim

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 18)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = row

	gui.Parent = playerGui

	-- Guards a double-click: the server ignores the second, but leaving the
	-- picker up while the first is being granted reads as the click not landing.
	local picked = false

	local function addCard(order: number, petName: string)
		local stats = PetConfig.get(petName)
		if not stats then
			return -- config and server disagree; skip rather than render a blank
		end

		local accent = PetConfig.RarityColors[stats.rarity] or Color3.fromRGB(200, 200, 200)

		local card = Instance.new("TextButton")
		card.Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT)
		card.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
		card.BorderSizePixel = 0
		card.Text = ""
		card.AutoButtonColor = false
		card.LayoutOrder = order
		card.Parent = row

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 14)
		corner.Parent = card

		local stroke = Instance.new("UIStroke")
		stroke.Color = accent
		stroke.Thickness = 2
		stroke.Transparency = 0.55
		stroke.Parent = card

		if not addPreview(card, stats.model) then
			-- no replicated copy of the rig: name the pet large instead, so the
			-- card still reads as something rather than an empty box
			local placeholder = Instance.new("TextLabel")
			placeholder.BackgroundTransparency = 1
			placeholder.Position = UDim2.fromOffset(10, 10)
			placeholder.Size = UDim2.new(1, -20, 0, 150)
			placeholder.Font = Enum.Font.GothamBold
			placeholder.Text = "?"
			placeholder.TextColor3 = accent
			placeholder.TextSize = 64
			placeholder.TextTransparency = 0.6
			placeholder.Parent = card
		end

		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Position = UDim2.fromOffset(10, 168)
		name.Size = UDim2.new(1, -20, 0, 44)
		name.Font = Enum.Font.GothamBold
		name.Text = stats.displayName
		name.TextColor3 = accent
		name.TextSize = 17
		name.TextWrapped = true
		name.Parent = card

		local detail = Instance.new("TextLabel")
		detail.BackgroundTransparency = 1
		detail.Position = UDim2.fromOffset(10, 212)
		detail.Size = UDim2.new(1, -20, 0, 20)
		detail.Font = Enum.Font.GothamMedium
		detail.Text = `{stats.damage} dmg`
		detail.TextColor3 = Color3.fromRGB(170, 170, 185)
		detail.TextSize = 14
		detail.Parent = card

		local choose = Instance.new("TextLabel")
		choose.AnchorPoint = Vector2.new(0.5, 1)
		choose.BackgroundColor3 = accent
		choose.BorderSizePixel = 0
		choose.Position = UDim2.new(0.5, 0, 1, -12)
		choose.Size = UDim2.new(1, -24, 0, 32)
		choose.Font = Enum.Font.GothamBold
		choose.Text = "Choose"
		choose.TextColor3 = Color3.fromRGB(20, 20, 26)
		choose.TextSize = 14
		choose.Parent = card

		local chooseCorner = Instance.new("UICorner")
		chooseCorner.CornerRadius = UDim.new(0, 8)
		chooseCorner.Parent = choose

		card.MouseEnter:Connect(function()
			if not picked then
				stroke.Transparency = 0
				TweenService:Create(card, TweenInfo.new(0.12), {
					BackgroundColor3 = Color3.fromRGB(38, 38, 50),
				}):Play()
			end
		end)
		card.MouseLeave:Connect(function()
			stroke.Transparency = 0.55
			TweenService:Create(card, TweenInfo.new(0.12), {
				BackgroundColor3 = Color3.fromRGB(28, 28, 38),
			}):Play()
		end)

		card.Activated:Connect(function()
			if picked then
				return
			end
			picked = true
			requestStarter:FireServer(petName)
			gui.Enabled = false
		end)
	end

	Remotes.get("ChooseStarter").OnClientEvent:Connect(function(petNames)
		-- the server re-offers on every spawn until one is picked, so ignore
		-- anything that arrives after the click
		if picked or typeof(petNames) ~= "table" then
			return
		end

		for _, child in row:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end

		for order, petName in petNames do
			addCard(order, petName)
		end

		gui.Enabled = true
	end)
end

return StarterPicker
