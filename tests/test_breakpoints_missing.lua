DAP_EXTRA_WITHOUT_DAPUI = true
local root = dofile(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)) .. '/bootstrap.lua').root
local notify, messages = vim.notify, {}
vim.notify = function(message, level) messages[#messages + 1] = { message, level } end
assert(not pcall(require, 'dapui.breakpoints'), 'This check needs the dap-ui fork off the runtimepath')
require('dap-extra').setup()
require('dap-extra').setup()
local extra = require('dap-extra').breakpoints
assert(not extra.available)
assert(#messages == 1, vim.inspect(messages))
assert(messages[1][1] == extra.unavailable_message and messages[1][2] == vim.log.levels.WARN)
-- Everything else still works.
local repl = require('dap.repl')
assert(repl.commands.custom_commands.bt and vim.tbl_contains(repl.commands.into, 's'))
assert(require('dap').listeners.on_config['dap-extra'], 'cppdbg defaults missing')
local dap = require('dap')
local session = dap.session
local selected = { id = 9, source = { path = root .. '/tests/test.lua' }, line = 2, column = 1 }
dap.session = function() return { id = 1, current_frame = selected } end
require('dap-extra').local_frame()
assert(vim.api.nvim_buf_get_name(0) == selected.source.path)
dap.session = session
-- The feature's commands report it is disabled and do not raise.
for _, command in ipairs({ 'DapCommandBreakpoint echo 1', 'DapChainBreakpoint', 'DapBreakpointReset 2' }) do
	messages = {}
	vim.cmd(command)
	assert(#messages == 1 and messages[1][1] == extra.unavailable_message, command .. ': ' .. vim.inspect(messages))
end
assert(vim.tbl_isempty(extra.parents()))
-- Turned off on purpose: no warning.
messages = {}
extra.setup(false)
assert(#messages == 0, vim.inspect(messages))
vim.notify = notify
print('Graceful fallback without dapui.breakpoints checks passed')
