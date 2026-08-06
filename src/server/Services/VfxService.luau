--!strict
-- One-shot visual effects: clone a template out of ServerStorage.VFX, put it
-- where something happened, let it play, throw it away.
--
-- Effect packs off the toolbox are authored two different ways and neither is
-- wrong. Some ship their emitters disabled, expecting an Emit() burst; others
-- ship them enabled, expecting to be switched on and off. Both are handled
-- below, so an effect works however its author built it.
--
-- Templates are direct children of ServerStorage.VFX. Unlike pet models there
-- is no reliable way to tell "an effect" from "a folder of effects" by looking
-- at it, so this stays flat and predictable rather than clever.

local Debris = game:GetService("Debris")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local FOLDER_NAME = "VFX"
local DEFAULT_EMIT = 12 -- particles for a burst emitter that specifies none

-- An attack effect fires about twice a second per pet, so anything that outlasts
-- the punch is on screen three times over before the first copy has gone. These
-- keep an impact reading as an impact:
local EMIT_WINDOW = 0.15 -- how long a streaming emitter is allowed to run
local FADE_TIME = 0.2 -- visible meshes are faded out over this
local MIN_LIFETIME = 0.35 -- floor, so nothing is cut off the instant it spawns
local MAX_LIFETIME = 3 -- ceiling, so a badly authored effect cannot linger

local VfxService = {}

local templates: { [string]: Instance } = {}
local effectFolder: Folder

-- Effects fire several times a second, so a missing one has to say so once
-- rather than once per hit.
local warned: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn(message)
end

local function indexTemplates()
	local folder = ServerStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		warn(`[VfxService] ServerStorage has no '{FOLDER_NAME}' folder - effects will be skipped`)
		return
	end

	local names: { string } = {}
	for _, child in folder:GetChildren() do
		templates[child.Name] = child
		table.insert(names, child.Name)
	end

	table.sort(names)
	print(`[VfxService] indexed {#names} effect(s): {table.concat(names, ", ")}`)
end

-- Plays `name` at `position`. Silently does nothing when the effect is missing,
-- so a typo in a config never stops a pet from actually landing its hit.
function VfxService.playAt(name: string, position: Vector3)
	local template = templates[name]
	if not template then
		warnOnce(`{name}/missing`, `[VfxService] no effect named '{name}' under ServerStorage.{FOLDER_NAME}`)
		return
	end

	local clone = template:Clone()

	-- PivotTo is the only thing that positions a whole effect in one call, and
	-- it needs a Model or a Part. A bare Folder has no pivot to move.
	if not clone:IsA("PVInstance") then
		warnOnce(
			`{name}/pivot`,
			`[VfxService] '{name}' is a {clone.ClassName}, which cannot be positioned - group it into a Model`
		)
		clone:Destroy()
		return
	end

	local emitters: { ParticleEmitter } = {}
	local visible: { BasePart } = {}

	local function prepare(instance: Instance)
		if instance:IsA("BasePart") then
			-- effects are decoration: they must never fall, block a click on the
			-- breakable behind them, or trip a touch handler
			instance.Anchored = true
			instance.CanCollide = false
			instance.CanQuery = false
			instance.CanTouch = false

			-- A solid mesh is the other reason an effect overstays: emitter
			-- carriers are already invisible, but an impact flash is a real
			-- part that would otherwise just sit there until the clone goes.
			if instance.Transparency < 1 then
				table.insert(visible, instance)
			end
		elseif instance:IsA("ParticleEmitter") then
			table.insert(emitters, instance)
		elseif instance:IsA("LuaSourceContainer") then
			instance:Destroy() -- same toolbox hygiene as pet models
		end
	end

	prepare(clone)
	for _, descendant in clone:GetDescendants() do
		prepare(descendant)
	end

	clone:PivotTo(CFrame.new(position))
	clone.Parent = effectFolder

	-- after parenting, so the particles have somewhere to render
	local streaming = false
	local longestParticle = 0

	for _, emitter in emitters do
		longestParticle = math.max(longestParticle, emitter.Lifetime.Max)

		if emitter.Enabled then
			streaming = true
		else
			local count = emitter:GetAttribute("EmitCount")
			emitter:Emit(if typeof(count) == "number" then count else DEFAULT_EMIT)
		end
	end

	-- A stream left running is what turns a punch into a jet. Give it just long
	-- enough to read as an impact, then shut it off and let whatever it already
	-- produced finish flying on its own.
	if streaming then
		task.delay(EMIT_WINDOW, function()
			for _, emitter in emitters do
				emitter.Enabled = false
			end
		end)
	end

	for _, part in visible do
		TweenService:Create(part, TweenInfo.new(FADE_TIME), { Transparency = 1 }):Play()
	end

	-- Measured rather than guessed: an effect with 0.3s particles is gone in
	-- half a second, one with 2s particles gets its full two. A Duration
	-- attribute on the template overrides this if you want to tune it in Studio.
	local override = template:GetAttribute("Duration")
	local lifetime = if typeof(override) == "number"
		then override
		else math.clamp(EMIT_WINDOW + longestParticle, MIN_LIFETIME, MAX_LIFETIME)

	Debris:AddItem(clone, lifetime)
end

function VfxService.start()
	effectFolder = Instance.new("Folder")
	effectFolder.Name = "Effects"
	effectFolder.Parent = Workspace

	indexTemplates()
end

return VfxService
