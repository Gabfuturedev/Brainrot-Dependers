--!strict
-- Coins. The saved profile is the source of truth; the leaderstats IntValue is
-- only a replicated view of it, so the client can display a number.

local Players = game:GetService("Players")

local DataService = require(script.Parent.DataService)

local CurrencyService = {}

local coinValues: { [Player]: IntValue } = {}

local function onProfileLoaded(player: Player)
	local data = DataService.getData(player)
	if not data then
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = data.coins -- start from what they had last session
	coins.Parent = leaderstats

	leaderstats.Parent = player
	coinValues[player] = coins
end

function CurrencyService.addCoins(player: Player, amount: number)
	local data = DataService.getData(player)
	if not data then
		return -- profile still loading, or they already left
	end

	data.coins += amount

	local coins = coinValues[player]
	if coins then
		coins.Value = data.coins
	end
end

function CurrencyService.getCoins(player: Player): number
	local data = DataService.getData(player)
	return if data then data.coins else 0
end

function CurrencyService.start()
	DataService.ProfileLoaded:Connect(onProfileLoaded)
	Players.PlayerRemoving:Connect(function(player)
		coinValues[player] = nil
	end)
end

return CurrencyService
