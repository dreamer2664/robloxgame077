--[[
	Minimal Roblox value types for running game logic outside of Roblox.
	Only what the pure shared modules touch is implemented, with the same
	semantics as the real classes (including unit-vector errors on zero length).
]]

local Vector3 = {}
Vector3.__index = Vector3

local function new(x: number, y: number, z: number)
	return setmetatable({ X = x, Y = y, Z = z }, Vector3)
end

Vector3.new = new

function Vector3.__add(a, b)
	return new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end

function Vector3.__sub(a, b)
	return new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end

function Vector3.__mul(a, b)
	if type(a) == "number" then
		return new(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return new(a.X * b, a.Y * b, a.Z * b)
	end
	return new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end

function Vector3.__div(a, b)
	return new(a.X / b, a.Y / b, a.Z / b)
end

function Vector3.__unm(a)
	return new(-a.X, -a.Y, -a.Z)
end

function Vector3.__eq(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end

function Vector3.__tostring(a)
	return string.format("%.2f, %.2f, %.2f", a.X, a.Y, a.Z)
end

function Vector3.__index(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif key == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		if m == 0 then
			error("Vector3 unit vector is zero length")
		end
		return new(self.X / m, self.Y / m, self.Z / m)
	end
	return Vector3[key]
end

function Vector3:Dot(other)
	return self.X * other.X + self.Y * other.Y + self.Z * other.Z
end

function Vector3:Cross(other)
	return new(
		self.Y * other.Z - self.Z * other.Y,
		self.Z * other.X - self.X * other.Z,
		self.X * other.Y - self.Y * other.X
	)
end

function Vector3:Lerp(other, alpha)
	return new(
		self.X + (other.X - self.X) * alpha,
		self.Y + (other.Y - self.Y) * alpha,
		self.Z + (other.Z - self.Z) * alpha
	)
end

local Color3 = {}
Color3.__index = Color3

function Color3.new(r: number, g: number, b: number)
	return setmetatable({ R = r, G = g, B = b }, Color3)
end

-- The Luau CLI sandboxes each module, so globals cannot be shared: the test
-- build injects `local Vector3 = require("./__Stubs").Vector3` at the top of any
-- shared module that references one of these types.
return { Vector3 = Vector3, Color3 = Color3 }
