--!strict
-- Assertions. A failed assertion throws an AssertionFailure table so the
-- runner can tell a *failure* (assert didn't hold) from an *error* (crash).

local Util = require(script.Parent.Util)

export type AssertionFailure = {
	isAssertionFailure: true,
	message: string,
	traceback: string,
}

local Assert = {}

local function fail(message: string): never
	local failure: AssertionFailure = {
		isAssertionFailure = true,
		message = message,
		traceback = debug.traceback("", 3),
	}
	error(failure, 0)
end

local function withMsg(base: string, msg: string?): string
	return if msg then msg .. ": " .. base else base
end

function Assert.isFailure(value: any): boolean
	return typeof(value) == "table" and value.isAssertionFailure == true
end

function Assert.fail(msg: string?)
	fail(msg or "Assert.fail() called")
end

function Assert.equals(actual: any, expected: any, msg: string?)
	if actual ~= expected then
		fail(withMsg(`expected {Util.pretty(expected)}, got {Util.pretty(actual)}`, msg))
	end
end

function Assert.notEquals(actual: any, unexpected: any, msg: string?)
	if actual == unexpected then
		fail(withMsg(`expected value to differ from {Util.pretty(unexpected)}`, msg))
	end
end

function Assert.deepEquals(actual: any, expected: any, msg: string?)
	if not Util.deepEqual(actual, expected) then
		fail(withMsg(`expected {Util.pretty(expected)}, got {Util.pretty(actual)}`, msg))
	end
end

function Assert.near(actual: any, expected: any, epsilon: number?, msg: string?)
	local eps = epsilon or 1e-5
	if not Util.near(actual, expected, eps) then
		fail(withMsg(`expected {Util.pretty(expected)} (±{eps}), got {Util.pretty(actual)}`, msg))
	end
end

function Assert.isTrue(value: any, msg: string?)
	if value ~= true then
		fail(withMsg(`expected true, got {Util.pretty(value)}`, msg))
	end
end

function Assert.isFalse(value: any, msg: string?)
	if value ~= false then
		fail(withMsg(`expected false, got {Util.pretty(value)}`, msg))
	end
end

function Assert.isNil(value: any, msg: string?)
	if value ~= nil then
		fail(withMsg(`expected nil, got {Util.pretty(value)}`, msg))
	end
end

function Assert.notNil(value: any, msg: string?)
	if value == nil then
		fail(withMsg("expected a non-nil value", msg))
	end
end

function Assert.typeOf(value: any, expectedType: string, msg: string?)
	if typeof(value) ~= expectedType then
		fail(withMsg(`expected type {expectedType}, got {typeof(value)}`, msg))
	end
end

function Assert.isA(instance: any, className: string, msg: string?)
	if typeof(instance) ~= "Instance" or not instance:IsA(className) then
		fail(withMsg(`expected Instance of class {className}, got {Util.pretty(instance)}`, msg))
	end
end

-- Asserts fn throws. If `pattern` is given, the error message must match it.
function Assert.throws(fn: (...any) -> ...any, pattern: string?, msg: string?)
	local ok, err = pcall(fn)
	if ok then
		fail(withMsg("expected function to throw, but it returned normally", msg))
	end
	if pattern and not string.find(tostring(err), pattern) then
		fail(withMsg(`expected error matching {Util.pretty(pattern)}, got {Util.pretty(tostring(err))}`, msg))
	end
end

function Assert.doesNotThrow(fn: (...any) -> ...any, msg: string?)
	local ok, err = pcall(fn)
	if not ok then
		fail(withMsg(`expected no error, got {Util.pretty(tostring(err))}`, msg))
	end
end

-- Async assertions.

-- Re-runs `check` until it stops failing, or rethrows its last failure after
-- `timeout` seconds. Use for state that settles asynchronously.
function Assert.eventually(check: () -> (), timeout: number?)
	local deadline = os.clock() + (timeout or 1)
	while true do
		local ok, err = pcall(check)
		if ok then
			return
		end
		if os.clock() >= deadline then
			if Assert.isFailure(err) then
				error(err, 0)
			end
			fail("eventually: " .. tostring(err))
		end
		task.wait()
	end
end

-- Asserts that `signal` (RBXScriptSignal or Fakes.Signal) fires within
-- `timeout` seconds after calling `trigger`. Returns the fired arguments.
function Assert.fires(signal: any, trigger: (() -> ())?, timeout: number?): ...any
	local fired, args = false, nil
	local connection = signal:Connect(function(...)
		if not fired then
			fired, args = true, table.pack(...)
		end
	end)
	if trigger then
		trigger()
	end
	local deadline = os.clock() + (timeout or 1)
	while not fired and os.clock() < deadline do
		task.wait()
	end
	connection:Disconnect()
	if not fired then
		fail(`expected signal to fire within {timeout or 1}s`)
	end
	return table.unpack(args, 1, args.n)
end

-- Spy assertions (see Mock.lua).

function Assert.called(spy: any, msg: string?)
	if spy.callCount == 0 then
		fail(withMsg("expected spy to be called, but it never was", msg))
	end
end

function Assert.notCalled(spy: any, msg: string?)
	if spy.callCount ~= 0 then
		fail(withMsg(`expected spy not to be called, but it was called {spy.callCount} time(s)`, msg))
	end
end

function Assert.calledTimes(spy: any, times: number, msg: string?)
	if spy.callCount ~= times then
		fail(withMsg(`expected spy to be called {times} time(s), got {spy.callCount}`, msg))
	end
end

function Assert.calledWith(spy: any, ...: any)
	if not spy:calledWith(...) then
		local seen = {}
		for _, call in spy.calls do
			table.insert(seen, Util.pretty(table.pack(table.unpack(call.args, 1, call.n))))
		end
		fail(`expected spy to be called with {Util.pretty(table.pack(...))}; calls were: {if #seen > 0
			then table.concat(seen, ", ")
			else "(none)"}`)
	end
end

return Assert
