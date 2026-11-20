--- Command breakpoints (run a Vim command when hit) and chained breakpoints
--- (off until a parent breakpoint is hit). Properties are stored through
--- the Foxinio/nvim-dap-ui fork's `dapui.breakpoints` module; without it this
--- feature is disabled and the rest of dap-extra works as before.
local M = {}

M.unavailable_message =
	'dap-extra: command/chained breakpoints disabled — requires Foxinio/nvim-dap-ui (dapui.breakpoints not found)'
M.available = false

local store
local configured, warned, disabled = false, false, false
--- handle → { armed = boolean, hits = integer }
local state = {}

local function notify_unavailable()
	if disabled then
		vim.notify('dap-extra: command/chained breakpoints are turned off (breakpoints = false)', vim.log.levels.INFO)
	else
		vim.notify(M.unavailable_message, vim.log.levels.WARN)
	end
end

local function location_text(buf, line)
	if not buf then return '(removed)' end
	return string.format('%s:%d', vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':~:.'), line)
end

local function parents_of(buf, line)
	return store.get(buf, line, 'parents') or {}
end

local function tracked(buf, line)
	return #parents_of(buf, line) > 0 or type(store.get(buf, line, 'reset')) == 'number'
end

local function state_for(buf, line)
	local handle = store.handle(buf, line)
	if not handle then return nil end
	if not state[handle] then
		state[handle] = { armed = #parents_of(buf, line) == 0, hits = 0 }
	end
	return state[handle], handle
end

--- Handles still referenced as a parent by some breakpoint.
local function referenced()
	local result = {}
	for _, data in ipairs(store.list()) do
		for _, entry in ipairs(data.breakpoints) do
			for _, handle in ipairs(entry.properties.parents or {}) do result[handle] = true end
		end
	end
	return result
end

--- Let go of a breakpoint's handle once nothing needs it, so its record can go.
local function maybe_release(buf, line)
	if not store.breakpoint(buf, line) or tracked(buf, line) then return end
	local handle = store.handle(buf, line)
	if handle and not referenced()[handle] then
		state[handle] = nil
		store.release(handle)
	end
end

local function resolve(buf, line)
	buf = buf or vim.api.nvim_get_current_buf()
	line = line or vim.api.nvim_win_get_cursor(0)[1]
	return buf, line
end

--- Add a plain breakpoint if the line has none.
local function ensure_breakpoint(buf, line)
	if store.breakpoint(buf, line) then return true end
	require('dap.breakpoints').set({}, buf, line)
	store.refresh(buf)
	return store.breakpoint(buf, line) ~= nil
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
		local pbuf, pline = store.locate(handle)
		return { buf = pbuf, line = pline }
	end, parents_of(buf, line))
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
		store.set(buf, line, 'command', text ~= '' and text or nil)
		store.set(buf, line, 'stop', opts.stop == true)
	end
	if cmd then return apply(cmd) end
	vim.ui.input({ prompt = 'Command on breakpoint: ', default = store.breakpoint(buf, line)
		and store.get(buf, line, 'command') or '' }, apply)
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
	local _, handle = state_for(buf, line)
	if handle then state[handle].hits = 0 end
	store.set(buf, line, 'reset', value)
	maybe_release(buf, line)
end

--- Make the breakpoint at buf/line wait on `targets` (list of `{ buf, line }`
--- of existing breakpoints). An empty list removes the chain.
function M.set_parents(targets, buf, line)
	if not guard() then return end
	buf, line = resolve(buf, line)
	if not ensure_breakpoint(buf, line) then return end
	local own = store.handle(buf, line)
	local handles, seen = {}, {}
	for _, target in ipairs(targets) do
		local handle = store.handle(target.buf, target.line)
		if handle and handle ~= own and not seen[handle] then
			seen[handle] = true
			handles[#handles + 1] = handle
		end
	end
	local previous = parents_of(buf, line)
	local entry = state[own] or { hits = 0 }
	entry.armed = #handles == 0
	state[own] = entry
	store.set(buf, line, 'parents', #handles > 0 and handles or nil)
	for _, handle in ipairs(previous) do
		if not seen[handle] then
			local pbuf, pline = store.locate(handle)
			if pbuf then maybe_release(pbuf, pline) end
		end
	end
	maybe_release(buf, line)
end

--- Whether `handle`'s breakpoint (transitively) waits on the breakpoint `target`.
local function waits_on(handle, target, visited)
	if handle == target then return true end
	visited = visited or {}
	if visited[handle] then return false end
	visited[handle] = true
	local pbuf, pline = store.locate(handle)
	if not pbuf then return false end
	for _, parent in ipairs(parents_of(pbuf, pline)) do
		if waits_on(parent, target, visited) then return true end
	end
	return false
end

--- Candidates for parents of buf/line: every other breakpoint that would not
--- create a loop.
local function candidates(buf, line)
	local own = store.handle(buf, line)
	local result = {}
	for _, data in ipairs(store.list()) do
		for _, entry in ipairs(data.breakpoints) do
			if not (entry.buf == buf and entry.line == line) then
				local handle = store.handle(entry.buf, entry.line)
				local loops = false
				for _, parent in ipairs(entry.properties.parents or {}) do
					if waits_on(parent, own) then loops = true end
				end
				if not loops then
					local text = vim.api.nvim_buf_get_lines(entry.buf, entry.line - 1, entry.line, false)[1] or ''
					result[#result + 1] = {
						buf = entry.buf, line = entry.line, handle = handle,
						label = location_text(entry.buf, entry.line) .. '  ' .. vim.trim(text),
					}
				end
			end
		end
	end
	-- Handles made only to list candidates are released again.
	for _, candidate in ipairs(result) do maybe_release(candidate.buf, candidate.line) end
	return result
end

local function telescope_pick(items, current, on_done)
	local ok = pcall(require, 'telescope')
	if not ok then return false end
	local pickers, finders = require('telescope.pickers'), require('telescope.finders')
	local actions, action_state = require('telescope.actions'), require('telescope.actions.state')
	local conf = require('telescope.config').values
	local entries = { { label = '(no parents)', none = true } }
	vim.list_extend(entries, items)
	pickers.new({}, {
		prompt_title = 'Parent breakpoints (<Tab> selects several)',
		finder = finders.new_table({
			results = entries,
			entry_maker = function(item)
				local mark = item.handle and current[item.handle] and '[x] ' or (item.none and '' or '[ ] ')
				return { value = item, display = mark .. item.label, ordinal = item.label }
			end,
		}),
		sorter = conf.generic_sorter({}),
		attach_mappings = function(prompt_bufnr)
			actions.select_default:replace(function()
				local picker = action_state.get_current_picker(prompt_bufnr)
				local selected = vim.tbl_map(function(entry) return entry.value end, picker:get_multi_selection())
				if #selected == 0 then selected = { action_state.get_selected_entry().value } end
				actions.close(prompt_bufnr)
				on_done(vim.tbl_filter(function(item) return not item.none end, selected))
			end)
			return true
		end,
	}):find()
	return true
end

local function select_pick(items, current, on_done)
	local chosen = {}
	for _, item in ipairs(items) do chosen[item] = current[item.handle] or false end
	local function step()
		local choices = vim.list_extend({}, items)
		choices[#choices + 1] = { done = true, label = 'Done' }
		vim.ui.select(choices, {
			prompt = 'Parent breakpoints (pick to toggle, then Done):',
			format_item = function(item)
				if item.done then return item.label end
				return (chosen[item] and '[x] ' or '[ ] ') .. item.label
			end,
		}, function(item)
			if not item then return end
			if item.done then
				return on_done(vim.tbl_filter(function(candidate) return chosen[candidate] end, items))
			end
			chosen[item] = not chosen[item]
			step()
		end)
	end
	step()
end

--- Pick the parents of the breakpoint at buf/line (default: cursor) from the
--- other breakpoints, with Telescope when installed, else vim.ui.select.
function M.chain(buf, line)
	if not guard() then return end
	buf, line = resolve(buf, line)
	if not ensure_breakpoint(buf, line) then return end
	local items = candidates(buf, line)
	if #items == 0 then
		vim.notify('No other breakpoints to chain to', vim.log.levels.INFO)
		return
	end
	local current = {}
	for _, handle in ipairs(parents_of(buf, line)) do current[handle] = true end
	local function done(selected)
		M.set_parents(selected, buf, line)
	end
	if not telescope_pick(items, current, done) then select_pick(items, current, done) end
end

--- Whether a chained or limited breakpoint is currently on (rule for dapui).
local function rule(bp)
	if not tracked(bp.buf, bp.line) then return true end
	local entry = state_for(bp.buf, bp.line)
	return not entry or entry.armed
end

local function on_hit(buf, line)
	local changed = { [buf] = true }
	if tracked(buf, line) then
		local entry = state_for(buf, line)
		entry.hits = entry.hits + 1
		local reset = store.get(buf, line, 'reset')
		if type(reset) == 'number' and entry.hits >= reset then entry.armed = false end
	end
	for _, data in ipairs(store.list()) do
		for _, child in ipairs(data.breakpoints) do
			for _, handle in ipairs(child.properties.parents or {}) do
				local pbuf, pline = store.locate(handle)
				if pbuf == buf and pline == line and child.properties.enabled then
					local entry = state_for(child.buf, child.line)
					entry.armed, entry.hits = true, 0
					changed[child.buf] = true
				end
			end
		end
	end
	for changed_buf in pairs(changed) do store.refresh(changed_buf) end
end

--- Run commands of the hit breakpoints once nvim-dap has finished handling
--- the stop, then continue unless a breakpoint should stay stopped.
local function run_commands(session, thread_id, hits)
	local commands, resume = {}, true
	for _, hit in ipairs(hits) do
		local command = store.get(hit.buf, hit.line, 'command')
		if command and command ~= '' then
			commands[#commands + 1] = command
			if store.get(hit.buf, hit.line, 'stop') then resume = false end
		else
			resume = false
		end
	end
	if #commands == 0 then return end
	local deadline = vim.uv.now() + 2000
	-- nvim-dap keeps the previous frame until the new stack trace arrives.
	local previous = session.current_frame
	local function ready()
		return session.stopped_thread_id == thread_id and session.current_frame ~= nil
			and session.current_frame ~= previous
	end
	local function run()
		if not ready() and vim.uv.now() < deadline then
			vim.defer_fn(run, 10)
			return
		end
		for _, command in ipairs(commands) do
			local ok, err = pcall(vim.cmd, command)
			if not ok then
				vim.notify('Breakpoint command failed: ' .. tostring(err), vim.log.levels.ERROR)
			end
		end
		if resume and not session.closed then
			if session.stopped_thread_id == thread_id and session._step then
				session:_step('continue')
			else
				session:request('continue', { threadId = thread_id }, function() end)
			end
		end
	end
	vim.schedule(run)
end

local function buffer_for_path(path)
	if not path then return nil end
	local target = vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
	for _, data in ipairs(store.list()) do
		if vim.fs.normalize(vim.fn.fnamemodify(data.name, ':p')) == target then return data.buffer end
	end
end

local function hits_from_ids(ids)
	local wanted, hits = {}, {}
	for _, id in ipairs(ids or {}) do wanted[id] = true end
	if next(wanted) == nil then return hits end
	for buf, buf_bps in pairs(require('dap.breakpoints').get()) do
		for _, bp in ipairs(buf_bps) do
			if bp.state and wanted[bp.state.id] then hits[#hits + 1] = { buf = buf, line = bp.line } end
		end
	end
	return hits
end

local function hits_from_frame(frame)
	local buf = frame and frame.source and buffer_for_path(frame.source.path)
	if not buf then return {} end
	for _, bp in ipairs(require('dap.breakpoints').get(buf)[buf] or {}) do
		if bp.line == frame.line or (bp.state and bp.state.line == frame.line) then
			return { { buf = buf, line = bp.line } }
		end
	end
	return {}
end

--- Stops waiting for their top frame: session → thread id → true.
local pending = setmetatable({}, { __mode = 'k' })

local function handle_hits(session, thread_id, hits)
	for _, hit in ipairs(hits) do on_hit(hit.buf, hit.line) end
	run_commands(session, thread_id, hits)
end

function M._on_stopped(session, body)
	if not body or body.reason ~= 'breakpoint' then return end
	local hits = hits_from_ids(body.hitBreakpointIds)
	if #hits > 0 or not body.threadId then return handle_hits(session, body.threadId, hits) end
	-- Without hit ids, match the top frame. nvim-dap requests it itself; its
	-- response is handled in _on_stack_trace before nvim-dap shows the frame,
	-- so breakpoints are updated before anyone can continue.
	pending[session] = pending[session] or {}
	pending[session][body.threadId] = true
	vim.defer_fn(function()
		if not (pending[session] and pending[session][body.threadId]) then return end
		session:request('stackTrace', { threadId = body.threadId, startFrame = 0, levels = 1 }, function(err, response)
			M._on_stack_trace(session, err, response, { threadId = body.threadId, startFrame = 0 })
		end)
	end, 1000)
end

function M._on_stack_trace(session, err, response, request)
	local threads = pending[session]
	local thread_id = request and request.threadId
	if err or not response or not threads or not threads[thread_id] or (request.startFrame or 0) ~= 0 then return end
	threads[thread_id] = nil
	handle_hits(session, thread_id, hits_from_frame((response.stackFrames or {})[1]))
end

function M._on_initialized()
	state = {}
end

local function format_parents(handles)
	if not handles or #handles == 0 then return '(none)' end
	return table.concat(vim.tbl_map(function(handle) return location_text(store.locate(handle)) end, handles), ', ')
end

local function format_reset(value)
	if type(value) == 'number' then return string.format('after %d hit%s', value, value == 1 and '' or 's') end
	return 'on restart'
end

local function register()
	store.register('command', {
		label = 'Command', type = 'string',
		summary = function(value) return 'Command: ' .. value end,
		sign = function() return { '⚡', 'DapBreakpointCommand' } end,
	})
	store.register('stop', {
		label = 'Stay stopped after command', type = 'boolean', default = false,
		summary = function() return 'Stays stopped after command' end,
	})
	store.register('parents', {
		label = 'Parents', type = 'custom', default = nil,
		format = function(value) return format_parents(value) end,
		summary = function(value, bp)
			local entry = state_for(bp.buf, bp.line)
			local waiting = entry and not entry.armed and ' (waiting)' or ''
			return 'Parents: ' .. format_parents(value) .. waiting
		end,
		edit = function(bp) M.chain(bp.buf, bp.line) end,
	})
	store.register('reset', {
		label = 'Turns off', type = 'custom', default = 'restart',
		format = format_reset,
		summary = function(value, bp)
			local entry = state_for(bp.buf, bp.line)
			return string.format('Turns off: %s (%d so far)', format_reset(value), entry and entry.hits or 0)
		end,
		edit = function(bp, current)
			vim.ui.input({ prompt = 'Turns off ("restart" or number of hits): ',
				default = tostring(current or 'restart') }, function(input)
				if not input then return end
				input = vim.trim(input)
				M.set_reset(input == '' and 'restart' or tonumber(input) or input, bp.buf, bp.line)
			end)
		end,
	})
	store.add_rule('dap-extra.chain', rule)
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
	store = module
	vim.api.nvim_set_hl(0, 'DapBreakpointCommand', { default = true, link = 'DiagnosticWarn' })
	register()
	local dap = require('dap')
	dap.listeners.before.event_initialized['dap-extra.breakpoints'] = M._on_initialized
	dap.listeners.after.event_stopped['dap-extra.breakpoints'] = M._on_stopped
	dap.listeners.before.stackTrace['dap-extra.breakpoints'] = M._on_stack_trace
	M.available, configured = true, true
end

return M
