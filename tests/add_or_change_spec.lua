local add_or_change = require("task-manager.add_or_change")
local config        = require("task-manager.config")

describe("add_or_change", function()
  local bufnr
  local orig_input

  before_each(function()
    config.setup({})
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    orig_input = vim.ui.input
  end)

  after_each(function()
    vim.ui.input = orig_input
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  local function set(lines, lnum)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { lnum, 0 })
  end

  local function get()
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  end

  local function answer(name)
    vim.ui.input = function(_, cb) cb(name) end
  end

  describe("action", function()
    it("returns 'add' for an empty line", function()
      set({ "" }, 1)
      assert.equals("add", add_or_change.action(bufnr, 1))
    end)

    it("returns 'add' for a whitespace-only line", function()
      set({ "   " }, 1)
      assert.equals("add", add_or_change.action(bufnr, 1))
    end)

    it("returns 'change' for a plain text line", function()
      set({ "hello" }, 1)
      assert.equals("change", add_or_change.action(bufnr, 1))
    end)

    it("returns 'change' for an fts line", function()
      set({ "## Feature 1: A" }, 1)
      assert.equals("change", add_or_change.action(bufnr, 1))
    end)
  end)

  describe("add_or_change_cursor", function()
    it("adds a feature on an empty line", function()
      set({ "" }, 1)
      answer("New")
      add_or_change.add_or_change_cursor("feature")
      assert.equals("## Feature 1: New", get()[1])
    end)

    it("adds a task on an empty line", function()
      set({ "## Feature 1: A", "" }, 2)
      answer("Do it")
      add_or_change.add_or_change_cursor("task")
      assert.equals("- [ ] 1.1 Do it", get()[2])
    end)

    it("adds a subtask on an empty line", function()
      set({ "## Feature 1: A", "- [ ] 1.1 T", "" }, 3)
      answer("Sub")
      add_or_change.add_or_change_cursor("subtask")
      -- add_subtask_cursor inserts below the cursor line
      assert.truthy(get()[4]:match("^%s+%- %[ %] 1%.1%.1 Sub$"))
    end)

    it("changes a plain text line to a feature without prompting", function()
      set({ "My Feature" }, 1)
      vim.ui.input = function() error("should not prompt") end
      add_or_change.add_or_change_cursor("feature")
      assert.are.same({ "## Feature 1: My Feature" }, get())
    end)

    it("changes a plain text line to a task", function()
      set({ "## Feature 1: A", "thing" }, 2)
      add_or_change.add_or_change_cursor("task")
      assert.are.same({ "## Feature 1: A", "- [ ] 1.1 thing" }, get())
    end)

    it("changes an existing task to a subtask", function()
      set({ "## Feature 1: A", "- [ ] 1.1 T", "- [ ] 1.2 U" }, 3)
      add_or_change.add_or_change_cursor("subtask")
      local lines = get()
      assert.equals("- [ ] 1.1 T", lines[2])
      assert.truthy(lines[3]:match("^%s+%- %[ %] 1%.1%.1 U$"))
    end)

    it("does nothing for an unknown kind", function()
      set({ "text" }, 1)
      local orig_notify = vim.notify
      vim.notify = function() end
      add_or_change.add_or_change_cursor("bogus")
      vim.notify = orig_notify
      assert.are.same({ "text" }, get())
    end)
  end)
end)
