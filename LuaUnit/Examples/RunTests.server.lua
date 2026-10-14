-- Put this in a Script (ServerScriptService) to run all tests when the game starts.
-- The JUnit XML report is written to a StringValue named "LuaUnitReport"
-- in ServerStorage, so an external CI tool can read it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local LuaUnit = require(ReplicatedStorage:WaitForChild("LuaUnit"))

local report = ServerStorage:FindFirstChild("LuaUnitReport") or Instance.new("StringValue")
report.Name = "LuaUnitReport"
report.Parent = ServerStorage

local results = LuaUnit.run({
	roots = { ServerScriptService, ReplicatedStorage },
	timeout = 5,
	-- filter = "Math", -- only run tests whose full name matches this pattern
	reporters = {
		LuaUnit.ConsoleReporter.new({ verbose = false }),
		LuaUnit.JUnitXmlReporter.new({ target = report }),
	},
})

if results.failed + results.errored > 0 then
	warn("LuaUnit: tests failed")
end
