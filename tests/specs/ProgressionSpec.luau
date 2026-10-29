local T = require("../support/TinyTest")
local Progression = require("../shared/Progression")
local SaveSchema = require("../shared/SaveSchema")
local Config = require("../shared/Config")

T.suite("Progression")

T.case("cost curve is monotonic and rounded", function()
	local previous = 0
	for level = 0, 6 do
		local cost = Progression.cost("lantern", level)
		T.ok(cost > previous, `level {level} costs more than the previous level`)
		T.equal(cost % 5, 0, `cost at level {level} is a multiple of 5`)
		previous = cost
	end
	T.equal(Progression.cost("nope", 0), math.huge, "unknown upgrade has no price")
	T.equal(
		Progression.cost("lantern", Config.Progression.MaxLevel),
		math.huge,
		"max level is unpurchasable"
	)
end)

T.case("purchase success spends embers and raises level", function()
	local save = SaveSchema.default(0)
	save.embers = 500
	local result = Progression.purchase(save, "wick")
	T.ok(result.ok, "purchase succeeded")
	T.equal(result.save.embers, 500 - result.cost, "embers deducted exactly once")
	T.equal(Progression.level(result.save, "wick"), 1, "level incremented")
	T.equal(Progression.level(save, "wick"), 0, "original save untouched")
	T.equal(save.embers, 500, "original balance untouched")
end)

T.case("purchase rejects when broke, unknown, or mastered", function()
	local poor = SaveSchema.default(0)
	poor.embers = 5
	T.equal(Progression.purchase(poor, "lantern").ok, false, "broke player cannot buy")
	T.equal(Progression.purchase(poor, "lantern").reason, "not enough embers", "reason is specific")
	T.equal(Progression.purchase(poor, "hack").ok, false, "unknown upgrade rejected")

	local maxed = SaveSchema.default(0)
	maxed.embers = 1e9
	maxed.upgrades.lantern = Config.Progression.MaxLevel
	T.equal(Progression.purchase(maxed, "lantern").ok, false, "cannot exceed max level")
end)

T.case("derived stats grow and stay clamped", function()
	local save = SaveSchema.default(0)
	local baseStats = Progression.stats(save)
	T.equal(baseStats.capacity, Config.Light.BaseCapacity, "base capacity")

	save.upgrades.lantern = 99
	save.upgrades.wick = 99
	local maxed = Progression.stats(save)
	T.equal(maxed.capacity, Config.Light.MaxCapacity, "capacity clamped to the hard cap")
	T.ok(maxed.regenPerSecond > baseStats.regenPerSecond, "wick improves regen")
	T.ok(maxed.lanternRadius > baseStats.lanternRadius, "lantern improves radius")
end)

T.case("lantern hue purchase validates ids", function()
	local save = SaveSchema.default(0)
	local ok = Progression.purchaseHue(save, "violet")
	T.ok(ok, "valid hue accepted")
	local bad, unchanged = Progression.purchaseHue(save, "rainbow-infinite")
	T.equal(bad, false, "invalid hue rejected")
	T.equal(unchanged.lanternHue, "amber", "hue unchanged after rejection")
end)

T.case("rank progresses with total upgrade levels", function()
	local save = SaveSchema.default(0)
	T.equal(Progression.rank(save), "Unlit", "starts unlit")
	save.upgrades.lantern = 2
	save.upgrades.wick = 1
	T.equal(Progression.rank(save), "Lamplighter", "three points unlocks lamplighter")
end)

return true
