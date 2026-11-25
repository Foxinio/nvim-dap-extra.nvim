dofile(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)) .. '/bootstrap.lua')
-- keep_stop_at_entry leaves the launch configuration's stopAtEntry alone.
require('dap-extra').setup({ keep_stop_at_entry = true })
local configure = require('dap').listeners.on_config['dap-extra']
assert(configure({ type = 'cppdbg', request = 'launch', stopAtEntry = true }).stopAtEntry == true)
assert(configure({ type = 'cppdbg', request = 'launch' }).stopAtEntry == nil)
print('keep_stop_at_entry checks passed')
