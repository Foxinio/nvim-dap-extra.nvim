--- Noticing which breakpoints were hit, turning chained ones on or off,
--- running commands and continuing.
local M = {}

local state = require('dap-extra.breakpoints.state')

local function on_hit(buf, line)
	local changed = { [buf] = true }
	if state.tracked(buf, line) then
		local entry = state.state_for(buf, line)
		entry.hits = entry.hits + 1
		local reset = state.store.get(buf, line, 'reset')
		if type(reset) == 'number' and entry.hits >= reset then entry.armed = false end
	end
	for _, data in ipairs(state.store.list()) do
		for _, child in ipairs(data.breakpoints) do
			for _, handle in ipairs(child.properties.parents or {}) do
				local pbuf, pline = state.store.locate(handle)
				if pbuf == buf and pline == line and child.properties.enabled then
					local entry = state.state_for(child.buf, child.line)
					entry.armed, entry.hits = true, 0
					changed[child.buf] = true
				end
			end
		end
	end
	for changed_buf in pairs(changed) do state.store.refresh(changed_buf) end
end

--- Run commands of the hit breakpoints once nvim-dap has finished handling
--- the stop, then continue unless a breakpoint should stay stopped.
local function run_commands(session, thread_id, hits)
	local commands, resume = {}, true
	for _, hit in ipairs(hits) do
		local command = state.store.get(hit.buf, hit.line, 'command')
		if command and command ~= '' then
			commands[#commands + 1] = command
			if state.store.get(hit.buf, hit.line, 'stop') then resume = false end
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
	for _, data in ipairs(state.store.list()) do
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

function M.on_stopped(session, body)
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
			M.on_stack_trace(session, err, response, { threadId = body.threadId, startFrame = 0 })
		end)
	end, 1000)
end

function M.on_stack_trace(session, err, response, request)
	local threads = pending[session]
	local thread_id = request and request.threadId
	if err or not response or not threads or not threads[thread_id] or (request.startFrame or 0) ~= 0 then return end
	threads[thread_id] = nil
	handle_hits(session, thread_id, hits_from_frame((response.stackFrames or {})[1]))
end

function M.on_initialized()
	state.reset()
end

return M
