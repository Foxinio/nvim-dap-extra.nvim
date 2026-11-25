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
local file = directory .. '/printers.cpp'
vim.fn.writefile({
	'#include <string>',
	'#include <vector>',
	'int main() {',
	'  std::vector<int> v{1, 2, 3};',
	'  std::string s = "hello";',
	'  return static_cast<int>(v.size() + s.size());',
	'}',
}, file)
local compiled = vim.system({ 'c++', '-g', '-O0', file, '-o', directory .. '/printers' }):wait()
assert(compiled.code == 0, compiled.stderr)
vim.cmd.edit(file)
require('dap.breakpoints').set({}, vim.api.nvim_get_current_buf(), 6)
dap.run({
	name = 'pretty printers', type = 'cppdbg', request = 'launch',
	program = directory .. '/printers', cwd = directory, MIMode = 'gdb',
	miDebuggerPath = '/usr/bin/gdb',
})
assert(vim.wait(20000, function()
	local session = dap.session()
	return session and session.current_frame and session.current_frame.line == 6
end, 20), 'Did not stop at the breakpoint')
local session = dap.session()
local function request(command, args)
	local result, failure
	session:request(command, args, function(err, response) failure, result = err, response end)
	assert(vim.wait(5000, function() return result ~= nil or failure ~= nil end, 20), command .. ' timed out')
	assert(not failure, vim.inspect(failure))
	return result
end
local scopes = request('scopes', { frameId = session.current_frame.id }).scopes
local locals = {}
for _, variable in ipairs(request('variables', { variablesReference = scopes[1].variablesReference }).variables) do
	locals[variable.name] = variable
end
assert(locals.v and locals.s, vim.inspect(vim.tbl_keys(locals)))
local children = request('variables', { variablesReference = locals.v.variablesReference }).variables
local names = vim.tbl_map(function(child) return child.name end, children)
print(('v = %s, children %s; s = %s'):format(locals.v.value, table.concat(names, ' '), locals.s.value))
assert(#children == 3 and children[1].value == '1' and children[3].value == '3',
	'std::vector is not pretty-printed: ' .. vim.inspect(names))
assert(locals.s.value:find('hello', 1, true), 'std::string is not pretty-printed: ' .. locals.s.value)
dap.terminate()
assert(vim.wait(10000, function() return dap.session() == nil end, 20), 'Session did not end')
vim.fn.delete(directory, 'rf')
print('Live GDB pretty-printer checks passed')
