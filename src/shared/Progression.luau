--!strict
--[[
	Upgrade catalogue and derived lantern statistics.
	Pure: the same maths runs on the server (authority) and the client (preview).
]]

local Config = require(script.Parent.Config)
local SaveSchema = require(script.Parent.SaveSchema)

export type SaveData = SaveSchema.SaveData

export type UpgradeDef = {
	id: string,
	title: string,
	blurb: string,
	icon: string,
	accent: string,
	maxLevel: number,
	format: (level: number) -> string,
}

export type Stats = {
	capacity: number,
	regenPerSecond: number,
	lanternRadius: number,
	pulseRadius: number,
	revealDuration: number,
	flareDamage: number,
}

local Progression = {}

Progression.UPGRADES = {
	{
		id = "lantern",
		title = "Lantern Capacity",
		blurb = "Wider reservoir of light. More pulses and flares before you gutter out.",
		icon = "ring",
		accent = "#FFB25E",
		maxLevel = Config.Progression.MaxLevel,
		format = function(level: number): string
			return `+{level * Config.Light.CapacityPerLanternLevel} max light`
		end,
	},
	{
		id = "wick",
		title = "Steady Wick",
		blurb = "Light returns faster in the dark. The reef rewards patience.",
		icon = "flame",
		accent = "#9BF6D8",
		maxLevel = Config.Progression.MaxLevel,
		format = function(level: number): string
			local regen = level * Config.Light.RegenPerLevel
			return string.format("+%.1f light/sec", regen)
		end,
	},
	{
		id = "resonance",
		title = "Resonance",
		blurb = "Your pulse carries further, mapping more of the reef per sounding.",
		icon = "wave",
		accent = "#4BE3D2",
		maxLevel = Config.Progression.MaxLevel,
		format = function(level: number): string
			return `+{math.floor(level * Config.Light.PulseRadiusPerLevel)} studs pulse range`
		end,
	},
	{
		id = "echo",
		title = "Long Echo",
		blurb = "Revealed shapes linger longer in your mind's eye.",
		icon = "eye",
		accent = "#7FB2FF",
		maxLevel = Config.Progression.MaxLevel,
		format = function(level: number): string
			return string.format("+%.1fs echo memory", level * Config.Light.RevealDurationPerLevel)
		end,
	},
	{
		id = "flare",
		title = "Flare Cut",
		blurb = "A sharper lash of light. Gloam stagger further and break sooner.",
		icon = "burst",
		accent = "#FF8A5C",
		maxLevel = Config.Progression.MaxLevel,
		format = function(level: number): string
			return `+{level * Config.Light.FlareDamagePerLevel} flare damage`
		end,
	},
} :: { UpgradeDef }

local upgradeLookup: { [string]: UpgradeDef } = {}
for _, def in Progression.UPGRADES do
	upgradeLookup[def.id] = def
end

function Progression.getUpgrade(id: unknown): UpgradeDef?
	if type(id) ~= "string" then
		return nil
	end
	return upgradeLookup[id :: string]
end

function Progression.level(save: SaveData, id: string): number
	local level = save.upgrades[id]
	if type(level) ~= "number" then
		return 0
	end
	return math.max(0, level)
end

--[[ Ember price of the next level, given the current level. ]]
function Progression.cost(id: string, currentLevel: number): number
	local def = upgradeLookup[id]
	if not def or currentLevel >= def.maxLevel then
		return math.huge
	end
	local price = Config.Progression.CostBase * (Config.Progression.CostGrowth ^ currentLevel)
	return math.floor(price / 5 + 0.5) * 5
end

function Progression.stats(save: SaveData): Stats
	local light = Config.Light
	local lantern = Progression.level(save, "lantern")
	local wick = Progression.level(save, "wick")
	local resonance = Progression.level(save, "resonance")
	local echo = Progression.level(save, "echo")
	local flare = Progression.level(save, "flare")

	return {
		capacity = math.min(
			light.MaxCapacity,
			light.BaseCapacity + lantern * light.CapacityPerLanternLevel
		),
		regenPerSecond = light.RegenPerSecond + wick * light.RegenPerLevel,
		lanternRadius = light.LanternRadius + lantern * light.LanternRadiusPerLevel,
		pulseRadius = light.PulseRadius + resonance * light.PulseRadiusPerLevel,
		revealDuration = light.RevealDuration + echo * light.RevealDurationPerLevel,
		flareDamage = light.FlareDamage + flare * light.FlareDamagePerLevel,
	}
end

export type PurchaseResult = {
	ok: boolean,
	reason: string?,
	save: SaveData,
	cost: number,
}

--[[ Attempts a purchase and returns a *new* save table. Never mutates the input. ]]
function Progression.purchase(save: SaveData, id: unknown): PurchaseResult
	local def = Progression.getUpgrade(id)
	if not def then
		return { ok = false, reason = "unknown upgrade", save = save, cost = math.huge }
	end
	local currentLevel = Progression.level(save, def.id)
	if currentLevel >= def.maxLevel then
		return { ok = false, reason = "already mastered", save = save, cost = math.huge }
	end
	local price = Progression.cost(def.id, currentLevel)
	if save.embers < price then
		return { ok = false, reason = "not enough embers", save = save, cost = price }
	end

	local nextSave: SaveData = table.clone(save)
	nextSave.upgrades = table.clone(save.upgrades)
	nextSave.embers = save.embers - price
	nextSave.upgrades[def.id] = currentLevel + 1

	return { ok = true, reason = nil, save = nextSave, cost = price }
end

function Progression.purchaseHue(save: SaveData, hue: unknown): (boolean, SaveData)
	if not SaveSchema.contains(SaveSchema.HUE_IDS, hue) then
		return false, save
	end
	local nextSave = table.clone(save)
	nextSave.lanternHue = hue :: string
	return true, nextSave
end

function Progression.rank(save: SaveData): (string, number)
	local spent = 0
	for _, def in Progression.UPGRADES do
		spent += Progression.level(save, def.id)
	end
	type RankTier = { threshold: number, name: string }
	local ranks: { RankTier } = {
		{ threshold = 0, name = "Unlit" },
		{ threshold = 3, name = "Lamplighter" },
		{ threshold = 8, name = "Tidewalker" },
		{ threshold = 14, name = "Reefwarden" },
		{ threshold = 22, name = "Beacon Saint" },
	}
	local rankName, threshold = "Unlit", 0
	for _, entry in ranks do
		if spent >= entry.threshold then
			threshold = entry.threshold
			rankName = entry.name
		end
	end
	return rankName, spent - threshold
end

return Progression
