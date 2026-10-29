local T = require("../support/TinyTest")
local GloamBrain = require("../shared/GloamBrain")
local Vector3 = require("../support/Stubs").Vector3

T.suite("GloamBrain")

local function context(overrides)
	local ctx = {
		targets = { { position = Vector3.new(0, 0, 40), light = 100 } },
		beacons = {},
		pulsePoint = nil,
		now = 0,
		groundY = 0,
	}
	for key, value in overrides or {} do
		ctx[key] = value
	end
	return ctx
end

local function stepFor(agent, ctx, seconds)
	local dt = 1 / 8
	local steps = math.floor(seconds / dt)
	for _ = 1, steps do
		GloamBrain.step(agent, ctx, dt, {})
	end
	return agent
end

T.case("drifter homes toward a lit target", function()
	local agent = GloamBrain.new(1, "Drifter", Vector3.new(0, 2, 0))
	local ctx = context({})
	local before = (agent.position - ctx.targets[1].position).Magnitude
	stepFor(agent, ctx, 2)
	local after = (agent.position - ctx.targets[1].position).Magnitude
	T.ok(after < before - 5, "closed distance on the light")
	T.equal(agent.mode, "hunt", "is hunting")
end)

T.case("drifters ignore unlit players", function()
	local agent = GloamBrain.new(2, "Drifter", Vector3.new(0, 2, 0))
	local ctx = context({ targets = { { position = Vector3.new(0, 0, 40), light = 0 } } })
	stepFor(agent, ctx, 2)
	T.equal(agent.mode, "drift", "no aggro without light")
end)

T.case("lunger dashes only at close range", function()
	local far = GloamBrain.new(3, "Lunger", Vector3.new(0, 2, 0))
	local farCtx = context({ targets = { { position = Vector3.new(0, 0, 80), light = 100 } } })
	GloamBrain.step(far, farCtx, 1 / 8, {})
	T.ok(far.mode ~= "lunge", "does not lunge from far away")

	local near = GloamBrain.new(4, "Lunger", Vector3.new(0, 2, 0))
	local nearCtx = context({ targets = { { position = Vector3.new(0, 0, 20), light = 100 } } })
	GloamBrain.step(near, nearCtx, 1 / 8, {})
	T.equal(near.mode, "lunge", "lunges when the player is close")
	T.ok(near.velocity.Magnitude > near.speed, "burst velocity exceeds walk speed")
end)

T.case("stagger interrupts, then recovers", function()
	local agent = GloamBrain.new(5, "Drifter", Vector3.new(0, 2, 0))
	local ctx = context({})
	GloamBrain.hit(agent, 10, 1.6)
	T.equal(agent.mode, "stagger", "staggered by a flare")
	stepFor(agent, ctx, 0.5)
	T.equal(agent.mode, "stagger", "still staggered mid-effect")
	stepFor(agent, ctx, 1.6)
	T.ok(agent.mode ~= "stagger", "recovers after the stagger expires")
end)

T.case("death at zero health", function()
	local agent = GloamBrain.new(6, "Lunger", Vector3.new(0, 2, 0))
	local died = GloamBrain.hit(agent, 999, 1)
	T.equal(died, true, "reports the kill")
	T.equal(agent.mode, "dead", "marked dead")
	T.equal(GloamBrain.hit(agent, 10, 1), false, "cannot die twice")
	local frozen = agent.position
	stepFor(agent, context({}), 2)
	T.equal(agent.position, frozen, "dead agents do not move")
end)

T.case("siphon prioritises beacons over players", function()
	local beacon = Vector3.new(-30, 0, 0)
	local agent = GloamBrain.new(7, "Siphon", Vector3.new(0, 2, 0))
	local ctx = context({
		beacons = { beacon },
		targets = { { position = Vector3.new(0, 0, 10), light = 100 } },
	})
	stepFor(agent, ctx, 1.5)
	T.ok((agent.position - beacon).Magnitude < 32, "moved toward the beacon, not the player")
end)

T.case("pulse attraction overrides quiet targets", function()
	local pulse = Vector3.new(30, 0, 0)
	local agent = GloamBrain.new(8, "Drifter", Vector3.new(0, 2, 0))
	local ctx = context({ pulsePoint = pulse })
	local start = (agent.position - pulse).Magnitude
	stepFor(agent, ctx, 1.5)
	T.ok((agent.position - pulse).Magnitude < start, "drawn to the sounding")
end)

T.case("separation keeps agents apart", function()
	local agent = GloamBrain.new(9, "Drifter", Vector3.new(0, 2, 0))
	local ctx = context({ targets = {} })
	local neighbours = { Vector3.new(1, 0, 0), Vector3.new(0, 0, 1) }
	GloamBrain.step(agent, ctx, 1 / 8, neighbours)
	local moved = Vector3.new(agent.velocity.X, 0, agent.velocity.Z)
	T.ok(moved.X < 0 or moved.Z < 0, "pushes away from neighbours")
end)

T.case("agents stay above the floor", function()
	local agent = GloamBrain.new(10, "Drifter", Vector3.new(0, 2, 0))
	local ctx = context({ groundY = 12 })
	stepFor(agent, ctx, 1)
	T.ok(agent.position.Y > 12, "hovers above the ground plane")
end)

return true
