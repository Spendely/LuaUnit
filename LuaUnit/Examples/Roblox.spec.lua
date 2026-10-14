-- Example: testing data saving, remotes, players and Instances.

return function(t)
	local describe, it, Assert, Fakes = t.describe, t.it, t.Assert, t.Fakes

	-- A typical PlayerData module. The DataStoreService is a field so tests
	-- can swap in the fake; in the game it stays the real service.
	local PlayerData = { DataStoreService = nil :: any }

	function PlayerData.load(player)
		local store = PlayerData.DataStoreService:GetDataStore("PlayerData")
		local ok, data = pcall(store.GetAsync, store, "user_" .. player.UserId)
		if not ok then
			return nil, data
		end
		return data or { coins = 0, inventory = {} }
	end

	function PlayerData.addCoins(player, amount)
		local store = PlayerData.DataStoreService:GetDataStore("PlayerData")
		return store:UpdateAsync("user_" .. player.UserId, function(old)
			old = old or { coins = 0, inventory = {} }
			old.coins += amount
			return old
		end)
	end

	describe("Data saving", function()
		t.beforeEach(function(ctx)
			ctx.service = Fakes.DataStoreService.new()
			ctx.store = ctx.service:GetDataStore("PlayerData")
			ctx.player = Fakes.Player.new({ UserId = 42 })
			PlayerData.DataStoreService = ctx.service
		end)

		it("gives new players default data", function(ctx)
			Assert.deepEquals(PlayerData.load(ctx.player), { coins = 0, inventory = {} })
		end)

		it("loads existing data", function(ctx)
			ctx.store:seed({ user_42 = { coins = 50, inventory = { "Sword" } } })
			Assert.equals(PlayerData.load(ctx.player).coins, 50)
		end)

		it("updates coins with UpdateAsync", function(ctx)
			PlayerData.addCoins(ctx.player, 10)
			PlayerData.addCoins(ctx.player, 5)
			Assert.equals(ctx.store:peek("user_42").coins, 15)
			Assert.equals(ctx.store:callCount("UpdateAsync"), 2)
		end)

		it("handles DataStore outages", function(ctx)
			ctx.store:failNext("GetAsync")
			local data, err = PlayerData.load(ctx.player)
			Assert.isNil(data)
			Assert.notNil(err)
		end)

		it("rejects data Roblox can't save", function(ctx)
			Assert.throws(function()
				ctx.store:SetAsync("bad", { part = Instance.new("Part") })
			end, "cannot be stored")
		end)

		it("loaded tables are copies, not live references", function(ctx)
			ctx.store:seed({ user_42 = { coins = 1 } })
			local data = PlayerData.load(ctx.player)
			data.coins = 999
			Assert.equals(ctx.store:peek("user_42").coins, 1)
		end)

		it("sorts leaderboards", function(ctx)
			local board = ctx.service:GetOrderedDataStore("Wins")
			board:seed({ a = 3, b = 10, c = 7 })
			local top = board:GetSortedAsync(false, 2):GetCurrentPage()
			Assert.equals(top[1].key, "b")
			Assert.equals(top[2].key, "c")
		end)
	end)

	describe("Remotes", function()
		it("server handler receives the player and arguments", function()
			local remote = Fakes.Remote.event("BuyItem")
			local player = Fakes.Player.new()
			local handler = t.spy()
			remote.OnServerEvent:Connect(handler)

			remote:FireServerAs(player, "Sword", 1)
			Assert.eventually(function()
				Assert.calledWith(handler, player, "Sword", 1)
			end)
		end)

		it("rejects functions, which can't be sent over the network", function()
			local remote = Fakes.Remote.event()
			Assert.throws(function()
				remote:FireServerAs(Fakes.Player.new(), function() end)
			end, "can't be sent")
		end)

		it("RemoteFunctions return the handler's values", function()
			local getCoins = Fakes.Remote.func()
			getCoins.OnServerInvoke = function(player)
				return player.UserId * 10
			end
			Assert.equals(getCoins:InvokeServerAs(Fakes.Player.new({ UserId = 3 })), 30)
		end)
	end)

	describe("Instances and events", function()
		it("t.create cleans up after the test", function()
			local part = t.create("Part", { Name = "TestPart", Anchored = true, Parent = workspace })
			Assert.isA(part, "BasePart")
			Assert.notNil(workspace:FindFirstChild("TestPart"))
		end)

		it("previous test's part is gone", function()
			Assert.isNil(workspace:FindFirstChild("TestPart"))
		end)

		it("detects Roblox events firing", function()
			local value = t.create("IntValue")
			local newValue = Assert.fires(value.Changed, function()
				value.Value = 5
			end)
			Assert.equals(newValue, 5)
		end)

		it("detects kicks", function()
			local player = Fakes.Player.new()
			player:Kick("cheating")
			Assert.calledWith(player.Kick, player, "cheating") -- method calls pass self
		end)
	end)
end
