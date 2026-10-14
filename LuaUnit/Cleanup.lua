--!strict
-- Per-test cleanup. Anything tracked here is destroyed/disconnected after
-- the current test, even if the test fails.
--   t.track(x)               -- Instance, connection, function, or { Destroy }
--   t.create("Part", props)  -- Instance.new + props, tracked automatically

local Cleanup = {}

local tracked: { any } = {}

function Cleanup.track<T>(item: T): T
	table.insert(tracked, item)
	return item
end

function Cleanup.create(className: string, props: { [string]: any }?): Instance
	local instance = Instance.new(className)
	local parent
	for key, value in props or {} do
		if key == "Parent" then
			parent = value -- set last, as recommended for performance
		else
			(instance :: any)[key] = value
		end
	end
	instance.Parent = parent
	return Cleanup.track(instance)
end

local function release(item: any)
	local kind = typeof(item)
	if kind == "Instance" then
		item:Destroy()
	elseif kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		task.cancel(item)
	elseif kind == "table" then
		if item.Destroy then
			item:Destroy()
		elseif item.Disconnect then
			item:Disconnect()
		end
	end
end

-- Called by the runner after every test. Releases in reverse order.
function Cleanup.run()
	for i = #tracked, 1, -1 do
		local ok, err = pcall(release, tracked[i])
		if not ok then
			warn("LuaUnit cleanup error: " .. tostring(err))
		end
	end
	table.clear(tracked)
end

return Cleanup
