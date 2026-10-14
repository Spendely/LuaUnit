--!strict
--[[
	Fake RemoteEvent / RemoteFunction for testing networking code in one place.

	Arguments are copied the way Roblox replicates them: tables are
	deep-copied and lose their metatables, and functions/threads are rejected.
	So a test catches "works locally, breaks over the network" bugs.

		local remote = Fakes.Remote.event()
		remote.OnServerEvent:Connect(handler)      -- same as the real API
		remote:FireServerAs(player, "BuyItem", 3)  -- simulate a client firing
		remote:FireClient(player, data)            -- check remote.clientCalls
]]

local Signal = require(script.Parent.Signal)

local Remote = {}

local function replicate(value: any, path: string): any
	local kind = typeof(value)
	if kind == "function" or kind == "thread" then
		error(`{path}: {kind} values can't be sent over a remote`, 0)
	elseif kind == "table" then
		local copy = {}
		for k, v in value do
			copy[k] = replicate(v, `{path}.{tostring(k)}`)
		end
		return copy -- metatable intentionally dropped, like real replication
	end
	return value
end

local function replicateArgs(...: any): { any }
	local args = table.pack(...)
	for i = 1, args.n do
		args[i] = replicate(args[i], `argument {i}`)
	end
	return args
end

local RemoteEvent = {}
RemoteEvent.__index = RemoteEvent

function Remote.event(name: string?)
	return setmetatable({
		Name = name or "RemoteEvent",
		ClassName = "RemoteEvent",
		OnServerEvent = Signal.new(),
		OnClientEvent = Signal.new(),
		serverCalls = {}, -- { { player, args } } from FireServerAs
		clientCalls = {}, -- { { player (nil = all), args } } from FireClient/FireAllClients
	}, RemoteEvent)
end

function RemoteEvent:FireServerAs(player: any, ...: any)
	local args = replicateArgs(...)
	table.insert(self.serverCalls, { player = player, args = args })
	self.OnServerEvent:Fire(player, table.unpack(args, 1, args.n))
end

function RemoteEvent:FireClient(player: any, ...: any)
	local args = replicateArgs(...)
	table.insert(self.clientCalls, { player = player, args = args })
	self.OnClientEvent:Fire(table.unpack(args, 1, args.n))
end

function RemoteEvent:FireAllClients(...: any)
	local args = replicateArgs(...)
	table.insert(self.clientCalls, { player = nil, args = args })
	self.OnClientEvent:Fire(table.unpack(args, 1, args.n))
end

function RemoteEvent:IsA(className: string): boolean
	return className == "RemoteEvent" or className == "Instance"
end

local RemoteFunction = {}
RemoteFunction.__index = RemoteFunction

function Remote.func(name: string?)
	return setmetatable({
		Name = name or "RemoteFunction",
		ClassName = "RemoteFunction",
		OnServerInvoke = nil :: ((any, ...any) -> ...any)?,
		OnClientInvoke = nil :: ((...any) -> ...any)?,
	}, RemoteFunction)
end

-- Simulates a client calling InvokeServer. Return values are replicated too.
function RemoteFunction:InvokeServerAs(player: any, ...: any): ...any
	local handler = self.OnServerInvoke
	if not handler then
		error(`{self.Name}: OnServerInvoke is not set`, 0)
	end
	local args = replicateArgs(...)
	local results = replicateArgs(handler(player, table.unpack(args, 1, args.n)))
	return table.unpack(results, 1, results.n)
end

function RemoteFunction:InvokeClient(_player: any, ...: any): ...any
	local handler = self.OnClientInvoke
	if not handler then
		error(`{self.Name}: OnClientInvoke is not set`, 0)
	end
	local args = replicateArgs(...)
	local results = replicateArgs(handler(table.unpack(args, 1, args.n)))
	return table.unpack(results, 1, results.n)
end

function RemoteFunction:IsA(className: string): boolean
	return className == "RemoteFunction" or className == "Instance"
end

return Remote
