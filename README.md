# mrdebug

An interactive debugger for **mruby**, built to run with nothing but a plain
mruby checkout — no PicoRuby, no extra HAL. Dropping a `binding.debugger`
call into a script pauses it at that line and drops you into a `(prdb)`
prompt.

This is a from-scratch rewrite of the old `picoruby-debug` gem: the core is
now a small, dependency-minimal mrbgem (`mrdebug`) instead of something
built around PicoRuby's console stack. See `docs/plan-phase1.md` for the
full design rationale.

**Phase 1 status**: mruby only, six commands (`continue` / `step` / `next` /
`break` / `delete` / `print`). The core also builds and runs under
PicoRuby's `PICORB_VM_MRUBY` POSIX host build (see
`docs/phase3-picoruby-host-verification.md`), but there's no PicoRuby/R2P2
support beyond that yet — no on-device UI, no R2P2-ESP32 build. See
[Roadmap](#roadmap) for what's intentionally not here yet.

## Installation

This repo doesn't have its own picoruby-style build; you point a plain
mruby checkout's `build_config.rb` at it:

```ruby
conf.gem gemdir: '/absolute/path/to/your/mrdebug/checkout'
```

(Once this repository is renamed off `picoruby-debug`, `conf.gem github:
'<owner>/mrdebug', branch: 'main'` will work the same way.)

That's it — no build flag, no `ENV` variable. Adding the gem enables
`binding.debugger` for that build.

## Usage

```ruby
def add(a, b)
  a + b
end

x = 1
binding.debugger # or binding.b / binding.break
y = add(x, 2)
puts y
```

```
$ bin/mruby script.rb
Breakpoint: script.rb:6
(prdb) n
Breakpoint: script.rb:7
(prdb) p y
nil
(prdb) c
3
```

Add more breakpoints with `break <line>` — matched by **suffix** against the
file the VM reports, so `break foo.rb:8` matches `/path/to/foo.rb`.

| Command | Alias | Description |
| --- | --- | --- |
| `continue` | `c`, empty input | Resume until the next breakpoint |
| `step` | `s` | Stop at the next executed line, including inside a call |
| `next` | `n` | Stop at the next line in the same frame or shallower (does not descend into a call) |
| `break [<file>:]<line>` | `b` | Add a breakpoint (file defaults to the currently stopped file), or list breakpoints with no argument |
| `delete [<number>]` | `d` | Delete breakpoint `<number>` (as listed by `break`), or all breakpoints with no argument |
| `print <expression>` | `p` | Evaluate `<expression>` against the stopped frame's binding |

There's no `quit` yet — let the script run to completion with `continue`.
An unrecognized command prints `unknown command: ...` and stays at the prompt.

### Stepping over mrdebug's own source

`Session` never stops inside this gem's own files (`mrblib/mrdebug/`,
`tools/mrdebug/`) — `MRDebug::OwnSource` is a hardcoded, suffix-matched list
of them (same idiom as breakpoint file matching), checked before any other
stop decision. `step`'s definition — stop at literally every executed line —
would otherwise show a line or two of `mrdebug`'s own source right after a
`binding.debugger` stop, the way CRuby's `debug` gem needs a skip-list for
stdlib/gems.

### Remote debugging over a socket

`binding.debugger`'s `(prdb)` prompt doesn't have to be your script's own
stdin/stdout. On the device side (host builds only):

```ruby
MRDebug.listen_tcp(4711) # blocks until a client connects
binding.debugger
```

then, from a second terminal or machine, the `mrdebug` CLI binary connects
and relays your terminal to that prompt:

```sh
build/host/bin/mrdebug --port 4711
```

`MRDebug.listen_unix('/tmp/my.sock')` and `mrdebug --sock-path /tmp/my.sock`
work the same way over a Unix domain socket. `Command.dispatch` still runs
entirely on the device side — the CLI only pumps bytes between the socket
and your terminal — so this works exactly like running the script locally,
just over a wire. See `docs/manual-verify-socket-transport.md` for a full
worked example.

## How it works

- `binding.debugger` calls into `MRDebug::Session`, a plain Ruby object that
  owns breakpoints and the current run/step/next mode.
- Line-by-line tracing is `src/hook.c`, the *only* C in this gem: it installs
  mruby's `code_fetch_hook` and calls `Session#on_line(file, line)` once per
  executed source line, on a dedicated `mrb_context` so a breakpoint hit deep
  in a recursive call can't corrupt the paused call stack.
- `src/frame.c` (the only other C file) answers frame-count/position/binding
  queries against that paused context, for `next`'s depth comparison and for
  building the `Binding` `print` evaluates against.
- Everything else — the command parser (`MRDebug::Command`), the `(prdb)`
  prompt (`MRDebug::UI::LocalConsole`), breakpoint matching — is plain Ruby.

### The `MRB_USE_DEBUG_HOOK` build-wide cost

Adding this gem sets `MRB_USE_DEBUG_HOOK`, which adds a `code_fetch_hook`
function pointer to `mrb_state` and one branch to the VM's per-instruction
dispatch. This is a **build-wide** effect — every gem in the build sees the
changed `mrb_state` layout — and there's no way to opt individual gems out
of it. Once armed (a breakpoint is set, or you're mid-`step`/`next`), the
hook also calls into Ruby once per *executed source line* until you
`continue` past it: see [Overhead](#overhead) for what that costs.

## Overhead

Measured with a tight `while i < 1_000_000; i += 1; end` loop (~2,000,000
traced lines when armed), averaged over 3 runs:

| Build | Time | vs. plain mruby |
| --- | --- | --- |
| Plain mruby (`MRB_USE_DEBUG_HOOK` not set) | ~0.028s | — |
| `mrdebug` loaded, `Hook` not armed (0 breakpoints) | ~0.025s | no measurable difference |
| `mrdebug` loaded, 1 breakpoint set (never reached) | ~3.61s | ~145x |

Loading the gem and creating a `Session` costs nothing measurable as long as
nothing is armed. Once armed, RUN mode funcalls into Ruby for every executed
line, not just near a breakpoint — about 1.8µs/line here. See "The
`MRB_USE_DEBUG_HOOK` build-wide cost" above for why there's no cheaper
middle ground in phase 1's design.

## Dependencies

- `mruby-binding`, `mruby-eval` (mruby core gems — for `Binding` and
  `Binding#eval`, which `print` uses)
- `mruby-io` (host builds only — `MRDebug::UI::LocalConsole` reads `STDIN`)
- `mruby-socket` (host builds only — `MRDebug::Transport::TCP`/`Unix`)

No PicoRuby gems. `tools/mrdebug/ui/local_console.rb` (the `(prdb)` prompt
itself) is only compiled into `build.host?` builds; the core (`MRDebug`,
`Session`, `Command`, the VM hook) has no I/O dependency at all.

## Development

```sh
MRDEBUG_MRUBY_DIR=/path/to/an/mruby/checkout rake build       # build/host/bin/mruby
MRDEBUG_MRUBY_DIR=/path/to/an/mruby/checkout rake test:unit   # mruby's own assert framework
```

`e2e/build_config.rb` is the build config those tasks drive; it turns on
`conf.enable_debug` (`mrbc -g`), which `test/e2e/*.rb` needs for the VM hook
to see line numbers in AOT-compiled test code — a plain `bin/mruby
script.rb` run doesn't need this, since it compiles at runtime.

`test/*.rb` (plain `assert`) and `test/e2e/*.rb` (drives the real VM hook,
`binding.debugger`, and the command layer together) both run under
`rake test:unit`; there's no separate transcript/E2E harness.

## Roadmap

Not in phase 1, roughly in the order a future phase might tackle them:

- `quit`, `list`, `bt`/`frame`/`up`/`down`, `watch`, `display`, `finish`,
  conditional/method breakpoints, `catch`, `step N`/`next N`
- PicoRuby / R2P2 support
- A serial transport (TCP/Unix socket transport and the host CLI binary
  exist — see [Remote debugging over a socket](#remote-debugging-over-a-socket))
- A host-side DAP bridge for `vscode-rdbg` compatibility
- An on-device console UI gem (`mrdebug-console`) for PicoRuby targets

See `docs/plan-phase1.md`'s "後続フェーズに送る項目" section for the full list
with rationale.
