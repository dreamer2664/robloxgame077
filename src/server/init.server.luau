--!strict
--[[
	ECHOWAKE - server bootstrap.

	Order matters:
	  1. build the world (geometry, prompts, spawns),
	  2. create and start services (Net before anything that talks to clients),
	  3. start the dive service *before* any character exists, so the
	     CharacterAdded hook is in place for the first spawn,
	  4. only then load player data and spawn characters.

	Every stage is wrapped so one failing subsystem cannot take the whole
	experience down silently.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local App = require(script.App)
local Builder = require(script.World.Builder)
local DiveService = require(script.Services.DiveService)
local GloamService = require(script.Services.GloamService)
local LeaderboardService = require(script.Services.LeaderboardService)
local NetService = require(script.Services.NetService)
local PlayerDataService = require(script.Services.PlayerDataService)

local pcallAny = pcall :: any

local function guard(label: string, fn: () -> ()): boolean
	local ok, err = pcallAny(fn)
	if not ok then
		warn(`[ECHOWAKE] {label} failed: {err}`)
	end
	return ok
end

local bootStart = os.clock()

local world = Builder.build()
print(`[ECHOWAKE] world built in {math.floor((os.clock() - bootStart) * 1000)}ms`)

local app: App.App = {
	net = NetService.new(),
	data = PlayerDataService.new(),
	gloam = GloamService.new(),
	board = LeaderboardService.new(),
	world = world,
	dive = nil,
}

local dive = DiveService.new()
app.dive = dive

guard("net", function()
	app.net:start()
end)
guard("data", function()
	app.data:start()
end)
guard("board", function()
	app.board:start()
end)
guard("gloam", function()
	app.gloam:start()
end)
guard("dive", function()
	dive:start(app)
end)

-- Player lifecycle -----------------------------------------------------------

local spawning: { [Player]: boolean } = {}

local function spawnPlayer(player: Player)
	if spawning[player] then
		return
	end
	spawning[player] = true
	local loaded = guard(`load {player.Name}`, function()
		app.data:loadAsync(player)
	end)
	if not loaded then
		warn(`[ECHOWAKE] {player.Name} loaded without persisted data`)
	end
	task.spawn(function()
		local ok = pcallAny(function()
			player:LoadCharacterAsync()
		end)
		if not ok then
			warn(`[ECHOWAKE] could not spawn {player.Name}`)
		end
		-- DiveService.onCharacterReady is invoked by the CharacterAdded hook; if the
		-- character already exists (fast spawn) call it directly.
		task.wait(0.15)
		if player.Character then
			dive:onCharacterReady(player)
		end
		dive:pushSave(player)
		app.net:signal(player, Net.Signal.Phase, { phase = "hub" })
		spawning[player] = nil
	end)
end

Players.PlayerAdded:Connect(spawnPlayer)

for _, player in Players:GetPlayers() do
	task.spawn(spawnPlayer, player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	guard(`leave {player.Name}`, function()
		dive:handlePlayerRemoving(player)
	end)
	guard(`save {player.Name}`, function()
		app.data:release(player)
	end)
end)

print(`[ECHOWAKE] server ready in {math.floor((os.clock() - bootStart) * 1000)}ms`)
