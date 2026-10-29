local T = require("../support/TinyTest")
local SaveSchema = require("../shared/SaveSchema")

T.suite("SaveSchema")

T.case("garbage payloads become a valid default save", function()
	for _, payload in { nil, 42, "hello", true, {} } do
		local save = SaveSchema.sanitize(payload, 100)
		T.equal(save.version, 3, `sanitised {type(payload)} payload has current version`)
		T.equal(save.embers, 0, "no free embers from garbage")
		T.equal(save.lanternHue, "amber", "default hue")
		T.ok(type(save.upgrades) == "table", "upgrade table always exists")
	end
end)

T.case("impossible values are clamped, not trusted", function()
	local save = SaveSchema.sanitize({
		version = 3,
		embers = 1e15,
		lifetimeEmbers = -500,
		beaconsLit = 0 / 0,
		dives = 1e12,
		bestDiveSeconds = 0 / 0,
		upgrades = { lantern = 5000, wick = -3, resonance = "lots" },
		lanternHue = "rainbow",
		codex = { Drifter = true, Secret = true },
	}, 50)

	T.equal(save.embers, 1e9, "embers clamped to the ceiling")
	T.equal(save.lifetimeEmbers, 0, "negative lifetime embers floored at 0")
	T.equal(save.beaconsLit, 0, "NaN counter floored")
	T.equal(save.dives, 1e7, "absurd counter clamped")
	T.equal(save.bestDiveSeconds, 0, "NaN time floored")
	T.equal(save.upgrades.lantern, 99, "upgrade level clamped")
	T.equal(save.upgrades.wick, 0, "negative level floored")
	T.equal(save.upgrades.resonance, 0, "non-numeric level dropped")
	T.equal(save.upgrades.hack, nil, "unknown upgrade key dropped")
	T.equal(save.lanternHue, "amber", "invalid hue falls back")
	T.equal(save.codex.Drifter, true, "known codex entry kept")
	T.equal(save.codex.Secret, nil, "unknown codex entry dropped")
end)

T.case("v1 payload migrates forward", function()
	local migrated = SaveSchema.sanitize({
		gold = 240,
		lanternLevel = 3,
		stats = { earned = 900, beacons = 7, dives = 2 },
	}, 1000)
	T.equal(migrated.embers, 240, "gold renamed to embers")
	T.equal(migrated.upgrades.lantern, 3, "flat lantern level moved into upgrades")
	T.equal(migrated.lifetimeEmbers, 900, "stats blob unpacked")
	T.equal(migrated.beaconsLit, 7, "beacon count preserved")
	T.equal(migrated.dives, 2, "dive count preserved")
	T.equal(migrated.version, 3, "upgraded to current version")
end)

T.case("timestamps are sane", function()
	local save = SaveSchema.sanitize({ version = 3, firstSeenAt = 5000, lastSeenAt = 100 }, 10)
	T.ok(save.firstSeenAt <= save.lastSeenAt, "first seen never after last seen")
end)

T.case("boolean flags must be exactly true", function()
	local save = SaveSchema.sanitize({ version = 3, codex = { Drifter = "yes", Lunger = 1 } }, 0)
	T.equal(save.codex.Drifter, nil, "string truthiness ignored")
	T.equal(save.codex.Lunger, nil, "number truthiness ignored")
end)

return true
