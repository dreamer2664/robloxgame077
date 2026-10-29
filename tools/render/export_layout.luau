--[[
	Exports the pure Layout description to JSON so tools/render can draw the exact
	geometry the game builds. Run through tools/render/build.sh.

	Deliberately dependency-free: a tiny serialiser keeps this runnable with the
	plain Luau CLI (no Roblox, no packages).
]]

local Layout = require("../../tests/.build/shared/Layout")

local function esc(text: string): string
	return (string.gsub(text, '"', '\\"'))
end

local function num(value: number): string
	if value ~= value or value == math.huge or value == -math.huge then
		return "0"
	end
	return string.format("%.4f", value)
end

local function encode(value: any): string
	local kind = type(value)
	if kind == "nil" then
		return "null"
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "number" then
		return num(value)
	elseif kind == "string" then
		return '"' .. esc(value) .. '"'
	elseif kind == "table" then
		local isArray = true
		local count = 0
		for key in value do
			count += 1
			if type(key) ~= "number" then
				isArray = false
			end
		end
		local pieces = {}
		if isArray and count == #value then
			for _, item in value do
				table.insert(pieces, encode(item))
			end
			return "[" .. table.concat(pieces, ",") .. "]"
		end
		for key, item in value do
			table.insert(pieces, '"' .. esc(tostring(key)) .. '":' .. encode(item))
		end
		return "{" .. table.concat(pieces, ",") .. "}"
	end
	return "null"
end

local world = Layout.build()
print(encode(world))
