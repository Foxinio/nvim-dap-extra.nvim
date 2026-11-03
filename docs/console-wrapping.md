# Console wrapping investigation

Run the reproduction from the plugin directory:

```sh
nvim --headless -u NONE -i NONE -l tests/investigate_console.lua
```

The reproduction starts `printf` in the actual DAP Console buffer, compares
its raw output with the original payload, and examines the terminal buffer
before and after widening the pane. It checks the current Neovim limitation;
it is an investigation tool, not a portability regression test.

## Result

On Neovim 0.11.7, a 130-character line emitted into a 20-column Console was
split into seven terminal rows. After another 40 lines pushed it into
scrollback, widening the Console to 60 columns left those seven rows unchanged.
The first rows remained:

```text
BEGIN:01234567890123
45678901234567890123
45678901234567890123
```

The raw stdout callback received the complete original line, without added
newlines. The Console window already had `wrap = false`. This reproduces the
problem without the program formatting its output according to terminal width.
Other programs can additionally format output according to their PTY width.

## Cause and supported interfaces

nvim-dap-ui's Console is nvim-dap's integrated terminal, not a plain output
buffer. nvim-dap starts the terminal job with a finite width; Neovim's terminal
emulator splits output into terminal rows. Changing window `wrap` does not
undo those rows. Neovim documents that terminal scrollback lines are not
reflowed when resized horizontally:
[Neovim options](https://neovim.io/doc/user/options/).

`terminal_win_cmd` selects the buffer/window for the terminal; it does not
change how stdout is captured. `jobresize()` sets a finite PTY size, rather
than providing an unlimited-width output stream. `nvim_open_term()` is also
a terminal emulator. None of these interfaces provides a plain, unwrapped
Console while retaining all integrated-terminal behavior.

## Follow-up recommendation

Keep the terminal implementation unchanged in this patch. Do not join stored
rows afterward: real newlines cannot safely be distinguished from terminal
wrapping after the original stream has been rendered.

For a true unwrapped output viewer, investigate adapter-provided output events
first, using the caller's actual adapter configuration. When an adapter can
capture program stdout/stderr directly, display that stream in a normal
`nowrap` buffer, preserving partial lines between events. This would need a
separate design for output routing and would not automatically preserve stdin,
terminal colors, cursor control, or programs requiring a TTY. Adapter launch
configuration remains caller-owned in this plugin.

A wider PTY is only a mitigation: it still has a finite wrap boundary, changes
the width visible to programs, and does not restore already split scrollback.
It should not be presented as a complete fix.
