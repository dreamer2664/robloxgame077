--!strict
--[[
	The complete client <-> server surface.

	Deliberately tiny: one RemoteEvent in each direction plus one RemoteFunction.
	Client->server messages are *intents* (never state), each validated centrally
	in ServerNet before it reaches gameplay code.
]]

local Net = {}

Net.FOLDER = "Remotes"
Net.INTENT = "Intent"
Net.SIGNAL = "Signal"
Net.QUERY = "Query"

-- Client -> server (RemoteEvent: (action, payload?))
Net.Intent = {
	Dive = "dive",
	Leave = "leave",
	Pulse = "pulse",
	Flare = "flare",
	Upgrade = "upgrade",
	Hue = "hue",
	Sprint = "sprint",
	Codex = "codex",
	Ready = "ready",
}

-- Server -> client (RemoteEvent: (event, payload?))
Net.Signal = {
	Light = "light", -- { value, capacity }
	Pulse = "pulse", -- { x, y, z, radius, userId }
	Reveal = "reveal", -- { ids, duration, origin = {x,y,z}, radius }
	Phase = "phase", -- { phase, ... }
	Run = "run", -- { timeLeft, beacons, complete, carried }
	Shard = "shard", -- { id, x, y, z, value, userId }
	Gloam = "gloam", -- { id, kind, state, x, y, z } (spawn/death/position hints)
	Hit = "hit", -- { x, y, z, kind } damage feedback
	Doused = "doused", -- { reason }
	Toast = "toast", -- { text, tone }
	Save = "save", -- full sanitised save for UI
	Bank = "bank", -- payout summary
	Prompt = "prompt", -- { text } contextual prompt for the HUD
	Flare = "flare", -- { x, y, z, ax, ay, az } flare cone VFX
	Panel = "panel", -- { name } open a hub panel (ledger / codex)
}

-- Client -> server (RemoteFunction: (query, payload?) -> result)
Net.Query = {
	State = "state",
	Ledger = "ledger",
}

--[[ Payload shapes the server will accept for each intent. Anything else is
     dropped before it can reach gameplay code. ]]
Net.INTENT_SHAPES = {
	[Net.Intent.Dive] = { allowed = {}, required = {} },
	[Net.Intent.Leave] = { allowed = {}, required = {} },
	[Net.Intent.Pulse] = { allowed = {}, required = {} },
	[Net.Intent.Flare] = { allowed = { "aim" }, required = { "aim" } },
	[Net.Intent.Upgrade] = { allowed = { "id" }, required = { "id" } },
	[Net.Intent.Hue] = { allowed = { "id" }, required = { "id" } },
	[Net.Intent.Sprint] = { allowed = { "on" }, required = { "on" } },
	[Net.Intent.Codex] = { allowed = { "id" }, required = { "id" } },
	[Net.Intent.Ready] = { allowed = {}, required = {} },
}

--[[ Server-side rate limits: { rate per second, burst }. ]]
Net.IntentBudget = {
	[Net.Intent.Dive] = { 0.5, 2 },
	[Net.Intent.Leave] = { 0.5, 2 },
	[Net.Intent.Pulse] = { 2, 4 },
	[Net.Intent.Flare] = { 4, 6 },
	[Net.Intent.Upgrade] = { 2, 4 },
	[Net.Intent.Hue] = { 1, 3 },
	[Net.Intent.Sprint] = { 4, 8 },
	[Net.Intent.Codex] = { 2, 4 },
	[Net.Intent.Ready] = { 1, 3 },
}

export type LightPayload = { value: number, capacity: number }
export type RunPayload = {
	timeLeft: number,
	beacons: { { id: string, progress: number, lit: boolean } },
	complete: boolean,
	carried: number,
	beaconsLit: number,
}

return Net
