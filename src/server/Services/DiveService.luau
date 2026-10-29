--!strict
--[[
	The dive: the whole gameplay loop, server side.

	Responsibilities
	* run state machine (hub -> dive -> payout -> hub),
	* the lantern economy (light is health, ammo and visibility at once),
	* beacons, ember motes and the exit gate,
	* pulse / flare resolution and Gloam population,
	* payouts and progression hand-off to persistence.

	Every number that matters is computed here; clients only *present* state.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Codex = require(Shared.Codex)
local GloamBrain = require(Shared.GloamBrain)
local LightMath = require(Shared.LightMath)
local Net = require(Shared.Net)
local Progression = require(Shared.Progression)
local SaveSchema = require(Shared.SaveSchema)

local App = require(script.Parent.Parent.App)

type App = App.App

export type DiverState = {
	userId: number,
	light: number,
	capacity: number,
	regen: number,
	carried: number,
	sprinting: boolean,
	lastSpendAt: number,
	lastPulseAt: number,
	lastFlareAt: number,
	joinedAt: number,
	pulseRadius: number,
	revealDuration: number,
	flareDamage: number,
	lanternRadius: number,
	out: boolean,
}

export type BeaconState = {
	id: string,
	title: string,
	position: Vector3,
	accent: Color3,
	core: Part,
	light: PointLight,
	progress: number,
	lit: boolean,
}

type Phase = "hub" | "dive" | "closing"

local PULSE_FLOOR = 5 -- the lantern never spends its last thread of light
local TICK = 0.1

local DiveService = {}
DiveService.__index = DiveService

export type DiveService = typeof(setmetatable(
	{} :: {
		app: App?,
		phase: Phase,
		timeLeft: number,
		beacons: { [string]: BeaconState },
		beaconOrder: { string },
		beaconsLit: number,
		divers: { [Player]: DiverState },
		complete: boolean,
		runStartedAt: number,
		accumulator: number,
		broadcastAt: number,
		maintainAt: number,
		kindsThisRun: { [string]: boolean },
		lastDiveBy: { [number]: number },
	},
	DiveService
))

function DiveService.new(): DiveService
	local self = setmetatable({
		app = nil,
		phase = "hub" :: Phase,
		timeLeft = 0,
		beacons = {} :: { [string]: BeaconState },
		beaconOrder = {} :: { string },
		beaconsLit = 0,
		divers = {} :: { [Player]: DiverState },
		complete = false,
		runStartedAt = 0,
		accumulator = 0,
		broadcastAt = 0,
		maintainAt = 0,
		kindsThisRun = {} :: { [string]: boolean },
		lastDiveBy = {} :: { [number]: number },
	}, DiveService)
	return self
end

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

local function characterRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

function DiveService.teleport(
	_self: DiveService,
	player: Player,
	position: Vector3,
	lookAt: Vector3?
)
	local root = characterRoot(player)
	if not root then
		return
	end
	local target = if lookAt
		then CFrame.lookAt(position + Vector3.new(0, 3.2, 0), lookAt)
		else CFrame.new(position + Vector3.new(0, 3.2, 0))
	root.CFrame = target
	root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
end

local function statsFor(app: App, player: Player): Progression.Stats
	local record = app.data:get(player)
	local save = if record then record.save else SaveSchema.default(os.time())
	return Progression.stats(save)
end

local function applyStats(app: App, player: Player, diver: DiverState)
	local stats = statsFor(app, player)
	diver.capacity = stats.capacity
	diver.regen = stats.regenPerSecond
	diver.pulseRadius = stats.pulseRadius
	diver.revealDuration = stats.revealDuration
	diver.flareDamage = stats.flareDamage
	diver.lanternRadius = stats.lanternRadius
	diver.light = math.min(diver.light, diver.capacity)
end

local function setWalkSpeed(player: Player, speed: number)
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.WalkSpeed = speed
	end
end

--------------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------------

function DiveService.start(self: DiveService, app: App)
	self.app = app

	for _, beaconSpec in app.world.beacons do
		local core = beaconSpec.core
		local state: BeaconState = {
			id = beaconSpec.id,
			title = beaconSpec.title,
			position = beaconSpec.position,
			accent = beaconSpec.accent,
			core = core,
			light = beaconSpec.light,
			progress = 0,
			lit = false,
		}
		self.beacons[beaconSpec.id] = state
		table.insert(self.beaconOrder, beaconSpec.id)
	end

	-- World prompts ---------------------------------------------------------
	local divePrompt = app.world.diveGate:FindFirstChildOfClass("ProximityPrompt")
	if divePrompt then
		divePrompt.Triggered:Connect(function(player: Player)
			self:requestDive(player)
		end)
	end
	app.world.ledgerPrompt.Triggered:Connect(function(player: Player)
		self:pushPanel(player, "ledger")
	end)
	app.world.codexPrompt.Triggered:Connect(function(player: Player)
		self:pushPanel(player, "codex")
	end)
	app.world.exitPrompt.Triggered:Connect(function(player: Player)
		self:requestEscape(player)
	end)

	-- Intents ---------------------------------------------------------------
	app.net:onIntent(Net.Intent.Dive, function(player: Player)
		self:requestDive(player)
	end)
	app.net:onIntent(Net.Intent.Leave, function(player: Player)
		self:requestEscape(player, true)
	end)
	app.net:onIntent(Net.Intent.Pulse, function(player: Player)
		self:requestPulse(player)
	end)
	app.net:onIntent(Net.Intent.Flare, function(player: Player, payload: any)
		self:requestFlare(player, payload)
	end)
	app.net:onIntent(Net.Intent.Sprint, function(player: Player, payload: any)
		self:setSprint(player, payload.on == true)
	end)
	app.net:onIntent(Net.Intent.Upgrade, function(player: Player, payload: any)
		self:purchaseUpgrade(player, payload.id)
	end)
	app.net:onIntent(Net.Intent.Hue, function(player: Player, payload: any)
		self:purchaseHue(player, payload.id)
	end)
	app.net:onIntent(Net.Intent.Codex, function(player: Player, payload: any)
		self:recordCodex(player, payload.id)
	end)

	-- Queries ---------------------------------------------------------------
	app.net:onQuery(Net.Query.State, function(player: Player)
		return self:buildStatePayload(player)
	end)
	app.net:onQuery(Net.Query.Ledger, function(player: Player)
		return app.board:getCached(player)
	end)

	-- Character management ---------------------------------------------------
	Players.CharacterAdded:Connect(function(character: Model)
		local player = Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		task.defer(function()
			self:onCharacterReady(player)
		end)
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		self:step(dt)
	end)
end

--[[ Called by init once a character exists (including respawns). ]]
function DiveService.onCharacterReady(self: DiveService, player: Player)
	local app = self.app
	if not app then
		return
	end
	local diver = self.divers[player]
	local spawnPosition: Vector3
	if diver and self.phase == "dive" and not diver.out then
		spawnPosition = app.world.reefSpawn
		self:teleport(player, spawnPosition, spawnPosition + Vector3.new(0, 0, -10))
		setWalkSpeed(player, Config.Light.WalkSpeed)
	else
		spawnPosition = app.world.hubSpawn
		self:teleport(player, spawnPosition, app.world.exitGate)
		setWalkSpeed(player, Config.Light.WalkSpeed)
	end
	local stats = statsFor(app, player)
	app.net:signal(
		player,
		Net.Signal.Light,
		{ value = stats.capacity, capacity = stats.capacity } :: Net.LightPayload
	)
	app.net:signal(player, Net.Signal.Phase, { phase = self.phase, inDive = diver ~= nil })
	self:pushSave(player)
end

function DiveService.pushSave(self: DiveService, player: Player)
	local app = self.app
	if not app then
		return
	end
	local record = app.data:get(player)
	if not record then
		return
	end
	app.net:signal(player, Net.Signal.Save, {
		save = record.save,
		stats = Progression.stats(record.save),
		rank = select(1, Progression.rank(record.save)),
		readOnly = record.readOnly,
	})
end

function DiveService.pushPanel(self: DiveService, player: Player, name: string)
	local app = self.app
	if not app then
		return
	end
	app.net:signal(player, Net.Signal.Panel, { name = name })
end

function DiveService.buildStatePayload(self: DiveService, player: Player): any
	local app = self.app
	if not app then
		return nil
	end
	local record = app.data:get(player)
	local save = if record then record.save else SaveSchema.default(os.time())
	local beacons = {}
	for _, id in self.beaconOrder do
		local beacon = self.beacons[id]
		table.insert(
			beacons,
			{ id = beacon.id, title = beacon.title, progress = beacon.progress, lit = beacon.lit }
		)
	end
	return {
		phase = self.phase,
		timeLeft = self.timeLeft,
		save = save,
		stats = Progression.stats(save),
		rank = select(1, Progression.rank(save)),
		beacons = beacons,
		complete = self.complete,
		beaconCount = #self.beaconOrder,
		inDive = self.divers[player] ~= nil,
		server = {
			divers = self:countDivers(),
			gloam = app.gloam:count(),
		},
	}
end

--------------------------------------------------------------------------------
-- dive entry / exit
--------------------------------------------------------------------------------

function DiveService.countDivers(self: DiveService): number
	local count = 0
	for _ in self.divers do
		count += 1
	end
	return count
end

function DiveService.requestDive(self: DiveService, player: Player)
	local app = self.app
	if not app then
		return
	end
	if self.divers[player] then
		app.net:signal(player, Net.Signal.Toast, { text = "You are already below.", tone = "warn" })
		return
	end
	if self.phase == "closing" then
		app.net:signal(
			player,
			Net.Signal.Toast,
			{ text = "The tide is turning. Wait a moment.", tone = "warn" }
		)
		return
	end
	if self.phase == "hub" then
		self:beginRun(player)
	else
		if self:countDivers() >= Config.Dive.MaxPlayers then
			app.net:signal(player, Net.Signal.Toast, { text = "This dive is full.", tone = "warn" })
			return
		end
		self:addDiver(player)
	end
end

function DiveService.beginRun(self: DiveService, player: Player)
	local app = self.app
	if not app then
		return
	end
	self.phase = "dive"
	self.complete = false
	self.beaconsLit = 0
	self.kindsThisRun = {}
	self.runStartedAt = os.clock()
	self.timeLeft = Config.Dive.Duration
	self.accumulator = 0
	self.maintainAt = 0

	for _, id in self.beaconOrder do
		local beacon = self.beacons[id]
		beacon.progress = 0
		beacon.lit = false
		self:paintBeacon(beacon)
	end

	for _, shard in app.world.shards do
		shard.collected = false
		shard.part.Transparency = 0
		shard.part.CanQuery = false
	end

	app.world.exitPrompt.Enabled = false
	app.gloam:reset()

	self:addDiver(player)
	self:spawnInitialSwarm()
	app.net:signalAll(
		Net.Signal.Phase,
		{ phase = "dive", message = "The tide holds. Relight the three beacons." }
	)
	self:broadcastRun()
end

function DiveService.addDiver(self: DiveService, player: Player)
	local app = self.app
	if not app then
		return
	end
	local stats = statsFor(app, player)
	local diver: DiverState = {
		userId = player.UserId,
		light = stats.capacity,
		capacity = stats.capacity,
		regen = stats.regenPerSecond,
		carried = 0,
		sprinting = false,
		lastSpendAt = 0,
		lastPulseAt = -100,
		lastFlareAt = -100,
		joinedAt = os.clock(),
		pulseRadius = stats.pulseRadius,
		revealDuration = stats.revealDuration,
		flareDamage = stats.flareDamage,
		lanternRadius = stats.lanternRadius,
		out = false,
	}
	self.divers[player] = diver

	local spawn = app.world.reefSpawn
	local offset = Vector3.new((self:countDivers() - 1) * 4 - 6, 0, 0)
	self:teleport(player, spawn + offset, spawn + Vector3.new(0, 0, -20))
	setWalkSpeed(player, Config.Light.WalkSpeed)
	app.net:signal(
		player,
		Net.Signal.Light,
		{ value = diver.light, capacity = diver.capacity } :: Net.LightPayload
	)
	app.net:signal(player, Net.Signal.Phase, { phase = "dive", inDive = true })
	app.net:signal(
		player,
		Net.Signal.Toast,
		{ text = "Lantern lit. Sound the dark with [Q].", tone = "info" }
	)
	self:pushSave(player)
	self:broadcastRun()
end

function DiveService.requestEscape(self: DiveService, player: Player, forced: boolean?)
	local app = self.app
	if not app then
		return
	end
	local diver = self.divers[player]
	if not diver then
		return
	end
	if not forced and not self.complete then
		app.net:signal(
			player,
			Net.Signal.Toast,
			{ text = "The gate is dark. Relight all three beacons.", tone = "warn" }
		)
		return
	end
	self:settle(player, if forced then "leave" else "escape")
end

--------------------------------------------------------------------------------
-- lantern economy
--------------------------------------------------------------------------------

function DiveService.spendLight(_self: DiveService, diver: DiverState, cost: number): boolean
	local ok, newValue = LightMath.spend(diver.light, cost, PULSE_FLOOR)
	if not ok then
		return false
	end
	diver.light = newValue
	diver.lastSpendAt = os.clock()
	return true
end

function DiveService.requestPulse(self: DiveService, player: Player)
	local app = self.app
	if not app then
		return
	end
	local diver = self.divers[player]
	if not diver then
		return
	end
	local now = os.clock()
	if now - diver.lastPulseAt < Config.Light.PulseCooldown then
		return
	end
	if not self:spendLight(diver, Config.Light.PulseCost) then
		app.net:signal(
			player,
			Net.Signal.Toast,
			{ text = "Not enough light to sound.", tone = "warn" }
		)
		return
	end
	diver.lastPulseAt = now

	local root = characterRoot(player)
	if not root then
		return
	end
	local origin = root.Position
	local radius = diver.pulseRadius

	app.net:signalAll(Net.Signal.Pulse, {
		x = origin.X,
		y = origin.Y,
		z = origin.Z,
		radius = radius,
		userId = player.UserId,
	})

	local ids = app.gloam:revealInRadius(origin, radius)
	app.gloam:attract(origin, Config.Gloam.PulseAttractRadius)
	app.net:signal(player, Net.Signal.Reveal, {
		ids = ids,
		duration = diver.revealDuration,
		origin = { x = origin.X, y = origin.Y, z = origin.Z },
		radius = radius,
	})
	app.net:signal(
		player,
		Net.Signal.Light,
		{ value = diver.light, capacity = diver.capacity } :: Net.LightPayload
	)
end

function DiveService.requestFlare(self: DiveService, player: Player, payload: any)
	local app = self.app
	if not app then
		return
	end
	local diver = self.divers[player]
	if not diver then
		return
	end
	local aim = payload and payload.aim
	if not aim or type(aim) ~= "table" then
		return
	end
	local direction = Vector3.new(aim.x, aim.y, aim.z)
	if direction.Magnitude < 0.1 or direction.Magnitude > 2 then
		return
	end
	local now = os.clock()
	if now - diver.lastFlareAt < Config.Light.FlareCooldown then
		return
	end
	if not self:spendLight(diver, Config.Light.FlareCost) then
		app.net:signal(
			player,
			Net.Signal.Toast,
			{ text = "Not enough light to flare.", tone = "warn" }
		)
		return
	end
	diver.lastFlareAt = now

	local root = characterRoot(player)
	if not root then
		return
	end
	local origin = root.Position
	local forward = direction.Unit
	local kills = app.gloam:damageCone(
		origin,
		forward,
		Config.Light.FlareRange,
		Config.Light.FlareHalfAngle,
		diver.flareDamage
	)
	app.net:signalAll(Net.Signal.Flare, {
		x = origin.X,
		y = origin.Y,
		z = origin.Z,
		ax = forward.X,
		ay = forward.Y,
		az = forward.Z,
		kills = kills,
	})
	app.net:signal(
		player,
		Net.Signal.Light,
		{ value = diver.light, capacity = diver.capacity } :: Net.LightPayload
	)
end

function DiveService.setSprint(self: DiveService, player: Player, on: boolean)
	local diver = self.divers[player]
	if not diver then
		return
	end
	diver.sprinting = on
	setWalkSpeed(player, if on then Config.Light.SprintSpeed else Config.Light.WalkSpeed)
end

--[[ Applies damage to a diver's light. Light *is* health. ]]
function DiveService.damageLight(
	self: DiveService,
	player: Player,
	amount: number,
	sourcePosition: Vector3
)
	local app = self.app
	if not app then
		return
	end
	local diver = self.divers[player]
	if not diver or diver.out then
		return
	end
	diver.light = math.max(0, diver.light - amount)
	app.net:signal(player, Net.Signal.Hit, {
		x = sourcePosition.X,
		y = sourcePosition.Y,
		z = sourcePosition.Z,
		amount = amount,
	})
	if diver.light <= 0 then
		self:settle(player, "doused")
	else
		app.net:signal(
			player,
			Net.Signal.Light,
			{ value = diver.light, capacity = diver.capacity } :: Net.LightPayload
		)
	end
end

--------------------------------------------------------------------------------
-- beacons / shards / population
--------------------------------------------------------------------------------

function DiveService.paintBeacon(_self: DiveService, beacon: BeaconState)
	if beacon.lit then
		beacon.core.Transparency = 0.02
		beacon.core.Color = Color3.new(
			math.min(1, beacon.accent.R * 1.15 + 0.1),
			math.min(1, beacon.accent.G * 1.15 + 0.1),
			math.min(1, beacon.accent.B * 1.15 + 0.1)
		)
		beacon.light.Brightness = 5.5
		beacon.light.Range = 64
	else
		beacon.core.Transparency = 0.55
		beacon.core.Color = Color3.fromRGB(40, 62, 74)
		beacon.light.Brightness = 0.5
		beacon.light.Range = 24
	end
end

function DiveService.lightBeacon(self: DiveService, beacon: BeaconState)
	local app = self.app
	if not app then
		return
	end
	if beacon.lit then
		return
	end
	beacon.lit = true
	beacon.progress = 1
	self.beaconsLit += 1
	self:paintBeacon(beacon)

	local burst = Instance.new("Part")
	burst.Shape = Enum.PartType.Ball
	burst.Size = Vector3.new(6, 6, 6)
	burst.Color = beacon.accent
	burst.Material = Enum.Material.Neon
	burst.Transparency = 0.2
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanQuery = false
	burst.CanTouch = false
	burst.CFrame = CFrame.new(beacon.position + Vector3.new(0, 12, 0))
	burst.Parent = app.world.reef

	task.spawn(function()
		for step = 1, 26 do
			local alpha = step / 26
			burst.Size = Vector3.new(6 + alpha * 40, 6 + alpha * 40, 6 + alpha * 40)
			burst.Transparency = 0.2 + alpha * 0.8
			task.wait(0.03)
		end
		burst:Destroy()
	end)

	app.net:signalAll(Net.Signal.Toast, {
		text = `{beacon.title} relit. ({self.beaconsLit}/{#self.beaconOrder})`,
		tone = "good",
	})

	if self.beaconsLit >= #self.beaconOrder and not self.complete then
		self.complete = true
		app.world.exitPrompt.Enabled = true
		app.world.gateGlow.Color = Color3.fromRGB(155, 246, 216)
		app.net:signalAll(Net.Signal.Toast, {
			text = "All beacons burn. The gate is open - ascend when you are ready.",
			tone = "good",
		})
		app.net:signalAll(Net.Signal.Phase, { phase = "dive", message = "The gate is open." })
	end
	self:broadcastRun()
end

function DiveService.spawnInitialSwarm(self: DiveService)
	local app = self.app
	if not app then
		return
	end
	local divers = math.max(1, self:countDivers())
	local count = Config.Gloam.BasePopulation + (divers - 1) * Config.Gloam.PopulationPerPlayer
	app.gloam:spawnWave(count, Vector3.new(0, 2, -20), { "Drifter", "Drifter", "Lunger" })
	if #self.beaconOrder > 0 then
		local firstBeacon = self.beacons[self.beaconOrder[2] or self.beaconOrder[1]]
		app.gloam:spawn("Siphon", firstBeacon.position + Vector3.new(6, 2, 6))
	end
end

function DiveService.maintainSwarm(self: DiveService)
	local app = self.app
	if not app then
		return
	end
	local unlit = #self.beaconOrder - self.beaconsLit
	local target = Config.Gloam.BasePopulation
		+ (self:countDivers() - 1) * Config.Gloam.PopulationPerPlayer
	target += unlit * Config.Gloam.PopulationPerUnlitBeacon
	target = math.clamp(target, 4, Config.Gloam.MaxAlive)
	local current = app.gloam:count()
	if current < target then
		local kinds = { "Drifter", "Drifter", "Lunger" }
		if unlit > 0 and math.random() < 0.4 then
			local id = self.beaconOrder[math.random(1, #self.beaconOrder)]
			local beacon = self.beacons[id]
			if beacon and not beacon.lit then
				app.gloam:spawn(
					"Siphon",
					beacon.position + Vector3.new(math.random(-8, 8), 2, math.random(-8, 8))
				)
			end
		end
		app.gloam:spawnWave(math.min(2, target - current), Vector3.new(0, 2, 60), kinds)
	end
end

--------------------------------------------------------------------------------
-- frame loop
--------------------------------------------------------------------------------

function DiveService.step(self: DiveService, dt: number)
	local app = self.app
	if not app then
		return
	end
	if self.phase ~= "dive" then
		return
	end

	dt = math.min(dt, 0.25)
	self.timeLeft -= dt
	if self.timeLeft <= 0 then
		self:endRun("tide")
		return
	end

	self.accumulator += dt
	local steps = 0
	while self.accumulator >= TICK and steps < 3 do
		self.accumulator -= TICK
		steps += 1
		self:fixedStep(TICK)
	end

	self.broadcastAt += dt
	if self.broadcastAt >= 0.25 then
		self.broadcastAt = 0
		self:broadcastRun()
	end

	self.maintainAt += dt
	if self.maintainAt >= 3 then
		self.maintainAt = 0
		self:maintainSwarm()
	end
end

function DiveService.fixedStep(self: DiveService, dt: number)
	local app = self.app
	if not app then
		return
	end
	local now = os.clock()

	-- Lantern regeneration / sprint burn
	for _, diver in self.divers do
		if not diver.out then
			local sinking = diver.sprinting and now - diver.lastSpendAt > 0.2
			if sinking then
				diver.light = math.max(0, diver.light - Config.Light.SprintDrainPerSecond * dt)
			elseif now - diver.lastSpendAt > Config.Light.RegenDelay then
				local multiplier = 1
				for _, beacon in self.beacons do
					if beacon.lit then
						multiplier = Config.Light.BeaconRegenMultiplier
						break
					end
				end
				diver.light =
					LightMath.regen(diver.light, diver.capacity, diver.regen, multiplier, dt)
			end
		end
	end

	-- Player positions for AI and contacts
	local targets: { { userId: number, position: Vector3 } } = {}
	for player, diver in self.divers do
		local root = characterRoot(player)
		if root and not diver.out then
			table.insert(targets, { userId = player.UserId, position = root.Position })
			if root.Position.Y < -40 then
				self:teleport(
					player,
					app.world.reefSpawn,
					app.world.reefSpawn + Vector3.new(0, 0, -10)
				)
			end
		end
	end

	-- Gloam
	local aiTargets: { GloamBrain.Target } = {}
	for player, diver in self.divers do
		local root = characterRoot(player)
		if root and not diver.out then
			table.insert(aiTargets, { position = root.Position, light = diver.light })
		end
	end
	local beaconPositions: { Vector3 } = {}
	for _, id in self.beaconOrder do
		local beacon = self.beacons[id]
		if not beacon.lit then
			table.insert(beaconPositions, beacon.position)
		end
	end
	local aiContext: GloamBrain.Context = {
		targets = aiTargets,
		beacons = beaconPositions,
		pulsePoint = nil,
		now = now,
		groundY = 0,
	}
	app.gloam:tick(dt, function()
		return aiContext
	end)

	-- Light is health: hitting zero must end the dive, whatever the source.
	for player, diver in self.divers do
		if not diver.out and diver.light <= 0 then
			self:settle(player, "doused")
		end
	end

	local contacts = app.gloam:contacts(targets, now)
	for _, contact in contacts do
		local player = Players:GetPlayerByUserId(contact.userId)
		if player then
			self:damageLight(player, contact.amount, contact.position)
		end
	end

	-- Record which Gloam the player has actually shared the water with.
	for kind in app.gloam.kindsSeen do
		self.kindsThisRun[kind] = true
	end

	-- Ember motes
	for _, shard in app.world.shards do
		if not shard.collected then
			for player, diver in self.divers do
				local root = characterRoot(player)
				if root and not diver.out and (root.Position - shard.position).Magnitude <= 5 then
					shard.collected = true
					shard.part.Transparency = 1
					diver.carried += shard.value
					app.net:signalAll(Net.Signal.Shard, {
						id = shard.id,
						x = shard.position.X,
						y = shard.position.Y,
						z = shard.position.Z,
						value = shard.value,
						userId = player.UserId,
					})
					app.net:signal(
						player,
						Net.Signal.Toast,
						{ text = `+{shard.value} embers`, tone = "good" }
					)
					break
				end
			end
		end
	end

	-- Beacons
	for _, id in self.beaconOrder do
		local beacon = self.beacons[id]
		if not beacon.lit then
			local contributors = 0
			for player, diver in self.divers do
				local root = characterRoot(player)
				if
					root
					and not diver.out
					and (root.Position - beacon.position).Magnitude <= Config.Dive.BeaconRadius
				then
					contributors += 1
				end
			end
			if contributors > 0 then
				local rate = 1 / Config.Dive.BeaconHoldTime
				beacon.progress += rate * (1 + 0.2 * (contributors - 1)) * dt
			end
			local draining = app.gloam:countDraining(beacon.position, Config.Dive.BeaconRadius + 4)
			if draining > 0 then
				beacon.progress -= 0.12 * draining * dt
			end
			beacon.progress = math.clamp(beacon.progress, 0, 1)
			if beacon.progress >= 1 then
				self:lightBeacon(beacon)
			end
		end
	end
end

function DiveService.broadcastRun(self: DiveService)
	local app = self.app
	if not app then
		return
	end
	local beacons = {}
	for _, id in self.beaconOrder do
		local beacon = self.beacons[id]
		table.insert(beacons, { id = beacon.id, progress = beacon.progress, lit = beacon.lit })
	end
	for player, diver in self.divers do
		app.net:signal(
			player,
			Net.Signal.Run,
			{
				timeLeft = self.timeLeft,
				beacons = beacons,
				complete = self.complete,
				carried = diver.carried,
				beaconsLit = self.beaconsLit,
			} :: Net.RunPayload
		)
		app.net:signal(
			player,
			Net.Signal.Light,
			{ value = diver.light, capacity = diver.capacity } :: Net.LightPayload
		)
	end
end

--------------------------------------------------------------------------------
-- payouts
--------------------------------------------------------------------------------

--[[
	Ends a player's dive, computes the payout and returns them to the hub.

	IMPORTANT: this runs inside the Heartbeat step for timeout/douse paths, so it
	must never yield. Persistence and the leaderboard write are deferred to a
	spawned thread (both hit DataStores, which yield). `deferSave = false` is used
	by the leave path, where PlayerDataService.release performs the final save.
]]
function DiveService.settle(self: DiveService, player: Player, reason: string, deferSave: boolean?)
	local app = self.app
	if not app then
		return
	end
	local diver = self.divers[player]
	if not diver then
		return
	end
	diver.out = true
	self.divers[player] = nil
	diver.sprinting = false
	setWalkSpeed(player, Config.Light.WalkSpeed)

	local died = reason == "doused"
	local escaped = reason == "escape"
	local elapsed = math.max(1, math.floor(os.clock() - diver.joinedAt))

	local payout = LightMath.payout({
		carriedEmbers = diver.carried,
		beaconsLit = self.beaconsLit,
		beaconCount = #self.beaconOrder,
		completed = self.complete,
		died = died,
		escaped = escaped,
	})

	local record = app.data:get(player)
	if record then
		local save = record.save
		save.embers += payout.total
		save.lifetimeEmbers += payout.total
		save.beaconsLit += self.beaconsLit
		save.dives += 1
		if self.complete then
			save.divesCompleted += 1
		end
		if save.bestDiveSeconds == 0 or elapsed < save.bestDiveSeconds then
			save.bestDiveSeconds = elapsed
		end
		for kind in self.kindsThisRun do
			save.codex[kind] = true
		end
		local lifetime = save.lifetimeEmbers
		record.dirty = true
		local shouldSave = deferSave ~= false
		if shouldSave then
			task.spawn(function()
				app.data:save(player)
				app.board:submit(player, lifetime)
				if player.Parent then
					self:pushSave(player)
				end
			end)
		end
	end

	app.net:signal(player, Net.Signal.Bank, {
		total = payout.total,
		banked = payout.banked,
		beaconBonus = payout.beaconBonus,
		completionBonus = payout.completionBonus,
		multiplier = payout.multiplier,
		reason = reason,
		beaconsLit = self.beaconsLit,
	})

	local message = if died
		then "Your lantern guttered out. The tide carried you home."
		elseif escaped then "You surfaced with the embers."
		elseif reason == "leave" then "You left the dive."
		else "The tide turned. You were pulled out."
	app.net:signal(
		player,
		Net.Signal.Toast,
		{ text = message, tone = if died then "bad" else "info" }
	)

	self:teleport(player, app.world.hubSpawn, app.world.exitGate)
	app.net:signal(player, Net.Signal.Phase, {
		phase = if self:countDivers() > 0 then "dive" else "hub",
		inDive = false,
	})

	if self:countDivers() == 0 then
		self:endRun("empty")
	end
end

function DiveService.endRun(self: DiveService, reason: string)
	local app = self.app
	if not app then
		return
	end
	self.phase = "closing"

	local remaining: { Player } = {}
	for player in self.divers do
		table.insert(remaining, player)
	end
	for _, player in remaining do
		self:settle(player, if reason == "tide" then "tide" else "leave")
	end

	app.gloam:clear()
	app.world.exitPrompt.Enabled = false
	app.world.gateGlow.Color = Color3.fromRGB(31, 182, 196)
	for _, shard in app.world.shards do
		shard.collected = false
		shard.part.Transparency = 0
	end
	for _, id in self.beaconOrder do
		local beacon = self.beacons[id]
		beacon.lit = false
		beacon.progress = 0
		self:paintBeacon(beacon)
	end
	self.beaconsLit = 0
	self.complete = false
	self.timeLeft = 0
	self.phase = "hub"

	app.net:signalAll(Net.Signal.Phase, { phase = "hub", message = "The reef sleeps." })
end

--------------------------------------------------------------------------------
-- progression intents
--------------------------------------------------------------------------------

function DiveService.purchaseUpgrade(self: DiveService, player: Player, id: unknown)
	local app = self.app
	if not app then
		return
	end
	local record = app.data:get(player)
	if not record then
		return
	end
	local result = Progression.purchase(record.save, id)
	if not result.ok then
		app.net:signal(
			player,
			Net.Signal.Toast,
			{ text = result.reason or "Cannot buy that", tone = "warn" }
		)
		return
	end
	app.data:mutate(player, function()
		return result.save
	end)
	local record2 = app.data:get(player)
	if record2 then
		record2.dirty = true
	end
	task.spawn(function()
		app.data:save(player)
	end)
	local diver = self.divers[player]
	if diver then
		applyStats(app, player, diver)
	end
	self:pushSave(player)
	app.net:signal(player, Net.Signal.Toast, { text = "Upgraded.", tone = "good" })
end

function DiveService.purchaseHue(self: DiveService, player: Player, id: unknown)
	local app = self.app
	if not app then
		return
	end
	local record = app.data:get(player)
	if not record then
		return
	end
	local ok, nextSave = Progression.purchaseHue(record.save, id)
	if not ok then
		return
	end
	app.data:mutate(player, function()
		return nextSave
	end)
	local record2 = app.data:get(player)
	if record2 then
		record2.dirty = true
	end
	task.spawn(function()
		app.data:save(player)
	end)
	self:pushSave(player)
	app.net:signal(player, Net.Signal.Toast, { text = "Lantern recoloured.", tone = "good" })
end

function DiveService.recordCodex(self: DiveService, player: Player, id: unknown)
	local app = self.app
	if not app then
		return
	end
	if not Codex.get(id) then
		return
	end
	local record = app.data:get(player)
	if not record or record.save.codex[id :: string] then
		return
	end
	app.data:mutate(player, function(save)
		local nextSave = table.clone(save)
		nextSave.codex = table.clone(save.codex)
		nextSave.codex[id :: string] = true
		return nextSave
	end)
	self:pushSave(player)
end

--[[ Called when a player leaves the server mid-dive. ]]
function DiveService.handlePlayerRemoving(self: DiveService, player: Player)
	if self.divers[player] then
		-- No deferral: PlayerDataService.release runs immediately after this and
		-- performs the final write, so the payout must already be in the record.
		self:settle(player, "doused", false)
	end
end

return DiveService
