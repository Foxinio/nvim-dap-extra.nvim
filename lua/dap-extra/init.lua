local M = {}
local configured = false

--- Command and chained breakpoints; see the README.
M.breakpoints = require('dap-extra.breakpoints')

function M.setup(opts)
	if configured then return end
	opts = opts or {}
	local dap = require('dap')
	dap.listeners.on_config['dap-extra'] = function(config)
		if config.type ~= 'cppdbg' then return config end
		-- Configurations copied from common examples set stopAtEntry = true,
		-- which stops at main on every run.
		if config.stopAtEntry and not opts.keep_stop_at_entry then
			config = vim.deepcopy(config)
			config.stopAtEntry = false
		end
		if config.MIMode and config.MIMode ~= 'gdb' then return config end
		config = vim.deepcopy(config)
		local commands = config.setupCommands or {}
		local defaults = {}
		for _, default in ipairs({
			-- GDB auto-loads pretty printers (libstdc++'s and others) but only
			-- applies them over MI once enabled; tolerated without Python support.
			{ text = '-enable-pretty-printing', description = 'Enable pretty-printing for gdb', ignoreFailures = true },
			{ text = 'catch throw' },
			{ text = 'handle SIGABRT SIGSEGV SIGBUS SIGILL SIGFPE stop print pass' },
			{ text = '-break-insert -f pthread_kill' },
		}) do
			if not vim.iter(commands):any(function(command) return command.text == default.text end) then
				defaults[#defaults + 1] = default
			end
		end
		config.setupCommands = vim.list_extend(defaults, commands)
		return config
	end
	require('nvim-dap-virtual-text').setup(vim.tbl_deep_extend('force', {
		enabled = true,
		highlight_changed_variables = true,
		highlight_new_as_changed = true,
		show_stop_reason = true,
		commented = false,
		only_first_definition = true,
		all_references = false,
		clear_on_continue = false,
	}, opts.virtual_text or {}))

	vim.fn.sign_define('DapBreakpoint', { text = '🛑', texthl = '', linehl = '', numhl = '' })
	vim.fn.sign_define('DapBreakpointCondition', { text = '🟨', texthl = '', linehl = '', numhl = '' })
	vim.fn.sign_define('DapLogPoint', { text = '📝', texthl = '', linehl = '', numhl = '' })
	vim.fn.sign_define('DapStopped', { text = '▶', texthl = '', linehl = 'Visual', numhl = '' })
	vim.fn.sign_define('DapBreakpointRejected', { text = '', texthl = 'DiagnosticError', linehl = '', numhl = '' })

	require('dap-extra.repl').setup()
	-- Command/chained breakpoints need the dap-ui fork; nothing here may stop
	-- the rest of setup.
	local ok, err = pcall(require('dap-extra.breakpoints').setup, opts.breakpoints)
	if not ok then
		vim.notify('dap-extra: command/chained breakpoints disabled: ' .. tostring(err), vim.log.levels.WARN)
	end
	-- The rebuild warning must not stop the rest of setup.
	ok, err = pcall(require('dap-extra.watch').setup, opts.watch_program)
	if not ok then
		vim.notify('dap-extra: rebuild warning disabled: ' .. tostring(err), vim.log.levels.WARN)
	end
	configured = true
end

--- Show the selected frame's source in the current window (file or adapter
--- source), without changing windows, tabs or the selected frame.
function M.local_frame()
	local session = require('dap').session()
	local frame = session and session.current_frame
	local location = frame and frame.source
	if not location or not frame.line or frame.line < 1
		or (not location.path and (location.sourceReference or 0) == 0) then
		vim.notify('Selected frame source is unavailable', vim.log.levels.INFO)
		return
	end
	local name
	if (location.sourceReference or 0) ~= 0 then
		name = string.format('dap-src://%d/%d/%s', session.id, location.sourceReference, location.path or '')
	else
		name = location.path
		if not name:match('^%a+://') and vim.fn.filereadable(name) == 0 then
			vim.notify('Selected frame source is unavailable', vim.log.levels.INFO)
			return
		end
	end
	local buffer = vim.fn.bufadd(name)
	vim.fn.bufload(buffer)
	vim.api.nvim_win_set_buf(0, buffer)
	vim.api.nvim_win_set_cursor(0, { frame.line, math.max(0, (frame.column or 1) - 1) })
end

return M
