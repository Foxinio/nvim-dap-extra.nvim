dofile(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)) .. '/bootstrap.lua')
local dap = require('dap')
require('dap-extra').setup()
dap.adapters.cppdbg = {
	id = 'cppdbg', type = 'executable',
	command = vim.fn.stdpath('data') .. '/mason/bin/OpenDebugAD7',
}
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local file = directory .. '/exceptions.cpp'
vim.fn.writefile({
	'#include <cassert>',
	'#include <pthread.h>',
	'#include <signal.h>',
	'__attribute__((noinline)) void signal_thread() { pthread_kill(pthread_self(), 0); }',
	'__attribute__((noinline)) void fail() { assert(false); }',
	'int main() {',
	'  try { throw 42; } catch (int) {}',
	'  signal_thread();',
	'  fail();',
	'}',
}, file)
local compiled = vim.system({ 'c++', '-pthread', '-g', '-O0', file, '-o', directory .. '/exceptions' }):wait()
assert(compiled.code == 0, compiled.stderr)
local stops = 0
dap.listeners.after.event_stopped.exception_check = function() stops = stops + 1 end
local function wait_for_stop(count, caller)
	assert(vim.wait(15000, function()
		local session = dap.session()
		return stops >= count and session and session.current_frame ~= nil
	end, 20), 'Expected exception/assertion stop ' .. count)
	local session = dap.session()
	local trace, failure
	session:request('stackTrace', { threadId = session.stopped_thread_id }, function(err, response)
		failure, trace = err, response
	end)
	assert(vim.wait(5000, function() return trace ~= nil or failure ~= nil end, 20))
	assert(not failure, vim.inspect(failure))
	assert(vim.iter(trace.stackFrames):any(function(frame) return frame.name:find('main', 1, true) ~= nil end),
		'Calling stack is unavailable')
	if caller then
		assert(vim.iter(trace.stackFrames):any(function(frame) return frame.name:find(caller, 1, true) ~= nil end),
			'Current calling frame is unavailable: ' .. caller)
		local stacks = require('dapui').elements.stacks
		assert(vim.wait(5000, function()
			local lines = table.concat(vim.api.nvim_buf_get_lines(stacks.buffer(), 0, -1, false), '\n')
			return lines:find(caller, 1, true) ~= nil
				and (caller ~= 'signal_thread' or lines:find('pthread_kill', 1, true) ~= nil)
		end, 20), 'Stacks pane still shows the previous stop instead of ' .. caller)
	end
	assert(session.config.setupCommands[1].text == 'catch throw')
	assert(#session.config.setupCommands == 3, 'Restart duplicated defaults')
end
dap.run({
	name = 'exception defaults', type = 'cppdbg', request = 'launch',
	program = directory .. '/exceptions', cwd = directory, MIMode = 'gdb',
	miDebuggerPath = '/usr/bin/gdb',
})
wait_for_stop(1)
dap.continue()
wait_for_stop(2, 'signal_thread')
dap.continue()
wait_for_stop(3, 'fail')
dap.restart()
wait_for_stop(4)
dap.continue()
wait_for_stop(5, 'signal_thread')
dap.continue()
wait_for_stop(6, 'fail')
dap.continue()
wait_for_stop(7, 'fail')
dap.continue()
assert(vim.wait(10000, function() return dap.session() == nil end, 20), 'Fatal signal did not exit')
dap.listeners.after.event_stopped.exception_check = nil
vim.fn.delete(directory, 'rf')
print('Live GDB throw, pthread_kill, assertion, Stacks refresh and restart defaults checks passed')
