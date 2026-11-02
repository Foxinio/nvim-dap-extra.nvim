local root = dofile(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)) .. '/bootstrap.lua').root
local dap, dapui = require('dap'), require('dapui')
local original_session, stopped = dap.session, nil
dap.session = function() return stopped end
local ui = require('dap-extra.ui')
local breakpoints = require('dap.breakpoints')
require('dap-extra').setup()
require('dap-extra.panes').setup()
local util = require('dapui.util')
local open_buf, render_before = util.open_buf, dapui.elements.breakpoints.render
require('dap-extra.panes').setup()
assert(util.open_buf == open_buf and dapui.elements.breakpoints.render == render_before)
dap.defaults.fallback.switchbuf = ui.jump
vim.cmd.edit(root .. '/tests/test_panes.lua')
local buffer = vim.api.nvim_get_current_buf()
ui.open()
local source = vim.api.nvim_get_current_win()
breakpoints.set({ condition = 'x > 0', hit_condition = '2', log_message = 'x={x}' }, buffer, 2)
local pane = dapui.elements.breakpoints
local function render() pane.render(); vim.wait(30, function() return false end) end
local function select_breakpoint()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_get_buf(win) == pane.buffer() then vim.api.nvim_set_current_win(win); break end
	end
	local lines = vim.api.nvim_buf_get_lines(pane.buffer(), 0, -1, false)
	for index, text in ipairs(lines) do
		if text:match('^%s+2%s') then vim.api.nvim_win_set_cursor(0, { index, 0 }); return end
	end
	error('Breakpoint row missing')
end
local function press(key)
	local mapping = vim.fn.maparg(key, 'n', false, true)
	assert(mapping.buffer == 1 and mapping.callback, 'Missing buffer-local binding: ' .. key)
	mapping.callback()
end
render()
select_breakpoint()
press('t')
render()
assert(#(breakpoints.get(buffer)[buffer] or {}) == 0)
select_breakpoint()
press('t')
render()
local restored = assert(breakpoints.get(buffer)[buffer])[1]
assert(restored.condition == 'x > 0' and restored.hitCondition == '2' and restored.logMessage == 'x={x}')
select_breakpoint()
press('<CR>')
assert(vim.api.nvim_get_current_win() == source and vim.api.nvim_win_get_cursor(0)[1] == 2)
select_breakpoint()
press('t')
render()
select_breakpoint()
press('d')
render()
assert(#(breakpoints.get(buffer)[buffer] or {}) == 0)
assert(not table.concat(vim.api.nvim_buf_get_lines(pane.buffer(), 0, -1, false), '\n'):match('x > 0'), 'Disabled breakpoint was not removed')
breakpoints.set({}, buffer, 3)
render()
local frame = { id = 12, name = 'pane-test', line = 4, column = 1, source = { path = vim.api.nvim_buf_get_name(buffer) } }
stopped = { stopped_thread_id = 1, threads = { [1] = { id = 1, name = 'main', stopped = true, frames = { frame } } } }
stopped._frame_set = function(self, selected)
	self.current_frame = selected
	ui.jump(buffer, selected.line, selected.column)
end
for _, listener in pairs(dap.listeners.after.threads) do
	listener(stopped, nil, { threads = { stopped.threads[1] } }, {}, 0)
end
pane = dapui.elements.stacks
render()
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	if vim.api.nvim_win_get_buf(win) == pane.buffer() then vim.api.nvim_set_current_win(win); break end
end
for index, text in ipairs(vim.api.nvim_buf_get_lines(pane.buffer(), 0, -1, false)) do
	if text:find('pane-test', 1, true) then vim.api.nvim_win_set_cursor(0, { index, 0 }); break end
end
press('<CR>')
assert(stopped.current_frame == frame and vim.api.nvim_get_current_win() == source)
assert(vim.api.nvim_win_get_cursor(source)[1] == 4)
dap.session = original_session
breakpoints.clear()
print('Debugger pane bindings, source routing and disabled breakpoint removal passed')
