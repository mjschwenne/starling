// Linear sorts — the `Sort` typsy class, the `sort(..)` factory, and the
// per-DS theme. Rides on the multi-row array draw backend in
// `array-draw.typ` (the analog of how `hashmap.typ` rides on
// `hashmap-draw.typ`).
//
// A `Sort` wraps parallel arrays: `values` (the non-negative integer sort
// keys) and `labels` (each `auto` = show the key, or arbitrary content, so
// an *enumeration* can be sorted by ordinal while displaying names). The
// integer key is what the count array is indexed by; the label only rides
// along for display — the `value`/`label` split shared with BST/B24. It
// animates the two classic linear (distribution) sorts:
//   * counting sort — histogram the values, then place them. Two variants:
//       - "prefix"      (default, stable): count -> cumulative prefix sums
//                        -> place right-to-left into an output array. The
//                        stability radix sort relies on.
//       - "reconstruct" (intro, not stable): histogram, then emit each
//                        value `count[v]` times back into the output.
//   * radix sort (LSD) — one stable prefix counting-sort pass per digit
//     place (ones, tens, ...), keyed on the extracted digit. Radix is a
//     thin wrapper over the counting-sort engine with a digit extractor —
//     one engine, not two.
//
// The count array is indexed directly by value (counting sort, k = max+1)
// or by digit (radix, k = base); no negative/offset handling.

#import "@preview/typsy:0.2.2": *
#import "./anim-core.typ" as core
#import "./array-draw.typ" as arr-draw
#import "./op-theme.typ": _resolve-op-theme-arg

// Resolve a `render-theme:` argument that may be `auto` (read state) or a
// partial dict (merge into default). Mirrors the same helper in the other
// DS modules.
#let _resolve-render-theme-arg(theme) = if theme == auto {
  auto
} else { core._merge-render-theme(theme) }

// ===================================================================
// Per-DS theme — the sort palette
// ===================================================================
//
// Structural colours (node/edge/note fills) come from `render-theme`;
// operation strokes (reading, active bucket, placement) from `op-theme`.
// This per-DS theme carries only what's intrinsic to a sort visualization:
// the empty-cell fill, the small index labels, the row captions, the
// histogram-cell fill, and the radix active-digit colour.

/// Default sort palette. Pass a partial dict to #raw("set-sort-theme(..)")
/// to override individual roles.
#let default-sort-theme = (
  empty-fill: rgb("#f2f2f2"),
  index-fill: rgb("#888888"),
  row-label-fill: black,
  count-fill: rgb("#eef4fb"),
  active-digit-fill: rgb("#2b6cb0"),
  // The connector colour for the "buckets" variant's chains / head pointers.
  chain-stroke: rgb("#8a8f98"),
)

#let _sort-theme-keys = (
  "empty-fill",
  "index-fill",
  "row-label-fill",
  "count-fill",
  "active-digit-fill",
  "chain-stroke",
)

/// Typsy refinement: a dictionary whose keys are a subset of the sort
/// theme keys. Used by #raw("set-sort-theme") and the per-call
/// #raw("theme:") arguments to give early errors on typos.
#let SortTheme = Refine(
  Dictionary(..Any),
  d => d.keys().all(k => _sort-theme-keys.contains(k)),
)

#let _sort-theme-state = state("starling:sort-theme", default-sort-theme)

/// Override one or more sort theme keys for the rest of the document
/// (state-based, scoped by Typst's normal layout flow). Pass a partial
/// dictionary — only the keys you list are changed; the rest stay at their
/// current values. Unknown keys panic.
#let set-sort-theme(theme) = {
  for k in theme.keys() {
    if not _sort-theme-keys.contains(k) {
      panic(
        "set-sort-theme: unknown key '"
          + k
          + "'. Valid keys: "
          + _sort-theme-keys.join(", ")
          + ".",
      )
    }
  }
  _sort-theme-state.update(prev => {
    let next = prev
    for (k, v) in theme.pairs() { next.insert(k, v) }
    next
  })
}

// Merge a partial sort-theme override into `default-sort-theme`, panicking
// on unknown keys. Used by per-call `theme:` arguments.
#let _merge-sort-theme(override) = {
  for k in override.keys() {
    if not _sort-theme-keys.contains(k) {
      panic(
        "sort-theme: unknown key '"
          + k
          + "'. Valid keys: "
          + _sort-theme-keys.join(", ")
          + ".",
      )
    }
  }
  let next = default-sort-theme
  for (k, v) in override.pairs() { next.insert(k, v) }
  next
}

#let _resolve-sort-theme-arg(theme) = if theme == auto {
  auto
} else { _merge-sort-theme(theme) }

// The render-theme dict `draw-array` consumes is the merged render-theme
// plus the sort palette laid on top (the backend reads both key families
// off one dict). Combine them here.
#let _combined-render-theme(rt, st) = {
  let out = rt
  for (k, v) in st.pairs() { out.insert(k, v) }
  out
}

// ===================================================================
// Pure sorting helpers (module-level)
// ===================================================================

// Integer power `b^e` (calc.pow may return a float, which breaks the
// integer `quo`/`rem` used for digit extraction).
#let _ipow(b, e) = {
  let r = 1
  for _ in range(e) { r = r * b }
  r
}

// Number of digits of `maxv` in `base` (at least 1).
#let _num-digits(maxv, base) = {
  if maxv <= 0 { return 1 }
  let d = 0
  let m = maxv
  while m > 0 {
    m = calc.quo(m, base)
    d = d + 1
  }
  d
}

// Default count-array size for counting sort: max value + 1 (indices
// 0..k-1 are the values themselves).
#let _k-of(values) = if values.len() == 0 { 1 } else { calc.max(..values) + 1 }

// Stable counting sort of `values` keyed by `key` into `k` buckets
// (CLRS): histogram, prefix sums, then place right-to-left. Returns the
// sorted array. Shared by the pure ops and — conceptually — the animation.
#let _stable-sort-by(values, key, k) = {
  let n = values.len()
  let counts = range(k).map(_ => 0)
  for v in values { counts.at(key(v)) = counts.at(key(v)) + 1 }
  for b in range(1, k) { counts.at(b) = counts.at(b) + counts.at(b - 1) }
  let out = range(n).map(_ => none)
  for i in range(n - 1, -1, step: -1) {
    let v = values.at(i)
    let b = key(v)
    counts.at(b) = counts.at(b) - 1
    out.at(counts.at(b)) = v
  }
  out
}

#let _counting-sort(values, k) = _stable-sort-by(values, v => v, k)

#let _radix-sort(values, base) = {
  if values.len() == 0 { return () }
  let maxv = calc.max(..values)
  let cur = values
  for d in range(_num-digits(maxv, base)) {
    let place = _ipow(base, d)
    cur = _stable-sort-by(cur, v => calc.rem(calc.quo(v, place), base), base)
  }
  cur
}

// Human-readable name for digit place `d` in `base` (for radix captions).
#let _place-name(d, base) = if base == 10 {
  ("ones", "tens", "hundreds", "thousands", "ten-thousands").at(
    d,
    default: "10^" + str(d),
  )
} else { str(base) + "^" + str(d) }

// ===================================================================
// Elements: the (key, label) pair
// ===================================================================
//
// A `Sort` stores parallel `values` (the non-negative integer sort keys,
// which counting/radix index the count array by) and `labels` (what each
// element displays — `auto` falls back to the key). An "element" bundles
// one of each. The counting/radix engine below operates on elements so a
// label rides along with its key through placement; only the integer
// `.key` ever drives the histogram. Same split as BST/B24's `value`/`label`.

// Build the element array from parallel `values` / `labels`.
#let _elems(values, labels) = range(values.len()).map(i => (
  key: values.at(i),
  label: labels.at(i, default: auto),
))

// String reference to an element for captions / alt text. Uses the label
// only when it is a plain string (arbitrary content can't be spliced into
// a string), else the ordering key — the same rule as `tree-anim`'s
// `_alt-label`.
#let _disp(elem) = if type(elem.label) == str { elem.label } else { str(elem.key) }

// The *visible* display value of an element (for a cell body): the label
// when set, else the integer key. Returns an int (auto label) or content
// (explicit label); `_row` renders either. An int auto-label thus draws
// exactly as the bare-integer path did.
#let _disp-val(elem) = if elem.label == auto { elem.key } else { elem.label }

// ===================================================================
// Display-frame helpers
// ===================================================================

// One row of the positioned table. `values` may contain `none` for empty
// cells; each non-`none` entry is either an int (rendered `[#v]`, the
// count/cumul rows and auto-labelled elements) or already-content (an
// explicit element label, passed through). `subs` (if given) is an array
// of per-cell secondary annotations (the radix active digit). `indices:
// auto` labels cells 0..n-1.
// A cell's rendered value: `none` (empty), an int wrapped to content
// (`[#v]` — count/cumul rows and auto-labelled elements), or already-content
// (an explicit element label) passed through.
#let _cell-value(v) = if v == none { none } else if type(v) == int { [#v] } else { v }

#let _row(id, label, values, indices: auto, kind: "data", subs: none) = (
  id: id,
  label: label,
  kind: kind,
  indices: indices,
  cells: range(values.len()).map(i => (
    value: _cell-value(values.at(i)),
    sub: if subs == none { none } else { subs.at(i, default: none) },
  )),
)

// Build Frame records from per-frame specs (the `_hm-make-frames-multi`
// analog). Each spec carries `table`, `build: (op-theme, render-theme) =>
// Snapshot`, and `caption`/`step`/`alt`. `sort-theme` / `render-theme` are
// pre-resolved (`auto` => read state at render time); op-theme is always
// the `op-arg` the lib helpers resolve and pass in. The render-theme handed
// to the backend and the snapshot builder is the render theme with the sort
// palette merged on top.
#let _sort-make-frames-multi(specs, sort-theme, render-theme, cell-width: "fit") = {
  // Global measurement set: the distinct non-empty cell bodies across ALL
  // frames. Threaded onto every frame's table as `measure-cells` so "fit"
  // sizing measures the same superset each frame — the cell size (and hence
  // the canvas footprint) stays constant even as a running count grows
  // wider than the widest value, so the table never jumps on a slide.
  let seen = (:)
  let measure-cells = ()
  for s in specs {
    for row in s.table.rows {
      // Cells, plus any chain entries (the "buckets" row kind) so they size
      // to the same fit width as the array cells.
      let cells = row.cells + row.at("chains", default: ()).flatten()
      for cell in cells {
        if cell.at("value", default: none) != none {
          let key = repr(cell)
          if key not in seen {
            seen.insert(key, true)
            measure-cells.push(cell)
          }
        }
      }
    }
  }
  specs.map(s => (core.Frame.new)(
    _builder: (
      fn: (op-arg, rt-arg) => {
        let st = if sort-theme == auto {
          _sort-theme-state.get()
        } else { sort-theme }
        let rt = if render-theme == auto { rt-arg } else { render-theme }
        let combined = _combined-render-theme(rt, st)
        let snap = (s.build)(op-arg, combined)
        // Pin the sizing mode for this render (displays fit to content by
        // default — they always render inside the lib helpers' `context`,
        // so `measure` is available).
        let table = s.table
        table.cell-width = cell-width
        table.measure-cells = measure-cells
        core._make-canvas(
          arr-draw._draw-array-backend,
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

// ===================================================================
// Counting sort — the prefix (stable) engine, reused by radix
// ===================================================================
//
// Builds the specs for a single stable prefix-sum counting-sort pass over
// `values`, keyed by `key` into `k` buckets. `subs` (radix: the extracted
// digit per input cell) rides along on the input row all pass. `init-*`
// override the leading frame (radix replaces "init" with a per-pass
// "pass-start"); `with-settled` appends the terminal sorted frame (radix
// sets it only on the last pass). Returns `(specs:, output:)` — the sorted
// order so radix can feed the next pass.
//
// Frame `step.kind`s: "init"/"pass-start", "count", "count-done", "prefix",
// "prefix-done", "place", "settled".
//
// When `separate-counts` is true the histogram and the cumulative prefix
// sums live in two DISTINCT rows ("count" and "cumul") instead of one
// mutated-in-place row: the count row keeps the raw histogram all pass, the
// prefix sums build up in the cumulative row, and placement decrements the
// cumulative row. Pedagogically clearer (the original histogram stays
// visible), at the cost of one extra row. Only meaningful for the prefix
// engine (radix / the reconstruct variant leave it `false`).
#let _counting-prefix-specs(
  elems,
  k,
  key: e => e.key,
  in-label: [input],
  count-label: [count],
  cumul-label: [cumulative],
  out-label: [output],
  subs: none,
  separate-counts: false,
  init-caption: none,
  init-step: (kind: "init"),
  init-alt: none,
  with-settled: true,
) = {
  let n = elems.len()
  let empty-out = range(n).map(_ => none)
  // Empty (all-`none`, muted) count-width row — the cumulative row before it
  // is built, in separate-counts mode.
  let empty-counts = range(k).map(_ => none)
  // The `out` array holds elements (or `none`); render each as its display
  // value so a label rides to its placed slot.
  let out-vals(output) = output.map(e => if e == none { none } else { _disp-val(e) })
  // `cumulative` is ignored unless `separate-counts` (then it becomes the
  // extra row between count and out).
  let mk-table(counts, cumulative, output, arrows) = {
    let rows = (
      _row("in", in-label, elems.map(_disp-val), subs: subs),
      _row("count", count-label, counts, kind: "count"),
    )
    if separate-counts {
      rows.push(_row("cumul", cumul-label, cumulative, kind: "count"))
    }
    rows.push(_row("out", out-label, out-vals(output)))
    (rows: rows, arrows: arrows)
  }

  let specs = ((
    table: mk-table(range(k).map(_ => 0), empty-counts, empty-out, ()),
    build: (_op, _rt) => core.blank-snapshot(),
    caption: init-caption,
    step: init-step,
    alt: if init-alt != none {
      init-alt
    } else {
      "Counting sort. Input: [" + elems.map(_disp).join(", ") + "]."
    },
  ),)

  // --- count phase ---
  let counts = range(k).map(_ => 0)
  for i in range(n) {
    let e = elems.at(i)
    let b = key(e)
    counts.at(b) = counts.at(b) + 1
    let ii = i
    let bb = b
    let ds = _disp(e)
    specs.push((
      table: mk-table(
        counts,
        empty-counts,
        empty-out,
        ((id: "read", from: (row: "in", col: ii), to: (row: "count", col: bb)),),
      ),
      build: (op, _rt) => {
        let s = core.blank-snapshot()
        s = (s.style-node)(arr-draw.array-cell-key("in", ii), stroke: op.search-stroke)
        s = (s.style-node)(arr-draw.array-cell-key("count", bb), stroke: op.attention-stroke)
        s = (s.style-edge)("read", stroke: op.search-stroke)
        s
      },
      caption: "count[" + str(bb) + "] += 1",
      step: (kind: "count", index: ii, bucket: bb),
      alt: "Read input[" + str(ii) + "] = " + ds + "; increment count[" + str(bb) + "].",
    ))
  }
  specs.push((
    table: mk-table(counts, empty-counts, empty-out, ()),
    build: (_op, _rt) => core.blank-snapshot(),
    caption: "histogram complete",
    step: (kind: "count-done"),
    alt: "Histogram complete: count = [" + counts.map(str).join(", ") + "].",
  ))

  // --- separate-counts: build a distinct cumulative row, then place from it
  if separate-counts {
    // cumulative[0] = count[0]; cumulative[b] = cumulative[b-1] + count[b].
    let cumulative = empty-counts
    cumulative.at(0) = counts.at(0)
    let c0 = counts.at(0)
    specs.push((
      table: mk-table(
        counts,
        cumulative,
        empty-out,
        ((id: "carry", from: (row: "count", col: 0), to: (row: "cumul", col: 0)),),
      ),
      build: (op, _rt) => {
        let s = core.blank-snapshot()
        s = (s.style-node)(arr-draw.array-cell-key("count", 0), stroke: op.search-stroke)
        s = (s.style-node)(arr-draw.array-cell-key("cumul", 0), stroke: op.attention-stroke)
        s = (s.style-edge)("carry", stroke: op.search-stroke)
        s
      },
      caption: "cumulative[0] = count[0]",
      step: (kind: "prefix", bucket: 0),
      alt: "Cumulative sum: cumulative[0] = count[0] = " + str(c0) + ".",
    ))
    for b in range(1, k) {
      cumulative.at(b) = cumulative.at(b - 1) + counts.at(b)
      let bb = b
      let cval = cumulative.at(b)
      specs.push((
        table: mk-table(
          counts,
          cumulative,
          empty-out,
          ((id: "carry", from: (row: "count", col: bb), to: (row: "cumul", col: bb)),),
        ),
        build: (op, _rt) => {
          let s = core.blank-snapshot()
          s = (s.style-node)(arr-draw.array-cell-key("count", bb), stroke: op.search-stroke)
          s = (s.style-node)(arr-draw.array-cell-key("cumul", bb - 1), stroke: op.search-stroke)
          s = (s.style-node)(arr-draw.array-cell-key("cumul", bb), stroke: op.attention-stroke)
          s = (s.style-edge)("carry", stroke: op.search-stroke)
          s
        },
        caption: "cumulative[" + str(bb) + "] = cumulative[" + str(bb - 1) + "] + count[" + str(bb) + "]",
        step: (kind: "prefix", bucket: bb),
        alt: "Cumulative sum: cumulative[" + str(bb) + "] becomes " + str(cval) + " (an end position).",
      ))
    }
    specs.push((
      table: mk-table(counts, cumulative, empty-out, ()),
      build: (_op, _rt) => core.blank-snapshot(),
      caption: [cumulative #sym.arrow end positions],
      step: (kind: "prefix-done"),
      alt: "Cumulative counts now hold each value's end position (decrement first to get the 0-based slot): [" + cumulative.map(str).join(", ") + "].",
    ))

    // --- place phase (right-to-left; decrement the cumulative row) ---
    let output = empty-out
    for i in range(n - 1, -1, step: -1) {
      let e = elems.at(i)
      let b = key(e)
      cumulative.at(b) = cumulative.at(b) - 1
      let p = cumulative.at(b)
      output.at(p) = e
      let ii = i
      let bb = b
      let pp = p
      let dv = _disp-val(e)
      let ds = _disp(e)
      specs.push((
        table: mk-table(
          counts,
          cumulative,
          output,
          (
            (id: "read", from: (row: "in", col: ii), to: (row: "count", col: bb)),
            (id: "place", from: (row: "cumul", col: bb), to: (row: "out", col: pp)),
          ),
        ),
        build: (op, _rt) => {
          let s = core.blank-snapshot()
          s = (s.style-node)(arr-draw.array-cell-key("in", ii), stroke: op.search-stroke)
          s = (s.style-node)(arr-draw.array-cell-key("count", bb), stroke: op.search-stroke)
          s = (s.style-node)(arr-draw.array-cell-key("cumul", bb), stroke: op.attention-stroke)
          s = (s.style-node)(
            arr-draw.array-cell-key("out", pp),
            fill: op.success-fill,
            stroke: op.settled-stroke,
          )
          s = (s.style-edge)("read", stroke: op.search-stroke)
          s = (s.style-edge)("place", stroke: op.success-stroke)
          s
        },
        caption: [place #dv #sym.arrow decrement cumulative #sym.arrow #("output[" + str(pp) + "]")],
        step: (kind: "place", index: ii, bucket: bb, pos: pp),
        alt: "Decrement cumulative[" + str(bb) + "] to " + str(pp) + " (its 0-based slot), then place input[" + str(ii) + "] = " + ds + " into output[" + str(pp) + "].",
      ))
    }

    if with-settled {
      specs.push((
        table: mk-table(counts, cumulative, output, ()),
        build: (op, _rt) => {
          let s = core.blank-snapshot()
          for j in range(n) {
            s = (s.style-node)(
              arr-draw.array-cell-key("out", j),
              fill: op.success-fill,
              stroke: op.settled-stroke,
            )
          }
          s
        },
        caption: "sorted",
        step: (kind: "settled"),
        alt: "Sorted output: [" + output.map(e => if e == none { "" } else { _disp(e) }).join(", ") + "].",
      ))
    }
    return (specs: specs, output: output)
  }

  // --- prefix-sum phase (single-row: mutate the count row in place) ---
  for b in range(1, k) {
    counts.at(b) = counts.at(b) + counts.at(b - 1)
    let bb = b
    let cumulative = counts.at(b)
    specs.push((
      table: mk-table(counts, none, empty-out, ()),
      build: (op, _rt) => {
        let s = core.blank-snapshot()
        s = (s.style-node)(arr-draw.array-cell-key("count", bb - 1), stroke: op.search-stroke)
        s = (s.style-node)(arr-draw.array-cell-key("count", bb), stroke: op.attention-stroke)
        s
      },
      caption: "count[" + str(bb) + "] += count[" + str(bb - 1) + "]",
      step: (kind: "prefix", bucket: bb),
      alt: "Prefix sum: count[" + str(bb) + "] becomes " + str(cumulative) + " (an end position).",
    ))
  }
  specs.push((
    table: mk-table(counts, none, empty-out, ()),
    build: (_op, _rt) => core.blank-snapshot(),
    caption: [counts #sym.arrow end positions],
    step: (kind: "prefix-done"),
    alt: "Counts now hold each value's end position (decrement first to get the 0-based slot): [" + counts.map(str).join(", ") + "].",
  ))

  // --- place phase (right-to-left for stability) ---
  let output = empty-out
  for i in range(n - 1, -1, step: -1) {
    let e = elems.at(i)
    let b = key(e)
    counts.at(b) = counts.at(b) - 1
    let p = counts.at(b)
    output.at(p) = e
    let ii = i
    let bb = b
    let pp = p
    let dv = _disp-val(e)
    let ds = _disp(e)
    specs.push((
      table: mk-table(
        counts,
        none,
        output,
        (
          (id: "read", from: (row: "in", col: ii), to: (row: "count", col: bb)),
          (id: "place", from: (row: "count", col: bb), to: (row: "out", col: pp)),
        ),
      ),
      build: (op, _rt) => {
        let s = core.blank-snapshot()
        s = (s.style-node)(arr-draw.array-cell-key("in", ii), stroke: op.search-stroke)
        s = (s.style-node)(arr-draw.array-cell-key("count", bb), stroke: op.attention-stroke)
        s = (s.style-node)(
          arr-draw.array-cell-key("out", pp),
          fill: op.success-fill,
          stroke: op.settled-stroke,
        )
        s = (s.style-edge)("read", stroke: op.search-stroke)
        s = (s.style-edge)("place", stroke: op.success-stroke)
        s
      },
      caption: [place #dv #sym.arrow decrement count #sym.arrow #("output[" + str(pp) + "]")],
      step: (kind: "place", index: ii, bucket: bb, pos: pp),
      alt: "Decrement count[" + str(bb) + "] to " + str(pp) + " (its 0-based slot), then place input[" + str(ii) + "] = " + ds + " into output[" + str(pp) + "].",
    ))
  }

  if with-settled {
    specs.push((
      table: mk-table(counts, none, output, ()),
      build: (op, _rt) => {
        let s = core.blank-snapshot()
        for j in range(n) {
          s = (s.style-node)(
            arr-draw.array-cell-key("out", j),
            fill: op.success-fill,
            stroke: op.settled-stroke,
          )
        }
        s
      },
      caption: "sorted",
      step: (kind: "settled"),
      alt: "Sorted output: [" + output.map(e => if e == none { "" } else { _disp(e) }).join(", ") + "].",
    ))
  }
  (specs: specs, output: output)
}

// ===================================================================
// Counting sort — the reconstruct (intro, not stable) engine
// ===================================================================
//
// Histogram, then emit each value `v` into the output `count[v]` times,
// left to right. No prefix sums, no stability. Frame `step.kind`s: "init",
// "count", "count-done", "emit", "settled".
//
// Reconstruct rebuilds the output from the histogram alone — the bucket
// index (a key) is all it has, so it CANNOT tell which original element
// (hence which label) each emitted copy was. This is exactly why it is the
// unstable variant. For labelled elements it shows the *first-seen* label
// for each key (`label-of` below); with duplicate keys but distinct labels
// the emitted copies therefore share one label. The stable prefix engine
// and radix carry per-element labels faithfully.
#let _counting-reconstruct-specs(elems, k) = {
  let n = elems.len()
  let empty-out = range(n).map(_ => none)
  // First-seen label per key, so an emitted bucket value can display a
  // label rather than the bare key.
  let label-of = (:)
  for e in elems {
    let ks = str(e.key)
    if ks not in label-of { label-of.insert(ks, e.label) }
  }
  // Synthetic element for a bucket value (the emit phase has only the key).
  let bucket-elem(v) = (key: v, label: label-of.at(str(v), default: auto))
  let out-vals(output) = output.map(e => if e == none { none } else { _disp-val(e) })
  let mk-table(counts, output, arrows) = (
    rows: (
      _row("in", [input], elems.map(_disp-val)),
      _row("count", [count], counts, kind: "count"),
      _row("out", [output], out-vals(output)),
    ),
    arrows: arrows,
  )

  let specs = ((
    table: mk-table(range(k).map(_ => 0), empty-out, ()),
    build: (_op, _rt) => core.blank-snapshot(),
    caption: none,
    step: (kind: "init"),
    alt: "Counting sort (reconstruct). Input: [" + elems.map(_disp).join(", ") + "].",
  ),)

  // --- count phase ---
  let counts = range(k).map(_ => 0)
  for i in range(n) {
    let e = elems.at(i)
    let v = e.key
    counts.at(v) = counts.at(v) + 1
    let ii = i
    let vv = v
    let ds = _disp(e)
    specs.push((
      table: mk-table(
        counts,
        empty-out,
        ((id: "read", from: (row: "in", col: ii), to: (row: "count", col: vv)),),
      ),
      build: (op, _rt) => {
        let s = core.blank-snapshot()
        s = (s.style-node)(arr-draw.array-cell-key("in", ii), stroke: op.search-stroke)
        s = (s.style-node)(arr-draw.array-cell-key("count", vv), stroke: op.attention-stroke)
        s = (s.style-edge)("read", stroke: op.search-stroke)
        s
      },
      caption: "count[" + str(vv) + "] += 1",
      step: (kind: "count", index: ii, bucket: vv),
      alt: "Read input[" + str(ii) + "] = " + ds + "; increment count[" + str(vv) + "].",
    ))
  }
  specs.push((
    table: mk-table(counts, empty-out, ()),
    build: (_op, _rt) => core.blank-snapshot(),
    caption: "histogram complete",
    step: (kind: "count-done"),
    alt: "Histogram complete: count = [" + counts.map(str).join(", ") + "].",
  ))

  // --- emit phase: sweep buckets, write each value count[v] times ---
  let output = empty-out
  let pos = 0
  for v in range(k) {
    let c = counts.at(v)
    for _rep in range(c) {
      let el = bucket-elem(v)
      output.at(pos) = el
      let vv = v
      let pp = pos
      let cc = c
      let dv = _disp-val(el)
      let ds = _disp(el)
      specs.push((
        table: mk-table(
          counts,
          output,
          ((id: "emit", from: (row: "count", col: vv), to: (row: "out", col: pp)),),
        ),
        build: (op, _rt) => {
          let s = core.blank-snapshot()
          s = (s.style-node)(arr-draw.array-cell-key("count", vv), stroke: op.attention-stroke)
          s = (s.style-node)(
            arr-draw.array-cell-key("out", pp),
            fill: op.success-fill,
            stroke: op.settled-stroke,
          )
          s = (s.style-edge)("emit", stroke: op.success-stroke)
          s
        },
        caption: [emit #dv #sym.arrow #("output[" + str(pp) + "]")],
        step: (kind: "emit", value: vv, pos: pp),
        alt: "Emit value " + ds + " into output[" + str(pp) + "] (count[" + str(vv) + "] = " + str(cc) + ").",
      ))
      pos = pos + 1
    }
  }

  specs.push((
    table: mk-table(counts, output, ()),
    build: (op, _rt) => {
      let s = core.blank-snapshot()
      for j in range(n) {
        s = (s.style-node)(
          arr-draw.array-cell-key("out", j),
          fill: op.success-fill,
          stroke: op.settled-stroke,
        )
      }
      s
    },
    caption: "sorted",
    step: (kind: "settled"),
    alt: "Sorted output: [" + output.map(e => if e == none { "" } else { _disp(e) }).join(", ") + "].",
  ))
  specs
}

// ===================================================================
// Counting sort — the buckets (chaining-hash-table) engine
// ===================================================================
//
// The space-inefficient, pedagogically direct view: instead of a histogram
// of counts, the count array is a *chaining hash table* (identity hash
// `h(v) = v`, `k` buckets). Phase 1 (distribute) copies each input element
// into the chain of bucket `key`, appending at the tail. Phase 2 (gather)
// reads the buckets left-to-right, each chain head-to-tail, into the output
// — which makes it a *stable* sort (tail-append + head-first read preserves
// input order within a bucket). Rides the array backend's "buckets" row
// kind (chains hang down from the header cells). Frame `step.kind`s: "init",
// "distribute", "distribute-done", "gather", "settled".
#let _counting-buckets-specs(elems, k) = {
  let n = elems.len()
  // Histogram only to size the reserved chain depth (the deepest bucket), so
  // every frame reserves the same vertical band and the canvas stays fixed.
  let loads = range(k).map(_ => 0)
  for e in elems { loads.at(e.key) = loads.at(e.key) + 1 }
  let max-depth = if k == 0 { 0 } else { calc.max(0, ..loads) }

  let empty-out = range(n).map(_ => none)
  let out-vals(output) = output.map(e => if e == none { none } else { _disp-val(e) })
  // `buckets` is an array of k chains (each a list of elements). Render it as
  // the "buckets" row: k header cells labelled by index, chains hanging down.
  let bucket-row(buckets) = (
    id: "buckets",
    label: [buckets],
    kind: "buckets",
    cells: range(k).map(i => (value: [#i], sub: none)),
    chains: buckets.map(chain => chain.map(e => (value: _cell-value(_disp-val(e)), sub: none))),
    chain-depth: max-depth,
    indices: none,
  )
  let mk-table(buckets, output, arrows) = (
    rows: (
      _row("in", [input], elems.map(_disp-val)),
      bucket-row(buckets),
      _row("out", [output], out-vals(output)),
    ),
    arrows: arrows,
  )

  // init
  let buckets = range(k).map(_ => ())
  let specs = ((
    table: mk-table(buckets, empty-out, ()),
    build: (_op, _rt) => core.blank-snapshot(),
    caption: none,
    step: (kind: "init"),
    alt: "Counting sort (buckets). Input: [" + elems.map(_disp).join(", ") + "].",
  ),)

  // --- distribute phase: copy each element into its bucket's chain ---
  for i in range(n) {
    let e = elems.at(i)
    let b = e.key
    let j = buckets.at(b).len()
    buckets.at(b).push(e)
    let ii = i
    let bb = b
    let jj = j
    let dv = _disp-val(e)
    let ds = _disp(e)
    specs.push((
      table: mk-table(buckets, empty-out, (
        (id: "copy", from: (row: "in", col: ii), to: (row: "buckets", col: bb, depth: jj)),
      )),
      build: (op, _rt) => {
        let s = core.blank-snapshot()
        s = (s.style-node)(arr-draw.array-cell-key("in", ii), stroke: op.search-stroke)
        s = (s.style-node)(
          arr-draw.array-entry-key("buckets", bb, jj),
          fill: op.success-fill,
          stroke: op.settled-stroke,
        )
        s = (s.style-edge)("copy", stroke: op.search-stroke)
        s
      },
      caption: [copy #dv #sym.arrow bucket #bb],
      step: (kind: "distribute", index: ii, bucket: bb, depth: jj),
      alt: "Copy input[" + str(ii) + "] = " + ds + " into bucket " + str(bb) + " (chain depth " + str(jj) + ").",
    ))
  }
  specs.push((
    table: mk-table(buckets, empty-out, ()),
    build: (_op, _rt) => core.blank-snapshot(),
    caption: "all elements distributed",
    step: (kind: "distribute-done"),
    alt: "Every element copied into its bucket; now read the buckets in order.",
  ))

  // --- gather phase: read buckets in order, each chain head-to-tail ---
  let output = empty-out
  let pos = 0
  for b in range(k) {
    for j in range(buckets.at(b).len()) {
      let e = buckets.at(b).at(j)
      output.at(pos) = e
      let bb = b
      let jj = j
      let pp = pos
      let ds = _disp(e)
      specs.push((
        table: mk-table(buckets, output, (
          (id: "gather", from: (row: "buckets", col: bb, depth: jj), to: (row: "out", col: pp)),
        )),
        build: (op, _rt) => {
          let s = core.blank-snapshot()
          s = (s.style-node)(arr-draw.array-entry-key("buckets", bb, jj), stroke: op.search-stroke)
          s = (s.style-node)(
            arr-draw.array-cell-key("out", pp),
            fill: op.success-fill,
            stroke: op.settled-stroke,
          )
          s = (s.style-edge)("gather", stroke: op.success-stroke)
          s
        },
        caption: [read bucket #bb #sym.arrow #("output[" + str(pp) + "]")],
        step: (kind: "gather", bucket: bb, depth: jj, pos: pp),
        alt: "Read bucket " + str(bb) + " (depth " + str(jj) + ") = " + ds + " into output[" + str(pp) + "].",
      ))
      pos = pos + 1
    }
  }

  // --- settled ---
  specs.push((
    table: mk-table(buckets, output, ()),
    build: (op, _rt) => {
      let s = core.blank-snapshot()
      for jx in range(n) {
        s = (s.style-node)(
          arr-draw.array-cell-key("out", jx),
          fill: op.success-fill,
          stroke: op.settled-stroke,
        )
      }
      s
    },
    caption: "sorted",
    step: (kind: "settled"),
    alt: "Sorted output: [" + output.map(e => if e == none { "" } else { _disp(e) }).join(", ") + "].",
  ))
  specs
}

// ===================================================================
// Radix sort (LSD) — one prefix counting-sort pass per digit place
// ===================================================================
#let _radix-specs(elems, base) = {
  let n = elems.len()
  if n == 0 { return () }
  let maxv = calc.max(..elems.map(e => e.key))
  let digits = _num-digits(maxv, base)
  let cur = elems
  let all-specs = ()
  for d in range(digits) {
    let place = _ipow(base, d)
    let keyf = e => calc.rem(calc.quo(e.key, place), base)
    let subs = cur.map(e => [#keyf(e)])
    let is-last = d == digits - 1
    let ps = _counting-prefix-specs(
      cur,
      base,
      key: keyf,
      subs: subs,
      init-caption: "pass " + str(d + 1) + ": " + _place-name(d, base) + " digit",
      init-step: (kind: "pass-start", digit: d),
      init-alt: "Radix pass " + str(d + 1) + " on the " + _place-name(d, base) + " digit (subscript = extracted digit). Current order: [" + cur.map(_disp).join(", ") + "].",
      with-settled: is-last,
    )
    all-specs += ps.specs
    cur = ps.output
  }
  all-specs
}

// ===================================================================
// Sort class
// ===================================================================

/// Typsy class wrapping an array of non-negative integer sort keys (field
/// #raw("values")) and a parallel array of display #raw("labels") (each
/// #raw("auto") = show the key, or arbitrary content), with pure linear-sort
/// operations (#raw("counting-sort"), #raw("radix-sort")) and the animated
/// #raw("*-display") methods. Counting/radix bucket on the integer keys; the
/// labels only ride along for display — the #raw("value")/#raw("label") split
/// shared with @@BST / @@B24. Build one via the @@sort() factory. The
/// #raw("*-display") methods return #raw("Array(Frame)").
#let Sort = class(
  name: "Sort",
  fields: (values: Array(..Int), labels: Array(..Any)),
  methods: (
    len: (self) => self.values.len(),
    // Baseline sorted order (Typst's builtin sort) — the correctness oracle.
    // Sorts the integer keys; labels are a display concern only.
    sorted: (self) => self.values.sorted(),
    // Stable counting sort. `k` is the count-array size (default max+1).
    // Returns the sorted integer keys (labels are a display-only concern).
    counting-sort: (self, k: auto) => _counting-sort(
      self.values,
      if k == auto { _k-of(self.values) } else { k },
    ),
    // LSD radix sort in the given `base` (default 10). Returns the sorted
    // integer keys.
    radix-sort: (self, base: 10) => _radix-sort(self.values, base),
    describe: (self) => if self.values.len() == 0 {
      "array []"
    } else {
      "array [" + _elems(self.values, self.labels).map(_disp).join(", ") + "]"
    },
    // Structural invariants: every value is a non-negative integer and the
    // labels array is parallel to it.
    check-invariants: (self) => {
      for v in self.values {
        assert(type(v) == int, message: "check-invariants: values must be integers.")
        assert(v >= 0, message: "check-invariants: values must be non-negative.")
      }
      assert(
        self.labels.len() == self.values.len(),
        message: "check-invariants: labels must be parallel to values.",
      )
      true
    },
    // The positioned-table dict the renderer consumes (a single input row)
    // — the counterpart to `Graph.positioned` / `HashMap.positioned`. Feed
    // it to `draw-array` for hand-composed cetz canvases.
    positioned: (self, cell-width: auto) => (
      rows: (_row("a", none, _elems(self.values, self.labels).map(_disp-val)),),
      arrows: (),
      cell-width: cell-width,
    ),
    // -----------------------------------------------------------------
    // Display methods
    // -----------------------------------------------------------------
    // Static single-row array, no operation styling. `theme:` overrides the
    // sort palette; `render-theme:` the structural render theme;
    // `cell-width` sizes the cells ("fit" default / `auto` / a number).
    display: (self, theme: auto, render-theme: auto, cell-width: "fit") => {
      let spec = (
        table: (
          rows: (_row("a", none, _elems(self.values, self.labels).map(_disp-val)),),
          arrows: (),
        ),
        build: (_op, _rt) => core.blank-snapshot(),
        caption: none,
        step: (kind: "static"),
        alt: (self.describe)() + ".",
      )
      _sort-make-frames-multi(
        (spec,),
        _resolve-sort-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
        cell-width: cell-width,
      )
    },
    // Animate counting sort. `variant: "prefix"` (default) is the stable
    // count -> prefix-sum -> place version; `variant: "reconstruct"` is the
    // simpler histogram-then-emit intro version; `variant: "buckets"` is the
    // space-inefficient chaining-hash-table view (copy each element into the
    // chain of bucket = its value, then read the buckets in order). `k` is
    // the count-array size (default max+1). `separate-counts: true` (prefix
    // variant only) splits the histogram and the cumulative prefix sums into
    // two distinct rows — the raw counts stay visible while the end positions
    // build in their own row and placement decrements it. Frame `step.kind`s:
    // see the engine comments.
    counting-sort-display: (
      self,
      k: auto,
      variant: "prefix",
      separate-counts: false,
      theme: auto,
      render-theme: auto,
      cell-width: "fit",
    ) => {
      assert(
        ("prefix", "reconstruct", "buckets").contains(variant),
        message: "counting-sort-display: variant must be \"prefix\", \"reconstruct\", or \"buckets\".",
      )
      assert(
        not (separate-counts and variant != "prefix"),
        message: "counting-sort-display: separate-counts applies only to variant \"prefix\".",
      )
      let kk = if k == auto { _k-of(self.values) } else { k }
      let elems = _elems(self.values, self.labels)
      let specs = if variant == "reconstruct" {
        _counting-reconstruct-specs(elems, kk)
      } else if variant == "buckets" {
        _counting-buckets-specs(elems, kk)
      } else {
        _counting-prefix-specs(elems, kk, separate-counts: separate-counts).specs
      }
      _sort-make-frames-multi(
        specs,
        _resolve-sort-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
        cell-width: cell-width,
      )
    },
    // Animate LSD radix sort: one stable prefix counting-sort pass per
    // digit place in `base` (default 10). Each input cell shows its
    // extracted digit as a subscript for the active pass. Frame
    // `step.kind`s: "pass-start", then the counting-sort kinds, ending
    // "settled".
    radix-sort-display: (self, base: 10, theme: auto, render-theme: auto, cell-width: "fit") => {
      assert(base >= 2, message: "radix-sort-display: base must be >= 2.")
      _sort-make-frames-multi(
        _radix-specs(_elems(self.values, self.labels), base),
        _resolve-sort-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
        cell-width: cell-width,
      )
    },
  ),
)

// ===================================================================
// Factory
// ===================================================================

/// Build a @@Sort. Each element is either a bare non-negative integer
/// (the common case — it is both the sort key and what's shown) or a dict
/// #raw("(value: <int>, label: <content>)") to sort an *enumeration*: the
/// integer #raw("value") is the sort key (counting/radix index by it) and
/// #raw("label") is the arbitrary content drawn in the cell (the
/// #raw("value")/#raw("label") split shared with @@BST). Accepts a splat of
/// elements (#raw("sort(3, 1, 4)")) or a single array of them
/// (#raw("sort((3, 1, 4))")).
///
/// #example(```typc
/// sort(3, 1, 4, 1, 5)                         // plain integers
/// sort(
///   (value: 2, label: [Tue]),                 // an enumeration
///   (value: 0, label: [Sun]),
///   (value: 1, label: [Mon]),
/// )
/// ```)
///
/// -> Sort
#let sort(
  /// The elements to sort — a splat of ints and/or
  /// #raw("(value:, label:)") dicts, or one array of them.
  /// -> int | dictionary
  ..args,
) = {
  let raw = args.pos()
  if raw.len() == 1 and type(raw.first()) == array { raw = raw.first() }
  let values = ()
  let labels = ()
  for x in raw {
    let (key, label) = if type(x) == dictionary {
      assert(
        "value" in x,
        message: "sort: an element dict must have a 'value' key.",
      )
      for k in x.keys() {
        assert(
          k == "value" or k == "label",
          message: "sort: element dict keys must be 'value' / 'label', got '" + k + "'.",
        )
      }
      (x.value, x.at("label", default: auto))
    } else {
      (x, auto)
    }
    assert(
      type(key) == int and key >= 0,
      message: "sort: values must be non-negative integers.",
    )
    values.push(key)
    labels.push(label)
  }
  (Sort.new)(values: values, labels: labels)
}
