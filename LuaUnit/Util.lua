--!strict
-- Shared helpers: pretty printing, deep equality, XML escaping.

local Util = {}

local function sortedKeys(t: { [any]: any }): { any }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return keys
end

function Util.pretty(value: any, depth: number?): string
	local d = depth or 0
	local kind = typeof(value)
	if kind == "string" then
		return string.format("%q", value)
	elseif kind == "Instance" then
		return value:GetFullName() .. " (" .. value.ClassName .. ")"
	elseif kind == "table" then
		if d > 3 then
			return "{...}"
		end
		local parts = {}
		for _, k in sortedKeys(value) do
			table.insert(parts, "[" .. Util.pretty(k, d + 1) .. "] = " .. Util.pretty(value[k], d + 1))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return kind .. "(" .. tostring(value) .. ")"
end

function Util.deepEqual(a: any, b: any, seen: { [any]: any }?): boolean
	if a == b then
		return true
	end
	if typeof(a) ~= "table" or typeof(b) ~= "table" then
		return false
	end
	local visited = seen or {}
	if visited[a] == b then
		return true
	end
	visited[a] = b
	for k, v in a do
		if not Util.deepEqual(v, b[k], visited) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

-- Approximate equality for numbers and common Roblox datatypes.
function Util.near(a: any, b: any, epsilon: number): boolean
	local kind = typeof(a)
	if kind ~= typeof(b) then
		return false
	end
	if kind == "number" then
		return math.abs(a - b) <= epsilon
	elseif kind == "Vector3" or kind == "Vector2" then
		return (a - b).Magnitude <= epsilon
	elseif kind == "CFrame" then
		local ac, bc = { a:GetComponents() }, { b:GetComponents() }
		for i = 1, #ac do
			if math.abs(ac[i] - bc[i]) > epsilon then
				return false
			end
		end
		return true
	elseif kind == "Color3" then
		return math.abs(a.R - b.R) <= epsilon and math.abs(a.G - b.G) <= epsilon and math.abs(a.B - b.B) <= epsilon
	end
	return a == b
end

function Util.xmlEscape(s: string): string
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
end

return Util
