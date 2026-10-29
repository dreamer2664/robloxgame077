--!strict
--[[
	Persistence.

	Guarantees
	* a player always has a usable record, even when DataStore is unavailable
	  (Studio without API access, outages) - the game degrades to in-memory;
	* payloads read back from disk are sanitised through SaveSchema before they
	  touch gameplay code;
	* a lightweight write lease stops two servers from clobbering each other,
	  which is the usual cause of item duplication;
	* everything is retried with backoff and never yields inside a signal handler
	  without a guard.
]]

local DataStoreService = game:GetService("DataStoreService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local SaveSchema = require(Shared.SaveSchema)

local pcallAny = pcall :: any

export type SaveData = SaveSchema.SaveData

export type PlayerRecord = {
	save: SaveData,
	loaded: boolean,
	dirty: boolean,
	readOnly: boolean,
	lastSavedAt: number,
	saveCount: number,
}

local PlayerDataService = {}
PlayerDataService.__index = PlayerDataService

export type PlayerDataService = typeof(setmetatable(
	{} :: {
		store: DataStore?,
		available: boolean,
		sessionId: string,
		records: { [Player]: PlayerRecord },
		blacklistWarned: boolean,
		stopLoop: (() -> ())?,
	},
	PlayerDataService
))

local RETRIES = Config.Persistence.MaxRetries
local LEASE = Config.Persistence.LockLeaseSeconds

function PlayerDataService.new(): PlayerDataService
	local self = setmetatable({}, PlayerDataService)
	self.records = {}
	self.sessionId = `srv-{math.floor(os.time())}-{math.random(100000, 999999)}`
	self.available = true
	self.store = nil
	self.blacklistWarned = false
	return self
end

function PlayerDataService.start(self: PlayerDataService)
	local ok, store = pcallAny(function()
		return DataStoreService:GetDataStore(Config.Persistence.StoreName)
	end)
	if ok and store then
		self.store = store :: DataStore
	else
		self.available = false
		warn(`[ECHOWAKE] DataStore unavailable; running with in-memory saves ({store})`)
	end

	local stop = false
	task.spawn(function()
		while not stop do
			task.wait(Config.Persistence.AutosaveInterval)
			for player in self.records do
				self:save(player)
			end
		end
	end)
	self.stopLoop = function()
		stop = true
	end

	game:BindToClose(function()
		self:saveAll()
		task.wait(2)
	end)
end

local function keyFor(player: Player): string
	return Config.Persistence.KeyPrefix .. tostring(player.UserId)
end

local function nowSeconds(): number
	return os.time()
end

--[[ Claims (or renews) this server's write lease. Returns false if another live
     server holds it. ]]
function PlayerDataService.claimLease(self: PlayerDataService, player: Player): boolean
	local store = self.store
	if not store then
		return true
	end
	local claimed = false
	local attempts = 0
	while attempts < RETRIES and not claimed do
		attempts += 1
		local ok, result = pcallAny(function()
			return store:UpdateAsync(keyFor(player), function(old: unknown)
				local existing: any = if type(old) == "table" then old else {}
				local lease = existing._lease
				local now = nowSeconds()
				if
					type(lease) == "table"
					and lease.server ~= self.sessionId
					and type(lease.at) == "number"
					and now - lease.at < LEASE
				then
					return nil -- refuse: a live server owns this save
				end
				existing._lease = { server = self.sessionId, at = now }
				return existing
			end)
		end)
		if ok and result ~= nil then
			claimed = true
		elseif ok then
			return false -- explicitly refused
		else
			task.wait(0.4 * attempts)
		end
	end
	return claimed
end

function PlayerDataService.loadAsync(self: PlayerDataService, player: Player): PlayerRecord
	local existing = self.records[player]
	if existing then
		return existing
	end

	local save = SaveSchema.default(nowSeconds())
	local readOnly = false

	if self.store then
		local attempt = 0
		local loaded = false
		while attempt < RETRIES and not loaded do
			attempt += 1
			local ok, result = pcallAny(function()
				return (self.store :: DataStore):GetAsync(keyFor(player))
			end)
			if ok then
				loaded = true
				if type(result) == "table" then
					-- Never trust the payload: sanitise through the schema.
					save = SaveSchema.sanitize(result, nowSeconds())
				end
			else
				warn(`[ECHOWAKE] load failed for {player.Name} (attempt {attempt}): {result}`)
				task.wait(0.5 * attempt)
			end
		end
		if not loaded then
			-- Refuse to write over data we could not read; a fresh save would
			-- silently wipe the player's progress.
			readOnly = true
			warn(`[ECHOWAKE] {player.Name} is read-only for this session (load failed)`)
		elseif not self:claimLease(player) then
			readOnly = true
			warn(`[ECHOWAKE] {player.Name} is read-only: save is leased to another server`)
		end
	end

	save.lastSeenAt = nowSeconds()
	local record: PlayerRecord = {
		save = save,
		loaded = true,
		dirty = false,
		readOnly = readOnly,
		lastSavedAt = 0,
		saveCount = 0,
	}
	self.records[player] = record
	return record
end

function PlayerDataService.get(self: PlayerDataService, player: Player): PlayerRecord?
	return self.records[player]
end

--[[ Applies a pure transformation and marks the record dirty. ]]
function PlayerDataService.mutate(
	self: PlayerDataService,
	player: Player,
	transform: (SaveData) -> SaveData
): SaveData?
	local record = self.records[player]
	if not record then
		return nil
	end
	record.save = transform(record.save)
	record.dirty = true
	return record.save
end

function PlayerDataService.save(self: PlayerDataService, player: Player): boolean
	local record = self.records[player]
	if not record or not record.dirty then
		return true
	end
	if record.readOnly or not self.store then
		record.dirty = false
		return false
	end

	local payload = table.clone(record.save) :: any
	payload._lease = { server = self.sessionId, at = nowSeconds() }

	local stored = false
	local attempt = 0
	while attempt < RETRIES and not stored do
		attempt += 1
		local ok, result = pcallAny(function()
			return (self.store :: DataStore):UpdateAsync(keyFor(player), function(old: unknown)
				local existing: any = if type(old) == "table" then old else {}
				local lease = existing._lease
				local now = nowSeconds()
				if
					type(lease) == "table"
					and lease.server ~= self.sessionId
					and type(lease.at) == "number"
					and now - lease.at < LEASE
				then
					return nil
				end
				return payload
			end)
		end)
		if ok and result ~= nil then
			stored = true
		else
			warn(`[ECHOWAKE] save failed for {player.Name} (attempt {attempt}): {result}`)
			task.wait(0.5 * attempt)
		end
	end

	if stored then
		record.dirty = false
		record.lastSavedAt = os.clock()
		record.saveCount += 1
	elseif not self.blacklistWarned then
		self.blacklistWarned = true
		warn("[ECHOWAKE] repeated save failures; keeping data in memory")
	end
	return stored
end

function PlayerDataService.saveAll(self: PlayerDataService)
	for player in self.records do
		if player.Parent then
			self:save(player)
		end
	end
end

--[[ Called on PlayerRemoving: final save, then drop the record. ]]
function PlayerDataService.release(self: PlayerDataService, player: Player)
	local record = self.records[player]
	if not record then
		return
	end
	self:save(player)
	if self.store and not record.readOnly then
		local store = self.store
		pcallAny(function()
			store:UpdateAsync(keyFor(player), function(old: unknown)
				local existing: any = if type(old) == "table" then old else {}
				local lease = existing._lease
				if type(lease) == "table" and lease.server == self.sessionId then
					existing._lease = { server = "released", at = 0 }
					return existing
				end
				return nil
			end)
		end)
	end
	self.records[player] = nil
end

function PlayerDataService.playerCount(self: PlayerDataService): number
	local count = 0
	for _ in self.records do
		count += 1
	end
	return count
end

return PlayerDataService
