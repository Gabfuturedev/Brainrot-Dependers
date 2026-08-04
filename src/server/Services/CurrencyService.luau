--!strict
-- Coins, exposed through leaderstats. No saving yet - that comes with DataStores.

local Players = game:GetService("Players")

local CurrencyService = {}

local coinValues: { [Player]: IntValue } = {}

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = 0
	coins.Parent = leaderstats

	leaderstats.Parent = player
	coinValues[player] = coins
end

function CurrencyService.addCoins(player: Player, amount: number)
	local coins = coinValues[player]
	if coins then
		coins.Value += amount
	end
end

function CurrencyService.getCoins(player: Player): number
	local coins = coinValues[player]
	return coins and coins.Value or 0
end

function CurrencyService.start()
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		coinValues[player] = nil
	end)
end

return CurrencyService
