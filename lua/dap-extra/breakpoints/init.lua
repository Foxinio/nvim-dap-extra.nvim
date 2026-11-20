--- Command breakpoints (run a Vim command when hit) and chained breakpoints
--- (off until a parent breakpoint is hit). Properties are stored through
--- the Foxinio/nvim-dap-ui fork's `dapui.breakpoints` module; without it this
--- feature is disabled and the rest of dap-extra works as before.
---
--- Submodules: `state` (store and run-time state), `properties` (what is
--- registered with dapui.breakpoints), `picker`, `hits` (hit handling).
local M = {}

M.unavailable_message =
	'dap-extra: command/chained breakpoints disabled — requires Foxinio/nvim-dap-ui (dapui.breakpoints not found)'
M.available = false

local state = require('dap-extra.breakpoints.state')
local configured, warned, disabled = false, false, false

local function notify_unavailable()
	if disabled then
		vim.notify('dap-extra: command/chained breakpoints are turned off (breakpoints = false)', vim.log.levels.INFO)
	else
		vim.notify(M.unavailable_message, vim.log.levels.WARN)
	end
end

local function resolve(buf, line)
	buf = buf or vim.api.nvim_get_current_buf()
	line = line or vim.api.nvim_win_get_cursor(0)[1]
	return buf, line
end

--- Add a plain breakpoint if the line has none.
local function ensure_breakpoint(buf, line)
	if state.store.breakpoint(buf, line) then return true end
	require('dap.breakpoints').set({}, buf, line)
	state.store.refresh(buf)
	return state.store.breakpoint(buf, line) ~= nil
end

local function guard()
	if not M.available then
		notify_unavailable()
		return false
	end
	return true
end

--- Breakpoints a chained breakpoint waits on, as `{ buf, line }` (buf is nil
--- for a parent that was removed).
function M.parents(buf, line)
	if not guard() then return {} end
	buf, line = resolve(buf, line)
	return vim.tbl_map(function(handle)
		local pbuf, pline = state.store.locate(handle)
		return { buf = pbuf, line = pline }
	end, state.parents_of(buf, line))
end

--- Run `cmd` (a Vim command) when the breakpoint at buf/line (default: cursor)
--- is hit. Without `cmd`, asks for one; an empty command removes it.
--- `opts.stop = true` keeps the program stopped afterwards.
function M.set_command(cmd, opts, buf, line)
	if not guard() then return end
	opts = opts or {}
	buf, line = resolve(buf, line)
	local function apply(text)
		if text == nil then return end
		if not ensure_breakpoint(buf, line) then return end
		state.store.set(buf, line, 'command', text ~= '' and text or nil)
		state.store.set(buf, line, 'stop', opts.stop == true)
	end
	if cmd then return apply(cmd) end
	vim.ui.input({ prompt = 'Command on breakpoint: ', default = state.store.breakpoint(buf, line)
		and state.store.get(buf, line, 'command') or '' }, apply)
end

--- When a breakpoint turns off again: 'restart' (stays on until the next run
--- or restart) or a number N (turns off after N hits).
function M.set_reset(value, buf, line)
	if not guard() then return end
	buf, line = resolve(buf, line)
	if value ~= 'restart' and (type(value) ~= 'number' or value < 1 or value % 1 ~= 0) then
		vim.notify('Breakpoint reset must be "restart" or a positive whole number', vim.log.levels.WARN)
		return
	end
	if not ensure_breakpoint(buf, line) then return end
	local _, handle = state.state_for(buf, line)
	if handle then state.runtime[handle].hits = 0 end
	state.store.set(buf, line, 'reset', value)
	state.maybe_release(buf, line)
end

--- Make the breakpoint at buf/line wait on `targets` (list of `{ buf, line }`
--- of existing breakpoints). An empty list removes the chain.
function M.set_parents(targets, buf, line)
	if not guard() then return end
	buf, line = resolve(buf, line)
	if not ensure_breakpoint(buf, line) then return end
	local own = state.store.handle(buf, line)
	local handles, seen = {}, {}
	for _, target in ipairs(targets) do
		local handle = state.store.handle(target.buf, target.line)
		if handle and handle ~= own and not seen[handle] then
			seen[handle] = true
			handles[#handles + 1] = handle
		end
	end
	local previous = state.parents_of(buf, line)
	local entry = state.runtime[own] or { hits = 0 }
	entry.armed = #handles == 0
	state.runtime[own] = entry
	state.store.set(buf, line, 'parents', #handles > 0 and handles or nil)
	for _, handle in ipairs(previous) do
		if not seen[handle] then
			local pbuf, pline = state.store.locate(handle)
			if pbuf then state.maybe_release(pbuf, pline) end
		end
	end
	state.maybe_release(buf, line)
end

--- Pick the parents of the breakpoint at buf/line (default: cursor) from the
--- other breakpoints, with Telescope when installed, else vim.ui.select.
function M.chain(buf, line)
	if not guard() then return end
	buf, line = resolve(buf, line)
	if not ensure_breakpoint(buf, line) then return end
	local items = require('dap-extra.breakpoints.picker').candidates(buf, line)
	if #items == 0 then
		vim.notify('No other breakpoints to chain to', vim.log.levels.INFO)
		return
	end
	local current = {}
	for _, handle in ipairs(state.parents_of(buf, line)) do current[handle] = true end
	local function done(selected)
		M.set_parents(selected, buf, line)
	end
	require('dap-extra.breakpoints.picker').pick(items, current, done)
end

local function define_commands()
	vim.api.nvim_create_user_command('DapCommandBreakpoint', function(args)
		M.set_command(args.args ~= '' and args.args or nil, { stop = args.bang })
	end, { nargs = '*', bang = true, complete = 'command',
		desc = 'Run a Vim command when this breakpoint is hit (! keeps the program stopped)' })
	vim.api.nvim_create_user_command('DapChainBreakpoint', function() M.chain() end,
		{ desc = 'Pick breakpoints this breakpoint waits on' })
	vim.api.nvim_create_user_command('DapBreakpointReset', function(args)
		local value = vim.trim(args.args)
		M.set_reset(value == 'restart' and value or tonumber(value) or value)
	end, { nargs = 1, complete = function() return { 'restart' } end,
		desc = 'When this breakpoint turns off again: restart or after N hits' })
end

--- Set up the feature. Never raises: without `dapui.breakpoints`, the feature
--- is disabled with one warning. `enabled = false` disables it silently.
function M.setup(enabled)
	define_commands()
	if enabled == false then
		disabled, M.available = true, false
		return
	end
	disabled = false
	if configured then return end
	local ok, module = pcall(require, 'dapui.breakpoints')
	if not ok or type(module) ~= 'table' or not module.register then
		M.available = false
		if not warned then
			warned = true
			notify_unavailable()
		end
		return
	end
	state.store = module
	vim.api.nvim_set_hl(0, 'DapBreakpointCommand', { default = true, link = 'DiagnosticWarn' })
	require('dap-extra.breakpoints.properties').register({ chain = M.chain, set_reset = M.set_reset })
	local hits = require('dap-extra.breakpoints.hits')
	local dap = require('dap')
	dap.listeners.before.event_initialized['dap-extra.breakpoints'] = hits.on_initialized
	dap.listeners.after.event_stopped['dap-extra.breakpoints'] = hits.on_stopped
	dap.listeners.before.stackTrace['dap-extra.breakpoints'] = hits.on_stack_trace
	M.available, configured = true, true
end

return M
