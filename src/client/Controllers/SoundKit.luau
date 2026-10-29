--!strict
--[[
	Sound hooks.

	ECHOWAKE ships with no third-party audio: every id below is intentionally
	empty until a verified Creator Store sound is chosen (see ASSETS.md for the
	search terms and the review checklist). Playback no-ops on empty ids, so the
	game is fully playable and nothing silently depends on a missing asset.

	To wire audio: drop a verified asset id string ("rbxasset" + "id://<number>")
	into this table after reviewing it against the checklist in ASSETS.md.
]]

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local ContentProvider = game:GetService("ContentProvider")

local SoundKit = {}

SoundKit.IDS = {
	pulse = "",
	flare = "",
	beaconLit = "",
	shard = "",
	hit = "",
	diveStart = "",
	bank = "",
	uiClick = "",
} :: { [string]: string }

SoundKit.Volumes = {
	pulse = 0.55,
	flare = 0.5,
	beaconLit = 0.7,
	shard = 0.4,
	hit = 0.6,
	diveStart = 0.6,
	bank = 0.6,
	uiClick = 0.25,
} :: { [string]: number }

SoundKit.ENABLED = true

function SoundKit.play(key: string, parent: Instance?, pitch: number?): Sound?
	local id = SoundKit.IDS[key]
	if not SoundKit.ENABLED or id == nil or id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = SoundKit.Volumes[key] or 0.5
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = parent or SoundService
	sound:Play()
	Debris:AddItem(sound, 6)
	return sound
end

--[[ Preloads configured ids so the first pulse is not a buffer stall. ]]
function SoundKit.preload()
	local assets: { string } = {}
	for _, id in SoundKit.IDS do
		if id ~= "" then
			table.insert(assets, id)
		end
	end
	if #assets == 0 then
		return
	end
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(assets)
	end)
	if not ok then
		warn(`[ECHOWAKE] sound preload failed: {err}`)
	end
end

return SoundKit
