# nvim-dap-extra.nvim

Reusable DAP tab/source routing, REPL history and frame commands, pane bindings,
and cleanup. Requires Neovim 0.11+.

## Installation

```lua
{
  'Foxinio/nvim-dap-extra.nvim',
  lazy = false,
  dependencies = {
    'mfussenegger/nvim-dap', 'rcarriga/nvim-dap-ui',
    'nvim-neotest/nvim-nio', 'theHamsta/nvim-dap-virtual-text',
  },
  opts = { dapui = {}, virtual_text = {} },
}
```

`require('dap-extra').setup(opts)` merges `dapui` and `virtual_text` tables
over the bundled UI defaults. Setup may be repeated; listeners, commands,
history hooks and compatibility patches do not stack. Repeated calls leave the
existing configuration in place. Adapter registration,
language configurations, Mason, and global mappings belong to the caller.
Only generic GDB REPL shortcuts need a GDB/cppdbg session; loading the plugin
does not require GDB or an adapter.

For `cppdbg` sessions with `MIMode = 'gdb'` (or omitted), setup automatically
adds `catch throw` and
`handle SIGABRT SIGSEGV SIGBUS SIGILL SIGFPE stop print pass` to startup commands.
This stops on every C++ throw, including handled exceptions, and on common fatal
signals before delivery, including assertion failures that call `abort()`.
Continuing delivers the signal and may terminate the program. Existing
`setupCommands` run afterward and can override signal handling. Other adapters
and explicit LLDB sessions are unchanged; no `pthread_kill` breakpoint is added.

## UI helpers

```lua
local ui = require('dap-extra.ui')
-- Bind these in your own configuration, after loading the plugin:
vim.keymap.set('n', '<F5>', ui.action(function() require('dap').continue() end))
vim.keymap.set('n', '<leader>dg', ui.local_frame)
```

`action(callback, use_cursor)` routes to a shared debug tab and forwards all
arguments. Set `use_cursor` for source-sensitive actions such as run-to-cursor.
`focus()`, `toggle()`, `repl()`, `open()`, `close()`, `jump(buf, line, column)`,
`local_frame()`, `reset()`, and `cleanup()` remain available. Columns passed to `jump`
are one-based. Local frame navigation preserves the selected frame and splits.

The debugger uses one dedicated tab across sessions. Actions wrapped with
`action()`, stack and breakpoint source selection, and pane toggles switch to
that tab. `action(callback, true)` retains the invoking file and cursor;
wrapped actions use the invoking cwd. Bind breakpoint editing and value hover
directly to nvim-dap to keep them in the invoking window and tab.
Use `gt` / `gT` to switch between tabs. Debugger panes stay open after the
program exits or debugging stops, so final output remains available. Use
`:DapClean` to close them explicitly.
Starting a debug session focuses the REPL in insert mode, ready for commands.

Use `:DapReset` to restore configured debugger pane sizes and reopen missing
panes without interrupting debugging. It uses the existing debug tab and does
not reconstruct manually rearranged splits.

Use `:DapClean` to terminate debugging, clear inline debugger annotations and
cached values, and close debugger panes and the REPL, even after a session has
already ended. It preserves the source tab, file buffers and breakpoints. Use
`:tabclose` afterward if you also want to close that tab.

The optional mappings above bind `<F5>` to continue and `<leader>dg` to show
the selected frame in the invoking window, preserving splits and frame
selection, including adapter-provided sources. The plugin installs no global
keymaps.

In Stacks, Enter or `o` selects the frame and focuses its source in the existing
debug source pane; Space or `t` toggles subtle frames for the thread. In
Breakpoints, Enter or `o` focuses the breakpoint's source without changing frame
selection, `t` enables/disables it, and `d` removes it (including disabled entries).
These bindings are buffer-local.

The REPL accepts `s`, `n`, `si`, `ni`, `fin`, `c`, `p expression`, `i locals`,
and `gdb arbitrary-command`.
Use `r` or `run` to restart the current session from the beginning, or start
the last debug configuration when no session is active. If nothing has been
run yet, nvim-dap reports that no configuration is available to rerun.

Use `q` or `quit` to terminate the current debug session asynchronously. Wait
for the `Debugging stopped` notification before closing the debug tab. These
commands request termination even for attached programs, without invoking
`:DapClean`; debugger panes remain open. With no active session they report
`No active debug session`. Process termination depends on
the adapter honoring the request.

The Console uses Neovim's integrated terminal. Long output can be split into
terminal rows even with `nowrap`, and resizing does not repair old scrollback.
See the [Console wrapping investigation](docs/console-wrapping.md) for a
reproduction and follow-up recommendation.

Multiline definitions
belong in startup commands; this pane is a DAP REPL, not an interactive terminal.
REPL commands and subsequent stops update the debug source and variables without
taking focus or leaving REPL input mode. Moving elsewhere during execution is
respected; source-window stack bindings focus the debug source normally.

In insert mode, Up/Down search commands submitted with Enter using the text
you have typed as a prefix. Empty input browses all commands. Down past the
newest match restores your typed prefix; editing it starts a new search.

Use `up [n]` / `down [n]` to move toward callers / callees (default one frame),
`frame n` or `f n` to select a zero-based frame, and `frame` to show the current
frame. `bt [n]`, `backtrace [n]` and `where [n]` list numbered frames, optionally
limited to the first n. Frame selection updates the source and variables through
DAP, keeping them synchronized. Relative moves stop at the ends of the stack.


## Checks

```sh
nvim --headless -u NONE -i NONE -l tests/test.lua
nvim --headless -u NONE -i NONE -l tests/test_panes.lua
nvim --headless -u NONE -i NONE -l tests/test_controls.lua
nvim --headless -u NONE -i NONE -l tests/test_focus_live.lua
nvim --headless -u NONE -i NONE -l tests/test_exceptions_live.lua
```

Run from this plugin directory. Tests use only declared dependencies in
Neovim's data/lazy (`NVIM_TEST_DEPENDENCIES` overrides the parent directory)
and change to an unrelated cwd. The live suites need cc, c++, GDB, ptrace and
OpenDebugAD7 in Neovim's data/mason/bin.
