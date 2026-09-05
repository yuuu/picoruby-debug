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

PicoRuby/R2P2 support does not exist yet — phase 1 is mruby-only,
deliberately. Don't add `PICORB_VM_MRUBY`-style branching back in without
that being an explicit, planned phase.

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
-g`): without it, AOT-compiled `test/*.rb` has no line info, and the VM hook
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

- `test/*.rb` — plain `assert` (`test/line_breakpoint.rb`, `test/session.rb`,
  `test/command.rb`): pure-Ruby logic, no VM hook involved. `Session`'s
  `:next`-mode depth comparison is checked by stubbing
  `MRDebug::Hook.frame_count` (`Hook.define_singleton_method(:frame_count)
  { ... }`, removed again in an `ensure`) rather than relying on a real
  paused context.
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
`test/*.rb`/`test/e2e/*.rb` (not from a plain `bin/mruby script.rb` run) —
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
  gems (`mruby-binding`, `mruby-eval`); `mruby-io` and
  `tools/mrdebug/**/*.rb` (the `(prdb)` prompt) are added only under
  `spec.build.host?`, so a firmware build never sees the console UI's I/O
  dependency at all — the core (`MRDebug`, `Session`, `Command`, the VM
  hook) has none. `spec.rbfiles +=` (rather than replacing `spec.rbfiles`)
  is what makes this additive-and-safe: confirmed via
  `MRuby::Gem::Specification#setup` giving `@rbfiles` its default value
  from `mrblib/**/*.rb` *before* `instance_eval(&@initializer)` runs this
  file's block (`lib/mruby/gem.rb` in the mruby checkout).
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
    context rather than reusing one.
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
  entry point.
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
- **`mrblib/mrdebug/own_source.rb`** — `MRDebug::OwnSource`: the hardcoded
  suffix-matched file list `Session#should_break?` checks first, to never
  stop (or count against `step N`/`watch`) inside this gem's own code. See
  "Known gaps" below.
- **`mrblib/mrdebug/command.rb`** — `MRDebug::Command.dispatch(session,
  line)` parses one command line and returns `[output_lines, :stay |
  :resume]`; it never prints. This is what keeps the command layer testable
  without stdio and reusable across front ends (today just
  `LocalConsole`, but the split is exactly the "coreoutputs data, UI prints
  it" boundary `docs/plan-phase1.md` calls for).
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
  trailing newline by hand (`strip_eol`), not `String#chomp` — that's
  `mruby-string-ext`, which misbehaves under `mrbtest`.
- **`tools/mrdebug/ui/local_console.rb`** (host builds only) —
  `MRDebug::UI::LocalConsole`: the `(prdb)` prompt, one `STDIN.gets` (now via
  a `Transport`, defaulting to `Stdio`) per command. Reading exactly one
  line at a time is what avoids the old `picoruby-editor`-based design's
  known bug (piped/pasted multi-command input losing everything after a
  resuming command) — there's no shared read-ahead buffer to lose data from.

## Known gaps (in progress)

- **~~Stepping through mrdebug's own source~~ — fixed.**
  `MRDebug::OwnSource` (`mrblib/mrdebug/own_source.rb`) is a hardcoded,
  suffix-matched list of this gem's own Ruby files; `Session#should_break?`
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
- **PicoRuby/R2P2 support does not exist.** Phase 1 is deliberately
  mruby-only; see `docs/plan-phase1.md`'s "後続フェーズに送る項目" for what a
  PicoRuby phase would need to add back (dependency-injection points for
  `mrbgem.rake`, an on-device console UI gem depending on
  `picoruby-editor`/`picoruby-io-console`, etc.) — don't reintroduce
  `PICORB_VM_MRUBY`-style branching speculatively.
