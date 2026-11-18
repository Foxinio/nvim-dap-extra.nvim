# nvim-dap-extra.nvim

Extras for [nvim-dap](https://github.com/mfussenegger/nvim-dap): GDB-style REPL
commands with prefix history, stack navigation commands, cppdbg defaults,
nvim-dap-virtual-text and sign setup, and showing the selected frame in the
current window. Requires Neovim 0.11+. It does not need nvim-dap-ui.

The debugger UI parts that used to live here (the dedicated debug tab, source
routing, pane bindings, `:DapRestoreLayout`, `:DapClean`) are now part of the
[Foxinio/nvim-dap-ui](https://github.com/Foxinio/nvim-dap-ui) fork
(`:help dapui.debug_tab`).

## Installation

```lua
{
  'Foxinio/nvim-dap-extra.nvim',
  lazy = false,
  dependencies = { 'mfussenegger/nvim-dap', 'theHamsta/nvim-dap-virtual-text' },
  opts = { virtual_text = {} },
}
```

`require('dap-extra').setup(opts)` merges `virtual_text` over the bundled
nvim-dap-virtual-text defaults. Setup may be repeated; listeners, commands and
history hooks do not stack. Adapter registration, language configurations,
Mason, dap-ui and global mappings belong to the caller. Only the GDB REPL
shortcuts need a GDB/cppdbg session.

For `cppdbg` sessions with `MIMode = 'gdb'` (or omitted), setup automatically
adds `catch throw`,
`handle SIGABRT SIGSEGV SIGBUS SIGILL SIGFPE stop print pass`, and a pending
`pthread_kill` function breakpoint to startup commands.
This stops on every C++ throw, including handled exceptions, and on common fatal
signals before delivery, including assertion failures that call `abort()`.
Continuing delivers the signal and may terminate the program. Existing
`setupCommands` run afterward and can override signal handling. Other adapters
and explicit LLDB sessions are unchanged. Every `pthread_kill` call stops,
including calls sending harmless signals.

## Selected frame here

```lua
vim.keymap.set('n', '<leader>dg', require('dap-extra').local_frame)
```

`local_frame()` shows the selected frame's source in the current window, for
files and adapter-provided sources, without changing windows, tabs or the
selected frame. A missing source is reported and nothing moves.

## REPL

The REPL accepts `s`, `n`, `si`, `ni`, `fin`, `c`, `p expression`, `i locals`,
and `gdb arbitrary-command`.
Use `r` or `run` to restart the current session from the beginning, or start
the last debug configuration when no session is active. If nothing has been
run yet, nvim-dap reports that no configuration is available to rerun.

Use `q` or `quit` to terminate the current debug session asynchronously. Wait
for the `Debugging stopped` notification before closing the debug tab. These
commands request termination even for attached programs; debugger panes remain
open. With no active session they report
`No active debug session`. Process termination depends on
the adapter honoring the request.

Multiline definitions belong in startup commands; this is a DAP REPL, not an
interactive terminal.

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
make test       # test.lua, test_controls.lua (nvim-dap only)
make test-live  # test_focus_live.lua, test_exceptions_live.lua (also need the dap-ui fork: make deps-live)
```

Run from this plugin directory. Tests use only declared dependencies in
Neovim's data/lazy (`DEPS_DIR` or `NVIM_TEST_DEPENDENCIES` overrides the parent
directory; `make deps test DEPS_DIR=.deps` clones them, as CI does) and change
to an unrelated cwd. The live suites need cc, c++, GDB, ptrace and OpenDebugAD7
in Neovim's data/mason/bin.
