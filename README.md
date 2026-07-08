# picoruby-debug

A debugger for PicoRuby. **mruby only** — on mruby/c it prints an "unsupported"
message and does nothing.

This gem is the foundation for an interactive debugger. Dropping a
`binding.debugger` call into a script installs mruby's `code_fetch_hook`,
which checks each new source line against the registered breakpoints and,
when the current mode says to stop, calls back into Ruby (`Debugger#on_break`)
to show an interactive prompt.

## Usage

```ruby
require 'debug'

a = 1
b = 2
binding.debugger # or binding.b / binding.break
c = a + b
puts c
```

Running this script pauses at the `binding.debugger` line and drops you into
an interactive prompt:

```
Breakpoint: /test.rb:5
(prdb)> 
```

From there you can add more breakpoints with `b <line>` (matched by **suffix**
against the file the breakpoint applies to, so `b test.rb:8` matches
`/path/to/test.rb`), then `c` to continue running until the next one is hit.

Commands at the prompt:

- `c` / `continue` / *(empty)* — resume execution until the next breakpoint
- `s` / `step` — stop at the next line, stepping into calls
- `n` / `next` — stop at the next line in the same/shallower frame
- `q` / `quit` — stop the script
- `bt` / `where` — show the current location (full backtrace is a future step)
- `b` / `break [<file>:]<line>` — add a breakpoint, or list the current
  breakpoints (with their numbers) if no argument is given
- `d` / `delete [<number>]` — delete breakpoint `<number>` (as shown by `b`
  with no argument), or all breakpoints if no number is given
- `l` / `list [<line>]` — show the source around the current line, or around
  `<line>` if given (10 lines of context, current line marked with `=>`)
- `p` / `print <expression>` — evaluate `<expression>` against the paused
  frame's locals and print the result (via `Binding#eval`); unavailable if no
  binding could be built for the current frame
- `disp` / `display <expression>` — register an expression to be
  automatically evaluated and shown every time execution stops, or list the
  currently registered display expressions (with their numbers) if no
  argument is given
- `undisp` / `undisplay [<number>]` — remove display expression `<number>`
  (as shown by `display` with no argument), or all of them if no number is
  given
- `w` / `watch <expression>` — stop execution automatically whenever
  `<expression>`'s value changes, or list the currently registered
  watchpoints (with their numbers) if no argument is given
- `uw` / `unwatch [<number>]` — remove watchpoint `<number>` (as shown by
  `watch` with no argument), or all of them if no number is given

## Installation

Add the following line to your build configuration:

```ruby
conf.gem github: 'yuuu/picoruby-debug', branch: 'main'
```

This gem does not depend on `ENV['PICORB_DEBUG']` or any other build flag —
adding it to the gem list is enough to enable `binding.debugger` support, on
any target (POSIX host, ESP32, etc.).

## Dependencies

- `picoruby-sandbox`
- `picoruby-editor`
- `picoruby-io-console`
- `mruby-binding` (mruby only)
- `mruby-eval` (mruby only)
