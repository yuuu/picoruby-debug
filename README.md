# picoruby-debug

A debugger for PicoRuby. **mruby only** — on mruby/c it prints an "unsupported"
message and does nothing.

This gem is the foundation for an interactive debugger. Dropping a
`binding.debugger` call into a script installs mruby's `code_fetch_hook`,
which checks each new source line against the registered breakpoints and,
when the current mode says to stop, calls back into Ruby (`Debugger#on_break`)
to show an interactive prompt.

## Installation

Add the following line to your build configuration:

```ruby
conf.gem github: 'yuuu/picoruby-debug', branch: 'main'
```

This gem does not depend on `ENV['PICORB_DEBUG']` or any other build flag —
adding it to the gem list is enough to enable `binding.debugger` support, on
any target (POSIX host, ESP32, etc.).

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

| Command | Description |
| --- | --- |
| `c` / `continue` / *(empty)* | Resume execution until the next breakpoint |
| `s` / `step` | Stop at the next line, stepping into calls |
| `n` / `next` | Stop at the next line in the same/shallower frame |
| `q` / `quit` | Stop the script |
| `bt` / `where` | Show the full call stack, innermost frame first (`#0`, `#1`, ...); a frame with no Ruby-level position (e.g. a C frame) is omitted |
| `b` / `break [<file>:]<line>` | Add a breakpoint, or list the current breakpoints (with their numbers) if no argument is given |
| `d` / `delete [<number>]` | Delete breakpoint `<number>` (as shown by `b` with no argument), or all breakpoints if no number is given |
| `l` / `list [<line>]` | Show the source around the current line, or around `<line>` if given (10 lines of context, current line marked with `=>`) |
| `p` / `print <expression>` | Evaluate `<expression>` against the paused frame's locals and print the result (via `Binding#eval`); unavailable if no binding could be built for the current frame |
| `disp` / `display <expression>` | Register an expression to be automatically evaluated and shown every time execution stops, or list the currently registered display expressions (with their numbers) if no argument is given |
| `undisp` / `undisplay [<number>]` | Remove display expression `<number>` (as shown by `display` with no argument), or all of them if no number is given |
| `w` / `watch <expression>` | Stop execution automatically whenever `<expression>`'s value changes, or list the currently registered watchpoints (with their numbers) if no argument is given |
| `uw` / `unwatch [<number>]` | Remove watchpoint `<number>` (as shown by `watch` with no argument), or all of them if no number is given |

## DAP support (experimental, POSIX only)

This gem can act as a minimal
[Debug Adapter Protocol](https://microsoft.github.io/debug-adapter-protocol/)
server, so an editor (e.g. VS Code) can drive it instead of (or alongside)
the `(prdb)` prompt. Two pieces make this up:

- `DapTransport` (`mrblib/dap_transport.rb`) — the wire format only:
  `Content-Length: <n>\r\n\r\n<n bytes of JSON>` framing over a TCP socket.
- `DapSession` (`mrblib/dap_session.rb`) — the request/response layer on top,
  a second front end over the same core `Debugger` operations
  `dispatch_command` (the CLI) already uses. Supported requests:
  `initialize`, `attach` (`launch` is treated as an alias — this debugger
  has no separate "launch a process" step), `setBreakpoints`,
  `configurationDone`, `continue`/`next`/`stepIn`/`stepOut`, `stackTrace`,
  `scopes`, `variables`, `evaluate`, `threads`, `disconnect`; it emits
  `stopped` and `terminated` events. Unhandled requests or a bug in a
  handler get a `success: false` response rather than aborting the session.

Wherever `DapTransport.available?` (i.e. `picoruby-socket` is in the build),
DAP is **on by default** on port 4711 (`Debugger::DEFAULT_DAP_PORT`) — just
`require 'debug'` and `binding.debugger` is enough:

```ruby
require 'debug'

def add(a, b)
  a + b
end

binding.debugger
puts add(1, 2)
```

The first `binding.debugger` call is this debugger's only entry point, so
it's also the one point where "the script hasn't started running yet" and
"we can still talk to a client" overlap: it blocks there until a client
completes the `initialize`/`attach`/`setBreakpoints`/`configurationDone`
handshake, then reports that first stop (reason `"entry"`) and every
subsequent one the same way over the same connection.

Use a different port with `Debugger.listen_dap(port)`, called *before* the
script's first `binding.debugger`. Pass a falsy port
(`Debugger.listen_dap(nil)`/`listen_dap(false)`) to opt back out of DAP
entirely and fall back to the plain `(prdb)` prompt.

`picoruby-socket` is **not** a hard dependency of this gem — a build without
it still compiles, `DapTransport.available?` returns `false`, and the above
just runs under the normal `(prdb)` prompt instead regardless of the default
port. Add `picoruby-socket` to your build config to actually use it.

## Dependencies

- `picoruby-sandbox`
- `picoruby-editor`
- `picoruby-io-console`
- `picoruby-json`
- `mruby-binding` (mruby only)
- `mruby-eval` (mruby only)
- `picoruby-socket` (optional, soft dependency — only needed for
  `DapTransport`; see above)
