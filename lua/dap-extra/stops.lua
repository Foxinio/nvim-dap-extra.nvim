--- Which breakpoints a stop hit, and a check that their conditions hold.
---
--- Hits come from the adapter's `hitBreakpointIds`, or, when it sends none (as
--- OpenDebugAD7 does), from the top frame of nvim-dap's own `stackTrace`
--- response, handled before nvim-dap shows the frame.
---
--- cppdbg (MIEngine) replaces a breakpoint whose condition changed while the
--- program runs by adding the new one at once but deleting the old one only at
--- the next stop, so the old unconditional breakpoint can still stop the
--- program. The condition guard evaluates the condition of a hit breakpoint in
--- the stopped frame and continues when it is clearly false.
---
--- Needs only nvim-dap.
local M = {}

--- name → fun(session, thread_id, hits)
local subscribers = {}
local recheck = true
--- Stops waiting for their top frame: session → thread id → true.
local pending = setmetatable({}, { __mode = 'k' })

--- Call `fn(session, thread_id, hits)` for every breakpoint stop that the
--- guard keeps. `hits` is a list of `{ buf, line }` of nvim-dap breakpoints.
function M.subscribe(name, fn)
	subscribers[name] = fn
end

local function notify(session, thread_id, hits)
	for _, fn in pairs(subscribers) do fn(session, thread_id, hits) end
end

local function buffer_for_path(path)
	if not path then return nil end
	local target = vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
	for buf in pairs(require('dap.breakpoints').get()) do
		local name = vim.api.nvim_buf_get_name(buf)
		if vim.fs.normalize(vim.fn.fnamemodify(name, ':p')) == target then return buf end
	end
end

local function hits_from_ids(ids)
	local wanted, hits = {}, {}
	for _, id in ipairs(ids or {}) do wanted[id] = true end
	if next(wanted) == nil then return hits end
	for buf, buf_bps in pairs(require('dap.breakpoints').get()) do
		for _, bp in ipairs(buf_bps) do
			if bp.state and wanted[bp.state.id] then hits[#hits + 1] = { buf = buf, line = bp.line, bp = bp } end
		end
	end
	return hits
end

local function hits_from_frame(frame)
	local buf = frame and frame.source and buffer_for_path(frame.source.path)
	if not buf then return {} end
	for _, bp in ipairs(require('dap.breakpoints').get(buf)[buf] or {}) do
		if bp.line == frame.line or (bp.state and bp.state.line == frame.line) then
			return { { buf = buf, line = bp.line, bp = bp } }
		end
	end
	return {}
end

local function continue(session, thread_id)
	if session.closed then return end
	if session.stopped_thread_id == thread_id and session._step then
		session:_step('continue')
	else
		session:request('continue', { threadId = thread_id }, function() end)
	end
end

local function is_false(result)
	local value = vim.trim(tostring(result or '')):lower()
	return value == 'false' or value == '0'
end

--- Keep hits whose condition is not clearly false; when none is left, continue.
local function guard(session, thread_id, frame_id, hits)
	local checks = {}
	for _, hit in ipairs(hits) do
		local condition = hit.bp and hit.bp.condition
		if condition and condition ~= '' then checks[#checks + 1] = hit end
	end
	if not recheck or #checks == 0 or not frame_id then
		return notify(session, thread_id, hits)
	end
	local rejected, waiting = {}, #checks
	for _, hit in ipairs(checks) do
		session:request('evaluate', { expression = hit.bp.condition, frameId = frame_id, context = 'watch' },
			function(err, response)
				if not err and response and is_false(response.result) then rejected[hit] = true end
				waiting = waiting - 1
				if waiting > 0 then return end
				local kept = vim.tbl_filter(function(candidate) return not rejected[candidate] end, hits)
				if #kept == 0 then
					continue(session, thread_id)
				else
					notify(session, thread_id, kept)
				end
			end)
	end
end

--- Top frame of a thread, from our own request (used when nvim-dap's is not
--- available to us).
local function request_frame(session, thread_id, cb)
	session:request('stackTrace', { threadId = thread_id, startFrame = 0, levels = 1 }, function(err, response)
		cb(not err and response and (response.stackFrames or {})[1] or nil)
	end)
end

function M.on_stopped(session, body)
	if not body or body.reason ~= 'breakpoint' then return end
	local thread_id = body.threadId
	local hits = hits_from_ids(body.hitBreakpointIds)
	if #hits > 0 or not thread_id then
		local needs_frame = recheck and vim.iter(hits):any(function(hit)
			return hit.bp.condition and hit.bp.condition ~= ''
		end)
		if not needs_frame or not thread_id then return notify(session, thread_id, hits) end
		return request_frame(session, thread_id, function(frame)
			guard(session, thread_id, frame and frame.id, hits)
		end)
	end
	-- Without hit ids, match the top frame from nvim-dap's own stackTrace
	-- response (on_stack_trace), falling back to our own request.
	pending[session] = pending[session] or {}
	pending[session][thread_id] = true
	vim.defer_fn(function()
		if not (pending[session] and pending[session][thread_id]) then return end
		request_frame(session, thread_id, function(frame)
			M.on_stack_trace(session, nil, { stackFrames = { frame } }, { threadId = thread_id, startFrame = 0 })
		end)
	end, 1000)
end

function M.on_stack_trace(session, err, response, request)
	local threads = pending[session]
	local thread_id = request and request.threadId
	if err or not response or not threads or not threads[thread_id] or (request.startFrame or 0) ~= 0 then return end
	threads[thread_id] = nil
	local frame = (response.stackFrames or {})[1]
	guard(session, thread_id, frame and frame.id, hits_from_frame(frame))
end

--- Install the listeners. `enabled = false` turns the condition guard off;
--- hits are still reported to subscribers.
function M.setup(enabled)
	recheck = enabled ~= false
	local dap = require('dap')
	dap.listeners.after.event_stopped['dap-extra.stops'] = M.on_stopped
	dap.listeners.before.stackTrace['dap-extra.stops'] = M.on_stack_trace
end

return M
