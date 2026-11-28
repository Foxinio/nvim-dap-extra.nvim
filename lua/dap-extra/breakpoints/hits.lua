--- What a breakpoint hit does: turning chained breakpoints on or off,
--- running commands and continuing. Which breakpoints were hit comes from
--- dap-extra.stops.
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

--- Handle breakpoint hits reported by dap-extra.stops (after its condition
--- check): count them, turn on chained breakpoints, run commands.
function M.handle(session, thread_id, hits)
	for _, hit in ipairs(hits) do on_hit(hit.buf, hit.line) end
	run_commands(session, thread_id, hits)
end

function M.on_initialized()
	state.reset()
end

return M
