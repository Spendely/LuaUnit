--!strict
--[[
	In-memory stand-in for DataStoreService. Lets you unit test save/load code
	without touching real data (and without "Enable Studio Access to API Services").

	Your code has to receive the service instead of calling game:GetService
	directly, e.g.:
		PlayerData.DataStoreService = game:GetService("DataStoreService")
		-- in a test:
		PlayerData.DataStoreService = Fakes.DataStoreService.new()

	Mirrors the real API: GetAsync, SetAsync, UpdateAsync, IncrementAsync,
	RemoveAsync, plus GetSortedAsync on ordered stores. Values are validated
	the way Roblox does (no Instances/functions, no mixed tables, 4MB limit)
	and deep-copied, so mutating a loaded table doesn't change the store.

	Test controls on every store:
		store:failNext(method?, message?)  -- next call (to method, or any) throws
		store:seed({ key = value, ... })    -- preload data
		store:peek(key)                     -- read without logging/latency
		store.calls                         -- { { method = "SetAsync", key = "..." } }
]]

local HttpService = game:GetService("HttpService")

local MAX_KEY_LENGTH = 50
local MAX_VALUE_BYTES = 4 * 1024 * 1024

export type Options = {
	latency: number?, -- seconds each call yields, to surface race conditions
}

local FakeDataStoreService = {}
FakeDataStoreService.__index = FakeDataStoreService

local FakeDataStore = {}
FakeDataStore.__index = FakeDataStore

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

local function validateValue(value: any, path: string, seen: { [any]: boolean })
	local kind = typeof(value)
	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			error(`{path}: NaN/inf cannot be stored`, 0)
		end
	elseif kind == "string" or kind == "boolean" then
		return
	elseif kind == "table" then
		if seen[value] then
			error(`{path}: tables with cycles cannot be stored`, 0)
		end
		seen[value] = true
		local hasArrayKeys, hasStringKeys = false, false
		for k, v in value do
			if typeof(k) == "number" then
				hasArrayKeys = true
			elseif typeof(k) == "string" then
				hasStringKeys = true
			else
				error(`{path}: table keys must be strings or numbers, got {typeof(k)}`, 0)
			end
			validateValue(v, `{path}.{tostring(k)}`, seen)
		end
		if hasArrayKeys and hasStringKeys then
			error(`{path}: mixed array/dictionary tables cannot be stored`, 0)
		end
		if hasArrayKeys and #value ~= (function()
			local n = 0
			for _ in value do
				n += 1
			end
			return n
		end)() then
			error(`{path}: arrays with holes cannot be stored`, 0)
		end
		seen[value] = nil
	else
		error(`{path}: {kind} cannot be stored in a DataStore`, 0)
	end
end

local function validate(key: any, value: any?)
	if typeof(key) ~= "string" or #key == 0 then
		error("DataStore key must be a non-empty string", 0)
	end
	if #key > MAX_KEY_LENGTH then
		error(`DataStore key exceeds {MAX_KEY_LENGTH} characters`, 0)
	end
	if value ~= nil then
		validateValue(value, "value", {})
		if #HttpService:JSONEncode(value) > MAX_VALUE_BYTES then
			error("DataStore value exceeds 4MB", 0)
		end
	end
end

local function keyInfo(entry)
	return {
		Version = tostring(entry.version),
		CreatedTime = entry.created,
		UpdatedTime = entry.updated,
		GetUserIds = function()
			return table.clone(entry.userIds)
		end,
		GetMetadata = function()
			return table.clone(entry.metadata)
		end,
	}
end

function FakeDataStoreService.new(options: Options?)
	return setmetatable({ _stores = {}, _options = options or {} }, FakeDataStoreService)
end

local function getStore(self, name: string, scope: string?, ordered: boolean)
	local id = (if ordered then "ordered:" else "") .. name .. "/" .. (scope or "global")
	if not self._stores[id] then
		self._stores[id] = setmetatable({
			name = name,
			ordered = ordered,
			calls = {},
			_data = {},
			_failures = {},
			_latency = self._options.latency,
		}, FakeDataStore)
	end
	return self._stores[id]
end

function FakeDataStoreService:GetDataStore(name: string, scope: string?)
	return getStore(self, name, scope, false)
end

function FakeDataStoreService:GetOrderedDataStore(name: string, scope: string?)
	return getStore(self, name, scope, true)
end

function FakeDataStoreService:GetRequestBudgetForRequestType(_requestType: any): number
	return math.huge
end

-- Runs before every store call: logs it, simulates latency and queued failures.
function FakeDataStore:_begin(method: string, key: string?)
	table.insert(self.calls, { method = method, key = key })
	if self._latency then
		task.wait(self._latency)
	end
	for i, failure in self._failures do
		if failure.method == nil or failure.method == method then
			table.remove(self._failures, i)
			error(failure.message, 0)
		end
	end
end

function FakeDataStore:_write(key: string, value: any, userIds: { number }?, options: any?)
	local now = DateTime.now().UnixTimestampMillis
	local entry = self._data[key]
	if entry then
		entry.value = deepCopy(value)
		entry.version += 1
		entry.updated = now
	else
		entry = { value = deepCopy(value), version = 1, created = now, updated = now, userIds = {}, metadata = {} }
		self._data[key] = entry
	end
	if userIds then
		entry.userIds = table.clone(userIds)
	end
	if options and options.GetMetadata then
		entry.metadata = options:GetMetadata()
	end
	return entry
end

function FakeDataStore:_checkOrdered(value: any)
	if self.ordered and (typeof(value) ~= "number" or value % 1 ~= 0) then
		error("OrderedDataStore values must be integers", 0)
	end
end

function FakeDataStore:GetAsync(key: string)
	validate(key)
	self:_begin("GetAsync", key)
	local entry = self._data[key]
	if not entry then
		return nil, nil
	end
	return deepCopy(entry.value), keyInfo(entry)
end

function FakeDataStore:SetAsync(key: string, value: any, userIds: { number }?, options: any?)
	if value == nil then
		error("Argument 2 missing or nil", 0)
	end
	validate(key, value)
	self:_checkOrdered(value)
	self:_begin("SetAsync", key)
	return tostring(self:_write(key, value, userIds, options).version)
end

function FakeDataStore:UpdateAsync(key: string, transform: (any, any) -> (any, { number }?, any?))
	validate(key)
	self:_begin("UpdateAsync", key)
	local entry = self._data[key]
	local newValue, userIds, metadata = transform(
		if entry then deepCopy(entry.value) else nil,
		if entry then keyInfo(entry) else nil
	)
	if newValue == nil then
		-- Returning nil from the transform cancels the update, like the real API.
		return nil, nil
	end
	validate(key, newValue)
	self:_checkOrdered(newValue)
	local written = self:_write(key, newValue, userIds, nil)
	if metadata then
		written.metadata = metadata
	end
	return deepCopy(written.value), keyInfo(written)
end

function FakeDataStore:IncrementAsync(key: string, delta: number?, userIds: { number }?)
	validate(key)
	self:_begin("IncrementAsync", key)
	local entry = self._data[key]
	local current = if entry then entry.value else 0
	if typeof(current) ~= "number" then
		error("IncrementAsync: existing value is not a number", 0)
	end
	local newValue = current + math.floor(delta or 1)
	self:_write(key, newValue, userIds, nil)
	return newValue
end

function FakeDataStore:RemoveAsync(key: string)
	validate(key)
	self:_begin("RemoveAsync", key)
	local entry = self._data[key]
	self._data[key] = nil
	if not entry then
		return nil, nil
	end
	return entry.value, keyInfo(entry)
end

-- OrderedDataStore only. Returns a pages object like the real DataStorePages.
function FakeDataStore:GetSortedAsync(ascending: boolean, pageSize: number, minValue: number?, maxValue: number?)
	if not self.ordered then
		error("GetSortedAsync is only available on OrderedDataStores", 0)
	end
	self:_begin("GetSortedAsync", nil)
	local entries = {}
	for key, entry in self._data do
		local v = entry.value
		if (minValue == nil or v >= minValue) and (maxValue == nil or v <= maxValue) then
			table.insert(entries, { key = key, value = v })
		end
	end
	table.sort(entries, function(a, b)
		if a.value == b.value then
			return a.key < b.key
		end
		return if ascending then a.value < b.value else a.value > b.value
	end)

	local pages = { IsFinished = false, _page = 1 }
	local function update()
		pages.IsFinished = pages._page * pageSize >= #entries
	end
	function pages:GetCurrentPage()
		local page = {}
		for i = (self._page - 1) * pageSize + 1, math.min(self._page * pageSize, #entries) do
			table.insert(page, table.clone(entries[i]))
		end
		return page
	end
	function pages:AdvanceToNextPageAsync()
		if self.IsFinished then
			error("No more pages", 0)
		end
		self._page += 1
		update()
	end
	update()
	return pages
end

-- Test controls -------------------------------------------------------------

function FakeDataStore:failNext(method: string?, message: string?)
	table.insert(self._failures, {
		method = method,
		message = message or "502: API Services rejected request (simulated)",
	})
end

function FakeDataStore:seed(data: { [string]: any })
	for key, value in data do
		validate(key, value)
		self:_write(key, value, nil, nil)
	end
end

function FakeDataStore:peek(key: string): any
	local entry = self._data[key]
	return if entry then deepCopy(entry.value) else nil
end

function FakeDataStore:callCount(method: string): number
	local n = 0
	for _, call in self.calls do
		if call.method == method then
			n += 1
		end
	end
	return n
end

return FakeDataStoreService
