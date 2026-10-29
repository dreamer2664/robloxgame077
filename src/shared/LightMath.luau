--!strict
--[[
	Lantern economy and cone/radius geometry.
	Pure maths shared by the authoritative server and the client HUD preview.
]]

local Config = require(script.Parent.Config)

local LightMath = {}

export type FlareHit = {
	index: number,
	position: Vector3,
	distance: number,
	damage: number,
}

LightMath.FLARE_WHITELIST_KEYS = { "aim" } :: { string }

--[[ Linear-ish falloff that stays useful at the rim of the torch. ]]
function LightMath.falloff(distance: number, radius: number): number
	if radius <= 0 then
		return 0
	end
	local t = math.clamp(distance / radius, 0, 1)
	local smooth = 1 - t * t
	return math.max(0, smooth * smooth)
end

--[[ True when `offset` (target - origin) sits inside a cone. ]]
function LightMath.inCone(
	offset: Vector3,
	forward: Vector3,
	range: number,
	halfAngleDeg: number
): boolean
	local distance = offset.Magnitude
	if distance > range or distance <= 0.001 then
		return distance <= range
	end
	local cosAngle = offset.Unit:Dot(forward.Unit)
	local threshold = math.cos(math.rad(halfAngleDeg))
	return cosAngle >= threshold
end

--[[ Returns the indices of targets inside the flare cone, with damage scaled by distance. ]]
function LightMath.flareTargets(
	origin: Vector3,
	forward: Vector3,
	targets: { Vector3 },
	range: number,
	halfAngleDeg: number,
	baseDamage: number
): { FlareHit }
	local hits: { FlareHit } = {}
	for index, position in targets do
		local offset = position - origin
		if LightMath.inCone(offset, forward, range, halfAngleDeg) then
			local distance = offset.Magnitude
			local scale = 1 - 0.35 * math.clamp(distance / range, 0, 1)
			table.insert(hits, {
				index = index,
				position = position,
				distance = distance,
				damage = math.floor(baseDamage * scale + 0.5),
			})
		end
	end
	return hits
end

--[[
	Applies a light spend. Returns success plus the new value; a spend that would
	empty the lantern below the reserve is rejected so the player always keeps a
	thread of light (and the game never soft-locks in pitch darkness).
]]
function LightMath.spend(current: number, cost: number, floor: number): (boolean, number)
	if current - cost < floor then
		return false, current
	end
	return true, current - cost
end

function LightMath.regen(
	current: number,
	capacity: number,
	rate: number,
	multiplier: number,
	dt: number
): number
	return math.min(capacity, current + rate * multiplier * dt)
end

--[[
	Reward maths for a finished dive. Kept pure so payouts are auditable and
	cannot be inflated by a client.
]]
export type PayoutInput = {
	carriedEmbers: number,
	beaconsLit: number,
	beaconCount: number,
	completed: boolean,
	died: boolean,
	escaped: boolean,
}

export type Payout = {
	banked: number,
	beaconBonus: number,
	completionBonus: number,
	multiplier: number,
	total: number,
}

function LightMath.payout(input: PayoutInput): Payout
	local carried = math.max(0, math.floor(input.carriedEmbers))
	local beaconBonus = math.max(0, math.min(input.beaconsLit, input.beaconCount))
		* Config.Dive.BeaconPayout
	local completionBonus = if input.completed then Config.Dive.CompletionBonus else 0
	local multiplier = 1
	if input.died then
		multiplier = Config.Dive.DeathPayoutMultiplier
	elseif input.escaped then
		multiplier = Config.Dive.EscapePayoutMultiplier
	end
	local subtotal = carried + beaconBonus + completionBonus
	local total = math.floor(subtotal * multiplier + 0.5)
	return {
		banked = carried,
		beaconBonus = beaconBonus,
		completionBonus = completionBonus,
		multiplier = multiplier,
		total = total,
	}
end

--[[ Formats seconds as m:ss for HUD readability. ]]
function LightMath.formatClock(seconds: number): string
	local clamped = math.max(0, math.ceil(seconds))
	local minutes = math.floor(clamped / 60)
	return string.format("%d:%02d", minutes, clamped % 60)
end

return LightMath
