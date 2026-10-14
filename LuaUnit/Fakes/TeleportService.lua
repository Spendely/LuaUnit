--!strict
--[[
	Fake TeleportService. Nothing actually teleports (it never works in
	Studio anyway); teleports are recorded so tests can check them.

		local teleport = Fakes.TeleportService.new()
		Party.TeleportService = teleport
		Party.start(players)
		Assert.equals(teleport.teleports[1].placeId, ARENA_PLACE_ID)
		teleport:failNext("TeleportAsync", "Teleport failed: server full")
]]

local HttpService = game:GetService("HttpService")

local Signal = require(script.Parent.Signal)

local Teleport = {}
Teleport.__index = Teleport

function Teleport.new()
	return setmetatable({
		-- { { placeId, players, options, method } }
		teleports = {},
		reservedServers = {},
		TeleportInitFailed = Signal.new(),
		_failures = {},
		_localTeleportData = nil,
	}, Teleport)
end

function Teleport:failNext(method: string?, message: string?)
	table.insert(self._failures, { method = method, message = message or "Teleport failed (simulated)" })
end

function Teleport:_begin(method: string, players: { any }?)
	for i, failure in self._failures do
		if failure.method == nil or failure.method == method then
			table.remove(self._failures, i)
			-- Real TeleportAsync failures can both throw and fire TeleportInitFailed.
			for _, player in players or {} do
				self.TeleportInitFailed:Fire(player, Enum.TeleportResult.Failure, failure.message, 0, nil)
			end
			error(failure.message, 0)
		end
	end
end

local function validatePlayers(players: any)
	if typeof(players) ~= "table" or #players == 0 then
		error("players must be a non-empty array", 0)
	end
	if #players > 50 then
		error("cannot teleport more than 50 players at once", 0)
	end
end

function Teleport:TeleportAsync(placeId: number, players: { any }, options: any?)
	validatePlayers(players)
	self:_begin("TeleportAsync", players)
	local data = options and options.GetTeleportData and options:GetTeleportData()
	if data ~= nil then
		-- Teleport data must survive JSON, like the real service requires.
		HttpService:JSONEncode(data)
	end
	table.insert(self.teleports, {
		method = "TeleportAsync",
		placeId = placeId,
		players = table.clone(players),
		options = options,
		teleportData = data,
	})
	return {
		PrivateServerId = options and options.ReservedServerAccessCode and "fake-private-server" or "",
		ReservedServerAccessCode = options and options.ReservedServerAccessCode or "",
	}
end

function Teleport:Teleport(placeId: number, player: any, teleportData: any?)
	self:_begin("Teleport", { player })
	table.insert(self.teleports, { method = "Teleport", placeId = placeId, players = { player }, teleportData = teleportData })
end

function Teleport:ReserveServer(placeId: number): (string, string)
	self:_begin("ReserveServer")
	local code = "fake-access-code-" .. (#self.reservedServers + 1)
	local id = "fake-private-server-" .. (#self.reservedServers + 1)
	table.insert(self.reservedServers, { placeId = placeId, accessCode = code, privateServerId = id })
	return code, id
end

-- Client-side: set what GetLocalPlayerTeleportData returns.
function Teleport:setLocalTeleportData(data: any)
	self._localTeleportData = data
end

function Teleport:GetLocalPlayerTeleportData(): any
	return self._localTeleportData
end

-- All players teleported to placeId (optional), across all calls.
function Teleport:playersSentTo(placeId: number?): { any }
	local result = {}
	for _, record in self.teleports do
		if placeId == nil or record.placeId == placeId then
			for _, player in record.players do
				table.insert(result, player)
			end
		end
	end
	return result
end

return Teleport
