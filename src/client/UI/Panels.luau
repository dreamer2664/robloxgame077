--!strict
--[[
	The Ledger (upgrades + lantern hues), the Codex (bestiary) and the board.

	One modal, three tabs, opened by walking up to the props in the hub or by the
	HUD hint. Purchases are only ever *requests* - the server prices and applies
	them, and the refreshed save comes back as a signal.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Codex = require(Shared.Codex)
local Net = require(Shared.Net)
local Progression = require(Shared.Progression)

local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)
local ClientNet = require(script.Parent.Parent.Controllers.ClientNet)

local Panels = {}
Panels.__index = Panels

type Tab = "ledger" | "codex" | "board"

export type Panels = typeof(setmetatable(
	{} :: {
		gui: ScreenGui,
		root: Frame,
		scrim: Frame,
		card: Frame,
		title: TextLabel,
		subtitle: TextLabel,
		tabButtons: { [string]: TextButton },
		content: ScrollingFrame,
		open: boolean,
		activeTab: Tab,
		save: any,
		stats: any,
		rank: string,
		board: { any },
		onOpenChanged: ((open: boolean) -> ())?,
	},
	Panels
))

local CONTENT_WIDTH = 600

function Panels.new(parent: Instance): Panels
	local gui = Instance.new("ScreenGui")
	gui.Name = "EchowakePanels"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Enabled = false
	gui.Parent = parent

	local root = Kit.frame(gui, {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	local scale = Instance.new("UIScale")
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
		or Vector2.new(1280, 720)
	scale.Scale = math.clamp(viewport.Y / 860, 0.62, 1.1)
	scale.Parent = root

	local scrim = Kit.frame(root, {
		Name = "Scrim",
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
	})
	scrim.Active = true

	local card = Kit.frame(root, {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CONTENT_WIDTH + 48, 486),
		BackgroundTransparency = 0.04,
	})
	Kit.corner(card, UDim.new(0, 20))
	Kit.stroke(card, Theme.Color.stroke, 1.5, 0.55)
	Kit.padding(card, 24, 20)

	local title = Kit.label(card, "THE LEDGER", {
		Font = Theme.Font.display,
		TextSize = 24,
		Size = UDim2.fromOffset(320, 30),
	})
	local subtitle = Kit.label(card, "", {
		Font = Theme.Font.body,
		TextSize = 13,
		TextColor3 = Theme.Color.textDim,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 18),
	})

	local close = Kit.button(card, "CLOSE", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(78, 30),
		TextSize = 12,
		Font = Theme.Font.heading,
	})

	local tabs = Kit.frame(card, {
		Name = "Tabs",
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
	})
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.Parent = tabs

	local tabButtons: { [string]: TextButton } = {}
	local index = 0
	for _, entry in
		{
			{ id = "ledger", text = "UPGRADES" },
			{ id = "codex", text = "CODEX" },
			{ id = "board", text = "LEDGER BOARD" },
		}
	do
		index += 1
		local button = Kit.button(tabs, entry.text, {
			Size = UDim2.fromOffset(150, 34),
			LayoutOrder = index,
			TextSize = 12,
			BackgroundTransparency = 0.2,
		})
		tabButtons[entry.id] = button
	end

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Position = UDim2.fromOffset(0, 102)
	content.Size = UDim2.new(1, 0, 1, -102)
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = 4
	content.ScrollBarImageColor3 = Theme.Color.stroke
	content.ScrollBarImageTransparency = 0.5
	content.Parent = card
	local contentLayout = Instance.new("UIListLayout")
	contentLayout.Padding = UDim.new(0, 8)
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Parent = content

	local self = setmetatable({
		gui = gui,
		root = root,
		scrim = scrim,
		card = card,
		title = title,
		subtitle = subtitle,
		tabButtons = tabButtons,
		content = content,
		open = false,
		activeTab = "ledger" :: Tab,
		save = nil,
		stats = nil,
		rank = "Unlit",
		board = {},
	}, Panels)

	close.Activated:Connect(function()
		self:close()
	end)
	scrim.InputBegan:Connect(function()
		self:close()
	end)
	for id, button in tabButtons do
		button.Activated:Connect(function()
			self:setTab(id :: Tab)
		end)
	end

	return self
end

function Panels.setData(self: Panels, payload: any)
	if payload.save then
		self.save = payload.save
	end
	if payload.stats then
		self.stats = payload.stats
	end
	if payload.rank then
		self.rank = payload.rank
	end
	if self.open then
		self:render()
	end
end

function Panels.setBoard(self: Panels, entries: { any })
	self.board = entries or {}
	if self.open and self.activeTab == "board" then
		self:render()
	end
end

function Panels.toggle(self: Panels, tab: Tab?)
	if self.open then
		self:close()
		return
	end
	self:openWith(tab or "ledger")
end

function Panels.openWith(self: Panels, tab: Tab)
	self.open = true
	self.gui.Enabled = true
	self.activeTab = tab
	if tab == "board" then
		task.spawn(function()
			local entries = ClientNet.query(Net.Query.Ledger)
			if type(entries) == "table" then
				self:setBoard(entries)
			end
		end)
	end
	self:render()

	self.card.Size = UDim2.fromOffset(CONTENT_WIDTH + 40, 470)
	Kit.tween(self.card, { Size = UDim2.fromOffset(CONTENT_WIDTH + 48, 486) }, Theme.Motion.base)
	self.scrim.BackgroundTransparency = 1
	Kit.tween(self.scrim, { BackgroundTransparency = 0.35 }, Theme.Motion.base)

	if self.onOpenChanged then
		self.onOpenChanged(true)
	end
end

function Panels.close(self: Panels)
	if not self.open then
		return
	end
	self.open = false
	Kit.tween(self.scrim, { BackgroundTransparency = 1 }, Theme.Motion.fast)
	task.delay(Theme.Motion.fast, function()
		if not self.open then
			self.gui.Enabled = false
		end
	end)
	if self.onOpenChanged then
		self.onOpenChanged(false)
	end
end

function Panels.setTab(self: Panels, tab: Tab)
	self.activeTab = tab
	if tab == "board" then
		task.spawn(function()
			local entries = ClientNet.query(Net.Query.Ledger)
			if type(entries) == "table" then
				self:setBoard(entries)
			end
		end)
	end
	self:render()
end

local function clear(frame: Instance)
	for _, child in frame:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function row(parent: Instance, order: number, height: number): Frame
	local frame = Kit.frame(parent, {
		Size = UDim2.new(1, -8, 0, height),
		BackgroundTransparency = 0.24,
		BackgroundColor3 = Theme.Color.inkSoft,
		LayoutOrder = order,
	})
	Kit.corner(frame, UDim.new(0, 12))
	Kit.padding(frame, 14, 10)
	return frame
end

function Panels.renderLedger(self: Panels)
	local save = self.save
	if not save then
		return
	end
	local order = 0
	for _, def in Progression.UPGRADES do
		order += 1
		local level = Progression.level(save, def.id)
		local price = Progression.cost(def.id, level)
		local maxed = level >= def.maxLevel
		local affordable = save.embers >= price

		local card = row(self.content, order, 70)
		local accent = Theme.hex(def.accent)

		local name = Kit.label(card, string.upper(def.title), {
			Font = Theme.Font.heading,
			TextSize = 15,
			Size = UDim2.fromOffset(300, 18),
		})
		name.TextColor3 = accent

		Kit.label(card, def.blurb, {
			Font = Theme.Font.body,
			TextSize = 12,
			TextColor3 = Theme.Color.textDim,
			Position = UDim2.fromOffset(0, 20),
			Size = UDim2.new(1, -150, 0, 30),
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
		})

		Kit.label(card, def.format(level), {
			Font = Theme.Font.mono,
			TextSize = 12,
			TextColor3 = accent,
			Position = UDim2.fromOffset(0, 50),
			Size = UDim2.new(1, -150, 0, 14),
		})

		-- level pips
		local pips = Kit.frame(card, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -110, 0, 4),
			Size = UDim2.fromOffset(math.min(def.maxLevel, 8) * 12, 10),
			BackgroundTransparency = 1,
		})
		for pip = 1, math.min(def.maxLevel, 8) do
			local dot = Kit.frame(pips, {
				Position = UDim2.fromOffset((pip - 1) * 12, 0),
				Size = UDim2.fromOffset(7, 7),
				BackgroundColor3 = if pip <= level then accent else Theme.Color.strokeDim,
				BackgroundTransparency = if pip <= level then 0 else 0.55,
			})
			Kit.corner(dot, UDim.new(1, 0))
		end

		local buy = Kit.button(card, if maxed then "MASTERED" else `◆ {price}`, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(104, 34),
			TextSize = 13,
			BackgroundTransparency = if affordable and not maxed then 0.05 else 0.35,
			TextColor3 = if maxed
				then Theme.Color.textDim
				elseif affordable then Theme.Color.ember
				else Theme.Color.textDim,
		})
		if not maxed and affordable then
			buy.Activated:Connect(function()
				ClientNet.fire(Net.Intent.Upgrade, { id = def.id })
			end)
		end
	end

	-- Lantern hues
	order += 1
	local hueCard = row(self.content, order, 74)
	Kit.label(hueCard, "LANTERN HUE", {
		Font = Theme.Font.heading,
		TextSize = 14,
		Size = UDim2.fromOffset(300, 18),
		TextColor3 = Theme.Color.text,
	})
	Kit.label(hueCard, "How your lantern reads in the dark - and to other Lamplighters.", {
		Font = Theme.Font.body,
		TextSize = 12,
		TextColor3 = Theme.Color.textDim,
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 16),
	})
	local hues = {
		{ id = "amber", color = Color3.fromRGB(255, 178, 94) },
		{ id = "mint", color = Color3.fromRGB(155, 246, 216) },
		{ id = "violet", color = Color3.fromRGB(192, 139, 255) },
		{ id = "crimson", color = Color3.fromRGB(255, 107, 127) },
		{ id = "ice", color = Color3.fromRGB(127, 178, 255) },
	}
	for index, hue in hues do
		local swatch = Kit.button(hueCard, "", {
			Position = UDim2.fromOffset((index - 1) * 46, 42),
			Size = UDim2.fromOffset(38, 22),
			BackgroundColor3 = hue.color,
			BackgroundTransparency = if save.lanternHue == hue.id then 0 else 0.45,
			Text = "",
		})
		Kit.corner(swatch, UDim.new(0, 6))
		swatch.Activated:Connect(function()
			ClientNet.fire(Net.Intent.Hue, { id = hue.id })
		end)
	end
end

function Panels.renderCodex(self: Panels)
	local save = self.save
	local order = 0
	for _, archetype in Codex.ARCHETYPES do
		order += 1
		local found = save and save.codex and save.codex[archetype.id] == true
		local card = row(self.content, order, 92)
		local accent = Theme.hex(archetype.color)

		local nameLabel =
			Kit.label(card, string.upper(if found then archetype.title else "UNRECORDED"), {
				Font = Theme.Font.heading,
				TextSize = 15,
				Size = UDim2.fromOffset(300, 18),
			})
		nameLabel.TextColor3 = if found then accent else Theme.Color.textDim

		Kit.label(card, if found then archetype.lore else "Sound a pulse near one to record it.", {
			Font = Theme.Font.body,
			TextSize = 12,
			TextColor3 = Theme.Color.textDim,
			Position = UDim2.fromOffset(0, 20),
			Size = UDim2.new(1, 0, 0, 34),
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
		})

		Kit.label(card, if found then archetype.tell else "", {
			Font = Theme.Font.mono,
			TextSize = 11,
			TextColor3 = if found then accent else Theme.Color.textDim,
			Position = UDim2.fromOffset(0, 56),
			Size = UDim2.new(1, 0, 0, 26),
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
	end
end

function Panels.renderBoard(self: Panels)
	local order = 0
	if #self.board == 0 then
		local card = row(self.content, 1, 64)
		Kit.label(card, "The board is quiet. Surface with embers to be remembered.", {
			Font = Theme.Font.body,
			TextSize = 13,
			TextColor3 = Theme.Color.textDim,
			Size = UDim2.new(1, 0, 0, 44),
			TextWrapped = true,
		})
		return
	end
	for _, entry in self.board do
		order += 1
		local card = row(self.content, order, 40)
		Kit.label(card, `{entry.rank}`, {
			Font = Theme.Font.mono,
			TextSize = 14,
			TextColor3 = if entry.rank <= 3 then Theme.Color.gold else Theme.Color.textDim,
			Size = UDim2.fromOffset(36, 20),
		})
		Kit.label(card, entry.name, {
			Font = Theme.Font.body,
			TextSize = 14,
			Position = UDim2.fromOffset(40, 0),
			Size = UDim2.new(1, -160, 0, 20),
			TextColor3 = if entry.isLocal then Theme.Color.mint else Theme.Color.text,
		})
		Kit.label(card, `◆ {entry.score}`, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Font = Theme.Font.mono,
			TextSize = 14,
			TextColor3 = Theme.Color.ember,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.fromOffset(140, 20),
		})
	end
end

function Panels.render(self: Panels)
	clear(self.content)
	for _, button in self.tabButtons do
		Kit.tween(
			button,
			{ BackgroundTransparency = 0.28, TextColor3 = Theme.Color.textDim },
			Theme.Motion.fast
		)
	end
	local activeButton = self.tabButtons[self.activeTab]
	if activeButton then
		Kit.tween(
			activeButton,
			{ BackgroundTransparency = 0.02, TextColor3 = Theme.Color.stroke },
			Theme.Motion.fast
		)
	end

	local embers = if self.save then self.save.embers else 0
	if self.activeTab == "ledger" then
		self.title.Text = "THE LEDGER"
		self.subtitle.Text = `◆ {embers} embers · rank {self.rank}`
		self:renderLedger()
	elseif self.activeTab == "codex" then
		self.title.Text = "THE CODEX"
		self.subtitle.Text = "Everything the reef has shown you."
		self:renderCodex()
	else
		self.title.Text = "LEDGER BOARD"
		self.subtitle.Text = "Lifetime embers, all Lamplighters."
		self:renderBoard()
	end
end

return Panels
