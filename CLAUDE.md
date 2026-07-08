# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this gem is

`picoruby-debug` is an in-progress debugger for PicoRuby, aiming for
CRuby's `debug` gem-like functionality. It only works on the **mruby** VM
(`PICORB_VM_MRUBY`); on mruby/c it is inert (`src/mrubyc/debug.c` is an empty
init). See `README.md` in this directory for full usage docs (commands,
build config setup, POSIX host debugging) — read it before making changes,
since it documents behavior and constraints that are easy to regress.

## Design policy

Standard input/output (the `(prdb)` prompt via `Editor::Line`, `puts`, source
listing, etc.) is implemented in Ruby (`mrblib/debugger.rb`). Everything else — VM hook
installation, breakpoint storage/matching, mode tracking, context switching,
Binding construction — is implemented in C (`src/mruby/debug.c`/`debugger.c`)
as much as possible. When adding a feature, keep new console I/O on the Ruby
side and new VM-level mechanics on the C side rather than mixing the two;
this is why none of `src/mruby/*.c` has any HAL/stdio dependency.

## Build & test

There is no dedicated test suite for this gem yet. This repo is a standalone
mrbgem (like `picoruby-ws2812`), not a picoruby checkout itself, so exercising
changes means pointing a picoruby build at your local working copy:

```ruby
conf.gem gemdir: '/absolute/path/to/your/picoruby-debug/checkout'
```

This gem does not depend on `ENV['PICORB_DEBUG']` or any other build flag —
`binding.debugger` works as soon as the gem is in the build, on any target
(POSIX host, ESP32, etc.). It changes `sizeof(mrb_state)` build-wide (see
below), so it affects every build using that build config. R2P2-ESP32
currently adds this gem unconditionally in `xtensa-esp-picoruby.rb`
(`ENV['PICORB_DEBUG']` there only gates unrelated flags like
`ESTALLOC_DEBUG`/`conf.enable_debug`/`-Og`).

For a quick local check, add the `gemdir:` line above to a
[picoruby](https://github.com/picoruby/picoruby) checkout's
`build_config/default.rb`, then:

```sh
cd /path/to/picoruby
rake
build/host/bin/picoruby /path/to/script.rb
```

## Architecture

- **`mrbgem.rake`**: sets `MRB_USE_DEBUG_HOOK` (only on mruby) — this is what
  compiles mruby's `code_fetch_hook` into the VM. `conf.enable_debug` does
  *not* set this; it only defines `MRB_DEBUG`. Because the define changes
  `mrb_state`'s layout and the hook fires from `vm.c` core, it must stay
  build-wide and self-contained in this gem's rake file, not something
  callers opt into separately.
- **`include/`**: shared headers, one per `src/mruby/*.c` file
  (`breakpoint.h`, `line_breakpoint.h`, `watch_breakpoint.h`, `debugger.h`,
  `debug.h`). Each `src/mruby/*.c` file is an independent translation unit
  (see below), so any function it exposes to another file must be declared
  here and given external linkage (no more `static`) — this is what makes
  the split possible without one file `#include`-ing another's `.c`.
  `debug.h`/`debugger.h` are deliberately thin: each declares only the
  handful of functions its file implements for the *other* side to call
  (see `debug.c`/`debugger.c` below) — neither struct's internal layout
  (`picoruby_debugger` in `debugger.c`, the hook-tracking globals in
  `debug.c`) is shared at all, so each file's internal state stays fully
  private to it.
- **`src/*.c`** (`debug.c`, `breakpoint.c`, `line_breakpoint.c`,
  `watch_breakpoint.c`, `debugger.c`): VM dispatch shims, one per class.
  `mrbgem.rake`'s default file globbing only picks up `src/*.c`
  (non-recursive; confirmed in `lib/mruby/gem.rb`'s `srcs_to_objs`), so each
  of these top-level files is auto-detected as its own translation unit and
  `#include`s the real implementation from `mruby/<name>.c` (guarded by
  `#if defined(PICORB_VM_MRUBY)`; this gem is mruby-only, so there's no
  `mrubyc/<name>.c` counterpart for these four — only `debug.c` needs the
  `#elif defined(PICORB_VM_MRUBYC)` branch, since `mrbc_debug_init` in
  `src/mrubyc/debug.c` is the actual entry point the mrubyc gem loader
  calls). This mirrors `picoruby-littlefs`'s `src/littlefs.c` /
  `littlefs_file.c` / `littlefs_dir.c` pattern, just with more files.
- **`src/mruby/breakpoint.c`**: the `Breakpoint` base class. Its C struct
  (`debug_breakpoint`, just an `active` flag, declared in
  `include/breakpoint.h`) is embedded as the **first member** of
  `LineBreakpoint`/`WatchBreakpoint`'s own structs (C99 6.7.2.1 guarantees a
  struct pointer and a pointer to its first member are interconvertible —
  the same idiom as BSD's `sockaddr`/`sockaddr_in`), so
  `debug_breakpoint_active_p`/`debug_breakpoint_deactivate` (extern,
  declared in `include/breakpoint.h`) work on either subclass without
  per-subclass dispatch, and `debugger.c`'s `remove_*`/`clear_*` methods
  reuse them directly instead of duplicating deactivate logic.
  `MRB_SET_INSTANCE_TT(breakpoint, MRB_TT_CDATA)` is set only here;
  `mrb_class_new` copies `MRB_INSTANCE_TT(super)` into subclasses, so
  `LineBreakpoint`/`WatchBreakpoint` inherit CDATA automatically.
- **`src/mruby/line_breakpoint.c`**: `LineBreakpoint` (file/line fields,
  suffix-based `debug_file_match`, both private to this file).
  `debug_line_breakpoint_new`/`debug_line_breakpoint_file_matches`/
  `debug_line_breakpoint_stops_at` are extern (declared in
  `include/line_breakpoint.h`) for `debug.c`'s hot path and `debugger.c`'s
  `add_breakpoint`. Also exposes `break?(file, line)` to Ruby as a
  documented predicate for the same match rule the hot path uses
  internally.
- **`src/mruby/watch_breakpoint.c`**: `WatchBreakpoint` (expr field). The
  "last evaluated value" cache is **not** in this C struct — it's plain
  Ruby ivars on the instance (`WatchBreakpoint#break?`, in
  `mrblib/watch_breakpoint.rb`), since mruby's GC marks ivars on
  `MRB_TT_CDATA` objects the same as any other object, so no custom
  mark/free handling is needed for values that can be arbitrary Ruby
  objects.
- **`src/mruby/debug.c`** and **`src/mruby/debugger.c`** split the VM-hook
  mechanism from the Debugger class's own data along a clean ownership
  line, not just a historical one: **`debugger.c` owns the `Debugger`
  instance's actual data (breakpoints, watches, mode, quit flag);
  `debug.c` owns the VM hook mechanism (installing `code_fetch_hook`,
  swapping `mrb->c`, deciding which instruction to act on) and never
  touches that data directly, only through the query/mutator functions
  `debugger.c` exposes via `include/debugger.h`.**
  - **`src/mruby/debugger.c`**: the `Debugger` class's C methods
    (`add_breakpoint`, `add_watch`, `set_step_mode`, `request_quit`, etc.)
    and `mrb_picoruby_debug_debugger_init`, which defines the class and
    registers them. Owns the private `picoruby_debugger` struct
    (`breakpoints`/`watches` — `mrb_realloc`'d C arrays of `mrb_value`,
    each entry a GC-registered (`mrb_gc_register`) `LineBreakpoint`/
    `WatchBreakpoint` instance, since the array itself is plain C memory
    the GC doesn't scan — plus `mode`, `next_ci`, `quit_requested`), which
    **no other file can see**: this struct's type, `debugger_state`
    (the lazy-init accessor), `picoruby_debugger_free`, and the
    `debug_mode` enum are all `static`/file-local. Everything `debug.c`'s
    hot path needs from this state is exposed instead as small extern
    query functions declared in `include/debugger.h`
    (`mrb_debugger_watching_p`, `mrb_debugger_mode_run_p`,
    `mrb_debugger_has_breakpoints_p`, `mrb_debugger_file_relevant_p`,
    `mrb_debugger_should_break_p`, `mrb_debugger_quit_requested_p`,
    `mrb_debugger_update_next_ci`, `mrb_debugger_reset_mode`) — each reads
    fields straight through `DATA_PTR` (no per-call type check) via the
    extern helpers from `breakpoint.c`/`line_breakpoint.c`, so this is a
    plain C function call from `debug.c`, not a `mrb_funcall`, and costs
    about the same as the old direct-field-access design.
    `mrb_gc_unregister` only runs in two places: `picoruby_debugger_free`
    (Debugger teardown) and `clear_breakpoints`/`clear_watches` — unlike
    `remove_breakpoint`/`remove_watch` (single delete: deactivate in
    place, never freed until teardown), a bare `delete`/`unwatch` frees
    everything immediately and resets the count to 0, so the next add
    renumbers from #1 — this is pre-existing behavior the class-split
    refactor preserves, and forgetting the immediate `gc_unregister`
    there would leak/desync it. `enable_hook`/`disable_hook` are the two
    Debugger methods whose *bodies* live in `debug.c` instead (see below)
    — this file just registers them by name via the `include/debug.h`
    declarations, since their job is installing/removing the VM hook
    itself, not touching `picoruby_debugger`.
  - **`src/mruby/debug.c`**: VM hook mechanics only. No knowledge of
    `picoruby_debugger`'s layout at all — everywhere the old code read a
    struct field directly, it now calls one of the `include/debugger.h`
    functions above, passing the currently-active Debugger instance as a
    plain `mrb_value`. That instance is tracked via this file's own
    globals (`active_debugger_self`/`active_debugger_p`), not stored
    inside the Debugger's struct — there's only ever one active Debugger
    (owning the hook) at a time, so a global is simpler than threading an
    instance reference through per-instance state. The same reasoning
    applies to `in_break` (re-entrancy guard), `prev_line`/`prev_irep`
    (same-line dedup), and `debugger_self_registered` (GC-registration
    bookkeeping): none of these are ever read or written by Ruby-facing
    Debugger methods, so they're plain `static` globals here rather than
    struct fields. `debug_code_fetch_hook` — the actual
    `mrb->code_fetch_hook` callback — reads the globals above, then asks
    `debugger.c`'s query functions whether to act; `debug_invoke_on_break`
    does the same for `quit_requested`/`next_ci` after the `on_break`
    funcall returns. `mrb_debugger_enable_hook`/`disable_hook` (declared
    in `include/debug.h`, registered on the Debugger class by
    `debugger.c`) also live here since installing/removing the hook and
    setting `active_debugger_self`/`_p` are exactly this file's
    responsibility. Key mechanics, in case of changes:
  - **Context switch around callbacks**: `debug_invoke_on_break` must swap
    `mrb->c` to `mrb->c->prev` before `mrb_funcall_id`-ing into
    `Debugger#on_break`, because the enclosing `mrb_vm_exec` (for the
    debugged task) caches `ci`/`regs` in locals that a stack-growing funcall
    on the *same* context would leave dangling. The hook also self-disables
    (`mrb->code_fetch_hook = NULL`) during the callback to avoid recursing.
  - **Quit** is deferred: `request_quit` (in `debugger.c`) just sets a
    flag; the actual `mrb->c->status = MRB_TASK_STOPPED` happens back in
    `debug_invoke_on_break` (via `mrb_debugger_quit_requested_p`) after
    `mrb->c` is restored to the debugged task's own context.
  - **Modes** (`DBG_MODE_RUN` / `STEP` / `NEXT`, private to `debugger.c`)
    are checked inside `mrb_debugger_should_break_p`. RUN has a fast path
    (`mrb_debugger_file_relevant_p`) that skips ireps outside any
    breakpoint's file so diving into library calls (e.g. `puts`) doesn't
    reprocess every line.
  - **Watchpoints** (`watch`/`unwatch`) add a second, independent reason for
    the hook to fire: `mrb_debugger_watching_p` forces the hook to give up
    the RUN-mode fast path and visit every line, in every file, while any
    watch is active — a watched expression can change from anywhere. The
    hook still computes `mrb_debugger_should_break_p` (breakpoints/STEP/
    NEXT) as before and passes it to `debug_invoke_on_break` as
    `real_stop`; when a line is visited only because of an active watch
    (`real_stop == 0`), Ruby's `on_break` evaluates the watch expressions
    and silently returns if none changed, so the extra visits are
    invisible unless a watch actually fires. Because watch-forced visits
    can happen from a deeper frame than a `next` was issued from,
    `mrb_debugger_update_next_ci` only refreshes `next_ci` when
    `real_stop` is true — otherwise a watch-only visit deep in a call
    would corrupt NEXT's frame-depth tracking and cause spurious stops
    inside called methods.
  - **Bindings for `print`**: `debug_make_binding` builds a `Binding` from
    the paused frame's `ci`/`env` (mirroring `Kernel#binding`); nil for a C
    frame. All console output is on the Ruby side — this file has no
    HAL/stdio dependency.
  - `mrb_binding_debugger` (the `binding.debugger`/`b`/`break` entry point)
    also lives here, along with `mrb_picoruby_debug_gem_init`/`_gem_final`
    — the gem's actual init/final entry points, which call the four
    `mrb_picoruby_debug_*_init` functions (breakpoint, line_breakpoint,
    watch_breakpoint, debugger) in dependency order before registering
    `Binding#debugger`/`#b`/`#break`.
- **`mrblib/debugger.rb`**: the `Debugger` class — the interactive `(prdb)`
  prompt loop (`on_break`), the command dispatch bodies, and `list_entries`
  (the shared 1-based/stable listing loop used by both `list_breakpoints`
  and `list_watches`). C methods it calls (`add_breakpoint`, `set_step_mode`,
  `request_quit`, etc.) are defined in `src/mruby/debugger.c`.
- **`mrblib/breakpoint.rb`/`line_breakpoint.rb`/`watch_breakpoint.rb`**: the
  Ruby-side half of the three CDATA classes above — mostly `to_s`/
  `numbered_line` formatting, plus `WatchBreakpoint#break?`/
  `#add_initial_value` (the value-cache/change-detection logic that used to
  live in `Debugger#check_watches`/`@watch_cache`).
- **`mrblib/display.rb`**: `Display` — one display expression (`expr` +
  `active` flag + `print_line`). Pure Ruby, no C counterpart: unlike
  breakpoints/watches, `display`/`undisplay` need no VM mechanic — they just
  re-evaluate and print at whatever timing `on_break` already runs at.
  `Debugger#@displays` is an `Array<Display>`.
- Breakpoint file matching is **suffix-based** (`debug_file_match`) and
  numbering is **stable**: `remove_breakpoint`/`delete_breakpoint` deactivate
  in place rather than compacting the array, so existing breakpoint numbers
  never shift. The same stable-numbering convention is used for watchpoints
  and display expressions.

## Dependencies

- `picoruby-sandbox`
- `picoruby-editor` (the `(prdb)` prompt's line editor, `Editor::Line`) and
  `picoruby-io-console` (the raw-mode/non-blocking reads it's built on) —
  same stack `picoruby-shell` uses, so typed characters echo immediately
  even on platforms with no OS-level tty echo (e.g. ESP32). On POSIX,
  `on_break` also brackets the prompt loop in `STDIN.raw!`/`STDIN.cooked!`
  (unlike `picoruby-shell`'s `r2p2` binary, which forces raw mode once for
  the whole process at C-level startup — see `init_posix()` in
  `picoruby-bin-r2p2/tools/r2p2/r2p2.c` — plain `build/host/bin/picoruby`
  does not, so without this the terminal reverts to cooked/echoing mode
  between `Editor::Line`'s polls and every character gets echoed twice).
- `picoruby-machine` (for `picorb_hal_write`, stdio-free console output)
- mruby only: `mruby-binding`, `mruby-eval`

## Known gaps (in progress)

- `bt`/`where` prints only the current location, not a real backtrace.
- No `mrb_protect` around the `on_break` funcall in general. This used to
  also cover Ctrl-C from `gets` escaping with the hook/context swapped out,
  but that specific case is now closed: `on_break`'s prompt loop is built on
  `Editor::Line#start` (see `Debugger#initialize`/`#on_break` in
  `mrblib/debugger.rb`), which already `rescue`s `Interrupt` internally
  around its own `read_nonblock` call and never lets it propagate out of
  `on_break`. Other exception sources escaping the funcall unprotected is
  still an open, unrelated gap.
- `Editor::Line#start`'s per-poll `STDIN.read_nonblock(255)` can read more
  than one full command (with its trailing Enter) into its local `line`
  buffer in a single call — e.g. multiple commands piped/pasted at once. If
  one of the *earlier* commands in that chunk causes the `on_break` block to
  call `break` (`continue`/`step`/`next`/`quit`), that `break` unwinds
  straight out of `Editor::Line#start` (see the "break-inside-yielded-block"
  note above), silently discarding whatever was left unread in `line` —
  including any *later* command in the same chunk. Confirmed via
  `printf 'b 9\nc\nc\n' | build/host/bin/picoruby script.rb`: the second `c`
  is lost and the process hangs waiting for input that was already piped in.
  Typing interactively doesn't trigger this in practice (each keystroke
  normally arrives in its own poll), but pasting/piping several commands
  including a resuming one can. Fixing it properly needs `Editor::Line` (a
  `picoruby-editor` class also used by `picoruby-shell`) to preserve
  unconsumed input across a break-triggered exit from `start`, which is out
  of scope for this gem alone.
