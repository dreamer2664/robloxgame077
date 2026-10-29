--!strict
--[[
	ECHOWAKE - client bootstrap.

	Owns the presentation loop: HUD, panels, lantern rig, input. It reads only
	from Store (which is fed by server signals) and never decides gameplay
	outcomes - every action is an intent sent to the server.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)

local ClientNet = require(script.Controllers.ClientNet)
local Controls = require(script.Controllers.Controls)
local Lantern = require(script.Controllers.Lantern)
local SoundKit = require(script.Controllers.SoundKit)
local Store = require(script.Controllers.Store)

local Hud = require(script.UI.Hud)
local Panels = require(script.UI.Panels)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

ClientNet.start()

-- The game has no health bar and no inventory: hide the default ones so the HUD
-- owns the screen. Wrapped because CoreGui is not always ready at script start.
task.spawn(function()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)
		end)
		if ok then
			return
		end
		task.wait(0.25)
	end
end)

local hud = Hud.new(playerGui)
local panels = Panels.new(playerGui)
local lantern = Lantern.new()

lantern:buildRig()
lantern:watchGloam()
hud:resize()

SoundKit.preload()

--------------------------------------------------------------------------------
-- state wiring
--------------------------------------------------------------------------------

local function refreshHud()
	hud:update(Store.get(), Controls.getCooldowns(), Controls.isSprinting())
end

local function applySave(payload: any)
	if not payload or not payload.save then
		return
	end
	Store.patch({
		save = payload.save,
		stats = payload.stats,
		rank = payload.rank,
		readOnly = payload.readOnly == true,
	})
	panels:setData(payload)
	if payload.save.lanternHue then
		lantern:setHue(payload.save.lanternHue)
	end
	if payload.stats then
		lantern:setRadius(payload.stats.lanternRadius)
	end
	refreshHud()
end

ClientNet.on(Net.Signal.Light, function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	Store.patch({ light = payload.value, capacity = payload.capacity })
end)

ClientNet.on(Net.Signal.Run, function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	Store.patch({ run = payload, phase = "dive", inDive = true })
end)

ClientNet.on(Net.Signal.Phase, function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local previous = Store.get().phase
	local updates: { [string]: any } = { phase = payload.phase }
	if payload.phase == "hub" then
		updates.inDive = false
		updates.run = nil
	elseif payload.inDive ~= nil then
		updates.inDive = payload.inDive == true
	end
	Store.patch(updates)
	lantern:setPhaseMood(payload.phase)
	if previous ~= payload.phase then
		if payload.phase == "dive" then
			hud:banner("THE REEF BELOW")
		else
			hud:banner("SURFACED")
		end
	end
	Controls.setEnabled(Store.get().phase == "dive" and Store.get().inDive)
	refreshHud()
end)

ClientNet.on(Net.Signal.Save, function(payload: any)
	applySave(payload)
end)

ClientNet.on(Net.Signal.Toast, function(payload: any)
	if type(payload) == "table" and type(payload.text) == "string" then
		hud:toast(payload.text, payload.tone)
	end
end)

ClientNet.on(Net.Signal.Pulse, function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local position = Vector3.new(payload.x, payload.y, payload.z)
	lantern:pulseWave(position, payload.radius or 70, lantern.ambient)
end)

ClientNet.on(Net.Signal.Reveal, function(payload: any)
	if type(payload) ~= "table" or type(payload.ids) ~= "table" then
		return
	end
	lantern:reveal(payload.ids, payload.duration or 2.4)
end)

ClientNet.on(Net.Signal.Flare, function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local origin = Vector3.new(payload.x, payload.y, payload.z)
	local direction = Vector3.new(payload.ax or 0, payload.ay or 0, payload.az or -1)
	lantern:flareFlash(origin, direction, lantern.ambient)
end)

ClientNet.on(Net.Signal.Hit, function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	hud:flashDamage(0.3)
	lantern:shake(0.9, 0.35)
	SoundKit.play("hit", nil, 0.85)
end)

ClientNet.on(Net.Signal.Shard, function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	lantern:pickupSpark(Vector3.new(payload.x, payload.y, payload.z))
end)

ClientNet.on(Net.Signal.Bank, function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	Store.patch({ lastBank = payload })
	hud:showPayout(payload)
	SoundKit.play("bank")
end)

ClientNet.on(Net.Signal.Panel, function(payload: any)
	if
		type(payload) == "table"
		and (payload.name == "ledger" or payload.name == "codex" or payload.name == "board")
	then
		panels:openWith(payload.name)
	end
end)

panels.onOpenChanged = function(open: boolean)
	Controls.setEnabled(not open)
	if not open then
		Controls.setEnabled(Store.get().phase == "dive" and Store.get().inDive)
	end
end

--------------------------------------------------------------------------------
-- input
--------------------------------------------------------------------------------

Controls.start()

hud:setActions({
	pulse = function()
		Controls.pulse()
	end,
	flare = function()
		Controls.flare()
	end,
	sprint = function(on: boolean)
		Controls.setSprint(on)
	end,
	abandon = function()
		ClientNet.fire(Net.Intent.Leave)
	end,
})

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.L then
		panels:toggle("ledger")
	elseif input.KeyCode == Enum.KeyCode.C then
		panels:toggle("codex")
	elseif input.KeyCode == Enum.KeyCode.Escape then
		panels:close()
	end
end)

Controls.onChange(function()
	refreshHud()
end)

Store.on(function()
	refreshHud()
end)

--------------------------------------------------------------------------------
-- character / camera
--------------------------------------------------------------------------------

local function bindCharacter(character: Model)
	local stats = Store.get().stats
	if stats then
		lantern:setRadius(stats.lanternRadius)
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root and root:IsA("BasePart") then
		lantern:setPhaseMood(Store.get().phase)
	end
end

if player.Character then
	bindCharacter(player.Character)
end
player.CharacterAdded:Connect(bindCharacter)

local camera = workspace.CurrentCamera
if camera then
	camera.ViewportSize = camera.ViewportSize
	local function onViewport()
		hud:resize()
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(onViewport)
end

--------------------------------------------------------------------------------
-- boot: pull initial state, then run the presentation loop
--------------------------------------------------------------------------------

task.spawn(function()
	local state = ClientNet.query(Net.Query.State)
	if type(state) == "table" then
		Store.patch({
			phase = state.phase or "hub",
			inDive = state.inDive == true,
			run = if state.inDive
				then {
					timeLeft = state.timeLeft or 0,
					beacons = state.beacons or {},
					complete = state.complete == true,
					carried = 0,
					beaconsLit = 0,
				}
				else nil,
		})
		applySave({
			save = state.save,
			stats = state.stats,
			rank = state.rank,
		})
		lantern:setPhaseMood(state.phase or "hub")
	end
	Controls.setEnabled(Store.get().phase == "dive" and Store.get().inDive)
	hud:setPhase(Store.get().phase)
	refreshHud()
	hud:banner("ECHOWAKE")
	hud:toast("Rekindle the drowned city.", "info")
end)

local hudAccumulator = 0
RunService.RenderStepped:Connect(function(dt: number)
	lantern:step(dt)
	hudAccumulator += dt
	if hudAccumulator >= 0.05 then
		hudAccumulator = 0
		refreshHud()
	end
end)

print("[ECHOWAKE] client ready")
