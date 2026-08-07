--!strict
-- Hands each player one of the plots in Workspace.Plot and takes it back when
-- they leave.
--
-- Ownership is published as an attribute on the plot rather than sent over a
-- remote. Attributes replicate on their own, so every client can see who owns
-- what without the server telling anyone - the same trick breakable health
-- uses, and it means a plot is self-describing to anything that looks at it.
--
-- A plot missing pieces is warned about once and still assigned. Half a plot is
-- better than a player with nowhere to stand while you are still building.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local FOLDER_NAME = "Plots"
local OWNER_ATTRIBUTE = "OwnerUserId"

-- What a finished plot contains. Nothing here is required to load; this is the
-- checklist the startup warning reads from.
local EXPECTED = {
	{ name = "Spawn", kind = "BasePart" },
	{ name = "Core", kind = "PVInstance" },
	{ name = "Posts", kind = "Folder" },
	{ name = "EnemySpawns", kind = "Folder" },
}

local PlotService = {}

local plots: { Instance } = {}
local ownerOf: { [Instance]: Player } = {}
local plotOf: { [Player]: Instance } = {}

local plotAssigned = Instance.new("BindableEvent")
-- Fires (player, plot) once a plot is theirs. Connect before start().
PlotService.PlotAssigned = plotAssigned.Event

local plotReleased = Instance.new("BindableEvent")
-- Fires (player, plot) when they leave, so anything spawned on that plot can
-- clean itself up.
PlotService.PlotReleased = plotReleased.Event

function PlotService.getPlot(player: Player): Instance?
	return plotOf[player]
end

function PlotService.getOwner(plot: Instance): Player?
	return ownerOf[plot]
end

-- Named piece of a player's plot, e.g. getPart(player, "Spawn"). Returns nil
-- rather than erroring so callers can degrade on a half-built plot.
function PlotService.getPart(player: Player, childName: string): BasePart?
	local plot = plotOf[player]
	local child = plot and plot:FindFirstChild(childName)
	if not child then
		return nil
	end
	if child:IsA("BasePart") then
		return child
	end
	if child:IsA("Model") then
		return child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

function PlotService.getFolder(player: Player, childName: string): Instance?
	local plot = plotOf[player]
	local child = plot and plot:FindFirstChild(childName)
	return if child and child:IsA("Folder") then child else nil
end

local function describeGaps(plot: Instance)
	local missing: { string } = {}
	for _, expected in EXPECTED do
		local child = plot:FindFirstChild(expected.name)
		if not child or not child:IsA(expected.kind) then
			table.insert(missing, expected.name)
		end
	end

	if #missing > 0 then
		warn(`[PlotService] plot '{plot.Name}' is missing: {table.concat(missing, ", ")}`)
	end
end

local function moveToSpawn(player: Player, character: Model)
	local spawn = PlotService.getPart(player, "Spawn")
	if not spawn then
		return -- no spawn marker; they land wherever Roblox put them
	end

	-- PivotTo rather than setting the root's CFrame: it carries accessories and
	-- anything else welded on, and a hair floating at the old spawn is a
	-- genuinely common bug from doing this the other way.
	character:PivotTo(spawn.CFrame + Vector3.new(0, spawn.Size.Y / 2 + 3, 0))
end

local function claim(player: Player)
	if plotOf[player] then
		return
	end

	for _, plot in plots do
		if not ownerOf[plot] then
			ownerOf[plot] = player
			plotOf[player] = plot
			plot:SetAttribute(OWNER_ATTRIBUTE, player.UserId)

			print(`[PlotService] {player.Name} -> plot {plot.Name}`)
			plotAssigned:Fire(player, plot)

			if player.Character then
				moveToSpawn(player, player.Character)
			end
			return
		end
	end

	-- Should not happen while MaxPlayers matches the plot count, but a server
	-- that silently seats someone nowhere is worse than one that says so.
	warn(`[PlotService] no free plot for {player.Name} - check MaxPlayers against the number of plots`)
end

local function release(player: Player)
	local plot = plotOf[player]
	if not plot then
		return
	end

	plotOf[player] = nil
	ownerOf[plot] = nil
	plot:SetAttribute(OWNER_ATTRIBUTE, nil)
	plotReleased:Fire(player, plot)
end

function PlotService.start()
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if not folder then
		warn(`[PlotService] Workspace has no '{FOLDER_NAME}' folder - nobody gets a plot`)
		return
	end

	-- Sorted by name so plot 1 is always claimed first. GetChildren order is not
	-- guaranteed, and "which plot am I on" changing between sessions for no
	-- reason is confusing to build against.
	for _, child in folder:GetChildren() do
		table.insert(plots, child)
	end
	table.sort(plots, function(a, b)
		return a.Name < b.Name
	end)

	for _, plot in plots do
		plot:SetAttribute(OWNER_ATTRIBUTE, nil)
		describeGaps(plot)
	end

	print(`[PlotService] {#plots} plot(s) ready`)

	local function bind(player: Player)
		claim(player)
		player.CharacterAdded:Connect(function(character)
			moveToSpawn(player, character)
		end)
	end

	-- in Studio the local player can already exist by the time this runs, so
	-- PlayerAdded alone would never seat them
	for _, player in Players:GetPlayers() do
		bind(player)
	end
	Players.PlayerAdded:Connect(bind)
	Players.PlayerRemoving:Connect(release)
end

return PlotService
