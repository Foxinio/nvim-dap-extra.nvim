--- Warn when the program being debugged is rebuilt during a session. Only a
--- notification: the session keeps running the build it started with.
local M = {}

local uv = vim.uv or vim.loop
--- session id → { handle, timer, stat }
local watchers = {}
local configured = false

local function changed(old, new)
	return old.ino ~= new.ino or old.size ~= new.size
		or old.mtime.sec ~= new.mtime.sec or old.mtime.nsec ~= new.mtime.nsec
end

local function close(handle)
	if handle and not handle:is_closing() then
		handle:stop()
		handle:close()
	end
end

function M.stop(session)
	local watcher = session and watchers[session.id]
	if not watcher then return end
	watchers[session.id] = nil
	close(watcher.handle)
	close(watcher.timer)
end

function M.start(session)
	local program = session and session.config and session.config.program
	if type(program) ~= 'string' or program == '' then return end
	program = vim.fn.fnamemodify(program, ':p')
	local stat = uv.fs_stat(program)
	if not stat or stat.type ~= 'file' then return end
	M.stop(session)
	local directory, name = vim.fs.dirname(program), vim.fs.basename(program)
	local handle, timer = uv.new_fs_event(), uv.new_timer()
	if not handle or not timer then
		close(handle)
		close(timer)
		return
	end
	local watcher = { handle = handle, timer = timer, stat = stat }
	-- Called in libuv's fast context: only stat here, notify via vim.schedule.
	local function check()
		if watchers[session.id] ~= watcher then return end
		local current = uv.fs_stat(program)
		if not current or not changed(watcher.stat, current) then return end
		watcher.stat = current
		vim.schedule(function()
			vim.notify(('dap-extra: %s was rebuilt; this session still runs the previous build '
				.. '(restart with r to load the new one)'):format(vim.fn.fnamemodify(program, ':~:.')),
				vim.log.levels.WARN)
		end)
	end
	local ok = handle:start(directory, {}, function(err, filename)
		if err or (filename and filename ~= name) then return end
		-- Linkers write in several steps: check once things settle.
		timer:stop()
		timer:start(300, 0, check)
	end)
	if not ok then
		close(handle)
		close(timer)
		return
	end
	watchers[session.id] = watcher
end

--- Watch launched/attached programs for rebuilds unless `enabled` is false.
function M.setup(enabled)
	local dap = require('dap')
	if enabled == false then
		for _, event in ipairs({ 'launch', 'attach', 'restart', 'event_terminated', 'event_exited', 'disconnect' }) do
			dap.listeners.after[event]['dap-extra.watch'] = nil
		end
		for id in pairs(watchers) do M.stop({ id = id }) end
		configured = false
		return
	end
	if configured then return end
	local function start(session, err)
		if not err then M.start(session) end
	end
	dap.listeners.after.launch['dap-extra.watch'] = start
	dap.listeners.after.attach['dap-extra.watch'] = start
	-- A restart request reloads the program in the same session: new baseline.
	dap.listeners.after.restart['dap-extra.watch'] = start
	dap.listeners.after.event_terminated['dap-extra.watch'] = M.stop
	dap.listeners.after.event_exited['dap-extra.watch'] = M.stop
	dap.listeners.after.disconnect['dap-extra.watch'] = M.stop
	configured = true
end

--- Number of active watchers (for tests).
function M._count()
	return vim.tbl_count(watchers)
end

return M
