dofile(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)) .. '/bootstrap.lua')
require('dap-extra').setup({ dapui = { layouts = {
	{ elements = { 'scopes', 'stacks' }, position = 'left', size = 32 },
	{ elements = { 'repl', 'console' }, position = 'bottom', size = 8 },
} } })
local dap, dapui = require('dap'), require('dapui')
local repl = require('dap.repl')
local original_tab = vim.api.nvim_get_current_tabpage()
local original_layout = vim.fn.winlayout()
vim.cmd('DapReset')
local debug_tab, source = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_win()
local source_buffer, cursor = vim.api.nvim_win_get_buf(source), vim.api.nvim_win_get_cursor(source)
local breakpoints = vim.deepcopy(require('dap.breakpoints').get())
local function pane(name)
	local buffer = dapui.elements[name].buffer()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(debug_tab)) do
		if vim.api.nvim_win_get_buf(win) == buffer then return win end
	end
	error('Missing pane: ' .. name)
end
local function sizes()
	local result = {}
	for _, name in ipairs({ 'scopes', 'stacks', 'repl', 'console' }) do
		local win = pane(name)
		result[name] = { vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win) }
	end
	return result
end
local expected = sizes()
assert(expected.scopes[1] == 32 and expected.repl[2] == 8)
vim.api.nvim_win_set_width(pane('scopes'), 45)
vim.api.nvim_win_set_height(pane('repl'), 14)
assert(not vim.deep_equal(sizes(), expected))
local session, terminate, notify = dap.session, dap.terminate, vim.notify
local active = {}
dap.session = function() return active end
dap.terminate = function() error('Reset must not terminate debugging') end
vim.api.nvim_set_current_tabpage(original_tab)
vim.cmd('DapReset')
assert(vim.api.nvim_get_current_tabpage() == debug_tab and vim.api.nvim_get_current_win() == source)
assert(vim.deep_equal(sizes(), expected) and dap.session() == active)
assert(vim.api.nvim_win_get_buf(source) == source_buffer)
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(source), cursor))
assert(vim.deep_equal(require('dap.breakpoints').get(), breakpoints))
vim.api.nvim_set_current_win(pane('repl'))
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'dap> ' })
local repl_win = vim.api.nvim_get_current_win()
vim.cmd('DapReset')
assert(vim.api.nvim_get_current_win() == repl_win and vim.deep_equal(sizes(), expected))
vim.api.nvim_win_close(pane('stacks'), true)
vim.cmd('DapReset')
assert(pane('stacks') and vim.deep_equal(sizes(), expected))
vim.api.nvim_win_close(pane('console'), true)
vim.cmd('DapReset')
assert(vim.api.nvim_get_current_win() == pane('repl'), 'Reset must restore REPL focus')
assert(vim.deep_equal(sizes(), expected), vim.inspect({ actual = sizes(), expected = expected }))
local messages, pending = {}, nil
vim.notify = function(message) messages[#messages + 1] = message end
dap.terminate = function(opts)
	assert(opts.disconnect_args.terminateDebuggee == true)
	pending = opts.on_done
end
local before = vim.fn.winlayout()
for _, command in ipairs({ 'q', 'quit' }) do
	messages, pending = {}, nil
	repl.execute(command)
	assert(pending and #messages == 0, 'Quit must return before completion')
	assert(vim.deep_equal(vim.fn.winlayout(), before), 'Quit must not clean up panes directly')
	pending()
	assert(#messages == 0, 'Completion notification must be scheduled')
	assert(vim.wait(1000, function() return #messages == 1 end))
	assert(messages[1] == 'Debugging stopped')
end
messages = {}
repl.execute('quit')
pending('adapter refused termination')
assert(vim.wait(1000, function() return #messages == 1 end))
assert(messages[1] == 'Could not stop debugging: adapter refused termination')
dap.session = function() return nil end
dap.terminate = function() error('No session to terminate') end
repl.execute('q')
assert(vim.wait(1000, function() return messages[#messages] == 'No active debug session' end))
assert(messages[#messages] == 'No active debug session')
local restart, run_last = dap.restart, dap.run_last
local restarts, starts = 0, 0
dap.restart = function() restarts = restarts + 1 end
dap.run_last = function() starts = starts + 1 end
for _, command in ipairs({ 'r', 'run' }) do
	dap.session = function() return active end
	repl.execute(command)
	assert(vim.wait(1000, function() return restarts == starts + 1 end))
	dap.session = function() return nil end
	repl.execute(command)
	assert(vim.wait(1000, function() return starts == restarts end))
end
assert(restarts == 2 and starts == 2)
vim.api.nvim_set_current_win(pane('repl'))
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'dap> ' })
assert(vim.fn.maparg('<CR>', 'i', false, true).callback, 'REPL Enter mapping is missing')
vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(0), 0 })
vim.api.nvim_feedkeys(vim.keycode('Arun<Ignore><CR><Esc>'), 'xt', false)
assert(vim.wait(1000, function() return starts == 3 end), vim.inspect(vim.api.nvim_buf_get_lines(0, 0, -1, false)))
local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(vim.tbl_contains(lines, 'dap> run'), vim.inspect(lines))
local wrapped_execute = repl.execute
require('dap-extra.repl').setup()
assert(repl.execute == wrapped_execute, 'Repeated REPL setup must not stack wrappers')
dap.restart, dap.run_last = restart, run_last
dap.session, dap.terminate, vim.notify = session, terminate, notify
vim.api.nvim_set_current_tabpage(original_tab)
assert(vim.deep_equal(vim.fn.winlayout(), original_layout))
print('Debugger reset and asynchronous REPL quit checks passed')
