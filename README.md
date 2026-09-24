# mrdebug

An interactive debugger for **mruby** (and PicoRuby's mruby VM). Put
`binding.debugger` in a script and it pauses there with a `(prdb)` prompt.

## Installation

Add the gem to your mruby `build_config.rb`:

```ruby
conf.gem github: 'yuuu/picoruby-debug', branch: 'main'
```

On a PicoRuby device (e.g. R2P2-ESP32), add the on-device console gem
under `console/` instead — it pulls in `mrdebug` itself:

```ruby
conf.gem github: 'yuuu/picoruby-debug', branch: 'main', path: 'console'
```

On R2P2-ESP32, also raise the PicoRuby task stack to at least 32768 bytes
(`PICORB_TASK_STACK_SIZE=32768` in the environment of the ESP-IDF build);
the 8192 default overflows as soon as the debugger stops.

## Usage

### Example

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
$ mruby script.rb
Stop: script.rb:6
(prdb) n
Stop: script.rb:7
(prdb) p y
nil
(prdb) break 2
Breakpoint 1 added at script.rb:2
(prdb) c
Breakpoint 1: script.rb:2
(prdb) p a + b
3
(prdb) bt
#0 script.rb:2
#1 script.rb:7
(prdb) c
3
```

No setup call is needed: the first `binding.debugger` opens the prompt on
the script's own terminal (piped input such as `printf 'n\nc\n' | mruby
script.rb` also works).

### Commands

| Command | Alias | Description |
| --- | --- | --- |
| `continue` | `c`, empty input | Resume until the next breakpoint |
| `step [<n>]` | `s` | Stop at the next executed line, entering calls |
| `next [<n>]` | `n` | Stop at the next line in the same or a shallower frame |
| `break [<file>:]<line> [if <expr>]` | `b` | Add a line breakpoint (no argument lists breakpoints) |
| `break <Class>#<method>` / `<Class>.<method>` / `<method>` | `b` | Add a method breakpoint (`#` instance, `.` singleton, bare = any class) |
| `delete [<n>]` | `d` | Delete breakpoint `<n>`, or all with no argument |
| `watch [<expr>]` | | Stop when `<expr>`'s value changes (no argument lists watches) |
| `display <expr>` | | Print `<expr>` at every stop |
| `print <expr>` | `p` | Evaluate `<expr>` in the selected frame |
| `list [[<file>:]<line>]` | `l` | Show source around the current line |
| `cat [<file>]` | | Show a whole source file |
| `backtrace` | `bt`, `where` | Show the call stack (`#0` = innermost) |
| `frame [<n>]` | `f` | Select frame `<n>`, or show the selected frame |
| `up [<n>]` / `down [<n>]` | | Move the selected frame toward the caller / back |

- File names match by suffix: `break foo.rb:8` matches `/path/to/foo.rb`.
- A method breakpoint stops inside a Ruby method, or just before calling a
  C method. `Foo#bar` also matches subclasses and includers, and `Foo` need
  not be defined yet.
- `frame`/`up`/`down` only affect `print`/`list`; execution always resumes
  from the actual stop.

### Remote connection

Set an environment variable and the first `binding.debugger` waits for a
client instead of using the local terminal:

```sh
MRDEBUG_PORT=4711 mruby script.rb       # or MRDEBUG_SOCK=/tmp/mrdebug.sock
```

```sh
mrdebug                                  # reads MRDEBUG_PORT / MRDEBUG_SOCK
mrdebug --host 192.168.0.10 --port 4711  # e.g. a board on the network
```

A script (or device firmware) can also start listening explicitly:

```ruby
MRDebug.listen_tcp(4711)   # or MRDebug.listen_unix('/tmp/mrdebug.sock')
binding.debugger
```

### Connecting from VS Code

`mrdebug` can bridge a DAP client to a listening device. Start the bridge:

```sh
mrdebug --host 192.168.0.10 --port 4711 --dap-port 12345
```

Then attach with [vscode-rdbg](https://marketplace.visualstudio.com/items?itemName=KoichiSasada.vscode-rdbg):

```json
{
  "type": "rdbg",
  "request": "attach",
  "name": "Attach to mrdebug",
  "debugPort": "localhost:12345"
}
```

Breakpoints, continue, step over/in, the call stack and source view work;
variables, watch expressions and step out are not supported yet.

## Features

- **Zero configuration** — `binding.debugger` is the only line a script needs.
- **Small C footprint** — only the VM hook and frame walking are in C
  (`src/`); breakpoints, sessions and commands are plain Ruby.
- **No cost until armed** — with no breakpoint set and no step in progress,
  the VM runs as fast as without the gem. Once armed, every executed line
  calls into Ruby (about 1.8µs/line, ~145x on a tight loop).
- **Runs on devices** — works on PicoRuby's mruby VM, including R2P2-ESP32.
- **Remote and DAP** — a TCP/Unix socket console and a VS Code bridge.

Note that the gem sets `MRB_USE_DEBUG_HOOK`, which applies to the whole
build.

## Dependencies

- mruby 4.0.0+, or PicoRuby with `PICORB_VM_MRUBY`
- `mruby-binding`, `mruby-eval`
- Host builds only: `mruby-io`, `mruby-socket`, `mruby-env`
  (`picoruby-socket` / `picoruby-env` on PicoRuby)
- `console/` only: `picoruby-editor`, `picoruby-io-console`

## Roadmap

- `quit`, `finish`, `catch` (exception breakpoints)
- Variables, evaluate and step out over DAP
- A serial transport
- PicoRuby's mruby/c VM (not supported: it has no debug hook)
