# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this gem is

`mrdebug` is an interactive debugger for **mruby**, rebuilt from scratch
(the old `picoruby-debug` gem) to run with nothing but a plain mruby
checkout — see `docs/plan-phase1.md` for the design rationale and the
step-by-step history of how this codebase got to its current shape, and
`docs/plan-phase2.md` for what comes after phase 1 (scope and ordering
for phase 2 onward).
Read `README.md` before making changes; it documents the command set and
the known rough edges (particularly the "stepping shows mrdebug's own
source" limitation) that are easy to regress.

PicoRuby/R2P2 support is still not a planned phase of its own — phase 1
remains mruby-only by design, and no on-device console UI gem
(`mrdebug-console` or similar, still Phase3 scope) exists yet. What *has*
landed is two narrow, mechanical compatibility fixes so this gem's
existing core (Ruby + `src/hook.c`/`src/frame.c`) also builds and runs
under PicoRuby's `PICORB_VM_MRUBY` host build without changing mainline
mruby's behavior at all: `mrbgem.rake`'s dependency resolution branches
`core:` vs `gemdir:` (PicoRuby vendors `mruby-binding`/`mruby-eval`/
`mruby-io`/`mruby-socket` under `mrbgems/picoruby-mruby/lib/mruby/mrbgems`
rather than exposing them under its own `MRUBY_ROOT/mrbgems`), and
`src/hook.c`'s `dbg_context_reset` guards a `svars` field PicoRuby's
vendored mruby fork's `struct mrb_context` doesn't have. See
`docs/phase3-picoruby-host-verification.md` for what was confirmed working
(`step`/`next`/`break`/`delete`/`print`/`continue`, PICORB_VM_MRUBY POSIX
host build only) and what remains untouched (R2P2-ESP32 cross build,
on-device UI, PicoRuby's own `mruby-c`/femtoruby VM). Don't add further
`PICORB_VM_MRUBY`-style branching beyond these two fixes without that
being its own explicit, planned phase.

## Design policy

**C is only for what Ruby cannot do**: reading file/line out of an irep,
walking the raw callinfo stack, and safely getting control from the VM's
per-instruction dispatch. That's `src/hook.c` (VM hook mechanics) and
`src/frame.c` (frame walking) — the only two C files in this gem. Everything
else (breakpoint matching, session state, the command parser, the `(prdb)`
prompt) is Ruby. When adding a feature, assume it belongs in Ruby unless you
can point at a specific thing only C can do (as the frame API's `mrb_context`
walking or the VM hook's context swap need to).

## Build & test

This repo is a standalone mrbgem, not a full mruby/picoruby checkout. Point
`MRDEBUG_MRUBY_DIR` at a checkout of [mruby](https://github.com/mruby/mruby)
(4.0.0+) and use this repo's own `Rakefile`:

```sh
MRDEBUG_MRUBY_DIR=/path/to/mruby rake build       # build/host/bin/mruby
MRDEBUG_MRUBY_DIR=/path/to/mruby rake test:unit   # mrbtest
```

Both drive mruby's own `Rakefile` with `MRUBY_CONFIG=e2e/build_config.rb`
and `MRUBY_BUILD_DIR=<this repo>/build`, so nothing lands inside the mruby
checkout itself. `e2e/build_config.rb` turns on `conf.enable_debug` (`mrbc
-g`): without it, AOT-compiled `test/**/*.rb` has no line info, and the VM hook
can never be observed firing from a `test/e2e/*.rb` assertion (`if (line <
0) return;` in `src/hook.c` bails immediately) — a plain `bin/mruby
script.rb` run doesn't need this, since it compiles at runtime and always
emits debug info.

For a quick manual smoke check without `rake test:unit`, pipe commands into
a script that sets up a session:

```ruby
MRDebug.session = MRDebug::Session.new
MRDebug.session.ui = MRDebug::UI::LocalConsole.new
binding.debugger
```

```sh
printf 'n\np x\nc\n' | build/host/bin/mruby script.rb
```

### Two test layers, one runner

- `test/**/*.rb` (outside `test/e2e/`) — plain `assert`, pure-Ruby logic, no
  VM hook involved. Mirrors the source tree being tested:
  `test/mrblib/mrdebug/*.rb` for `mrblib/mrdebug/*.rb`,
  `test/tools/mrdebug/**/*.rb` for `tools/mrdebug/**/*.rb`. `Session`'s
  `:next`-mode depth comparison is checked by stubbing
  `MRDebug::Hook.frame_count` (`Hook.define_singleton_method(:frame_count)
  { ... }`) rather than relying on a real paused context. **Restore a
  stubbed `Hook` method via `alias_method`, not `remove_method`**:
  `remove_method` on a singleton method that shadowed a C-defined one
  deletes it outright instead of un-shadowing it (`test/mrblib/mrdebug/session.rb`'s
  `frame_count`/`armed=` stubs both alias the original aside first, then
  alias it back in the `ensure`) — confirmed by a real crash this mistake
  caused once a later test's real `next_mode!` call found `frame_count`
  gone entirely.
- `test/e2e/*.rb` — also plain `assert`, but exercises the real VM hook,
  `binding.debugger`, and the command layer together (ported from what used
  to be ad hoc `e2e/scenarios/*.rb` scripts checked by eye; that approach
  once let a real bug — a wrong callback arity — go unnoticed for several
  steps, which is why this layer is now `assert`-based too).

**Every test that creates a `Session` must clean up the VM hook.** `Session#initialize`
calls `MRDebug::Hook.install(self)`, and adding a breakpoint or leaving
step/next mode set also arms it (`MRDebug::Hook.armed = true`). Without an
`ensure MRDebug::Hook.uninstall end` in every `assert` block, an armed hook
leaks into whatever mrbtest runs next — including mruby's own core test
suite, sharing the same process — and can silently self-trace mrdebug's own
library code (see `Session::DIRECT_STOP_FRAME_OFFSET` below) or just slow
everything down.

**Avoid `mruby-string-ext` methods (`String#strip`, `#end_with?`,
`#start_with?`, ...) in code that also runs under `mrbtest`.** They come up
as `NoMethodError` specifically when called from this gem's own
`test/**/*.rb` (not from a plain `bin/mruby script.rb` run) —
confirmed via a clean rebuild, not a caching artifact, and not fixed by
declaring `mruby-test` as a build-time gem dependency up front. The likely
cause is a presym (symbol-ID) mismatch between `mrbc` and the `mruby-test`
gem's late, dynamic addition to the build (`tasks/test.rake`'s
`build.gem(core: 'mruby-test')`, which runs after the "host" build's own
symbols are already resolved) — not root-caused further, since it isn't
worth the time relative to the fix: **mruby *core* `src/string.c`/`src/array.c`
ROM-table methods are unaffected** (`to_i`, `empty?`, `rindex`, `include?`,
`[]`, `size` all confirmed fine) — only the separate `mruby-string-ext` gem's
table is affected. `mrblib/mrdebug/line_breakpoint.rb`'s suffix match and
`mrblib/mrdebug/command.rb`'s argument trimming both hand-roll what
`#end_with?`/`#strip` would otherwise do, for this reason.

## Architecture

- **`mrbgem.rake`**: declares the gem `mrdebug` and sets
  `MRB_USE_DEBUG_HOOK` (build-wide — see below). Depends only on mruby core
  gems (`mruby-binding`, `mruby-eval`); `mruby-io`, `mruby-socket`,
  `mruby-env` (the last only for `MRDEBUG_PORT`/`MRDEBUG_SOCK` in
  `MRDebug.autostart`), and `tools/mrdebug/**/*.rb` (the `(prdb)` prompt)
  are added only under `spec.build.host?`, so a firmware build never sees
  the console UI's I/O dependency at all — the core (`MRDebug`, `Session`,
  `Command`, the VM hook) has none. `spec.rbfiles +=` (rather than
  replacing `spec.rbfiles`) is what makes this additive-and-safe: confirmed
  via `MRuby::Gem::Specification#setup` giving `@rbfiles` its default value
  from `mrblib/**/*.rb` *before* `instance_eval(&@initializer)` runs this
  file's block (`lib/mruby/gem.rb` in the mruby checkout). Each of these
  dependencies is declared via `core:` on mainline mruby, or
  `gemdir:` pointing straight at PicoRuby's vendored copy
  (`mrbgems/picoruby-mruby/lib/mruby/mrbgems/<name>`) when
  `spec.build.respond_to?(:picoruby?) && spec.build.picoruby?` — `core:`
  always resolves under `MRUBY_ROOT/mrbgems`, which is where mainline
  keeps these gems but not where PicoRuby vendors them, and
  `build.picoruby?` only exists on PicoRuby's own `MRuby::Build` subclass,
  hence the `respond_to?` guard. This is the same pattern PicoRuby's own
  `stdlib.gembox` already uses for `mruby-binding`/`mruby-eval`, not
  something invented here. See
  `docs/phase3-picoruby-host-verification.md`.
- **`src/hook.c`** — the VM hook. `struct mrdebug_hook hook` (file-static)
  holds everything: the installed session, whether the hook is armed,
  same-line dedup state (`prev_irep`/`prev_line`), the dedicated debugger
  context, and a frozen-string cache for filenames (keyed by `(irep, char*)`
  identity, since `mrb_debug_get_filename` returns an interned symbol's
  name — stable while the irep lives).
  - **The dedicated context** (`dbg_context_new`/`dbg_context_reset`,
    modeled on `mruby-fiber`'s `init_fiber`) exists because `mrb_vm_exec`
    keeps a local `mrb_callinfo *ci` pointing into `mrb->c->cibase`; a
    funcall from the hook that grows the *same* context's `cibase` (e.g. a
    deep `Session#on_line` call chain) would leave that local dangling.
    Every callback — hook-triggered or direct — swaps `mrb->c` to this
    context first. `mrb->c->prev` is `NULL` on the root context in plain
    mruby (unlike the old PicoRuby-oriented design, which assumed a
    non-root `prev` to borrow), which is exactly why this gem needs its own
    context rather than reusing one. `dbg_context_reset`'s one field write to
    `c->svars` is wrapped in `#ifndef MRDEBUG_NO_SVARS` — PicoRuby's vendored
    mruby fork's `struct mrb_context` has no `svars` field at all (mainline
    mruby added it later, for Fiber-scoped special variables), and
    `mrbgem.rake` only defines `MRDEBUG_NO_SVARS` when
    `build.picoruby?`, so mainline mruby's behavior here is unchanged (see
    `docs/phase3-picoruby-host-verification.md`).
  - **`invoke_on_line`** is the shared swap-call-restore sequence, used by
    both `hook_code_fetch` (bnd = nil) and `MRDebug::Hook.enter` (bnd =
    the caller's `Binding`, for the direct `binding.debugger` path — see
    `Session::DIRECT_STOP_FRAME_OFFSET` below for why that path still
    needed its own entry point rather than just calling `session.on_line`
    directly). `hook.in_callback` guards re-entrancy; `MRDebug::Hook.armed=`
    only touches `mrb->code_fetch_hook` directly when *not* `in_callback` —
    if `#on_line` arms/disarms mid-callback (e.g. `step_mode!`),
    `invoke_on_line`'s own tail re-derives `mrb->code_fetch_hook` from
    `hook.armed` on the way out instead.
  - **`MRDebug::Hook.armed=` toggles `mrb->code_fetch_hook` itself**
    (`NULL` vs the hook function), not a flag checked *inside* the hook —
    so a disarmed hook costs nothing beyond the VM's own existing
    `if (mrb->code_fetch_hook)` check (`CODE_FETCH_HOOK` macro in mruby's
    `src/vm.c`), the same as no debugger being loaded at all. Only
    `hook.armed` still exists as a flag: it's what `invoke_on_line`
    consults when deciding whether to *re-arm* on the way out.
  - **`mrdebug_paused_ctx(mrb)`** (declared in `src/mrdebug.h`, called from
    `src/frame.c`) returns `hook.paused` if set, else `mrb->c` — the
    fallback matters for `MRDebug::Hook.enter`'s direct-call path, where no
    hook callback (and thus no `hook.paused`) is involved, but `mrb->c` at
    that point genuinely *is* the debuggee's live context.
- **`src/frame.c`** — walks whatever `mrdebug_paused_ctx` returns.
  `frame_count`/`frame_at` are plain `ci - cibase` arithmetic (depth 0 =
  innermost); `frame_position` reads `ci->pc` directly for the innermost
  frame but steps back one instruction for any other (a resumed call site's
  `pc` is just past the call); `frame_binding` builds a `Binding` the same
  way `Kernel#binding` does, lazily creating the frame's `REnv` if it
  doesn't have one yet.
- **`src/mrdebug.h`** — the only header, declaring exactly the two things
  `hook.c` and `frame.c` share (`mrdebug_paused_ctx`, `mrdebug_frame_init`).
  Not placed under `include/`, which mruby's gem convention reserves for
  cross-gem sharing.
- **`mrblib/mrdebug.rb`** — `module MRDebug`: `.session`/`.session=` (the
  latter also calls `Hook.install`, so assigning *any* session — a real
  `Session` or a lightweight test double implementing `#on_line` — makes it
  the hook's active session too) and `.break(bnd)`, `Binding#debugger`'s
  entry point. `.break` calls `.autostart` when `@session` is still `nil`,
  then bails unless one got set — a no-op `.autostart` here (overridden on
  host builds by `tools/mrdebug/device.rb`) is what keeps a firmware build,
  or any build that never wired a UI, silently doing nothing rather than
  funcalling `on_line` on `nil`.
- **`mrblib/binding.rb`** — reopens core `Binding` to add
  `#debugger`/`#b`/`#break`, all delegating to `MRDebug.break(self)`.
  `Binding#source_location` (from mruby's own `mruby-binding` gem) is
  already exact here, resolved from the live call stack at the point
  `binding` was called — no VM hook involvement needed for file/line at
  this entry point, unlike a breakpoint hit.
- **`mrblib/mrdebug/session.rb`** — `MRDebug::Session`: owns breakpoints and
  run/step/next mode, decides stop/no-stop in `#on_line`, and (since the UI
  wiring landed) calls `ui.on_stop(self)` synchronously if a UI is attached,
  *inside* `#on_line` — matching the "prompt loop runs inside the hook
  callback's own stack frame" design the old repo used too.
  - **`#stop_reason_for`** (the private predicate `#on_line` uses; was
    `#should_break?`) returns *why* to stop, not a bool: the matched
    `LineBreakpoint` or `WatchVarBreakpoint` object, `:step`, `:next`, or
    `nil` to keep going. `#on_line` stores it in `@stopped_by` (also
    `:debugger` for a direct `binding.debugger` stop), and **`#stop_banner`**
    turns that into the headline the UI prints. It finds which list
    (`@breakpoints` / `@watches`) holds `@stopped_by` and hands that list to
    `LineBreakpoint#stop_banner` / `WatchVarBreakpoint#stop_banner`, which
    locate their own number in it (`siblings.index(self) + 1`) and own their
    "Breakpoint N: …" / "Watchpoint N: …" wording — no per-class branch in
    `Session`. A step/next/debugger stop is in neither list, so it falls
    back to a plain `"Stop: file:line"`.
  - **`Session::DIRECT_STOP_FRAME_OFFSET = 3`**: `Binding#debugger` →
    `MRDebug.break` → `MRDebug::Hook.enter` is a fixed 3-frame call chain
    that `Hook.enter`'s `invoke_on_line` captures `mrb->c` through *before*
    swapping into the debugger context — so a direct stop's
    `Hook.frame_count` always includes exactly these 3 extra frames on top
    of the debuggee's own depth at the call site, confirmed empirically
    across nesting depths, all three `Binding` aliases, and repeated direct
    stops in one session. `next_mode!` subtracts it when `@direct_stop` is
    set, rather than falling back to `step_mode!` as an earlier version of
    this file did.
  - `on_line`'s 3rd parameter (`bnd`) distinguishes a direct stop (always
    present, and *always* stops unconditionally) from a hook-triggered one
    (`nil`; `MRDebug::Hook.frame_binding(0)` is used to build the binding
    lazily instead). The VM hook's own funcall always passes exactly 3 args
    (`nil` for `bnd` when hook-triggered) — a test double's `#on_line` needs
    a matching arity (`def on_line(file, line, bnd = nil)`), or the VM hook
    silently swallows the resulting `ArgumentError` via `mrb_protect_error`
    (`src/hook.c`) and nothing appears to happen at all. This exact mistake
    shipped undetected in the old `e2e/scenarios/hook_trace.rb` for several
    steps, since nothing but eyeballing `puts` output checked it.
- **`mrblib/mrdebug/line_breakpoint.rb`** — file/line/active, suffix match
  via hand-rolled `String#[]` slicing (see "Avoid `mruby-string-ext`
  methods" above), stable numbering shared with `Session`'s breakpoint
  array (`delete` deactivates in place rather than compacting).
  `#stop_banner(siblings, location)` returns the `"Breakpoint N: …"` headline,
  N being its own index in `siblings` + 1.
- **`mrblib/mrdebug/watch_var_breakpoint.rb`** — `MRDebug::WatchVarBreakpoint`
  (named after `LineBreakpoint`; was `WatchExpression`): a watched expression
  string, its last evaluated value, `#changed?(bnd)`, and `#stop_banner`
  returning `"Watchpoint N: …"` (the label the user sees is still
  "Watchpoint").
- **`mrblib/mrdebug/own_source.rb`** — `MRDebug::OwnSource`: the hardcoded
  suffix-matched file list `Session#stop_reason_for` checks first, to never
  stop (or count against `step N`/`watch`) inside this gem's own code. See
  "Known gaps" below.
- **`mrblib/mrdebug/command.rb`** — `MRDebug::Command.dispatch(session,
  line)` parses one command line and returns `[output_lines, :stay |
  :resume]`; it never prints. This is what keeps the command layer testable
  without stdio and reusable across front ends (today just
  `LocalConsole`, but the split is exactly the "coreoutputs data, UI prints
  it" boundary `docs/plan-phase1.md` calls for).
  - **`list`/`l`** is the one command whose *body* needs I/O (reading the
    stopped file's source text) despite living in this I/O-free core file.
    Rather than splitting a "source reader" out to `tools/mrdebug/` and
    injecting it into `Session`/`Command` (the `Transport` pattern), it
    stays in `Command.source_listing` and just checks `defined?(File)`
    first: on a host build `File` is always present (`mrbgem.rake` adds
    `mruby-io` under `spec.build.host?`, and `spec.rbfiles +=` never
    removes core), so this is the common case; a firmware build that never
    linked `mruby-io` in gets a one-line "not available" message instead of
    a `NameError`. This was chosen over dependency injection because
    `list`'s only device-specific need is *reading bytes off a path
    already known to Ruby* (`session.file`) — unlike `Transport`, there's
    no protocol or session-lifetime state to own, so a DI seam would add a
    layer without a matching axis of variation to justify it. `File.read`
    (not `File.readlines`, which mruby-io's `File` doesn't define) plus a
    hand-rolled `"\n"`-split (`String#split` is core; `#each_line`/`#lines`
    are `mruby-string-ext`, unsafe under `mrbtest` per above) turns the
    file into a 1-indexed line array; `LIST_CONTEXT` (5) lines on either
    side of the target are then clamped to `1..line_count` and formatted
    with a `"  "`/`"=>"` marker prefix for the current line (see README).
- **`mrblib/mrdebug/ui.rb`** — `MRDebug::UI::Base`, the one-method contract
  (`#on_stop(session)`) a UI implements.
- **`mrblib/mrdebug/transport.rb`** (Phase3) — `MRDebug::Transport::Base`:
  the `(prdb)` prompt's I/O contract (`#gets`/`#write`), not a wire protocol
  (DAP, rdbg, ...) — see `docs/plan-phase3.md`.
- **`mrblib/mrdebug/transport/loopback.rb`** (Phase3) —
  `MRDebug::Transport::Loopback`: an in-process, array-backed transport with
  no I/O, used to test `LocalConsole` under `rake test:unit` without stdio.
- **`tools/mrdebug/transport/stdio.rb`** (host builds only, Phase3) —
  `MRDebug::Transport::Stdio`: `STDIN`/`STDOUT` via `mruby-io`. Strips a
  trailing newline by hand (`strip_eol`, now shared on `Transport::Base`),
  not `String#chomp` — that's `mruby-string-ext`, which misbehaves under
  `mrbtest`.
- **`tools/mrdebug/transport/socket.rb`** (host builds only) —
  `MRDebug::Transport::Socket`/`TCP`/`Unix`: `mruby-socket`, wrapping the
  accepted (`.listen`, device side) or connected (`.connect`, CLI side)
  socket. `#gets` uses `#sysread`, not mruby-io's buffered `IO#gets` —
  the latter makes `#write` raise `Errno::ESPIPE` (silently swallowed by
  the VM hook, freezing the `(prdb)` loop) once a read has more than one
  line buffered ahead, since `IO#write` on a dual-purpose fd tries to
  `lseek` back by the leftover count first.
- **`tools/mrdebug/device.rb`** (host builds only) — `MRDebug.listen_tcp`/
  `.listen_unix`: device-side setup — `Session.new`, block for the CLI to
  connect, wire the connection to `LocalConsole`. Also `MRDebug.autostart`
  (overriding the core no-op), which `MRDebug.break` calls on the first
  `binding.debugger` hit when no session exists — a three-way branch on the
  environment: `MRDEBUG_SOCK` → `listen_unix`; else `MRDEBUG_PORT` →
  `listen_tcp` on it; else `attach_stdio` (a `Session` whose `LocalConsole`
  talks to this process's own `STDIN`/`STDOUT` — no socket, no separate
  `mrdebug` CLI, the common local case and what makes README's Usage
  example work with zero setup). This is what lets a script carry nothing
  but `binding.debugger`. It's a one-shot by construction (`@session.nil?`
  gates it); a listener bind failure propagates out of `binding.debugger`
  rather than being swallowed. `DEFAULT_PORT` (4711, rdbg's convention) is
  only the fallback for a *port that was asked for but unspecified* — a
  bare `MRDebug.listen_tcp`, or `mrdebug` with no args — not for
  `autostart`, which goes to stdio when `MRDEBUG_PORT` is unset.
  `env_value` tolerates a build without `mruby-env` (`defined?(ENV)`) and
  treats a blank value as unset.
- **`tools/mrdebug/cli/cli.rb`**'s `--port`/`--sock-path` (and no args at
  all, which reads `MRDEBUG_SOCK`/`MRDEBUG_PORT`, falling back to
  `DEFAULT_PORT`, via `connect_auto`) — connect via the
  transports above, then hand off to `#relay`: a raw `IO.select`-based
  byte pump between the socket and real `STDIN`/`STDOUT`, since the
  device's `(prdb) ` prompt has no trailing newline for a `#gets`-based
  relay to wait on. A bare `mrdebug FILE:LINE` (a positional arg, no
  connection flag) still runs the interim local demo session instead.
  `Command.dispatch` runs on the device side, so the CLI only relays
  bytes — no structured RPC layer needed here (contrast
  `docs/phase4-to-phase3-requests.md`, about the DAP bridge's needs).
- **`tools/mrdebug/ui/local_console.rb`** (host builds only) —
  `MRDebug::UI::LocalConsole`: the `(prdb)` prompt, one `STDIN.gets` (now via
  a `Transport`, defaulting to `Stdio`) per command. Reading exactly one
  line at a time is what avoids the old `picoruby-editor`-based design's
  known bug (piped/pasted multi-command input losing everything after a
  resuming command) — there's no shared read-ahead buffer to lose data from.
  The stop headline it prints is `session.stop_banner` (see `session.rb`
  above), not a hardcoded string — so a step/next stop reads `Stop: …`, not
  `Breakpoint: …`.

## Known gaps (in progress)

- **~~Stepping through mrdebug's own source~~ — fixed.**
  `MRDebug::OwnSource` (`mrblib/mrdebug/own_source.rb`) is a hardcoded,
  suffix-matched list of this gem's own Ruby files; `Session#stop_reason_for`
  checks it first and refuses to stop (or count against `step N`/`watch`)
  inside them. Hardcoded rather than discovered at runtime (`Dir.glob` would
  need a filesystem, which a PicoRuby target may not have) — remember to
  update `OwnSource::FILES` when adding, removing, or renaming a file under
  `mrblib/mrdebug/` or `tools/mrdebug/`. This turned out to be the root
  cause behind two problems that looked like mruby/VM bugs during Phase3
  track B (`step N`/`next N`'s counter being consumed by mrdebug's own
  code, and part of `watch`'s line-shift symptom) — see `docs/known-bugs.md`.
- **Performance**: `RUN` mode with one or more breakpoints funcalls into
  Ruby once per *executed source line*, everywhere, not just near a
  breakpoint's file — the old C implementation had a fast path that skipped
  irep files unrelated to any breakpoint, dropped when breakpoint matching
  moved to Ruby. Only `MRDebug::Hook.armed` is left as a fast gate on the C
  side (see above), so a build with zero active breakpoints and no
  step/next in flight costs nothing beyond that. See `README.md`'s Overhead
  section for measured numbers.
- **PicoRuby/R2P2 support is still just the core, not a real phase.**
  The `mrbgem.rake`/`src/hook.c` compatibility fixes (see "What this gem
  is" and `docs/phase3-picoruby-host-verification.md`) only get this
  gem's existing mruby-only core to build and run under PicoRuby's
  `PICORB_VM_MRUBY` **POSIX host** build — confirmed for
  `step`/`next`/`break`/`delete`/`print`/`continue` via `LocalConsole`.
  Everything `docs/plan-phase1.md`'s "後続フェーズに送る項目" describes for
  a real PicoRuby phase is still missing: an on-device console UI gem
  depending on `picoruby-editor`/`picoruby-io-console` (this gem's
  `tools/mrdebug/ui/local_console.rb` assumes plain stdio, which PicoRuby's
  own R2P2 binary does not always have), R2P2-ESP32 cross-build wiring, and
  PicoRuby's mrubyc/femtoruby VM (a different, unrelated implementation
  would be needed there — `MRB_USE_DEBUG_HOOK`/`code_fetch_hook` are
  mruby-only). Don't reintroduce further `PICORB_VM_MRUBY`-style branching
  beyond the two fixes already landed without that being its own explicit,
  planned phase.
