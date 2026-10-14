--!strict
-- Discovers *.spec ModuleScripts, builds the describe/it tree, runs it.

local RunService = game:GetService("RunService")

local Assert = require(script.Parent.Assert)
local Mock = require(script.Parent.Mock)
local Cleanup = require(script.Parent.Cleanup)

local Fakes = {
	DataStoreService = require(script.Parent.Fakes.DataStoreService),
	Signal = require(script.Parent.Fakes.Signal),
	Remote = require(script.Parent.Fakes.Remote),
	Player = require(script.Parent.Fakes.Player),
	Clock = require(script.Parent.Fakes.Clock),
	MemoryStoreService = require(script.Parent.Fakes.MemoryStoreService),
	MarketplaceService = require(script.Parent.Fakes.MarketplaceService),
	TeleportService = require(script.Parent.Fakes.TeleportService),
}

export type Status = "passed" | "failed" | "errored" | "skipped"

export type TestResult = {
	name: string,
	status: Status,
	message: string?,
	traceback: string?,
	duration: number,
}

export type SuiteResult = {
	name: string,
	tests: { TestResult },
	duration: number,
}

export type RunResults = {
	suites: { SuiteResult },
	passed: number,
	failed: number,
	errored: number,
	skipped: number,
	duration: number,
}

export type Options = {
	roots: { Instance }?,
	filter: string?, -- Lua pattern matched against "Group > Sub > test name"
	timeout: number?, -- seconds per test, default 5
	reporters: { any }?,
	-- Require clones of spec modules so edits are picked up without restarting
	-- (needed when running from a plugin, where require() caches across runs).
	freshRequire: boolean?,
}

type Realm = "server" | "client"

type Hook = (ctx: { [any]: any }) -> ()

type Node = {
	kind: "group" | "test",
	name: string,
	parent: Node?,
	fn: Hook?,
	children: { Node },
	beforeAll: { Hook },
	afterAll: { Hook },
	beforeEach: { Hook },
	afterEach: { Hook },
	skip: boolean,
	only: boolean,
	realm: Realm?,
}

local Runner = {}

Runner.Fakes = Fakes

local function newNode(kind, name, parent): Node
	return {
		kind = kind,
		name = name,
		parent = parent,
		children = {},
		beforeAll = {},
		afterAll = {},
		beforeEach = {},
		afterEach = {},
		skip = false,
		only = false,
	}
end

-- Builds the API table passed to a spec function and collects its tree.
local function collect(specFn: (any) -> (), suiteName: string): (Node, boolean)
	local root = newNode("group", suiteName, nil)
	local current = root
	local anyOnly = false

	local function addGroup(name: string, body: () -> (), skip: boolean, only: boolean, realm: Realm?)
		local group = newNode("group", name, current)
		group.skip, group.only, group.realm = skip, only, realm
		anyOnly = anyOnly or only
		table.insert(current.children, group)
		local previous = current
		current = group
		body()
		current = previous
	end

	local function addTest(name: string, fn: Hook, skip: boolean, only: boolean, realm: Realm?)
		local test = newNode("test", name, current)
		test.fn, test.skip, test.only, test.realm = fn, skip, only, realm
		anyOnly = anyOnly or only
		table.insert(current.children, test)
	end

	local api = {
		Assert = Assert,
		Mock = Mock,
		spy = Mock.spy,
		stub = Mock.stub,
		Fakes = Fakes,
		track = Cleanup.track,
		create = Cleanup.create,
		describeServer = function(name, body) addGroup(name, body, false, false, "server") end,
		describeClient = function(name, body) addGroup(name, body, false, false, "client") end,
		itServer = function(name, fn) addTest(name, fn, false, false, "server") end,
		itClient = function(name, fn) addTest(name, fn, false, false, "client") end,
		describe = function(name, body) addGroup(name, body, false, false) end,
		describeSkip = function(name, body) addGroup(name, body, true, false) end,
		describeOnly = function(name, body) addGroup(name, body, false, true) end,
		it = function(name, fn) addTest(name, fn, false, false) end,
		itSkip = function(name, fn) addTest(name, fn, true, false) end,
		itOnly = function(name, fn) addTest(name, fn, false, true) end,
		beforeAll = function(fn) table.insert(current.beforeAll, fn) end,
		afterAll = function(fn) table.insert(current.afterAll, fn) end,
		beforeEach = function(fn) table.insert(current.beforeEach, fn) end,
		afterEach = function(fn) table.insert(current.afterEach, fn) end,
	}

	specFn(api)
	return root, anyOnly
end

local function errorHandler(err: any): any
	if Assert.isFailure(err) then
		return err
	end
	return { message = tostring(err), traceback = debug.traceback(nil, 2) }
end

-- Runs fn in its own thread so yielding tests work and can time out.
-- Returns nil on success, or { message, traceback, isAssertionFailure? }.
local function runGuarded(fn: () -> (), timeout: number): any
	local done, problem = false, nil
	local thread = task.spawn(function()
		local ok, err = xpcall(fn, errorHandler)
		if not ok then
			problem = err
		end
		done = true
	end)
	local started = os.clock()
	while not done do
		if os.clock() - started > timeout then
			task.cancel(thread)
			return { message = `timed out after {timeout}s`, traceback = "" }
		end
		task.wait()
	end
	return problem
end

local function fullName(node: Node): string
	local parts = {}
	local n: Node? = node
	while n and n.parent do -- the root is the suite itself, so stop before it
		table.insert(parts, 1, n.name)
		n = n.parent
	end
	return table.concat(parts, " > ")
end

local function isFocused(node: Node): boolean
	local n: Node? = node
	while n do
		if n.only then
			return true
		end
		n = n.parent
	end
	return false
end

local function isSkipped(node: Node): boolean
	local n: Node? = node
	while n do
		if n.skip then
			return true
		end
		n = n.parent
	end
	return false
end

-- A test marked "server" only runs where RunService:IsServer() is true, and
-- likewise for "client". Client tests also need a running game, because in
-- Studio edit mode IsClient() is true but there is no LocalPlayer.
local function wrongRealm(node: Node): boolean
	local n: Node? = node
	while n do
		if n.realm == "server" and not RunService:IsServer() then
			return true
		elseif n.realm == "client" and not (RunService:IsClient() and RunService:IsRunning()) then
			return true
		end
		n = n.parent
	end
	return false
end

local function runHooks(hooks: { Hook }, ctx, timeout): any
	for _, hook in hooks do
		local problem = runGuarded(function() hook(ctx) end, timeout)
		if problem then
			return problem
		end
	end
	return nil
end

local function runTest(node: Node, state, ctx): TestResult
	local name = fullName(node)
	local started = os.clock()

	-- beforeEach hooks run outermost first, afterEach innermost first.
	local chain = {}
	local n: Node? = node.parent
	while n do
		table.insert(chain, 1, n)
		n = n.parent
	end

	local problem
	for _, group in chain do
		problem = runHooks(group.beforeEach, ctx, state.timeout)
		if problem then
			break
		end
	end
	if not problem then
		problem = runGuarded(function() (node.fn :: Hook)(ctx) end, state.timeout)
	end
	for i = #chain, 1, -1 do
		local afterProblem = runHooks(chain[i].afterEach, ctx, state.timeout)
		problem = problem or afterProblem
	end
	Mock.restoreAll()
	Cleanup.run()

	local result: TestResult = {
		name = name,
		status = "passed",
		duration = os.clock() - started,
	}
	if problem then
		result.status = if Assert.isFailure(problem) then "failed" else "errored"
		result.message = problem.message
		result.traceback = problem.traceback
	end
	return result
end

local function runGroup(group: Node, state, results: { TestResult }, inheritedCtx)
	-- Each group gets a context that inherits from its parent's (beforeAll data).
	local groupCtx = setmetatable({}, { __index = inheritedCtx })
	local setupProblem = runHooks(group.beforeAll, groupCtx, state.timeout)

	for _, child in group.children do
		if child.kind == "group" then
			if setupProblem then
				-- Don't run anything nested; report every test inside as errored.
				local function markErrored(node: Node)
					for _, c in node.children do
						if c.kind == "group" then
							markErrored(c)
						else
							table.insert(results, {
								name = fullName(c),
								status = "errored",
								message = "beforeAll failed: " .. setupProblem.message,
								duration = 0,
							})
						end
					end
				end
				markErrored(child)
			else
				runGroup(child, state, results, groupCtx)
			end
		else
			local name = fullName(child)
			local excluded = (state.anyOnly and not isFocused(child))
				or (state.filter and not string.find(name, state.filter))
			if isSkipped(child) or excluded or wrongRealm(child) then
				table.insert(results, { name = name, status = "skipped", duration = 0 })
			elseif setupProblem then
				table.insert(results, {
					name = name,
					status = "errored",
					message = "beforeAll failed: " .. setupProblem.message,
					traceback = setupProblem.traceback,
					duration = 0,
				})
			else
				-- Fresh per-test context, falling back to the group's beforeAll data.
				local ctx = setmetatable({}, { __index = groupCtx })
				table.insert(results, runTest(child, state, ctx))
			end
		end
	end

	runHooks(group.afterAll, groupCtx, state.timeout)
end

local function notify(reporters: { any }, event: string, ...: any)
	for _, reporter in reporters do
		local handler = reporter[event]
		if handler then
			handler(reporter, ...)
		end
	end
end

function Runner.findSpecs(roots: { Instance }): { ModuleScript }
	local specs = {}
	for _, root in roots do
		local candidates = root:GetDescendants()
		table.insert(candidates, root)
		for _, inst in candidates do
			if inst:IsA("ModuleScript") and inst.Name:match("%.spec$") then
				table.insert(specs, inst)
			end
		end
	end
	table.sort(specs, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)
	return specs
end

function Runner.run(options: Options?): RunResults
	local opts: Options = options or {}
	local reporters = opts.reporters or {}
	local roots = opts.roots or { game:GetService("ServerScriptService"), game:GetService("ReplicatedStorage") }
	local runStarted = os.clock()

	-- Collect every suite first so itOnly/describeOnly works across files.
	local suites = {}
	local anyOnly = false
	for _, module in Runner.findSpecs(roots) do
		local suiteName = module.Name:gsub("%.spec$", "")
		local ok, specFn
		if opts.freshRequire then
			-- Clone next to the original so script.Parent-relative requires still resolve.
			local clone = module:Clone()
			clone.Name = module.Name .. ".__luaunit"
			clone.Parent = module.Parent
			ok, specFn = pcall(require, clone)
			clone:Destroy()
		else
			ok, specFn = pcall(require, module)
		end
		if not ok or typeof(specFn) ~= "function" then
			local reason = if ok then "spec module must return a function" else tostring(specFn)
			table.insert(suites, { name = suiteName, loadError = reason })
		else
			local collected, root, hasOnly = pcall(collect, specFn, suiteName)
			if collected then
				anyOnly = anyOnly or hasOnly
				table.insert(suites, { name = suiteName, root = root })
			else
				table.insert(suites, { name = suiteName, loadError = tostring(root) })
			end
		end
	end

	local state = { timeout = opts.timeout or 5, filter = opts.filter, anyOnly = anyOnly }
	local runResults: RunResults = { suites = {}, passed = 0, failed = 0, errored = 0, skipped = 0, duration = 0 }

	notify(reporters, "onRunStart")
	for _, suite in suites do
		local started = os.clock()
		local tests: { TestResult } = {}
		notify(reporters, "onSuiteStart", suite.name)
		if suite.loadError then
			table.insert(tests, { name = "<load>", status = "errored", message = suite.loadError, duration = 0 })
		else
			runGroup(suite.root, state, tests, nil)
		end
		local suiteResult: SuiteResult = { name = suite.name, tests = tests, duration = os.clock() - started }
		for _, t in tests do
			runResults[t.status] += 1
			notify(reporters, "onTestEnd", suite.name, t)
		end
		table.insert(runResults.suites, suiteResult)
		notify(reporters, "onSuiteEnd", suiteResult)
	end
	runResults.duration = os.clock() - runStarted
	notify(reporters, "onRunEnd", runResults)

	return runResults
end

return Runner
