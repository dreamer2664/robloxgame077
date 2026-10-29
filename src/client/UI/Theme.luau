--!strict
--[[ ECHOWAKE UI theme: one palette, one type scale, one motion language. ]]

local Palette = require(game:GetService("ReplicatedStorage").Shared.Palette)

local Theme = {}

Theme.Color = {
	ink = Color3.fromRGB(4, 12, 20),
	inkSoft = Color3.fromRGB(8, 24, 34),
	panel = Color3.fromRGB(6, 17, 26),
	panelSolid = Color3.fromRGB(5, 13, 20),
	stroke = Color3.fromRGB(47, 216, 200),
	strokeDim = Color3.fromRGB(22, 96, 96),
	text = Color3.fromRGB(220, 238, 245),
	textDim = Color3.fromRGB(126, 150, 166),
	amber = Color3.fromRGB(255, 178, 94),
	amberDeep = Color3.fromRGB(138, 74, 23),
	ember = Color3.fromRGB(255, 211, 122),
	cyan = Color3.fromRGB(75, 227, 210),
	mint = Color3.fromRGB(155, 246, 216),
	bad = Color3.fromRGB(255, 107, 127),
	good = Color3.fromRGB(110, 240, 160),
	gold = Color3.fromRGB(255, 211, 122),
	shadow = Color3.fromRGB(0, 0, 0),
}

Theme.Font = {
	display = Enum.Font.GothamBlack,
	heading = Enum.Font.GothamBold,
	body = Enum.Font.Gotham,
	mono = Enum.Font.Code,
}

Theme.Radius = {
	panel = UDim.new(0, 14),
	chip = UDim.new(0, 10),
	pill = UDim.new(1, 0),
}

Theme.Transparency = {
	panel = 0.08,
	scrim = 0.35,
}

Theme.Motion = {
	fast = 0.14,
	base = 0.24,
	slow = 0.42,
	ease = Enum.EasingStyle.Quint,
	out = Enum.EasingDirection.Out,
}

function Theme.hex(value: string): Color3
	local r, g, b = Palette.parse(value)
	return Color3.fromRGB(
		math.floor(r * 255 + 0.5),
		math.floor(g * 255 + 0.5),
		math.floor(b * 255 + 0.5)
	)
end

return Theme
