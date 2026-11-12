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
	'__attribute__((noinline)) void fail() { assert(false); }',
	'int main() {',
	'  try { throw 42; } catch (int) {}',
	'  fail();',
	'}',
}, file)
local compiled = vim.system({ 'c++', '-g', '-O0', file, '-o', directory .. '/exceptions' }):wait()
assert(compiled.code == 0, compiled.stderr)
local stops = 0
dap.listeners.after.event_stopped.exception_check = function() stops = stops + 1 end
local function wait_for_stop(count)
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
	if count % 2 == 0 then
		assert(vim.iter(trace.stackFrames):any(function(frame) return frame.name:find('fail', 1, true) ~= nil end),
			'Assertion failure frame is unavailable')
	end
	assert(session.config.setupCommands[1].text == 'catch throw')
	assert(#session.config.setupCommands == 2, 'Restart duplicated defaults')
end
dap.run({
	name = 'exception defaults', type = 'cppdbg', request = 'launch',
	program = directory .. '/exceptions', cwd = directory, MIMode = 'gdb',
	miDebuggerPath = '/usr/bin/gdb',
})
wait_for_stop(1)
dap.continue()
wait_for_stop(2)
dap.restart()
wait_for_stop(3)
dap.continue()
wait_for_stop(4)
dap.continue()
assert(vim.wait(10000, function() return dap.session() == nil end, 20), 'Fatal signal did not exit')
dap.listeners.after.event_stopped.exception_check = nil
vim.fn.delete(directory, 'rf')
print('Live GDB throw, assertion, calling stack and restart defaults checks passed')
