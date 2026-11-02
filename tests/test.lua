local root = dofile(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)) .. '/bootstrap.lua').root
local dap, repl = require('dap'), require('dap.repl')
require('dap-extra').setup({ dapui = { floating = { border = 'single' } } })
assert(require('dapui.config').floating.border == 'single')
assert(require('dapui.config').icons.current_frame == '*')
local function listener_count()
	local count = 0
	for _, when in ipairs({ dap.listeners.before, dap.listeners.after }) do
		for _, event in pairs(when) do
			for _ in pairs(event) do count = count + 1 end
		end
	end
	return count
end
local listeners = listener_count()
local render = require('dapui').elements.breakpoints.render
vim.wait(20, function() return false end)
require('dap-extra').setup()
assert(listener_count() == listeners and require('dapui').elements.breakpoints.render == render)
local session = dap.session
local execute = repl.execute
local forwarded = {}
dap.session = function() return { config = { type = 'cppdbg' } } end
repl.execute = function(command) forwarded[#forwarded + 1] = command end
repl.commands.custom_commands.gdb('info locals')
assert(vim.deep_equal(forwarded, { '-exec info locals' }))
assert(repl.commands.custom_commands.pn == nil)
assert(vim.tbl_contains(repl.commands.into, 's') and vim.tbl_contains(repl.commands.out, 'fin'))
repl.execute = execute
local frames = {
	{ id = 100, name = 'inner', source = { path = 'inner.cpp' }, line = 10 },
	{ id = 7, name = 'caller', source = { path = 'caller.cpp' }, line = 20 },
	{ id = 42, name = 'main', source = { path = 'main.cpp' }, line = 30 },
}
local stopped = { stopped_thread_id = 1, threads = { { frames = frames } }, current_frame = frames[1] }
stopped._frame_set = function(self, frame) self.current_frame = frame end
dap.session = function() return stopped end
local original_append, output = repl.append, {}
repl.append = function(text) output[#output + 1] = text end
local commands = repl.commands.custom_commands
commands.up('2')
assert(stopped.current_frame == frames[3])
commands.down('')
assert(stopped.current_frame == frames[2])
commands.f('0')
assert(stopped.current_frame == frames[1])
commands.up('99')
assert(stopped.current_frame == frames[3])
commands.down('99')
assert(stopped.current_frame == frames[1])
commands.frame('2')
commands.frame('99')
commands.down('invalid')
assert(stopped.current_frame == frames[3])
commands.frame('')
assert(output[#output]:find('#2 main at main.cpp:30', 1, true))
output = {}
commands.backtrace('2')
assert(#output == 2 and output[1]:find('#0 inner', 1, true) and output[2]:find('#1 caller', 1, true))
dap.session = function() return nil end
commands.up('')
assert(output[#output]:find('requires a stopped session', 1, true))
repl.append = original_append
dap.session, repl.execute = session, execute

local original_buffer = vim.api.nvim_get_current_buf()
local prompt_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(prompt_buffer)
vim.bo[prompt_buffer].buftype = 'prompt'
vim.fn.prompt_setprompt(prompt_buffer, 'dap> ')
require('dap-extra.history').attach(prompt_buffer)
local function typed(text) vim.api.nvim_buf_set_lines(prompt_buffer, 0, -1, false, { 'dap> ' .. text }) end
local function key(lhs) return vim.fn.maparg(lhs, 'i', false, true).callback() end
local function line() return vim.api.nvim_get_current_line() end
for _, command in ipairs({ 'p node', 'up', 'p root', 'frame 0', 'p node->name()' }) do
	typed(command)
	assert(key('<CR>') == '<CR>')
end
typed('p ')
key('<Up>'); assert(line() == 'dap> p node->name()')
key('<Up>'); assert(line() == 'dap> p root')
key('<Up>'); assert(line() == 'dap> p node')
key('<Up>'); assert(line() == 'dap> p node')
key('<Down>'); assert(line() == 'dap> p root')
key('<Down>'); key('<Down>'); assert(line() == 'dap> p ')
typed('frame'); key('<Up>'); assert(line() == 'dap> frame 0')
typed('no match'); key('<Up>'); assert(line() == 'dap> no match')
typed(''); key('<Up>'); assert(line() == 'dap> p node->name()')
vim.api.nvim_set_current_buf(original_buffer)
vim.api.nvim_buf_delete(prompt_buffer, { force = true })

local function action(callback, cursor) return require('dap-extra.ui').action(callback, cursor) end
local mappings = {
	['<F10>'] = action(function() dap.step_over() end),
	['<leader>b'] = function() dap.toggle_breakpoint() end,
	['<leader>B'] = function() dap.set_breakpoint(vim.fn.input('Condition: ')) end,
	['<leader>dK'] = function() require('dap.ui.widgets').hover() end,
	['<leader>dg'] = function() require('dap-extra.ui').local_frame() end,
	['<leader>dl'] = action(function() dap.run_to_cursor() end, true),
}
-- Debug panes and source jumps must leave the original tab's windows intact.
local debug_ui = require('dap-extra.ui')
vim.cmd('vsplit')
local original_tab = vim.api.nvim_get_current_tabpage()
local original_layout = vim.fn.winlayout()
local original_buffers = vim.tbl_map(vim.api.nvim_win_get_buf, vim.api.nvim_tabpage_list_wins(original_tab))
local tab_count = #vim.api.nvim_list_tabpages()
debug_ui.open()
local debug_tab = vim.api.nvim_get_current_tabpage()
assert(debug_tab ~= original_tab and #vim.api.nvim_list_tabpages() == tab_count + 1)
debug_ui.open()
assert(#vim.api.nvim_list_tabpages() == tab_count + 1, 'Reuse the debugger tab')
vim.api.nvim_set_current_tabpage(original_tab)
local called = false
debug_ui.action(function(value)
	called = value
	assert(vim.api.nvim_get_current_tabpage() == debug_tab)
end)('forwarded')
assert(called == 'forwarded' and #vim.api.nvim_list_tabpages() == tab_count + 1)
local step_over = dap.step_over
dap.step_over = function() assert(vim.api.nvim_get_current_tabpage() == debug_tab) end
vim.api.nvim_set_current_tabpage(original_tab)
mappings['<F10>']()
dap.step_over = step_over
vim.api.nvim_set_current_tabpage(original_tab)
local origin_buffer = vim.api.nvim_get_current_buf()
local origin_cursor = vim.api.nvim_win_get_cursor(0)
debug_ui.action(function()
	assert(vim.api.nvim_get_current_tabpage() == debug_tab)
	assert(vim.api.nvim_get_current_buf() == origin_buffer)
	assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), origin_cursor))
end, true)()
vim.api.nvim_set_current_tabpage(original_tab)
local target = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(target, 0, -1, false, { 'first', 'second' })
debug_ui.jump(target, 2, 1)
assert(vim.api.nvim_get_current_tabpage() == debug_tab and vim.api.nvim_get_current_buf() == target)
vim.api.nvim_set_current_tabpage(original_tab)
debug_ui.close()
assert(vim.api.nvim_get_current_tabpage() == original_tab)
assert(vim.deep_equal(vim.fn.winlayout(), original_layout))
assert(vim.deep_equal(vim.tbl_map(vim.api.nvim_win_get_buf, vim.api.nvim_tabpage_list_wins(original_tab)), original_buffers))
local invoking = vim.api.nvim_get_current_win()
local toggle_breakpoint, set_breakpoint = dap.toggle_breakpoint, dap.set_breakpoint
local widgets = require('dap.ui.widgets')
local hover, input = widgets.hover, vim.fn.input
local local_calls = 0
local function local_action()
	local_calls = local_calls + 1
	assert(vim.api.nvim_get_current_win() == invoking)
	assert(vim.deep_equal(vim.fn.winlayout(), original_layout))
	assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), origin_cursor))
end
dap.toggle_breakpoint, dap.set_breakpoint, widgets.hover = local_action, local_action, local_action
vim.fn.input = function() return '' end
for _, key in ipairs({ '<leader>b', '<leader>B', '<leader>dK' }) do mappings[key]() end
assert(local_calls == 3)
dap.toggle_breakpoint, dap.set_breakpoint, widgets.hover, vim.fn.input = toggle_breakpoint, set_breakpoint, hover, input

local selected = { id = 9, source = { path = root .. '/tests/test.lua' }, line = 2, column = 1 }
dap.session = function() return { id = 1, current_frame = selected } end
mappings['<leader>dg']()
assert(vim.api.nvim_get_current_win() == invoking and vim.deep_equal(vim.fn.winlayout(), original_layout))
assert(vim.api.nvim_buf_get_name(0) == selected.source.path and vim.api.nvim_win_get_cursor(0)[1] == 2)
assert(dap.session().current_frame == selected)
selected.source = { sourceReference = 10 }
local adapter_buffer = vim.fn.bufadd('dap-src://1/10/')
vim.api.nvim_buf_set_lines(adapter_buffer, 0, -1, false, { 'adapter', 'source' })
mappings['<leader>dg']()
assert(vim.api.nvim_get_current_buf() == adapter_buffer)
selected.source = nil
mappings['<leader>dg']()
assert(vim.api.nvim_get_current_buf() == adapter_buffer)
dap.session = session
vim.api.nvim_win_set_buf(invoking, origin_buffer)

vim.api.nvim_set_current_win(invoking)
local run_to_cursor = dap.run_to_cursor
dap.run_to_cursor = function()
	assert(vim.api.nvim_get_current_tabpage() == debug_tab)
	assert(vim.api.nvim_get_current_buf() == origin_buffer)
end
mappings['<leader>dl']()
dap.run_to_cursor = run_to_cursor
debug_ui.open()
local source_win = vim.api.nvim_get_current_win()
dap.repl.open()
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(debug_tab)) do
	if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'dap-repl' then vim.api.nvim_set_current_win(win); break end
end
local repl_win = vim.api.nvim_get_current_win()
assert(vim.bo.filetype == 'dap-repl')
local function automatic_update()
	debug_ui.jump(target, 2, 1)
	assert(vim.api.nvim_get_current_win() == repl_win)
	assert(vim.api.nvim_win_get_buf(source_win) == target)
end
automatic_update()
stopped._frame_set = function(self, frame)
	self.current_frame = frame
	debug_ui.jump(target, 2, 1)
end
dap.session = function() return stopped end
commands.frame('0')
assert(stopped.current_frame == frames[1] and vim.api.nvim_get_current_win() == repl_win)
dap.session = session
debug_ui.open()
assert(vim.api.nvim_get_current_win() == repl_win)
vim.schedule(automatic_update)
vim.wait(50, function() return false end)
vim.api.nvim_set_current_win(invoking)
vim.schedule(function() debug_ui.jump(target, 1, 1) end)
vim.wait(50, function() return false end)
assert(vim.api.nvim_get_current_win() == source_win, 'Source actions must not restore old REPL focus')
vim.api.nvim_set_current_tabpage(debug_tab)
vim.cmd('tabclose')
debug_ui.open()
assert(vim.api.nvim_get_current_tabpage() ~= original_tab, 'Recreate a manually closed debugger tab')
debug_ui.close()
debug_ui.setup()
local terminate, pending = dap.terminate, nil
local virtual_text = require('nvim-dap-virtual-text/virtual_text')
local namespace = vim.api.nvim_create_namespace('debug-cleanup-test')
local clear_text, clear_frames = virtual_text.clear_virtual_text, virtual_text.clear_last_frames
local clears = 0
virtual_text.clear_virtual_text = function()
	clears = clears + 1
	vim.api.nvim_buf_clear_namespace(target, namespace, 0, -1)
end
virtual_text.clear_last_frames = function() end
dap.terminate = function(options) pending = options.on_done end
debug_ui.open()
local cleanup_tab = vim.api.nvim_get_current_tabpage()
local breakpoint_count = vim.deepcopy(require('dap.breakpoints').get())
vim.api.nvim_buf_set_extmark(target, namespace, 0, 0, { virt_text = { { 'stale value' } } })
vim.api.nvim_set_current_win(invoking)
vim.cmd('DapClean')
assert(vim.api.nvim_get_current_win() == invoking)
assert(vim.api.nvim_tabpage_is_valid(cleanup_tab))
assert(#vim.api.nvim_tabpage_list_wins(cleanup_tab) == 1)
assert(#vim.api.nvim_buf_get_extmarks(target, namespace, 0, -1, {}) == 0)
assert(vim.deep_equal(require('dap.breakpoints').get(), breakpoint_count))
assert(clears == 1 and pending)
pending()
dap.terminate = function() end
vim.cmd('DapClean')
assert(clears == 3 and vim.api.nvim_get_current_win() == invoking)
dap.terminate = terminate
virtual_text.clear_virtual_text, virtual_text.clear_last_frames = clear_text, clear_frames
debug_ui.focus()
local old_source, existing_tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
vim.cmd.vsplit()
local surviving = vim.api.nvim_get_current_win()
vim.api.nvim_win_close(old_source, true)
debug_ui.focus()
assert(vim.api.nvim_get_current_tabpage() == existing_tab)
assert(vim.api.nvim_get_current_win() ~= surviving, 'Recreate a closed source window in the same tab')
print('Standalone debugger routing, REPL, cleanup and repeated setup checks passed')
