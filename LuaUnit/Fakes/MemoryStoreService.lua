--!strict
--[[
	In-memory MemoryStoreService: SortedMaps, Queues and HashMaps, with
	expiration. Pass a Fakes.Clock to test expiry instantly:

		local clock = Fakes.Clock.new()
		local service = Fakes.MemoryStoreService.new({ clock = clock })
		local map = service:GetSortedMap("Matchmaking")
		map:SetAsync("bob", 1200, 30)
		clock:advance(31)  -- "bob" has now expired

	Every structure supports :failNext(method?, message?) and has a .calls log.
]]

local Clock = require(script.Parent.Clock)

local MAX_EXPIRATION = 45 * 24 * 60 * 60

local Service = {}
Service.__index = Service

local function copy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local result = {}
	for k, v in value do
		result[k] = copy(v)
	end
	return result
end

-- Shared base for logging, failure injection and expiry checks.
local function newBase(service, name: string)
	return {
		name = name,
		calls = {},
		_failures = {},
		_clock = service._clock,
	}
end

local function begin(self, method: string)
	table.insert(self.calls, { method = method })
	for i, failure in self._failures do
		if failure.method == nil or failure.method == method then
			table.remove(self._failures, i)
			error(failure.message, 0)
		end
	end
end

local function failNext(self, method: string?, message: string?)
	table.insert(self._failures, { method = method, message = message or "MemoryStore request failed (simulated)" })
end

local function checkExpiration(expiration: number)
	if typeof(expiration) ~= "number" or expiration <= 0 or expiration > MAX_EXPIRATION then
		error(`expiration must be between 0 and {MAX_EXPIRATION} seconds`, 0)
	end
end

-- Key/value maps (SortedMap and HashMap share most of their logic) ----------

local KeyValue = {}
KeyValue.__index = KeyValue
KeyValue.failNext = failNext

function KeyValue:_live(key: string)
	local entry = self._data[key]
	if entry and entry.expiresAt <= self._clock:now() then
		self._data[key] = nil
		return nil
	end
	return entry
end

function KeyValue:GetAsync(key: string)
	begin(self, "GetAsync")
	local entry = self:_live(key)
	if not entry then
		return nil
	end
	if self.sorted then
		return copy(entry.value), entry.sortKey
	end
	return copy(entry.value)
end

function KeyValue:SetAsync(key: string, value: any, expiration: number, sortKey: any?): boolean
	checkExpiration(expiration)
	begin(self, "SetAsync")
	self._data[key] = { value = copy(value), expiresAt = self._clock:now() + expiration, sortKey = sortKey }
	return true
end

function KeyValue:UpdateAsync(key: string, transform: (any, any?) -> (any, any?), expiration: number): any
	checkExpiration(expiration)
	begin(self, "UpdateAsync")
	local entry = self:_live(key)
	local newValue, newSortKey = transform(
		if entry then copy(entry.value) else nil,
		if entry then entry.sortKey else nil
	)
	if newValue == nil then
		return nil
	end
	self._data[key] = { value = copy(newValue), expiresAt = self._clock:now() + expiration, sortKey = newSortKey }
	return copy(newValue)
end

function KeyValue:RemoveAsync(key: string)
	begin(self, "RemoveAsync")
	self._data[key] = nil
end

-- SortedMap only: items ordered by sortKey (if any), then key.
-- Bounds are { key = ..., sortKey = ... } like the real API.
function KeyValue:GetRangeAsync(direction: Enum.SortDirection, count: number, lower: any?, upper: any?)
	if not self.sorted then
		error("GetRangeAsync is only available on SortedMaps", 0)
	end
	begin(self, "GetRangeAsync")
	local items = {}
	for key in self._data do
		local entry = self:_live(key)
		if entry then
			table.insert(items, { key = key, value = copy(entry.value), sortKey = entry.sortKey })
		end
	end
	local function less(a, b)
		if a.sortKey ~= b.sortKey then
			if a.sortKey == nil then
				return false
			elseif b.sortKey == nil then
				return true
			end
			return a.sortKey < b.sortKey
		end
		return a.key < b.key
	end
	table.sort(items, less)
	local filtered = {}
	for _, item in items do
		local aboveLower = lower == nil or less({ key = lower.key or "", sortKey = lower.sortKey }, item)
		local belowUpper = upper == nil or less(item, { key = upper.key or "\255", sortKey = upper.sortKey })
		if aboveLower and belowUpper then
			table.insert(filtered, item)
		end
	end
	local result = {}
	local descending = direction == Enum.SortDirection.Descending
	for i = 1, math.min(count, #filtered) do
		table.insert(result, filtered[if descending then #filtered - i + 1 else i])
	end
	return result
end

function KeyValue:peek(key: string): any
	local entry = self:_live(key)
	return if entry then copy(entry.value) else nil
end

-- Queue ----------------------------------------------------------------------

local Queue = {}
Queue.__index = Queue
Queue.failNext = failNext

function Queue:AddAsync(value: any, expiration: number, priority: number?)
	checkExpiration(expiration)
	begin(self, "AddAsync")
	self._order += 1
	table.insert(self._items, {
		value = copy(value),
		expiresAt = self._clock:now() + expiration,
		priority = priority or 0,
		order = self._order,
		invisibleUntil = 0,
	})
end

-- Returns up to `count` items and an id to pass to RemoveAsync. Read items are
-- hidden for the invisibility timeout, then reappear if not removed.
function Queue:ReadAsync(count: number, allOrNothing: boolean?, _waitTimeout: number?)
	begin(self, "ReadAsync")
	local now = self._clock:now()
	for i = #self._items, 1, -1 do
		if self._items[i].expiresAt <= now then
			table.remove(self._items, i)
		end
	end
	table.sort(self._items, function(a, b)
		if a.priority ~= b.priority then
			return a.priority > b.priority
		end
		return a.order < b.order
	end)
	local picked = {}
	for _, item in self._items do
		if #picked >= count then
			break
		end
		if item.invisibleUntil <= now then
			table.insert(picked, item)
		end
	end
	if #picked == 0 or (allOrNothing and #picked < count) then
		return {}, nil
	end
	self._readId += 1
	local id = tostring(self._readId)
	local values = {}
	for _, item in picked do
		item.invisibleUntil = now + self.invisibilityTimeout
		item.readId = id
		table.insert(values, copy(item.value))
	end
	return values, id
end

function Queue:RemoveAsync(id: string)
	begin(self, "RemoveAsync")
	for i = #self._items, 1, -1 do
		if self._items[i].readId == id then
			table.remove(self._items, i)
		end
	end
end

function Queue:size(): number
	return #self._items
end

-- Service --------------------------------------------------------------------

function Service.new(options: { clock: any? }?)
	return setmetatable({
		_clock = options and options.clock or Clock.real(),
		_sortedMaps = {},
		_hashMaps = {},
		_queues = {},
	}, Service)
end

function Service:GetSortedMap(name: string)
	if not self._sortedMaps[name] then
		local map = newBase(self, name)
		map.sorted, map._data = true, {}
		self._sortedMaps[name] = setmetatable(map, KeyValue)
	end
	return self._sortedMaps[name]
end

function Service:GetHashMap(name: string)
	if not self._hashMaps[name] then
		local map = newBase(self, name)
		map.sorted, map._data = false, {}
		self._hashMaps[name] = setmetatable(map, KeyValue)
	end
	return self._hashMaps[name]
end

function Service:GetQueue(name: string, invisibilityTimeout: number?)
	if not self._queues[name] then
		local queue = newBase(self, name)
		queue._items, queue._order, queue._readId = {}, 0, 0
		queue.invisibilityTimeout = invisibilityTimeout or 30
		self._queues[name] = setmetatable(queue, Queue)
	end
	return self._queues[name]
end

return Service
