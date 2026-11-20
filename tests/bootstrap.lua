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
-- The dap-ui fork provides dapui.breakpoints for command/chained breakpoints.
-- Scripts that check the feature degrades without it set this global first.
if not DAP_EXTRA_WITHOUT_DAPUI then add({ 'nvim-dap-ui' }) end

--- Live/integration scripts also set up the fork's panes and debug tab; the
--- unit tests check dap-extra works without them (it only uses dapui.breakpoints).
function M.with_dapui()
	add({ 'nvim-nio' })
	require('dapui').setup()
end
vim.cmd.cd('/tmp')
return M
