--!strict
--[[
	Turns the pure Layout description into real Roblox instances.

	Design notes
	* Geometry is grouped into folders by role so future streaming/LOD work can
	  target "Decor" (the vast majority of parts) separately from structure.
	* Roblox `Part.Shape = Cylinder` runs its axis along local X, while the layout
	  describes Y-up cylinders. The conversion happens once, here.
	* Every interactive object gets an attribute (`EWTag`, `EWId`) so gameplay
	  code never has to guess by name.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage.Shared
local Palette = require(Shared.Palette)
local Layout = require(Shared.Layout)

export type BeaconRuntime = {
	id: string,
	title: string,
	position: Vector3,
	accent: Color3,
	core: Part,
	light: PointLight,
}

export type ShardRuntime = {
	id: number,
	position: Vector3,
	value: number,
	part: Part,
	collected: boolean,
}

export type WorldRuntime = {
	hub: Folder,
	reef: Folder,
	beacons: { [string]: BeaconRuntime },
	shards: { ShardRuntime },
	hubSpawn: Vector3,
	reefSpawn: Vector3,
	exitGate: Vector3,
	diveGate: Part,
	ledgerPrompt: ProximityPrompt,
	codexPrompt: ProximityPrompt,
	exitPrompt: ProximityPrompt,
	gateGlow: Part,
}

local MATERIALS: { [string]: Enum.Material } = {
	Slate = Enum.Material.Slate,
	Neon = Enum.Material.Neon,
	Glass = Enum.Material.Glass,
	Metal = Enum.Material.Metal,
	Fabric = Enum.Material.Fabric,
	ForceField = Enum.Material.ForceField,
	Basalt = Enum.Material.Basalt,
	Cobblestone = Enum.Material.Cobblestone,
}

local Builder = {}

local function toColor(hex: string): Color3
	local r, g, b = Palette.parse(hex)
	return Color3.fromRGB(
		math.floor(r * 255 + 0.5),
		math.floor(g * 255 + 0.5),
		math.floor(b * 255 + 0.5)
	)
end

local function toVector(v: Layout.Vec): Vector3
	return Vector3.new(v.x, v.y, v.z)
end

--[[ Applies a PartSpec to a real part, handling the Y-up cylinder convention. ]]
local function applySpec(part: Part, spec: Layout.PartSpec)
	local color = toColor(spec.color)
	part.Color = color
	part.Material = MATERIALS[spec.mat] or Enum.Material.Slate
	part.Transparency = spec.alpha or 0
	part.CanCollide = spec.tag == "floor" or spec.tag == "wall" or spec.tag == "beaconBase"
	part.CanTouch = false
	part.CanQuery = spec.tag ~= "mote" and spec.tag ~= "water"
	part.CastShadow = spec.cast ~= false
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	local rot = spec.rot or { x = 0, y = 0, z = 0 }
	local position = toVector(spec.pos)

	if spec.shape == "Ball" then
		part.Shape = Enum.PartType.Ball
		part.Size = toVector(spec.size)
		part.CFrame = CFrame.new(position)
	elseif spec.shape == "Cylinder" then
		-- Layout: (diameterX, heightY, diameterZ). Part: axis on X.
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(spec.size.y, spec.size.x, spec.size.z)
		part.CFrame = CFrame.new(position)
			* CFrame.Angles(0, math.rad(rot.y), 0)
			* CFrame.Angles(0, 0, math.rad(90))
	else
		part.Size = toVector(spec.size)
		part.CFrame = CFrame.new(position)
			* CFrame.fromEulerAnglesYXZ(math.rad(rot.y), math.rad(rot.x), math.rad(rot.z))
	end

	part:SetAttribute("EWTag", spec.tag)
	if spec.emissive then
		part:SetAttribute("EWEmissive", spec.emissive)
	end
end

local function createPart(parent: Instance, spec: Layout.PartSpec): Part
	local part = Instance.new("Part")
	applySpec(part, spec)
	part.Name = spec.tag
	part.Parent = parent
	return part
end

local function buildArea(area: Layout.Area, parent: Folder, folderName: string): { Part }
	local root = Instance.new("Folder")
	root.Name = folderName
	root.Parent = parent

	local buckets: { [string]: Folder } = {}
	local function bucketFor(tag: string): Folder
		local key = if tag == "floor"
				or tag == "wall"
				or tag == "roof"
			then "Structure"
			else "Decor"
		local existing = buckets[key]
		if existing then
			return existing
		end
		local folder = Instance.new("Folder")
		folder.Name = key
		folder.Parent = root
		buckets[key] = folder
		return folder
	end

	local created: { Part } = {}
	for _, spec in area.parts do
		table.insert(created, createPart(bucketFor(spec.tag), spec))
	end

	for _, spec in area.lights do
		local part = Instance.new("Part")
		part.Name = "LightAnchor"
		part.Size = Vector3.new(1, 1, 1)
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CFrame = CFrame.new(toVector(spec.pos))
		part.Parent = root
		local point = Instance.new("PointLight")
		local color = toColor(spec.color)
		point.Color = color
		point.Brightness = spec.brightness
		point.Range = spec.range
		point.Shadows = false
		point.Parent = part
	end

	return created
end

local function makePrompt(
	part: Part,
	actionText: string,
	objectText: string,
	holdDuration: number
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = holdDuration
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = part
	return prompt
end

--[[ Ambient particles: cheap, atmospheric, and entirely code-driven. ]]
local function addAmbience(parent: Folder, world: Layout.World)
	local reefFolder = parent:FindFirstChild("Reef") :: Folder?

	local dust = Instance.new("Part")
	dust.Name = "ReefDust"
	dust.Size = Vector3.new(180, 90, 310)
	dust.Transparency = 1
	dust.Anchored = true
	dust.CanCollide = false
	dust.CanQuery = false
	dust.CanTouch = false
	dust.CFrame = CFrame.new(0, 40, 0)
	dust.Parent = reefFolder

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(toColor(Palette.Hex.Mint), toColor(Palette.Hex.CyanDeep))
	emitter.Size = NumberSequence.new(0.12, 0.28)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(6, 14)
	emitter.Rate = 22
	emitter.Speed = NumberRange.new(0.3, 1.2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 0.7
	emitter.Parent = dust

	if world.hub then
		local hubFolder = parent:FindFirstChild("Hub") :: Folder?
		if hubFolder then
			local hubDust = dust:Clone()
			hubDust.Name = "HubDust"
			hubDust.Size = Vector3.new(120, 90, 120)
			hubDust.CFrame =
				CFrame.new(world.hub.tower.x, world.hub.tower.y - 20, world.hub.tower.z)
			hubDust.Parent = hubFolder
			local hubEmitter = hubDust:FindFirstChildOfClass("ParticleEmitter")
			if hubEmitter then
				hubEmitter.Color = ColorSequence.new(toColor(Palette.Hex.Ember))
				hubEmitter.Rate = 14
			end
		end
	end
end

--[[ Builds both areas and wires up every interactive object. ]]
function Builder.build(seed: number?): WorldRuntime
	local world = Layout.build(seed)

	local root = Instance.new("Folder")
	root.Name = "EchowakeWorld"
	root.Parent = workspace

	local hubFolder = Instance.new("Folder")
	hubFolder.Name = "Hub"
	hubFolder.Parent = root

	buildArea(world.hub, hubFolder, "HubGeometry")

	local reefFolder = Instance.new("Folder")
	reefFolder.Name = "Reef"
	reefFolder.Parent = root
	buildArea(world.reef, reefFolder, "ReefGeometry")

	addAmbience(root, world)

	-- Beacons ---------------------------------------------------------------
	local beacons: { [string]: BeaconRuntime } = {}
	local reefGeometry = reefFolder:FindFirstChild("ReefGeometry") :: Folder
	local decor = reefGeometry:FindFirstChild("Decor") :: Folder
	-- Layout emits beacon decoration in definition order; walk the sorted-by-position
	-- list to bind each core to its beacon definition reliably.
	local cores: { Part } = {}
	for _, child in decor:GetChildren() do
		if child:IsA("Part") and child:GetAttribute("EWTag") == "beaconCore" then
			table.insert(cores, child)
		end
	end
	table.sort(cores, function(a: Part, b: Part): boolean
		if a.Position.Z ~= b.Position.Z then
			return a.Position.Z > b.Position.Z
		end
		return a.Position.X < b.Position.X
	end)

	for beaconIndex, spec in world.reef.beacons do
		local core = cores[beaconIndex]
		if core then
			local accent = toColor(spec.accent)
			core.Color = accent
			core:SetAttribute("EWId", spec.id)
			CollectionService:AddTag(core, "EchowakeBeaconCore")

			local point = Instance.new("PointLight")
			point.Color = accent
			point.Brightness = 0.6
			point.Range = 26
			point.Shadows = false
			point.Parent = core

			local emitter = Instance.new("ParticleEmitter")
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Color = ColorSequence.new(accent)
			emitter.Size = NumberSequence.new(0.6, 0.05)
			emitter.Transparency = NumberSequence.new(0.2, 1)
			emitter.Lifetime = NumberRange.new(0.8, 1.8)
			emitter.Rate = 8
			emitter.Speed = NumberRange.new(2, 6)
			emitter.SpreadAngle = Vector2.new(35, 35)
			emitter.LightEmission = 1
			emitter.Parent = core

			beacons[spec.id] = {
				id = spec.id,
				title = spec.title,
				position = toVector(spec.pos),
				accent = accent,
				core = core,
				light = point,
			}
		end
	end

	-- Ember motes -----------------------------------------------------------
	local shards: { ShardRuntime } = {}
	local shardFolder = Instance.new("Folder")
	shardFolder.Name = "Embers"
	shardFolder.Parent = reefFolder
	for _, spec in world.reef.shards do
		local part = Instance.new("Part")
		part.Name = `Ember_{spec.id}`
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(1.5, 1.5, 1.5)
		part.Color = toColor(Palette.Hex.Ember)
		part.Material = Enum.Material.Neon
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.CFrame = CFrame.new(toVector(spec.pos))
		part:SetAttribute("EWTag", "ember")
		part:SetAttribute("EWId", spec.id)
		part.Parent = shardFolder

		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color = ColorSequence.new(toColor(Palette.Hex.Gold))
		sparkle.Size = NumberSequence.new(0.35, 0)
		sparkle.Transparency = NumberSequence.new(0.2, 1)
		sparkle.Lifetime = NumberRange.new(0.5, 1.1)
		sparkle.Rate = 6
		sparkle.Speed = NumberRange.new(0.5, 2)
		sparkle.LightEmission = 1
		sparkle.Parent = part

		table.insert(shards, {
			id = spec.id,
			position = toVector(spec.pos),
			value = spec.value,
			part = part,
			collected = false,
		})
	end

	-- Spawns ----------------------------------------------------------------
	local hubSpawn = toVector(world.hub.spawns[1])
	local reefSpawn = toVector(world.reef.spawns[1])

	local hubSpawnPad = Instance.new("SpawnLocation")
	hubSpawnPad.Name = "HubSpawn"
	hubSpawnPad.Size = Vector3.new(14, 1, 14)
	hubSpawnPad.Transparency = 1
	hubSpawnPad.Anchored = true
	hubSpawnPad.CanCollide = false
	hubSpawnPad.Neutral = true
	hubSpawnPad.Duration = 0
	hubSpawnPad.CFrame = CFrame.new(hubSpawn)
	hubSpawnPad.Parent = hubFolder

	local reefSpawnPad = Instance.new("SpawnLocation")
	reefSpawnPad.Name = "ReefSpawn"
	reefSpawnPad.Size = Vector3.new(14, 1, 14)
	reefSpawnPad.Transparency = 1
	reefSpawnPad.Anchored = true
	reefSpawnPad.CanCollide = false
	reefSpawnPad.Neutral = true
	reefSpawnPad.Duration = 0
	reefSpawnPad.CFrame = CFrame.new(reefSpawn)
	reefSpawnPad.Parent = reefFolder

	-- Interactive prompts ---------------------------------------------------
	local function findTagged(folder: Instance, tag: string): Part?
		for _, descendant in folder:GetDescendants() do
			if descendant:IsA("Part") and descendant:GetAttribute("EWTag") == tag then
				return descendant
			end
		end
		return nil
	end

	local gatePart = findTagged(hubFolder, "diveGate")
	local ledgerPart = findTagged(hubFolder, "ledgerboard")
	local codexPart = findTagged(hubFolder, "codexStone")
	local exitPart = findTagged(reefFolder, "gate")

	if not (gatePart and ledgerPart and codexPart and exitPart) then
		error("ECHOWAKE: world is missing an interactive anchor")
	end

	local diveGatePrompt = makePrompt(gatePart, "Descend", "The Dive Gate", 0.6)
	diveGatePrompt.Name = "DivePrompt"

	local ledgerPrompt = makePrompt(ledgerPart, "Open", "The Ledger", 0)
	ledgerPrompt.Name = "LedgerPrompt"

	local codexPrompt = makePrompt(codexPart, "Read", "The Codex", 0)
	codexPrompt.Name = "CodexPrompt"

	local exitPrompt = makePrompt(exitPart, "Ascend", "Return Gate", 0.9)
	exitPrompt.Name = "ExitPrompt"
	exitPrompt.Enabled = false

	-- A "gate glow" part we recolour to signal that the exit is open.
	local gateGlow = exitPart

	local worldRuntime: WorldRuntime = {
		hub = hubFolder,
		reef = reefFolder,
		beacons = beacons,
		shards = shards,
		hubSpawn = hubSpawn,
		reefSpawn = reefSpawn,
		exitGate = toVector(world.reef.exitGate),
		diveGate = gatePart,
		ledgerPrompt = ledgerPrompt,
		codexPrompt = codexPrompt,
		exitPrompt = exitPrompt,
		gateGlow = gateGlow,
	}

	return worldRuntime
end

return Builder
