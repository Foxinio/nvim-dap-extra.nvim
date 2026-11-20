dofile(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)) .. '/bootstrap.lua')
local dap = require('dap')
local notify, messages = vim.notify, {}
require('dap-extra').setup()
local watch = require('dap-extra.watch')
vim.notify = function(message, level) messages[#messages + 1] = { message, level } end
local function listener_count()
	local count = 0
	for _, event in pairs(dap.listeners.after) do
		for _ in pairs(event) do count = count + 1 end
	end
	return count
end
local listeners = listener_count()
watch.setup()
assert(listener_count() == listeners, 'Repeated setup added listeners')

local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local program = directory .. '/prog'
vim.fn.writefile({ 'old build' }, program)
local session = { id = 1, config = { program = program } }
dap.listeners.after.launch['dap-extra.watch'](session, nil, {}, {})
assert(watch._count() == 1)
local function settle() vim.wait(800, function() return false end) end
settle()
assert(#messages == 0, 'No change, no warning: ' .. vim.inspect(messages))

-- Rebuild the way a linker does: remove the old file, write a new one.
vim.fn.delete(program)
vim.fn.writefile({ 'new build', 'longer' }, program)
assert(vim.wait(3000, function() return #messages >= 1 end), 'Rebuild must warn')
settle()
assert(#messages == 1, 'One warning per rebuild: ' .. vim.inspect(messages))
assert(messages[1][2] == vim.log.levels.WARN and messages[1][1]:find('prog was rebuilt', 1, true), messages[1][1])

-- Writing in place warns again.
vim.fn.writefile({ 'third build', 'even longer', 'yes' }, program)
assert(vim.wait(3000, function() return #messages == 2 end), 'Second rebuild must warn again')

-- Other files in the same directory are ignored.
vim.fn.writefile({ 'x' }, directory .. '/other.o')
settle()
assert(#messages == 2, vim.inspect(messages))

-- Session end stops the watcher.
dap.listeners.after.event_terminated['dap-extra.watch'](session, {})
assert(watch._count() == 0)
vim.fn.writefile({ 'after the session' }, program)
settle()
assert(#messages == 2, 'No warnings after the session ended')

-- Sessions without a program are skipped.
dap.listeners.after.attach['dap-extra.watch']({ id = 2, config = { processId = 1 } }, nil, {}, {})
dap.listeners.after.launch['dap-extra.watch']({ id = 3, config = { program = directory .. '/missing' } }, nil, {}, {})
assert(watch._count() == 0)

-- Turned off: nothing registered.
watch.setup(false)
assert(dap.listeners.after.launch['dap-extra.watch'] == nil)
watch.setup()
assert(dap.listeners.after.launch['dap-extra.watch'] ~= nil)

vim.notify = notify
vim.fn.delete(directory, 'rf')
print('Rebuild warning checks passed')
