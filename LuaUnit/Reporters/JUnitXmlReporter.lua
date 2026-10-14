--!strict
-- Builds a JUnit XML report. After the run, read reporter.xml, or pass
-- `target` (a StringValue) to have the XML written into it for CI to pick up.

local Util = require(script.Parent.Parent.Util)

local JUnitXmlReporter = {}
JUnitXmlReporter.__index = JUnitXmlReporter

function JUnitXmlReporter.new(options: { target: StringValue? }?)
	return setmetatable({ xml = "", target = options and options.target }, JUnitXmlReporter)
end

local function attr(value: any): string
	return '"' .. Util.xmlEscape(tostring(value)) .. '"'
end

function JUnitXmlReporter:onRunEnd(results)
	local out = { '<?xml version="1.0" encoding="UTF-8"?>' }
	table.insert(out, string.format(
		"<testsuites tests=%s failures=%s errors=%s skipped=%s time=%s>",
		attr(results.passed + results.failed + results.errored + results.skipped),
		attr(results.failed), attr(results.errored), attr(results.skipped),
		attr(string.format("%.3f", results.duration))
	))

	for _, suite in results.suites do
		local counts = { failed = 0, errored = 0, skipped = 0 }
		for _, t in suite.tests do
			if counts[t.status] then
				counts[t.status] += 1
			end
		end
		table.insert(out, string.format(
			"  <testsuite name=%s tests=%s failures=%s errors=%s skipped=%s time=%s>",
			attr(suite.name), attr(#suite.tests), attr(counts.failed), attr(counts.errored),
			attr(counts.skipped), attr(string.format("%.3f", suite.duration))
		))
		for _, t in suite.tests do
			local open = string.format(
				"    <testcase classname=%s name=%s time=%s",
				attr(suite.name), attr(t.name), attr(string.format("%.3f", t.duration))
			)
			if t.status == "passed" then
				table.insert(out, open .. "/>")
			else
				table.insert(out, open .. ">")
				if t.status == "skipped" then
					table.insert(out, "      <skipped/>")
				else
					local tag = if t.status == "failed" then "failure" else "error"
					table.insert(out, string.format(
						"      <%s message=%s>%s</%s>",
						tag, attr(t.message or ""), Util.xmlEscape(t.traceback or ""), tag
					))
				end
				table.insert(out, "    </testcase>")
			end
		end
		table.insert(out, "  </testsuite>")
	end
	table.insert(out, "</testsuites>")

	self.xml = table.concat(out, "\n")
	if self.target then
		self.target.Value = self.xml
	end
end

return JUnitXmlReporter
