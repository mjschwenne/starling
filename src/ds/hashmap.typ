// Hash map.
//
// A fixed-length array of `capacity` slots. Keys are placed by a pluggable
// hash function `(key, m) => index`; collisions are resolved by one of four
// strategies:
//
//   "chaining"   each slot holds a linked list (chain) of entries
//   "linear"     open addressing, probe (h + i)         mod m
//   "quadratic"  open addressing, probe (h + i*i)       mod m
//   "double"     open addressing, probe (h + i*h2(k))   mod m
//
// Slot representation follows from that: a chaining slot is an array of entry
// dicts `(key, label, value)`; an open-addressing slot is `none`, an entry, or
// `(tombstone: true)`. A tombstone marks a deleted open-addressing slot —
// search must step over it (an empty slot, by contrast, ends the probe) and
// insert may reuse the first one it passes.
//
// The teaching-critical semantics, all of which the animations show:
// insert UPDATES an existing key in place; open-addressing insert reuses the
// first tombstone it passes, else the first empty, else panics (which
// quadratic probing can hit while slots remain); search stops at the first
// empty but steps over tombstones; delete writes a tombstone (open addressing)
// or unlinks (chaining). Two deliberately-buggy variants exist to teach why:
// `delete(.., tombstone: false)` clears the slot instead, and
// `resize(.., rehash: false)` copies entries to their old indices.
//
// step.kind vocabulary
// --------------------
//   static                     the one frame of `display`
//   init                       the opening frame of every animation
//   hash                       the hash box appears (chaining)
//   probe / compare            one open-addressing probe / one chain entry
//   insert / update            the key landed, or replaced an existing one
//   full                       the probe sequence ran out with nowhere to put it
//   found / not-found          how a lookup ended; `step.reason` says why a
//                              miss missed ("empty" / "exhausted" / "chain-end")
//   remove                     the entry marked for deletion
//   deleted / tombstone / cleared      how the slot was left afterwards
//   new-array / rehash / copy  the three phases of a resize
//   settled                    terminal success of a mutation
// The final frame of every display carries `step.result` — the map the
// operation produced (the unchanged input, for a search).

#import "../core/draw-util.typ": anchor
#import "../core/frame.typ": make-frames, make-renderer
#import "../core/snapshot.typ": blank-snapshot, with-edge, with-node
#import "../core/style.typ": assert-any-of
#import "../core/text.typ": alt-describe, alt-intro
#import "../draw/hashmap.typ": cell-key, draw-hashmap, entry-key

#let _DS = "Hash table"

/// The collision strategies this module understands.
#let strategies = ("chaining", "linear", "quadratic", "double")

// ===================================================================
// Hashing
// ===================================================================

// The bucket index for `key`. Defensively wrapped into [0, m) even if the
// user's hash returns out of range or negative.
#let _hash-index(hm, key) = {
  let r = calc.rem((hm.hash)(key, hm.capacity), hm.capacity)
  if r < 0 { r + hm.capacity } else { r }
}

// The step size for double hashing: the second hash normalized into [1, m). A
// zero step would stall the probe, so it becomes 1.
#let _hash2-step(hm, key) = {
  let s = calc.rem((hm.hash2)(key, hm.capacity), hm.capacity)
  if s < 0 { s = s + hm.capacity }
  if s == 0 { 1 } else { s }
}

/// The bucket index `key` hashes to.
/// -> int
#let hash-of(hm, key) = _hash-index(hm, key)

/// The probe sequence for `key`: `capacity` indices in probe order for open
/// addressing, or the single relevant bucket for chaining.
/// -> array
#let probe-seq(hm, key) = {
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

// Substitute the key for `k` and the capacity for `m` in a hash-repr string.
// The word-boundary regex leaves `mod` intact; the doubled backslash carries a
// literal `\b` into the regex engine (a single one is a backspace character
// and never matches).
#let _sub-repr(rep, key, m) = (
  rep.replace(regex("\\bk\\b"), str(key)).replace(regex("\\bm\\b"), str(m))
)

// ===================================================================
// Walks — shared by the pure operations and the animations
// ===================================================================

#let _make-entry(key, value, label) = (
  key: key,
  label: if label == auto { str(key) } else { label },
  value: value,
)

#let _classify(slot, key) = if slot == none {
  "empty"
} else if slot.at("tombstone", default: false) {
  "tombstone"
} else if slot.key == key { "same" } else { "other" }

// Walk the open-addressing probe sequence for `key`:
//   steps      every slot visited, as (probe, index, state)
//   kind       "found" | "empty" (hit a free slot) | "exhausted"
//   index      the landing index, for "found" / "empty"
//   first-tomb the first tombstone passed, or none
// Search stops at the first empty; insert reuses `first-tomb` when set.
#let _oa-walk(hm, key) = {
  let first-tomb = none
  let steps = ()
  for (i, idx) in probe-seq(hm, key).enumerate() {
    let state = _classify(hm.slots.at(idx), key)
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

// Walk the chain at `key`'s bucket: every entry compared, then "found" (with
// its depth) or "absent" (depth = the chain length, i.e. one past the tail).
#let _chain-walk(hm, key) = {
  let idx = _hash-index(hm, key)
  let chain = hm.slots.at(idx)
  let steps = ()
  for (j, entry) in chain.enumerate() {
    let same = entry.key == key
    steps.push((depth: j, index: idx, same: same))
    if same { return (bucket: idx, steps: steps, kind: "found", depth: j) }
  }
  (bucket: idx, steps: steps, kind: "absent", depth: chain.len())
}

// Every live entry in slot order — chains flattened bucket by bucket, or the
// non-empty non-tombstone slots.
#let _live(hm) = {
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

#let _empty-slots(strategy, capacity) = if strategy == "chaining" {
  range(capacity).map(_ => ())
} else { range(capacity).map(_ => none) }

// ===================================================================
// Pure operations
// ===================================================================

/// The number of live entries — empties and tombstones don't count.
/// -> int
#let size(hm) = _live(hm).len()

/// The load factor, n / m.
/// -> float
#let load-factor(hm) = _live(hm).len() / hm.capacity

/// Whether `key` is present.
/// -> bool
#let contains(hm, key) = if hm.strategy == "chaining" {
  _chain-walk(hm, key).kind == "found"
} else { _oa-walk(hm, key).kind == "found" }

/// The value stored for `key`, or `default` when absent.
/// -> any
#let get(hm, key, default: none) = {
  if hm.strategy == "chaining" {
    let w = _chain-walk(hm, key)
    if w.kind == "found" { hm.slots.at(w.bucket).at(w.depth).value } else {
      default
    }
  } else {
    let w = _oa-walk(hm, key)
    if w.kind == "found" { hm.slots.at(w.index).value } else { default }
  }
}

/// Insert (or update) `key`. An existing key is replaced in place — this is a
/// map, not a multiset. Panics only when an open-addressing table is full and
/// the key can't be placed.
/// -> dictionary
#let insert(hm, key, value: none, label: auto) = {
  let entry = _make-entry(key, value, label)
  let slots = hm.slots
  if hm.strategy == "chaining" {
    let w = _chain-walk(hm, key)
    let chain = slots.at(w.bucket)
    if w.kind == "found" { chain.at(w.depth) = entry } else { chain.push(entry) }
    slots.at(w.bucket) = chain
  } else {
    let w = _oa-walk(hm, key)
    if w.kind == "found" {
      slots.at(w.index) = entry
    } else if w.kind == "empty" {
      slots.at(if w.first-tomb != none { w.first-tomb } else { w.index }) = entry
    } else if w.first-tomb != none {
      // Exhausted, but a tombstone earlier in the sequence is reusable.
      slots.at(w.first-tomb) = entry
    } else {
      panic("hashmap.insert: table is full; cannot place key " + repr(key) + ".")
    }
  }
  (..hm, slots: slots)
}

/// Delete `key`. Chaining unlinks the entry; open addressing writes a
/// tombstone, never a plain empty, so later probes still traverse the slot. A
/// no-op when the key is absent.
///
/// `tombstone: false` is the *naive* open-addressing deletion: it clears the
/// slot to empty instead. That is deliberately buggy — a later search whose
/// probe sequence runs through the cleared slot now stops early and fails to
/// find keys stored beyond it. It exists to *teach* that failure. The flag is
/// a no-op for chaining, which has no tombstones.
/// -> dictionary
#let delete(hm, key, tombstone: true) = {
  let slots = hm.slots
  if hm.strategy == "chaining" {
    let w = _chain-walk(hm, key)
    if w.kind != "found" { return hm }
    let chain = slots.at(w.bucket)
    chain.remove(w.depth)
    slots.at(w.bucket) = chain
  } else {
    let w = _oa-walk(hm, key)
    if w.kind != "found" { return hm }
    slots.at(w.index) = if tombstone { (tombstone: true) } else { none }
  }
  (..hm, slots: slots)
}

/// Grow (or shrink) to `new-cap`, rehashing every live entry through the new
/// capacity in slot order. Tombstones are dropped.
///
/// `rehash: false` is the *naive* resize (buggy, for teaching): each live entry
/// is copied verbatim into its OLD index of the larger array, without
/// recomputing the hash. Because `h(k) mod new-cap` then points elsewhere, a
/// later search for a moved key probes the wrong slot and misses — the
/// demonstration of why a real resize must rehash. It requires
/// `new-cap >= capacity`, so the old indices fit.
/// -> dictionary
#let resize(hm, new-cap, rehash: true) = {
  assert(new-cap > 0, message: "hashmap.resize: capacity must be positive.")
  let empty = _empty-slots(hm.strategy, new-cap)
  if not rehash {
    assert(
      new-cap >= hm.capacity,
      message: "hashmap.resize: rehash: false requires new-cap >= capacity "
        + "(the old indices must fit).",
    )
    // Copy live entries to their old index, dropping tombstones and empties —
    // matching the animation, and meaningless anyway once the probe chains
    // they patched are broken by not rehashing.
    let slots = empty
    for (i, slot) in hm.slots.enumerate() {
      if hm.strategy == "chaining" {
        slots.at(i) = slot
      } else if slot != none and not slot.at("tombstone", default: false) {
        slots.at(i) = slot
      }
    }
    return (..hm, capacity: new-cap, slots: slots)
  }
  let fresh = (..hm, capacity: new-cap, slots: empty)
  for e in _live(hm) {
    fresh = insert(fresh, e.key, value: e.value, label: e.label)
  }
  fresh
}

/// A textual rendering of the table, used in alt text.
/// -> str
#let describe(hm) = {
  let strat = (
    chaining: "separate chaining",
    linear: "linear probing",
    quadratic: "quadratic probing",
    double: "double hashing",
  ).at(hm.strategy)
  let contents = _live(hm)
    .map(e => if e.value == none { e.label } else { e.label + "=" + repr(e.value) })
    .join(", ")
  (
    "hash table ("
      + strat
      + ", "
      + str(hm.capacity)
      + " slots, "
      + str(_live(hm).len())
      + " entries"
      + (if contents == none { "" } else { ": " + contents })
      + ")"
  )
}

/// Check the structural invariants: a positive capacity, a known strategy, a
/// slots array the length of the capacity, and every slot shaped for the
/// strategy. Returns `true` or panics naming the first violation.
/// -> bool
#let check-invariants(hm) = {
  assert(hm.capacity > 0, message: "hashmap.check-invariants: capacity must be positive.")
  assert-any-of(hm.strategy, strategies, "hashmap.check-invariants")
  assert(
    hm.slots.len() == hm.capacity,
    message: "hashmap.check-invariants: slots length "
      + str(hm.slots.len())
      + " != capacity "
      + str(hm.capacity)
      + ".",
  )
  for slot in hm.slots {
    if hm.strategy == "chaining" {
      assert(
        type(slot) == array,
        message: "hashmap.check-invariants: a chaining slot must be an array.",
      )
    } else {
      assert(
        slot == none or type(slot) == dictionary,
        message: "hashmap.check-invariants: an open-addressing slot must be "
          + "none or a dict.",
      )
    }
  }
  true
}

// ===================================================================
// Construction
// ===================================================================

/// Build a hash map with `capacity` slots, a collision `strategy`, a pluggable
/// `hash` function `(key, m) => index`, and a display `hash-repr` string in
/// which `k` means the key and `m` the capacity (substituted as whole words —
/// write them standalone, since `"3k"` will not substitute).
///
/// The `"double"` strategy takes a second hash `hash2` for the probe step size
/// (with its own `hash2-repr`); the other strategies ignore it. Seed the table
/// by listing `entries` — each a bare key or a `(key, value)` pair.
///
/// -> dictionary
#let new(
  /// The number of array slots (m). Must be positive.
  /// -> int
  capacity,
  /// `"chaining"`, `"linear"`, `"quadratic"`, or `"double"`.
  /// -> str
  strategy: "chaining",
  /// The hash function `(key, m) => index`; the division method by default.
  /// -> function
  hash: (k, m) => calc.rem(k, m),
  /// The hash's display form, shown in the animation's hash box.
  /// -> str
  hash-repr: "k mod m",
  /// The second hash `(key, m) => step`, sizing each probe step for the
  /// `"double"` strategy. The step is normalized into `[1, m)`. The default is
  /// nonzero and — when `m` is prime — coprime to `m`, so the probe sequence
  /// visits every slot.
  /// -> function
  hash2: (k, m) => 1 + calc.rem(k, m - 1),
  /// The second hash's display form, shown on the hash box's second line.
  /// -> str
  hash2-repr: "1 + (k mod (m - 1))",
  /// Items to seed the table with, inserted in order — each a bare key or a
  /// `(key, value)` pair.
  /// -> array
  entries: (),
) = {
  assert(capacity > 0, message: "hashmap.new: capacity must be positive.")
  assert-any-of(strategy, strategies, "hashmap.new")
  let hm = (
    kind: "hashmap",
    capacity: capacity,
    strategy: strategy,
    hash: hash,
    hash-repr: hash-repr,
    hash2: hash2,
    hash2-repr: hash2-repr,
    slots: _empty-slots(strategy, capacity),
  )
  for e in entries {
    hm = if type(e) == array {
      insert(hm, e.at(0), value: e.at(1, default: none))
    } else { insert(hm, e) }
  }
  hm
}

// ===================================================================
// Rendering
// ===================================================================

// The positioned-table dict the backend consumes. `hm.slots` is already in the
// backend's shape, so this is a thin wrapper; `cells` and `capacity` may be
// overridden for a frame showing a table other than the map's own (the resize
// animation shows the half-filled new array).
#let _table(
  hm,
  orientation,
  cells: auto,
  capacity: auto,
  hash-box: none,
  cell-width: auto,
  phantom: none,
  measure-cells: (),
) = (
  capacity: if capacity == auto { hm.capacity } else { capacity },
  orientation: orientation,
  strategy: hm.strategy,
  cells: if cells == auto { hm.slots } else { cells },
  hash-box: hash-box,
  cell-width: cell-width,
  phantom: phantom,
  measure-cells: measure-cells,
)

/// The positioned-table dict the renderer consumes — the entry point for a
/// hand-composed cetz canvas (`draw-hashmap`) or the `Op` command stream
/// (`make-renderer(positioned(hm), draw-hashmap)`). `orientation` picks the
/// layout; `hash-box`, when set to `(key, expr, index[, expr2, step])`, draws
/// the hash-box overlay.
/// -> dictionary
#let positioned(
  hm,
  orientation: "horizontal",
  hash-box: none,
  cell-width: auto,
) = _table(hm, orientation, hash-box: hash-box, cell-width: cell-width)

/// A `Renderer` over this table, bound to the hash-map backend — the entry
/// point for driving an animation yourself with the `Op` command stream. Pass
/// `sticky: true` when you want each frame's styling to accumulate.
/// -> dictionary
#let renderer(
  hm,
  orientation: "horizontal",
  hash-box: none,
  cell-width: auto,
  node-style: (:),
  edge-style: (:),
  sticky: false,
  theme: (:),
) = make-renderer(
  positioned(hm, orientation: orientation, hash-box: hash-box, cell-width: cell-width),
  draw-hashmap,
  node-style: node-style,
  edge-style: edge-style,
  sticky: sticky,
  theme: theme,
)

// Turn per-frame specs into frames. Each spec carries its own `table` (the
// table mutates frame to frame) plus a `build(theme) => snapshot`.
//
// The one piece of real work here is the global measurement set: the distinct
// entry bodies across ALL frames, threaded onto every frame's table so "fit"
// sizing measures the same superset each time. Without it the cells resize the
// moment a wider key lands and the whole table jumps on the slide.
#let _frames(specs, theme, cell-width) = {
  let seen = (:)
  let measure-cells = ()
  for s in specs {
    for slot in s.table.cells {
      let entries = if s.table.strategy == "chaining" {
        slot
      } else if slot != none and not slot.at("tombstone", default: false) {
        (slot,)
      } else { () }
      for e in entries {
        let k = repr(e)
        if k not in seen {
          seen.insert(k, true)
          measure-cells.push(e)
        }
      }
    }
  }
  make-frames(
    specs.map(s => (
      structure: (..s.table, cell-width: cell-width, measure-cells: measure-cells),
      build: s.build,
      caption: s.caption,
      step: s.step,
      alt: s.alt,
    )),
    draw-hashmap,
    theme: theme,
  )
}

// A blank snapshot with one element styled — keeps the spec builders terse.
#let _styled(key, ..style) = with-node(blank-snapshot(), key, style.named())

// The hash-box overlay for `key`: where the hash sends it before any probing.
// Double hashing also carries the second formula and its step, which the
// backend renders as a second line.
#let _hash-box(hm, key) = {
  let base = (
    key: key,
    expr: _sub-repr(hm.hash-repr, key, hm.capacity),
    index: _hash-index(hm, key),
    expr2: none,
    step: none,
  )
  if hm.strategy == "double" {
    base.expr2 = _sub-repr(hm.hash2-repr, key, hm.capacity)
    base.step = _hash2-step(hm, key)
  }
  base
}

// ===================================================================
// Operation animations
// ===================================================================
//
// Insert, search, and delete share a leading walk phase: the hash box appears,
// then the probe sequence (open addressing) or the bucket's chain (chaining)
// lights up step by step. `_walk-specs` produces those common frames plus the
// walk result; each operation appends its own terminal frame.

// The shared leading frames. `action` only tunes the opening alt text.
// Returns `(specs, walk, hb)`.
#let _walk-specs(hm, key, orientation, action) = {
  let hb = _hash-box(hm, key)
  // The init frame reserves the hash box's footprint with a *ghost* box (same
  // geometry, nothing drawn) so the table doesn't jump on the slide when the
  // real box appears on the next subslide.
  let init = (
    table: _table(hm, orientation, hash-box: (..hb, ghost: true)),
    build: _ => blank-snapshot(),
    caption: none,
    step: (kind: "init"),
    alt: alt-intro(_DS, describe(hm), action + " " + str(key)),
  )

  if hm.strategy == "chaining" {
    let w = _chain-walk(hm, key)
    let bucket = w.bucket
    let specs = (
      init,
      (
        table: _table(hm, orientation, hash-box: hb),
        build: th => _styled(cell-key(bucket), stroke: th.op.attention-stroke),
        caption: [h(#key) = #bucket],
        step: (kind: "hash", bucket: bucket),
        alt: "h(" + str(key) + ") = " + str(bucket) + "; scan bucket " + str(bucket) + ".",
      ),
    )
    let compared = ()
    for st in w.steps {
      compared.push(st.depth)
      // Pin this frame's copy — `compared` keeps growing behind it.
      let so-far = compared
      specs.push((
        table: _table(hm, orientation, hash-box: hb),
        build: th => {
          let s = _styled(cell-key(bucket), stroke: th.op.attention-stroke)
          for d in so-far {
            s = with-node(s, entry-key(bucket, d), (stroke: th.op.search-stroke))
          }
          s
        },
        caption: [compare #hm.slots.at(bucket).at(st.depth).label],
        step: (kind: "compare", bucket: bucket, depth: st.depth, same: st.same),
        alt: "Compare with the entry at depth "
          + str(st.depth)
          + " of bucket "
          + str(bucket)
          + ".",
      ))
    }
    return (specs: specs, walk: w, hb: hb)
  }

  // Open addressing.
  let w = _oa-walk(hm, key)
  let specs = (init,)
  let probed = ()
  for (i, st) in w.steps.enumerate() {
    probed.push(st.index)
    let so-far = probed
    // A probed cell already reads occupied / empty / tombstoned from its own
    // drawing, and a side note would be occluded by the neighbouring cell in a
    // contiguous array — so the probe's state rides the caption instead.
    let hint = if st.state == "tombstone" {
      " (skip ×)"
    } else if st.state == "empty" {
      " (free)"
    } else if st.state == "same" { " (match)" } else { "" }
    specs.push((
      table: _table(hm, orientation, hash-box: hb),
      build: th => {
        let s = blank-snapshot()
        for idx in so-far {
          s = with-node(s, cell-key(idx), (stroke: th.op.search-stroke))
        }
        s
      },
      caption: if i == 0 { [h(#key) = #hb.index] } else { [probe #(i + 1)#hint] },
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
  let (specs, walk: w, hb) = _walk-specs(hm, key, orientation, "insert")
  let after = insert(hm, key, value: value, label: label)

  if hm.strategy == "chaining" {
    let bucket = w.bucket
    if w.kind == "found" {
      let d = w.depth
      specs.push((
        table: _table(after, orientation, hash-box: hb),
        build: th => _styled(
          entry-key(bucket, d),
          fill: th.op.success-fill,
          stroke: th.op.settled-stroke,
        ),
        caption: [update #key],
        step: (kind: "update", bucket: bucket, depth: d, result: after),
        alt: "Key "
          + str(key)
          + " already present in bucket "
          + str(bucket)
          + "; value updated in place.",
      ))
    } else {
      let d = hm.slots.at(bucket).len()
      specs.push((
        table: _table(after, orientation, hash-box: hb),
        build: th => with-edge(
          _styled(
            entry-key(bucket, d),
            fill: th.op.success-fill,
            stroke: th.op.settled-stroke,
          ),
          entry-key(bucket, d),
          (stroke: th.op.success-stroke),
        ),
        caption: [insert #key],
        step: (kind: "insert", bucket: bucket, depth: d, result: after),
        alt: "Inserted " + str(key) + " at the tail of bucket " + str(bucket) + ".",
      ))
    }
    return specs
  }

  // Open addressing. An exhausted probe with no reusable tombstone means the
  // table is full *for this key* — which quadratic probing can hit while slots
  // remain elsewhere.
  if w.kind == "exhausted" and w.first-tomb == none {
    let probed = w.steps.map(st => st.index)
    specs.push((
      table: _table(hm, orientation, hash-box: hb),
      build: th => {
        let s = blank-snapshot()
        for idx in probed { s = with-node(s, cell-key(idx), (stroke: th.op.danger-stroke)) }
        s
      },
      caption: [table full],
      step: (kind: "full", result: hm),
      alt: "Probe sequence exhausted with no free slot; "
        + str(key)
        + " cannot be inserted (the table is full for this key).",
    ))
    return specs
  }
  let target = if w.kind == "found" {
    w.index
  } else if w.first-tomb != none { w.first-tomb } else { w.index }
  let verb = if w.kind == "found" { "update" } else { "insert" }
  specs.push((
    table: _table(after, orientation, hash-box: hb),
    build: th => _styled(
      cell-key(target),
      fill: th.op.success-fill,
      stroke: th.op.settled-stroke,
    ),
    caption: [#verb #key → slot #target],
    step: (
      kind: if w.kind == "found" { "update" } else { "insert" },
      index: target,
      updated: w.kind == "found",
      result: after,
    ),
    alt: (if w.kind == "found" { "Updated " } else { "Inserted " })
      + str(key)
      + " at slot "
      + str(target)
      + ".",
  ))
  specs
}

#let _search-specs(hm, key, orientation) = {
  let (specs, walk: w, hb) = _walk-specs(hm, key, orientation, "look up")

  if hm.strategy == "chaining" {
    let bucket = w.bucket
    if w.kind == "found" {
      let d = w.depth
      specs.push((
        table: _table(hm, orientation, hash-box: hb),
        build: th => _styled(entry-key(bucket, d), stroke: th.op.settled-stroke),
        caption: [found #key],
        step: (kind: "found", bucket: bucket, depth: d, result: hm),
        alt: "Found " + str(key) + " at depth " + str(d) + " of bucket " + str(bucket) + ".",
      ))
    } else {
      // Reached the end of the chain without a match. Ring a phantom "null"
      // cell past the last entry — the slot the search fell off the end into —
      // rather than the bucket header, which holds no key and so reads as if
      // the bucket itself were the miss.
      let depth = hm.slots.at(bucket).len()
      specs.push((
        table: _table(
          hm,
          orientation,
          hash-box: hb,
          phantom: (bucket: bucket, depth: depth),
        ),
        build: th => _styled(entry-key(bucket, depth), stroke: th.op.danger-stroke),
        caption: [#key not found],
        step: (kind: "not-found", bucket: bucket, reason: "chain-end", result: hm),
        alt: str(key)
          + " not found; reached the end of bucket "
          + str(bucket)
          + "'s chain.",
      ))
    }
    return specs
  }

  if w.kind == "found" {
    let idx = w.index
    specs.push((
      table: _table(hm, orientation, hash-box: hb),
      build: th => _styled(cell-key(idx), stroke: th.op.settled-stroke),
      caption: [found #key],
      step: (kind: "found", index: idx, result: hm),
      alt: "Found " + str(key) + " at slot " + str(idx) + ".",
    ))
  } else {
    let idx = if w.kind == "empty" { w.index } else { none }
    specs.push((
      table: _table(hm, orientation, hash-box: hb),
      build: th => if idx == none {
        blank-snapshot()
      } else { _styled(cell-key(idx), stroke: th.op.danger-stroke) },
      caption: [#key not found],
      step: (kind: "not-found", index: idx, reason: w.kind, result: hm),
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

#let _delete-specs(hm, key, orientation, tombstone: true, search: true) = {
  let wf = _walk-specs(hm, key, orientation, "delete")
  let hb = wf.hb
  let w = wf.walk
  // `search: false` drops the walk, keeping only the opening frame.
  let specs = if search { wf.specs } else { (wf.specs.first(),) }

  if hm.strategy == "chaining" {
    let bucket = w.bucket
    if w.kind != "found" {
      // Fell off the end of the chain — mark the phantom "null" cell past the
      // last entry, mirroring the failed lookup.
      let depth = hm.slots.at(bucket).len()
      specs.push((
        table: _table(
          hm,
          orientation,
          hash-box: hb,
          phantom: (bucket: bucket, depth: depth),
        ),
        build: th => _styled(entry-key(bucket, depth), stroke: th.op.danger-stroke),
        caption: [#key not found],
        step: (kind: "not-found", bucket: bucket, reason: "chain-end", result: hm),
        alt: str(key) + " not found in bucket " + str(bucket) + "; nothing to delete.",
      ))
      return specs
    }
    let d = w.depth
    specs.push((
      table: _table(hm, orientation, hash-box: hb),
      build: th => _styled(entry-key(bucket, d), stroke: th.op.danger-stroke),
      caption: [remove #key],
      step: (kind: "remove", bucket: bucket, depth: d),
      alt: "Removing " + str(key) + " from bucket " + str(bucket) + ".",
    ))
    let after = delete(hm, key)
    specs.push((
      // A ghost hash box reserves the walk's footprint, so this clean result
      // frame doesn't jump — the table stays put as the chain shrinks.
      table: _table(after, orientation, hash-box: (..hb, ghost: true)),
      build: _ => blank-snapshot(),
      caption: [deleted #key],
      step: (kind: "deleted", bucket: bucket, result: after),
      alt: "Deleted " + str(key) + "; bucket " + str(bucket) + " re-linked.",
    ))
    return specs
  }

  // Open addressing: a deleted slot becomes a tombstone, not an empty.
  if w.kind != "found" {
    let idx = if w.kind == "empty" { w.index } else { none }
    specs.push((
      table: _table(hm, orientation, hash-box: hb),
      build: th => if idx == none {
        blank-snapshot()
      } else { _styled(cell-key(idx), stroke: th.op.danger-stroke) },
      caption: [#key not found],
      step: (kind: "not-found", index: idx, reason: w.kind, result: hm),
      alt: str(key) + " not found; nothing to delete.",
    ))
    return specs
  }
  let idx = w.index
  specs.push((
    table: _table(hm, orientation, hash-box: hb),
    build: th => _styled(cell-key(idx), stroke: th.op.danger-stroke),
    caption: [remove #key],
    step: (kind: "remove", index: idx),
    alt: "Removing " + str(key) + " from slot " + str(idx) + ".",
  ))
  let after = delete(hm, key, tombstone: tombstone)
  specs.push((
    // The ghost hash box reserves the walk's footprint, so the terminal frame
    // keeps the table in place — matching the `init` ghost and insert's real
    // box.
    table: _table(after, orientation, hash-box: (..hb, ghost: true)),
    build: th => _styled(cell-key(idx), stroke: th.op.danger-stroke),
    caption: if tombstone { [tombstone at #idx] } else { [clear slot #idx] },
    step: (
      kind: if tombstone { "tombstone" } else { "cleared" },
      index: idx,
      result: after,
    ),
    alt: if tombstone {
      (
        "Slot "
          + str(idx)
          + " marked as a tombstone (×), so probes for other keys still pass "
          + "through it."
      )
    } else {
      // Naive deletion: the slot is blanked to empty. It stays ringed in
      // danger to flag the hazard — a later probe that reaches this now-empty
      // slot stops early, so any key stored beyond it becomes unreachable.
      (
        "Slot "
          + str(idx)
          + " cleared to empty (no tombstone). A later probe that reaches it "
          + "now stops early, so keys stored beyond it in a probe sequence "
          + "become unreachable — this is the deletion bug tombstones prevent."
      )
    },
  ))
  specs
}

// The correct resize, one frame per live entry: replay it through the hash
// under the *new* capacity and land it where that says. Returns the frames
// and the map they built.
#let _rehash-specs(acc, live, orientation) = {
  let specs = ()
  let cur = acc
  for e in live {
    let next = insert(cur, e.key, value: e.value, label: e.label)
    let hb = _hash-box(next, e.key)
    let sk = if cur.strategy == "chaining" {
      let w = _chain-walk(next, e.key)
      entry-key(w.bucket, w.depth)
    } else { cell-key(_oa-walk(next, e.key).index) }
    specs.push((
      table: _table(next, orientation, hash-box: hb),
      build: th => _styled(sk, fill: th.op.success-fill, stroke: th.op.settled-stroke),
      caption: [rehash #e.label],
      step: (kind: "rehash", key: e.key, index: hb.index),
      alt: "Rehashed " + e.label + " under the new capacity.",
    ))
    cur = next
  }
  (specs: specs, acc: cur)
}

// The buggy copy: each live entry is placed at its OLD index in the larger
// array. Nothing is hashed, so no hash box is shown.
#let _copy-specs(hm, acc, orientation) = {
  let specs = ()
  let cur = acc
  let copied = acc.slots
  for (i, slot) in hm.slots.enumerate() {
    let entries = if hm.strategy == "chaining" { slot } else if (
      slot != none and not slot.at("tombstone", default: false)
    ) { (slot,) } else { () }
    for (j, entry) in entries.enumerate() {
      copied.at(i) = if hm.strategy == "chaining" {
        copied.at(i) + (entry,)
      } else { entry }
      let next = (..hm, capacity: acc.capacity, slots: copied)
      let sk = if hm.strategy == "chaining" { entry-key(i, j) } else { cell-key(i) }
      let where = if hm.strategy == "chaining" { "bucket" } else { "slot" }
      specs.push((
        table: _table(next, orientation),
        build: th => _styled(sk, fill: th.op.success-fill, stroke: th.op.settled-stroke),
        caption: [copy #entry.label → #where #i],
        step: (kind: "copy", key: entry.key, index: i),
        alt: "Copied "
          + entry.label
          + " into "
          + where
          + " "
          + str(i)
          + " (its old index) without rehashing.",
      ))
      cur = next
    }
  }
  (specs: specs, acc: cur)
}

// Resize: allocate a `new-cap`-slot array and move every live entry into it,
// one frame per entry landing in the growing array.
//
// `rehash: true` replays each live entry (in old-slot order) through the hash
// under the *new* capacity — the correct resize — each frame showing the hash
// box and the recomputed landing slot.
//
// `rehash: false` is the buggy variant for teaching: each entry is copied
// verbatim into its OLD index of the larger array, without recomputing the
// hash. No hash box is shown, because nothing is hashed. Since the array is
// now longer, `h(k) mod new-cap` points somewhere else, so a later
// `search-display` for a moved key probes the wrong slot and misses.
#let _resize-specs(hm, new-cap, orientation, rehash: true) = {
  let live = _live(hm)
  let specs = (
    (
      table: _table(hm, orientation),
      build: _ => blank-snapshot(),
      caption: [before (m = #hm.capacity)],
      step: (kind: "init"),
      alt: alt-intro(
        _DS,
        describe(hm),
        "resize from "
          + str(hm.capacity)
          + " to "
          + str(new-cap)
          + " slots"
          + (if rehash {
            " and rehash " + str(live.len()) + " entries"
          } else {
            (
              ", copying "
                + str(live.len())
                + " entries to their old indices WITHOUT rehashing (buggy)"
            )
          }),
      ),
    ),
  )
  let empty = (..hm, capacity: new-cap, slots: _empty-slots(hm.strategy, new-cap))
  specs.push((
    table: _table(empty, orientation),
    build: _ => blank-snapshot(),
    caption: [new array (m = #new-cap)],
    step: (kind: "new-array", capacity: new-cap),
    alt: "Allocated a new array of "
      + str(new-cap)
      + " slots; "
      + (if rehash { "rehashing" } else { "copying" })
      + " each entry into it.",
  ))

  let moved = if rehash {
    _rehash-specs(empty, live, orientation)
  } else { _copy-specs(hm, empty, orientation) }
  specs += moved.specs

  specs.push((
    table: _table(moved.acc, orientation),
    build: _ => blank-snapshot(),
    caption: if rehash { [rehashed] } else { [copied (not rehashed)] },
    step: (
      kind: "settled",
      capacity: new-cap,
      rehashed: rehash,
      result: moved.acc,
    ),
    alt: (if rehash {
      "Resize complete: "
    } else {
      (
        "Resize complete WITHOUT rehashing — moved keys are now at the wrong "
          + "index for the new capacity, so lookups will miss: "
      )
    })
      + describe(moved.acc)
      + ".",
  ))
  specs
}
}

// ===================================================================
// Displays
// ===================================================================
//
// `cell-width` sizes the array cells: `"fit"` (the default here) grows them to
// the widest label the animation will ever show, `auto` keeps the fixed
// footprint and never measures, and a number pins an exact width. `"fit"` is
// safe as a default only because these always render inside the `slides.typ`
// helpers' `context`, where `measure` is available.

/// The table as a single static frame.
/// -> array
#let display(hm, orientation: "horizontal", theme: (:), cell-width: "fit") = _frames(
  (
    (
      table: _table(hm, orientation),
      build: _ => blank-snapshot(),
      caption: none,
      step: (kind: "static", result: hm),
      alt: alt-describe(_DS, describe(hm)),
    ),
  ),
  theme,
  cell-width,
)

/// Animate inserting `key`: the hash box, the probe or chain walk, and the
/// landing.
/// -> array
#let insert-display(
  hm,
  key,
  value: none,
  label: auto,
  orientation: "horizontal",
  theme: (:),
  cell-width: "fit",
) = _frames(_insert-specs(hm, key, value, label, orientation), theme, cell-width)

/// Animate looking `key` up — the same walk as insert, ending in a settled
/// ring on a hit or a danger ring on a miss. Open addressing stops at the
/// first empty slot; chaining at the chain's end.
/// -> array
#let search-display(
  hm,
  key,
  orientation: "horizontal",
  theme: (:),
  cell-width: "fit",
) = _frames(_search-specs(hm, key, orientation), theme, cell-width)

/// Animate deleting `key`: walk to it, then remove it — chaining unlinks the
/// entry, open addressing writes a tombstone (×) so later probes still
/// traverse the slot. `tombstone: false` animates the naive deletion that
/// clears the slot instead (see `delete`). `search: false` drops the leading
/// walk and cuts straight to the removal.
/// -> array
#let delete-display(
  hm,
  key,
  orientation: "horizontal",
  tombstone: true,
  search: true,
  theme: (:),
  cell-width: "fit",
) = _frames(
  _delete-specs(hm, key, orientation, tombstone: tombstone, search: search),
  theme,
  cell-width,
)

/// Animate growing (or shrinking) to `new-cap`, rehashing every live entry
/// through the new capacity one frame at a time. `rehash: false` animates the
/// naive resize that copies entries to their old indices instead (see
/// `resize`).
/// -> array
#let resize-display(
  hm,
  new-cap,
  rehash: true,
  orientation: "horizontal",
  theme: (:),
  cell-width: "fit",
) = {
  assert(new-cap > 0, message: "hashmap.resize-display: capacity must be positive.")
  assert(
    rehash or new-cap >= hm.capacity,
    message: "hashmap.resize-display: rehash: false requires new-cap >= "
      + "capacity (the old indices must fit).",
  )
  _frames(_resize-specs(hm, new-cap, orientation, rehash: rehash), theme, cell-width)
}
