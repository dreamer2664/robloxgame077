--!strict
--[[ Gloam bestiary: the data behind both the server AI and the hub codex UI. ]]

export type Archetype = {
	id: string,
	title: string,
	lore: string,
	tell: string,
	maxHealth: number,
	speed: number,
	radius: number,
	color: string,
	accent: string,
	shardDrop: number,
	emberDrop: number,
}

local Codex = {}

Codex.ARCHETYPES = {
	{
		id = "Drifter",
		title = "Drifter",
		lore = "A slow bloom of hungry tissue. It cannot see, but it remembers where light was.",
		tell = "Drifts toward any burning lantern. Uneven, patient, relentless.",
		maxHealth = 60,
		speed = 8.2,
		radius = 2.2,
		color = "#FF4D6D",
		accent = "#FFB0C0",
		shardDrop = 2,
		emberDrop = 8,
	},
	{
		id = "Lunger",
		title = "Lunger",
		lore = "Coiled muscle under a shell of bone-bright chitin. It waits for a pulse to give it a target.",
		tell = "Dashes when you are close and lit. Sidestep, then flare.",
		maxHealth = 45,
		speed = 11.5,
		radius = 1.8,
		color = "#FF8A5C",
		accent = "#FFD9B0",
		shardDrop = 2,
		emberDrop = 11,
	},
	{
		id = "Siphon",
		title = "Siphon",
		lore = "A drifting lung of the reef. It does not hunt divers; it drinks the beacons.",
		tell = "Ignores you and drains beacon progress. Relight it or lose the door.",
		maxHealth = 90,
		speed = 6.4,
		radius = 2.8,
		color = "#C08BFF",
		accent = "#E6D2FF",
		shardDrop = 3,
		emberDrop = 14,
	},
} :: { Archetype }

local byId: { [string]: Archetype } = {}
for _, archetype in Codex.ARCHETYPES do
	byId[archetype.id] = archetype
end

Codex.BY_ID = byId

function Codex.get(id: unknown): Archetype?
	if type(id) ~= "string" then
		return nil
	end
	return byId[id :: string]
end

return Codex
