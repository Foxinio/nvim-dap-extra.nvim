local M = {}
local history = {}

function M.attach(buffer)
	local search
	local function input()
		local prompt = vim.fn.prompt_getprompt(buffer)
		local line = vim.api.nvim_buf_get_lines(buffer, -2, -1, false)[1] or ''
		return line:sub(#prompt + 1), prompt
	end
	local function navigate(direction)
		local text, prompt = input()
		if not search or text ~= search.last then
			search = { prefix = text, last = text, index = #history + 1 }
		end
		local index = search.index + direction
		while index > 0 and index <= #history do
			if vim.startswith(history[index], search.prefix) then break end
			index = index + direction
		end
		if index <= 0 then return end
		search.index = math.min(index, #history + 1)
		search.last = history[search.index] or search.prefix
		vim.api.nvim_buf_set_lines(buffer, -2, -1, false, { prompt .. search.last })
		vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(buffer), #prompt + #search.last })
	end
	vim.keymap.set('i', '<Up>', function() navigate(-1) end, { buffer = buffer, desc = 'Previous command matching prefix' })
	vim.keymap.set('i', '<Down>', function() navigate(1) end, { buffer = buffer, desc = 'Next command matching prefix' })
	vim.keymap.set('i', '<CR>', function()
		local text = input()
		if text ~= '' and text ~= history[#history] then
			history[#history + 1] = text
			if #history > 100 then table.remove(history, 1) end
		end
		search = nil
		return '<CR>'
	end, { buffer = buffer, expr = true, desc = 'Submit debugger command' })
end

function M.setup()
	vim.api.nvim_create_autocmd('FileType', {
		group = vim.api.nvim_create_augroup('debug-prefix-history', { clear = true }),
		pattern = 'dap-repl',
		callback = function(opts) M.attach(opts.buf) end,
	})
	for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
		if vim.bo[buffer].filetype == 'dap-repl' then M.attach(buffer) end
	end
end

return M
