--!strict
--[[
	Token-bucket rate limiter. Pure: callers own the bucket table, which makes the
	behaviour fully unit testable with a fake clock.
]]

export type Bucket = {
	tokens: number,
	rate: number,
	burst: number,
	updatedAt: number,
}

local RateLimiter = {}

function RateLimiter.new(ratePerSecond: number, burst: number, now: number?): Bucket
	local t = now or 0
	return { tokens = burst, rate = ratePerSecond, burst = burst, updatedAt = t }
end

--[[ Refills the bucket according to elapsed time and consumes one token if available. ]]
function RateLimiter.consume(bucket: Bucket, now: number): (boolean, number)
	if now < bucket.updatedAt then
		-- Clock went backwards (or a fake clock reset); resynchronise defensively.
		bucket.updatedAt = now
		return false, bucket.tokens
	end
	local elapsed = now - bucket.updatedAt
	bucket.updatedAt = now
	bucket.tokens = math.min(bucket.burst, bucket.tokens + elapsed * bucket.rate)
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true, bucket.tokens
	end
	return false, bucket.tokens
end

--[[ Registers a hit against a fixed window. Returns true when the caller is over budget. ]]
function RateLimiter.exceedsWindow(
	count: number,
	windowStart: number,
	now: number,
	maxPerWindow: number,
	windowSeconds: number
): (boolean, number)
	if now - windowStart >= windowSeconds then
		return false, now
	end
	return count >= maxPerWindow, windowStart
end

return RateLimiter
