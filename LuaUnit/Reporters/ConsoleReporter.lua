--!strict
-- Prints results to the Output window. Failures go through warn() so they stand out.

local ConsoleReporter = {}
ConsoleReporter.__index = ConsoleReporter

local ICONS = { passed = "[PASS]", failed = "[FAIL]", errored = "[ERR ]", skipped = "[SKIP]" }

function ConsoleReporter.new(options: { verbose: boolean? }?)
	return setmetatable({ verbose = options and options.verbose or false }, ConsoleReporter)
end

function ConsoleReporter:onSuiteStart(suiteName: string)
	print(`LuaUnit ▸ {suiteName}`)
end

function ConsoleReporter:onTestEnd(_suiteName: string, test)
	local line = `  {ICONS[test.status]} {test.name} ({string.format("%.3f", test.duration)}s)`
	if test.status == "failed" or test.status == "errored" then
		warn(line .. "\n      " .. tostring(test.message))
		if self.verbose and test.traceback and test.traceback ~= "" then
			warn(test.traceback)
		end
	elseif test.status == "passed" or self.verbose then
		print(line)
	end
end

function ConsoleReporter:onRunEnd(results)
	local summary = string.format(
		"LuaUnit ▸ %d passed, %d failed, %d errored, %d skipped in %.3fs",
		results.passed,
		results.failed,
		results.errored,
		results.skipped,
		results.duration
	)
	if results.failed + results.errored > 0 then
		warn(summary)
	else
		print(summary)
	end
end

return ConsoleReporter
