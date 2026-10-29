local T = require("../support/TinyTest")
local Layout = require("../shared/Layout")
local Config = require("../shared/Config")

T.suite("Layout")

local world = Layout.build()

T.case("deterministic for a given seed", function()
	local a = Layout.build(12345)
	local b = Layout.build(12345)
	T.equal(#a.reef.parts, #b.reef.parts, "same part count")
	T.equal(
		a.reef.parts[#a.reef.parts].pos.x,
		b.reef.parts[#b.reef.parts].pos.x,
		"same final part position"
	)
	local c = Layout.build(999)
	T.ok(#c.reef.parts == #a.reef.parts, "different seed still yields a complete world")
end)

T.case("part budget is mobile-friendly", function()
	local total = #world.reef.parts + #world.hub.parts
	T.ok(#world.reef.parts < 2200, `reef has {#world.reef.parts} parts (budget 2200)`)
	T.ok(total < 2600, `whole world has {total} parts (budget 2600)`)
end)

T.case("no NaN or absurd geometry", function()
	local bad = 0
	for _, part in world.reef.parts do
		for _, axis in { "x", "y", "z" } do
			local value = part.pos[axis]
			local size = part.size[axis]
			if value ~= value or size ~= size or math.abs(value) > 1e5 or size <= 0 then
				bad += 1
			end
		end
	end
	T.equal(bad, 0, "every part has finite position and positive size")
end)

T.case("three beacons, unique ids, inside bounds", function()
	T.equal(#world.reef.beacons, Config.Dive.BeaconCount, "beacon count matches config")
	local seen = {}
	for _, beacon in world.reef.beacons do
		T.equal(seen[beacon.id], nil, `beacon id '{beacon.id}' is unique`)
		seen[beacon.id] = true
		local bounds = world.reef.bounds
		T.ok(
			beacon.pos.x > bounds.min.x
				and beacon.pos.x < bounds.max.x
				and beacon.pos.z > bounds.min.z
				and beacon.pos.z < bounds.max.z,
			`beacon '{beacon.id}' sits inside the arena`
		)
	end
end)

T.case("emitters and shards are placed on solid ground", function()
	local floors = {}
	for _, part in world.reef.parts do
		if part.tag == "floor" then
			table.insert(floors, part)
		end
	end
	T.ok(#floors > 50, "floor exists")
	local function supported(pos)
		for _, floor in floors do
			local dx = math.abs(pos.x - floor.pos.x)
			local dz = math.abs(pos.z - floor.pos.z)
			if dx <= floor.size.x / 2 + 2 and dz <= floor.size.z / 2 + 2 then
				return true
			end
		end
		return false
	end
	local floating = 0
	for _, shard in world.reef.shards do
		if not supported(shard.pos) then
			floating += 1
		end
	end
	T.equal(floating, 0, `all {#world.reef.shards} ember motes sit over floor`)
	T.equal(supported(world.reef.spawns[1]), true, "player spawn is over floor")
	T.equal(supported(world.reef.exitGate), true, "exit gate is over floor")
end)

T.case("collectibles and lights are present", function()
	T.ok(#world.reef.shards >= 30, "at least 30 ember motes")
	T.ok(#world.reef.lights >= 3, "beacons emit light")
	T.ok(#world.reef.parts > 0 and #world.hub.parts > 0, "both areas built")
	T.ok(#world.hub.lights >= 3, "hub is lit")
end)

T.case("hub floats clear of the reef", function()
	-- The lantern island hovers directly above the sunken reef; they must never
	-- intersect, or players would spawn inside geometry.
	T.ok(
		world.hub.bounds.min.y > world.reef.bounds.max.y + 100,
		"hub sits far above the reef vault"
	)
end)

T.case("sector metadata covers every beacon sector", function()
	local sectors = {}
	for _, sector in world.reef.sectors do
		sectors[sector.id] = true
	end
	for _, beacon in world.reef.beacons do
		T.ok(sectors[beacon.sector] == true, `beacon '{beacon.id}' belongs to a defined sector`)
	end
end)

return true
