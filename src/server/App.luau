--!strict
--[[
	The shared server context.

	Services are constructed once in init.server.luau and handed to each other
	through this table, which keeps construction order explicit and avoids
	circular `require`s between services.

	`dive` is deliberately typed `any`: DiveService requires App for its type, so
	referencing DiveService here would close the cycle.
]]

local Builder = require(script.Parent.World.Builder)
local GloamService = require(script.Parent.Services.GloamService)
local LeaderboardService = require(script.Parent.Services.LeaderboardService)
local NetService = require(script.Parent.Services.NetService)
local PlayerDataService = require(script.Parent.Services.PlayerDataService)

export type App = {
	net: NetService.NetService,
	data: PlayerDataService.PlayerDataService,
	gloam: GloamService.GloamService,
	board: LeaderboardService.LeaderboardService,
	world: Builder.WorldRuntime,
	dive: any,
}

local App = {}
return App
