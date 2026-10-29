--!strict
--[[
	Persistent player schema: defaults, migration and sanitation.

	Sanitation is a security boundary: datastore contents are untrusted input
	(a compromised write, a hand-edited value or an old broken version must never
	be able to hand a player infinite embers or crash the session).
]]

local Validate = require(script.Parent.Validate)

export type Upgrades = { [string]: number }

export type SaveData = {
	version: number,
	embers: number,
	lifetimeEmbers: number,
	beaconsLit: number,
	dives: number,
	divesCompleted: number,
	bestDiveSeconds: number,
	upgrades: Upgrades,
	lanternHue: string,
	codex: { [string]: boolean },
	lastSeenAt: number,
	firstSeenAt: number,
}

local SaveSchema = {}

SaveSchema.UPGRADE_IDS = { "lantern", "wick", "resonance", "echo", "flare" } :: { string }
SaveSchema.HUE_IDS = { "amber", "mint", "violet", "crimson", "ice" } :: { string }
SaveSchema.CODEX_IDS = { "Drifter", "Lunger", "Siphon" } :: { string }

local MAX_EMBERS = 1e9
local MAX_UPGRADE_LEVEL = 99
local MAX_COUNT = 1e7
local MAX_SECONDS = 1e6

local function clampNumber(value: unknown, min: number, max: number, fallback: number): number
	if not Validate.isNumber(value) then
		return fallback
	end
	local n = value :: number
	if n ~= n then
		return fallback
	end
	return math.clamp(n, min, max)
end

local function clampInt(value: unknown, min: number, max: number, fallback: number): number
	return math.floor(clampNumber(value, min, max, fallback) + 0.5)
end

local function contains(list: { string }, value: unknown): boolean
	if type(value) ~= "string" then
		return false
	end
	for _, entry in list do
		if entry == value then
			return true
		end
	end
	return false
end

SaveSchema.contains = contains

local function readFlagList(value: unknown): { [string]: boolean }
	local result: { [string]: boolean } = {}
	if type(value) ~= "table" then
		return result
	end
	for _, id in SaveSchema.CODEX_IDS do
		if (value :: any)[id] == true then
			result[id] = true
		end
	end
	return result
end

local function readUpgrades(value: unknown): Upgrades
	local result: Upgrades = {}
	if type(value) ~= "table" then
		return result
	end
	local source = value :: { [string]: unknown }
	for _, id in SaveSchema.UPGRADE_IDS do
		local level = source[id]
		if level ~= nil then
			result[id] = clampInt(level, 0, MAX_UPGRADE_LEVEL, 0)
		end
	end
	return result
end

function SaveSchema.default(now: number?): SaveData
	local t = now or 0
	return {
		version = 3,
		embers = 0,
		lifetimeEmbers = 0,
		beaconsLit = 0,
		dives = 0,
		divesCompleted = 0,
		bestDiveSeconds = 0,
		upgrades = { lantern = 0, wick = 0, resonance = 0, echo = 0, flare = 0 },
		lanternHue = "amber",
		codex = {},
		lastSeenAt = t,
		firstSeenAt = t,
	}
end

--[[
	Migrates old payload shapes forward. Returns a plain table; sanitation still
	runs afterwards, so a failed migration can never produce invalid data.
]]
function SaveSchema.migrate(raw: { [string]: unknown }): { [string]: unknown }
	local data = raw

	-- v1: embers stored under `gold`, no upgrade table.
	if data.version == nil or (data.version :: number) < 2 then
		data.embers = data.embers or data.gold
		data.gold = nil
		data.upgrades = data.upgrades or { lantern = data.lanternLevel }
		data.lanternLevel = nil
		data.version = 2
	end

	-- v2 -> v3: split lifetime tracking out of a single `stats` blob.
	if (data.version :: number) < 3 then
		local stats = data.stats
		if type(stats) == "table" then
			local s = stats :: { [string]: unknown }
			data.lifetimeEmbers = data.lifetimeEmbers or s.earned
			data.beaconsLit = data.beaconsLit or s.beacons
			data.dives = data.dives or s.dives
		end
		data.stats = nil
		data.lanternHue = data.lanternHue or "amber"
		data.version = 3
	end

	return data
end

--[[ Forces any input into a valid SaveData. Never errors, never returns nil. ]]
function SaveSchema.sanitize(raw: unknown, now: number?): SaveData
	local t = now or 0
	if type(raw) ~= "table" then
		return SaveSchema.default(t)
	end
	local migrated = SaveSchema.migrate(raw :: { [string]: unknown })
	local base = SaveSchema.default(t)
	local hue = migrated.lanternHue
	local lastSeen = clampNumber(migrated.lastSeenAt, 0, 4102444800, t)
	local firstSeen = clampNumber(migrated.firstSeenAt, 0, 4102444800, lastSeen)

	return {
		version = 3,
		embers = clampInt(migrated.embers, 0, MAX_EMBERS, base.embers),
		lifetimeEmbers = clampInt(migrated.lifetimeEmbers, 0, MAX_EMBERS, 0),
		beaconsLit = clampInt(migrated.beaconsLit, 0, MAX_COUNT, 0),
		dives = clampInt(migrated.dives, 0, MAX_COUNT, 0),
		divesCompleted = clampInt(migrated.divesCompleted, 0, MAX_COUNT, 0),
		bestDiveSeconds = clampNumber(migrated.bestDiveSeconds, 0, MAX_SECONDS, 0),
		upgrades = readUpgrades(migrated.upgrades),
		lanternHue = if contains(SaveSchema.HUE_IDS, hue) then hue :: string else "amber",
		codex = readFlagList(migrated.codex),
		lastSeenAt = lastSeen,
		firstSeenAt = math.min(firstSeen, lastSeen),
	}
end

return SaveSchema
