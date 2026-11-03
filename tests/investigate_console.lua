dofile(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)) .. '/bootstrap.lua')
require('dap-extra').setup()
require('dap-extra.ui').open()
local buffer = require('dapui').elements.console.buffer()
local win
for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	if vim.api.nvim_win_get_buf(candidate) == buffer then win = candidate; break end
end
assert(win, 'Console is not visible')
vim.api.nvim_win_set_width(win, 20)
local width = vim.api.nvim_win_get_width(win)
local marker = 'BEGIN:' .. string.rep('0123456789', 12) .. ':END'
local payload = marker .. '\n' .. string.rep('filler\n', 40)
local raw, exited = {}, false
vim.api.nvim_win_call(win, function()
	assert(vim.fn.jobstart({ 'printf', '%s', payload }, {
		term = true,
		on_stdout = function(_, data) raw[#raw + 1] = table.concat(data, '\n') end,
		on_exit = function() exited = true end,
	}) > 0)
end)
assert(vim.wait(5000, function() return exited end))
local function lines() return vim.api.nvim_buf_get_lines(buffer, 0, -1, false) end
local before = lines()
assert(table.concat(raw):gsub('\r\n', '\n') == payload, 'Program output differs from the original text')
assert(not vim.tbl_contains(before, marker), 'Expected the terminal to split the long line')
vim.api.nvim_win_set_width(win, 60)
vim.wait(100, function() return false end)
local after = lines()
assert(not vim.tbl_contains(after, marker), 'This Neovim version restored the scrollback line')
print(vim.inspect({
	neovim = vim.version(), initial_width = width, widened_to = vim.api.nvim_win_get_width(win),
	wrap = vim.wo[win].wrap, raw_line_length = #marker,
	first_rows_before = vim.list_slice(before, 1, 8),
	first_rows_after = vim.list_slice(after, 1, 8),
}))
