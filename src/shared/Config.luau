--!strict
--[[
	ECHOWAKE — central tuning table.
	Every gameplay number lives here so balance can be adjusted in one place.
	Pure data: no Roblox APIs, so it can be unit tested and exported.
]]

export type LightConfig = {
	CapacityPerLanternLevel: number,
	BaseCapacity: number,
	MaxCapacity: number,
	RegenPerSecond: number,
	RegenPerLevel: number,
	RegenDelay: number,
	BeaconRegenMultiplier: number,
	LanternRadius: number,
	LanternRadiusPerLevel: number,
	PulseCost: number,
	PulseCooldown: number,
	PulseRadius: number,
	PulseRadiusPerLevel: number,
	RevealDuration: number,
	RevealDurationPerLevel: number,
	FlareCost: number,
	FlareCooldown: number,
	FlareRange: number,
	FlareHalfAngle: number,
	FlareDamage: number,
	FlareDamagePerLevel: number,
	FlareStagger: number,
	DousedRescueTime: number,
	SprintSpeed: number,
	WalkSpeed: number,
	SprintDrainPerSecond: number,
}

local Config = {}

Config.Info = {
	Name = "ECHOWAKE",
	Tagline = "Rekindle the drowned city.",
	Version = "1.0.0",
}

Config.Dive = {
	Duration = 300, -- seconds of dive time before the tide turns
	DurationPerExtraPlayer = 20,
	MaxPlayers = 6,
	BeaconCount = 3,
	BeaconHoldTime = 4.5, -- seconds in range to relight one beacon
	BeaconRadius = 13, -- studs from beacon core to count as "in reach"
	BeaconPayout = 60, -- embers granted per beacon relit (banked on return)
	CompletionBonus = 120, -- extra embers for relighting all three beacons
	DeathPayoutMultiplier = 0.5, -- fraction of carried embers kept when doused
	EscapePayoutMultiplier = 1.25, -- bonus for reaching the gate yourself
	MinimumDiveLevelToBank = 0,
	RewardPerShard = 5,
}

Config.Light = {
	BaseCapacity = 100,
	CapacityPerLanternLevel = 12,
	MaxCapacity = 220,
	RegenPerSecond = 1.9,
	RegenPerLevel = 0.16,
	RegenDelay = 1.1,
	BeaconRegenMultiplier = 5,
	LanternRadius = 26,
	LanternRadiusPerLevel = 1.6,
	PulseCost = 18,
	PulseCooldown = 5.5,
	PulseRadius = 74,
	PulseRadiusPerLevel = 3.4,
	RevealDuration = 2.6,
	RevealDurationPerLevel = 0.14,
	FlareCost = 22,
	FlareCooldown = 3.4,
	FlareRange = 32,
	FlareHalfAngle = 34, -- half of the cone's total angle
	FlareDamage = 34,
	FlareDamagePerLevel = 6,
	FlareStagger = 1.6,
	DousedRescueTime = 4.0,
	SprintSpeed = 23,
	WalkSpeed = 16,
	SprintDrainPerSecond = 7,
} :: LightConfig

Config.Gloam = {
	MaxAlive = 26,
	BasePopulation = 9,
	PopulationPerPlayer = 2, -- keeps a full 6-player server inside MaxAlive after unlit-beacon bonus
	PopulationPerUnlitBeacon = 2,
	TickRate = 12, -- server AI updates per second (clients interpolate between them)
	SpawnRadiusMin = 42,
	SpawnRadiusMax = 96,
	SpawnCooldown = 2.4,
	ContactDamage = 14,
	ContactCooldown = 1.15,
	LightSeekBias = 1.0,
	PulseAttractRadius = 78,
	PulseAttractTime = 3.2,
}

Config.Progression = {
	MaxLevel = 8,
	CostBase = 90,
	CostGrowth = 1.55,
}

Config.Persistence = {
	StoreName = "EchowakeSave_v1",
	OrderedStoreName = "EchowakeLedger_v1",
	KeyPrefix = "player_",
	SaveVersion = 3,
	AutosaveInterval = 90,
	LockLeaseSeconds = 90,
	MaxRetries = 4,
	LeaderboardSize = 15,
}

Config.Leaderboard = {
	RefreshInterval = 60,
}

Config.Ui = {
	ToastDuration = 2.8,
	HudFadeTime = 0.35,
}

return Config
