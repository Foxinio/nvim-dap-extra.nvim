--- Choosing parent breakpoints: candidates without loops, and the pickers.
local M = {}

local state = require('dap-extra.breakpoints.state')

--- Whether `handle`'s breakpoint (transitively) waits on the breakpoint `target`.
local function waits_on(handle, target, visited)
	if handle == target then return true end
	visited = visited or {}
	if visited[handle] then return false end
	visited[handle] = true
	local pbuf, pline = state.store.locate(handle)
	if not pbuf then return false end
	for _, parent in ipairs(state.parents_of(pbuf, pline)) do
		if waits_on(parent, target, visited) then return true end
	end
	return false
end

--- Candidates for parents of buf/line: every other breakpoint that would not
--- create a loop.
function M.candidates(buf, line)
	local own = state.store.handle(buf, line)
	local result = {}
	for _, data in ipairs(state.store.list()) do
		for _, entry in ipairs(data.breakpoints) do
			if not (entry.buf == buf and entry.line == line) then
				local handle = state.store.handle(entry.buf, entry.line)
				local loops = false
				for _, parent in ipairs(entry.properties.parents or {}) do
					if waits_on(parent, own) then loops = true end
				end
				if not loops then
					local text = vim.api.nvim_buf_get_lines(entry.buf, entry.line - 1, entry.line, false)[1] or ''
					result[#result + 1] = {
						buf = entry.buf, line = entry.line, handle = handle,
						label = state.location_text(entry.buf, entry.line) .. '  ' .. vim.trim(text),
					}
				end
			end
		end
	end
	-- Handles made only to list candidates are released again.
	for _, candidate in ipairs(result) do state.maybe_release(candidate.buf, candidate.line) end
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

--- Let the user pick from `items`; `current` marks the current parents
--- (handle → true). Calls `on_done(selected)`. Uses Telescope when installed.
function M.pick(items, current, on_done)
	if not telescope_pick(items, current, on_done) then select_pick(items, current, on_done) end
end

return M
