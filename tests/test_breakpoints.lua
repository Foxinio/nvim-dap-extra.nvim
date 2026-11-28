dofile(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)) .. '/bootstrap.lua')
local dap = require('dap')
local dap_breakpoints = require('dap.breakpoints')
require('dap-extra').setup()
local extra = require('dap-extra').breakpoints
local store = require('dapui.breakpoints')
assert(extra.available, 'dapui.breakpoints should be found')
assert(not package.loaded.dapui, 'Only dapui.breakpoints may be loaded, not dap-ui itself')
local function listener_count()
	local count = 0
	for _, when in ipairs({ dap.listeners.before, dap.listeners.after }) do
		for _, event in pairs(when) do
			for _ in pairs(event) do count = count + 1 end
		end
	end
	return count
end
local listeners = listener_count()
require('dap-extra').setup()
extra.setup()
assert(listener_count() == listeners, 'Repeated setup added listeners')
for _, command in ipairs({ 'DapCommandBreakpoint', 'DapChainBreakpoint', 'DapBreakpointReset' }) do
	assert(vim.fn.exists(':' .. command) == 2, command .. ' is missing')
end

local file = vim.fn.tempname() .. '.c'
vim.fn.writefile({ 'int a;', 'parent();', 'x;', 'child();', 'second_child();', 'other_parent();' }, file)
vim.cmd.edit(file)
local buf = vim.api.nvim_get_current_buf()
for _, line in ipairs({ 2, 4, 5, 6 }) do dap_breakpoints.set({}, buf, line) end
dap_breakpoints.set({ condition = 'x > 1' }, buf, 4)

-- A fake session that records what nvim-dap would send to the adapter.
local frames = {}
local condition_result = '1'
local session = setmetatable({ children = {}, steps = {}, threads = {} }, {
	__index = {
		set_breakpoints = function(self, bps)
			self.sent = self.sent or {}
			for bufnr, list in pairs(bps) do
				self.sent[bufnr] = vim.tbl_map(function(bp) return bp.line end, list)
			end
		end,
		request = function(self, command, args, callback)
			if command == 'stackTrace' then
				callback(nil, { stackFrames = { frames[args.threadId] } })
			elseif command == 'evaluate' then
				-- Conditions re-checked on breakpoint stops hold unless a test says not.
				callback(nil, { result = condition_result })
			elseif command == 'continue' then
				self.steps[#self.steps + 1] = 'continue-request'
				callback(nil, {})
			end
		end,
		_step = function(self, step) self.steps[#self.steps + 1] = step end,
	},
})
local sessions = dap.sessions
dap.sessions = function() return { session } end
local function initialize()
	for _, name in ipairs({ 'dapui.breakpoints', 'dap-extra.breakpoints' }) do
		dap.listeners.before.event_initialized[name](session, {})
	end
	session:set_breakpoints(dap_breakpoints.get())
end
local function sent()
	return table.concat(session.sent[buf], ',')
end
local function stop(body)
	session.stopped_thread_id = body.threadId
	body.reason = body.reason or 'breakpoint'
	dap.listeners.after.event_stopped['dap-extra.stops'](session, body)
end
-- nvim-dap fetches the stopped thread's stack; dap-extra reads that response.
local function hit_line(line)
	frames[1] = { id = 1, line = line, source = { path = file } }
	stop({ threadId = 1 })
	dap.listeners.before.stackTrace['dap-extra.stops'](session, nil, { stackFrames = { frames[1] } },
		{ threadId = 1, startFrame = 0 })
	-- nvim-dap sets the new frame after the before-listeners ran.
	session.current_frame = { id = 1 }
end

initialize()
assert(sent() == '2,4,5,6', sent())

-- Chain: child (4) waits on parent (2); second child (5) waits on 2 or 6.
extra.set_parents({ { buf = buf, line = 2 } }, buf, 4)
extra.set_parents({ { buf = buf, line = 2 }, { buf = buf, line = 6 } }, buf, 5)
assert(sent() == '2,6', 'Chained breakpoints must be held back: ' .. sent())
assert(#dap_breakpoints.get(buf)[buf] == 4, 'Held-back breakpoints stay in nvim-dap')
assert(store.breakpoint(buf, 4).condition == 'x > 1', 'Condition kept while held back')
assert(not store.is_active(buf, 4) and not store.is_active(buf, 5))
local parents = extra.parents(buf, 5)
assert(#parents == 2 and parents[1].line == 2 and parents[2].line == 6, vim.inspect(parents))

-- A parent hit reported through hitBreakpointIds turns the child on.
dap_breakpoints.set_state(buf, { id = 11, line = 2, verified = true })
stop({ threadId = 1, hitBreakpointIds = { 11 } })
assert(sent() == '2,4,5,6', 'Parent hit must send both children: ' .. sent())

-- New run: chained breakpoints are off again.
initialize()
assert(sent() == '2,6', 'New session must reset chains: ' .. sent())

-- Either parent works; matched from the stopped frame when no ids are sent.
hit_line(6)
assert(sent() == '2,5,6', 'Second parent must turn on 5 before nvim-dap shows the frame: ' .. sent())

-- If nvim-dap does not fetch the stack, dap-extra asks for the top frame itself.
initialize()
frames[1] = { id = 1, line = 6, source = { path = file } }
stop({ threadId = 1 })
assert(sent() == '2,6')
assert(vim.wait(3000, function() return sent() == '2,5,6' end), 'Fallback stackTrace must match: ' .. sent())

-- Turns off after N hits.
initialize()
extra.set_reset(2, buf, 4)
hit_line(2)
assert(vim.wait(1000, function() return store.is_active(buf, 4) end))
hit_line(4)
assert(vim.wait(100, function() return false end) == false and store.is_active(buf, 4), 'One hit is not enough')
hit_line(4)
assert(vim.wait(1000, function() return not store.is_active(buf, 4) end), 'Two hits must turn it off')
assert(not sent():find('4', 1, true), sent())
hit_line(2)
assert(vim.wait(1000, function() return store.is_active(buf, 4) end), 'Parent turns it on again')

-- Command breakpoint: runs and continues; with stop, stays stopped.
vim.g.hit = 0
extra.set_command('let g:hit += 1', {}, buf, 6)
assert(store.get(buf, 6, 'command') == 'let g:hit += 1')
session.steps = {}
hit_line(6)
assert(vim.wait(1000, function() return vim.g.hit == 1 and #session.steps == 1 end), vim.inspect(session.steps))
assert(session.steps[1] == 'continue')
extra.set_command('let g:hit += 1', { stop = true }, buf, 6)
hit_line(6)
assert(vim.wait(1000, function() return vim.g.hit == 2 end))
vim.wait(50, function() return false end)
assert(#session.steps == 1, 'stop = true must not continue')
-- A command breakpoint whose condition is false when it stops (a stale stop
-- from cppdbg) is continued without running the command.
store.set(buf, 6, 'condition', 'x == 9')
condition_result, session.steps = '0', {}
hit_line(6)
vim.wait(100, function() return false end)
assert(vim.g.hit == 2 and vim.deep_equal(session.steps, { 'continue' }), vim.inspect(session.steps))
store.set(buf, 6, 'condition', nil)
condition_result = '1'
-- A failing command is reported and does not raise.
local notify, messages = vim.notify, {}
vim.notify = function(message) messages[#messages + 1] = message end
extra.set_command('nosuchcommand', {}, buf, 6)
hit_line(6)
assert(vim.wait(1000, function() return #messages > 0 end))
assert(messages[1]:find('Breakpoint command failed', 1, true), messages[1])
vim.cmd('DapBreakpointReset soon')
assert(messages[#messages]:find('restart', 1, true), messages[#messages])
vim.notify = notify
extra.set_command('', {}, buf, 6)
assert(store.get(buf, 6, 'command') == nil)

-- Clearing everything drops the child's record.
extra.set_reset('restart', buf, 4)
extra.set_parents({}, buf, 4)
local ns = vim.api.nvim_get_namespaces().dapui_breakpoint_properties
assert(#vim.api.nvim_buf_get_extmarks(buf, ns, { 3, 0 }, { 3, -1 }, {}) == 0, 'Record must be dropped')
assert(store.is_active(buf, 4))

-- Picker via vim.ui.select: toggle a parent, then Done.
local select = vim.ui.select
package.loaded.telescope = nil
local real_require = require
require = function(name)
	if name == 'telescope' then error('no telescope') end
	return real_require(name)
end
local picks = { 1, 'done' }
vim.ui.select = function(items, opts, choice)
	local pick = table.remove(picks, 1)
	if pick == 'done' then return choice(items[#items]) end
	assert(opts.format_item(items[pick]):find('^%[ %]'), opts.format_item(items[pick]))
	choice(items[pick])
end
vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.cmd('DapChainBreakpoint')
require = real_require
vim.ui.select = select
assert(#extra.parents(buf, 4) == 1 and extra.parents(buf, 4)[1].line == 2, vim.inspect(extra.parents(buf, 4)))

-- :DapCommandBreakpoint! on a line without a breakpoint adds one.
vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.cmd('DapCommandBreakpoint! echo "here"')
assert(store.breakpoint(buf, 3) and store.get(buf, 3, 'command') == 'echo "here"' and store.get(buf, 3, 'stop'))

dap.sessions = sessions
vim.fn.delete(file)
print('Command and chained breakpoint checks passed')
