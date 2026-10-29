--!strict
--[[
	The heads-up display.

	Layout logic: everything anchors to corners of the safe area and scales with
	viewport height, so a phone in portrait, a tablet and a 1440p monitor all get
	a readable, uncluttered HUD. Colour carries meaning: amber = your light,
	cyan = the reef, magenta = danger, mint = success.
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local LightMath = require(Shared.LightMath)

local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)

local Hud = {}
Hud.__index = Hud

export type Chip = {
	frame: Frame,
	fill: Frame,
	label: TextLabel,
	cost: TextLabel,
	stroke: UIStroke,
}

export type Hud = typeof(setmetatable(
	{} :: {
		gui: ScreenGui,
		scale: UIScale,
		root: Frame,
		runBar: Frame,
		timer: TextLabel,
		tideLabel: TextLabel,
		pips: { [string]: { frame: Frame, fill: Frame, glyph: TextLabel, stroke: UIStroke } },
		carried: TextLabel,
		lanternPanel: Frame,
		lightBar: Kit.Bar,
		lightValue: TextLabel,
		lightHint: TextLabel,
		pulseChip: Chip,
		flareChip: Chip,
		profile: Frame,
		rankLabel: TextLabel,
		emberLabel: TextLabel,
		toasts: Frame,
		crosshair: Frame,
		vignette: Frame,
		damageFlash: Frame,
		bannerLabel: TextLabel,
		footer: TextLabel,
		mobileBar: Frame,
		sprintButton: TextButton,
		payout: Frame,
		visiblePhase: string,
		actions: HudActions,
		sprintHeld: boolean,
	},
	Hud
))

local function corner(parent: Instance, radius: UDim?): UICorner
	return Kit.corner(parent, radius)
end

function Hud.new(parent: Instance): Hud
	local gui = Instance.new("ScreenGui")
	gui.Name = "EchowakeHud"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 10
	gui.Parent = parent

	local root = Kit.frame(gui, {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	local scale = Instance.new("UIScale")
	scale.Parent = root

	-- Fields are filled in by the build* passes below; the cast keeps the
	-- constructor honest without listing twenty placeholder widgets.
	local self = setmetatable(
		{
			gui = gui,
			root = root,
			scale = scale,
			visiblePhase = "",
			pips = {},
			sprintHeld = false,
			actions = {
				pulse = function() end,
				flare = function() end,
				sprint = function(_on: boolean) end,
			},
		} :: any,
		Hud
	) :: Hud

	self:buildVignette()
	self:buildCrosshair()
	self:buildRunBar()
	self:buildLantern()
	self:buildProfile()
	self:buildToasts()
	self:buildBanner()
	self:buildFooter()
	self:buildMobile()
	self:buildPayout()

	return self
end

--------------------------------------------------------------------------------
-- construction
--------------------------------------------------------------------------------

function Hud.buildVignette(self: Hud)
	local vignette = Kit.frame(self.root, {
		Name = "Vignette",
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.62,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	})
	vignette.Active = false

	-- Four soft edge gradients approximate a radial vignette without an image asset.
	local edges = {
		{ name = "Top", size = UDim2.new(1, 0, 0, 160), pos = UDim2.fromOffset(0, 0), rot = 90 },
		{
			name = "Bottom",
			size = UDim2.new(1, 0, 0, 220),
			pos = UDim2.new(0, 0, 1, -220),
			rot = 270,
		},
		{ name = "Left", size = UDim2.new(0, 200, 1, 0), pos = UDim2.fromOffset(0, 0), rot = 0 },
		{
			name = "Right",
			size = UDim2.new(0, 200, 1, 0),
			pos = UDim2.new(1, -200, 0, 0),
			rot = 180,
		},
	}
	for _, edge in edges do
		local frame = Kit.frame(vignette, {
			Name = edge.name,
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.1,
			Size = edge.size,
			Position = edge.pos,
		})
		frame.BorderSizePixel = 0
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = edge.rot
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = frame
	end

	self.vignette = vignette

	local flash = Kit.frame(self.root, {
		Name = "DamageFlash",
		BackgroundColor3 = Theme.Color.bad,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
	})
	flash.Active = false
	self.damageFlash = flash
end

function Hud.buildCrosshair(self: Hud)
	local crosshair = Kit.frame(self.root, {
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(26, 26),
		BackgroundTransparency = 1,
		ZIndex = 5,
	})
	local ring = Kit.frame(crosshair, {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(18, 18),
		BackgroundTransparency = 1,
	})
	corner(ring, UDim.new(1, 0))
	Kit.stroke(ring, Theme.Color.cyan, 1.5, 0.55)
	local dot = Kit.frame(crosshair, {
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(3, 3),
		BackgroundColor3 = Theme.Color.mint,
		BackgroundTransparency = 0.15,
	})
	corner(dot, UDim.new(1, 0))
	crosshair.Visible = false
	self.crosshair = crosshair
end

function Hud.buildRunBar(self: Hud)
	local bar = Kit.frame(self.root, {
		Name = "RunBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(430, 64),
		BackgroundTransparency = 0.18,
		ZIndex = 4,
	})
	corner(bar, UDim.new(0, 16))
	Kit.stroke(bar, Theme.Color.strokeDim, 1, 0.55)
	Kit.padding(bar, 14, 8)

	local tide = Kit.label(bar, "TIDE", {
		Font = Theme.Font.heading,
		TextSize = 10,
		TextColor3 = Theme.Color.textDim,
		Size = UDim2.fromOffset(46, 12),
		Position = UDim2.fromOffset(0, 2),
		ZIndex = 5,
	})
	self.tideLabel = tide

	local timer = Kit.label(bar, "5:00", {
		Font = Theme.Font.mono,
		TextSize = 26,
		TextColor3 = Theme.Color.text,
		Size = UDim2.fromOffset(110, 30),
		Position = UDim2.fromOffset(0, 12),
		ZIndex = 5,
	})
	self.timer = timer

	local pips = Kit.frame(bar, {
		Name = "Pips",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(120, 0),
		Size = UDim2.fromOffset(200, 48),
		ZIndex = 5,
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = pips

	for index, beaconId in { "chancel", "west", "east" } do
		local pip = Kit.frame(pips, {
			Name = `Pip_{beaconId}`,
			Size = UDim2.fromOffset(56, 44),
			BackgroundColor3 = Theme.Color.ink,
			BackgroundTransparency = 0.2,
			LayoutOrder = index,
			ZIndex = 5,
		})
		corner(pip, UDim.new(0, 8))
		local stroke = Kit.stroke(pip, Theme.Color.strokeDim, 1, 0.6)
		local fill = Kit.frame(pip, {
			Name = "Fill",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Theme.Color.cyan,
			BackgroundTransparency = 0.45,
			ZIndex = 6,
		})
		corner(fill, UDim.new(0, 8))
		local glyph = Kit.label(pip, string.upper(string.sub(beaconId, 1, 1)), {
			Font = Theme.Font.display,
			TextSize = 18,
			TextColor3 = Theme.Color.textDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 7,
		})
		self.pips[beaconId] = { frame = pip, fill = fill, glyph = glyph, stroke = stroke }
	end

	local carried = Kit.label(bar, "◆ 0", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Font = Theme.Font.heading,
		TextSize = 16,
		TextColor3 = Theme.Color.ember,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromOffset(90, 24),
		ZIndex = 5,
	})
	self.carried = carried

	bar.Visible = false
	self.runBar = bar
end

function Hud.buildLantern(self: Hud)
	local panel = Kit.frame(self.root, {
		Name = "Lantern",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 22, 1, -22),
		Size = UDim2.fromOffset(300, 118),
		BackgroundTransparency = 0.16,
		ZIndex = 4,
	})
	corner(panel, UDim.new(0, 16))
	Kit.stroke(panel, Theme.Color.strokeDim, 1, 0.5)
	Kit.padding(panel, 16, 12)

	local title = Kit.label(panel, "LANTERN", {
		Font = Theme.Font.heading,
		TextSize = 11,
		TextColor3 = Theme.Color.textDim,
		Size = UDim2.fromOffset(120, 14),
		ZIndex = 5,
	})
	title.Text = "LANTERN"

	local value = Kit.label(panel, "100%", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Font = Theme.Font.mono,
		TextSize = 14,
		TextColor3 = Theme.Color.amber,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromOffset(100, 14),
		ZIndex = 5,
	})
	self.lightValue = value

	local bar = Kit.bar(panel, {
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 12),
		ZIndex = 5,
	})
	self.lightBar = bar

	local hint = Kit.label(panel, "light is life · light is sight", {
		Position = UDim2.fromOffset(0, 38),
		Font = Theme.Font.body,
		TextSize = 11,
		TextColor3 = Theme.Color.textDim,
		Size = UDim2.new(1, 0, 0, 14),
		ZIndex = 5,
	})
	self.lightHint = hint

	local function makeChip(text: string, cost: number, order: number, accent: Color3)
		local chip = Kit.frame(panel, {
			Name = text,
			Position = UDim2.fromOffset(order * 138, 58),
			Size = UDim2.fromOffset(130, 44),
			BackgroundColor3 = Theme.Color.ink,
			BackgroundTransparency = 0.15,
			ZIndex = 5,
		})
		corner(chip, UDim.new(0, 10))
		local stroke = Kit.stroke(chip, accent, 1, 0.45)
		local fill = Kit.frame(chip, {
			Name = "Cooldown",
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.35,
			ZIndex = 6,
		})
		corner(fill, UDim.new(0, 10))
		local key = Kit.frame(chip, {
			Position = UDim2.fromOffset(9, 12),
			Size = UDim2.fromOffset(20, 20),
			BackgroundColor3 = accent,
			BackgroundTransparency = 0.72,
			ZIndex = 7,
		})
		corner(key, UDim.new(0, 5))
		Kit.label(key, text:sub(1, 1), {
			Font = Theme.Font.display,
			TextSize = 11,
			TextColor3 = Theme.Color.text,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 8,
		})
		local label = Kit.label(chip, text:upper(), {
			Position = UDim2.fromOffset(34, 12),
			Font = Theme.Font.heading,
			TextSize = 12,
			TextColor3 = Theme.Color.text,
			Size = UDim2.fromOffset(90, 20),
			ZIndex = 7,
		})
		local costLabel = Kit.label(chip, `-{cost}%`, {
			Position = UDim2.fromOffset(34, 24),
			Font = Theme.Font.body,
			TextSize = 10,
			TextColor3 = Theme.Color.textDim,
			Size = UDim2.fromOffset(90, 14),
			ZIndex = 7,
		})
		return { frame = chip, fill = fill, label = label, cost = costLabel, stroke = stroke }
	end

	self.pulseChip = makeChip("Pulse", Config.Light.PulseCost, 0, Theme.Color.cyan)
	self.flareChip = makeChip("Flare", Config.Light.FlareCost, 1, Theme.Color.amber)
	self.lanternPanel = panel
end

function Hud.buildProfile(self: Hud)
	local card = Kit.frame(self.root, {
		Name = "Profile",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -22, 0, 16),
		Size = UDim2.fromOffset(196, 62),
		BackgroundTransparency = 0.2,
		ZIndex = 4,
	})
	corner(card, UDim.new(0, 14))
	Kit.stroke(card, Theme.Color.strokeDim, 1, 0.55)
	Kit.padding(card, 12, 8)

	local rank = Kit.label(card, "UNLIT", {
		Font = Theme.Font.display,
		TextSize = 15,
		TextColor3 = Theme.Color.text,
		Size = UDim2.new(1, 0, 0, 18),
		ZIndex = 5,
	})
	local ember = Kit.label(card, "◆ 0 embers", {
		Font = Theme.Font.body,
		TextSize = 13,
		TextColor3 = Theme.Color.ember,
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 16),
		ZIndex = 5,
	})
	local hint = Kit.label(card, "E · The Ledger", {
		Font = Theme.Font.body,
		TextSize = 11,
		TextColor3 = Theme.Color.textDim,
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 0, 14),
		ZIndex = 5,
	})
	hint.Name = "Hint"

	self.profile = card
	self.rankLabel = rank
	self.emberLabel = ember
end

function Hud.buildToasts(self: Hud)
	local holder = Kit.frame(self.root, {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.fromOffset(420, 200),
		BackgroundTransparency = 1,
		ZIndex = 20,
	})
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder
	self.toasts = holder
end

function Hud.buildBanner(self: Hud)
	local banner = Kit.label(self.root, "", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.33),
		Size = UDim2.new(1, 0, 0, 54),
		Font = Theme.Font.display,
		TextSize = 34,
		TextColor3 = Theme.Color.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		ZIndex = 21,
	})
	self.bannerLabel = banner
end

function Hud.buildFooter(self: Hud)
	local footer = Kit.label(self.root, "", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -26),
		Size = UDim2.new(0, 520, 0, 24),
		Font = Theme.Font.body,
		TextSize = 14,
		TextColor3 = Theme.Color.textDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 6,
	})
	self.footer = footer
end

export type HudActions = {
	pulse: () -> (),
	flare: () -> (),
	sprint: (on: boolean) -> (),
}

function Hud.setActions(self: Hud, actions: HudActions)
	self.actions = actions
end

function Hud.buildMobile(self: Hud)
	local bar = Kit.frame(self.root, {
		Name = "MobileBar",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -22, 1, -22),
		Size = UDim2.fromOffset(180, 180),
		BackgroundTransparency = 1,
		ZIndex = 6,
	})

	local function makeButton(
		name: string,
		text: string,
		pos: UDim2,
		size: UDim2,
		accent: Color3
	): TextButton
		local button = Kit.button(bar, text, {
			Name = name,
			Position = pos,
			Size = size,
			BackgroundColor3 = Theme.Color.ink,
			BackgroundTransparency = 0.25,
			Font = Theme.Font.heading,
			TextSize = 13,
			TextColor3 = accent,
		})
		corner(button, UDim.new(1, 0))
		Kit.stroke(button, accent, 1.5, 0.35)
		return button
	end

	local pulseButton = makeButton(
		"Pulse",
		"PULSE",
		UDim2.fromOffset(0, 60),
		UDim2.fromOffset(86, 86),
		Theme.Color.cyan
	)
	local flareButton = makeButton(
		"Flare",
		"FLARE",
		UDim2.fromOffset(94, 0),
		UDim2.fromOffset(70, 70),
		Theme.Color.amber
	)
	local sprint = makeButton(
		"Sprint",
		"RUN",
		UDim2.fromOffset(112, 104),
		UDim2.fromOffset(56, 56),
		Theme.Color.mint
	)
	self.sprintButton = sprint

	pulseButton.Activated:Connect(function()
		self.actions.pulse()
	end)
	flareButton.Activated:Connect(function()
		self.actions.flare()
	end)
	sprint.Activated:Connect(function()
		self.sprintHeld = not self.sprintHeld
		self.actions.sprint(self.sprintHeld)
	end)
	self.mobileBar = bar
	bar.Visible = UserInputService.TouchEnabled
end

function Hud.buildPayout(self: Hud)
	local frame = Kit.frame(self.root, {
		Name = "Payout",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(340, 200),
		BackgroundTransparency = 0.06,
		Visible = false,
		ZIndex = 25,
	})
	corner(frame, UDim.new(0, 18))
	Kit.stroke(frame, Theme.Color.gold, 1.5, 0.3)
	Kit.padding(frame, 20, 18)

	Kit.label(frame, "SURFACED", {
		Font = Theme.Font.heading,
		TextSize = 12,
		TextColor3 = Theme.Color.textDim,
		Size = UDim2.new(1, 0, 0, 16),
		ZIndex = 26,
	})
	local total = Kit.label(frame, "+0", {
		Font = Theme.Font.display,
		TextSize = 40,
		TextColor3 = Theme.Color.ember,
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, 46),
		ZIndex = 26,
	})
	total.Name = "Total"
	local detail = Kit.label(frame, "", {
		Font = Theme.Font.body,
		TextSize = 13,
		TextColor3 = Theme.Color.textDim,
		Position = UDim2.fromOffset(0, 68),
		Size = UDim2.new(1, 0, 0, 60),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 26,
	})
	detail.Name = "Detail"
	frame.Visible = false
	self.payout = frame
end

--------------------------------------------------------------------------------
-- behaviour
--------------------------------------------------------------------------------

function Hud.resize(self: Hud)
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
		or Vector2.new(1280, 720)
	local scaleValue = math.clamp(viewport.Y / 860, 0.72, 1.18)
	self.scale.Scale = scaleValue
	local narrow = viewport.X < 760
	self.profile.Visible = not narrow
	self.lanternPanel.Size = if narrow
		then UDim2.fromOffset(268, 112)
		else UDim2.fromOffset(300, 118)
end

function Hud.toast(self: Hud, text: string, tone: string?)
	local color = if tone == "good"
		then Theme.Color.good
		elseif tone == "bad" then Theme.Color.bad
		elseif tone == "warn" then Theme.Color.amber
		else Theme.Color.cyan

	local pill = Kit.frame(self.toasts, {
		Size = UDim2.fromOffset(math.clamp(#text * 8 + 40, 160, 400), 34),
		BackgroundTransparency = 0.12,
		BackgroundColor3 = Theme.Color.ink,
	})
	corner(pill, UDim.new(1, 0))
	Kit.stroke(pill, color, 1, 0.35)
	local label = Kit.label(pill, text, {
		Font = Theme.Font.body,
		TextSize = 14,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
	})
	label.ZIndex = 22

	-- Beat the reference so a burst of toasts does not stack on one another.
	task.wait(0.05)
	Kit.tween(pill, { BackgroundTransparency = 0.02 })
	task.delay(Config.Ui.ToastDuration, function()
		Kit.tween(pill, { BackgroundTransparency = 1 })
		Kit.tween(label, { TextTransparency = 1 })
		task.wait(Theme.Motion.base + 0.05)
		pill:Destroy()
	end)
end

function Hud.banner(self: Hud, text: string, color: Color3?)
	local label = self.bannerLabel
	label.Text = text
	label.TextColor3 = color or Theme.Color.text
	label.TextTransparency = 1
	label.Position = UDim2.fromScale(0.5, 0.35)
	Kit.tween(label, { TextTransparency = 0 }, Theme.Motion.base)
	Kit.tween(label, { Position = UDim2.fromScale(0.5, 0.33) }, 0.6)
	task.delay(2.4, function()
		Kit.tween(label, { TextTransparency = 1 }, 0.6)
	end)
end

function Hud.flashDamage(self: Hud, strength: number)
	self.damageFlash.BackgroundTransparency = 1 - math.clamp(strength, 0.05, 0.32)
	Kit.tween(self.damageFlash, { BackgroundTransparency = 1 }, 0.45)
end

function Hud.showPayout(self: Hud, payload: any)
	local total = self.payout:FindFirstChild("Total") :: TextLabel?
	local detail = self.payout:FindFirstChild("Detail") :: TextLabel?
	if not (total and detail) then
		return
	end
	total.Text = `+{payload.total}`
	local lines = {
		`embers carried  ×{payload.banked}`,
		`beacons relit  ×{payload.beaconsLit}`,
	}
	if payload.completionBonus and payload.completionBonus > 0 then
		table.insert(lines, `all beacons  +{payload.completionBonus}`)
	end
	if payload.multiplier and payload.multiplier ~= 1 then
		table.insert(lines, string.format("multiplier  %.2f×", payload.multiplier))
	end
	detail.Text = table.concat(lines, "   ·   ")

	self.payout.Visible = true
	self.payout.Size = UDim2.fromOffset(320, 180)
	Kit.tween(self.payout, { Size = UDim2.fromOffset(340, 200) }, Theme.Motion.base)
	task.delay(4.5, function()
		Kit.tween(self.payout, { BackgroundTransparency = 1 }, 0.5)
		local t = self.payout:FindFirstChild("Total")
		if t and t:IsA("TextLabel") then
			Kit.tween(t, { TextTransparency = 1 }, 0.4)
		end
		task.wait(0.55)
		self.payout.Visible = false
		self.payout.BackgroundTransparency = 0.06
		if t and t:IsA("TextLabel") then
			t.TextTransparency = 0
		end
	end)
end

local function lerpColor(from: Color3, to: Color3, alpha: number): Color3
	return from:Lerp(to, math.clamp(alpha, 0, 1))
end

--[[ Refreshes every value from client state. Called on change and on a slow tick. ]]
function Hud.update(self: Hud, state: any, cooldowns: { [string]: number }, sprinting: boolean)
	local inDive = state.phase == "dive" and state.inDive
	self.runBar.Visible = inDive
	self.crosshair.Visible = inDive
	self.mobileBar.Visible = UserInputService.TouchEnabled and inDive

	local ratio = if state.capacity > 0 then math.clamp(state.light / state.capacity, 0, 1) else 0
	self.lightBar.fill.Size = UDim2.fromScale(ratio, 1)
	self.lightValue.Text = `{math.floor(ratio * 100 + 0.5)}%`

	local low = ratio < 0.3
	local danger = Color3.fromRGB(255, 107, 127)
	local target = if low then danger else Theme.Color.amber
	self.lightBar.gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, lerpColor(Theme.Color.amberDeep, target, 0.6)),
		ColorSequenceKeypoint.new(1, if low then danger else Theme.Color.mint),
	})
	self.lightValue.TextColor3 = target
	self.lightHint.Text = if low then "light failing" else "light is life · light is sight"
	self.lightHint.TextColor3 = if low then danger else Theme.Color.textDim

	local now = os.clock()
	local pulseRemaining = math.max(0, (cooldowns.pulse or 0) - now) / Config.Light.PulseCooldown
	local flareRemaining = math.max(0, (cooldowns.flare or 0) - now) / Config.Light.FlareCooldown
	self.pulseChip.fill.Size = UDim2.fromScale(pulseRemaining, 1)
	self.flareChip.fill.Size = UDim2.fromScale(flareRemaining, 1)
	self.pulseChip.label.TextTransparency = if pulseRemaining > 0 then 0.5 else 0
	self.flareChip.label.TextTransparency = if flareRemaining > 0 then 0.5 else 0
	local pulseAffordable = ratio * state.capacity >= Config.Light.PulseCost + 5
	local flareAffordable = ratio * state.capacity >= Config.Light.FlareCost + 5
	self.pulseChip.stroke.Transparency = if pulseAffordable then 0.35 else 0.75
	self.flareChip.stroke.Transparency = if flareAffordable then 0.35 else 0.75

	if state.run then
		self.timer.Text = LightMath.formatClock(state.run.timeLeft)
		self.timer.TextColor3 = if state.run.timeLeft < 45
			then Theme.Color.bad
			else Theme.Color.text
		self.carried.Text = `◆ {state.run.carried}`
		for _, beacon in state.run.beacons do
			local pip = self.pips[beacon.id]
			if pip then
				pip.fill.Size = UDim2.fromScale(1, math.clamp(beacon.progress, 0, 1))
				if beacon.lit then
					pip.fill.BackgroundColor3 = Theme.Color.mint
					pip.fill.BackgroundTransparency = 0.1
					pip.glyph.TextColor3 = Theme.Color.ink
					pip.stroke.Color = Theme.Color.mint
					pip.stroke.Transparency = 0.15
				else
					pip.fill.BackgroundColor3 = Theme.Color.cyan
					pip.fill.BackgroundTransparency = 0.45
					pip.glyph.TextColor3 = Theme.Color.textDim
					pip.stroke.Color = Theme.Color.strokeDim
					pip.stroke.Transparency = 0.6
				end
			end
		end
	end

	if state.save then
		self.rankLabel.Text = string.upper(state.rank or "Unlit")
		self.emberLabel.Text = `◆ {state.save.embers} embers`
	end

	local hintLabel = self.profile:FindFirstChild("Hint")
	if hintLabel and hintLabel:IsA("TextLabel") then
		hintLabel.Text = if inDive then "the reef remembers" else "E · The Ledger"
	end

	self.footer.Text = if inDive
		then (if state.run and state.run.complete
			then "Gate open · reach the return gate and press E"
			else "Relight the three beacons · [Q] pulse · [F] flare")
		else "Walk to the Dive Gate · press E to descend"
	self.footer.TextColor3 = if inDive
			and state.run
			and state.run.complete
		then Theme.Color.mint
		else Theme.Color.textDim

	if self.sprintButton then
		self.sprintButton.TextColor3 = if sprinting then Theme.Color.mint else Theme.Color.textDim
	end
end

function Hud.setPhase(self: Hud, phase: string)
	if self.visiblePhase == phase then
		return
	end
	self.visiblePhase = phase
	local inDive = phase == "dive"
	self.mobileBar.Visible = inDive and UserInputService.TouchEnabled
end

return Hud
