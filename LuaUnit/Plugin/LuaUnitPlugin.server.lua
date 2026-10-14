-- Studio plugin: adds a "Run Tests" toolbar button.
-- Install: put this Script in a Folder, right-click > "Save as Local Plugin...".
-- It runs tests in edit mode against the LuaUnit ModuleScript in ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local toolbar = plugin:CreateToolbar("LuaUnit")
local runButton = toolbar:CreateButton("Run Tests", "Run all *.spec tests", "rbxassetid://4458901886")
runButton.ClickableWhenViewportHidden = true

local running = false

local function runTests()
	if running then
		return
	end
	local source = ReplicatedStorage:FindFirstChild("LuaUnit")
	if not source then
		warn("LuaUnit: no 'LuaUnit' ModuleScript found in ReplicatedStorage")
		return
	end

	running = true
	-- require() caches per ModuleScript, so require a fresh clone each time
	-- to pick up edits made since the last run.
	local clone = source:Clone()
	clone.Name = "LuaUnit.__plugin"
	clone.Parent = source.Parent

	local ok, err = pcall(function()
		local LuaUnit = require(clone)
		LuaUnit.run({
			roots = { ServerScriptService, ReplicatedStorage, StarterPlayer },
			freshRequire = true,
			reporters = { LuaUnit.ConsoleReporter.new({ verbose = true }) },
		})
	end)

	clone:Destroy()
	running = false
	runButton:SetActive(false)
	if not ok then
		warn("LuaUnit: run failed: " .. tostring(err))
	end
end

runButton.Click:Connect(function()
	task.spawn(runTests)
end)
