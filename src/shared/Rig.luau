--!strict
-- Making a toolbox rig safe to anchor and move by hand.
--
-- Both pets and enemies are dropped in from the toolbox, anchored at the root
-- and driven by CFrame, and both hit the same two problems: bundled scripts we
-- do not want running, and bodies attached to nothing that fall through the
-- world the moment they are unanchored. That second one cost three rounds of
-- debugging on the pets - an invisible rig that still followed and still
-- attacked, because the HumanoidRootPart was the only thing left.
--
-- Shared so the next rig-driven system inherits the fix instead of the bug.

local Rig = {}

-- Roblox's own default animations, which any place is allowed to play - unlike
-- a rig's bundled ones, which usually belong to whoever uploaded it and fail to
-- load with an access error.
Rig.DefaultAnimations = {
	[Enum.HumanoidRigType.R15] = { idle = "rbxassetid://507766388", walk = "rbxassetid://507777826" },
	[Enum.HumanoidRigType.R6] = { idle = "rbxassetid://180435571", walk = "rbxassetid://180426354" },
}

-- One animation driver, and only one.
--
-- Toolbox rigs often carry both a Humanoid and an AnimationController, and with
-- both present each applies its own pose every frame and the model twitches
-- between them. The Humanoid wins: it carries the RigType that picks the right
-- default animation set.
function Rig.resolveAnimator(model: Model): Animator?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local controller = model:FindFirstChildOfClass("AnimationController")

	if humanoid and controller then
		controller:Destroy()
		controller = nil
	end

	local source: Instance? = humanoid or controller
	if not source then
		local created = Instance.new("AnimationController")
		created.Parent = model
		source = created
	end
	assert(source, "animation source")

	local animator = source:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = source
	end
	return animator :: Animator
end

-- Loads and returns a looping track, or nil if the asset will not load.
--
-- LoadAnimation succeeds even for an asset the place cannot access - the
-- failure only surfaces asynchronously on Play - so a nil here means the id was
-- malformed, not that it is playable.
function Rig.loadLoop(animator: Animator, animationId: string, priority: Enum.AnimationPriority): AnimationTrack?
	if animationId == "" then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		warn(`[Rig] could not load animation {animationId}: {track}`)
		return nil
	end

	track.Looped = true
	track.Priority = priority
	return track
end

-- Nothing that ships with a model has anything to do: every behaviour is driven
-- by our own services, a bundled animator would fight them, and a free-model
-- Script running on the server is how backdoors get in.
function Rig.stripScripts(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end
end

-- Welds any part that is jointed to nothing onto the root.
--
-- Parts that already have a joint are left alone: those are the ones an
-- animation drives, and welding them would pin them rigid. Returns how many
-- needed it, so callers can report a rig that should really be built properly.
function Rig.weldLoose(model: Model, root: BasePart): number
	local jointed: { [BasePart]: boolean } = { [root] = true }

	for _, descendant in model:GetDescendants() do
		-- JointInstance covers Motor6D and Weld; WeldConstraint is a separate
		-- class that happens to carry the same two properties
		if descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") then
			local a, b = descendant.Part0, descendant.Part1
			if a then
				jointed[a] = true
			end
			if b then
				jointed[b] = true
			end
		end
	end

	local welded = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and not jointed[descendant] then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = descendant
			weld.Parent = root
			welded += 1
		end
	end

	return welded
end

-- Decoration, not physics: a driven rig must never fall, block a click on
-- something behind it, or trip a touch handler. CanQuery stays on so it can
-- still be raycast at, which is how a player targets one.
function Rig.makeKinematic(model: Model, root: BasePart)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = true
			descendant.CanTouch = false
			descendant.Massless = true
			descendant.Anchored = false
		end
	end

	-- anchoring the root carries the rest, now that the rest is attached to it
	root.Anchored = true

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- The rig is driven by CFrame, so the Humanoid has no idea it is
		-- moving and its state machine would fight us. PlatformStand is not an
		-- option here: it suppresses animations entirely.
		pcall(function()
			humanoid.EvaluateStateMachine = false
		end)
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

return Rig
