local M = {}

function M.setup()
	local repl = require('dap.repl')
	require('dap-extra.history').setup()
	for command, alias in pairs({ into = 's', next_ = 'n', intoi = 'si', nexti = 'ni', out = 'fin', continue = 'c' }) do
		if not vim.tbl_contains(repl.commands[command], alias) then table.insert(repl.commands[command], alias) end
	end
	local function gdb(command, args)
		local session = require('dap').session()
		if not session or session.config.type ~= 'cppdbg' then
			repl.append('This command requires a GDB/cppdbg session')
			return
		end
		repl.execute('-exec ' .. command .. (args and args ~= '' and ' ' .. args or ''))
	end
	for _, name in ipairs({ 'p', 'i' }) do
		local command = name
		repl.commands.custom_commands[command] = function(args) gdb(command, args) end
	end
	repl.commands.custom_commands.gdb = function(args) gdb(args) end
	for _, name in ipairs({ 'up', 'down', 'frame', 'bt' }) do
		local command = name
		repl.commands.custom_commands[command] = function(args)
			require('dap-extra.stack').command(command, args)
		end
	end
	repl.commands.custom_commands.f = repl.commands.custom_commands.frame
	repl.commands.custom_commands.backtrace = repl.commands.custom_commands.bt
	repl.commands.custom_commands.where = repl.commands.custom_commands.bt
end

return M
