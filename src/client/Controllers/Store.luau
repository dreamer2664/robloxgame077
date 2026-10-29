--!strict
--[[
	One client-side state object, updated only from server signals, and a tiny
	subscription list. Presentation code reads this; nothing else stores state.
]]

local Store = {}

export type RunState = {
	timeLeft: number,
	beacons: { { id: string, progress: number, lit: boolean } },
	complete: boolean,
	carried: number,
	beaconsLit: number,
}

export type State = {
	phase: string,
	inDive: boolean,
	light: number,
	capacity: number,
	run: RunState?,
	save: any,
	stats: any,
	rank: string,
	readOnly: boolean,
	lastBank: any,
}

type Listener = (state: State, key: string) -> ()

local state: State = {
	phase = "hub",
	inDive = false,
	light = 100,
	capacity = 100,
	run = nil,
	save = nil,
	stats = nil,
	rank = "Unlit",
	readOnly = false,
	lastBank = nil,
}

local listeners: { Listener } = {}

function Store.get(): State
	return state
end

function Store.on(listener: Listener)
	table.insert(listeners, listener)
end

function Store.patch(values: { [string]: any })
	local changed = ""
	for key, value in values do
		(state :: any)[key] = value
		changed = key
	end
	for _, listener in listeners do
		listener(state, changed)
	end
end

function Store.inDive(): boolean
	return state.phase == "dive" and state.inDive
end

return Store
