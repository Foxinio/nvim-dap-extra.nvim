local M = {}
M.root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp = { M.root, vim.env.VIMRUNTIME }
local dependencies = vim.env.NVIM_TEST_DEPENDENCIES or vim.fn.stdpath('data') .. '/lazy'
for _, name in ipairs({ 'nvim-dap', 'nvim-dap-ui', 'nvim-nio', 'nvim-dap-virtual-text' }) do
	local path = dependencies .. '/' .. name
	assert(vim.fn.isdirectory(path) == 1, 'Missing test dependency: ' .. path)
	vim.opt.rtp:append(path)
end
vim.cmd.cd('/tmp')
return M
