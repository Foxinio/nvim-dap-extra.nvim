local M = {}
local configured = false

function M.setup(opts)
	if configured then return end
	opts = opts or {}
	local dap, dapui = require('dap'), require('dapui')
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

	-- Dap UI setup
	-- For more information, see |:help nvim-dap-ui|
	dapui.setup(vim.tbl_deep_extend('force', {
		element_mappings = {
			stacks = { expand = '<2-LeftMouse>', open = { '<CR>', 'o' }, toggle = { '<Space>', 't' } },
			breakpoints = { expand = '<2-LeftMouse>', open = { '<CR>', 'o' }, toggle = 't', remove = 'd' },
		},
		icons = { expanded = '▾', collapsed = '▸', current_frame = '*' },
		layouts = {
			{
				elements = {
					{ id = 'scopes', size = 0.45 },
					{ id = 'breakpoints', size = 0.15 },
					{ id = 'stacks', size = 0.25 },
					{ id = 'watches', size = 0.15 },
				},
				position = 'left',
				size = 48,
			},
			{
				elements = {
					{ id = 'repl', size = 0.5 },
					{ id = 'console', size = 0.5 },
				},
				position = 'bottom',
				size = 12,
			},
		},
		floating = {
			border = 'rounded',
		},
		controls = {
			enabled = true,
			element = 'repl',
			icons = {
				pause = '⏸',
				play = '▶',
				step_into = '⏎',
				step_over = '⏭',
				step_out = '⏮',
				step_back = 'b',
				run_last = '▶▶',
				terminate = '⏹',
				disconnect = '⏏',
			},
		},
	}, opts.dapui or {}))
	require('dap-extra.panes').setup()

	vim.fn.sign_define('DapBreakpoint', { text = '🛑', texthl = '', linehl = '', numhl = '' })
	vim.fn.sign_define('DapBreakpointCondition', { text = '🟨', texthl = '', linehl = '', numhl = '' })
	vim.fn.sign_define('DapLogPoint', { text = '📝', texthl = '', linehl = '', numhl = '' })
	vim.fn.sign_define('DapStopped', { text = '▶', texthl = '', linehl = 'Visual', numhl = '' })
	vim.fn.sign_define('DapBreakpointRejected', { text = '', texthl = 'DiagnosticError', linehl = '', numhl = '' })

	require('dap-extra.repl').setup()
	local debug_ui = require('dap-extra.ui')
	debug_ui.setup()
	dap.defaults.fallback.switchbuf = debug_ui.jump
	dap.listeners.after.event_initialized['dapui_config'] = function()
		debug_ui.open()
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'dap-repl' then
				vim.api.nvim_set_current_win(win)
				vim.cmd.startinsert({ bang = true })
				break
			end
		end
	end
	configured = true
end

return M
