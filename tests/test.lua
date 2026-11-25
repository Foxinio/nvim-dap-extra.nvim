local root = dofile(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)) .. '/bootstrap.lua').root
local dap, repl = require('dap'), require('dap.repl')
require('dap-extra').setup()
assert(not package.loaded.dapui, 'dap-extra must not load dap-ui')
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
vim.wait(20, function() return false end)
require('dap-extra').setup()
assert(listener_count() == listeners, 'Repeated setup added listeners')
local configure = dap.listeners.on_config['dap-extra']
local defaults = {
	{ text = '-enable-pretty-printing', description = 'Enable pretty-printing for gdb', ignoreFailures = true },
	{ text = 'catch throw' },
	{ text = 'handle SIGABRT SIGSEGV SIGBUS SIGILL SIGFPE stop print pass' },
	{ text = '-break-insert -f pthread_kill' },
}
for _, request in ipairs({ 'launch', 'attach' }) do
	for _, mode in ipairs({ 'gdb', false }) do
		local config = { type = 'cppdbg', request = request, MIMode = mode or nil }
		assert(vim.deep_equal(configure(config).setupCommands, defaults))
		assert(config.setupCommands == nil, 'Defaults mutated the original configuration')
	end
end
local config = { type = 'cppdbg', setupCommands = { { text = 'handle SIGABRT nostop' } } }
local original = vim.deepcopy(config)
local prepared = configure(config)
assert(vim.deep_equal(config, original))
assert(vim.deep_equal(prepared.setupCommands, vim.list_extend(vim.deepcopy(defaults), config.setupCommands)))
assert(vim.deep_equal(configure(prepared), prepared), 'Repeated configuration duplicated defaults')
-- A command already in the user's setupCommands is not added twice.
local own = configure({ type = 'cppdbg', setupCommands = { { text = '-enable-pretty-printing' } } })
assert(#vim.tbl_filter(function(command) return command.text == '-enable-pretty-printing' end,
	own.setupCommands) == 1, 'Pretty printing was enabled twice')
assert(own.setupCommands[#own.setupCommands].text == '-enable-pretty-printing', 'User command must stay last')
-- stopAtEntry is turned off for every cppdbg session, without mutating the original.
for _, mode in ipairs({ 'gdb', 'lldb' }) do
	local entry = { type = 'cppdbg', request = 'launch', MIMode = mode, stopAtEntry = true }
	assert(configure(entry).stopAtEntry == false, 'stopAtEntry kept for ' .. mode)
	assert(entry.stopAtEntry == true, 'stopAtEntry change mutated the original configuration')
end
assert(configure({ type = 'debugpy', stopAtEntry = true }).stopAtEntry == true, 'Other adapters must be unchanged')
for _, excluded in ipairs({ { type = 'debugpy' }, { type = 'codelldb' }, { type = 'cppdbg', MIMode = 'lldb' } }) do
	assert(configure(excluded) == excluded)
end
local session = dap.session
local execute = repl.execute
local forwarded = {}
dap.session = function() return { config = { type = 'cppdbg' } } end
repl.execute = function(command) forwarded[#forwarded + 1] = command end
repl.commands.custom_commands.gdb('info locals')
assert(vim.deep_equal(forwarded, { '-exec info locals' }))
local appended = {}
local append = repl.append
repl.append = function(text) appended[#appended + 1] = text end
repl.commands.custom_commands.gdb('  ')
repl.append = append
assert(#forwarded == 1 and appended[1] == 'Usage: gdb <command>')
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

-- local_frame shows the selected frame in the current window only.
vim.cmd('vsplit')
local invoking, layout = vim.api.nvim_get_current_win(), vim.fn.winlayout()
local selected = { id = 9, source = { path = root .. '/tests/test.lua' }, line = 2, column = 1 }
dap.session = function() return { id = 1, current_frame = selected } end
require('dap-extra').local_frame()
assert(vim.api.nvim_get_current_win() == invoking and vim.deep_equal(vim.fn.winlayout(), layout))
assert(vim.api.nvim_buf_get_name(0) == selected.source.path and vim.api.nvim_win_get_cursor(0)[1] == 2)
assert(dap.session().current_frame == selected, 'local_frame must not change the selected frame')
selected.source = { sourceReference = 10 }
local adapter_buffer = vim.fn.bufadd('dap-src://1/10/')
vim.api.nvim_buf_set_lines(adapter_buffer, 0, -1, false, { 'adapter', 'source' })
require('dap-extra').local_frame()
assert(vim.api.nvim_get_current_buf() == adapter_buffer)
selected.source = nil
require('dap-extra').local_frame()
assert(vim.api.nvim_get_current_buf() == adapter_buffer, 'Missing source keeps the window')
dap.session = session
print('REPL commands, history, cppdbg defaults, local frame and repeated setup checks passed')
