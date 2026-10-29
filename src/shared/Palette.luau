--!strict
--[[
	ECHOWAKE — art direction.
	A single source of truth for colour so the world builder, VFX and UI stay cohesive.
	Authored as hex strings (pure data) and converted to Color3 where needed.
]]

local Palette = {}

Palette.Hex = {
	-- Environment
	Abyss = "#03060C",
	Water = "#061420",
	Stone = "#0E1622",
	StoneAlt = "#141F2D",
	StoneLit = "#1B2C3C",
	CoralBone = "#6E7F91",
	CoralBoneDim = "#3B4A59",
	Rust = "#2A1C18",

	-- Bioluminescence
	Cyan = "#4BE3D2",
	CyanDeep = "#12796F",
	Teal = "#1FB6C4",
	Mint = "#9BF6D8",

	-- Lantern / player
	Amber = "#FFB25E",
	AmberDeep = "#8A4A17",
	Ember = "#FFD37A",

	-- Threat
	Gloam = "#FF4D6D",
	GloamDeep = "#7A1030",
	GloamCore = "#FFB0C0",

	-- UI
	Ink = "#04101A",
	InkSoft = "#081A26",
	Stroke = "#2FD8C8",
	Text = "#DCEEF5",
	TextDim = "#7E96A6",
	Good = "#6EF0A0",
	Bad = "#FF6B7F",
	Gold = "#FFD37A",
}

-- Region accent colours: each reef sector gets a signature hue so the player can
-- navigate by colour alone (readability on a dark map).
Palette.Sector = {
	Nave = "#4BE3D2",
	Aisle = "#7FB2FF",
	Trench = "#C08BFF",
}

Palette.GloamByKind = {
	Drifter = "#FF4D6D",
	Lunger = "#FF8A5C",
	Siphon = "#C08BFF",
}

--[[ "#RRGGBB" -> 0..1 rgb triple. Falls back to magenta so a typo is loud, not silent. ]]
function Palette.parse(hex: string): (number, number, number)
	local clean = string.gsub(hex, "#", "")
	local r = tonumber(string.sub(clean, 1, 2), 16)
	local g = tonumber(string.sub(clean, 3, 4), 16)
	local b = tonumber(string.sub(clean, 5, 6), 16)
	if not (r and g and b) then
		return 1, 0, 1
	end
	return r / 255, g / 255, b / 255
end

return Palette
