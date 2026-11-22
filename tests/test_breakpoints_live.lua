dofile(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)) .. '/bootstrap.lua')
local dap = require('dap')
if vim.env.DAP_TRACE then dap.set_log_level('TRACE') end
require('dap-extra').setup()
local extra = require('dap-extra').breakpoints
assert(extra.available, 'Needs the dap-ui fork for dapui.breakpoints')
dap.adapters.cppdbg = {
	id = 'cppdbg', type = 'executable',
	command = vim.fn.stdpath('data') .. '/mason/bin/OpenDebugAD7',
}
-- Start the debuggee without an integrated terminal: in headless `nvim -l`
-- that launch can hang while a FileType autocommand exists (REPL history).
dap.defaults.cppdbg.force_external_terminal = true
-- `script` gives the debuggee the terminal it expects.
dap.defaults.cppdbg.external_terminal = {
	command = '/bin/sh', args = { '-c', 'exec script -qfc "$*" /dev/null >/dev/null', 'sh' },
}
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local file = directory .. '/chain.c'
vim.fn.writefile({
	'int counter = 0;',
	'__attribute__((noinline)) void parent(void) { counter++; }',
	'__attribute__((noinline)) void child(void) { counter += 2; }',
	'int main(void) {',
	'  for (int i = 0; i < 3; i++) child();',
	'  parent();',
	'  for (int i = 0; i < 5; i++) child();',
	'  return counter;',
	'}',
}, file)
local compiled = vim.system({ 'cc', '-g', '-O0', file, '-o', directory .. '/chain' }):wait()
assert(compiled.code == 0, compiled.stderr)
vim.cmd.edit(file)
local buf = vim.api.nvim_get_current_buf()
local breakpoints = require('dap.breakpoints')
breakpoints.set({}, buf, 2)
breakpoints.set({}, buf, 3)
-- The parent runs a command and continues; the child waits on it and turns
-- off again after two hits.
vim.g.parent_hits = 0
extra.set_command('let g:parent_hits += 1', {}, buf, 2)
extra.set_parents({ { buf = buf, line = 2 } }, buf, 3)
extra.set_reset(2, buf, 3)

local stops = 0
dap.listeners.after.event_stopped.chain_check = function() stops = stops + 1 end
dap.run({
	name = 'chained breakpoints', type = 'cppdbg', request = 'launch',
	program = directory .. '/chain', cwd = directory, MIMode = 'gdb',
	miDebuggerPath = '/usr/bin/gdb',
})
local child_stops, handled, last_frame = {}, 0, nil
while true do
	local done = vim.wait(20000, function()
		local session = dap.session()
		if not session then return true end
		local frame = session.current_frame
		-- A new frame object means nvim-dap finished loading this stop.
		return stops > handled and frame ~= nil and frame ~= last_frame and frame.line == 3
			and session.stopped_thread_id ~= nil
	end, 20)
	assert(done, 'Timed out waiting for a child stop or the end of the program')
	if not dap.session() then break end
	handled, last_frame = stops, dap.session().current_frame
	child_stops[#child_stops + 1] = vim.g.parent_hits
	dap.continue()
	assert(#child_stops <= 5, 'Child breakpoint did not turn off')
end
assert(vim.g.parent_hits == 1, 'Parent command ran ' .. tostring(vim.g.parent_hits) .. ' times')
assert(vim.deep_equal(child_stops, { 1, 1 }),
	'Child must stop only after the parent, twice: ' .. vim.inspect(child_stops))
dap.listeners.after.event_stopped.chain_check = nil
vim.fn.delete(directory, 'rf')
print('Live GDB command and chained breakpoint checks passed')
