--!strict
--[[
	Everything the player *sees* of their own lantern: the carried orb, its light,
	the fog thickness of each area, the pulse shockwave, the flare flash, the
	"echo outline" of revealed Gloam, camera shake and pickup sparks.

	All of it is client-side presentation. Damage, reveal eligibility and light
	values come from the server.
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Palette = require(Shared.Palette)

local SoundKit = require(script.Parent.SoundKit)

local Lantern = {}
Lantern.__index = Lantern

local HUE_COLORS: { [string]: string } = {
	amber = "#FFB25E",
	mint = "#9BF6D8",
	violet = "#C08BFF",
	crimson = "#FF6B7F",
	ice = "#7FB2FF",
}

export type Lantern = typeof(setmetatable(
	{} :: {
		player: Player,
		orb: Part?,
		light: PointLight?,
		glow: Part?,
		shakeStrength: number,
		shakeUntil: number,
		revealed: { [BasePart]: number },
		glowFolder: Folder?,
		currentHue: string,
		fogTarget: number,
		ambient: Color3,
	},
	Lantern
))

local function toColor(hex: string): Color3
	local r, g, b = Palette.parse(hex)
	return Color3.fromRGB(
		math.floor(r * 255 + 0.5),
		math.floor(g * 255 + 0.5),
		math.floor(b * 255 + 0.5)
	)
end

function Lantern.new(): Lantern
	local player = Players.LocalPlayer
	local self = setmetatable({
		player = player,
		orb = nil,
		light = nil,
		glow = nil,
		shakeStrength = 0,
		shakeUntil = 0,
		revealed = {},
		glowFolder = nil,
		currentHue = "amber",
		fogTarget = 340,
		ambient = Color3.fromRGB(255, 178, 94),
	}, Lantern)
	return self
end

--------------------------------------------------------------------------------
-- rig
--------------------------------------------------------------------------------

function Lantern.buildRig(self: Lantern)
	local existing = workspace:FindFirstChild("EchowakeClientFx")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "EchowakeClientFx"
	folder.Parent = workspace
	self.glowFolder = folder

	local orb = Instance.new("Part")
	orb.Name = "LanternOrb"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(1.15, 1.15, 1.15)
	orb.Material = Enum.Material.Neon
	orb.Color = self.ambient
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = false
	orb.CastShadow = false
	orb.Transparency = 0.12
	orb.Parent = folder

	local halo = Instance.new("Part")
	halo.Name = "LanternHalo"
	halo.Shape = Enum.PartType.Ball
	halo.Size = Vector3.new(3.4, 3.4, 3.4)
	halo.Material = Enum.Material.Neon
	halo.Color = self.ambient
	halo.Anchored = true
	halo.CanCollide = false
	halo.CanQuery = false
	halo.CanTouch = false
	halo.CastShadow = false
	halo.Transparency = 0.82
	halo.Parent = folder

	local light = Instance.new("PointLight")
	light.Color = self.ambient
	light.Brightness = 2.6
	light.Range = 30
	light.Shadows = true
	light.Parent = orb

	self.orb = orb
	self.glow = halo
	self.light = light
end

function Lantern.setHue(self: Lantern, hue: string)
	if self.currentHue == hue and self.light then
		return
	end
	self.currentHue = hue
	local color = toColor(HUE_COLORS[hue] or HUE_COLORS.amber)
	self.ambient = color
	if self.light then
		self.light.Color = color
	end
	if self.orb then
		self.orb.Color = color
	end
	if self.glow then
		self.glow.Color = color
	end
end

function Lantern.setRadius(self: Lantern, radius: number)
	if self.light then
		self.light.Range = radius
	end
end

--------------------------------------------------------------------------------
-- vfx
--------------------------------------------------------------------------------

function Lantern.shake(self: Lantern, strength: number, duration: number)
	self.shakeStrength = math.max(self.shakeStrength, strength)
	self.shakeUntil = math.max(self.shakeUntil, os.clock() + duration)
end

--[[ Expanding ground ring + shell: the "sound" the player sends into the dark. ]]
function Lantern.pulseWave(self: Lantern, position: Vector3, radius: number, color: Color3)
	local folder = self.glowFolder
	if not folder then
		return
	end

	local ring = Instance.new("Part")
	ring.Name = "PulseRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.35, 4, 4)
	ring.CFrame = CFrame.new(position - Vector3.new(0, 2.4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.25
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = folder

	local shell = Instance.new("Part")
	shell.Name = "PulseShell"
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.new(4, 4, 4)
	shell.CFrame = CFrame.new(position)
	shell.Material = Enum.Material.ForceField
	shell.Color = color
	shell.Transparency = 0.55
	shell.Anchored = true
	shell.CanCollide = false
	shell.CanQuery = false
	shell.CanTouch = false
	shell.CastShadow = false
	shell.Parent = folder

	local duration = 0.85
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.clamp((os.clock() - start) / duration, 0, 1)
		local eased = 1 - (1 - alpha) ^ 2
		local currentRadius = 4 + eased * radius * 2
		ring.Size = Vector3.new(0.35, currentRadius, currentRadius)
		ring.Transparency = 0.2 + alpha * 0.8
		shell.Size = Vector3.new(currentRadius, currentRadius, currentRadius)
		shell.Transparency = 0.55 + alpha * 0.45
		if alpha >= 1 then
			connection:Disconnect()
			ring:Destroy()
			shell:Destroy()
		end
	end)

	Debris:AddItem(ring, duration + 0.5)
	Debris:AddItem(shell, duration + 0.5)
	self:shake(0.25, 0.3)
	SoundKit.play("pulse", self.orb)
end

function Lantern.flareFlash(self: Lantern, position: Vector3, direction: Vector3, color: Color3)
	local folder = self.glowFolder
	if not folder then
		return
	end
	local flash = Instance.new("Part")
	flash.Name = "FlareFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(5, 5, 5)
	flash.CFrame = CFrame.new(position + direction * 6)
	flash.Material = Enum.Material.Neon
	flash.Color = color
	flash.Transparency = 0.05
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.CastShadow = false
	flash.Parent = folder

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 8
	light.Range = 34
	light.Parent = flash

	local start = os.clock()
	local duration = 0.3
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.clamp((os.clock() - start) / duration, 0, 1)
		flash.Size = Vector3.new(5 + alpha * 16, 5 + alpha * 16, 5 + alpha * 16)
		flash.Transparency = 0.05 + alpha * 0.95
		light.Brightness = 8 * (1 - alpha)
		if alpha >= 1 then
			connection:Disconnect()
			flash:Destroy()
		end
	end)
	Debris:AddItem(flash, duration + 0.4)
	self:shake(0.55, 0.28)
	SoundKit.play("flare", self.orb)
end

function Lantern.pickupSpark(self: Lantern, position: Vector3)
	local folder = self.glowFolder
	if not folder then
		return
	end
	local spark = Instance.new("Part")
	spark.Shape = Enum.PartType.Ball
	spark.Size = Vector3.new(2, 2, 2)
	spark.CFrame = CFrame.new(position)
	spark.Material = Enum.Material.Neon
	spark.Color = toColor(Palette.Hex.Ember)
	spark.Anchored = true
	spark.CanCollide = false
	spark.CanQuery = false
	spark.CanTouch = false
	spark.Parent = folder
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.clamp((os.clock() - start) / 0.45, 0, 1)
		spark.Size = Vector3.new(2 + alpha * 8, 2 + alpha * 8, 2 + alpha * 8)
		spark.Transparency = alpha
		if alpha >= 1 then
			connection:Disconnect()
			spark:Destroy()
		end
	end)
	Debris:AddItem(spark, 1)
	SoundKit.play("shard", self.orb, 1.2)
end

--------------------------------------------------------------------------------
-- reveal
--------------------------------------------------------------------------------

--[[ Gloam are nearly invisible until something reveals them. ]]
--[[ Hides Gloam until something reveals them. Runs on its own thread: the folder
     does not exist until the server starts GloamService, and blocking the client
     bootstrap on WaitForChild would delay signal wiring (and lose the first
     phase/light updates). ]]
function Lantern.watchGloam(_self: Lantern)
	task.spawn(function()
		local gloamFolder = workspace:WaitForChild("Gloam", 30)
		if not gloamFolder then
			warn("[ECHOWAKE] Gloam folder never appeared; enemy stealth disabled")
			return
		end
		local function hide(instance: Instance)
			if instance:IsA("BasePart") then
				instance.LocalTransparencyModifier = 0.94
			end
			instance.DescendantAdded:Connect(function(child)
				if child:IsA("BasePart") then
					child.LocalTransparencyModifier = 0.94
				end
			end)
		end
		for _, child in gloamFolder:GetChildren() do
			hide(child)
		end
		gloamFolder.ChildAdded:Connect(hide)
	end)
end

function Lantern.reveal(self: Lantern, ids: { number }, duration: number)
	local gloamFolder = workspace:FindFirstChild("Gloam")
	if not gloamFolder then
		return
	end
	local untilTime = os.clock() + duration
	for _, child in gloamFolder:GetChildren() do
		local id = child:GetAttribute("EWGloamId")
		if id == nil then
			-- server sets the id on the part when it spawns
			id = child:GetAttribute("EWId")
		end
		if id ~= nil then
			for _, wanted in ids do
				if id == wanted then
					for _, descendant in child:GetDescendants() do
						if descendant:IsA("BasePart") then
							descendant.LocalTransparencyModifier = 0.1
							self.revealed[descendant] = untilTime
						end
					end
					if child:IsA("BasePart") then
						child.LocalTransparencyModifier = 0.1
						self.revealed[child] = untilTime
					end
					break
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- atmosphere
--------------------------------------------------------------------------------

function Lantern.setPhaseMood(self: Lantern, phase: string)
	local isDive = phase == "dive"
	local fog = if isDive then 210 else 520
	local ambient = if isDive then Color3.fromRGB(3, 8, 14) else Color3.fromRGB(5, 14, 22)
	if math.abs(Lighting.FogEnd - fog) > 1 then
		TweenService:Create(Lighting, TweenInfo.new(1.8, Enum.EasingStyle.Quad), { FogEnd = fog })
			:Play()
	end
	TweenService:Create(Lighting, TweenInfo.new(1.8, Enum.EasingStyle.Quad), { Ambient = ambient })
		:Play()
	self.fogTarget = fog
end

--------------------------------------------------------------------------------
-- per-frame
--------------------------------------------------------------------------------

function Lantern.step(self: Lantern, _dt: number)
	local player = self.player
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local orb = self.orb
	if orb and root and root:IsA("BasePart") then
		local bob = math.sin(os.clock() * 2.2) * 0.12
		local offset = CFrame.new(1.25, 1.05 + bob, 1.75)
			* CFrame.Angles(0, math.sin(os.clock() * 0.9) * 0.2, 0)
		orb.CFrame = root.CFrame * offset
		if self.glow then
			self.glow.CFrame = orb.CFrame
			self.glow.Transparency = 0.78 + math.sin(os.clock() * 3.1) * 0.05
		end
		orb.Transparency = 0.1
	elseif orb then
		orb.CFrame = CFrame.new(0, -500, 0)
		if self.glow then
			self.glow.CFrame = orb.CFrame
		end
	end

	-- Expire echoes
	local now = os.clock()
	for part, expiry in self.revealed do
		if now > expiry then
			if part.Parent then
				part.LocalTransparencyModifier = 0.94
			end
			self.revealed[part] = nil
		end
	end

	-- Camera shake: applied through Humanoid.CameraOffset so it layers on top of
	-- the default camera controller instead of fighting it for the CFrame.
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if now < self.shakeUntil then
			local remaining = (self.shakeUntil - now) / 0.3
			local strength = self.shakeStrength * math.clamp(remaining, 0, 1)
			humanoid.CameraOffset =
				Vector3.new((math.random() - 0.5) * strength, (math.random() - 0.5) * strength, 0)
		elseif self.shakeStrength > 0 then
			self.shakeStrength = 0
			humanoid.CameraOffset = Vector3.new(0, 0, 0)
		end
	end
end

return Lantern
