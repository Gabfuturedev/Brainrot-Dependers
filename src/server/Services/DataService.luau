--!strict
-- Owns every player's saved data. Nothing else in the game touches DataStores.
-- ProfileStore handles session locking, autosaving and shutdown saving for us,
-- so there is deliberately no BindToClose here - it would fight the library.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ProfileStore = require(script.Parent.Parent.Packages.ProfileStore)

local STORE_NAME = "PlayerData"
local KEY_PREFIX = "Player_"

-- Mock keeps Studio testing self-contained: no API access needed, and you
-- can't corrupt live player data while experimenting. Flip to false once you
-- have enabled Studio Access to API Services and want to test real saving.
local USE_MOCK_IN_STUDIO = true

-- Every field a player can have. Adding a key here is all that's needed -
-- Profile:Reconcile() backfills it for players who saved before it existed.
-- Remember ProfileStore's rules: no Instances, no Vector3/CFrame, no functions.
local PROFILE_TEMPLATE = {
	coins = 0,
	ownedPets = {} :: { [string]: string }, -- [petId] = pet name from PetConfig
	equipped = {} :: { string }, -- petIds currently following the player
	unlockedAreas = { Area1 = true } :: { [string]: boolean },
	starterChosen = false, -- the one-time pick on first join has been made
	-- Every pet name ever obtained, which is NOT the same as ownedPets: an
	-- index has to remember what you have seen even after you delete it, or
	-- clearing out duplicates would re-lock pets you already found.
	discovered = {} :: { [string]: boolean },
}

export type Data = typeof(PROFILE_TEMPLATE)

local DataService = {}

local profiles: { [Player]: any } = {}
local store: any

local profileLoaded = Instance.new("BindableEvent")
-- Fires (player) once their data is ready. Connect to this in start() BEFORE
-- DataService.start() runs, or you will miss the players who load first.
DataService.ProfileLoaded = profileLoaded.Event

function DataService.getProfile(player: Player): any?
	return profiles[player]
end

function DataService.getData(player: Player): Data?
	local profile = profiles[player]
	return profile and profile.Data
end

-- Yields until the player's data is ready. Returns nil if they leave first.
function DataService.waitForData(player: Player): Data?
	while player.Parent == Players and not profiles[player] do
		task.wait()
	end
	return DataService.getData(player)
end

local function onPlayerAdded(player: Player)
	local profile = store:StartSessionAsync(`{KEY_PREFIX}{player.UserId}`, {
		-- stop retrying if they leave while we're still waiting on a lock
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if not profile then
		player:Kick("Your data could not be loaded. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId) -- GDPR: lets Roblox find this data on request
	profile:Reconcile() -- backfill any template keys added since their last save

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		-- another server took the session, or we shut down; playing on without
		-- data would silently discard their progress
		player:Kick("Your data session was ended. Please rejoin.")
	end)

	if player.Parent ~= Players then
		-- they left during the load; release the lock immediately
		profile:EndSession()
		return
	end

	profiles[player] = profile
	profileLoaded:Fire(player)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		profile:EndSession() -- saves, then releases the lock for the next server
	end
end

function DataService.start()
	store = ProfileStore.New(STORE_NAME, PROFILE_TEMPLATE)

	if RunService:IsStudio() and USE_MOCK_IN_STUDIO then
		store = store.Mock
		warn("[DataService] using MOCK data store - nothing saves between Studio sessions")
	end

	ProfileStore.OnError:Connect(function(message: string, storeName: string, key: string)
		warn(`[DataService] {storeName}/{key}: {message}`)
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return DataService
