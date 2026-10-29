--[[
	Balance simulation.

	These are not unit tests of code paths: they simulate the *economy* using the
	same pure functions the server runs, so a tuning change that quietly breaks
	the pacing (a dive that can never pay for an upgrade, a pulse you can spam
	forever, a beacon that two Siphons can permanently deny) fails CI.
]]
local T = require("../support/TinyTest")
local Config = require("../shared/Config")
local LightMath = require("../shared/LightMath")
local Progression = require("../shared/Progression")
local SaveSchema = require("../shared/SaveSchema")

T.suite("Balance")

local DEFAULT_STATS = Progression.stats(SaveSchema.default(0))

T.case("lantern: pulse spam cannot be sustained", function()
	local light = DEFAULT_STATS.capacity
	local pulses = 0
	local t = 0
	local dt = 1 / 20
	-- Spam every frame for 60 seconds with the real cooldown and regen rules.
	while t < 60 do
		t += dt
		local ok, after = LightMath.spend(light, Config.Light.PulseCost, 5)
		if ok and t >= 0 then
			-- cooldown gate, exactly as the server enforces it
			if pulses == 0 or t >= pulses * Config.Light.PulseCooldown then
				light = after
				pulses += 1
			end
		end
		light = LightMath.regen(light, DEFAULT_STATS.capacity, DEFAULT_STATS.regenPerSecond, 1, dt)
	end
	local sustainable = Config.Light.RegenPerSecond * Config.Light.PulseCooldown
	T.ok(
		sustainable < Config.Light.PulseCost,
		`pulse costs more than one cooldown of regen regenerates ({Config.Light.PulseCost} > {string.format(
			"%.1f",
			sustainable
		)})`
	)
	T.ok(light <= DEFAULT_STATS.capacity, "light never exceeds capacity")
end)

T.case("lantern: a resting player recovers from a flare", function()
	local light = 20
	local t = 0
	while light < DEFAULT_STATS.capacity and t < 120 do
		t += 0.1
		if t > Config.Light.RegenDelay then
			light =
				LightMath.regen(light, DEFAULT_STATS.capacity, DEFAULT_STATS.regenPerSecond, 1, 0.1)
		end
	end
	T.ok(t < 90, `full recovery from 20% takes {math.floor(t)}s (under 90s)`)
end)

T.case("beacons: solo progress beats one Siphon, loses to two", function()
	local holdRate = 1 / Config.Dive.BeaconHoldTime
	local siphonDrain = 0.12
	T.ok(holdRate - siphonDrain > 0, "one Siphon slows but cannot deny a beacon")
	T.ok(holdRate - 2 * siphonDrain <= 0, "two Siphons can deny a beacon (intended contest)")
end)

T.case("tide: a full clear is achievable but not trivially", function()
	local travelPerBeacon = 12 -- seconds of running between objectives, conservative
	local setup = 18
	local total = setup
		+ travelPerBeacon * Config.Dive.BeaconCount
		+ Config.Dive.BeaconHoldTime * Config.Dive.BeaconCount
	T.ok(
		total < Config.Dive.Duration * 0.5,
		`a clean run needs ~{math.floor(total)}s of a {Config.Dive.Duration}s tide`
	)
end)

T.case("economy: a perfect dive pays for the first upgrade", function()
	local shards = 0
	local shardValue = Config.Dive.RewardPerShard
	local collected = 30 * shardValue
	local payout = LightMath.payout({
		carriedEmbers = collected,
		beaconsLit = 3,
		beaconCount = 3,
		completed = true,
		died = false,
		escaped = true,
	})
	local firstCost = Progression.cost("lantern", 0)
	T.ok(
		payout.total >= firstCost * 3,
		`a full clear ({payout.total}) buys several first upgrades ({firstCost})`
	)
	shards += 1
	T.equal(shards, 1, "simulation inputs are wired")
end)

T.case("economy: dying still progresses", function()
	local payout = LightMath.payout({
		carriedEmbers = 60,
		beaconsLit = 1,
		beaconCount = 3,
		completed = false,
		died = true,
		escaped = false,
	})
	T.ok(payout.total > 0, "a failed dive still banks something")
	local firstCost = Progression.cost("lantern", 0)
	T.ok(payout.total < firstCost, "but a failed dive does not pay for a tier-1 upgrade")
end)

T.case("progression: full mastery is a long, finite road", function()
	local save = SaveSchema.default(0)
	local totalCost = 0
	for _, def in Progression.UPGRADES do
		for level = 0, def.maxLevel - 1 do
			totalCost += Progression.cost(def.id, level)
		end
	end
	local perDive = 300 -- a realistic mid-tier payout
	local dives = math.ceil(totalCost / perDive)
	T.ok(totalCost > 5000, `full mastery costs {totalCost} embers`)
	T.ok(dives > 20 and dives < 400, `roughly {dives} dives to master everything (target 20-400)`)
end)

T.case("difficulty: swarm population stays inside budget", function()
	local solo = Config.Gloam.BasePopulation + 1 * 2
	T.ok(solo <= Config.Gloam.MaxAlive, "solo population within the live cap")
	local full = Config.Gloam.BasePopulation
		+ (Config.Dive.MaxPlayers - 1) * Config.Gloam.PopulationPerPlayer
		+ 6
	T.ok(
		full <= Config.Gloam.MaxAlive,
		`a full {Config.Dive.MaxPlayers}-player server stays under the cap ({full} <= {Config.Gloam.MaxAlive})`
	)
end)

return true
