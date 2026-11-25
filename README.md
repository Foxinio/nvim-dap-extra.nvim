# nvim-dap-extra.nvim

Extras for [nvim-dap](https://github.com/mfussenegger/nvim-dap): GDB-style REPL
commands with prefix history, stack navigation commands, cppdbg defaults,
nvim-dap-virtual-text and sign setup, and showing the selected frame in the
current window, plus command and chained breakpoints. Requires Neovim 0.11+.
Only command and chained breakpoints need the nvim-dap-ui fork.

The debugger UI parts that used to live here (the dedicated debug tab, source
routing, pane bindings, `:DapRestoreLayout`, `:DapClean`) are now part of the
[Foxinio/nvim-dap-ui](https://github.com/Foxinio/nvim-dap-ui) fork
(`:help dapui.debug_tab`).

## Installation

```lua
{
  'Foxinio/nvim-dap-extra.nvim',
  lazy = false,
  dependencies = {
    'mfussenegger/nvim-dap', 'theHamsta/nvim-dap-virtual-text',
    'Foxinio/nvim-dap-ui', -- optional: command and chained breakpoints
  },
  opts = { virtual_text = {} },
}
```

`require('dap-extra').setup(opts)` merges `virtual_text` over the bundled
nvim-dap-virtual-text defaults. Setup may be repeated; listeners, commands and
history hooks do not stack. Adapter registration, language configurations,
Mason, dap-ui and global mappings belong to the caller. Only the GDB REPL
shortcuts need a GDB/cppdbg session.

For `cppdbg` sessions with `MIMode = 'gdb'` (or omitted), setup automatically
adds `-enable-pretty-printing`, `catch throw`,
`handle SIGABRT SIGSEGV SIGBUS SIGILL SIGFPE stop print pass`, and a pending
`pthread_kill` function breakpoint to startup commands.
This stops on every C++ throw, including handled exceptions, and on common fatal
signals before delivery, including assertion failures that call `abort()`.
Continuing delivers the signal and may terminate the program. Existing
`setupCommands` run afterward and can override signal handling. Other adapters
and explicit LLDB sessions are unchanged. Every `pthread_kill` call stops,
including calls sending harmless signals.

Pretty printing makes GDB use the printers it auto-loads, such as libstdc++'s,
so `std::vector`, `std::string` and `std::map` show their contents instead of
internal members. A GDB without Python support ignores it. To turn it off, add
`{ text = '-disable-pretty-printing' }` to your own `setupCommands`.

`cppdbg` sessions also never stop at `main` on their own: setup turns
`stopAtEntry` off, which configurations copied from common examples set to
`true`. Breakpoints in `main` still stop. To keep your configuration's
`stopAtEntry`, use `opts = { keep_stop_at_entry = true }`.

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

## Command and chained breakpoints

These need the [Foxinio/nvim-dap-ui](https://github.com/Foxinio/nvim-dap-ui)
fork, whose `dapui.breakpoints` module stores the extra properties (see
`:help dapui.breakpoints`). Only that module is loaded, not dap-ui itself.
Without it, setup warns once that this feature is disabled, the commands below
report the same, and everything else works as usual. Pass
`opts = { breakpoints = false }` to turn the feature off without the warning.

- `:DapCommandBreakpoint {cmd}` runs the Vim command `{cmd}` whenever the
  breakpoint on the cursor line is hit, then continues the program. With `!`
  the program stays stopped. Without `{cmd}` you are asked for one; an empty
  command removes it. The command runs while the program is stopped, so it
  can read the frame (for example `:lua print(require('dap').session().current_frame.line)`).
- `:DapChainBreakpoint` picks the breakpoints this one waits on (Telescope
  with `<Tab>` for several, or repeated `vim.ui.select` with a `Done` entry).
  A chained breakpoint is not sent to the debugger until any one of its
  parents is hit. Picking nothing removes the chain.
- `:DapBreakpointReset restart|N` sets when it turns off again: `restart`
  (default) keeps it on until the next run or restart; `N` turns it off after
  N hits, until a parent turns it on again.

Both commands add a plain breakpoint if the line has none. The same functions
are available for mappings:

```lua
local bp = require('dap-extra').breakpoints
vim.keymap.set('n', '<leader>dB', bp.chain)
vim.keymap.set('n', '<leader>dC', function() bp.set_command() end)
-- bp.set_command(cmd, { stop = true }, buf, line), bp.set_parents({ { buf = b, line = l } }, buf, line),
-- bp.set_reset('restart' | n, buf, line), bp.parents(buf, line)
```

In the dap-ui Breakpoints pane, `<CR>` expands any breakpoint into all its
properties (enabled, condition, hit condition, log message, command, stay
stopped, parents, turns off) and `e` edits the one under the cursor.

Signs: a breakpoint that is off (disabled, or waiting for a parent) shows `○`;
an active command breakpoint shows `⚡`. Both stay in nvim-dap's breakpoint
list, so conditions and log messages are kept while they are off.

Limitations: a logpoint never pauses the program, so it cannot act as a
parent. Hit counts and chain state are shared by all sessions running at the
same time and reset whenever a session starts or restarts. Breakpoint hits are
matched by the adapter's `hitBreakpointIds` or, when it sends none (as
OpenDebugAD7 does), by the stopped frame's file and line.

## Rebuild warning

While a session runs, dap-extra watches the debugged `program` (from the
launch or attach configuration). If it is rebuilt, you get one warning per
rebuild: the session still runs the previous build, and `r`/`run` restarts it
with the new one. Nothing else happens; debugging continues as normal. The
watch stops when the session ends. Sessions without a `program` are not
watched. Turn it off with `opts = { watch_program = false }`.

## Checks

```sh
make test       # test.lua, test_controls.lua, test_breakpoints.lua, test_breakpoints_missing.lua, test_watch.lua, test_stop_at_entry.lua
make test-live  # test_focus_live.lua, test_exceptions_live.lua, test_breakpoints_live.lua, test_pretty_printers_live.lua (make deps-live)
```

Run from this plugin directory. Tests use only declared dependencies in
Neovim's data/lazy (`DEPS_DIR` or `NVIM_TEST_DEPENDENCIES` overrides the parent
directory; `make deps test DEPS_DIR=.deps` clones them, as CI does) and change
to an unrelated cwd. The live suites need cc, c++, GDB, ptrace and OpenDebugAD7
in Neovim's data/mason/bin.
