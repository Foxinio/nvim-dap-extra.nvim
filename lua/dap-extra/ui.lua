local M = {}
local tab, source

local function ensure()
	if not tab or not vim.api.nvim_tabpage_is_valid(tab) then
		vim.cmd('tab split')
		tab = vim.api.nvim_get_current_tabpage()
		source = vim.api.nvim_get_current_win()
	else
		if not vim.api.nvim_win_is_valid(source) or vim.api.nvim_win_get_tabpage(source) ~= tab then
			vim.api.nvim_win_call(vim.api.nvim_tabpage_list_wins(tab)[1], function()
				vim.cmd('topleft new')
				source = vim.api.nvim_get_current_win()
			end)
		end
	end
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

function M.open()
	if vim.bo.filetype == 'dap-repl' then
		ensure()
		vim.api.nvim_win_call(source, function() require('dapui').open() end)
		return
	end
	M.focus()
	require('dapui').open()
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
