local M = {}

function M.inactive_command(text)
	if not require('dap').session() and (text == 'q' or text == 'quit' or text == 'r' or text == 'run') then
		return require('dap.repl').commands.custom_commands[text]
	end
end

function M.setup()
	local repl = require('dap.repl')
	local function quit()
		local dap = require('dap')
		if not dap.session() then
			vim.notify('No active debug session', vim.log.levels.INFO)
			return
		end
		dap.terminate({
			disconnect_args = { terminateDebuggee = true },
			on_done = vim.schedule_wrap(function(err)
				if err then
					vim.notify('Could not stop debugging: ' .. tostring(err), vim.log.levels.ERROR)
					return
				end
				vim.notify('Debugging stopped', vim.log.levels.INFO)
			end),
		})
	end
	repl.commands.custom_commands.q = quit
	repl.commands.custom_commands.quit = quit
	local function run()
		local dap = require('dap')
		if dap.session() then dap.restart() else dap.run_last() end
	end
	repl.commands.custom_commands.r = run
	repl.commands.custom_commands.run = run
	-- Upstream rejects custom commands without a session, including commands that start one.
	if not M.execute then
		M.execute = repl.execute
		repl.execute = function(text, opts)
			local command = M.inactive_command(text)
			if command then
				repl.append(text)
				command()
				return
			end
			return M.execute(text, opts)
		end
	end
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
