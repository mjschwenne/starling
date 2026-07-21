// Linear sorts — the `Sort` typsy class, the `sort(..)` factory, and the
// per-DS theme. Rides on the multi-row array draw backend in
// `array-draw.typ` (the analog of how `hashmap.typ` rides on
// `hashmap-draw.typ`).
//
// A `Sort` wraps a plain array of non-negative integers and animates the
// two classic linear (distribution) sorts:
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
)

#let _sort-theme-keys = (
  "empty-fill",
  "index-fill",
  "row-label-fill",
  "count-fill",
  "active-digit-fill",
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
// Display-frame helpers
// ===================================================================

// One row of the positioned table. `values` may contain `none` for empty
// cells; `subs` (if given) is an array of per-cell secondary annotations
// (the radix active digit). `indices: auto` labels cells 0..n-1.
#let _row(id, label, values, indices: auto, kind: "data", subs: none) = (
  id: id,
  label: label,
  kind: kind,
  indices: indices,
  cells: range(values.len()).map(i => (
    value: {
      let v = values.at(i)
      if v == none { none } else { [#v] }
    },
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
      for cell in row.cells {
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
#let _counting-prefix-specs(
  values,
  k,
  key: v => v,
  in-label: [input],
  count-label: [count],
  out-label: [output],
  subs: none,
  init-caption: none,
  init-step: (kind: "init"),
  init-alt: none,
  with-settled: true,
) = {
  let n = values.len()
  let empty-out = range(n).map(_ => none)
  let mk-table(counts, output, arrows) = (
    rows: (
      _row("in", in-label, values, subs: subs),
      _row("count", count-label, counts, kind: "count"),
      _row("out", out-label, output),
    ),
    arrows: arrows,
  )

  let specs = ((
    table: mk-table(range(k).map(_ => 0), empty-out, ()),
    build: (_op, _rt) => core.blank-snapshot(),
    caption: init-caption,
    step: init-step,
    alt: if init-alt != none {
      init-alt
    } else {
      "Counting sort. Input: [" + values.map(str).join(", ") + "]."
    },
  ),)

  // --- count phase ---
  let counts = range(k).map(_ => 0)
  for i in range(n) {
    let v = values.at(i)
    let b = key(v)
    counts.at(b) = counts.at(b) + 1
    let ii = i
    let bb = b
    specs.push((
      table: mk-table(
        counts,
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
      alt: "Read input[" + str(ii) + "] = " + str(v) + "; increment count[" + str(bb) + "].",
    ))
  }
  specs.push((
    table: mk-table(counts, empty-out, ()),
    build: (_op, _rt) => core.blank-snapshot(),
    caption: "histogram complete",
    step: (kind: "count-done"),
    alt: "Histogram complete: count = [" + counts.map(str).join(", ") + "].",
  ))

  // --- prefix-sum phase ---
  for b in range(1, k) {
    counts.at(b) = counts.at(b) + counts.at(b - 1)
    let bb = b
    let cumulative = counts.at(b)
    specs.push((
      table: mk-table(counts, empty-out, ()),
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
    table: mk-table(counts, empty-out, ()),
    build: (_op, _rt) => core.blank-snapshot(),
    caption: "counts -> end positions",
    step: (kind: "prefix-done"),
    alt: "Counts now hold each value's end position: [" + counts.map(str).join(", ") + "].",
  ))

  // --- place phase (right-to-left for stability) ---
  let output = empty-out
  for i in range(n - 1, -1, step: -1) {
    let v = values.at(i)
    let b = key(v)
    counts.at(b) = counts.at(b) - 1
    let p = counts.at(b)
    output.at(p) = v
    let ii = i
    let bb = b
    let pp = p
    let vv = v
    specs.push((
      table: mk-table(
        counts,
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
      caption: "place " + str(vv) + " -> output[" + str(pp) + "]",
      step: (kind: "place", index: ii, bucket: bb, pos: pp),
      alt: "Place input[" + str(ii) + "] = " + str(vv) + " into output[" + str(pp) + "]; count[" + str(bb) + "] decremented to " + str(counts.at(bb)) + ".",
    ))
  }

  if with-settled {
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
      alt: "Sorted output: [" + output.map(str).join(", ") + "].",
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
#let _counting-reconstruct-specs(values, k) = {
  let n = values.len()
  let empty-out = range(n).map(_ => none)
  let mk-table(counts, output, arrows) = (
    rows: (
      _row("in", [input], values),
      _row("count", [count], counts, kind: "count"),
      _row("out", [output], output),
    ),
    arrows: arrows,
  )

  let specs = ((
    table: mk-table(range(k).map(_ => 0), empty-out, ()),
    build: (_op, _rt) => core.blank-snapshot(),
    caption: none,
    step: (kind: "init"),
    alt: "Counting sort (reconstruct). Input: [" + values.map(str).join(", ") + "].",
  ),)

  // --- count phase ---
  let counts = range(k).map(_ => 0)
  for i in range(n) {
    let v = values.at(i)
    counts.at(v) = counts.at(v) + 1
    let ii = i
    let vv = v
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
      alt: "Read input[" + str(ii) + "] = " + str(v) + "; increment count[" + str(vv) + "].",
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
      output.at(pos) = v
      let vv = v
      let pp = pos
      let cc = c
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
        caption: "emit " + str(vv) + " -> output[" + str(pp) + "]",
        step: (kind: "emit", value: vv, pos: pp),
        alt: "Emit value " + str(vv) + " into output[" + str(pp) + "] (count[" + str(vv) + "] = " + str(cc) + ").",
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
    alt: "Sorted output: [" + output.map(str).join(", ") + "].",
  ))
  specs
}

// ===================================================================
// Radix sort (LSD) — one prefix counting-sort pass per digit place
// ===================================================================
#let _radix-specs(values, base) = {
  let n = values.len()
  if n == 0 { return () }
  let maxv = calc.max(..values)
  let digits = _num-digits(maxv, base)
  let cur = values
  let all-specs = ()
  for d in range(digits) {
    let place = _ipow(base, d)
    let keyf = v => calc.rem(calc.quo(v, place), base)
    let subs = cur.map(v => [#keyf(v)])
    let is-last = d == digits - 1
    let ps = _counting-prefix-specs(
      cur,
      base,
      key: keyf,
      subs: subs,
      init-caption: "pass " + str(d + 1) + ": " + _place-name(d, base) + " digit",
      init-step: (kind: "pass-start", digit: d),
      init-alt: "Radix pass " + str(d + 1) + " on the " + _place-name(d, base) + " digit (subscript = extracted digit). Current order: [" + cur.map(str).join(", ") + "].",
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

/// Typsy class wrapping an array of non-negative integers, with pure
/// linear-sort operations (#raw("counting-sort"), #raw("radix-sort")) and
/// the animated #raw("*-display") methods. Build one via the @@sort()
/// factory. The #raw("*-display") methods return #raw("Array(Frame)").
#let Sort = class(
  name: "Sort",
  fields: (values: Array(..Int)),
  methods: (
    len: (self) => self.values.len(),
    // Baseline sorted order (Typst's builtin sort) — the correctness oracle.
    sorted: (self) => self.values.sorted(),
    // Stable counting sort. `k` is the count-array size (default max+1).
    counting-sort: (self, k: auto) => _counting-sort(
      self.values,
      if k == auto { _k-of(self.values) } else { k },
    ),
    // LSD radix sort in the given `base` (default 10).
    radix-sort: (self, base: 10) => _radix-sort(self.values, base),
    describe: (self) => if self.values.len() == 0 {
      "array []"
    } else { "array [" + self.values.map(str).join(", ") + "]" },
    // Structural invariants: every value is a non-negative integer.
    check-invariants: (self) => {
      for v in self.values {
        assert(type(v) == int, message: "check-invariants: values must be integers.")
        assert(v >= 0, message: "check-invariants: values must be non-negative.")
      }
      true
    },
    // The positioned-table dict the renderer consumes (a single input row)
    // — the counterpart to `Graph.positioned` / `HashMap.positioned`. Feed
    // it to `draw-array` for hand-composed cetz canvases.
    positioned: (self, cell-width: auto) => (
      rows: (_row("a", none, self.values),),
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
        table: (rows: (_row("a", none, self.values),), arrows: ()),
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
    // simpler histogram-then-emit intro version. `k` is the count-array
    // size (default max+1). Frame `step.kind`s: see the engine comments.
    counting-sort-display: (
      self,
      k: auto,
      variant: "prefix",
      theme: auto,
      render-theme: auto,
      cell-width: "fit",
    ) => {
      assert(
        variant == "prefix" or variant == "reconstruct",
        message: "counting-sort-display: variant must be \"prefix\" or \"reconstruct\".",
      )
      let kk = if k == auto { _k-of(self.values) } else { k }
      let specs = if variant == "reconstruct" {
        _counting-reconstruct-specs(self.values, kk)
      } else {
        _counting-prefix-specs(self.values, kk).specs
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
        _radix-specs(self.values, base),
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

/// Build a @@Sort over non-negative integers. Accepts either a splat of
/// numbers (#raw("sort(3, 1, 4, 1, 5)")) or a single array
/// (#raw("sort((3, 1, 4, 1, 5))")).
///
/// -> Sort
#let sort(
  /// The values to sort — a splat of ints or one array of ints.
  /// -> int
  ..args,
) = {
  let v = args.pos()
  if v.len() == 1 and type(v.first()) == array { v = v.first() }
  for x in v {
    assert(
      type(x) == int and x >= 0,
      message: "sort: values must be non-negative integers.",
    )
  }
  (Sort.new)(values: v)
}
