local T = require("../support/TinyTest")
local Random = require("../shared/Random")

T.suite("Random")

T.case("same seed reproduces the same stream", function()
	local a = Random.new(7)
	local b = Random.new(7)
	for i = 1, 20 do
		T.equal(a:nextFloat(), b:nextFloat(), `draw {i} matches for identical seeds`)
	end
end)

T.case("different seeds diverge", function()
	local a = Random.new(1)
	local b = Random.new(2)
	local same = true
	for _ = 1, 10 do
		if a:nextFloat() ~= b:nextFloat() then
			same = false
		end
	end
	T.equal(same, false, "different seeds produce different values")
end)

T.case("range and int respect their bounds", function()
	local rng = Random.new(99)
	local min, max = math.huge, -math.huge
	for _ = 1, 500 do
		local value = rng:range(-5, 5)
		min = math.min(min, value)
		max = math.max(max, value)
		T.ok(value >= -5 and value <= 5, "range stays within bounds")
	end
	T.ok(min < -4 and max > 4, "range covers its span")

	for _ = 1, 500 do
		local value = rng:int(1, 6)
		T.ok(value >= 1 and value <= 6 and value == math.floor(value), "int is an integer in range")
	end
end)

T.case("sign only returns -1 or 1", function()
	local rng = Random.new(3)
	for _ = 1, 50 do
		local s = rng:sign()
		T.ok(s == 1 or s == -1, "sign is +/-1")
	end
end)

T.case("zero seed still produces a usable stream", function()
	local rng = Random.new(0)
	local value = rng:nextFloat()
	T.ok(value >= 0 and value < 1, "zero seed is remapped, not degenerate")
end)

return true
