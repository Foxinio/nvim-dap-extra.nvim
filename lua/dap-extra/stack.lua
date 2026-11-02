local M = {}

function M.command(command, args)
	local repl = require('dap.repl')
	local session = require('dap').session()
	local thread = session and session.threads[session.stopped_thread_id]
	local frames = thread and thread.frames
	if not frames or not session.current_frame then
		repl.append('Stack navigation requires a stopped session with loaded frames')
		return
	end
	args = vim.trim(args or '')
	if args ~= '' and not args:match('^%d+$') then
		repl.append('Usage: ' .. command .. ' [non-negative integer]')
		return
	end
	local number = args ~= '' and tonumber(args) or nil
	local function describe(index)
		local frame = frames[index]
		local source = frame.source or {}
		return string.format('#%d %s at %s:%d', index - 1, frame.name, source.path or source.name or '?', frame.line or 0)
	end
	if command == 'bt' then
		for index = 1, math.min(number or #frames, #frames) do repl.append(describe(index)) end
		return
	end
	local current
	for index, frame in ipairs(frames) do
		if frame.id == session.current_frame.id then current = index; break end
	end
	if not current then repl.append('Current frame is not in the loaded stack'); return end
	local target = current
	if command == 'frame' then
		target = number and number + 1 or current
		if target < 1 or target > #frames then repl.append('No frame #' .. tostring(number)); return end
	else
		target = math.max(1, math.min(#frames, current + (command == 'up' and 1 or -1) * (number or 1)))
	end
	session:_frame_set(frames[target])
	repl.append(describe(target))
end

return M
