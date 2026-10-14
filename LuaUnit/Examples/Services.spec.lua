-- Example: clock, MemoryStore, purchases and teleports.

return function(t)
	local describe, it, Assert, Fakes = t.describe, t.it, t.Assert, t.Fakes

	describe("Clock", function()
		-- A cooldown module that takes its clock as a dependency.
		local function newCooldown(clock, seconds)
			local readyAt = 0
			return function()
				if clock:now() < readyAt then
					return false
				end
				readyAt = clock:now() + seconds
				return true
			end
		end

		it("tests cooldowns without waiting", function()
			local clock = Fakes.Clock.new()
			local tryAttack = newCooldown(clock, 5)
			Assert.isTrue(tryAttack())
			Assert.isFalse(tryAttack())
			clock:advance(5)
			Assert.isTrue(tryAttack())
		end)

		it("runs delayed callbacks in order when advanced", function()
			local clock = Fakes.Clock.new()
			local order = {}
			clock:delay(2, function() table.insert(order, "second") end)
			clock:delay(1, function() table.insert(order, "first") end)
			local cancelled = clock:delay(1.5, function() table.insert(order, "never") end)
			cancelled.cancel()
			clock:advance(10)
			Assert.deepEquals(order, { "first", "second" })
		end)

		it("resumes threads waiting on the clock", function()
			local clock = Fakes.Clock.new()
			local done = false
			task.spawn(function()
				clock:wait(30)
				done = true
			end)
			clock:advance(29)
			Assert.isFalse(done)
			clock:advance(1)
			Assert.isTrue(done)
		end)
	end)

	describe("MemoryStore", function()
		t.beforeEach(function(ctx)
			ctx.clock = Fakes.Clock.new()
			ctx.memory = Fakes.MemoryStoreService.new({ clock = ctx.clock })
		end)

		it("expires sorted map entries", function(ctx)
			local map = ctx.memory:GetSortedMap("Lobby")
			map:SetAsync("bob", { elo = 1200 }, 30)
			Assert.equals(map:GetAsync("bob").elo, 1200)
			ctx.clock:advance(31)
			Assert.isNil(map:GetAsync("bob"))
		end)

		it("ranges by sort key", function(ctx)
			local map = ctx.memory:GetSortedMap("Elo")
			map:SetAsync("a", true, 60, 1500)
			map:SetAsync("b", true, 60, 900)
			map:SetAsync("c", true, 60, 1200)
			local top = map:GetRangeAsync(Enum.SortDirection.Descending, 2)
			Assert.equals(top[1].key, "a")
			Assert.equals(top[2].key, "c")
		end)

		it("queues hide read items until removed or timed out", function(ctx)
			local queue = ctx.memory:GetQueue("Jobs", 10)
			queue:AddAsync("job1", 60)
			Assert.deepEquals((queue:ReadAsync(1)), { "job1" })
			Assert.deepEquals((queue:ReadAsync(1)), {}) -- invisible while being processed
			ctx.clock:advance(10)
			local items, id = queue:ReadAsync(1) -- reappears: it was never removed
			Assert.deepEquals(items, { "job1" })
			queue:RemoveAsync(id)
			Assert.equals(queue:size(), 0)
		end)
	end)

	describe("Purchases", function()
		local COINS_PRODUCT, VIP_PASS = 1001, 2002

		-- A shop that must not grant the same purchase twice.
		local function newShop(coins)
			local granted = {}
			return function(receipt)
				if granted[receipt.PurchaseId] then
					return Enum.ProductPurchaseDecision.PurchaseGranted
				end
				coins[receipt.PlayerId] = (coins[receipt.PlayerId] or 0) + 100
				granted[receipt.PurchaseId] = true
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
		end

		it("grants developer products once, even if Roblox retries", function()
			local coins = {}
			local market = Fakes.MarketplaceService.new({ products = { [COINS_PRODUCT] = { PriceInRobux = 25 } } })
			market.ProcessReceipt = newShop(coins)
			local player = Fakes.Player.new({ UserId = 7 })

			local decision, receipt = market:simulatePurchase(player, COINS_PRODUCT)
			Assert.equals(decision, Enum.ProductPurchaseDecision.PurchaseGranted)
			market:simulatePurchase(player, COINS_PRODUCT, { purchaseId = receipt.PurchaseId })
			Assert.equals(coins[7], 100)
		end)

		it("checks game pass ownership", function()
			local market = Fakes.MarketplaceService.new({ gamePasses = { [7] = { VIP_PASS } } })
			Assert.isTrue(market:UserOwnsGamePassAsync(7, VIP_PASS))
			Assert.isFalse(market:UserOwnsGamePassAsync(8, VIP_PASS))
		end)

		it("records purchase prompts", function()
			local market = Fakes.MarketplaceService.new()
			local player = Fakes.Player.new()
			market:PromptGamePassPurchase(player, VIP_PASS)
			Assert.calledWith(market.PromptGamePassPurchase, market, player, VIP_PASS)
		end)
	end)

	describe("Teleports", function()
		local ARENA = 123456

		it("records who was sent where", function()
			local teleport = Fakes.TeleportService.new()
			local a, b = Fakes.Player.new(), Fakes.Player.new()
			teleport:TeleportAsync(ARENA, { a, b })
			Assert.equals(#teleport:playersSentTo(ARENA), 2)
		end)

		it("simulates teleport failures", function()
			local teleport = Fakes.TeleportService.new()
			local failed = t.spy()
			teleport.TeleportInitFailed:Connect(failed)
			teleport:failNext("TeleportAsync", "server full")
			Assert.throws(function()
				teleport:TeleportAsync(ARENA, { Fakes.Player.new() })
			end, "server full")
			Assert.called(failed)
		end)
	end)
end
