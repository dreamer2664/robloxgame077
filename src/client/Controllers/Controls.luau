--!strict
--[[
	Input. Keyboard/mouse, gamepad and the on-screen touch buttons all funnel into
	the same three verbs: pulse, flare, sprint.

	Local cooldowns gate the UI feel; the server re-checks every request.
]]

local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local ClientNet = require(script.Parent.ClientNet)
local Store = require(script.Parent.Store)

local Controls = {}

export type Cooldowns = {
	pulse: number,
	flare: number,
}

local cooldowns: Cooldowns = { pulse = 0, flare = 0 }
local sprinting = false
local enabled = true
local listeners: { (cooldowns: Cooldowns, sprinting: boolean) -> () } = {}

local function notify()
	for _, listener in listeners do
		listener(cooldowns, sprinting)
	end
end

function Controls.getCooldowns(): Cooldowns
	return cooldowns
end

function Controls.isSprinting(): boolean
	return sprinting
end

function Controls.onChange(listener: (cooldowns: Cooldowns, sprinting: boolean) -> ())
	table.insert(listeners, listener)
end

function Controls.setEnabled(value: boolean)
	enabled = value
	if not value and sprinting then
		sprinting = false
		ClientNet.fire(Net.Intent.Sprint, { on = false })
		notify()
	end
end

local function canAct(): boolean
	if not enabled then
		return false
	end
	local state = Store.get()
	return state.phase == "dive" and state.inDive
end

function Controls.pulse()
	if not canAct() then
		return
	end
	if os.clock() < cooldowns.pulse then
		return
	end
	cooldowns.pulse = os.clock() + Config.Light.PulseCooldown
	ClientNet.fire(Net.Intent.Pulse)
	notify()
end

local function aimDirection(): Vector3
	local camera = workspace.CurrentCamera
	if camera then
		return camera.CFrame.LookVector
	end
	return Vector3.new(0, 0, -1)
end

function Controls.flare()
	if not canAct() then
		return
	end
	if os.clock() < cooldowns.flare then
		return
	end
	cooldowns.flare = os.clock() + Config.Light.FlareCooldown
	local aim = aimDirection()
	ClientNet.fire(Net.Intent.Flare, { aim = { x = aim.X, y = aim.Y, z = aim.Z } })
	notify()
end

function Controls.setSprint(on: boolean)
	if on == sprinting then
		return
	end
	if on and not canAct() then
		return
	end
	sprinting = on
	ClientNet.fire(Net.Intent.Sprint, { on = on })
	notify()
end

function Controls.start()
	ContextActionService:BindAction("EW_Pulse", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			Controls.pulse()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)

	ContextActionService:BindAction("EW_Flare", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			Controls.flare()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.F, Enum.KeyCode.ButtonR1)

	ContextActionService:BindAction("EW_Sprint", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			Controls.setSprint(true)
		elseif
			inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel
		then
			Controls.setSprint(false)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)

	-- Mouse: left click also flares (right thumb does the same on touch).
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			Controls.flare()
		end
	end)

	-- Drive the cooldown readouts. Fast while something is recharging, idle
	-- otherwise, so we never burn frames on a static HUD.
	task.spawn(function()
		while true do
			local now = os.clock()
			if cooldowns.pulse > now or cooldowns.flare > now then
				notify()
				task.wait(1 / 20)
			else
				task.wait(0.2)
			end
		end
	end)
end

return Controls
