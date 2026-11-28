dofile(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)) .. '/bootstrap.lua')
local dap = require('dap')
require('dap-extra').setup()
dap.adapters.cppdbg = {
	id = 'cppdbg', type = 'executable',
	command = vim.fn.stdpath('data') .. '/mason/bin/OpenDebugAD7',
}
-- Start the debuggee without an integrated terminal: in headless `nvim -l`
-- that launch can hang while a FileType autocommand exists (REPL history).
-- `script` gives the debuggee the terminal it expects.
dap.defaults.cppdbg.force_external_terminal = true
dap.defaults.cppdbg.external_terminal = {
	command = '/bin/sh', args = { '-c', 'exec script -qfc "$*" /dev/null >/dev/null', 'sh' },
}
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local file = directory .. '/condition.c'
vim.fn.writefile({
	'#include <unistd.h>',
	'int main(void) {',
	'  int sum = 0;',
	'  usleep(1500000);',
	'  for (int i = 0; i < 6; i++) {',
	'    sum += i;',
	'  }',
	'  return sum;',
	'}',
}, file)
local compiled = vim.system({ 'cc', '-g', '-O0', file, '-o', directory .. '/condition' }):wait()
assert(compiled.code == 0, compiled.stderr)
vim.cmd.edit(file)
local buf = vim.api.nvim_get_current_buf()
require('dap.breakpoints').set({}, buf, 6)
local stops = 0
dap.listeners.after.event_stopped.condition_check = function() stops = stops + 1 end
dap.run({
	name = 'condition', type = 'cppdbg', request = 'launch',
	program = directory .. '/condition', cwd = directory, MIMode = 'gdb',
	miDebuggerPath = '/usr/bin/gdb',
})
-- While the program sleeps (running), add a condition the way the Breakpoints
-- pane does. cppdbg adds the conditional breakpoint at once but deletes the old
-- unconditional one only at the next stop.
assert(vim.wait(15000, function()
	local session = dap.session()
	return session and session.initialized
end, 20), 'Session did not start')
vim.wait(500, function() return false end)
require('dapui.breakpoints').set(buf, 6, 'condition', 'i == 4')

local seen, handled, last = {}, 0, nil
while true do
	local done = vim.wait(20000, function()
		local session = dap.session()
		if not session then return true end
		local frame = session.current_frame
		return stops > handled and frame ~= nil and frame ~= last and session.stopped_thread_id ~= nil
	end, 20)
	assert(done, 'Timed out waiting for a stop or the end of the program')
	local session = dap.session()
	if not session then break end
	handled, last = stops, session.current_frame
	-- Only count stops that stay stopped; a stop the guard continues is skipped.
	vim.wait(500, function() return false end)
	session = dap.session()
	if not session then break end
	if session.stopped_thread_id == nil or session.current_frame ~= last then goto next_stop end
	local value
	session:request('evaluate', { expression = 'i', frameId = last.id, context = 'watch' }, function(_, response)
		value = response and response.result or '?'
	end)
	assert(vim.wait(5000, function() return value ~= nil end, 20))
	seen[#seen + 1] = ('%d(i=%s)'):format(last.line, value)
	dap.continue()
	assert(#seen <= 6, 'Too many stops: ' .. table.concat(seen, ','))
	::next_stop::
end
assert(vim.deep_equal(seen, { '6(i=4)' }), 'Condition was not respected: ' .. table.concat(seen, ','))
dap.listeners.after.event_stopped.condition_check = nil
vim.fn.delete(directory, 'rf')
print('Live GDB condition-while-running checks passed')
