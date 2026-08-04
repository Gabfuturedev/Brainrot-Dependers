--!strict
-- Centre-screen toast for hatch results, coloured by rarity.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared.Config.PetConfig)
local Remotes = require(Shared.Remotes)

local HOLD_TIME = 1.6

local player = Players.LocalPlayer

local HatchPopup = {}

function HatchPopup.start()
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "HatchPopup"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.34)
	label.Size = UDim2.fromOffset(420, 56)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 34
	label.TextStrokeTransparency = 0.35
	label.TextTransparency = 1
	label.Text = ""
	label.Parent = gui

	gui.Parent = playerGui

	local function show(text: string, color: Color3)
		label.Text = text
		label.TextColor3 = color
		label.Position = UDim2.fromScale(0.5, 0.36)

		TweenService:Create(label, TweenInfo.new(0.2), {
			TextTransparency = 0,
			TextStrokeTransparency = 0.35,
			Position = UDim2.fromScale(0.5, 0.34),
		}):Play()

		task.delay(HOLD_TIME, function()
			TweenService:Create(label, TweenInfo.new(0.4), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
				Position = UDim2.fromScale(0.5, 0.31),
			}):Play()
		end)
	end

	Remotes.get("HatchResult").OnClientEvent:Connect(function(petName, detail)
		if not petName then
			-- failure: `detail` is the reason, e.g. "Need 40 more coins"
			show(detail or "Cannot hatch", Color3.fromRGB(255, 120, 120))
			return
		end

		local stats = PetConfig.get(petName)
		local rarity = detail or "Common"
		local color = PetConfig.RarityColors[rarity] or Color3.fromRGB(255, 255, 255)
		show(`{rarity}!  {stats and stats.displayName or petName}`, color)
	end)
end

return HatchPopup
