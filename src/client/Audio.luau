--!strict
-- Sounds for things that happened to you specifically: your hits, your coins,
-- your hatch. Breaks are played by the server on the breakable itself, since
-- those belong to the area rather than to one player.
--
-- Everything here rides on remotes that already existed for other reasons - no
-- new server traffic was added to make the game audible.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Sound = require(Shared.Sound)
local SoundConfig = require(Shared.Config.SoundConfig)

local EggFx = require(script.Parent.UI.EggFx)

-- Three pets on a half-second cooldown means six hits a second, and stacking a
-- sound that densely turns it into a buzz. This caps it at a rate that still
-- reads as one-per-hit during normal play.
local HIT_INTERVAL = 0.07

local Audio = {}

function Audio.start()
	local lastHit = 0
	Remotes.get("DamageDealt").OnClientEvent:Connect(function()
		local now = os.clock()
		if now - lastHit < HIT_INTERVAL then
			return
		end
		lastHit = now
		Sound.play2d("Hit")
	end)

	Remotes.get("DropCollected").OnClientEvent:Connect(function()
		Sound.play2d("Collect")
	end)

	-- Pitched by the best pull in the batch, matching what HatchPopup shows.
	-- Playing one sound per pet in a ten-pull would just be noise.
	--
	-- Via EggFx rather than the remote, so the sting lands on the flash and the
	-- card together instead of a beat before the egg has finished shaking.
	EggFx.Finished:Connect(function(results)
		if typeof(results) ~= "table" or #results == 0 then
			return -- a failure toast; HatchPopup already explains it
		end

		local bestPitch = 0
		for _, result in results do
			local pitch = SoundConfig.HatchPitch[result.rarity] or 1
			bestPitch = math.max(bestPitch, pitch)
		end

		Sound.play2d("Hatch", if bestPitch > 0 then bestPitch else 1)
	end)

	-- AreasUpdated fires on join and on every respawn, not only on a purchase,
	-- so compare against what we last saw. The first push is whatever we walked
	-- in already owning and must stay silent.
	local known: { [string]: boolean }? = nil
	Remotes.get("AreasUpdated").OnClientEvent:Connect(function(areas)
		local current: { [string]: boolean } = if typeof(areas) == "table" then areas else {}

		if known then
			for name in current do
				if not known[name] then
					Sound.play2d("Unlock")
					break
				end
			end
		end

		known = current
	end)
end

return Audio
