# Joy host patch: the `memory access out of bounds` blocker

The Roc app in this directory crashes on its first message dispatch (`RuntimeError: memory access out of bounds`)
when it is built against the stock Joy 0.33.0 platform. Two independent causes were found and fixed; this note
records the host patch, because the platform bundle in `app.roc` ships the unpatched host.

## Cause 1 — Joy's host allocator assumes it is the only code that grows memory

`host/host.rs` in the Joy platform bumps a cursor through wasm linear memory:

```rust
let prev = core::arch::wasm32::memory_grow(0, pages);
if prev == usize::MAX { return 0; }
END += pages * PAGE; // contiguous: nobody else grows memory
```

The Roc **boxy runtime**, which the compiler links into every wasm app that has closures, allocates through
Zig's `std.heap.page_allocator` (`src/boxy_runtime/main.zig`) and grows the same memory independently. Once an
app creates enough closures (this one registers procs for every `on_click`/`on_input` site), the runtime grows
memory after the host has started allocating, the host's `END` goes stale, and it hands out spans that overlap
the runtime's pages. The next proc registration then traps in `roc_boxy_register_erased_proc`.

Symptoms this explains: traps only on the *second* host entry; both the data path (`dispatch_value`) and the
subscription path (`sync_subs` → `roc_subs`); removing enough of the render (the sidebar, the breadcrumbs)
avoids it; minimal Joy apps are unaffected; no compiler version, opt mode, stack size or initial memory size
changes it.

### The patch (`host/host.rs`, `bump_span`)

```rust
    let start = NEXT;
    let end = start + total;
    if end > END {
        let pages = (end - END + PAGE - 1) / PAGE;
        let prev = core::arch::wasm32::memory_grow(0, pages);
        if prev == usize::MAX {
            return 0;
        }
        END += pages * PAGE; // contiguous: nobody else grows memory
    }
```

becomes

```rust
    // The Roc boxy runtime allocates through its own page allocator, which grows
    // linear memory behind our back, so END can lag the real end. Re-read it and
    // skip past any pages it took: handing out a span that overlaps them would
    // corrupt the heap.
    let cur = core::arch::wasm32::memory_size(0) * PAGE;
    if cur > END {
        END = cur;
        if NEXT < cur {
            NEXT = align_up(cur, 16);
        }
    }
    let start = NEXT;
    let end = start + total;
    if end > END {
        let pages = (end - END + PAGE - 1) / PAGE;
        let prev = core::arch::wasm32::memory_grow(0, pages);
        if prev == usize::MAX {
            return 0;
        }
        END = prev * PAGE + pages * PAGE; // the real end, not the stale one
    }
```

## Cause 2 — the page never unwrapped SurrealDB's response envelope

`www/index.html` read rows with `Array.isArray(data) ? data : (data[0]?.result || [])`. SurrealDB answers with a
one-element envelope (`[{ result: [...], status: "OK", ... }]`), which *is* an array, so every list was built
from the envelope itself and rendered one fieldless row (`|Unknown|`, `Unknown||true`). Fixed by the shared
`unwrapRows` helper in `index.html`.

## Building against the patched host

The patch is checked in beside this note as `joy-host-bump-span.patch`; apply it to a Joy 0.33.0 checkout with
`git apply joy-host-bump-span.patch`.

```sh
git clone --depth 1 --branch 0.33.0 https://github.com/niclas-ahden/joy.git /tmp/joy-src
# apply the bump_span patch above to /tmp/joy-src/host/host.rs
mkdir -p /tmp/joy-src/platform/targets/wasm32 /tmp/joy-src/platform/www
cp ~/.cache/roc/packages/9UWLeQeJEUkXNGmZtibc1aqpL3gm6Li65GvXxsML5vFz/www/runtime.js /tmp/joy-src/platform/www/runtime.js
rustc --edition 2021 --target wasm32-unknown-unknown --crate-type staticlib \
  -C opt-level=2 -C panic=abort --cfg joy_bench --emit obj \
  /tmp/joy-src/host/host.rs -o /tmp/joy-src/platform/targets/wasm32/host.wasm
```

`--cfg joy_bench` is required: the platform's `main.roc` exports `bench_phase_ms`, which only that host build
provides (otherwise `wasm-ld` fails with `symbol exported via --export not found`).

Then point the app's platform at the checkout and build:

```roc
	pf: platform "/tmp/joy-src/platform/main.roc",
```

```sh
roc build --target=wasm32 --no-cache --output=www/app.wasm app.roc
```

`www/app.wasm` in this tree is the build made that way, so the app works as shipped. Rebuilding it from the
unmodified `app.roc` (remote platform URL) reproduces the crash.

## Upstream report (ready to post to niclas-ahden/joy)

> **Host allocator can overlap pages grown by the Roc boxy runtime**
>
> Apps that register enough erased procs trap with `RuntimeError: memory access out of bounds` in
> `roc_boxy_register_erased_proc` on their second host entry (a data dispatch or a subscription sync), while
> minimal apps are fine. `bump_span` in `host/host.rs` assumes the host is the only code that grows linear
> memory (`END += pages * PAGE; // contiguous: nobody else grows memory`), but the Roc boxy runtime's
> `std.heap.page_allocator` grows it too, so once it grows after the host has started allocating, `END` is
> stale and the host hands out spans that overlap the runtime's pages. Re-reading `memory_size(0)` before
> bumping and using `memory_grow`'s return value for `END` (patch above) fixes it; I verified with an app that
> trapped before and runs cleanly after.
