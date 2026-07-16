// Hash map — the `HashMap` typsy class, the `hashmap(..)` factory, and
// the per-DS theme. Rides on the hash-map draw backend in
// `hashmap-draw.typ` (the analog of how `bst.typ` rides on `tree-anim`
// and `graph.typ` rides on `graph-draw`).
//
// A hash table is a fixed-length array of `capacity` slots. Keys are
// placed by a pluggable hash function `(key, m) => index`; collisions are
// resolved by one of three strategies:
//   * "chaining"  — each slot holds a linked list (chain) of entries.
//   * "linear"    — open addressing; probe (h + i)     mod m.
//   * "quadratic" — open addressing; probe (h + i*i)   mod m.
//
// Slot representation:
//   * chaining        : slot = array of entry dicts (key:, label:, value:)
//   * open addressing : slot = none | entry dict | (tombstone: true)
// A tombstone marks a deleted open-addressing slot: search must skip over
// it (unlike an empty slot, which terminates the probe), and insert may
// reuse the first one it passes.

#import "@preview/typsy:0.2.2": *
#import "./anim-core.typ" as core
#import "./hashmap-draw.typ" as hm-draw
#import "./op-theme.typ": _resolve-op-theme-arg

// Resolve a `render-theme:` argument that may be `auto` (read state) or a
// partial dict (merge into default). Mirrors the same helper in the
// other DS modules.
#let _resolve-render-theme-arg(theme) = if theme == auto {
  auto
} else { core._merge-render-theme(theme) }

// ===================================================================
// Per-DS theme — the hash-map palette
// ===================================================================
//
// Structural colours (node/edge/note fills) come from `render-theme`;
// operation strokes (probe walk, landing, miss) from `op-theme`. This
// per-DS theme carries only what's intrinsic to a hash table: the empty
// slot fill, the small index labels, the hash-box frame, tombstone
// styling, and the chain link/box colours.

/// Default hash-map palette. Pass a partial dict to
/// #raw("set-hashmap-theme(..)") to override individual roles.
#let default-hashmap-theme = (
  empty-fill: rgb("#f2f2f2"),
  index-fill: rgb("#888888"),
  hash-box-fill: white,
  hash-box-stroke: black,
  tombstone-fill: rgb("#e0e0e0"),
  tombstone-stroke: rgb("#999999"),
  chain-stroke: black,
  chain-fill: white,
)

#let _hashmap-theme-keys = (
  "empty-fill",
  "index-fill",
  "hash-box-fill",
  "hash-box-stroke",
  "tombstone-fill",
  "tombstone-stroke",
  "chain-stroke",
  "chain-fill",
)

/// Typsy refinement: a dictionary whose keys are a subset of the
/// hash-map theme keys. Used by #raw("set-hashmap-theme") and the
/// per-call #raw("theme:") arguments to give early errors on typos.
#let HashmapTheme = Refine(
  Dictionary(..Any),
  d => d.keys().all(k => _hashmap-theme-keys.contains(k)),
)

#let _hashmap-theme-state = state("starling:hashmap-theme", default-hashmap-theme)

/// Override one or more hash-map theme keys for the rest of the document
/// (state-based, scoped by Typst's normal layout flow). Pass a partial
/// dictionary — only the keys you list are changed; the rest stay at
/// their current values. Unknown keys panic.
#let set-hashmap-theme(theme) = {
  for k in theme.keys() {
    if not _hashmap-theme-keys.contains(k) {
      panic(
        "set-hashmap-theme: unknown key '"
          + k
          + "'. Valid keys: "
          + _hashmap-theme-keys.join(", ")
          + ".",
      )
    }
  }
  _hashmap-theme-state.update(prev => {
    let next = prev
    for (k, v) in theme.pairs() { next.insert(k, v) }
    next
  })
}

// Merge a partial hashmap-theme override into `default-hashmap-theme`,
// panicking on unknown keys. Used by per-call `theme:` arguments.
#let _merge-hashmap-theme(override) = {
  for k in override.keys() {
    if not _hashmap-theme-keys.contains(k) {
      panic(
        "hashmap-theme: unknown key '"
          + k
          + "'. Valid keys: "
          + _hashmap-theme-keys.join(", ")
          + ".",
      )
    }
  }
  let next = default-hashmap-theme
  for (k, v) in override.pairs() { next.insert(k, v) }
  next
}

#let _resolve-hashmap-theme-arg(theme) = if theme == auto {
  auto
} else { _merge-hashmap-theme(theme) }

// The render-theme dict `draw-hashmap` consumes is the merged
// render-theme plus the hash-map palette laid on top (the backend reads
// both key families off one dict). Combine them here.
#let _combined-render-theme(rt, hm) = {
  let out = rt
  for (k, v) in hm.pairs() { out.insert(k, v) }
  out
}

// ===================================================================
// Pure-op helpers (module-level, take a `HashMap` as first arg)
// ===================================================================

// The normalized bucket index for `key` in a table of `hm.capacity`
// slots. Defensively wraps into [0, m) even if the user's hash function
// returns out of range or negative.
#let _hash-index(hm, key) = {
  let raw = (hm.hash.fn)(key, hm.capacity)
  let r = calc.rem(raw, hm.capacity)
  if r < 0 { r + hm.capacity } else { r }
}

// The (nonzero) step size for double hashing: the second hash function
// normalized into [1, m). A zero step would stall the probe, so it's
// bumped to 1.
#let _hash2-step(hm, key) = {
  let raw = (hm.hash2.fn)(key, hm.capacity)
  let s = calc.rem(raw, hm.capacity)
  if s < 0 { s = s + hm.capacity }
  if s == 0 { 1 } else { s }
}

// The open-addressing probe sequence for `key`: `capacity` indices in
// probe order. Linear steps by i; quadratic by i*i; double hashing by
// i * h2(key) (all mod m). For chaining there is a single relevant
// bucket, so we return `(h,)`.
#let _probe-seq(hm, key) = {
  let h = _hash-index(hm, key)
  let m = hm.capacity
  if hm.strategy == "chaining" {
    (h,)
  } else if hm.strategy == "linear" {
    range(m).map(i => calc.rem(h + i, m))
  } else if hm.strategy == "quadratic" {
    range(m).map(i => calc.rem(h + i * i, m))
  } else {
    let step = _hash2-step(hm, key)
    range(m).map(i => calc.rem(h + i * step, m))
  }
}

// Substitute the key for `k` and the capacity for `m` in a hash-repr
// string (word-boundary regex so `mod` is left intact). Double-backslash
// so the Typst string carries a literal `\b` into the regex engine as a
// word boundary (a single `\b` would be a backspace char and never
// match). Parenthesised so the multi-line method chain is read as one
// expression (a bare `#let x = a\n  .f()` ends at the newline at module
// scope).
#let _sub-repr(repr, key, m) = (
  repr
    .replace(regex("\\bk\\b"), str(key))
    .replace(regex("\\bm\\b"), str(m))
)
#let _expr-of(hm, key) = _sub-repr(hm.hash-repr, key, hm.capacity)
#let _expr2-of(hm, key) = _sub-repr(hm.hash2-repr, key, hm.capacity)

#let _make-entry(key, value, label) = (
  key: key,
  label: if label == auto { str(key) } else { label },
  value: value,
)

#let _classify-slot(slot, key) = if slot == none {
  "empty"
} else if slot.at("tombstone", default: false) {
  "tombstone"
} else if slot.key == key {
  "same"
} else { "other" }

// Walk the open-addressing probe sequence for `key`. Returns a record:
//   steps      — array of (probe:, index:, state:) for every slot visited
//   kind       — "found" (key present), "empty" (hit an empty slot),
//                or "exhausted" (walked all m probes, no empty/same)
//   index      — the landing index for "found"/"empty"
//   first-tomb — index of the first tombstone passed (none if none)
// Search stops at the first empty; insert reuses `first-tomb` if set.
#let _oa-walk(hm, key) = {
  let seq = _probe-seq(hm, key)
  let first-tomb = none
  let steps = ()
  for (i, idx) in seq.enumerate() {
    let slot = hm.slots.at(idx)
    let state = _classify-slot(slot, key)
    steps.push((probe: i, index: idx, state: state))
    if state == "same" {
      return (steps: steps, kind: "found", index: idx, first-tomb: first-tomb)
    } else if state == "empty" {
      return (steps: steps, kind: "empty", index: idx, first-tomb: first-tomb)
    } else if state == "tombstone" and first-tomb == none {
      first-tomb = idx
    }
  }
  (steps: steps, kind: "exhausted", index: none, first-tomb: first-tomb)
}

// Walk the chain at `key`'s bucket. Returns:
//   bucket — the bucket index
//   steps  — array of (depth:, index:, same:) for every entry compared
//   kind   — "found" or "absent"
//   depth  — the matching entry's depth (for "found")
#let _chain-walk(hm, key) = {
  let idx = _hash-index(hm, key)
  let chain = hm.slots.at(idx)
  let steps = ()
  for (j, entry) in chain.enumerate() {
    let same = entry.key == key
    steps.push((depth: j, index: idx, same: same))
    if same {
      return (bucket: idx, steps: steps, kind: "found", depth: j)
    }
  }
  (bucket: idx, steps: steps, kind: "absent", depth: chain.len())
}

// The live entries in slot order (chaining: chains flattened bucket by
// bucket; open addressing: non-empty, non-tombstone slots).
#let _live-entries(hm) = {
  let out = ()
  for slot in hm.slots {
    if hm.strategy == "chaining" {
      out += slot
    } else if slot != none and not slot.at("tombstone", default: false) {
      out.push(slot)
    }
  }
  out
}

// Rebuild a HashMap with new `slots` (same everything else).
#let _rebuild(hm, slots) = (hm.meta.cls.new)(
  capacity: hm.capacity,
  strategy: hm.strategy,
  hash: hm.hash,
  hash-repr: hm.hash-repr,
  hash2: hm.hash2,
  hash2-repr: hm.hash2-repr,
  slots: slots,
)

// ===================================================================
// Display-frame helpers
// ===================================================================

// The positioned-table dict the backend consumes. `hm.slots` is already
// in the backend's expected shape, so this is a thin wrapper; `cells`
// may be overridden for frames that show a table state other than the
// map's own (e.g. resize showing the pre-insert new array).
#let _to-table(hm, orientation, cells: auto, capacity: auto, strategy: auto, hash-box: none, cell-width: auto, phantom: none) = (
  capacity: if capacity == auto { hm.capacity } else { capacity },
  orientation: orientation,
  strategy: if strategy == auto { hm.strategy } else { strategy },
  cells: if cells == auto { hm.slots } else { cells },
  hash-box: hash-box,
  cell-width: cell-width,
  phantom: phantom,
)

// The hash-box overlay dict for `key` on `hm` (an operation annotation
// pointing at the initial hash slot). `index` is where the hash sends
// the key before any probing. For double hashing it also carries the
// second-hash formula (`expr2`) and its step value (`step`), which the
// backend renders as a second line.
#let _hash-box(hm, key) = {
  let base = (
    key: key,
    expr: _expr-of(hm, key),
    index: _hash-index(hm, key),
    expr2: none,
    step: none,
  )
  if hm.strategy == "double" {
    base.expr2 = _expr2-of(hm, key)
    base.step = _hash2-step(hm, key)
  }
  base
}

// Build Frame records from per-frame specs. Each spec carries:
//   table  — the positioned table for that frame
//   build  — (op-theme, render-theme) => Snapshot. Shared across a phase
//            where possible so Typst's call cache amortizes the work.
//   caption / step / alt — theme-independent metadata
// `hm-theme` / `render-theme` are pre-resolved (`auto` => read state at
// render time). op-theme is always the `op-arg` the lib helpers resolve
// and pass in. The render-theme handed to the backend and the snapshot
// builder is the render theme with the hash-map palette merged on top.
#let _hm-make-frames-multi(specs, hm-theme, render-theme, cell-width: "fit") = {
  specs.map(s => (core.Frame.new)(
    _builder: (
      fn: (op-arg, rt-arg) => {
        let hm = if hm-theme == auto {
          _hashmap-theme-state.get()
        } else { hm-theme }
        let rt = if render-theme == auto { rt-arg } else { render-theme }
        let combined = _combined-render-theme(rt, hm)
        let snap = (s.build)(op-arg, combined)
        // Pin the sizing mode for this render (displays fit to content by
        // default — they always render inside the lib helpers' `context`,
        // so `measure` is available).
        let table = s.table
        table.cell-width = cell-width
        core._make-canvas(
          hm-draw._draw-hashmap-backend,
          table,
          snap,
          (:),
          (:),
          combined,
        )
      },
    ),
    caption: s.caption,
    step: s.step,
    alt: s.alt,
  ))
}

// Convenience: a blank snapshot with one node styled. Keeps the spec
// build closures terse.
#let _styled(key, ..style) = {
  let s = core.blank-snapshot()
  (s.style-node)(key, ..style)
}

// ===================================================================
// Operation animations (insert / search / delete)
// ===================================================================
//
// All three share a leading "walk" phase — the hash box appears, then
// the probe sequence (open addressing) or bucket chain (chaining) is
// highlighted step by step. `_walk-frames` produces those common
// frames plus the walk result; each operation appends its own terminal
// frame(s). Frame vocabulary (`step.kind`): "init", "hash", "probe",
// "compare", "insert"/"update", "full", "found", "not-found", "remove",
// "deleted", "tombstone".

// The shared leading frames. `action` ("insert"/"look up"/"delete")
// only tunes the init alt text. Returns
// `(specs: array, walk: dict, hb: dict)`.
#let _walk-frames(hm, key, orientation, action) = {
  let hb = _hash-box(hm, key)
  let base-alt = (
    "Hash table: "
      + (hm.describe)()
      + ". About to "
      + action
      + " "
      + str(key)
      + "."
  )
  // The init frame reserves the hash box's footprint with a *ghost* box (same
  // geometry, nothing drawn) so the table doesn't jump on the slide when the
  // real hash box appears on the next subslide.
  let init = (
    table: _to-table(hm, orientation, hash-box: (..hb, ghost: true)),
    build: (_op, _rt) => core.blank-snapshot(),
    caption: none,
    step: (kind: "init"),
    alt: base-alt,
  )

  if hm.strategy == "chaining" {
    let w = _chain-walk(hm, key)
    let bucket = w.bucket
    let specs = (
      init,
      (
        table: _to-table(hm, orientation, hash-box: hb),
        build: (op, _rt) => _styled(hm-draw.cell-key(bucket), stroke: op.attention-stroke),
        caption: [h(#key) = #bucket],
        step: (kind: "hash", bucket: bucket),
        alt: "h(" + str(key) + ") = " + str(bucket) + "; scan bucket " + str(bucket) + ".",
      ),
    )
    let compared = ()
    for st in w.steps {
      compared.push(st.depth)
      let snap-compared = compared
      let entry-lbl = hm.slots.at(bucket).at(st.depth).label
      specs.push((
        table: _to-table(hm, orientation, hash-box: hb),
        build: (op, _rt) => {
          let s = _styled(hm-draw.cell-key(bucket), stroke: op.attention-stroke)
          for d in snap-compared {
            s = (s.style-node)(hm-draw.entry-key(bucket, d), stroke: op.search-stroke)
          }
          s
        },
        caption: [compare #entry-lbl],
        step: (kind: "compare", bucket: bucket, depth: st.depth, same: st.same),
        alt: "Compare with the entry at depth " + str(st.depth) + " of bucket " + str(bucket) + ".",
      ))
    }
    return (specs: specs, walk: w, hb: hb)
  }

  // Open addressing (linear / quadratic).
  let w = _oa-walk(hm, key)
  let specs = (init,)
  let probed = ()
  for (i, st) in w.steps.enumerate() {
    probed.push(st.index)
    let snap-probed = probed
    // The probed cell already shows occupied (a key) vs empty (grey) vs
    // tombstone (×), and a side note would be occluded by the adjacent
    // cell in a contiguous array — so the probe state rides the caption.
    let hint = if st.state == "tombstone" {
      " (skip ×)"
    } else if st.state == "empty" {
      " (free)"
    } else if st.state == "same" { " (match)" } else { "" }
    let cap = if i == 0 {
      [h(#key) = #hb.index]
    } else { [probe #(i + 1)#hint] }
    specs.push((
      table: _to-table(hm, orientation, hash-box: hb),
      build: (op, _rt) => {
        let s = core.blank-snapshot()
        for idx in snap-probed {
          s = (s.style-node)(hm-draw.cell-key(idx), stroke: op.search-stroke)
        }
        s
      },
      caption: cap,
      step: (kind: "probe", probe: st.probe, index: st.index, state: st.state),
      alt: "Probe "
        + str(i + 1)
        + " lands on slot "
        + str(st.index)
        + " ("
        + st.state
        + ").",
    ))
  }
  (specs: specs, walk: w, hb: hb)
}

#let _insert-specs(hm, key, value, label, orientation) = {
  let wf = _walk-frames(hm, key, orientation, "insert")
  let specs = wf.specs
  let w = wf.walk
  let hb = wf.hb

  if hm.strategy == "chaining" {
    let bucket = w.bucket
    let hm2 = (hm.insert)(key, value: value, label: label)
    if w.kind == "found" {
      let d = w.depth
      specs.push((
        table: _to-table(hm2, orientation, hash-box: hb),
        build: (op, _rt) => _styled(
          hm-draw.entry-key(bucket, d),
          fill: op.success-fill,
          stroke: op.settled-stroke,
        ),
        caption: [update #key],
        step: (kind: "update", bucket: bucket, depth: d),
        alt: "Key " + str(key) + " already present in bucket " + str(bucket) + "; value updated in place.",
      ))
    } else {
      let d = hm.slots.at(bucket).len()
      specs.push((
        table: _to-table(hm2, orientation, hash-box: hb),
        build: (op, _rt) => {
          let s = _styled(
            hm-draw.entry-key(bucket, d),
            fill: op.success-fill,
            stroke: op.settled-stroke,
          )
          (s.style-edge)(hm-draw.entry-key(bucket, d), stroke: op.success-stroke)
        },
        caption: [insert #key],
        step: (kind: "insert", bucket: bucket, depth: d),
        alt: "Inserted " + str(key) + " at the tail of bucket " + str(bucket) + ".",
      ))
    }
    return specs
  }

  // Open addressing.
  if w.kind == "exhausted" and w.first-tomb == none {
    let probed = w.steps.map(st => st.index)
    specs.push((
      table: _to-table(hm, orientation, hash-box: hb),
      build: (op, _rt) => {
        let s = core.blank-snapshot()
        for idx in probed {
          s = (s.style-node)(hm-draw.cell-key(idx), stroke: op.danger-stroke)
        }
        s
      },
      caption: [table full],
      step: (kind: "full"),
      alt: "Probe sequence exhausted with no free slot; " + str(key) + " cannot be inserted (table full for this key).",
    ))
    return specs
  }
  let target = if w.kind == "found" {
    w.index
  } else if w.first-tomb != none { w.first-tomb } else { w.index }
  let hm2 = (hm.insert)(key, value: value, label: label)
  let verb = if w.kind == "found" { "update" } else { "insert" }
  specs.push((
    table: _to-table(hm2, orientation, hash-box: hb),
    build: (op, _rt) => _styled(
      hm-draw.cell-key(target),
      fill: op.success-fill,
      stroke: op.settled-stroke,
    ),
    caption: [#verb #key → slot #target],
    step: (kind: "insert", index: target, updated: w.kind == "found"),
    alt: (if w.kind == "found" { "Updated " } else { "Inserted " })
      + str(key)
      + " at slot "
      + str(target)
      + ".",
  ))
  specs
}

#let _search-specs(hm, key, orientation) = {
  let wf = _walk-frames(hm, key, orientation, "look up")
  let specs = wf.specs
  let w = wf.walk
  let hb = wf.hb

  if hm.strategy == "chaining" {
    let bucket = w.bucket
    if w.kind == "found" {
      let d = w.depth
      specs.push((
        table: _to-table(hm, orientation, hash-box: hb),
        build: (op, _rt) => _styled(hm-draw.entry-key(bucket, d), stroke: op.settled-stroke),
        caption: [found #key],
        step: (kind: "found", bucket: bucket, depth: d),
        alt: "Found " + str(key) + " at depth " + str(d) + " of bucket " + str(bucket) + ".",
      ))
    } else {
      // Reached the end of the chain without a match. Highlight a phantom
      // "null" cell past the last entry (the slot the search fell off the end
      // into) rather than the bucket header — the header held no key, so a red
      // ring on it reads as if the bucket itself were the miss.
      let depth = hm.slots.at(bucket).len()
      specs.push((
        table: _to-table(hm, orientation, hash-box: hb, phantom: (bucket: bucket, depth: depth)),
        build: (op, _rt) => _styled(hm-draw.entry-key(bucket, depth), stroke: op.danger-stroke),
        caption: [#key not found],
        step: (kind: "not-found", bucket: bucket),
        alt: str(key) + " not found; reached the end of bucket " + str(bucket) + "'s chain.",
      ))
    }
    return specs
  }

  if w.kind == "found" {
    let idx = w.index
    specs.push((
      table: _to-table(hm, orientation, hash-box: hb),
      build: (op, _rt) => _styled(hm-draw.cell-key(idx), stroke: op.settled-stroke),
      caption: [found #key],
      step: (kind: "found", index: idx),
      alt: "Found " + str(key) + " at slot " + str(idx) + ".",
    ))
  } else {
    let idx = if w.kind == "empty" { w.index } else { none }
    specs.push((
      table: _to-table(hm, orientation, hash-box: hb),
      build: (op, _rt) => if idx == none {
        core.blank-snapshot()
      } else { _styled(hm-draw.cell-key(idx), stroke: op.danger-stroke) },
      caption: [#key not found],
      step: (kind: "not-found", index: idx),
      alt: str(key)
        + " not found"
        + (if idx != none {
          " — reached empty slot " + str(idx)
        } else { " — probe sequence exhausted" })
        + ".",
    ))
  }
  specs
}

#let _delete-specs(hm, key, orientation, tombstone: true) = {
  let wf = _walk-frames(hm, key, orientation, "delete")
  let specs = wf.specs
  let w = wf.walk
  let hb = wf.hb

  if hm.strategy == "chaining" {
    let bucket = w.bucket
    if w.kind != "found" {
      // Fell off the end of the chain — mark the phantom "null" cell past the
      // last entry, mirroring the failed lookup (see `_search-specs`).
      let depth = hm.slots.at(bucket).len()
      specs.push((
        table: _to-table(hm, orientation, hash-box: hb, phantom: (bucket: bucket, depth: depth)),
        build: (op, _rt) => _styled(hm-draw.entry-key(bucket, depth), stroke: op.danger-stroke),
        caption: [#key not found],
        step: (kind: "not-found", bucket: bucket),
        alt: str(key) + " not found in bucket " + str(bucket) + "; nothing to delete.",
      ))
      return specs
    }
    let d = w.depth
    specs.push((
      table: _to-table(hm, orientation, hash-box: hb),
      build: (op, _rt) => _styled(hm-draw.entry-key(bucket, d), stroke: op.danger-stroke),
      caption: [remove #key],
      step: (kind: "remove", bucket: bucket, depth: d),
      alt: "Removing " + str(key) + " from bucket " + str(bucket) + ".",
    ))
    let hm2 = (hm.delete)(key)
    specs.push((
      table: _to-table(hm2, orientation),
      build: (_op, _rt) => core.blank-snapshot(),
      caption: [deleted #key],
      step: (kind: "deleted", bucket: bucket),
      alt: "Deleted " + str(key) + "; bucket " + str(bucket) + " re-linked.",
    ))
    return specs
  }

  // Open addressing: a deleted slot becomes a tombstone (not empty).
  if w.kind != "found" {
    let idx = if w.kind == "empty" { w.index } else { none }
    specs.push((
      table: _to-table(hm, orientation, hash-box: hb),
      build: (op, _rt) => if idx == none {
        core.blank-snapshot()
      } else { _styled(hm-draw.cell-key(idx), stroke: op.danger-stroke) },
      caption: [#key not found],
      step: (kind: "not-found", index: idx),
      alt: str(key) + " not found; nothing to delete.",
    ))
    return specs
  }
  let idx = w.index
  specs.push((
    table: _to-table(hm, orientation, hash-box: hb),
    build: (op, _rt) => _styled(hm-draw.cell-key(idx), stroke: op.danger-stroke),
    caption: [remove #key],
    step: (kind: "remove", index: idx),
    alt: "Removing " + str(key) + " from slot " + str(idx) + ".",
  ))
  let hm2 = (hm.delete)(key, tombstone: tombstone)
  if tombstone {
    specs.push((
      table: _to-table(hm2, orientation),
      build: (op, _rt) => _styled(hm-draw.cell-key(idx), stroke: op.danger-stroke),
      caption: [tombstone at #idx],
      step: (kind: "tombstone", index: idx),
      alt: "Slot " + str(idx) + " marked as a tombstone (×), so probes for other keys still pass through it.",
    ))
  } else {
    // Naive deletion: the slot is blanked to empty. Ring it in danger to
    // flag the hazard — a later probe that reaches this now-empty slot
    // stops early, so any key stored beyond it becomes unreachable.
    specs.push((
      table: _to-table(hm2, orientation),
      build: (op, _rt) => _styled(hm-draw.cell-key(idx), stroke: op.danger-stroke),
      caption: [clear slot #idx],
      step: (kind: "cleared", index: idx),
      alt: "Slot "
        + str(idx)
        + " cleared to empty (no tombstone). A later probe that reaches it now stops early, so keys stored beyond it in a probe sequence become unreachable — this is the deletion bug tombstones prevent.",
    ))
  }
  specs
}

// Resize / rehash: allocate a `new-cap`-slot array and replay every live
// entry (old-slot order) through the new hash. One frame per entry, each
// showing the hash box under the new capacity and the entry landing in
// the growing new array. Frame `step.kind`s: "init", "new-array",
// "rehash", "done".
#let _resize-specs(hm, new-cap, orientation) = {
  let live = _live-entries(hm)
  let base-alt = (
    "Hash table: "
      + (hm.describe)()
      + ". Resizing from "
      + str(hm.capacity)
      + " to "
      + str(new-cap)
      + " slots and rehashing "
      + str(live.len())
      + " entries."
  )
  let specs = (
    (
      table: _to-table(hm, orientation),
      build: (_op, _rt) => core.blank-snapshot(),
      caption: [before (m = #hm.capacity)],
      step: (kind: "init"),
      alt: base-alt,
    ),
  )
  // A fresh empty table at the new capacity (mirrors `resize`).
  let empty-slots = if hm.strategy == "chaining" {
    range(new-cap).map(_ => ())
  } else { range(new-cap).map(_ => none) }
  let acc = (hm.meta.cls.new)(
    capacity: new-cap,
    strategy: hm.strategy,
    hash: hm.hash,
    hash-repr: hm.hash-repr,
    hash2: hm.hash2,
    hash2-repr: hm.hash2-repr,
    slots: empty-slots,
  )
  specs.push((
    table: _to-table(acc, orientation),
    build: (_op, _rt) => core.blank-snapshot(),
    caption: [new array (m = #new-cap)],
    step: (kind: "new-array", capacity: new-cap),
    alt: "Allocated a new array of " + str(new-cap) + " slots; rehashing each entry into it.",
  ))
  for e in live {
    let acc2 = (acc.insert)(e.key, value: e.value, label: e.label)
    let hb = _hash-box(acc2, e.key)
    let style-key = if hm.strategy == "chaining" {
      let w = _chain-walk(acc2, e.key)
      hm-draw.entry-key(w.bucket, w.depth)
    } else {
      let w = _oa-walk(acc2, e.key)
      hm-draw.cell-key(w.index)
    }
    let sk = style-key
    let e-lbl = e.label
    specs.push((
      table: _to-table(acc2, orientation, hash-box: hb),
      build: (op, _rt) => _styled(sk, fill: op.success-fill, stroke: op.settled-stroke),
      caption: [rehash #e-lbl],
      step: (kind: "rehash", key: e.key, index: hb.index),
      alt: "Rehashed " + e-lbl + " under the new capacity.",
    ))
    acc = acc2
  }
  specs.push((
    table: _to-table(acc, orientation),
    build: (_op, _rt) => core.blank-snapshot(),
    caption: [rehashed],
    step: (kind: "done", capacity: new-cap),
    alt: "Resize complete: " + (acc.describe)() + ".",
  ))
  specs
}

// ===================================================================
// HashMap class
// ===================================================================

#let _strategies = ("chaining", "linear", "quadratic", "double")

/// Typsy class representing a hash table with a pluggable hash function
/// and one of four collision strategies (#raw("\"chaining\""),
/// #raw("\"linear\""), #raw("\"quadratic\""), #raw("\"double\"")). Build
/// one via the
/// @@hashmap() factory. Pure operations (#raw("hash-of"),
/// #raw("probe-seq"), #raw("insert"), #raw("contains"), #raw("get"),
/// #raw("delete"), #raw("resize"), #raw("load-factor"),
/// #raw("describe"), #raw("check-invariants")) return values or new
/// #raw("HashMap")s; the #raw("*-display") methods return
/// #raw("Array(Frame)").
#let HashMap = class(
  name: "HashMap",
  fields: (
    capacity: Int,
    strategy: Str,
    // The hash function wrapped in a singleton dict `(fn: (key, m) =>
    // int)` so typsy doesn't self-inject on the function-typed field
    // (same trick as `Frame._builder` / `Renderer.draw`).
    hash: Dictionary(..Any),
    hash-repr: Str,
    // The second hash function (step size) for double hashing, same
    // singleton-dict wrapping. Unused by the other strategies but always
    // present (typsy classes have fixed fields).
    hash2: Dictionary(..Any),
    hash2-repr: Str,
    // length == capacity; element type depends on strategy (see header).
    slots: Array(..Any),
  ),
  methods: (
    is-chaining: (self) => self.strategy == "chaining",
    // The bucket index `key` hashes to.
    hash-of: (self, key) => _hash-index(self, key),
    // The probe sequence (open addressing) or `(bucket,)` (chaining).
    probe-seq: (self, key) => _probe-seq(self, key),
    // Number of live entries (excludes empties and tombstones).
    size: (self) => _live-entries(self).len(),
    // Load factor α = n / m.
    load-factor: (self) => _live-entries(self).len() / self.capacity,
    contains: (self, key) => {
      if self.strategy == "chaining" {
        _chain-walk(self, key).kind == "found"
      } else {
        _oa-walk(self, key).kind == "found"
      }
    },
    // The value stored for `key`, or `default` when absent.
    get: (self, key, default: none) => {
      if self.strategy == "chaining" {
        let w = _chain-walk(self, key)
        if w.kind == "found" {
          self.slots.at(w.bucket).at(w.depth).value
        } else { default }
      } else {
        let w = _oa-walk(self, key)
        if w.kind == "found" { self.slots.at(w.index).value } else { default }
      }
    },
    // Insert (or update) `key` with `value`. Existing keys are updated in
    // place (map semantics). Panics only if an open-addressing table is
    // full and the key can't be placed.
    insert: (self, key, value: none, label: auto) => {
      let entry = _make-entry(key, value, label)
      if self.strategy == "chaining" {
        let w = _chain-walk(self, key)
        let chain = self.slots.at(w.bucket)
        if w.kind == "found" {
          chain.at(w.depth) = entry
        } else {
          chain.push(entry)
        }
        let slots = self.slots
        slots.at(w.bucket) = chain
        _rebuild(self, slots)
      } else {
        let w = _oa-walk(self, key)
        let slots = self.slots
        if w.kind == "found" {
          slots.at(w.index) = entry
        } else if w.kind == "empty" {
          let target = if w.first-tomb != none { w.first-tomb } else { w.index }
          slots.at(target) = entry
        } else {
          // exhausted: reuse the first tombstone, else the table is full.
          if w.first-tomb != none {
            slots.at(w.first-tomb) = entry
          } else {
            panic(
              "insert: hash table is full; cannot place key " + repr(key) + ".",
            )
          }
        }
        _rebuild(self, slots)
      }
    },
    // Delete `key`. Chaining unlinks the entry; open addressing writes a
    // tombstone (never a plain empty, so later probes still traverse it).
    // A no-op if the key is absent.
    //
    // `tombstone: false` is the *naive* open-addressing deletion: it
    // clears the slot to empty instead of leaving a tombstone. That is
    // deliberately buggy — a later search whose probe sequence runs
    // through the cleared slot now stops early and fails to find keys
    // stored beyond it. It exists to *teach* that failure; real code
    // should keep the default. The flag is a no-op for chaining, which
    // has no tombstones.
    delete: (self, key, tombstone: true) => {
      if self.strategy == "chaining" {
        let w = _chain-walk(self, key)
        if w.kind != "found" { return self }
        let chain = self.slots.at(w.bucket)
        chain.remove(w.depth)
        let slots = self.slots
        slots.at(w.bucket) = chain
        _rebuild(self, slots)
      } else {
        let w = _oa-walk(self, key)
        if w.kind != "found" { return self }
        let slots = self.slots
        slots.at(w.index) = if tombstone { (tombstone: true) } else { none }
        _rebuild(self, slots)
      }
    },
    // Grow (or shrink) to `new-cap` and rehash every live entry through
    // the new capacity, in slot order. Tombstones are dropped.
    resize: (self, new-cap) => {
      assert(new-cap > 0, message: "resize: capacity must be positive.")
      let empty = if self.strategy == "chaining" {
        range(new-cap).map(_ => ())
      } else { range(new-cap).map(_ => none) }
      let fresh = (self.meta.cls.new)(
        capacity: new-cap,
        strategy: self.strategy,
        hash: self.hash,
        hash-repr: self.hash-repr,
        hash2: self.hash2,
        hash2-repr: self.hash2-repr,
        slots: empty,
      )
      for e in _live-entries(self) {
        fresh = (fresh.insert)(e.key, value: e.value, label: e.label)
      }
      fresh
    },
    describe: (self) => {
      let n = _live-entries(self).len()
      let strat = if self.strategy == "chaining" {
        "separate chaining"
      } else if self.strategy == "linear" {
        "linear probing"
      } else if self.strategy == "quadratic" {
        "quadratic probing"
      } else { "double hashing" }
      let contents = _live-entries(self)
        .map(e => {
          if e.value == none { e.label } else { e.label + "=" + repr(e.value) }
        })
        .join(", ")
      (
        "hash table ("
          + strat
          + ", "
          + str(self.capacity)
          + " slots, "
          + str(n)
          + " entries"
          + (if contents == none { "" } else { ": " + contents })
          + ")"
      )
    },
    // Structural invariants: capacity positive, strategy recognised,
    // slots length matches capacity, and each slot has the right shape
    // for the strategy. Returns true or panics with the first violation.
    check-invariants: (self) => {
      assert(self.capacity > 0, message: "check-invariants: capacity must be positive.")
      assert(
        _strategies.contains(self.strategy),
        message: "check-invariants: unknown strategy '" + self.strategy + "'.",
      )
      assert(
        self.slots.len() == self.capacity,
        message: "check-invariants: slots length "
          + str(self.slots.len())
          + " != capacity "
          + str(self.capacity)
          + ".",
      )
      for slot in self.slots {
        if self.strategy == "chaining" {
          assert(
            type(slot) == array,
            message: "check-invariants: chaining slot must be an array.",
          )
        } else {
          assert(
            slot == none or type(slot) == dictionary,
            message: "check-invariants: open-addressing slot must be none or a dict.",
          )
        }
      }
      true
    },
    // The positioned-table dict the renderer consumes — the hash-map
    // counterpart to `Graph.positioned`. Feed it to `draw-hashmap` (for
    // hand-composed cetz canvases) or `make-hashmap-renderer` (for the
    // `Op` command stream). `orientation` picks the layout; `hash-box`,
    // when set to `(key:, expr:, index:[, expr2:, step:])`, draws the
    // hash-box overlay. `cell-width` (`auto` by default) pins a fixed
    // array-cell width in cetz units; `auto` fits the widest label.
    positioned: (self, orientation: "horizontal", hash-box: none, cell-width: auto) => {
      _to-table(self, orientation, hash-box: hash-box, cell-width: cell-width)
    },
    // -----------------------------------------------------------------
    // Display methods
    // -----------------------------------------------------------------
    // Returns a one-frame Frame array — the static table, no operation
    // styling. `orientation` is "horizontal" (default) or "vertical".
    // `theme:` overrides the hash-map palette; `render-theme:` the
    // structural render theme. `cell-width` sizes the array cells:
    // "fit" (default) grows them to the widest label, `auto` keeps the
    // fixed historical footprint, or a number pins an exact width.
    display: (self, orientation: "horizontal", theme: auto, render-theme: auto, cell-width: "fit") => {
      let spec = (
        table: _to-table(self, orientation),
        build: (_op, _rt) => core.blank-snapshot(),
        caption: none,
        step: (kind: "static"),
        alt: (self.describe)() + ".",
      )
      _hm-make-frames-multi(
        (spec,),
        _resolve-hashmap-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
        cell-width: cell-width,
      )
    },
    // Animate inserting `key` (with optional `value`). Shows the hash
    // box, the probe/chain walk, and the landing. Frame `step.kind`s:
    // "init", "hash", "probe" / "compare", "insert" / "update", "full".
    // `cell-width` sizes the array cells (see `display`).
    insert-display: (
      self,
      key,
      value: none,
      label: auto,
      orientation: "horizontal",
      theme: auto,
      render-theme: auto,
      cell-width: "fit",
    ) => {
      _hm-make-frames-multi(
        _insert-specs(self, key, value, label, orientation),
        _resolve-hashmap-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
        cell-width: cell-width,
      )
    },
    // Animate looking `key` up. Same walk as insert, ending in a
    // settled-stroke ring on a hit or a danger-stroke miss frame. Open
    // addressing stops at the first empty slot; chaining at the chain's
    // end. Frame `step.kind`s: "init", "hash"/"probe"/"compare",
    // "found", "not-found".
    search-display: (self, key, orientation: "horizontal", theme: auto, render-theme: auto, cell-width: "fit") => {
      _hm-make-frames-multi(
        _search-specs(self, key, orientation),
        _resolve-hashmap-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
        cell-width: cell-width,
      )
    },
    // Animate deleting `key`. Walks to the key, then removes it: chaining
    // unlinks the entry; open addressing writes a tombstone (×) so later
    // probes still traverse the slot. `tombstone: false` is the naive
    // open-addressing deletion that clears the slot to empty instead — a
    // deliberately buggy variant for teaching why tombstones are needed
    // (a later search then stops early at the cleared slot); it's a no-op
    // for chaining. Frame `step.kind`s: "init", walk kinds, "remove",
    // "deleted"/"tombstone"/"cleared", or "not-found".
    delete-display: (self, key, orientation: "horizontal", tombstone: true, theme: auto, render-theme: auto, cell-width: "fit") => {
      _hm-make-frames-multi(
        _delete-specs(self, key, orientation, tombstone: tombstone),
        _resolve-hashmap-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
        cell-width: cell-width,
      )
    },
    // Animate growing (or shrinking) to `new-cap` and rehashing every
    // live entry through the new capacity, one entry per frame. Frame
    // `step.kind`s: "init", "new-array", "rehash", "done".
    resize-display: (self, new-cap, orientation: "horizontal", theme: auto, render-theme: auto, cell-width: "fit") => {
      assert(new-cap > 0, message: "resize-display: capacity must be positive.")
      _hm-make-frames-multi(
        _resize-specs(self, new-cap, orientation),
        _resolve-hashmap-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
        cell-width: cell-width,
      )
    },
  ),
)

// ===================================================================
// Factory
// ===================================================================

/// Build a @@HashMap with #raw("capacity") slots, a collision
/// #raw("strategy"), a pluggable #raw("hash") function
/// #raw("(key, m) => index"), and a display #raw("hash-repr") string
/// (with #raw("k") = key and #raw("m") = capacity, e.g.
/// #raw("\"k mod m\"")). For the #raw("\"double\"") strategy a second
/// hash #raw("hash2") supplies the probe step size (with its own
/// #raw("hash2-repr")); it is ignored by the other strategies.
/// Optionally seed it by inserting each item in #raw("entries") (a bare
/// key, or a #raw("(key, value)") pair).
///
/// -> HashMap
#let hashmap(
  /// Number of array slots (m). Must be positive.
  /// -> int
  capacity,
  /// Collision resolution: #raw("\"chaining\""), #raw("\"linear\""),
  /// #raw("\"quadratic\""), or #raw("\"double\"").
  /// -> str
  strategy: "chaining",
  /// The hash function #raw("(key, m) => index"). Default is the
  /// division method #raw("k mod m").
  /// -> function
  hash: (k, m) => calc.rem(k, m),
  /// Display form of the hash, shown in the animation's hash box.
  /// #raw("k") and #raw("m") are substituted with the key and capacity.
  /// -> str
  hash-repr: "k mod m",
  /// The second hash function #raw("(key, m) => step") used by the
  /// #raw("\"double\"") strategy to size each probe step. The step is
  /// normalized into #raw("[1, m)") (a zero step becomes #raw("1")).
  /// Default #raw("1 + (k mod (m - 1))"), which is nonzero and — when
  /// #raw("m") is prime — coprime to #raw("m"), so the probe sequence
  /// visits every slot.
  /// -> function
  hash2: (k, m) => 1 + calc.rem(k, m - 1),
  /// Display form of the second hash, shown on the hash box's second
  /// line for double hashing.
  /// -> str
  hash2-repr: "1 + (k mod (m - 1))",
  /// Items to seed the table with — each a bare key or a
  /// #raw("(key, value)") pair, inserted in order.
  /// -> array
  entries: (),
) = {
  assert(capacity > 0, message: "hashmap: capacity must be positive.")
  assert(
    _strategies.contains(strategy),
    message: "hashmap: strategy must be one of " + _strategies.join(", ") + ".",
  )
  let slots = if strategy == "chaining" {
    range(capacity).map(_ => ())
  } else { range(capacity).map(_ => none) }
  let h = (HashMap.new)(
    capacity: capacity,
    strategy: strategy,
    hash: (fn: hash),
    hash-repr: hash-repr,
    hash2: (fn: hash2),
    hash2-repr: hash2-repr,
    slots: slots,
  )
  for e in entries {
    if type(e) == array {
      h = (h.insert)(e.at(0), value: e.at(1, default: none))
    } else {
      h = (h.insert)(e)
    }
  }
  h
}
