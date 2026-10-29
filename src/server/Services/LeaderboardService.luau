--!strict
--[[
	Lifetime-ember ledger (OrderedDataStore), refreshed on a slow loop and cached
	so no client request ever blocks on a datastore call.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local pcallAny = pcall :: any

export type Entry = {
	rank: number,
	name: string,
	score: number,
	isLocal: boolean,
}

local LeaderboardService = {}
LeaderboardService.__index = LeaderboardService

export type LeaderboardService = typeof(setmetatable(
	{} :: {
		store: OrderedDataStore?,
		cache: { Entry },
		nameCache: { [number]: string },
		lastRefresh: number,
		available: boolean,
	},
	LeaderboardService
))

function LeaderboardService.new(): LeaderboardService
	local self = setmetatable({}, LeaderboardService)
	self.cache = {}
	self.nameCache = {}
	self.lastRefresh = 0
	self.available = true
	self.store = nil
	return self
end

function LeaderboardService.start(self: LeaderboardService)
	local ok, store = pcallAny(function()
		return DataStoreService:GetOrderedDataStore(Config.Persistence.OrderedStoreName)
	end)
	if ok and store then
		self.store = store :: OrderedDataStore
	else
		self.available = false
		warn("[ECHOWAKE] leaderboard datastore unavailable; board will stay empty")
	end

	task.spawn(function()
		while true do
			self:refresh()
			task.wait(Config.Leaderboard.RefreshInterval)
		end
	end)
end

--[[ Publishes a lifetime score, but only if it improves on the stored value. ]]
function LeaderboardService.submit(self: LeaderboardService, player: Player, score: number)
	local store = self.store
	if not store or score <= 0 then
		return
	end
	self.nameCache[player.UserId] = player.DisplayName
	pcallAny(function()
		local current = store:GetAsync(tostring(player.UserId))
		if type(current) ~= "number" or score > current then
			store:SetAsync(tostring(player.UserId), math.floor(score))
		end
	end)
end

function LeaderboardService.refresh(self: LeaderboardService)
	local store = self.store
	if not store then
		return
	end
	local ok, pages = pcallAny(function()
		return store:GetSortedAsync(false, Config.Persistence.LeaderboardSize)
	end)
	if not ok or not pages then
		return
	end
	local pageOk, entries = pcallAny(function()
		return pages:GetCurrentPage()
	end)
	if not pageOk or type(entries) ~= "table" then
		return
	end

	local result: { Entry } = {}
	for rank, entry in entries :: { { key: string, value: number } } do
		local userId = tonumber(entry.key)
		local name = if userId then self.nameCache[userId] else nil
		if not name and userId then
			local nameOk, fetched = pcallAny(function()
				return Players:GetNameFromUserIdAsync(userId)
			end)
			if nameOk and type(fetched) == "string" then
				name = fetched :: string
				self.nameCache[userId] = name
			end
		end
		table.insert(result, {
			rank = rank,
			name = name or "Lamplighter",
			score = math.floor(entry.value),
			isLocal = false,
		})
	end
	self.cache = result
	self.lastRefresh = os.clock()
end

function LeaderboardService.getCached(self: LeaderboardService, player: Player?): { Entry }
	local result: { Entry } = {}
	for _, entry in self.cache do
		table.insert(result, {
			rank = entry.rank,
			name = entry.name,
			score = entry.score,
			isLocal = player ~= nil and entry.name == player.DisplayName,
		})
	end
	return result
end

return LeaderboardService
