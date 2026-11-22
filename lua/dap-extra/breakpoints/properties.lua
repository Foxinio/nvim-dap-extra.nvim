--- The properties dap-extra registers with dapui.breakpoints.
local M = {}

local state = require('dap-extra.breakpoints.state')

local function format_parents(handles)
	if not handles or #handles == 0 then return '(none)' end
	return table.concat(vim.tbl_map(function(handle)
		return state.location_text(state.store.locate(handle))
	end, handles), ', ')
end

local function format_reset(value)
	if type(value) == 'number' then return string.format('after %d hit%s', value, value == 1 and '' or 's') end
	return 'on restart'
end

--- Register command, stop, parents and reset. `actions` gives the editors:
--- `chain(buf, line)` and `set_reset(value, buf, line)`.
function M.register(actions)
	local store = state.store
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
			local entry = state.state_for(bp.buf, bp.line)
			local waiting = entry and not entry.armed and ' (waiting)' or ''
			return 'Parents: ' .. format_parents(value) .. waiting
		end,
		edit = function(bp) actions.chain(bp.buf, bp.line) end,
	})
	store.register('reset', {
		label = 'Turns off', type = 'custom', default = 'restart',
		format = format_reset,
		summary = function(value, bp)
			local entry = state.state_for(bp.buf, bp.line)
			return string.format('Turns off: %s (%d so far)', format_reset(value), entry and entry.hits or 0)
		end,
		edit = function(bp, current)
			vim.ui.input({ prompt = 'Turns off ("restart" or number of hits): ',
				default = tostring(current or 'restart') }, function(input)
				if not input then return end
				input = vim.trim(input)
				actions.set_reset(input == '' and 'restart' or tonumber(input) or input, bp.buf, bp.line)
			end)
		end,
	})
	store.add_rule('dap-extra.chain', state.rule)
end

return M
