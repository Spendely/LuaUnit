-- Example: spies, stubs, and server/client-only tests.

return function(t)
	local describe, it, Assert = t.describe, t.it, t.Assert

	-- Stand-in for a real game module.
	local DataStore = {}
	function DataStore.save(key, value)
		error("would hit the real DataStore")
	end

	local function savePlayer(name, coins)
		return DataStore.save("player_" .. name, coins)
	end

	describe("Spies", function()
		it("records calls and arguments", function()
			local onHit = t.spy()
			onHit(10, "sword")
			onHit(5, "bow")
			Assert.calledTimes(onHit, 2)
			Assert.calledWith(onHit, 5, "bow")
		end)

		it("can return fixed values", function()
			local roll = t.spy():returns(6)
			Assert.equals(roll(), 6)
		end)
	end)

	describe("Stubs", function()
		it("replace a module function during the test", function()
			local save = t.stub(DataStore, "save"):returns(true)
			Assert.isTrue(savePlayer("Bob", 100))
			Assert.calledWith(save, "player_Bob", 100)
		end)

		it("are restored automatically after each test", function()
			Assert.throws(function()
				savePlayer("Bob", 100)
			end, "real DataStore")
		end)
	end)

	t.describeServer("Server only", function()
		it("can see ServerStorage", function()
			Assert.notNil(game:GetService("ServerStorage"))
		end)
	end)

	t.itClient("client only: has a LocalPlayer", function()
		Assert.notNil(game:GetService("Players").LocalPlayer)
	end)
end
