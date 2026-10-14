--!strict
--[[
	LuaUnit — a JUnit-style test framework for Roblox Luau.

	In Studio, this file is the source of the "LuaUnit" ModuleScript; every
	other file is a child ModuleScript with the same name (Reporters is a Folder).

	Usage:
		local LuaUnit = require(path.to.LuaUnit)
		local results = LuaUnit.run({ roots = { game.ServerScriptService } })
]]

local Runner = require(script.Runner)

local LuaUnit = {
	Assert = require(script.Assert),
	Mock = require(script.Mock),
	Cleanup = require(script.Cleanup),
	Fakes = Runner.Fakes,
	Runner = Runner,
	ConsoleReporter = require(script.Reporters.ConsoleReporter),
	JUnitXmlReporter = require(script.Reporters.JUnitXmlReporter),
}

-- Runs all *.spec modules under `roots`. Uses a ConsoleReporter if no reporters are given.
function LuaUnit.run(options: Runner.Options?): Runner.RunResults
	local opts: Runner.Options = options or {}
	if not opts.reporters then
		opts.reporters = { LuaUnit.ConsoleReporter.new() }
	end
	return Runner.run(opts)
end

return LuaUnit
