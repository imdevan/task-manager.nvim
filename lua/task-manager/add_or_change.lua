local utils  = require("task-manager.utils")
local add    = require("task-manager.add")
local change = require("task-manager.change")

local M = {}

---Valid fts kinds accepted by add_or_change.
M.kinds = { "feature", "task", "subtask" }

---Decide whether the line at `lnum` should be added to or changed.
---A blank line gets a new fts added; a line with any text (plain or fts) is changed.
---@param bufnr integer
---@param lnum  integer
---@return "add"|"change"
function M.action(bufnr, lnum)
  return utils.get_line(bufnr, lnum):match("%S") and "change" or "add"
end

---Add a new `kind` if the cursor line is blank, otherwise change the cursor
---line into a `kind`.
---@param kind "feature"|"task"|"subtask"
function M.add_or_change_cursor(kind)
  if not vim.tbl_contains(M.kinds, kind) then
    vim.notify("task-manager: unknown kind '" .. tostring(kind) .. "'", vim.log.levels.ERROR)
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  if M.action(bufnr, utils.cursor_line()) == "add" then
    add["add_" .. kind .. "_cursor"]()
  else
    change["changeTo_" .. kind .. "_cursor"]()
  end
end

---Prompt for a kind, then add or change the cursor line.
function M.add_or_change_prompt()
  vim.ui.select(M.kinds, { prompt = "Add or change to: " }, function(kind)
    if kind then M.add_or_change_cursor(kind) end
  end)
end

return M
