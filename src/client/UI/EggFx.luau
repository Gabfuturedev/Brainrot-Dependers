--!strict
-- The egg's hatch animation, and the gate that holds the reveal back until it
-- has played.
--
-- A result that appears the instant you click has no weight to it. The egg
-- wobbles - building, not fading, so it reads as something about to give way -
-- then flashes, and only then does the popup land. The flash is tinted by the
-- best pet in the pull, so the colour tells you what you got a beat before the
-- card does. That beat is the whole point.
--
-- Runs entirely on the client. The egg part is shared by everyone, and a
-- server-side animation would have two players' hatches fighting over one
-- CFrame; done locally, each player sees their own and nobody collides.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared.Config.PetConfig)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)

local SHAKE_TIME = 0.7
local SHAKE_ANGLE = 16 -- degrees of roll at full intensity
local SHAKE_SPEED = 32 -- oscillations per second
local SHAKE_RISE = 0.6 -- studs it lifts as it builds
local FLASH_TIME = 0.28
local LIGHT_RANGE = 30
local LIGHT_BRIGHTNESS = 12

-- Never strand the lock. The server can decline a request without replying at
-- all - an unloaded profile, a batch size it does not offer - and a player
-- locked out of hatching forever is far worse than one who double-hatched.
local HATCH_TIMEOUT = 10

local EggFx = {}

local finished = Instance.new("BindableEvent")
-- Fires (results, detail) once the animation has played - HatchPopup and Audio
-- listen to this rather than to the remote, so the reveal cannot outrun the egg.
EggFx.Finished = finished.Event

local busyChanged = Instance.new("BindableEvent")
-- Fires (busy) so the hatch buttons can grey out while a pull is playing.
EggFx.BusyChanged = busyChanged.Event

local lastEggName: string? = nil
local generation = 0

-- One hatch at a time, from the press until the reveal has finished. Without
-- it, holding E spends hundreds of coins into animations that cut each other
-- off, and the player never sees a single result they paid for.
local busy = false
local busyToken = 0

local function setBusy(value: boolean)
	if busy == value then
		return
	end
	busy = value
	busyChanged:Fire(value)
end

function EggFx.isBusy(): boolean
	return busy
end

-- Call before firing RequestHatch. Returns false when a pull is already
-- running, in which case the caller should do nothing at all.
function EggFx.beginHatch(eggName: string): boolean
	if busy then
		return false
	end

	lastEggName = eggName
	busyToken += 1
	local mine = busyToken
	setBusy(true)

	task.delay(HATCH_TIMEOUT, function()
		-- only release if this is still the request that took the lock
		if busy and busyToken == mine then
			setBusy(false)
		end
	end)

	return true
end

-- Called by HatchPopup once its reveal has been dismissed, which is the real
-- end of the sequence - not the moment the server replied.
function EggFx.endReveal()
	setBusy(false)
end

-- Same rule the server uses to pick an egg's part, so both sides agree on where
-- a given egg actually is. Shared with EggBillboard.
function EggFx.hostPartOf(model: Instance): BasePart?
	if model:IsA("BasePart") then
		return model
	end
	if model:IsA("Model") then
		return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

-- HatchResult does not say which egg it came from, and it does not need to:
-- the player pressed a specific button, so the client already knows. Set by
-- beginHatch; this is only here for anything that hatches without taking the
-- lock.
function EggFx.noteEgg(eggName: string)
	lastEggName = eggName
end

local function eggPart(): BasePart?
	if not lastEggName then
		return nil
	end
	local eggs = Workspace:FindFirstChild("Eggs")
	local model = eggs and eggs:FindFirstChild(lastEggName)
	return if model then EggFx.hostPartOf(model) else nil
end

local function flash(part: BasePart, color: Color3)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = LIGHT_RANGE
	light.Brightness = 0
	light.Shadows = false
	light.Parent = part

	-- up fast, down slow: a light that fades out reads as an afterglow, where
	-- one that snaps off reads as a bug
	local up = TweenService:Create(light, TweenInfo.new(0.06), { Brightness = LIGHT_BRIGHTNESS })
	up:Play()
	up.Completed:Once(function()
		TweenService:Create(light, TweenInfo.new(FLASH_TIME), { Brightness = 0 }):Play()
	end)

	Debris:AddItem(light, FLASH_TIME + 0.5)
end

local function shake(part: BasePart, color: Color3, onComplete: () -> ())
	generation += 1
	local mine = generation

	local base = part.CFrame
	local elapsed = 0

	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(deltaTime)
		-- a newer hatch owns the egg now, or it was removed from the world
		if generation ~= mine or not part.Parent then
			connection:Disconnect()
			return
		end

		elapsed += deltaTime
		if elapsed >= SHAKE_TIME then
			connection:Disconnect()
			part.CFrame = base -- always restore; this is a local-only change
			flash(part, color)
			onComplete()
			return
		end

		-- Intensity climbs rather than decays. A shake that starts hard and
		-- settles reads as an impact that already happened; one that builds
		-- reads as pressure about to break, which is what we want here.
		local intensity = elapsed / SHAKE_TIME
		local wave = math.sin(elapsed * SHAKE_SPEED)
		part.CFrame = base
			* CFrame.new(0, math.abs(wave) * SHAKE_RISE * intensity, 0)
			* CFrame.Angles(0, 0, math.rad(SHAKE_ANGLE) * intensity * wave)
	end)
end

function EggFx.start()
	Remotes.get("HatchResult").OnClientEvent:Connect(function(results, detail)
		-- failures skip the animation: there is nothing to build anticipation
		-- toward, and shaking an egg that did not hatch is a lie
		if typeof(results) ~= "table" or #results == 0 then
			finished:Fire(results, detail)
			return
		end

		local part = eggPart()
		if not part then
			finished:Fire(results, detail) -- no egg to animate; show it straight away
			return
		end

		-- tint the flash with the best pull, so the colour lands before the card
		local color = Theme.Color.Text
		local best = -1
		for _, result in results do
			local stats = PetConfig.get(result.name)
			local damage = if stats then stats.damage else 0
			if damage > best then
				best = damage
				color = PetConfig.RarityColors[result.rarity] or color
			end
		end

		shake(part, color, function()
			finished:Fire(results, detail)
		end)
	end)
end

return EggFx
