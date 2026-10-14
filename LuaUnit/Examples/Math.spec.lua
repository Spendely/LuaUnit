-- Example spec. Any ModuleScript whose name ends in ".spec" is picked up.
-- It returns a function that receives the test API.

return function(t)
	local describe, it, Assert = t.describe, t.it, t.Assert

	describe("Math", function()
		t.beforeEach(function(ctx)
			ctx.numbers = { 1, 2, 3 }
		end)

		it("adds numbers", function()
			Assert.equals(1 + 1, 2)
		end)

		it("gets a fresh context each test", function(ctx)
			table.insert(ctx.numbers, 4)
			Assert.equals(#ctx.numbers, 4)
		end)

		it("compares tables deeply", function(ctx)
			Assert.deepEquals(ctx.numbers, { 1, 2, 3 })
		end)

		it("compares floats and vectors approximately", function()
			Assert.near(0.1 + 0.2, 0.3)
			Assert.near(Vector3.new(1, 2, 3), Vector3.new(1, 2, 3.000001))
		end)

		it("detects errors", function()
			Assert.throws(function()
				error("boom")
			end, "boom")
		end)

		it("supports yielding tests", function()
			task.wait(0.1)
			Assert.isTrue(true)
		end)

		t.itSkip("is skipped", function()
			Assert.fail("should never run")
		end)
	end)
end
