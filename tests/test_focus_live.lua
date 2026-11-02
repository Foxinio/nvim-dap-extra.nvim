local root = dofile(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)) .. '/bootstrap.lua').root
local dap = require('dap')
local ui = require('dap-extra.ui')
local repl = require('dap.repl')
require('dapui').setup()
require('dap-extra.repl').setup()
dap.defaults.fallback.switchbuf = ui.jump
dap.listeners.after.event_initialized.focus_check = ui.open
dap.adapters.cppdbg = { id = 'cppdbg', type = 'executable', command = vim.fn.stdpath('data') .. '/mason/bin/OpenDebugAD7' }
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local file = directory .. '/focus.c'
vim.fn.writefile({
	'__attribute__((noinline)) int inner(int value) {',
	'  value += 1;',
	'  value += 2;',
	'  return value;',
	'}',
	'int main(void) {',
	'  return inner(3);',
	'}',
}, file)
assert(vim.system({ 'cc', '-g', '-O0', file, '-o', directory .. '/focus' }):wait().code == 0)
vim.cmd.edit(file)
vim.cmd.vsplit()
local origin = vim.api.nvim_get_current_win()
local layout = vim.fn.winlayout()
require('dap.breakpoints').set({}, vim.api.nvim_get_current_buf(), 2)
ui.action(function()
	dap.run({ name = 'focus check', type = 'cppdbg', request = 'launch', program = directory .. '/focus',
		cwd = directory, MIMode = 'gdb', miDebuggerPath = '/usr/bin/gdb', stopAtEntry = false })
end)()
local function stopped()
	return dap.session() and dap.session().current_frame ~= nil
end
assert(vim.wait(15000, stopped, 20), 'Initial breakpoint did not stop')
local source = vim.api.nvim_get_current_win()
local debug_tab = vim.api.nvim_get_current_tabpage()
repl.open()
local repl_win
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(debug_tab)) do
	if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'dap-repl' then repl_win = win end
end
vim.api.nvim_set_current_win(assert(repl_win))
local function focused() assert(vim.api.nvim_get_current_win() == repl_win, 'REPL lost focus') end
repl.execute('up')
assert(vim.wait(5000, function() return stopped() and dap.session().current_frame.name:find('main', 1, true) end, 20),
	vim.inspect(dap.session() and dap.session().current_frame))
focused()
assert(vim.api.nvim_win_get_cursor(source)[1] == 7)
repl.execute('frame 0')
assert(vim.wait(5000, function() return stopped() and dap.session().current_frame.name:find('inner', 1, true) end, 20))
focused()
repl.execute('p value')
vim.wait(100, function() return false end)
focused()
local line = dap.session().current_frame.line
repl.execute('n')
assert(vim.wait(5000, function() return stopped() and dap.session().current_frame.line ~= line end, 20))
focused()
vim.api.nvim_set_current_win(origin)
local frame = dap.session().current_frame
ui.local_frame()
assert(vim.api.nvim_get_current_win() == origin and vim.deep_equal(vim.fn.winlayout(), layout))
assert(dap.session().current_frame == frame and vim.api.nvim_win_get_cursor(0)[1] == frame.line)
require('dap.ui.widgets').hover('value')
vim.wait(200, function() return false end)
assert(vim.api.nvim_get_current_tabpage() == vim.api.nvim_win_get_tabpage(origin))
assert(vim.deep_equal(vim.fn.winlayout(), layout))
ui.setup()
vim.cmd('DapClean')
assert(vim.wait(5000, function() return dap.session() == nil end, 20))
assert(#vim.api.nvim_tabpage_list_wins(debug_tab) == 1)
vim.fn.delete(directory, 'rf')
print('Live GDB REPL stepping, frame navigation, hover and local source checks passed')
