local T = require("../support/TinyTest")
local LightMath = require("../shared/LightMath")
local Config = require("../shared/Config")
local Vector3 = require("../support/Stubs").Vector3

T.suite("LightMath")

T.case("falloff is monotonic and bounded", function()
	T.equal(LightMath.falloff(0, 10), 1, "full strength at the source")
	T.equal(LightMath.falloff(10, 10), 0, "zero at the rim")
	T.ok(LightMath.falloff(4, 10) > LightMath.falloff(6, 10), "further is dimmer")
	T.equal(LightMath.falloff(4, 0), 0, "zero radius is safe")
end)

T.case("cone test", function()
	local forward = Vector3.new(0, 0, 1)
	T.ok(LightMath.inCone(Vector3.new(0, 0, 10), forward, 20, 40), "straight ahead is inside")
	T.ok(not LightMath.inCone(Vector3.new(0, 0, 25), forward, 20, 40), "beyond range is outside")
	T.ok(
		not LightMath.inCone(Vector3.new(0, 0, -10), forward, 20, 40),
		"behind the player is outside"
	)
	T.ok(
		not LightMath.inCone(Vector3.new(10, 0, 1), forward, 20, 30),
		"wide to the side is outside"
	)
	T.ok(LightMath.inCone(Vector3.new(1, 0, 10), forward, 20, 30), "slight offset is inside")
end)

T.case("flare hits respect the cone and scale with distance", function()
	local origin = Vector3.new(0, 0, 0)
	local forward = Vector3.new(0, 0, 1)
	local targets = {
		Vector3.new(0, 0, 5),
		Vector3.new(0, 0, 30),
		Vector3.new(-40, 0, 0),
	}
	local hits = LightMath.flareTargets(origin, forward, targets, 32, 34, 40)
	T.equal(#hits, 2, "only targets inside the cone are hit")
	T.ok(hits[1].damage > hits[2].damage, "closer target takes more damage")
	T.equal(hits[1].index, 1, "index maps back to the input target")
end)

T.case("spend respects the reserve floor", function()
	local ok, after = LightMath.spend(50, 18, 10)
	T.ok(ok, "spend allowed with headroom")
	T.equal(after, 32, "light deducted")
	local denied, unchanged = LightMath.spend(12, 18, 10)
	T.equal(denied, false, "spend blocked under the floor")
	T.equal(unchanged, 12, "light untouched when blocked")
end)

T.case("regen never exceeds capacity", function()
	T.equal(LightMath.regen(99, 100, 5, 1, 1), 100, "clamped at capacity")
	T.near(LightMath.regen(50, 100, 2, 1, 1), 52, 0.001, "adds rate * dt")
end)

T.case("payout maths", function()
	local perfect = LightMath.payout({
		carriedEmbers = 100,
		beaconsLit = 3,
		beaconCount = 3,
		completed = true,
		died = false,
		escaped = true,
	})
	local expected =
		math.floor((100 + 3 * Config.Dive.BeaconPayout + Config.Dive.CompletionBonus) * 1.25)
	T.equal(perfect.total, expected, "escape bonus and beacon payout applied")

	local died = LightMath.payout({
		carriedEmbers = 100,
		beaconsLit = 1,
		beaconCount = 3,
		completed = false,
		died = true,
		escaped = false,
	})
	T.ok(died.total < perfect.total, "dying pays less")
	T.equal(
		died.total,
		math.floor((100 + Config.Dive.BeaconPayout) * Config.Dive.DeathPayoutMultiplier),
		"death multiplier applied to carried + beacon"
	)

	local negative = LightMath.payout({
		carriedEmbers = -500,
		beaconsLit = 99,
		beaconCount = 3,
		completed = false,
		died = false,
		escaped = false,
	})
	T.ok(negative.total >= 0, "negative carried embers can never reduce payout below zero")
end)

T.case("clock formatting", function()
	T.equal(LightMath.formatClock(0), "0:00", "zero")
	T.equal(LightMath.formatClock(65), "1:05", "minutes padded")
	T.equal(LightMath.formatClock(-5), "0:00", "negative clamps")
end)

return true
