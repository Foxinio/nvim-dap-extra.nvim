--- Shared state: the `dapui.breakpoints` store, and the run-time on/off state
--- and hit counts of chained or limited breakpoints.
local M = {}

--- The dapui.breakpoints module, set by setup when it is found.
M.store = nil
--- handle → { armed = boolean, hits = integer }
M.runtime = {}

--- Forget run-time state (a new session started).
function M.reset()
	M.runtime = {}
end

function M.location_text(buf, line)
	if not buf then return '(removed)' end
	return string.format('%s:%d', vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':~:.'), line)
end

function M.parents_of(buf, line)
	return M.store.get(buf, line, 'parents') or {}
end

--- Whether a breakpoint has run-time state: it has parents or turns off after N hits.
function M.tracked(buf, line)
	return #M.parents_of(buf, line) > 0 or type(M.store.get(buf, line, 'reset')) == 'number'
end

function M.state_for(buf, line)
	local handle = M.store.handle(buf, line)
	if not handle then return nil end
	if not M.runtime[handle] then
		M.runtime[handle] = { armed = #M.parents_of(buf, line) == 0, hits = 0 }
	end
	return M.runtime[handle], handle
end

--- Handles still referenced as a parent by some breakpoint.
local function referenced()
	local result = {}
	for _, data in ipairs(M.store.list()) do
		for _, entry in ipairs(data.breakpoints) do
			for _, handle in ipairs(entry.properties.parents or {}) do result[handle] = true end
		end
	end
	return result
end

--- Let go of a breakpoint's handle once nothing needs it, so its record can go.
function M.maybe_release(buf, line)
	if not M.store.breakpoint(buf, line) or M.tracked(buf, line) then return end
	local handle = M.store.handle(buf, line)
	if handle and not referenced()[handle] then
		M.runtime[handle] = nil
		M.store.release(handle)
	end
end

--- Rule for dapui.breakpoints: whether a chained or limited breakpoint is on.
function M.rule(bp)
	if not M.tracked(bp.buf, bp.line) then return true end
	local entry = M.state_for(bp.buf, bp.line)
	return not entry or entry.armed
end

return M
