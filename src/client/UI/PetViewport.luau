--!strict
-- Live 3D preview of a pet, for UI.
--
-- Viewports rather than uploaded screenshots: a new pet needs nothing beyond
-- its model going in the folder, which keeps "add a pet" at the same three
-- steps as everything else. No capture, no upload, no moderation wait, and the
-- preview can never drift out of sync with the model it represents.
--
-- The cost is that every ViewportFrame is a separate render pass, so this is
-- for places where a small, known number are on screen at once - a hatch
-- reveal, a starter card. Not a two-hundred row list.
--
-- Models must live in ReplicatedStorage: the client cannot see ServerStorage,
-- which is where the real rigs are.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "PetPreviews"
local SPIN_SPEED = 0.5 -- radians/sec when spin is asked for
local PADDING = 1.12 -- >1 leaves a little air around the model
local HEIGHT_BIAS = 0.15 -- camera lift as a fraction of model height

-- Yaw around the model, where 0 puts the camera dead in front of it. A Roblox
-- rig's front is its -Z face, so `look` below negates cos - park the camera on
-- +Z instead and you are staring at the back of every pet in the game.
--
-- 35 degrees off centre rather than 0: a straight-on view flattens a model and
-- hides its depth entirely.
local VIEW_ANGLE = math.rad(35)

-- Hover response. Small numbers on purpose: this should read as the model
-- noticing the cursor, not as a transition.
local HOVER_ZOOM = 0.88 -- fraction of the resting camera distance
local HOVER_YAW = math.rad(-16) -- turns a little further toward the viewer
local HOVER_SMOOTHING = 12 -- how fast it eases between rest and hover

export type Options = {
	spin: boolean?, -- slow continuous turntable
	hoverTarget: GuiObject?, -- element whose hover state animates the preview
	-- Renders the rig as a flat black shadow, for a pet not yet discovered.
	-- Killing the viewport's own lighting is what does it, so the shape stays
	-- perfectly readable while every detail is hidden - which is the point: you
	-- can see there is something to find without seeing what.
	silhouette: boolean?,
}

local PetViewport = {}

-- Every corner of a part in world space. Needed because a part's Size is local
-- and a rotated part's real extents are not its Size.
local function corners(part: BasePart, into: { Vector3 })
	local half = part.Size / 2
	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				table.insert(into, part.CFrame * Vector3.new(half.X * x, half.Y * y, half.Z * z))
			end
		end
	end
end

-- Bounds of what can actually be SEEN, which is not what GetBoundingBox gives.
--
-- A rig's HumanoidRootPart is invisible and frequently sits well off the body,
-- and toolbox models often carry stray invisible collision parts too. Including
-- those inflates the box, which pushes the camera far enough back that the pet
-- renders tiny and orbits around a point that is not its visual centre - so it
-- appears to swing past rather than turn on the spot.
local function visibleBounds(model: Model): (Vector3?, Vector3?)
	local points: { Vector3 } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
			corners(descendant, points)
		end
	end

	if #points == 0 then
		return nil -- nothing visible; caller falls back to the full box
	end

	local min, max = points[1], points[1]
	for index = 2, #points do
		min = min:Min(points[index])
		max = max:Max(points[index])
	end
	return (min + max) / 2, max - min
end

function PetViewport.exists(modelName: string): boolean
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	local template = folder and folder:FindFirstChild(modelName)
	return template ~= nil and template:IsA("Model")
end

-- Returns nil when the model is missing, so every caller can fall back to
-- something textual rather than rendering an empty box.
function PetViewport.create(modelName: string, options: Options?): ViewportFrame?
	local config: Options = options or {}
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	local template = folder and folder:FindFirstChild(modelName)
	if not template or not template:IsA("Model") then
		return nil
	end

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.BackgroundTransparency = 1
	if config.silhouette then
		viewport.Ambient = Color3.new(0, 0, 0)
		viewport.LightColor = Color3.new(0, 0, 0)
	else
		viewport.Ambient = Color3.fromRGB(190, 190, 205)
		viewport.LightColor = Color3.fromRGB(255, 255, 255)
	end
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)

	local model = template:Clone()
	model.Parent = viewport

	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local foundCenter, foundSize = visibleBounds(model)
	if not foundCenter or not foundSize then
		local boxCFrame, boxSize = model:GetBoundingBox()
		foundCenter, foundSize = boxCFrame.Position, boxSize
	end

	-- narrowed once here so the closures below need no casts of their own
	local center = foundCenter :: Vector3
	local size = foundSize :: Vector3

	local height = size.Y * HEIGHT_BIAS
	local distance = math.max(size.Magnitude, 1) -- replaced by frame() below

	-- Each pair is where the camera is now and where it is heading. Easing
	-- between them every frame is what makes hover feel like motion rather
	-- than a jump, and it lets spin and hover compose without fighting.
	local yaw, targetYaw = VIEW_ANGLE, VIEW_ANGLE
	local zoom, targetZoom = 1, 1

	local function look(): CFrame
		local range = distance * zoom
		-- -cos, so yaw 0 is the model's -Z face: its front
		local offset = Vector3.new(math.sin(yaw) * range, height, -math.cos(yaw) * range)
		return CFrame.lookAt(center + offset, center)
	end

	-- Distance from the camera's actual field of view and the frame's aspect
	-- ratio, rather than a guessed multiple of the model's diagonal. The
	-- diagonal always overestimates - it is longer than any single dimension -
	-- which is most of why the first version rendered everything small.
	local function frame()
		local frameSize = viewport.AbsoluteSize
		if frameSize.X <= 0 or frameSize.Y <= 0 then
			return -- not laid out yet; the AbsoluteSize signal below retries
		end

		local halfFov = math.rad(camera.FieldOfView) / 2
		local aspect = frameSize.X / frameSize.Y

		-- fit whichever axis needs the camera furthest away
		local fitHeight = size.Y / 2 / math.tan(halfFov)
		local fitWidth = math.max(size.X, size.Z) / 2 / (math.tan(halfFov) * aspect)

		distance = math.max(fitHeight, fitWidth, 0.5) * PADDING
		camera.CFrame = look()
	end

	-- AbsoluteSize is 0 until the frame has been laid out, and it changes again
	-- if the panel resizes, so this reframes rather than measuring once.
	viewport:GetPropertyChangedSignal("AbsoluteSize"):Connect(frame)
	frame()

	if config.hoverTarget then
		local target = config.hoverTarget
		target.MouseEnter:Connect(function()
			targetYaw = VIEW_ANGLE + HOVER_YAW
			targetZoom = HOVER_ZOOM
		end)
		target.MouseLeave:Connect(function()
			targetYaw = VIEW_ANGLE
			targetZoom = 1
		end)
	end

	if config.spin or config.hoverTarget then
		local connection: RBXScriptConnection
		connection = RunService.RenderStepped:Connect(function(deltaTime)
			-- self-cleaning: the caller owns the viewport and may destroy it at
			-- any time, and a live RenderStepped connection would leak
			if not viewport.Parent then
				connection:Disconnect()
				return
			end

			if config.spin then
				targetYaw += deltaTime * SPIN_SPEED
			end

			-- Nothing to do once it has settled. Without this a static hover
			-- preview would still recompute a CFrame every frame for the
			-- entire time the panel is open.
			local settled = math.abs(targetYaw - yaw) < 0.0005 and math.abs(targetZoom - zoom) < 0.0005
			if settled and not config.spin then
				return
			end

			local alpha = math.min(deltaTime * HOVER_SMOOTHING, 1)
			yaw += (targetYaw - yaw) * alpha
			zoom += (targetZoom - zoom) * alpha
			camera.CFrame = look()
		end)
	end

	return viewport
end

return PetViewport
