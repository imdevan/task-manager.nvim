

## Feature 1: add AddOrChange command
- [x] 1.1 wrapper around add or change
  - [x] 1.1.1 if line is empty add command with sub commands to add a feature, task, or sub task
  - [x] 1.1.2 if there is already text or another fts on the line, execute the change command
  - [x] 1.1.3 `TaskAddOrChange [feature|task|subtask]` command with completion; prompts for kind when omitted
  - [x] 1.1.4 tests in `tests/add_or_change_spec.lua`

- [x] 1.2 add additional default keybinds for task manager
- change line or create new
ctrl+shift+: (no leader; normal, or insert mode mode)
  - [x] 1.2.1 b - feature (`<C-S-b>`)
  - [x] 1.2.2 n - task (`<C-S-n>`)
  - [x] 1.2.3 m - subask (`<C-S-m>`)
  - [x] 1.2.4 document keymaps and command in README

