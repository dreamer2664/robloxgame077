local T = require("../support/TinyTest")
local RateLimiter = require("../shared/RateLimiter")

T.suite("RateLimiter")

T.case("burst then deny", function()
	local bucket = RateLimiter.new(1, 3, 0)
	T.ok(RateLimiter.consume(bucket, 0), "first token")
	T.ok(RateLimiter.consume(bucket, 0), "second token")
	T.ok(RateLimiter.consume(bucket, 0), "third token")
	local allowed = RateLimiter.consume(bucket, 0)
	T.equal(allowed, false, "fourth request in the same instant is denied")
end)

T.case("refills over time", function()
	local bucket = RateLimiter.new(2, 2, 0)
	RateLimiter.consume(bucket, 0)
	RateLimiter.consume(bucket, 0)
	T.equal(RateLimiter.consume(bucket, 0.2), false, "not enough time elapsed")
	T.ok(RateLimiter.consume(bucket, 0.5), "one token after 0.5s at 2/s")
end)

T.case("never exceeds burst", function()
	local bucket = RateLimiter.new(10, 2, 0)
	RateLimiter.consume(bucket, 1000)
	local second = RateLimiter.consume(bucket, 1000)
	T.ok(second, "bucket still holds burst-worth of tokens after idle")
end)

T.case("clock going backwards is handled", function()
	local bucket = RateLimiter.new(1, 1, 10)
	local allowed = RateLimiter.consume(bucket, 5)
	T.equal(allowed, false, "denies on backwards clock instead of granting tokens")
end)

T.case("window limiter", function()
	local over = RateLimiter.exceedsWindow(5, 0, 5, 5, 10)
	T.equal(over, true, "flags over-budget window")
	local ok, start = RateLimiter.exceedsWindow(5, 0, 11, 5, 10)
	T.equal(ok, false, "resets once the window expires")
	T.equal(start, 11, "new window starts now")
end)

return true
