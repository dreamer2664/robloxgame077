--!strict
--[[
	Server-owned Gloam population.

	The brain (shared/GloamBrain) decides where an agent wants to be; this service
	owns the parts, the swarm bookkeeping, contact damage and flare resolution.
	Nothing about an agent's position or health ever comes from a client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Codex = require(Shared.Codex)
local GloamBrain = require(Shared.GloamBrain)
local LightMath = require(Shared.LightMath)
local Palette = require(Shared.Palette)
local Random = require(Shared.Random)

export type Agent = GloamBrain.Agent
export type Context = GloamBrain.Context

export type GloamRecord = {
	agent: Agent,
	part: Part,
}

local GloamService = {}
GloamService.__index = GloamService

export type GloamService = typeof(setmetatable(
	{} :: {
		folder: Folder?,
		records: { GloamRecord },
		nextId: number,
		rng: Random.Rng,
		active: boolean,
		kindsSeen: { [string]: boolean },
	},
	GloamService
))

local function toColor(hex: string): Color3
	local r, g, b = Palette.parse(hex)
	return Color3.fromRGB(
		math.floor(r * 255 + 0.5),
		math.floor(g * 255 + 0.5),
		math.floor(b * 255 + 0.5)
	)
end

function GloamService.new(): GloamService
	local self = setmetatable({}, GloamService)
	self.records = {}
	self.nextId = 0
	self.rng = Random.new(os.time())
	self.active = false
	self.kindsSeen = {}
	return self
end

function GloamService.start(self: GloamService)
	local folder = Instance.new("Folder")
	folder.Name = "Gloam"
	folder.Parent = workspace
	self.folder = folder
end

function GloamService.createPart(_self: GloamService, archetype: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Name = `Gloam_{archetype.id}`
	part.Shape = Enum.PartType.Ball
	local radius = (archetype.radius :: number) * 2
	part.Size = Vector3.new(radius, radius * 1.15, radius)
	part.Color = toColor(archetype.color :: string)
	part.Material = Enum.Material.Neon
	part.Transparency = 0.62
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part:SetAttribute("EWTag", "gloam")

	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(radius * 0.45, radius * 0.45, radius * 0.45)
	core.Color = toColor(archetype.accent :: string)
	core.Material = Enum.Material.Neon
	core.Transparency = 0.1
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.CastShadow = false
	core.Parent = part

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(toColor(archetype.color :: string))
	sparkle.Size = NumberSequence.new(0.5, 0)
	sparkle.Transparency = NumberSequence.new(0.3, 1)
	sparkle.Lifetime = NumberRange.new(0.3, 0.7)
	sparkle.Rate = 10
	sparkle.Speed = NumberRange.new(0.4, 1.4)
	sparkle.LightEmission = 0.8
	sparkle.Parent = part

	return part
end

function GloamService.spawn(self: GloamService, kind: string, position: Vector3): GloamRecord?
	local folder = self.folder
	if not folder then
		return nil
	end
	if #self.records >= Config.Gloam.MaxAlive then
		return nil
	end
	local archetype = Codex.get(kind)
	if not archetype then
		return nil
	end
	self.nextId += 1
	local agent = GloamBrain.new(self.nextId, kind, position)
	local part = self:createPart(archetype :: any)
	part:SetAttribute("EWGloamId", agent.id)
	part:SetAttribute("EWKind", kind)
	part.CFrame = CFrame.new(position)
	part.Parent = folder
	self.kindsSeen[kind] = true
	local record: GloamRecord = { agent = agent, part = part }
	table.insert(self.records, record)
	return record
end

--[[ Spawns `count` agents in a ring around an anchor, avoiding the anchor itself. ]]
function GloamService.spawnWave(
	self: GloamService,
	count: number,
	anchor: Vector3,
	kinds: { string }?
)
	local palette = kinds or { "Drifter", "Drifter", "Lunger" }
	for _ = 1, count do
		local angle = self.rng:range(0, math.pi * 2)
		local distance = self.rng:range(Config.Gloam.SpawnRadiusMin, Config.Gloam.SpawnRadiusMax)
		local position = Vector3.new(
			anchor.X + math.cos(angle) * distance,
			anchor.Y + 2.4,
			anchor.Z + math.sin(angle) * distance
		)
		local kind = palette[self.rng:int(1, #palette)]
		self:spawn(kind, position)
	end
end

function GloamService.clear(self: GloamService)
	for _, record in self.records do
		record.part:Destroy()
	end
	self.records = {}
end

--[[ Bends nearby agents toward a sound (used by the player's pulse). ]]
function GloamService.attract(self: GloamService, origin: Vector3, radius: number)
	for _, record in self.records do
		if (record.agent.position - origin).Magnitude <= radius then
			record.agent.attractPoint = origin
			record.agent.attractTimer = Config.Gloam.PulseAttractTime
		end
	end
end

--[[ Applies flare damage in a cone. Returns the number of kills. ]]
function GloamService.damageCone(
	self: GloamService,
	origin: Vector3,
	forward: Vector3,
	range: number,
	halfAngle: number,
	damage: number
): (number, { Vector3 })
	local positions: { Vector3 } = {}
	for _, record in self.records do
		table.insert(positions, record.agent.position)
	end
	local hits = LightMath.flareTargets(origin, forward, positions, range, halfAngle, damage)
	local kills = 0
	local deadPositions: { Vector3 } = {}
	for _, hit in hits do
		local record = self.records[hit.index]
		if record then
			local died = GloamBrain.hit(record.agent, hit.damage, Config.Light.FlareStagger)
			if died then
				kills += 1
				table.insert(deadPositions, record.agent.position)
			end
		end
	end
	return kills, deadPositions
end

--[[ Positions of agents within radius, for the client's "echo outline". ]]
function GloamService.revealInRadius(
	self: GloamService,
	origin: Vector3,
	radius: number
): { number }
	local ids: { number } = {}
	for _, record in self.records do
		if (record.agent.position - origin).Magnitude <= radius then
			table.insert(ids, record.agent.id)
			record.part:SetAttribute("EWRevealed", true)
		end
	end
	return ids
end

--[[ How many agents are actively draining a beacon at `position`. ]]
function GloamService.countDraining(self: GloamService, position: Vector3, radius: number): number
	local count = 0
	for _, record in self.records do
		if
			record.agent.mode == "drain"
			and (record.agent.position - position).Magnitude <= radius
		then
			count += 1
		end
	end
	return count
end

function GloamService.getById(self: GloamService, id: number): GloamRecord?
	for _, record in self.records do
		if record.agent.id == id then
			return record
		end
	end
	return nil
end

export type TickResult = {
	contacts: { { userId: number, amount: number, kind: string, position: Vector3 } },
}

--[[ One AI tick. `ctxProvider` returns the current world context. ]]
function GloamService.tick(self: GloamService, dt: number, ctxProvider: () -> Context?): TickResult
	local result: TickResult = { contacts = {} }
	local ctx = ctxProvider()
	if not ctx then
		return result
	end

	local neighbours: { Vector3 } = {}
	for _, record in self.records do
		table.insert(neighbours, record.agent.position)
	end

	local dead: { number } = {}
	for index, record in self.records do
		local agent = record.agent
		GloamBrain.step(agent, ctx, dt, neighbours)

		if agent.mode == "dead" then
			table.insert(dead, index)
		else
			record.part.CFrame = CFrame.new(agent.position)
			local core = record.part:FindFirstChild("Core")
			if core and core:IsA("BasePart") then
				core.CFrame = record.part.CFrame
			end
		end
	end

	-- Remove the fallen (reverse order keeps indices valid).
	for i = #dead, 1, -1 do
		local index = dead[i]
		local record = self.records[index]
		if record then
			record.part:Destroy()
			table.remove(self.records, index)
		end
	end

	return result
end

--[[ Contact damage test, resolved by the dive service so light stays authoritative. ]]
function GloamService.contacts(
	self: GloamService,
	targets: { { userId: number, position: Vector3 } },
	now: number
): { { userId: number, amount: number, kind: string, position: Vector3 } }
	local contacts = {}
	for _, record in self.records do
		local agent = record.agent
		if agent.mode ~= "dead" and now - agent.lastHitAt >= Config.Gloam.ContactCooldown then
			for _, target in targets do
				local distance = (agent.position - target.position).Magnitude
				if distance <= agent.radius + 3.6 then
					agent.lastHitAt = now
					table.insert(contacts, {
						userId = target.userId,
						amount = Config.Gloam.ContactDamage,
						kind = agent.kind,
						position = agent.position,
					})
					break
				end
			end
		end
	end
	return contacts
end

function GloamService.count(self: GloamService): number
	return #self.records
end

return GloamService
