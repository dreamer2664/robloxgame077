--[[ A very small test framework: suites, cases, assertions, readable output. ]]

local TinyTest = {}

local results = {
	passed = 0,
	failed = 0,
	errors = 0,
	failures = {},
	suites = 0,
}

local currentSuite = "?"

function TinyTest.suite(name: string)
	currentSuite = name
	results.suites += 1
	print(`\n  {name}`)
end

local function record(ok: boolean, message: string)
	if ok then
		results.passed += 1
		print(`    [pass] {message}`)
	else
		results.failed += 1
		table.insert(results.failures, `{currentSuite} :: {message}`)
		print(`    [FAIL] {message}`)
	end
end

function TinyTest.case(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		results.errors += 1
		table.insert(results.failures, `{currentSuite} :: {name} threw: {tostring(err)}`)
		print(`    [ERROR] {name} -> {err}`)
	end
end

function TinyTest.ok(condition: boolean, message: string)
	record(condition == true, message)
end

function TinyTest.equal(actual: any, expected: any, message: string)
	local ok = actual == expected
	record(
		ok,
		if ok then message else `{message} (expected {tostring(expected)}, got {tostring(actual)})`
	)
end

function TinyTest.near(actual: number, expected: number, tolerance: number, message: string)
	local ok = math.abs(actual - expected) <= tolerance
	record(
		ok,
		if ok then message else `{message} (expected {expected} +/- {tolerance}, got {actual})`
	)
end

function TinyTest.throws(fn: () -> (), message: string)
	local ok = pcall(fn)
	record(not ok, message)
end

function TinyTest.report(): number
	print(`\n{string.rep("=", 60)}`)
	if results.failed == 0 and results.errors == 0 then
		print(`PASS  {results.passed} assertions across {results.suites} suites`)
	else
		print(`FAIL  {results.passed} passed, {results.failed} failed, {results.errors} errored`)
		for _, failure in results.failures do
			print(`   - {failure}`)
		end
	end
	print(string.rep("=", 60))
	return if results.failed == 0 and results.errors == 0 then 0 else 1
end

return TinyTest
