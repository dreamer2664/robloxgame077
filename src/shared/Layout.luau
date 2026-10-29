--!strict
--[[
	ECHOWAKE — world layout generator.

	This module is the single source of truth for geometry. It is *pure* (no
	Roblox APIs, only plain tables) so that:
	  * the server builds the place from it (World/Builder.luau),
	  * tests can assert the arena is navigable and every objective is reachable,
	  * tools/render can draw the exact same world offline for art review.

	Everything is deterministic: the same seed always produces the same reef.
]]

local Palette = require(script.Parent.Palette)
local Random = require(script.Parent.Random)

export type Vec = { x: number, y: number, z: number }
export type Shape = "Block" | "Cylinder" | "Ball"

export type PartSpec = {
	shape: Shape,
	pos: Vec,
	size: Vec,
	rot: Vec?,
	color: string,
	mat: string,
	alpha: number?,
	cast: boolean?,
	tag: string,
	emissive: number?,
}

export type PartOpts = {
	mat: string?,
	rot: Vec?,
	alpha: number?,
	cast: boolean?,
	tag: string?,
	emissive: number?,
}

export type LightSpec = {
	pos: Vec,
	color: string,
	brightness: number,
	range: number,
}

export type BeaconSpec = {
	id: string,
	title: string,
	sector: string,
	pos: Vec,
	accent: string,
}

export type ShardSpec = {
	id: number,
	pos: Vec,
	value: number,
}

export type Area = {
	parts: { PartSpec },
	lights: { LightSpec },
	bounds: { min: Vec, max: Vec },
	spawns: { Vec },
}

export type Reef = Area & {
	beacons: { BeaconSpec },
	shards: { ShardSpec },
	exitGate: Vec,
	sectors: { { id: string, title: string, accent: string, centre: Vec } },
}

export type Hub = Area & {
	diveGate: Vec,
	ledger: Vec,
	codex: Vec,
	ledgerboard: Vec,
	tower: Vec,
}

export type World = {
	seed: number,
	reef: Reef,
	hub: Hub,
}

local Layout = {}

Layout.HUB_ORIGIN = { x = 0, y = 620, z = 0 }
Layout.REEF_ORIGIN = { x = 0, y = 0, z = 0 }

-- Arena metrics shared with gameplay code.
Layout.REEF_HALF_WIDTH = 92
Layout.REEF_HALF_LENGTH = 158
Layout.FLOOR_Y = 0

local P = Palette.Hex

local function v(x: number, y: number, z: number): Vec
	return { x = x, y = y, z = z }
end

local parts: { PartSpec } = {}

local function add(shape: Shape, pos: Vec, size: Vec, color: string, opts: PartOpts?): PartSpec
	local o: PartOpts = opts or {}
	local spec: PartSpec = {
		shape = shape,
		pos = pos,
		size = size,
		rot = o.rot,
		color = color,
		mat = o.mat or "Slate",
		alpha = o.alpha,
		cast = o.cast,
		tag = o.tag or "decor",
		emissive = o.emissive,
	}
	table.insert(parts, spec)
	return spec
end

local function light(pos: Vec, color: string, brightness: number, range: number): LightSpec
	return { pos = pos, color = color, brightness = brightness, range = range }
end

--------------------------------------------------------------------------------
-- Reef: a sunken cathedral-reef, 184 x 316 studs of flooded nave.
--------------------------------------------------------------------------------

local REEF_HALF_W = Layout.REEF_HALF_WIDTH
local REEF_HALF_L = Layout.REEF_HALF_LENGTH

local NAVE_HALF = 46
local AISLE_OUTER = 88
local ARCH_SPAN = 50
local ARCH_HEIGHT = 62

local function buildFloor(rng: Random.Rng)
	local tile = 23
	-- Nave deck
	for x = -2, 1 do
		for z = -7, 6 do
			local px = x * tile + tile / 2
			local pz = z * tile + tile / 2
			local tint = if (x + z) % 3 == 0 then P.StoneAlt else P.Stone
			add("Block", v(px, rng:range(-0.18, 0.05), pz), v(tile - 0.35, 2, tile - 0.35), tint, {
				mat = "Slate",
				rot = v(0, rng:range(-0.6, 0.6), 0),
				tag = "floor",
			})
		end
	end

	-- Raised side aisles
	for _, side in { -1, 1 } do
		for x = 0, 1 do
			for z = -7, 6 do
				local px = side * (NAVE_HALF + 10.5 + x * 21)
				local pz = z * tile + tile / 2
				add("Block", v(px, 4, pz), v(20.5, 2, tile - 0.4), P.StoneAlt, {
					mat = "Slate",
					tag = "floor",
				})
			end
		end
		-- step lip between nave and aisle
		for z = -7, 6 do
			add(
				"Block",
				v(side * (NAVE_HALF + 0.6), 2, z * tile + tile / 2),
				v(2.2, 4, tile - 0.4),
				P.StoneLit,
				{
					mat = "Slate",
					tag = "floor",
				}
			)
		end
	end

	-- Apse platform (north end) with a stepped dais
	for ring = 0, 2 do
		local radius = 46 - ring * 8
		add(
			"Cylinder",
			v(0, 4.6 + ring * 1.6, -132),
			v(radius, 3 + ring * 3.2, radius),
			P.StoneLit,
			{
				mat = "Slate",
				tag = "floor",
			}
		)
	end

	-- South threshold / gate apron
	add("Block", v(0, 2, 146), v(96, 4, 26), P.Stone, { mat = "Slate", tag = "floor" })
end

local function buildRibs()
	-- Repeating rib arches: the strongest compositional rhythm in the arena.
	for index = 0, 12 do
		local z = -138 + index * 21
		for _, dir in { -1, 1 } do
			-- pillar
			local baseX = dir * (NAVE_HALF - 3)
			add("Block", v(baseX, 26, z), v(9, 52, 9), P.Stone, { mat = "Slate", tag = "wall" })
			add(
				"Block",
				v(baseX, 3.5, z),
				v(13, 7, 13),
				P.StoneAlt,
				{ mat = "Slate", tag = "wall" }
			)
			add(
				"Block",
				v(baseX, 53, z),
				v(12, 3.4, 12),
				P.StoneLit,
				{ mat = "Slate", tag = "wall" }
			)
			-- neon inlay running up the pillar
			add(
				"Block",
				v(baseX - dir * 4.6, 26, z),
				v(0.5, 44, 1.6),
				P.CyanDeep,
				{ mat = "Neon", tag = "accent", emissive = 1, alpha = 0.15, cast = false }
			)
		end

		-- arch voussoirs
		local segments = 11
		for step = 0, segments do
			local t = step / segments
			local angle = math.pi * t
			local ax = math.cos(angle) * ARCH_SPAN
			local ay = math.sin(angle) * ARCH_HEIGHT
			local rot = v(0, 0, math.deg(angle) - 90)
			add(
				"Block",
				v(ax, 52 + ay, z),
				v(8.4, 2.4, 8.4),
				if step == math.floor(segments / 2) then P.StoneLit else P.Stone,
				{
					mat = "Slate",
					rot = rot,
					tag = "wall",
				}
			)
		end

		-- keystone glow
		add("Ball", v(0, 52 + ARCH_HEIGHT + 1.5, z), v(3.2, 3.2, 3.2), P.CyanDeep, {
			mat = "Neon",
			alpha = 0.25,
			tag = "accent",
			emissive = 0.8,
			cast = false,
		})
	end
end

local function buildAisleColonnade(rng: Random.Rng)
	for _, dir in { -1, 1 } do
		for index = 0, 9 do
			local z = -120 + index * 26
			local x = dir * (AISLE_OUTER - 5)
			add("Cylinder", v(x, 20, z), v(9, 36, 9), P.Stone, { mat = "Slate", tag = "wall" })
			add("Block", v(x, 3, z), v(12, 6, 12), P.StoneAlt, { mat = "Slate", tag = "wall" })
			add("Block", v(x, 39, z), v(12, 4, 12), P.StoneLit, { mat = "Slate", tag = "wall" })
			-- capital glow ring
			add("Cylinder", v(x, 42.6, z), v(10.4, 0.6, 10.4), P.CyanDeep, {
				mat = "Neon",
				alpha = 0.2,
				tag = "accent",
				emissive = 0.7,
				cast = false,
			})
			-- coral climbing the column
			for _ = 1, 3 do
				local t = rng:range(0.2, 0.9)
				add(
					"Cylinder",
					v(x + dir * rng:range(2, 5), 6 + t * 30, z + rng:range(-4, 4)),
					v(rng:range(0.7, 1.6), rng:range(8, 16), rng:range(0.7, 1.6)),
					P.CoralBone,
					{
						mat = "Slate",
						rot = v(rng:range(-16, 16), 0, rng:range(-18, 0)),
						tag = "decor",
						cast = false,
					}
				)
			end
		end
	end
end

local function buildOuterWalls()
	-- Outer shell keeps the player inside and gives the fog something to eat.
	for _, dir in { -1, 1 } do
		add("Block", v(dir * (AISLE_OUTER + 4), 30, 0), v(10, 60, REEF_HALF_L * 2), P.Stone, {
			mat = "Slate",
			tag = "wall",
		})
	end
	add(
		"Block",
		v(0, 30, REEF_HALF_L + 4),
		v((AISLE_OUTER + 8) * 2, 60, 10),
		P.Stone,
		{ mat = "Slate", tag = "wall" }
	)
	add(
		"Block",
		v(0, 30, -REEF_HALF_L - 4),
		v((AISLE_OUTER + 8) * 2, 60, 10),
		P.Stone,
		{ mat = "Slate", tag = "wall" }
	)

	-- Collapsed roof: a few heavy slabs overhead read as a broken vault.
	local slabs = {
		{ -30, 96, -96, 40, 3, 34 },
		{ 26, 100, -34, 34, 3, 46 },
		{ -18, 92, 44, 52, 3, 30 },
		{ 34, 104, 108, 26, 3, 40 },
		{ -40, 88, 122, 30, 3, 26 },
	}
	for _, slab in slabs do
		add("Block", v(slab[1], slab[2], slab[3]), v(slab[4], slab[5], slab[6]), P.Stone, {
			mat = "Slate",
			rot = v(0, 0, 0),
			tag = "roof",
		})
	end

	-- Drowned banners hanging from the vault: pale cloth, the only soft shapes.
	for index = 0, 5 do
		local z = -110 + index * 44
		add(
			"Block",
			v(0, 74, z),
			v(18, 44, 0.6),
			P.CoralBoneDim,
			{ mat = "Fabric", alpha = 0.25, cast = false, tag = "decor" }
		)
	end
end

--[[ Navigation furniture: an inlaid line down the nave plus rune markers at each
     aisle mouth. In fog this is the difference between exploring and being lost. ]]
local function buildWayfinding()
	-- central inlay, broken into tiles so it catches the light unevenly
	for z = -126, 148, 8 do
		if (z + 126) % 24 ~= 0 then
			add("Block", v(0, 0.09, z), v(2.2, 0.22, 5.4), P.CyanDeep, {
				mat = "Neon",
				alpha = 0.35,
				tag = "glow",
				emissive = 0.5,
				cast = false,
			})
		end
	end
	-- aisle mouths
	type Mouth = { x: number, z: number }
	local mouths: { Mouth } = {
		{ x = -NAVE_HALF - 2, z = -84 },
		{ x = NAVE_HALF + 2, z = -84 },
		{ x = -NAVE_HALF - 2, z = 24 },
		{ x = NAVE_HALF + 2, z = 24 },
	}
	for _, mouth in mouths do
		local x, z = mouth.x, mouth.z
		add("Block", v(x, 2.6, z), v(3.4, 5.2, 12), P.CyanDeep, {
			mat = "Neon",
			alpha = 0.45,
			tag = "glow",
			emissive = 0.7,
			cast = false,
		})
		add("Block", v(x * 1.06, 5.4, z), v(1.2, 1.2, 13), P.Mint, {
			mat = "Neon",
			alpha = 0.2,
			tag = "accent",
			emissive = 1,
			cast = false,
		})
	end

	-- light shafts falling through the ruined vault: pure atmosphere, and they
	-- give the eye a vertical reference in the fog.
	for index = 0, 5 do
		local z = -110 + index * 44
		local x = if index % 2 == 0 then -9 else 11
		add("Block", v(x, 52, z), v(3.2, 84, 3.2), P.Cyan, {
			mat = "Glass",
			alpha = 0.94,
			tag = "shaft",
			emissive = 0.55,
			cast = false,
		})
		add("Cylinder", v(x, 1.2, z), v(16, 0.2, 16), P.CyanDeep, {
			mat = "Neon",
			alpha = 0.7,
			tag = "glow",
			emissive = 0.4,
			cast = false,
		})
	end
end

local function buildHangingBells()
	-- Drowned bells, still on their chains. Silhouettes that read at any distance.
	for index = 0, 3 do
		local z = -90 + index * 62
		local x = if index % 2 == 0 then 14 else -14
		local depth = 52 - index * 3
		add(
			"Cylinder",
			v(x, depth + 30, z),
			v(0.9, 34, 0.9),
			P.CoralBoneDim,
			{ mat = "Metal", tag = "decor", cast = false }
		)
		add(
			"Cylinder",
			v(x, depth + 8, z),
			v(13, 18, 13),
			P.StoneLit,
			{ mat = "Metal", tag = "decor" }
		)
		add(
			"Cylinder",
			v(x, depth - 1.6, z),
			v(15, 2, 15),
			P.CoralBone,
			{ mat = "Metal", tag = "decor" }
		)
		add("Ball", v(x, depth - 4.4, z), v(4, 4, 4), P.CyanDeep, {
			mat = "Neon",
			alpha = 0.4,
			tag = "accent",
			emissive = 0.6,
			cast = false,
		})
	end
end

local function buildStatues()
	-- Four seated wardens in the aisles: scale and environmental storytelling.
	local seats = {
		{ -62, 4, -58, 1 },
		{ 62, 4, -20, -1 },
		{ -62, 4, 40, 1 },
		{ 62, 4, 96, -1 },
	}
	for _, seat in seats do
		local x, y, z, dir = seat[1], seat[2], seat[3], seat[4]
		add("Block", v(x, y + 4, z), v(22, 8, 22), P.StoneLit, { mat = "Slate", tag = "decor" })
		add("Block", v(x, y + 20, z), v(14, 24, 12), P.Stone, { mat = "Slate", tag = "decor" })
		add("Block", v(x, y + 34, z), v(18, 6, 13), P.Stone, { mat = "Slate", tag = "decor" })
		add("Ball", v(x, y + 42, z), v(9, 9, 9), P.Stone, { mat = "Slate", tag = "decor" })
		-- glowing eyes
		for _, eye in { -2.2, 2.2 } do
			add("Ball", v(x + eye, y + 43, z - dir * 4.4), v(1.5, 1.5, 1.5), P.Mint, {
				mat = "Neon",
				tag = "accent",
				emissive = 1,
				cast = false,
			})
		end
		-- arms resting on knees
		add(
			"Block",
			v(x - 9, y + 20, z - dir * 5),
			v(5, 16, 14),
			P.Stone,
			{ mat = "Slate", tag = "decor" }
		)
		add(
			"Block",
			v(x + 9, y + 20, z - dir * 5),
			v(5, 16, 14),
			P.Stone,
			{ mat = "Slate", tag = "decor" }
		)
	end
end

--[[ Warm/cool rim lighting. This is what makes the architecture read: without
     sconces the rib arches vanish into the fog and the reef feels flat. ]]
local function buildSconces()
	local fixtures: { { x: number, y: number, z: number, warm: boolean } } = {}
	for index = 0, 12, 2 do
		local z = -138 + index * 21
		local warm = index % 4 == 0
		table.insert(fixtures, { x = -(NAVE_HALF - 8), y = 34, z = z, warm = warm })
		table.insert(fixtures, { x = NAVE_HALF - 8, y = 34, z = z, warm = warm })
	end
	for _, side in { -1, 1 } do
		for index = 0, 3 do
			local z = -100 + index * 66
			table.insert(
				fixtures,
				{ x = side * (AISLE_OUTER - 13), y = 26, z = z, warm = index % 2 == 0 }
			)
		end
	end

	local sconceLights: { LightSpec } = {}
	for _, fixture in fixtures do
		local color = if fixture.warm then P.Amber else P.CyanDeep
		-- iron bracket
		add("Cylinder", v(fixture.x, fixture.y, fixture.z), v(1.1, 5, 1.1), P.CoralBoneDim, {
			mat = "Metal",
			tag = "decor",
			cast = false,
		})
		-- the flame itself
		add("Ball", v(fixture.x, fixture.y + 2.6, fixture.z), v(2.6, 3.4, 2.6), color, {
			mat = "Neon",
			alpha = 0.1,
			tag = "accent",
			emissive = 1,
			cast = false,
		})
		table.insert(sconceLights, light(v(fixture.x, fixture.y + 2.6, fixture.z), color, 1.7, 62))
	end

	-- Ember braziers on the nave floor give the eye a warm anchor mid-arena.
	local braziers = {
		{ -18, -72 },
		{ 18, -18 },
		{ -18, 36 },
		{ 18, 92 },
	}
	for _, spot in braziers do
		local x, z = spot[1], spot[2]
		add(
			"Cylinder",
			v(x, 3.4, z),
			v(5.4, 6.8, 5.4),
			P.CoralBoneDim,
			{ mat = "Metal", tag = "decor" }
		)
		add("Cylinder", v(x, 7.2, z), v(6.8, 1.2, 6.8), P.Rust, { mat = "Metal", tag = "decor" })
		add("Ball", v(x, 9.4, z), v(3.6, 4.4, 3.6), P.Amber, {
			mat = "Neon",
			alpha = 0.08,
			tag = "accent",
			emissive = 1,
			cast = false,
		})
		table.insert(sconceLights, light(v(x, 10, z), P.Amber, 2.4, 70))
	end

	return sconceLights
end

local function buildCoral(rng: Random.Rng)
	-- Biomass grows along the walls and the aisle edges, never in the main lane.
	local function placeSpire(x: number, z: number, scale: number)
		local height = rng:range(8, 26) * scale
		local thickness = rng:range(0.9, 2.6) * scale
		local baseY = if math.abs(x) > NAVE_HALF then 4 else 0
		local lean = rng:range(-14, 14)
		local roll = rng:nextFloat()
		local bone = if roll < 0.22 then P.Rust elseif roll < 0.4 then P.StoneLit else P.CoralBone
		add("Cylinder", v(x, baseY + height / 2, z), v(thickness, height, thickness), bone, {
			mat = "Slate",
			rot = v(lean, 0, rng:range(-12, 12)),
			tag = "decor",
			cast = false,
		})
		add(
			"Ball",
			v(x + lean * 0.06, baseY + height - rng:range(0, 3), z),
			v(thickness * 1.7, thickness * 1.7, thickness * 1.7),
			P.CyanDeep,
			{
				mat = "Neon",
				alpha = 0.45,
				tag = "accent",
				emissive = 0.6,
				cast = false,
			}
		)
	end

	for _ = 1, 210 do
		local side = rng:sign()
		local x = side * rng:range(NAVE_HALF + 2, AISLE_OUTER - 2)
		local z = rng:range(-REEF_HALF_L + 8, REEF_HALF_L - 8)
		placeSpire(x, z, rng:range(0.7, 1.5))
	end
	for _ = 1, 70 do
		local x = rng:range(-NAVE_HALF + 6, NAVE_HALF - 6)
		local z = if rng:nextFloat() < 0.5
			then rng:range(-REEF_HALF_L + 6, -110)
			else rng:range(112, REEF_HALF_L - 6)
		placeSpire(x, z, rng:range(0.5, 1.1))
	end

	-- Glow pools on the floor: soft cyan light spill for readability.
	for _ = 1, 26 do
		local side = rng:sign()
		local x = side * rng:range(NAVE_HALF - 4, AISLE_OUTER - 6)
		local z = rng:range(-140, 140)
		local radius = rng:range(2.5, 5.5)
		add("Cylinder", v(x, 4.14, z), v(radius * 2, 0.1, radius * 2), P.CyanDeep, {
			mat = "Neon",
			alpha = 0.68,
			tag = "glow",
			emissive = 0.5,
			cast = false,
		})
	end
	for _ = 1, 10 do
		local x = rng:range(-NAVE_HALF + 10, NAVE_HALF - 10)
		local z = rng:range(-150, 150)
		local radius = rng:range(3, 7)
		add("Cylinder", v(x, 0.14, z), v(radius * 2, 0.1, radius * 2), P.CyanDeep, {
			mat = "Neon",
			alpha = 0.7,
			tag = "glow",
			emissive = 0.45,
			cast = false,
		})
	end

	-- Egg clusters: dense little colonies that catch the lantern.
	for _ = 1, 80 do
		local side = rng:sign()
		local x = side * rng:range(NAVE_HALF - 6, AISLE_OUTER - 4)
		local z = rng:range(-146, 146)
		local size = rng:range(0.7, 2.1)
		add(
			"Ball",
			v(x, 4 + size * 0.6, z),
			v(size, size * 1.3, size),
			if rng:nextFloat() < 0.3 then P.Mint else P.CyanDeep,
			{
				mat = "Neon",
				alpha = rng:range(0.25, 0.6),
				tag = "accent",
				emissive = 0.7,
				cast = false,
			}
		)
	end

	-- Rubble and fallen masonry.
	for _ = 1, 70 do
		local x = rng:range(-AISLE_OUTER + 4, AISLE_OUTER - 4)
		local z = rng:range(-150, 150)
		local s = rng:range(2, 7)
		add("Block", v(x, s / 2, z), v(s, rng:range(1.5, 3.5), rng:range(2, 6)), P.StoneAlt, {
			mat = "Slate",
			rot = v(rng:range(-6, 6), rng:range(0, 90), rng:range(-10, 10)),
			tag = "decor",
			cast = false,
		})
	end

	-- Drifting plankton: tiny emissive points that give the fog depth.
	for _ = 1, 150 do
		local x = rng:range(-AISLE_OUTER, AISLE_OUTER)
		local y = rng:range(16, 74)
		local z = rng:range(-REEF_HALF_L, REEF_HALF_L)
		local s = rng:range(0.18, 0.5)
		add("Ball", v(x, y, z), v(s, s, s), if rng:nextFloat() < 0.2 then P.Ember else P.Mint, {
			mat = "Neon",
			alpha = rng:range(0.1, 0.5),
			tag = "mote",
			emissive = 1,
			cast = false,
		})
	end
end

local function buildWater()
	-- Two translucent sheets: still water in the nave, deeper water in the aisles.
	add("Block", v(0, 1.6, 0), v(NAVE_HALF * 2, 0.2, REEF_HALF_L * 2), P.Water, {
		mat = "Glass",
		alpha = 0.72,
		tag = "water",
		cast = false,
	})
	add(
		"Block",
		v(0, 5.2, 0),
		v((AISLE_OUTER - NAVE_HALF) * 2 + NAVE_HALF * 2, 0.2, REEF_HALF_L * 2),
		P.Water,
		{
			mat = "Glass",
			alpha = 0.86,
			tag = "water",
			cast = false,
		}
	)
end

local function buildBeacons(): { BeaconSpec }
	local defs = {
		{
			id = "chancel",
			title = "The Chancel",
			sector = "Nave",
			pos = v(0, 0, -132),
			accent = P.Cyan,
		},
		{
			id = "west",
			title = "West Aisle",
			sector = "Aisle",
			pos = v(-64, 4, 30),
			accent = P.Mint,
		},
		{
			id = "east",
			title = "East Aisle",
			sector = "Trench",
			pos = v(64, 4, 92),
			accent = P.Teal,
		},
	}
	local beacons: { BeaconSpec } = {}
	for _, def in defs do
		local pos = def.pos
		local baseY = pos.y
		-- hex plinth
		for i = 0, 5 do
			local angle = math.rad(i * 60)
			add(
				"Cylinder",
				v(pos.x + math.cos(angle) * 8, baseY + 1.6, pos.z + math.sin(angle) * 8),
				v(6, 3.2, 6),
				P.StoneLit,
				{
					mat = "Slate",
					tag = "beaconBase",
				}
			)
		end
		add(
			"Cylinder",
			v(pos.x, baseY + 4.4, pos.z),
			v(14, 2.4, 14),
			P.Stone,
			{ mat = "Slate", tag = "beaconBase" }
		)
		-- bowl
		add(
			"Cylinder",
			v(pos.x, baseY + 7, pos.z),
			v(8, 3.4, 8),
			P.CoralBoneDim,
			{ mat = "Metal", tag = "beaconBase" }
		)
		-- the lantern core itself (moved/dyed by the server on relight)
		add("Ball", v(pos.x, baseY + 12, pos.z), v(9.4, 12.4, 9.4), def.accent, {
			mat = "Neon",
			alpha = 0.15,
			tag = "beaconCore",
			emissive = 1,
			cast = false,
		})
		-- three orbiting shards
		for i = 0, 2 do
			local angle = math.rad(i * 120)
			add(
				"Ball",
				v(pos.x + math.cos(angle) * 11, baseY + 14 + i * 2.4, pos.z + math.sin(angle) * 11),
				v(1.8, 1.8, 1.8),
				def.accent,
				{
					mat = "Neon",
					tag = "beaconShard",
					emissive = 1,
					cast = false,
				}
			)
		end
		-- light pillar: a wayfinding beacon visible through the fog from the gate
		add("Cylinder", v(pos.x, baseY + 54, pos.z), v(3.2, 96, 3.2), def.accent, {
			mat = "Neon",
			alpha = 0.55,
			tag = "beaconBeam",
			emissive = 0.8,
			cast = false,
		})
		add("Cylinder", v(pos.x, baseY + 20, pos.z), v(6.4, 26, 6.4), def.accent, {
			mat = "Neon",
			alpha = 0.42,
			tag = "beaconBeam",
			emissive = 0.9,
			cast = false,
		})

		-- ribbed hood
		for i = 0, 3 do
			local angle = math.rad(i * 90 + 45)
			add(
				"Cylinder",
				v(pos.x + math.cos(angle) * 6, baseY + 20, pos.z + math.sin(angle) * 6),
				v(0.9, 16, 0.9),
				P.CoralBone,
				{
					mat = "Metal",
					rot = v(math.cos(angle) * 12, 0, math.sin(angle) * -12),
					tag = "beaconBase",
				}
			)
		end
		table.insert(beacons, {
			id = def.id,
			title = def.title,
			sector = def.sector,
			pos = pos,
			accent = def.accent,
		})
	end
	return beacons
end

local function buildExitGate()
	local z = 150
	add("Block", v(-26, 18, z), v(9, 36, 12), P.Stone, { mat = "Slate", tag = "wall" })
	add("Block", v(26, 18, z), v(9, 36, 12), P.Stone, { mat = "Slate", tag = "wall" })
	add("Block", v(0, 38, z), v(62, 6, 12), P.StoneLit, { mat = "Slate", tag = "wall" })
	add(
		"Block",
		v(0, 22, z),
		v(44, 30, 0.8),
		P.Teal,
		{ mat = "ForceField", alpha = 0.82, tag = "gate", cast = false }
	)
	for i = 0, 5 do
		add("Ball", v(-22 + i * 8.8, 36.2, z - 5), v(1.4, 1.4, 1.4), P.Mint, {
			mat = "Neon",
			tag = "accent",
			emissive = 1,
			cast = false,
		})
	end
end

local function buildShards(rng: Random.Rng, beacons: { BeaconSpec }): { ShardSpec }
	local shards: { ShardSpec } = {}
	local index = 0
	local function tooCloseToBeacon(pos: Vec): boolean
		for _, beacon in beacons do
			local dx, dz = pos.x - beacon.pos.x, pos.z - beacon.pos.z
			if dx * dx + dz * dz < 18 * 18 then
				return true
			end
		end
		return false
	end
	local guard = 0
	while #shards < 42 and guard < 400 do
		guard += 1
		local x = rng:range(-AISLE_OUTER + 8, AISLE_OUTER - 8)
		local z = rng:range(-150, 146)
		local y = if math.abs(x) > NAVE_HALF then 4 else 0
		local pos = v(x, y + 3.4, z)
		if not tooCloseToBeacon(pos) then
			index += 1
			table.insert(shards, { id = index, pos = pos, value = 5 })
		end
	end
	return shards
end

local function buildReefLights(beacons: { BeaconSpec }, fixtureLights: { LightSpec }): { LightSpec }
	local lights: { LightSpec } = {}
	for _, fixture in fixtureLights do
		table.insert(lights, fixture)
	end
	for _, beacon in beacons do
		table.insert(
			lights,
			light(v(beacon.pos.x, beacon.pos.y + 12, beacon.pos.z), beacon.accent, 3.2, 58)
		)
	end
	for index = 0, 5 do
		table.insert(
			lights,
			light(v(if index % 2 == 0 then -20 else 20, 40, -110 + index * 46), P.CyanDeep, 0.9, 44)
		)
	end
	table.insert(lights, light(v(0, 24, 150), P.Mint, 1.6, 52))
	return lights
end

--------------------------------------------------------------------------------
-- Hub: a lantern island above the tide.
--------------------------------------------------------------------------------

local function buildHub(): Hub
	local hubParts: { PartSpec } = {}
	local hubLights: { LightSpec } = {}
	local origin = Layout.HUB_ORIGIN

	local function hAdd(shape: Shape, pos: Vec, size: Vec, color: string, opts: PartOpts?)
		local o: PartOpts = opts or {}
		table.insert(hubParts, {
			shape = shape,
			pos = { x = origin.x + pos.x, y = origin.y + pos.y, z = origin.z + pos.z },
			size = size,
			rot = o.rot,
			color = color,
			mat = o.mat or "Slate",
			alpha = o.alpha,
			cast = o.cast,
			tag = o.tag or "decor",
			emissive = o.emissive,
		})
	end

	-- Island disc + underbelly
	hAdd("Cylinder", v(0, 0, 0), v(96, 6, 96), P.Stone, { mat = "Slate", tag = "floor" })
	hAdd("Cylinder", v(0, -7, 0), v(70, 8, 70), P.StoneAlt, { mat = "Slate", tag = "floor" })
	hAdd(
		"Cylinder",
		v(0, -20, 0),
		v(30, 20, 30),
		P.Stone,
		{ mat = "Slate", tag = "floor", rot = v(180, 0, 0) }
	)

	-- Inlaid floor rings
	hAdd(
		"Cylinder",
		v(0, 3.12, 0),
		v(78, 0.3, 78),
		P.CyanDeep,
		{ mat = "Neon", alpha = 0.72, tag = "glow", emissive = 0.4, cast = false }
	)
	hAdd("Cylinder", v(0, 3.2, 0), v(52, 0.3, 52), P.StoneLit, { mat = "Slate", tag = "floor" })

	-- Lantern tower at the south of the island
	local towerZ = -30
	hAdd("Cylinder", v(0, 6, towerZ), v(26, 12, 26), P.Stone, { mat = "Slate", tag = "floor" })
	for i = 0, 5 do
		local angle = math.rad(i * 60)
		hAdd(
			"Cylinder",
			v(math.cos(angle) * 9, 26, towerZ + math.sin(angle) * 9),
			v(3.2, 40, 3.2),
			P.Stone,
			{ mat = "Slate", tag = "wall" }
		)
	end
	hAdd("Cylinder", v(0, 46, towerZ), v(24, 4, 24), P.StoneLit, { mat = "Slate", tag = "wall" })
	hAdd(
		"Ball",
		v(0, 54, towerZ),
		v(13, 13, 13),
		P.Amber,
		{ mat = "Neon", alpha = 0.1, tag = "towerLight", emissive = 1, cast = false }
	)
	hAdd("Cylinder", v(0, 64, towerZ), v(2, 14, 2), P.CoralBone, { mat = "Metal", tag = "decor" })
	hAdd(
		"Ball",
		v(0, 72, towerZ),
		v(3, 3, 3),
		P.Ember,
		{ mat = "Neon", tag = "accent", emissive = 1, cast = false }
	)

	-- Dive gate (north of island)
	local gateZ = 34
	hAdd("Block", v(-18, 14, gateZ), v(7, 24, 9), P.Stone, { mat = "Slate", tag = "wall" })
	hAdd("Block", v(18, 14, gateZ), v(7, 24, 9), P.Stone, { mat = "Slate", tag = "wall" })
	hAdd("Block", v(0, 27, gateZ), v(44, 5, 9), P.StoneLit, { mat = "Slate", tag = "wall" })
	hAdd(
		"Block",
		v(0, 14, gateZ),
		v(30, 20, 1),
		P.Teal,
		{ mat = "ForceField", alpha = 0.55, tag = "diveGate", cast = false }
	)
	for i = 0, 4 do
		hAdd(
			"Ball",
			v(-14 + i * 7, 25.6, gateZ - 5),
			v(1.1, 1.1, 1.1),
			P.Mint,
			{ mat = "Neon", tag = "accent", emissive = 1, cast = false }
		)
	end

	-- Ledger (upgrade shop) plinth on the west, codex stone on the east
	hAdd("Cylinder", v(-34, 5, 6), v(18, 10, 18), P.Stone, { mat = "Slate", tag = "floor" })
	hAdd(
		"Block",
		v(-34, 13, 6),
		v(14, 6, 3),
		P.AmberDeep,
		{ mat = "Neon", alpha = 0.2, tag = "ledgerboard", emissive = 0.9, cast = false }
	)

	hAdd("Cylinder", v(34, 5, 6), v(18, 10, 18), P.Stone, { mat = "Slate", tag = "floor" })
	hAdd(
		"Block",
		v(34, 13, 6),
		v(14, 6, 3),
		P.CyanDeep,
		{ mat = "Neon", alpha = 0.2, tag = "codexStone", emissive = 0.9, cast = false }
	)

	-- Railing: glowing posts around the rim (also a readable "don't fall" cue)
	for i = 0, 23 do
		local angle = math.rad(i * 15)
		local x = math.cos(angle) * 45
		local z = math.sin(angle) * 45
		if not (z > 0 and math.abs(x) < 24) then
			hAdd(
				"Cylinder",
				v(x, 6.5, z),
				v(1.2, 7, 1.2),
				P.CoralBone,
				{ mat = "Metal", tag = "decor", cast = false }
			)
			hAdd(
				"Ball",
				v(x, 10.6, z),
				v(1.1, 1.1, 1.1),
				P.Ember,
				{ mat = "Neon", tag = "accent", emissive = 1, cast = false }
			)
		end
	end

	-- Moored lantern buoys floating off the edge (composition + depth cue)
	for i = 0, 5 do
		local angle = math.rad(i * 60 + 30)
		local x = math.cos(angle) * 78
		local z = math.sin(angle) * 78
		hAdd(
			"Ball",
			v(x, -6, z),
			v(5, 5, 5),
			P.Amber,
			{ mat = "Neon", alpha = 0.25, tag = "buoy", emissive = 1, cast = false }
		)
		hAdd(
			"Cylinder",
			v(x, -14, z),
			v(1, 12, 1),
			P.CoralBoneDim,
			{ mat = "Metal", tag = "decor", cast = false }
		)
	end

	-- The hub is the first thing a player sees, so it carries the most authored
	-- furniture in the game: a causeway, standing stones, a chart monument, an
	-- obelisk and an arch to give the two shops different silhouettes.
	for index = 0, 4 do
		local z = 16 + index * 5
		for _, side in { -1, 1 } do
			hAdd(
				"Cylinder",
				v(side * 9, 6.5, z),
				v(1.4, 7, 1.4),
				P.CoralBone,
				{ mat = "Metal", tag = "decor", cast = false }
			)
			hAdd("Ball", v(side * 9, 10.4, z), v(2.1, 2.1, 2.1), P.Amber, {
				mat = "Neon",
				tag = "accent",
				emissive = 1,
				cast = false,
			})
			table.insert(
				hubLights,
				light(v(origin.x + side * 9, origin.y + 10.4, origin.z + z), P.Amber, 1.5, 30)
			)
		end
	end

	for index = 0, 11 do
		local angle = math.rad(index * 30 + 15)
		local x = math.cos(angle) * 41
		local z = math.sin(angle) * 41
		local height = 14 + (index % 3) * 5
		hAdd("Block", v(x, 3 + height / 2, z), v(5.5, height, 3.2), P.Stone, {
			mat = "Slate",
			rot = v(0, math.deg(angle) + 90, 0),
			tag = "decor",
		})
		hAdd(
			"Block",
			v(x * 0.97, 3 + height * 0.62, z * 0.97),
			v(0.8, height * 0.5, 0.6),
			P.CyanDeep,
			{
				mat = "Neon",
				alpha = 0.3,
				rot = v(0, math.deg(angle) + 90, 0),
				tag = "accent",
				emissive = 0.8,
				cast = false,
			}
		)
	end

	-- Central monument: a drowned chart of the reef with the three beacons marked.
	hAdd("Cylinder", v(0, 4.4, 0), v(16, 1.6, 16), P.StoneLit, { mat = "Slate", tag = "floor" })
	hAdd(
		"Cylinder",
		v(0, 6, 0),
		v(12, 2.4, 12),
		P.Water,
		{ mat = "Glass", alpha = 0.55, tag = "glow", cast = false }
	)
	type Marker = { x: number, z: number, color: string }
	local markers: { Marker } = {
		{ x = -3.5, z = -3, color = P.Cyan },
		{ x = 3.2, z = 0.5, color = P.Mint },
		{ x = 0.5, z = 3.4, color = P.Teal },
	}
	for _, marker in markers do
		hAdd("Ball", v(marker.x, 7.4, marker.z), v(1.5, 1.5, 1.5), marker.color, {
			mat = "Neon",
			tag = "accent",
			emissive = 1,
			cast = false,
		})
	end
	hAdd("Cylinder", v(0, 12, 0), v(2.4, 12, 2.4), P.Stone, { mat = "Slate", tag = "decor" })
	hAdd(
		"Ball",
		v(0, 19, 0),
		v(4.2, 4.2, 4.2),
		P.CyanDeep,
		{ mat = "Neon", alpha = 0.3, tag = "accent", emissive = 1, cast = false }
	)
	table.insert(hubLights, light(v(origin.x, origin.y + 22, origin.z), P.Cyan, 2.6, 46))

	-- Obelisk (codex) and arch (ledger): two very different silhouettes.
	hAdd("Block", v(34, 22, 6), v(7.5, 36, 7.5), P.Stone, { mat = "Slate", tag = "decor" })
	hAdd("Block", v(34, 40.4, 6), v(4.2, 4, 4.2), P.StoneLit, { mat = "Slate", tag = "decor" })
	for index = 0, 3 do
		hAdd(
			"Block",
			v(34, 12 + index * 7, 2.6),
			v(4.4, 1.6, 0.4),
			P.CyanDeep,
			{ mat = "Neon", tag = "accent", emissive = 0.9, cast = false }
		)
	end

	hAdd("Block", v(-41, 18, 6), v(4.4, 30, 4.4), P.Stone, { mat = "Slate", tag = "decor" })
	hAdd("Block", v(-27, 18, 6), v(4.4, 30, 4.4), P.Stone, { mat = "Slate", tag = "decor" })
	hAdd("Block", v(-34, 34.4, 6), v(19, 4.6, 4.6), P.StoneLit, { mat = "Slate", tag = "decor" })
	hAdd(
		"Block",
		v(-34, 30, 6),
		v(15, 1.2, 1.2),
		P.Amber,
		{ mat = "Neon", alpha = 0.15, tag = "accent", emissive = 1, cast = false }
	)

	-- Tide shelf + distant spires: depth cues for a small island on a big sea.
	hAdd(
		"Cylinder",
		v(0, -46, 0),
		v(300, 1, 300),
		P.CyanDeep,
		{ mat = "Neon", alpha = 0.86, tag = "water", emissive = 0.5, cast = false }
	)
	hAdd(
		"Cylinder",
		v(0, -47, 0),
		v(200, 1, 200),
		P.Teal,
		{ mat = "Neon", alpha = 0.7, tag = "water", emissive = 0.7, cast = false }
	)

	for index = 0, 9 do
		local angle = math.rad(index * 36 + 9)
		local distance = 170 + (index % 3) * 60
		local x = math.cos(angle) * distance
		local z = math.sin(angle) * distance
		local height = 90 + (index % 4) * 55
		hAdd(
			"Cylinder",
			v(x, -40 + height / 2, z),
			v(18 + (index % 3) * 8, height, 18 + (index % 3) * 8),
			P.Stone,
			{
				mat = "Slate",
				rot = v((index % 5) * 3, index * 17, (index % 3) * 4),
				tag = "decor",
				cast = false,
			}
		)
		hAdd("Ball", v(x, -40 + height, z), v(5, 5, 5), P.CyanDeep, {
			mat = "Neon",
			alpha = 0.5,
			tag = "accent",
			emissive = 0.6,
			cast = false,
		})
	end

	-- Water plane beneath the island
	hAdd(
		"Block",
		v(0, -52, 0),
		v(900, 0.4, 900),
		P.Water,
		{ mat = "Glass", alpha = 0.7, tag = "water", cast = false }
	)

	table.insert(hubLights, light(v(origin.x, origin.y + 54, origin.z - 30), P.Amber, 4.5, 120))
	table.insert(hubLights, light(v(origin.x, origin.y + 14, origin.z + 34), P.Teal, 2.2, 60))
	table.insert(hubLights, light(v(origin.x - 34, origin.y + 13, origin.z + 6), P.Ember, 1.4, 30))
	table.insert(hubLights, light(v(origin.x + 34, origin.y + 13, origin.z + 6), P.Cyan, 1.4, 30))

	return {
		parts = hubParts,
		lights = hubLights,
		bounds = {
			min = v(origin.x - 46, origin.y - 8, origin.z - 46),
			max = v(origin.x + 46, origin.y + 80, origin.z + 46),
		},
		spawns = { v(origin.x, origin.y + 6, origin.z + 18) },
		diveGate = v(origin.x, origin.y + 6, origin.z + 34),
		ledger = v(origin.x - 34, origin.y + 6, origin.z + 6),
		codex = v(origin.x + 34, origin.y + 6, origin.z + 6),
		ledgerboard = v(origin.x - 34, origin.y + 13, origin.z + 6),
		tower = v(origin.x, origin.y + 54, origin.z - 30),
	}
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function Layout.build(seed: number?): World
	local worldSeed = seed or 20261029
	local rng = Random.new(worldSeed)

	parts = {}
	buildFloor(rng)
	buildRibs()
	buildAisleColonnade(rng)
	buildOuterWalls()
	buildStatues()
	local beacons = buildBeacons()
	local fixtureLights = buildSconces()
	buildWayfinding()
	buildHangingBells()
	buildCoral(rng)
	buildWater()
	buildExitGate()
	local shards = buildShards(rng, beacons)
	local reefParts = parts

	local reef: Reef = {
		parts = reefParts,
		lights = buildReefLights(beacons, fixtureLights),
		bounds = {
			min = v(-REEF_HALF_W, -4, -REEF_HALF_L),
			max = v(REEF_HALF_W, 110, REEF_HALF_L),
		},
		spawns = { v(0, 3.4, 132) },
		beacons = beacons,
		shards = shards,
		exitGate = v(0, 2, 143),
		sectors = {
			{ id = "Nave", title = "The Nave", accent = P.Cyan, centre = v(0, 0, -40) },
			{ id = "Aisle", title = "West Aisle", accent = P.Mint, centre = v(-64, 4, 30) },
			{ id = "Trench", title = "East Aisle", accent = P.Teal, centre = v(64, 4, 92) },
		},
	}

	return {
		seed = worldSeed,
		reef = reef,
		hub = buildHub(),
	}
end

return Layout
