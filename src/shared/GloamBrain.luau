--!strict
--[[
	Gloam steering and state machine.

	Pure: agents are plain tables, all inputs come from a context table, so the
	whole brain can be unit tested without a Roblox instance. The server runs it
	at Config.Gloam.TickRate Hz and mirrors the result onto parts.
]]

local Config = require(script.Parent.Config)
local Codex = require(script.Parent.Codex)

export type Mode = "drift" | "hunt" | "lunge" | "drain" | "stagger" | "dead"

export type Agent = {
	id: number,
	kind: string,
	position: Vector3,
	velocity: Vector3,
	mode: Mode,
	health: number,
	maxHealth: number,
	speed: number,
	radius: number,
	staggerTimer: number,
	lungeCooldown: number,
	lungeTimer: number,
	attractTimer: number,
	attractPoint: Vector3?,
	lastHitAt: number,
}

export type Target = {
	position: Vector3,
	light: number,
}

export type Context = {
	targets: { Target },
	beacons: { Vector3 },
	pulsePoint: Vector3?,
	now: number,
	groundY: number,
}

local GloamBrain = {}

local HOVER = 2.4
local SEPARATION_WEIGHT = 1.9

function GloamBrain.new(id: number, kind: string, position: Vector3): Agent
	local archetype = Codex.get(kind) or Codex.ARCHETYPES[1]
	return {
		id = id,
		kind = archetype.id,
		position = position,
		velocity = Vector3.new(0, 0, 0),
		mode = "drift",
		health = archetype.maxHealth,
		maxHealth = archetype.maxHealth,
		speed = archetype.speed,
		radius = archetype.radius,
		staggerTimer = 0,
		lungeCooldown = 0,
		lungeTimer = 0,
		attractTimer = 0,
		attractPoint = nil,
		lastHitAt = -100,
	}
end

--[[ Applies damage; returns true when the agent died from this hit. ]]
function GloamBrain.hit(agent: Agent, amount: number, stagger: number): boolean
	if agent.mode == "dead" then
		return false
	end
	agent.health -= math.max(0, amount)
	agent.staggerTimer = math.max(agent.staggerTimer, stagger)
	if agent.health <= 0 then
		agent.health = 0
		agent.mode = "dead"
		agent.velocity = Vector3.new(0, 0, 0)
		return true
	end
	agent.mode = "stagger"
	return false
end

local function nearestTarget(position: Vector3, targets: { Target }): (Target?, number)
	local best: Target? = nil
	local bestDistance = math.huge
	for _, target in targets do
		if target.light > 0.01 then
			local distance = (target.position - position).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				best = target
			end
		end
	end
	return best, bestDistance
end

local function nearestPoint(position: Vector3, points: { Vector3 }): (Vector3?, number)
	local best: Vector3? = nil
	local bestDistance = math.huge
	for _, point in points do
		local distance = (point - position).Magnitude
		if distance < bestDistance then
			bestDistance = distance
			best = point
		end
	end
	return best, bestDistance
end

--[[ One fixed-step update. Mutates and returns the agent. ]]
function GloamBrain.step(agent: Agent, ctx: Context, dt: number, neighbors: { Vector3 }): Agent
	if agent.mode == "dead" then
		return agent
	end

	agent.lungeCooldown = math.max(0, agent.lungeCooldown - dt)
	agent.attractTimer = math.max(0, agent.attractTimer - dt)

	if agent.staggerTimer > 0 then
		agent.staggerTimer -= dt
		agent.mode = "stagger"
		agent.velocity = agent.velocity * math.max(0, 1 - 6 * dt)
		agent.position += agent.velocity * dt
		agent.position = Vector3.new(agent.position.X, ctx.groundY + HOVER, agent.position.Z)
		if agent.staggerTimer <= 0 then
			agent.mode = "hunt"
		end
		return agent
	end

	-- Pulse attraction: sound is bait. It overrides the beacon instinct but not a lunge.
	local pulsePoint = ctx.pulsePoint
	if pulsePoint and agent.mode ~= "lunge" then
		local distanceToPulse = (pulsePoint - agent.position).Magnitude
		if distanceToPulse <= Config.Gloam.PulseAttractRadius then
			agent.attractPoint = pulsePoint
			agent.attractTimer = Config.Gloam.PulseAttractTime
		end
	end

	local goal: Vector3? = nil

	if agent.mode == "lunge" then
		agent.lungeTimer -= dt
		if agent.lungeTimer <= 0 then
			agent.mode = "hunt"
			agent.lungeCooldown = 2.4
			agent.velocity = agent.velocity * 0.25
		end
		agent.position += agent.velocity * dt
		agent.position = Vector3.new(agent.position.X, ctx.groundY + HOVER, agent.position.Z)
		return agent
	end

	local target, targetDistance = nearestTarget(agent.position, ctx.targets)

	if agent.kind == "Siphon" then
		local beacon, beaconDistance = nearestPoint(agent.position, ctx.beacons)
		if beacon then
			if beaconDistance <= 7 then
				agent.mode = "drain"
				goal = beacon
			else
				agent.mode = "hunt"
				goal = beacon
			end
		elseif target then
			agent.mode = "hunt"
			goal = target.position
		end
	elseif agent.attractTimer > 0 and agent.attractPoint ~= nil then
		local attractPoint = agent.attractPoint :: Vector3
		agent.mode = "hunt"
		goal = attractPoint
	elseif target then
		agent.mode = "hunt"
		goal = target.position
		-- Lungers coil, then dash.
		if agent.kind == "Lunger" and targetDistance <= 26 and agent.lungeCooldown <= 0 then
			local direction = (target.position - agent.position)
			if direction.Magnitude > 0.01 then
				agent.mode = "lunge"
				agent.lungeTimer = 0.5
				agent.lungeCooldown = 2.6
				agent.velocity = direction.Unit * (agent.speed * 5.2)
				return agent
			end
		end
	end

	if not goal then
		-- Nothing to chase: drift slowly around the arena centre.
		agent.mode = "drift"
		local toCentre = Vector3.new(0, 0, 0) - Vector3.new(agent.position.X, 0, agent.position.Z)
		local wander = if toCentre.Magnitude > 1 then toCentre.Unit else Vector3.new(0, 0, 0)
		goal = agent.position + wander * 10
	end

	local goalPos: Vector3 = goal or agent.position
	local desired = Vector3.new(goalPos.X - agent.position.X, 0, goalPos.Z - agent.position.Z)
	local distance = desired.Magnitude
	if distance > 0.05 then
		desired = desired.Unit
	else
		desired = Vector3.new(0, 0, 0)
	end

	-- Separation keeps the swarm readable instead of a single stacked blob.
	local push = Vector3.new(0, 0, 0)
	for _, other in neighbors do
		local offset = Vector3.new(agent.position.X - other.X, 0, agent.position.Z - other.Z)
		local length = offset.Magnitude
		local personal = agent.radius * 2.6
		if length > 0.01 and length < personal then
			push += (offset / length) * ((personal - length) / personal)
		end
	end

	local steer = desired + push * SEPARATION_WEIGHT
	if steer.Magnitude > 0.01 then
		steer = steer.Unit
	end

	local speed = agent.speed
	if agent.mode == "drain" then
		speed = 0
	end

	local wantedVelocity = steer * speed
	-- Accelerate toward the wanted velocity so movement reads as organic.
	local blend = math.clamp(dt * 4, 0, 1)
	agent.velocity = agent.velocity + (wantedVelocity - agent.velocity) * blend
	agent.position += agent.velocity * dt
	agent.position = Vector3.new(agent.position.X, ctx.groundY + HOVER, agent.position.Z)
	return agent
end

return GloamBrain
