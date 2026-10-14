--!strict
--[[
	Controllable time, for testing cooldowns, timers and expirations without
	actually waiting.

	Your code should take a clock instead of calling os.clock/task.delay
	directly. Clock.real() has the same interface for production:

		Cooldown.clock = Fakes.Clock.real()    -- in the game
		Cooldown.clock = Fakes.Clock.new()     -- in a test
		...
		clock:advance(5)                       -- jump 5 seconds ahead

	Interface (both real and fake):
		clock:now()                -> seconds
		clock:delay(seconds, fn)   -> handle (handle:cancel())
		clock:wait(seconds)        -> yields until that much time has passed
]]

local Clock = {}

local FakeClock = {}
FakeClock.__index = FakeClock

function Clock.new(startTime: number?)
	return setmetatable({ _now = startTime or 0, _scheduled = {}, _nextId = 0 }, FakeClock)
end

function FakeClock:now(): number
	return self._now
end

function FakeClock:delay(seconds: number, fn: (...any) -> (), ...: any)
	self._nextId += 1
	local entry = { at = self._now + seconds, id = self._nextId, fn = fn, args = table.pack(...), cancelled = false }
	table.insert(self._scheduled, entry)
	return {
		cancel = function()
			entry.cancelled = true
		end,
	}
end

function FakeClock:wait(seconds: number): number
	local thread = coroutine.running()
	local started = self._now
	self:delay(seconds, function()
		task.spawn(thread, self._now - started)
	end)
	return coroutine.yield()
end

-- Moves time forward, running everything scheduled up to the new time in order.
function FakeClock:advance(seconds: number)
	local target = self._now + seconds
	while true do
		table.sort(self._scheduled, function(a, b)
			if a.at == b.at then
				return a.id < b.id
			end
			return a.at < b.at
		end)
		local nextEntry = self._scheduled[1]
		if not nextEntry or nextEntry.at > target then
			break
		end
		table.remove(self._scheduled, 1)
		if not nextEntry.cancelled then
			self._now = nextEntry.at
			nextEntry.fn(table.unpack(nextEntry.args, 1, nextEntry.args.n))
		end
	end
	self._now = target
end

function FakeClock:pending(): number
	local n = 0
	for _, entry in self._scheduled do
		if not entry.cancelled then
			n += 1
		end
	end
	return n
end

local RealClock = {}
RealClock.__index = RealClock

function Clock.real()
	return setmetatable({}, RealClock)
end

function RealClock:now(): number
	return os.clock()
end

function RealClock:delay(seconds: number, fn: (...any) -> (), ...: any)
	local thread = task.delay(seconds, fn, ...)
	return {
		cancel = function()
			task.cancel(thread)
		end,
	}
end

function RealClock:wait(seconds: number): number
	return task.wait(seconds)
end

return Clock
