local M = {}

function M.setup()
	local util = require('dapui.util')
	if not M.open_buf then
		M.open_buf = util.open_buf
		util.open_buf = function(buffer, line, column)
			if vim.bo.filetype == 'dapui_stacks' or vim.bo.filetype == 'dapui_breakpoints' then
				require('dap-extra.ui').jump(buffer, line or 1, column or 1)
				return true
			end
			return M.open_buf(buffer, line, column)
		end
	end
	local element = require('dapui').elements.breakpoints
	if M.element == element and element.render == M.render then return end
	local render = element.render
	element.render = function()
		render()
		local buffer = element.buffer()
		local mappings = {}
		for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buffer, 'n')) do mappings[mapping.lhs] = mapping.callback end
		if not mappings.d or not mappings.t then return end
		vim.keymap.set('n', 'd', function()
			local line = vim.api.nvim_win_get_cursor(0)[1]
			local marks = vim.api.nvim_buf_get_extmarks(buffer, require('dapui.render.canvas').namespace,
				{ line - 1, 0 }, { line - 1, -1 }, { details = true })
			for _, mark in ipairs(marks) do
				if mark[4].hl_group == 'DapUIBreakpointsDisabledLine' then
					-- Upstream removal leaves disabled entries in its private cache; enable and render first.
					mappings.t()
					render()
					break
				end
			end
			mappings.d()
		end, { buffer = buffer, desc = 'Remove breakpoint', nowait = true })
	end
	M.element, M.render = element, element.render
end

return M
