local T = require("../support/TinyTest")
local Validate = require("../shared/Validate")

T.suite("Validate")

T.case("numeric guards", function()
	T.ok(Validate.isNumber(3), "accepts finite number")
	T.ok(not Validate.isNumber(0 / 0), "rejects NaN")
	T.ok(not Validate.isNumber(math.huge), "rejects +inf")
	T.ok(not Validate.isNumber(-math.huge), "rejects -inf")
	T.ok(not Validate.isNumber("3"), "rejects numeric string")
	T.ok(not Validate.isNumber(nil), "rejects nil")
end)

T.case("integer guards", function()
	T.ok(Validate.isInteger(5), "accepts integer")
	T.ok(not Validate.isInteger(5.5), "rejects fractional")
	T.ok(not Validate.isInteger(-1, 0), "rejects below min")
	T.ok(not Validate.isInteger(11, 0, 10), "rejects above max")
	T.ok(Validate.isUint(0), "accepts zero as uint")
	T.ok(not Validate.isUint(-0.5), "rejects negative fraction")
end)

T.case("range + string guards", function()
	T.ok(Validate.isFiniteInRange(0.5, 0, 1), "inside range")
	T.ok(not Validate.isFiniteInRange(1.5, 0, 1), "outside range")
	T.ok(not Validate.isFiniteInRange(1e13, 0, 1e15), "rejects absurd magnitude")
	T.ok(Validate.isShortString("abc"), "accepts short string")
	T.ok(not Validate.isShortString(string.rep("a", 200)), "rejects long string")
	T.ok(not Validate.isShortString(12), "rejects non-string")
end)

T.case("direction triple", function()
	T.ok(Validate.isDirectionTriple({ x = 0, y = 0.5, z = -1 }), "accepts unit-ish direction")
	T.ok(not Validate.isDirectionTriple({ x = 0, y = 4, z = 0 }), "rejects out of range component")
	T.ok(not Validate.isDirectionTriple({ x = 0, y = 0 }), "rejects missing component")
	T.ok(not Validate.isDirectionTriple("down"), "rejects non-table")
end)

T.case("payload shape", function()
	local ok = Validate.shape({ aim = { x = 0, y = 0, z = 1 } }, { "aim" }, { "aim" })
	T.ok(ok, "accepts expected shape")

	local extra = Validate.shape(
		{ aim = { x = 0, y = 0, z = 1 }, speed = 900 },
		{ "aim" },
		{ "aim" }
	)
	T.equal(extra, false, "rejects unexpected field (client smuggling a speed buff)")

	local missing = Validate.shape({}, { "aim" }, { "aim" })
	T.equal(missing, false, "rejects missing required field")

	local notTable = Validate.shape("pulse", { "aim" }, { "aim" })
	T.equal(notTable, false, "rejects non-table payload")

	local nilAllowed = Validate.shape(nil, { "aim" })
	T.ok(nilAllowed, "nil payload allowed when nothing is required")

	local numericKey = Validate.shape({ [1] = "x" }, { "aim" })
	T.equal(numericKey, false, "rejects numeric keys")
end)

return true
