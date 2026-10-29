--!strict
--[[
	Owns the remote surface and is the *only* place client messages enter the
	server. Every intent is checked for:
	  1. an allow-listed action name,
	  2. an exact payload shape (no extra fields, no smuggling),
	  3. a per-player, per-action token bucket,
	  4. a live humanoid.
	Only then is the gameplay handler invoked.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Validate = require(Shared.Validate)
local RateLimiter = require(Shared.RateLimiter)

export type IntentHandler = (player: Player, payload: any) -> ()

type Bucket = RateLimiter.Bucket

-- The strict solver types `pcall` over a void-returning callback as returning a
-- single value, which loses the error slot. Widen it once, here, so handlers can
-- still report their failure reason.
local pcallAny = pcall :: any

local NetService = {}
NetService.__index = NetService

export type NetService = typeof(setmetatable(
	{} :: {
		folder: Folder?,
		intentRemote: RemoteEvent?,
		signalRemote: RemoteEvent?,
		queryRemote: RemoteFunction?,
		handlers: { [string]: IntentHandler },
		queryHandlers: { [string]: (player: Player, payload: any) -> any },
		buckets: { [number]: { [string]: Bucket } },
		dropped: number,
	},
	NetService
))

function NetService.new(): NetService
	local self = setmetatable({}, NetService)
	self.handlers = {}
	self.queryHandlers = {}
	self.buckets = {}
	self.dropped = 0
	return self
end

function NetService.start(self: NetService)
	local folder = Instance.new("Folder")
	folder.Name = Net.FOLDER
	folder.Parent = ReplicatedStorage

	local intent = Instance.new("RemoteEvent")
	intent.Name = Net.INTENT
	intent.Parent = folder

	local signal = Instance.new("RemoteEvent")
	signal.Name = Net.SIGNAL
	signal.Parent = folder

	local query = Instance.new("RemoteFunction")
	query.Name = Net.QUERY
	query.Parent = folder

	self.folder = folder
	self.intentRemote = intent
	self.signalRemote = signal
	self.queryRemote = query

	intent.OnServerEvent:Connect(function(player: Player, ...)
		self:dispatch(player, ...)
	end)

	query.OnServerInvoke = function(player: Player, kind: unknown, payload: unknown): any
		return self:dispatchQuery(player, kind, payload)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		self.buckets[player.UserId] = nil
	end)
end

function NetService.onIntent(self: NetService, action: string, handler: IntentHandler)
	self.handlers[action] = handler
end

function NetService.onQuery(
	self: NetService,
	kind: string,
	handler: (player: Player, payload: any) -> any
)
	self.queryHandlers[kind] = handler
end

function NetService.signal(self: NetService, player: Player, event: string, payload: any?)
	local remote = self.signalRemote
	if not remote or not player.Parent then
		return
	end
	remote:FireClient(player, event, payload)
end

function NetService.signalAll(self: NetService, event: string, payload: any?)
	local remote = self.signalRemote
	if not remote then
		return
	end
	remote:FireAllClients(event, payload)
end

function NetService.budgetFor(self: NetService, player: Player, action: string): Bucket
	local perPlayer = self.buckets[player.UserId]
	if not perPlayer then
		perPlayer = {}
		self.buckets[player.UserId] = perPlayer
	end
	local bucket = perPlayer[action]
	if not bucket then
		local budget = Net.IntentBudget[action]
		bucket = RateLimiter.new(budget and budget[1] or 2, budget and budget[2] or 4, os.clock())
		perPlayer[action] = bucket
	end
	return bucket
end

local function isAlive(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

--[[ Validates a raw intent. Returns (ok, reason). ]]
function NetService.validateIntent(
	self: NetService,
	player: Player,
	action: unknown,
	payload: unknown
): (boolean, string?)
	if type(action) ~= "string" then
		return false, "non-string action"
	end
	local shape = Net.INTENT_SHAPES[action :: string]
	if not shape then
		return false, "unknown intent"
	end
	local shapeOk, shapeReason = Validate.shape(payload, shape.allowed, shape.required)
	if not shapeOk then
		return false, shapeReason
	end
	if not isAlive(player) then
		return false, "no live character"
	end
	local allowed = RateLimiter.consume(self:budgetFor(player, action :: string), os.clock())
	if not allowed then
		return false, "rate limited"
	end
	return true, nil
end

function NetService.dispatch(self: NetService, player: Player, action: unknown, payload: unknown)
	local ok, reason = self:validateIntent(player, action, payload)
	if not ok then
		self.dropped += 1
		if reason ~= "rate limited" and reason ~= "no live character" then
			warn(`[ECHOWAKE] dropped intent from {player.Name}: {reason}`)
		end
		return
	end
	local handler = self.handlers[action :: string]
	if not handler then
		return
	end
	local success, err = pcallAny(handler, player, payload)
	if not success then
		warn(`[ECHOWAKE] intent '{action}' failed: {err}`)
	end
end

function NetService.dispatchQuery(
	self: NetService,
	player: Player,
	kind: unknown,
	payload: unknown
): any
	if type(kind) ~= "string" then
		return nil
	end
	local handler = self.queryHandlers[kind :: string]
	if not handler then
		return nil
	end
	local allowed = RateLimiter.consume(self:budgetFor(player, `q:{kind}`), os.clock())
	if not allowed then
		return nil
	end
	local ok, result = pcallAny(handler, player, payload)
	if not ok then
		warn(`[ECHOWAKE] query '{kind}' failed: {result}`)
		return nil
	end
	return result
end

return NetService
