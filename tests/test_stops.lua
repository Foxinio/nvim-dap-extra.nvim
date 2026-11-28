-- The condition guard and hit matching need only nvim-dap.
DAP_EXTRA_WITHOUT_DAPUI = true
dofile(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)) .. '/bootstrap.lua')
local notify = vim.notify
vim.notify = function() end
require('dap-extra').setup()
vim.notify = notify
local dap = require('dap')
local dap_breakpoints = require('dap.breakpoints')
local stops = require('dap-extra.stops')

local file = vim.fn.tempname() .. '.c'
vim.fn.writefile({ 'int main(void) {', '  int i = 0;', '  i++;', '  i++;', '  return i;', '}' }, file)
vim.cmd.edit(file)
local buf = vim.api.nvim_get_current_buf()
dap_breakpoints.set({ condition = 'i == 4' }, buf, 3)
dap_breakpoints.set({}, buf, 4)
dap_breakpoints.set_state(buf, { id = 21, line = 3, verified = true })

local reported, requests, result = {}, {}, 'false'
stops.subscribe('test', function(_, thread_id, hits)
	reported[#reported + 1] = { thread = thread_id, lines = vim.tbl_map(function(hit) return hit.line end, hits) }
end)
local session = setmetatable({ steps = {} }, {
	__index = {
		request = function(self, command, args, callback)
			requests[#requests + 1] = command
			if command == 'stackTrace' then
				callback(nil, { stackFrames = { { id = 7, line = 3, source = { path = file } } } })
			elseif command == 'evaluate' then
				assert(args.expression == 'i == 4' and args.frameId == 7 and args.context == 'watch', vim.inspect(args))
				if result == 'error' then
					callback({ message = 'No symbol "i" in current context.' }, nil)
				else
					callback(nil, { result = result })
				end
			elseif command == 'continue' then
				self.steps[#self.steps + 1] = 'continue-request'
				callback(nil, {})
			end
		end,
		_step = function(self, step) self.steps[#self.steps + 1] = step end,
	},
})
local function reset()
	reported, requests, session.steps = {}, {}, {}
end
-- A stop matched from nvim-dap's stackTrace response, as OpenDebugAD7 needs.
local function frame_stop(line)
	session.stopped_thread_id = 1
	dap.listeners.after.event_stopped['dap-extra.stops'](session, { reason = 'breakpoint', threadId = 1 })
	dap.listeners.before.stackTrace['dap-extra.stops'](session, nil,
		{ stackFrames = { { id = 7, line = line, source = { path = file } } } }, { threadId = 1, startFrame = 0 })
end

-- False condition: continued, not reported.
frame_stop(3)
assert(vim.deep_equal(session.steps, { 'continue' }), vim.inspect(session.steps))
assert(#reported == 0, vim.inspect(reported))

-- `0` counts as false too (C comparisons).
reset(); result = '0'
frame_stop(3)
assert(vim.deep_equal(session.steps, { 'continue' }) and #reported == 0)

-- True condition, or an evaluation error: the stop is kept and reported.
for _, value in ipairs({ 'true', '1', 'error' }) do
	reset(); result = value
	frame_stop(3)
	assert(#session.steps == 0, value .. ': ' .. vim.inspect(session.steps))
	assert(vim.deep_equal(reported, { { thread = 1, lines = { 3 } } }), value .. ': ' .. vim.inspect(reported))
end

-- No condition: reported straight away, nothing evaluated.
reset(); result = 'false'
frame_stop(4)
assert(not vim.tbl_contains(requests, 'evaluate'), vim.inspect(requests))
assert(vim.deep_equal(reported, { { thread = 1, lines = { 4 } } }))

-- Hits from hitBreakpointIds: the top frame is requested to evaluate in.
reset()
session.stopped_thread_id = 1
dap.listeners.after.event_stopped['dap-extra.stops'](session, { reason = 'breakpoint', threadId = 1, hitBreakpointIds = { 21 } })
assert(vim.deep_equal(requests, { 'stackTrace', 'evaluate' }), vim.inspect(requests))
assert(vim.deep_equal(session.steps, { 'continue' }) and #reported == 0)

-- Other stop reasons are ignored.
reset()
dap.listeners.after.event_stopped['dap-extra.stops'](session, { reason = 'step', threadId = 1 })
assert(#requests == 0 and #reported == 0)

-- recheck_conditions = false: hits are reported without evaluating.
stops.setup(false)
reset()
frame_stop(3)
assert(not vim.tbl_contains(requests, 'evaluate') and #session.steps == 0)
assert(vim.deep_equal(reported, { { thread = 1, lines = { 3 } } }))
stops.setup(true)

vim.fn.delete(file)
print('Breakpoint stop and condition guard checks passed')
