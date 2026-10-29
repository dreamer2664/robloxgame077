--!strict
--[[ Thin, typed wrapper over the two remotes. All server traffic goes through it. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

-- See NetService: the strict solver types `pcall` over a void callback as
-- returning one value, so widen it to keep the error slot.
local pcallAny = pcall :: any

local ClientNet = {}

type Handler = (payload: any) -> ()

local handlers: { [string]: { Handler } } = {}
local intentRemote: RemoteEvent? = nil
local signalRemote: RemoteEvent? = nil
local queryRemote: RemoteFunction? = nil
local ready = false

function ClientNet.start()
	if ready then
		return
	end
	local folder = ReplicatedStorage:WaitForChild(Net.FOLDER)
	intentRemote = folder:WaitForChild(Net.INTENT) :: RemoteEvent
	signalRemote = folder:WaitForChild(Net.SIGNAL) :: RemoteEvent
	queryRemote = folder:WaitForChild(Net.QUERY) :: RemoteFunction
	(signalRemote :: RemoteEvent).OnClientEvent:Connect(function(event: string, payload: any)
		local list = handlers[event]
		if not list then
			return
		end
		for _, handler in list do
			local ok, err = pcallAny(handler, payload)
			if not ok then
				warn(`[ECHOWAKE] signal '{event}' handler failed: {err}`)
			end
		end
	end)
	ready = true
end

function ClientNet.on(event: string, handler: Handler)
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
	end
	table.insert(list, handler)
end

function ClientNet.fire(action: string, payload: any?)
	if not intentRemote then
		return
	end
	(intentRemote :: RemoteEvent):FireServer(action, payload)
end

function ClientNet.query(kind: string, payload: any?): any
	if not queryRemote then
		return nil
	end
	local ok, result = pcall(function()
		return (queryRemote :: RemoteFunction):InvokeServer(kind, payload)
	end)
	if not ok then
		warn(`[ECHOWAKE] query '{kind}' failed: {result}`)
		return nil
	end
	return result
end

return ClientNet
