local M = {}
M.root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp = { M.root, vim.env.VIMRUNTIME }
local dependencies = vim.env.NVIM_TEST_DEPENDENCIES or vim.env.DEPS_DIR
if not dependencies or dependencies == '' then dependencies = vim.fn.stdpath('data') .. '/lazy' end
-- Absolute: the tests change directory to /tmp below.
dependencies = vim.fn.fnamemodify(dependencies, ':p'):gsub('/$', '')
local function add(names)
	for _, name in ipairs(names) do
		local path = dependencies .. '/' .. name
		assert(vim.fn.isdirectory(path) == 1, 'Missing test dependency: ' .. path)
		vim.opt.rtp:append(path)
	end
end
add({ 'nvim-dap', 'nvim-dap-virtual-text' })

--- Live/integration scripts also load the Foxinio/nvim-dap-ui fork (debug tab,
--- panes); the unit tests check dap-extra works without it.
function M.with_dapui()
	add({ 'nvim-dap-ui', 'nvim-nio' })
	require('dapui').setup()
end
vim.cmd.cd('/tmp')
return M
