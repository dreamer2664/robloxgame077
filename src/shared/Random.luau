--!strict
--[[
	Deterministic pseudo-random generator (32-bit LCG).

	Used for world decoration so the reef is identical on the server, on every
	client and in the offline renderer, and so layout tests are reproducible.
	Instances carry their own methods, so `rng:range(0, 1)` works on the value
	returned by `Random.new`.
]]

export type Rng = {
	state: number,
	nextFloat: (Rng) -> number,
	range: (Rng, number, number) -> number,
	int: (Rng, number, number) -> number,
	sign: (Rng) -> number,
	weighted: <T>(Rng, { { value: T, weight: number } }) -> T,
}

local Random = {}

local MOD = 4294967296 -- 2^32
local MUL = 1664525
local INC = 1013904223

local function nextFloat(rng: Rng): number
	rng.state = (rng.state * MUL + INC) % MOD
	return rng.state / MOD
end

local function range(rng: Rng, min: number, max: number): number
	return min + nextFloat(rng) * (max - min)
end

local function int(rng: Rng, min: number, max: number): number
	return math.floor(range(rng, min, max + 1))
end

local function sign(rng: Rng): number
	return if nextFloat(rng) < 0.5 then -1 else 1
end

--[[ Picks one entry from a weighted list. ]]
local function weighted<T>(rng: Rng, entries: { { value: T, weight: number } }): T
	local total = 0
	for _, entry in entries do
		total += entry.weight
	end
	local roll = nextFloat(rng) * total
	for _, entry in entries do
		roll -= entry.weight
		if roll <= 0 then
			return entry.value
		end
	end
	return entries[#entries].value
end

function Random.new(seed: number): Rng
	local s = math.floor(math.abs(seed)) % MOD
	if s == 0 then
		s = 1
	end
	return {
		state = s,
		nextFloat = nextFloat,
		range = range,
		int = int,
		sign = sign,
		weighted = weighted,
	}
end

Random.nextFloat = nextFloat
Random.range = range
Random.int = int
Random.sign = sign
Random.weighted = weighted

return Random
