local config = require("task-manager.config")

local M = {}

---Expand a brace pattern like "dir/{plan,tasks,spec}" into ordered candidates.
---Returns a list of absolute paths to try in order.
---@param spec string
---@param cwd  string
---@return string[]
local function candidates(spec, cwd)
  local abs = vim.startswith(spec, "/") and spec or (cwd .. "/" .. spec)
  local stat = vim.loop.fs_stat(abs)

  -- Plain directory: try default names in order
  if stat and stat.type == "directory" then
    local dir = abs:gsub("/$", "")
    local names = { "plan", "tasks", "spec" }
    local result = {}
    for _, name in ipairs(names) do
      result[#result + 1] = dir .. "/" .. name .. ".md"
    end
    return result
  end

  -- Brace glob: "dir/{a,b,c}" or "{a,b,c}"
  local prefix, brace = spec:match("^(.-)%{(.-)%}(.*)$")
  if brace then
    local suffix = spec:match("^.-%{.-%}(.*)$") or ""
    local result = {}
    for name in brace:gmatch("[^,]+") do
      local p = prefix .. name .. suffix
      if not vim.startswith(p, "/") then p = cwd .. "/" .. p end
      -- add .md if no extension
      if not p:match("%.%w+$") then p = p .. ".md" end
      result[#result + 1] = p
    end
    return result
  end

  -- Plain file
  return { abs }
end

---Open the spec file defined in config.spec.
---Supports plain file, directory (tries plan/tasks/spec.md in order),
---and brace glob patterns like "docs/{plan,tasks,spec}".
function M.open()
  local spec = config.options.spec or "plan/tasks.md"
  local cwd  = vim.fn.getcwd()
  local list = candidates(spec, cwd)

  for _, path in ipairs(list) do
    local stat = vim.loop.fs_stat(path)
    if stat and stat.type == "file" then
      vim.cmd("edit " .. vim.fn.fnameescape(path))
      return
    end
  end

  -- Nothing found: open the first candidate (new buffer)
  vim.cmd("edit " .. vim.fn.fnameescape(list[1]))
end

return M
