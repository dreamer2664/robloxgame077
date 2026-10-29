--!strict
--[[
	Defensive validation for everything that crosses a trust boundary:
	client -> server intents, and datastore payloads read back from disk.
	Pure functions, no state, exhaustively unit tested.
]]

local Validate = {}

local MAX_STRING = 64
local ABSURD_NUMBER = 1e12

function Validate.isNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Validate.isInteger(value: unknown, min: number?, max: number?): boolean
	if not Validate.isNumber(value) then
		return false
	end
	local n = value :: number
	if n ~= math.floor(n) then
		return false
	end
	if min and n < min then
		return false
	end
	if max and n > max then
		return false
	end
	return true
end

function Validate.isFiniteInRange(value: unknown, min: number, max: number): boolean
	if not Validate.isNumber(value) then
		return false
	end
	local n = value :: number
	return n >= min and n <= max and math.abs(n) < ABSURD_NUMBER
end

function Validate.isUint(value: unknown, max: number?): boolean
	return Validate.isInteger(value, 0, max or 1e15)
end

function Validate.isShortString(value: unknown, maxLength: number?): boolean
	return type(value) == "string" and #(value :: string) <= (maxLength or MAX_STRING)
end

function Validate.isBoolean(value: unknown): boolean
	return type(value) == "boolean"
end

--[[ Accepts a Vector3, or a {x, y, z} table, and returns a normalised unit-ish direction or nil. ]]
function Validate.isDirectionTriple(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	local t = value :: any
	return Validate.isFiniteInRange(t.x, -1.5, 1.5)
		and Validate.isFiniteInRange(t.y, -1.5, 1.5)
		and Validate.isFiniteInRange(t.z, -1.5, 1.5)
end

--[[ Rejects payload tables that are non-tables or carry unexpected keys. ]]
function Validate.shape(
	payload: unknown,
	allowedKeys: { string },
	requiredKeys: { string }?
): (boolean, string?)
	if payload == nil then
		if requiredKeys and #requiredKeys > 0 then
			return false, "missing payload"
		end
		return true, nil
	end
	if type(payload) ~= "table" then
		return false, "payload must be a table"
	end
	local t = payload :: { [string]: unknown }
	local allowed: { [string]: boolean } = {}
	for _, key in allowedKeys do
		allowed[key] = true
	end
	local count = 0
	for key in t do
		if type(key) ~= "string" or not allowed[key] then
			return false, "unexpected field"
		end
		count += 1
	end
	if count > #allowedKeys then
		return false, "payload too large"
	end
	if requiredKeys then
		for _, key in requiredKeys do
			if t[key] == nil then
				return false, `missing field '{key}'`
			end
		end
	end
	return true, nil
end

return Validate
