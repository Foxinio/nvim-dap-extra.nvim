local M = {}
local tab, source

local function track(win)
	local dapui = package.loaded.dapui
	if dapui and dapui.source_window then dapui.source_window.set(win) end
end

local function ensure_source()
	if not tab or not vim.api.nvim_tabpage_is_valid(tab) then
		vim.cmd('tab split')
		tab = vim.api.nvim_get_current_tabpage()
		source = vim.api.nvim_get_current_win()
	else
		if not vim.api.nvim_win_is_valid(source) or vim.api.nvim_win_get_tabpage(source) ~= tab then
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
				local buffer = vim.api.nvim_win_get_buf(win)
				local filetype = vim.bo[buffer].filetype
				if filetype ~= 'dap-repl' and not filetype:match('^dapui_')
					and vim.bo[buffer].buftype ~= 'terminal' and vim.api.nvim_win_get_config(win).relative == '' then
					source = win
					track(source)
					return
				end
			end
			vim.api.nvim_win_call(vim.api.nvim_tabpage_list_wins(tab)[1], function()
				vim.cmd('topleft new')
				source = vim.api.nvim_get_current_win()
			end)
		end
	end
	track(source)
end

--- The debug tab's source window, created if needed; dap-ui routes pane
--- navigation here through `select_window`.
function M.source_window()
	ensure_source()
	return source
end

local function ensure()
	ensure_source()
	local ok, tab_name = pcall(require, 'tabby.feature.tab_name')
	if not ok then return end
	local session = require('dap').session()
	local config = session and session.config
	if not config and tab_name.get_raw(tab) ~= '' then return end
	local target = config and config.name
	if config and type(config.program) == 'string' and config.program ~= '' then
		target = vim.fn.fnamemodify(config.program, ':t')
	end
	tab_name.set(tab, type(target) == 'string' and target ~= '' and ('DEBUGGER (' .. target .. ')') or 'DEBUGGER')
end

function M.focus()
	ensure()
	vim.api.nvim_set_current_win(source)
end

function M.action(callback, use_cursor)
	return function(...)
		local buffer = vim.api.nvim_get_current_buf()
		local cursor = vim.api.nvim_win_get_cursor(0)
		local cwd = vim.fn.getcwd()
		M.focus()
		vim.cmd.tcd(vim.fn.fnameescape(cwd))
		if use_cursor or not require('dap').session() then
			vim.api.nvim_win_set_buf(source, buffer)
			vim.api.nvim_win_set_cursor(source, cursor)
		end
		return callback(...)
	end
end

local function open(opts)
	if vim.bo.filetype == 'dap-repl' then
		ensure()
		vim.api.nvim_win_call(source, function() require('dapui').open(opts) end)
		return
	end
	M.focus()
	require('dapui').open(opts)
end

function M.open()
	open()
end

function M.reset()
	ensure()
	local repl = vim.bo.filetype == 'dap-repl' and vim.api.nvim_get_current_buf()
	-- The dap-ui fork rebuilds layouts with hand-closed panes on open().
	open({ reset = true })
	if repl then
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
			if vim.api.nvim_win_get_buf(win) == repl then vim.api.nvim_set_current_win(win); break end
		end
	end
end

function M.close()
	if not tab or not vim.api.nvim_tabpage_is_valid(tab) then return end
	local previous = vim.api.nvim_get_current_tabpage()
	vim.api.nvim_set_current_tabpage(tab)
	require('dapui').close()
	if vim.api.nvim_tabpage_is_valid(previous) then vim.api.nvim_set_current_tabpage(previous) end
end

function M.cleanup()
	local function clear()
		local virtual_text = require('nvim-dap-virtual-text/virtual_text')
		virtual_text.clear_virtual_text()
		virtual_text.clear_last_frames()
		M.close()
		require('dap').repl.close()
	end
	require('dap').terminate({ on_done = clear })
	clear()
end

function M.setup()
	vim.api.nvim_create_user_command('DapReset', M.reset, {
		force = true, desc = 'Restore configured debugger pane sizes',
	})
	vim.api.nvim_create_user_command('DapClean', M.cleanup, {
		force = true, desc = 'Terminate debugging, clear annotations and close debugger panes',
	})
end

function M.toggle()
	M.focus()
	require('dapui').toggle()
end

function M.repl()
	M.focus()
	require('dap').repl.toggle()
end

function M.jump(bufnr, line, column)
	if vim.bo.filetype == 'dap-repl' then ensure() else M.focus() end
	vim.api.nvim_win_set_buf(source, bufnr)
	-- Missing library sources can have fewer lines than the debugger reports.
	line = math.max(1, math.min(line, vim.api.nvim_buf_line_count(bufnr)))
	vim.api.nvim_win_set_cursor(source, { line, math.max(0, column - 1) })
end

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
