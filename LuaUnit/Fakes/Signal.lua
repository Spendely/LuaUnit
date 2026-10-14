--!strict
-- A pure-Luau signal with the same shape as RBXScriptSignal
-- (Connect / Once / Wait), plus Fire for tests to trigger it.

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local handlers = self._signal._handlers
	local index = table.find(handlers, self)
	if index then
		table.remove(handlers, index)
	end
end

function Signal.new()
	return setmetatable({ _handlers = {}, _waiting = {}, fireCount = 0 }, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	local connection = setmetatable({ Connected = true, _signal = self, _fn = fn }, Connection)
	table.insert(self._handlers, connection)
	return connection
end

function Signal:Once(fn: (...any) -> ())
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Wait(): ...any
	table.insert(self._waiting, coroutine.running())
	return coroutine.yield()
end

-- Wrapper so callable tables (like spies) work as handlers; task.spawn
-- only accepts real functions.
local function call(fn, ...)
	fn(...)
end

-- Handlers run in their own threads, like Roblox's deferred-off behaviour.
function Signal:Fire(...: any)
	self.fireCount += 1
	for _, connection in table.clone(self._handlers) do
		if connection.Connected then
			task.spawn(call, connection._fn, ...)
		end
	end
	local waiting = self._waiting
	self._waiting = {}
	for _, thread in waiting do
		task.spawn(thread, ...)
	end
end

function Signal:DisconnectAll()
	for _, connection in table.clone(self._handlers) do
		connection:Disconnect()
	end
end

function Signal:Destroy()
	self:DisconnectAll()
end

return Signal
