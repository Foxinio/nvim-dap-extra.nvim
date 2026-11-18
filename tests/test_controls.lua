dofile(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)) .. '/bootstrap.lua')
require('dap-extra').setup()
local dap = require('dap')
local repl = require('dap.repl')
local session, terminate, notify = dap.session, dap.terminate, vim.notify
local active = {}
dap.session = function() return active end
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
dap.repl.open()
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'dap-repl' then vim.api.nvim_set_current_win(win); break end
end
assert(vim.bo.filetype == 'dap-repl', 'REPL window missing')
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
print('Asynchronous REPL quit and run checks passed')
