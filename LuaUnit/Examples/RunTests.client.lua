-- Put this in a LocalScript (StarterPlayerScripts) to run client-side tests
-- on game start. itServer/describeServer tests are skipped here, and
-- itClient/describeClient tests are skipped by the server runner.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LuaUnit = require(ReplicatedStorage:WaitForChild("LuaUnit"))

local player = Players.LocalPlayer
local playerScripts = player:WaitForChild("PlayerScripts")

LuaUnit.run({
	roots = { ReplicatedStorage, playerScripts },
	timeout = 5,
	reporters = { LuaUnit.ConsoleReporter.new() },
})
