--!strict
-- Spies and stubs.
--   Mock.spy(fn?)          -> callable spy that records calls (and forwards to fn)
--   Mock.stub(tbl, key, fn?) -> replaces tbl[key] with a spy; restored after each test

export type Call = { args: { any }, n: number }

export type Spy = {
	calls: { Call },
	callCount: number,
	fn: (...any) -> ...any,
	returns: (self: Spy, ...any) -> Spy,
	implement: (self: Spy, fn: (...any) -> ...any) -> Spy,
	calledWith: (self: Spy, ...any) -> boolean,
	lastCall: (self: Spy) -> Call?,
	reset: (self: Spy) -> (),
	restore: (self: Spy) -> (),
}

local Util = require(script.Parent.Util)

local Mock = {}

local activeStubs: { Spy } = {}

local SpyMethods = {}
SpyMethods.__index = SpyMethods

SpyMethods.__call = function(self, ...)
	table.insert(self.calls, { args = table.pack(...), n = select("#", ...) })
	self.callCount += 1
	if self._impl then
		return self._impl(...)
	end
	if self._returns then
		return table.unpack(self._returns, 1, self._returns.n)
	end
	return nil
end

-- Make the spy return fixed values instead of calling through.
function SpyMethods:returns(...)
	self._impl = nil
	self._returns = table.pack(...)
	return self
end

-- Replace the spy's behaviour with fn.
function SpyMethods:implement(fn)
	self._returns = nil
	self._impl = fn
	return self
end

-- True if any recorded call had exactly these arguments (deep-compared).
function SpyMethods:calledWith(...)
	local expected = table.pack(...)
	for _, call in self.calls do
		if call.n == expected.n then
			local match = true
			for i = 1, expected.n do
				if not Util.deepEqual(call.args[i], expected[i]) then
					match = false
					break
				end
			end
			if match then
				return true
			end
		end
	end
	return false
end

function SpyMethods:lastCall()
	return self.calls[#self.calls]
end

function SpyMethods:reset()
	table.clear(self.calls)
	self.callCount = 0
end

function SpyMethods:restore()
	if self._target then
		self._target[self._key] = self._original
		self._target = nil
	end
end

function Mock.spy(fn: ((...any) -> ...any)?): Spy
	local spy = setmetatable({ calls = {}, callCount = 0, _impl = fn }, SpyMethods)
	-- Real function that calls the spy, for APIs that reject callable tables
	-- (e.g. part.Touched:Connect(spy.fn)).
	spy.fn = function(...)
		return spy(...)
	end
	return (spy :: any) :: Spy
end

function Mock.isSpy(value: any): boolean
	return typeof(value) == "table" and getmetatable(value) == SpyMethods
end

-- Replaces tbl[key] with a spy. With no fn, the spy calls the original.
-- Throws if tbl is frozen/readonly (e.g. Roblox services), so stub your own modules.
function Mock.stub(tbl: { [any]: any }, key: any, fn: ((...any) -> ...any)?): Spy
	local original = tbl[key]
	local spy: any = Mock.spy(fn or original)
	spy._target, spy._key, spy._original = tbl, key, original
	tbl[key] = spy
	table.insert(activeStubs, spy)
	return spy
end

-- Called by the runner after every test.
function Mock.restoreAll()
	for i = #activeStubs, 1, -1 do
		activeStubs[i]:restore()
	end
	table.clear(activeStubs)
end

return Mock
