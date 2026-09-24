# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this gem is

`mrdebug` is an interactive debugger for **mruby**, rebuilt from scratch
(the old `picoruby-debug` gem) to run with nothing but a plain mruby
checkout. Read `README.md` before making changes; it documents the
install steps and the command set.

It also runs under PicoRuby's `PICORB_VM_MRUBY` builds, both the POSIX
host build and R2P2-ESP32 (ESP32-S3) firmware, through a handful of narrow
compatibility branches that leave mainline mruby's behavior unchanged:
`mrbgem.rake` resolves dependencies via `core:` vs `gemdir:` (PicoRuby
vendors `mruby-binding`/`mruby-eval`/`mruby-io` under
`mrbgems/picoruby-mruby/lib/mruby/mrbgems` instead of its own
`MRUBY_ROOT/mrbgems`), and socket/env go through `picoruby-socket`/
`picoruby-env` instead of `mruby-socket`/`mruby-env`, which would redefine
the same class names and silently abort `mrb_open()`'s gem-init loop (see
`tools/mrdebug/transport/socket.rb`). `dbg_context_reset` writes
`c->svars`, so an older PicoRuby whose vendored mruby lacks that field
doesn't build.

On R2P2-ESP32, `picoruby-esp32`'s `PICORB_TASK_STACK_SIZE` must be at
least 32768 (the 8192 default overflows `picoruby_task` the instant the VM
hook's context-swap/funcall chain runs). It's read by `picoruby-esp32.c`'s
ESP-IDF CMake component from `ENV['PICORB_TASK_STACK_SIZE']`, not from
this gem's build config, so setting a define here does nothing.
PicoRuby's mruby/c VM is unsupported (`MRB_USE_DEBUG_HOOK`/
`code_fetch_hook` are mruby-only). Don't add further
`PICORB_VM_MRUBY`-style branching without a concrete need.

## Design policy

**C is only for what Ruby cannot do**: reading file/line out of an irep,
walking the raw callinfo stack, and safely getting control from the VM's
per-instruction dispatch. That's `src/hook.c` (VM hook mechanics) and
`src/frame.c` (frame walking) — the only two C files in this gem. Everything
else (breakpoint matching, session state, the command parser, the `(mrdbg)`
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
MRDEBUG_MRUBY_DIR=/path/to/mruby rake test:smoke  # spec/ (RSpec) smoke specs
MRDEBUG_PICORUBY_DIR=/path/to/picoruby rake picoruby:smoke  # same, PicoRuby host build
```

`build`/`test:unit`/`test:smoke` drive mruby's own `Rakefile` with `MRUBY_CONFIG=test/build_config/mruby.rb`
and `MRUBY_BUILD_DIR=<this repo>/build`, so nothing lands inside the mruby
checkout itself. `test/build_config/mruby.rb` turns on `conf.enable_debug` (`mrbc
-g`): without it, AOT-compiled `test/**/*.rb` has no line info, and the VM hook
can never be observed firing from a `test/integration/*.rb` assertion (`if (line <
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

`picoruby:build`/`picoruby:smoke` drive a PicoRuby checkout's `Rakefile`
the same way, with `test/build_config/picoruby.rb` and
`MRUBY_BUILD_DIR=<this repo>/build/picoruby`. PicoRuby has no mrbtest (its
Rakefile doesn't load mruby's `tasks/test.rake`), so the PicoRuby build is
only checked by the smoke specs: `spec/smoke_spec.rb` (RSpec, under CRuby
via `bundle exec`; the rake tasks pass the built binary as
`MRDEBUG_SMOKE_BIN`) writes each scenario's script inline to a tmpdir, pipes
commands into `(mrdbg)`, and compares `[command, output]` pairs — the
transcript split on the `(mrdbg) ` prompt — so a failure's diff points at the
command whose output changed. Keep smoke scenarios away from
anything whose output differs between the two VMs — e.g. stepping into
core `mrblib` (`Integer#times`) or a `watch` that fires inside `Kernel#puts`
both print VM-specific paths. `.github/workflows/ci.yml` runs all of this
against pinned mruby/picoruby commits (`MRUBY_REF`/`PICORUBY_REF`), plus a
`continue-on-error` run against each upstream's default branch.

### Two test layers, one runner

`test/build_config/{mruby,picoruby}.rb` are the rake build configs, not
tests: `mrbgem.rake` subtracts them from `spec.test_rbfiles`, since mruby
otherwise compiles every `test/**/*.rb` into mrbtest.

- `test/**/*.rb` (outside `test/integration/` and `test/build_config/`) — plain `assert`, pure-Ruby logic, no
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
- `test/integration/*.rb` — also plain `assert`, but exercises the real VM hook,
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
  `MRDebug.autostart`), and `tools/mrdebug/**/*.rb` (the `(mrdbg)` prompt)
  are added only under `spec.build.host?`, so a firmware build never sees
  the console UI's I/O dependency at all — the core (`MRDebug`, `Session`,
  `Command`, the VM hook) has none. `spec.rbfiles +=` (rather than
  replacing `spec.rbfiles`) is what makes this additive-and-safe: confirmed
  via `MRuby::Gem::Specification#setup` giving `@rbfiles` its default value
  from `mrblib/**/*.rb` *before* `instance_eval(&@initializer)` runs this
  file's block (`lib/mruby/gem.rb` in the mruby checkout). A PicoRuby
  firmware build (`picoruby && !host`) instead gets only
  `tools/mrdebug/{transport/socket,ui/local_console,device}.rb` plus the
  socket/env gems — enough for `MRDebug.listen_tcp` on the device, no CLI
  and no stdio. Each of these
  dependencies is declared via `core:` on mainline mruby, or
  `gemdir:` pointing straight at PicoRuby's vendored copy
  (`mrbgems/picoruby-mruby/lib/mruby/mrbgems/<name>`) when
  `spec.build.respond_to?(:picoruby?) && spec.build.picoruby?` — `core:`
  always resolves under `MRUBY_ROOT/mrbgems`, which is where mainline
  keeps these gems but not where PicoRuby vendors them, and
  `build.picoruby?` only exists on PicoRuby's own `MRuby::Build` subclass,
  hence the `respond_to?` guard. This is the same pattern PicoRuby's own
  `stdlib.gembox` already uses for `mruby-binding`/`mruby-eval`, not
  something invented here.
- **`console/`** — a separate gem, `mrdebug-console` (`conf.gem ...,
  path: 'console'`), for the on-device `(mrdbg)` prompt on PicoRuby.
  Depends on `mrdebug` (via `gemdir:` to the parent directory),
  `picoruby-editor` and `picoruby-io-console`. `MRDebug::UI::Console` reads
  the device's own raw console through `Editor::Line`, and its
  `MRDebug.autostart` overrides `tools/mrdebug/device.rb`'s (it loads
  later as a dependent), so a device with this gem opens the console on
  the first `binding.debugger` rather than looking at `MRDEBUG_PORT`.
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
    context rather than reusing one. `dbg_context_reset` also clears
    `c->svars[0]` so a previous callback's special variables (`$~`, ...)
    don't linger in the root frame; this needs a mruby (or PicoRuby-vendored
    mruby) new enough to have `struct mrb_context`'s `svars` field.
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
  - **Method breakpoints** (`check_method_call`, modeled on mruby's own
    `mrdb`): every armed tick, `mrb_decode_insn(pc)` (from
    `mruby-compiler`, a transitive dep via `mruby-eval`) checks whether the
    instruction is an `OP_SEND`/`SEND0`/`SENDB`/`SSEND`/`SSEND0`/`SSENDB`;
    if so, and the method symbol is in `hook.method_names` (a small array
    synced from Ruby by `Hook.watch_method_names`, so the common case is
    one symbol compare), it funcalls `Session#method_bp_for(recv, mid,
    is_cfunc)`. A C method (`MRB_METHOD_CFUNC_P`) is stopped on right there
    (its body runs no hook); a Ruby method sets `hook.deferred_bp`
    (GC-registered) so the *next* tick — the callee's first instruction —
    fires the stop, landing inside the method. `on_line` takes an optional
    4th arg (`forced`, the matched breakpoint) for these; the VM hook's
    normal line path still passes exactly 3.
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
    lazily instead). The VM hook's line path always passes exactly 3 args
    (`nil` for `bnd` when hook-triggered) — a test double's `#on_line` needs
    a matching arity (`def on_line(file, line, bnd = nil)`), or the VM hook
    silently swallows the resulting `ArgumentError` via `mrb_protect_error`
    (`src/hook.c`) and nothing appears to happen at all. This exact mistake
    shipped undetected in the old `e2e/scenarios/hook_trace.rb` for several
    steps, since nothing but eyeballing `puts` output checked it. (The
    method-breakpoint path passes a 4th arg, `forced`; a real `Session` and
    the recorder subclasses take `def on_line(file, line, bnd = nil, forced
    = nil)`.)
  - **Frame selection** (`frame`/`up`/`down`): `#select_frame(n)` picks a
    `#backtrace` index (0 = the stop itself) and caches that frame's
    `Hook.frame_binding`; `#binding` and `#location` (what `print`/`list`/
    `cat` use) follow the selected frame, while `@file`/`@line` stay the
    stop's own position (breakpoints, `next`'s depth, the banner). A new
    stop resets the selection to 0. `#backtrace` skips frames with no
    position (C methods), so a backtrace index maps to a raw
    `Hook.frame_*` depth via the private `#frame_list`, not by
    `index + offset`.
  - **`#method_bp_for(recv, mid, is_cfunc)`** (public — the VM hook
    funcalls it) returns the `MethodBreakpoint` whose name matches `mid` and
    whose `#matches_call?(recv)` holds, or `nil`; only in run mode (method
    breakpoints, like line ones, don't fire mid step/next).
    **`#add_method_breakpoint`** appends to the same `@breakpoints` array as
    line breakpoints (one shared number sequence) and calls
    **`#sync_method_names`**, which pushes the active method breakpoints'
    name symbols to `Hook.watch_method_names` (also on remove/clear).
- **`mrblib/mrdebug/line_breakpoint.rb`** — file/line/active, suffix match
  via hand-rolled `String#[]` slicing (see "Avoid `mruby-string-ext`
  methods" above), stable numbering shared with `Session`'s breakpoint
  array (`delete` deactivates in place rather than compacting).
  `#stop_banner(siblings, location)` returns the `"Breakpoint N: …"` headline,
  N being its own index in `siblings` + 1.
- **`mrblib/mrdebug/method_breakpoint.rb`** — `MRDebug::MethodBreakpoint`: a
  `(class_name | nil, method_name, singleton?, condition)` tuple, no
  resolution to file/line (the class need not exist yet). Lives in
  `@breakpoints` beside `LineBreakpoint` and answers the same protocol
  (`active?`, `condition`, `numbered_line`, `stop_banner`); `#match?(file,
  line)` is a hard `false` (it's matched at the call site by `src/hook.c`,
  not by line). `#matches_call?(recv)` is policy B — `recv.is_a?(klass)` for
  `Foo#bar` (subclasses and module includers included), `recv.equal?(klass)`
  for `Foo.bar`; `MethodBreakpoint.resolve` const-gets the name lazily and
  returns `nil` (matches nothing) while it's undefined.
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
  `LocalConsole`/`Console`/the DAP bridge, all of which just print or
  translate its output).
  - **`break`** routes on the argument shape: `parse_method_spec`
    (hand-rolled, no `Regexp` — same reason as the `mruby-string-ext`
    avoidance) recognizes `Const#m` / `Const::Const.m` / bare `m` and calls
    `add_method_breakpoint`; everything else is `[file:]line`. A `.` alone
    doesn't make it a method spec — `foo.rb:8`'s `foo` fails the
    uppercase-`Const` check and falls through to the line path.
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
    layer without a matching axis of variation to justify it. `File.open(file)
    { |f| f.read }` (not `File.read`, which PicoRuby's `picoruby-vfs` `File`
    class has no class method for — confirmed via a real `Cannot open` on
    R2P2-ESP32 hardware, only `#read` as an instance method; not
    `File.readlines` either, which mruby-io's `File` doesn't define) plus a
    hand-rolled `"\n"`-split (`String#split` is core; `#each_line`/`#lines`
    are `mruby-string-ext`, unsafe under `mrbtest` per above) turns the
    file into a 1-indexed line array; `LIST_CONTEXT` (5) lines on either
    side of the target are then clamped to `1..line_count` and formatted
    with a `"  "`/`"=>"` marker prefix for the current line (see README).
- **`mrblib/mrdebug/ui.rb`** — `MRDebug::UI::Base`, the one-method contract
  (`#on_stop(session)`) a UI implements.
- **`mrblib/mrdebug/transport.rb`** — `MRDebug::Transport::Base`:
  the `(mrdbg)` prompt's I/O contract (`#gets`/`#write`), not a wire protocol
  (DAP, rdbg, ...).
- **`mrblib/mrdebug/transport/loopback.rb`** —
  `MRDebug::Transport::Loopback`: an in-process, array-backed transport with
  no I/O, used to test `LocalConsole` under `rake test:unit` without stdio.
- **`tools/mrdebug/transport/stdio.rb`** (host builds only) —
  `MRDebug::Transport::Stdio`: `STDIN`/`STDOUT` via `mruby-io`. Strips a
  trailing newline by hand (`strip_eol`, now shared on `Transport::Base`),
  not `String#chomp` — that's `mruby-string-ext`, which misbehaves under
  `mrbtest`.
- **`tools/mrdebug/transport/socket.rb`** (host builds only) —
  `MRDebug::Transport::Socket`/`TCP`/`Unix`: `mruby-socket`, wrapping the
  accepted (`.listen`, device side) or connected (`.connect`, CLI side)
  socket. `#gets` uses `#sysread`, not mruby-io's buffered `IO#gets` —
  the latter makes `#write` raise `Errno::ESPIPE` (silently swallowed by
  the VM hook, freezing the `(mrdbg)` loop) once a read has more than one
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
  `mrdbg` CLI, the common local case and what makes README's Usage
  example work with zero setup). This is what lets a script carry nothing
  but `binding.debugger`. It's a one-shot by construction (`@session.nil?`
  gates it); a listener bind failure propagates out of `binding.debugger`
  rather than being swallowed. `DEFAULT_PORT` (4711, rdbg's convention) is
  only the fallback for a *port that was asked for but unspecified* — a
  bare `MRDebug.listen_tcp`, or `mrdbg` with no args — not for
  `autostart`, which goes to stdio when `MRDEBUG_PORT` is unset.
  `env_value` tolerates a build without `mruby-env` (`defined?(ENV)`) and
  treats a blank value as unset.
- **`tools/mrdbg/mrdbg_cli_main.c`** (host builds only) — the `mrdbg`
  command's C launcher; mruby builds a `spec.bins` entry only from
  `tools/<bin>/*.c`, so it sits apart from the Ruby under `tools/mrdebug/`.
  It just calls `mrdbg_cli_main` (`tools/mrdebug/cli/main.rb`).
- **`tools/mrdebug/cli/cli.rb`**'s `--port`/`--sock-path` (and no args at
  all, which reads `MRDEBUG_SOCK`/`MRDEBUG_PORT`, falling back to
  `DEFAULT_PORT`, via `connect_auto`) — connect via the
  transports above, then hand off to `#relay`: a raw `IO.select`-based
  byte pump between the socket and real `STDIN`/`STDOUT`, since the
  device's `(mrdbg) ` prompt has no trailing newline for a `#gets`-based
  relay to wait on. A bare `mrdbg FILE:LINE` (a positional arg, no
  connection flag) still runs the interim local demo session instead.
  `Command.dispatch` runs on the device side, so the CLI only relays
  bytes — no structured RPC layer needed here.
- **`tools/mrdebug/cli/dap_server.rb`/`dap_bridge.rb`/`device_link.rb`**
  (host builds only) — `mrdbg --port P --dap-port D`: a host-side DAP
  server (for vscode-rdbg's `attach`) that drives a device over the same
  plain-text `(mrdbg)` protocol, so no JSON ever reaches the device.
  `DapBridge#handle` maps requests to `(mrdbg)` commands (`bt` for
  `stackTrace`, `cat` for `source`); `stepOut`/`scopes`/`variables`/
  `evaluate` aren't implemented, since the text protocol has no way to
  carry a frame's locals.
- **`tools/mrdebug/ui/local_console.rb`** (host builds only) —
  `MRDebug::UI::LocalConsole`: the `(mrdbg)` prompt, one `STDIN.gets` (now via
  a `Transport`, defaulting to `Stdio`) per command. Reading exactly one
  line at a time is what avoids the old `picoruby-editor`-based design's
  known bug (piped/pasted multi-command input losing everything after a
  resuming command) — there's no shared read-ahead buffer to lose data from.
  The stop headline it prints is `session.stop_banner` (see `session.rb`
  above), not a hardcoded string — so a step/next stop reads `Stop: …`, not
  `Breakpoint: …`.

## Known gaps

- **mrdebug never stops in its own source.** `MRDebug::OwnSource`
  (`mrblib/mrdebug/own_source.rb`) is a hardcoded, suffix-matched list of
  this gem's own Ruby files; `Session#stop_reason_for` checks it first and
  refuses to stop (or count against `step N`/`watch`) inside them.
  Hardcoded rather than discovered at runtime (`Dir.glob` would need a
  filesystem, which a PicoRuby target may not have) — update
  `OwnSource::FILES` when adding, removing, or renaming a file under
  `mrblib/mrdebug/` or `tools/mrdebug/`. Missing an
  entry shows up as `step N`/`next N`'s counter being consumed by mrdebug's
  own code, or `watch` reporting a shifted line — symptoms that look like
  VM bugs but aren't.
- **Performance**: `RUN` mode with one or more breakpoints funcalls into
  Ruby once per *executed source line*, everywhere, not just near a
  breakpoint's file — the old C implementation had a fast path that skipped
  irep files unrelated to any breakpoint, dropped when breakpoint matching
  moved to Ruby. Only `MRDebug::Hook.armed` is left as a fast gate on the C
  side (see above), so a build with zero active breakpoints and no
  step/next in flight costs nothing beyond that (~1.8µs/line once armed,
  ~145x on a tight loop).
- **PicoRuby**: no upstream R2P2-ESP32 build_config wiring (verified only
  by adding the gem manually), and no mruby/c VM support.
