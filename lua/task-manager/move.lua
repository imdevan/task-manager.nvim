local utils = require("task-manager.utils")
local parser = require("task-manager.parser")
local renumber = require("task-manager.renumber")

local M = {}

---Find the line range [start, end] (1-indexed, inclusive) of a feature block.
---Returns the feature header line and the last line owned by the feature
---(including all tasks, subtasks, and trailing non-fts lines, but NOT the
---blank line separator before the next feature).
---@param bufnr integer
---@param feature_lnum integer  line number of the feature header
---@return integer, integer  start_line, end_line
local function get_feature_range(bufnr, feature_lnum)
	local token = parser.parse_line(utils.get_line(bufnr, feature_lnum))
	if not token or token.type ~= "feature" then
		return feature_lnum, feature_lnum
	end
	local fn = token.fn

	local index = parser.build_index(bufnr)
	local last_own = feature_lnum

	-- Find all lines belonging to this feature
	for _, t in ipairs(index) do
		if t.lnum <= feature_lnum then
			goto continue
		end
		if t.type == "feature" then
			break
		end
		if t.fn == fn then
			last_own = t.lnum
		end
		::continue::
	end

	-- Extend to cover trailing non-fts lines, but stop before blank lines
	-- that separate features
	local total = utils.line_count(bufnr)
	for i = last_own + 1, total do
		local line = utils.get_line(bufnr, i)
		local t = parser.parse_line(line)
		if t then
			-- Hit another fts token, stop
			break
		end
		-- If it's a blank line, check if the next line is a feature
		if line:match("^%s*$") then
			if i < total then
				local next_t = parser.parse_line(utils.get_line(bufnr, i + 1))
				if next_t and next_t.type == "feature" then
					-- This blank line separates features, don't include it
					break
				end
			end
		end
		last_own = i
	end

	return feature_lnum, last_own
end

---Move a feature block up by swapping it with the feature above.
---@param bufnr integer
---@param feature_lnum integer  line number of the feature header to move
---@return boolean  false if the feature is already at the top
function M.move_feature_up(bufnr, feature_lnum)
	local token = parser.parse_line(utils.get_line(bufnr, feature_lnum))
	if not token or token.type ~= "feature" then
		return false
	end

	-- Find the feature above
	local index = parser.build_index(bufnr)
	local prev_feature_lnum = nil
	for _, t in ipairs(index) do
		if t.type == "feature" and t.lnum < feature_lnum then
			prev_feature_lnum = t.lnum
		end
	end

	if not prev_feature_lnum then
		return false
	end -- already at top

	-- Get ranges for both features
	local prev_start, prev_end = get_feature_range(bufnr, prev_feature_lnum)
	local curr_start, curr_end = get_feature_range(bufnr, feature_lnum)

	-- Extract the text blocks
	local prev_lines = vim.api.nvim_buf_get_lines(bufnr, prev_start - 1, prev_end, false)
	local curr_lines = vim.api.nvim_buf_get_lines(bufnr, curr_start - 1, curr_end, false)

	-- Replace the entire range with swapped blocks, adding blank line separator
	local combined = {}
	for _, line in ipairs(curr_lines) do
		table.insert(combined, line)
	end
	table.insert(combined, "") -- blank line separator
	for _, line in ipairs(prev_lines) do
		table.insert(combined, line)
	end

	vim.api.nvim_buf_set_lines(bufnr, prev_start - 1, curr_end, false, combined)

	-- Renumber the entire buffer to fix all numbering
	renumber.renumber(bufnr)

	-- Move cursor to the new position of the moved feature (if in a valid window)
	local new_lnum = prev_start
	if vim.api.nvim_get_current_buf() == bufnr then
		pcall(utils.set_cursor_line, new_lnum)
	end

	return true
end

---Move a feature block down by swapping it with the feature below.
---@param bufnr integer
---@param feature_lnum integer  line number of the feature header to move
---@return boolean  false if the feature is already at the bottom
function M.move_feature_down(bufnr, feature_lnum)
	local token = parser.parse_line(utils.get_line(bufnr, feature_lnum))
	if not token or token.type ~= "feature" then
		return false
	end

	-- Find the feature below
	local index = parser.build_index(bufnr)
	local next_feature_lnum = nil
	for _, t in ipairs(index) do
		if t.type == "feature" and t.lnum > feature_lnum then
			next_feature_lnum = t.lnum
			break
		end
	end

	if not next_feature_lnum then
		return false
	end -- already at bottom

	-- Get ranges for both features
	local curr_start, curr_end = get_feature_range(bufnr, feature_lnum)
	local next_start, next_end = get_feature_range(bufnr, next_feature_lnum)

	-- Extract the text blocks
	local curr_lines = vim.api.nvim_buf_get_lines(bufnr, curr_start - 1, curr_end, false)
	local next_lines = vim.api.nvim_buf_get_lines(bufnr, next_start - 1, next_end, false)

	-- Replace the entire range with swapped blocks, adding blank line separator
	local combined = {}
	for _, line in ipairs(next_lines) do
		table.insert(combined, line)
	end
	table.insert(combined, "") -- blank line separator
	for _, line in ipairs(curr_lines) do
		table.insert(combined, line)
	end

	vim.api.nvim_buf_set_lines(bufnr, curr_start - 1, next_end, false, combined)

	-- Renumber the entire buffer to fix all numbering
	renumber.renumber(bufnr)

	-- Move cursor to the new position of the moved feature (if in a valid window)
	local new_lnum = curr_start + #next_lines + 1
	if vim.api.nvim_get_current_buf() == bufnr then
		pcall(utils.set_cursor_line, new_lnum)
	end

	return true
end

---Find the line range [start, end] of a task block (task + its subtasks +
---trailing non-fts lines, stopping before the next task or feature).
---@param bufnr integer
---@param task_lnum integer  line number of the task
---@return integer, integer  start_line, end_line
local function get_task_range(bufnr, task_lnum)
	local token = parser.parse_line(utils.get_line(bufnr, task_lnum))
	if not token or token.type ~= "task" then
		return task_lnum, task_lnum
	end
	local fn = token.fn
	local tn = token.tn

	local index = parser.build_index(bufnr)
	local last_own = task_lnum

	for _, t in ipairs(index) do
		if t.lnum <= task_lnum then
			goto continue
		end
		if t.type == "feature" or (t.type == "task" and t.fn == fn) then
			break
		end
		if t.fn == fn and t.tn == tn then
			last_own = t.lnum
		end
		::continue::
	end

	-- Extend to trailing non-fts lines before the next fts token,
	-- but stop before blank lines or --- separators that form a feature boundary
	local total = utils.line_count(bufnr)
	for i = last_own + 1, total do
		local line = utils.get_line(bufnr, i)
		local t = parser.parse_line(line)
		if t then break end
		if not line:match("%S") then break end
		if line:match("^%s*---%s*$") then break end
		last_own = i
	end

	return task_lnum, last_own
end
---@param bufnr integer
---@param task_lnum integer  line number of the task to move
---@return boolean  false if already at the top of the feature
function M.move_task_up(bufnr, task_lnum)
	local token = parser.parse_line(utils.get_line(bufnr, task_lnum))
	if not token or token.type ~= "task" then
		return false
	end
	local fn = token.fn

	-- Find the task above in the same feature
	local index = parser.build_index(bufnr)
	local prev_task_lnum = nil
	for _, t in ipairs(index) do
		if t.type == "task" and t.fn == fn and t.lnum < task_lnum then
			prev_task_lnum = t.lnum
		end
	end

	if not prev_task_lnum then
		return false
	end

	local prev_start, prev_end = get_task_range(bufnr, prev_task_lnum)
	local curr_start, curr_end = get_task_range(bufnr, task_lnum)

	local prev_lines = vim.api.nvim_buf_get_lines(bufnr, prev_start - 1, prev_end, false)
	local curr_lines = vim.api.nvim_buf_get_lines(bufnr, curr_start - 1, curr_end, false)

	local combined = {}
	for _, line in ipairs(curr_lines) do
		table.insert(combined, line)
	end
	for _, line in ipairs(prev_lines) do
		table.insert(combined, line)
	end

	vim.api.nvim_buf_set_lines(bufnr, prev_start - 1, curr_end, false, combined)
	renumber.renumber(bufnr)

	if vim.api.nvim_get_current_buf() == bufnr then
		pcall(utils.set_cursor_line, prev_start)
	end
	return true
end

---Move a task block down by swapping it with the task below in the same feature.
---@param bufnr integer
---@param task_lnum integer  line number of the task to move
---@return boolean  false if already at the bottom of the feature
function M.move_task_down(bufnr, task_lnum)
	local token = parser.parse_line(utils.get_line(bufnr, task_lnum))
	if not token or token.type ~= "task" then
		return false
	end
	local fn = token.fn

	-- Find the task below in the same feature
	local index = parser.build_index(bufnr)
	local next_task_lnum = nil
	for _, t in ipairs(index) do
		if t.type == "task" and t.fn == fn and t.lnum > task_lnum then
			next_task_lnum = t.lnum
			break
		end
	end

	if not next_task_lnum then
		return false
	end

	local curr_start, curr_end = get_task_range(bufnr, task_lnum)
	local next_start, next_end = get_task_range(bufnr, next_task_lnum)

	local curr_lines = vim.api.nvim_buf_get_lines(bufnr, curr_start - 1, curr_end, false)
	local next_lines = vim.api.nvim_buf_get_lines(bufnr, next_start - 1, next_end, false)

	local combined = {}
	for _, line in ipairs(next_lines) do
		table.insert(combined, line)
	end
	for _, line in ipairs(curr_lines) do
		table.insert(combined, line)
	end

	vim.api.nvim_buf_set_lines(bufnr, curr_start - 1, next_end, false, combined)
	renumber.renumber(bufnr)

	if vim.api.nvim_get_current_buf() == bufnr then
		pcall(utils.set_cursor_line, curr_start + #next_lines)
	end
	return true
end

---Move the task containing the cursor up.
---Works from any line within the task (task or subtask line).
function M.move_task_up_cursor()
	local bufnr = vim.api.nvim_get_current_buf()
	local ctx = parser.context_at(bufnr, utils.cursor_line())
	if not ctx or ctx.type == "feature" then
		return
	end
	local fn, tn = ctx.fn, ctx.tn
	for _, t in ipairs(parser.build_index(bufnr)) do
		if t.type == "task" and t.fn == fn and t.tn == tn then
			M.move_task_up(bufnr, t.lnum)
			return
		end
	end
end

---Move the task containing the cursor down.
---Works from any line within the task (task or subtask line).
function M.move_task_down_cursor()
	local bufnr = vim.api.nvim_get_current_buf()
	local ctx = parser.context_at(bufnr, utils.cursor_line())
	if not ctx or ctx.type == "feature" then
		return
	end
	local fn, tn = ctx.fn, ctx.tn
	for _, t in ipairs(parser.build_index(bufnr)) do
		if t.type == "task" and t.fn == fn and t.tn == tn then
			M.move_task_down(bufnr, t.lnum)
			return
		end
	end
end

---Find the line range [start, end] of a subtask (subtask line + trailing
---non-fts lines, stopping before the next subtask or task).
---@param bufnr integer
---@param subtask_lnum integer  line number of the subtask
---@return integer, integer  start_line, end_line
local function get_subtask_range(bufnr, subtask_lnum)
	local token = parser.parse_line(utils.get_line(bufnr, subtask_lnum))
	if not token or token.type ~= "subtask" then
		return subtask_lnum, subtask_lnum
	end
	local fn = token.fn
	local tn = token.tn

	local last_own = subtask_lnum

	-- Extend to trailing non-fts lines before the next fts token
	local total = utils.line_count(bufnr)
	for i = last_own + 1, total do
		local t = parser.parse_line(utils.get_line(bufnr, i))
		if t then
			break
		end
		last_own = i
	end

	return subtask_lnum, last_own
end

---Move a subtask up by swapping it with the subtask above in the same task.
---@param bufnr integer
---@param subtask_lnum integer  line number of the subtask to move
---@return boolean  false if already at the top of the task
function M.move_subtask_up(bufnr, subtask_lnum)
	local token = parser.parse_line(utils.get_line(bufnr, subtask_lnum))
	if not token or token.type ~= "subtask" then
		return false
	end
	local fn = token.fn
	local tn = token.tn

	-- Find the subtask above in the same task
	local index = parser.build_index(bufnr)
	local prev_subtask_lnum = nil
	for _, t in ipairs(index) do
		if t.type == "subtask" and t.fn == fn and t.tn == tn and t.lnum < subtask_lnum then
			prev_subtask_lnum = t.lnum
		end
	end

	if not prev_subtask_lnum then
		return false
	end

	-- Get ranges for both subtasks (including trailing notes)
	local prev_start, prev_end = get_subtask_range(bufnr, prev_subtask_lnum)
	local curr_start, curr_end = get_subtask_range(bufnr, subtask_lnum)

	-- Extract the text blocks
	local prev_lines = vim.api.nvim_buf_get_lines(bufnr, prev_start - 1, prev_end, false)
	local curr_lines = vim.api.nvim_buf_get_lines(bufnr, curr_start - 1, curr_end, false)

	-- Swap the blocks
	local combined = {}
	for _, line in ipairs(curr_lines) do
		table.insert(combined, line)
	end
	for _, line in ipairs(prev_lines) do
		table.insert(combined, line)
	end

	vim.api.nvim_buf_set_lines(bufnr, prev_start - 1, curr_end, false, combined)

	-- Renumber to fix subtask numbers
	renumber.renumber(bufnr)

	if vim.api.nvim_get_current_buf() == bufnr then
		pcall(utils.set_cursor_line, prev_start)
	end
	return true
end

---Move a subtask down by swapping it with the subtask below in the same task.
---@param bufnr integer
---@param subtask_lnum integer  line number of the subtask to move
---@return boolean  false if already at the bottom of the task
function M.move_subtask_down(bufnr, subtask_lnum)
	local token = parser.parse_line(utils.get_line(bufnr, subtask_lnum))
	if not token or token.type ~= "subtask" then
		return false
	end
	local fn = token.fn
	local tn = token.tn

	-- Find the subtask below in the same task
	local index = parser.build_index(bufnr)
	local next_subtask_lnum = nil
	for _, t in ipairs(index) do
		if t.type == "subtask" and t.fn == fn and t.tn == tn and t.lnum > subtask_lnum then
			next_subtask_lnum = t.lnum
			break
		end
	end

	if not next_subtask_lnum then
		return false
	end

	-- Get ranges for both subtasks (including trailing notes)
	local curr_start, curr_end = get_subtask_range(bufnr, subtask_lnum)
	local next_start, next_end = get_subtask_range(bufnr, next_subtask_lnum)

	-- Extract the text blocks
	local curr_lines = vim.api.nvim_buf_get_lines(bufnr, curr_start - 1, curr_end, false)
	local next_lines = vim.api.nvim_buf_get_lines(bufnr, next_start - 1, next_end, false)

	-- Swap the blocks
	local combined = {}
	for _, line in ipairs(next_lines) do
		table.insert(combined, line)
	end
	for _, line in ipairs(curr_lines) do
		table.insert(combined, line)
	end

	vim.api.nvim_buf_set_lines(bufnr, curr_start - 1, next_end, false, combined)

	-- Renumber to fix subtask numbers
	renumber.renumber(bufnr)

	if vim.api.nvim_get_current_buf() == bufnr then
		pcall(utils.set_cursor_line, curr_start + #next_lines)
	end
	return true
end

---Move the subtask under the cursor up.
function M.move_subtask_up_cursor()
	local bufnr = vim.api.nvim_get_current_buf()
	local ctx = parser.context_at(bufnr, utils.cursor_line())
	if not ctx or ctx.type ~= "subtask" then
		return
	end
	M.move_subtask_up(bufnr, ctx.lnum)
end

---Move the subtask under the cursor down.
function M.move_subtask_down_cursor()
	local bufnr = vim.api.nvim_get_current_buf()
	local ctx = parser.context_at(bufnr, utils.cursor_line())
	if not ctx or ctx.type ~= "subtask" then
		return
	end
	M.move_subtask_down(bufnr, ctx.lnum)
end

---Move the feature containing the cursor up.
function M.move_feature_up_cursor()
	local bufnr = vim.api.nvim_get_current_buf()
	local ctx = parser.context_at(bufnr, utils.cursor_line())
	if not ctx then
		return
	end

	-- Resolve the feature header line
	local feature_lnum
	if ctx.type == "feature" then
		feature_lnum = ctx.lnum
	else
		local fn = ctx.fn
		for _, t in ipairs(parser.build_index(bufnr)) do
			if t.type == "feature" and t.fn == fn then
				feature_lnum = t.lnum
				break
			end
		end
	end

	if not feature_lnum then
		return
	end
	M.move_feature_up(bufnr, feature_lnum)
end

---Move the feature containing the cursor down.
function M.move_feature_down_cursor()
	local bufnr = vim.api.nvim_get_current_buf()
	local ctx = parser.context_at(bufnr, utils.cursor_line())
	if not ctx then
		return
	end

	-- Resolve the feature header line
	local feature_lnum
	if ctx.type == "feature" then
		feature_lnum = ctx.lnum
	else
		local fn = ctx.fn
		for _, t in ipairs(parser.build_index(bufnr)) do
			if t.type == "feature" and t.fn == fn then
				feature_lnum = t.lnum
				break
			end
		end
	end

	if not feature_lnum then
		return
	end
	M.move_feature_down(bufnr, feature_lnum)
end

---Parse a move target string like "3", "3.2", or "3.2.1".
---@param target string
---@return table|nil { type: "feature"|"task"|"subtask", fn: integer, tn?: integer, sn?: integer }
local function parse_move_target(target)
	if not target or target == "" then
		return nil
	end
	local cleaned = target:match("(%d+%.?%d*%.?%d*)") or target
	local parts = vim.split(cleaned, ".", { plain = true })
	local fn = tonumber(parts[1])
	if not fn then
		return nil
	end
	if #parts == 1 then
		return { type = "feature", fn = fn }
	elseif #parts == 2 then
		local tn = tonumber(parts[2])
		if not tn then
			return nil
		end
		return { type = "task", fn = fn, tn = tn }
	elseif #parts >= 3 then
		local tn = tonumber(parts[2])
		local sn = tonumber(parts[3])
		if not tn or not sn then
			return nil
		end
		return { type = "subtask", fn = fn, tn = tn, sn = sn }
	end
	return nil
end

---Move the FTS item at line `lnum` to a target position.
---@param bufnr integer
---@param lnum integer  1-indexed cursor line
---@param target string  target position string e.g. "3", "2.1", "1.2.3"
---@return boolean  true if moved, false otherwise
function M.move_to_target(bufnr, lnum, target)
	local parsed_target = parse_move_target(target)
	if not parsed_target then
		vim.notify(string.format("Invalid move target '%s'", tostring(target)), vim.log.levels.WARN)
		return false
	end

	local ctx = parser.context_at(bufnr, lnum)
	if not ctx then
		vim.notify("No FTS item found at current cursor position", vim.log.levels.WARN)
		return false
	end

	if ctx.type == "feature" then
		local target_fn = parsed_target.fn
		if ctx.fn == target_fn then
			return true
		end

		local index = parser.build_index(bufnr)
		local curr_feat_lnum = nil
		for _, t in ipairs(index) do
			if t.type == "feature" and t.fn == ctx.fn then
				curr_feat_lnum = t.lnum
				break
			end
		end
		if not curr_feat_lnum then
			return false
		end

		local curr_start, curr_end = get_feature_range(bufnr, curr_feat_lnum)
		local curr_lines = vim.api.nvim_buf_get_lines(bufnr, curr_start - 1, curr_end, false)

		-- Trim trailing blank lines from extracted block
		while #curr_lines > 0 and curr_lines[#curr_lines]:match("^%s*$") do
			table.remove(curr_lines)
		end

		-- Remove current feature block (and any surrounding blank line separator) from buffer
		local del_start = curr_start
		local del_end = curr_end
		if del_start > 1 and utils.get_line(bufnr, del_start - 1):match("^%s*$") then
			del_start = del_start - 1
		elseif del_end < utils.line_count(bufnr) and utils.get_line(bufnr, del_end + 1):match("^%s*$") then
			del_end = del_end + 1
		end
		vim.api.nvim_buf_set_lines(bufnr, del_start - 1, del_end, false, {})

		local rem_index = parser.build_index(bufnr)
		local rem_features = {}
		for _, t in ipairs(rem_index) do
			if t.type == "feature" then
				table.insert(rem_features, t)
			end
		end

		local insert_line = 0
		if #rem_features == 0 then
			insert_line = 0
		elseif target_fn <= 1 then
			insert_line = rem_features[1].lnum - 1
		elseif target_fn > #rem_features then
			insert_line = utils.line_count(bufnr)
		else
			insert_line = rem_features[target_fn].lnum - 1
		end

		local to_insert = {}
		for _, l in ipairs(curr_lines) do
			table.insert(to_insert, l)
		end

		if insert_line > 0 then
			local prev_line = utils.get_line(bufnr, insert_line)
			if prev_line:match("%S") then
				table.insert(to_insert, 1, "")
			end
		end

		if insert_line < utils.line_count(bufnr) then
			local next_line = utils.get_line(bufnr, insert_line + 1)
			if next_line:match("%S") then
				table.insert(to_insert, "")
			end
		end

		vim.api.nvim_buf_set_lines(bufnr, insert_line, insert_line, false, to_insert)
		renumber.renumber(bufnr)

		local new_index = parser.build_index(bufnr)
		for _, t in ipairs(new_index) do
			if t.type == "feature" and t.fn == target_fn then
				if vim.api.nvim_get_current_buf() == bufnr then
					pcall(utils.set_cursor_line, t.lnum)
				end
				break
			end
		end
		return true

	elseif ctx.type == "task" or ctx.type == "subtask" then
		local task_lnum = nil
		local index = parser.build_index(bufnr)
		for _, t in ipairs(index) do
			if t.type == "task" and t.fn == ctx.fn and t.tn == ctx.tn then
				task_lnum = t.lnum
				break
			end
		end
		if not task_lnum then
			return false
		end

		local curr_start, curr_end = get_task_range(bufnr, task_lnum)
		local curr_lines = vim.api.nvim_buf_get_lines(bufnr, curr_start - 1, curr_end, false)

		vim.api.nvim_buf_set_lines(bufnr, curr_start - 1, curr_end, false, {})

		local rem_index = parser.build_index(bufnr)
		local target_fn = parsed_target.fn
		local target_tn = parsed_target.tn

		local target_feat_lnum = nil
		local tasks_in_feat = {}
		for _, t in ipairs(rem_index) do
			if t.type == "feature" and t.fn == target_fn then
				target_feat_lnum = t.lnum
			elseif t.type == "task" and t.fn == target_fn then
				table.insert(tasks_in_feat, t)
			end
		end

		local insert_line = 0
		if target_feat_lnum then
			if not target_tn or target_tn > #tasks_in_feat then
				if #tasks_in_feat > 0 then
					local _, last_t_end = get_task_range(bufnr, tasks_in_feat[#tasks_in_feat].lnum)
					insert_line = last_t_end
				else
					insert_line = target_feat_lnum
				end
			elseif target_tn <= 1 then
				if #tasks_in_feat > 0 then
					insert_line = tasks_in_feat[1].lnum - 1
				else
					insert_line = target_feat_lnum
				end
			else
				insert_line = tasks_in_feat[target_tn].lnum - 1
			end
		else
			insert_line = utils.line_count(bufnr)
		end

		vim.api.nvim_buf_set_lines(bufnr, insert_line, insert_line, false, curr_lines)
		renumber.renumber(bufnr)

		local new_index = parser.build_index(bufnr)
		for _, t in ipairs(new_index) do
			if t.type == "task" and t.fn == target_fn then
				if vim.api.nvim_get_current_buf() == bufnr then
					pcall(utils.set_cursor_line, t.lnum)
				end
				break
			end
		end
		return true
	end

	return false
end

---Prompt user for target move location and move item under cursor
function M.move_to_prompt()
	local bufnr = vim.api.nvim_get_current_buf()
	local lnum = utils.cursor_line()
	vim.ui.input({
		prompt = "Move FTS to target (# or #.# or #.#.#): ",
	}, function(input)
		if input and input ~= "" then
			M.move_to_target(bufnr, lnum, input)
		end
	end)
end

return M
