// Linear sorts — counting and radix, the two distribution sorts.
//
// A sort wraps parallel arrays: `values` (the non-negative integer sort keys)
// and `labels` (each `auto` = show the key, or arbitrary content, so an
// *enumeration* can be sorted by ordinal while displaying names). The integer
// key is what the count array is indexed by; the label only rides along for
// display — the `value`/`label` split shared with the trees.
//
// Two algorithms, three views of the first:
//
//   counting sort   histogram the values, then place them.
//     "prefix"        (default, stable) count -> cumulative prefix sums ->
//                     place right-to-left into an output array. The
//                     stability radix relies on.
//     "reconstruct"   (intro, not stable) histogram, then emit each value
//                     `count[v]` times back into the output.
//     "buckets"       (stable, space-inefficient) the count array as a
//                     chaining hash table: distribute each element into the
//                     tail of its bucket's chain, then gather the buckets in
//                     order.
//   radix sort      (LSD) one stable prefix counting-sort pass per digit
//                   place, keyed on the extracted digit. Radix is a thin
//                   wrapper over the counting engine with a digit extractor
//                   — one engine, not two.
//
// The count array is indexed directly by value (counting, k = max + 1) or by
// digit (radix, k = base); there is no negative or offset handling.
//
// step.kind vocabulary
// --------------------
//   static                     the one frame of `display`
//   init / pass-start          the opening frame; radix opens each pass
//   count / count-done         building the histogram
//   prefix / prefix-done       the cumulative sums (prefix variant)
//   place                      one element into the output (prefix variant)
//   emit                       one copy out of a bucket (reconstruct)
//   distribute / distribute-done / gather      the buckets variant
//   settled                    the output is sorted
// The final frame of every display carries `step.result` — the sorted keys.

#import "../core/draw-util.typ": anchor
#import "../core/frame.typ": make-frames, make-renderer
#import "../core/snapshot.typ": blank-snapshot, with-edge, with-node
#import "../core/text.typ": alt-describe, display-value as _display-value
#import "../draw/array.typ": cell-key, draw-array, entry-key

#let _DS = "Array"

/// The counting-sort variants this module understands.
#let variants = ("prefix", "reconstruct", "buckets")

// ===================================================================
// Elements: the (key, label) pair
// ===================================================================
//
// An "element" bundles one sort key with its display label. The engines
// below operate on elements so a label rides along with its key through
// placement; only the integer `.key` ever drives the histogram.

// The element array, from parallel `values` / `labels`.
#let _elems(s) = range(s.values.len()).map(i => (
  key: s.values.at(i),
  label: s.labels.at(i, default: auto),
))

// An element's name in prose: its label when that is a plain string, else the
// ordering key — the same rule the trees use.
#let _disp(elem) = _display-value(elem, value-key: "key")

// An element's *visible* value, for a cell body: the label when set, else the
// integer key. Returns an int (auto label) or content (explicit label); `_row`
// renders either, so an auto-labelled element draws exactly as a bare integer.
#let _disp-val(elem) = if elem.label == auto { elem.key } else { elem.label }

// Captions are content, never bare strings. Interpolating keeps the exact
// characters — writing "count[0] += 1" as markup would need escaping, and
// straight quotes would turn smart.
#let _cap(s) = [#s]

// ===================================================================
// Pure sorting
// ===================================================================

// Integer power `b^e`. `calc.pow` may return a float, which breaks the
// integer division the digit extractor depends on.
#let _ipow(b, e) = {
  let r = 1
  for _ in range(e) { r = r * b }
  r
}

// How many digits `maxv` has in `base` (at least 1).
#let _num-digits(maxv, base) = {
  let d = 0
  let v = maxv
  while v > 0 {
    v = calc.quo(v, base)
    d = d + 1
  }
  calc.max(1, d)
}

// The default count-array size for counting sort: max value + 1, since
// indices run 0..max.
#let _k-of(values) = if values.len() == 0 { 1 } else { calc.max(..values) + 1 }

// A stable counting sort of `values` keyed by `key` into `k` buckets — the
// same count / prefix-sum / place-right-to-left algorithm the animation
// narrates, run without the frames.
#let _stable-sort-by(values, key, k) = {
  let counts = range(k).map(_ => 0)
  for v in values {
    let b = key(v)
    counts.at(b) = counts.at(b) + 1
  }
  for b in range(1, k) { counts.at(b) = counts.at(b) + counts.at(b - 1) }
  let out = range(values.len()).map(_ => 0)
  for i in range(values.len() - 1, -1, step: -1) {
    let v = values.at(i)
    let b = key(v)
    counts.at(b) = counts.at(b) - 1
    out.at(counts.at(b)) = v
  }
  out
}

/// Counting-sort the keys into `k` buckets (default max + 1), returning the
/// sorted integer keys. Labels are a display concern and do not come along.
/// -> array
#let counting(s, k: auto) = _stable-sort-by(
  s.values,
  v => v,
  if k == auto { _k-of(s.values) } else { k },
)

/// LSD radix-sort the keys in `base` (default 10), returning them sorted.
/// -> array
#let radix(s, base: 10) = {
  if s.values.len() == 0 { return () }
  let maxv = calc.max(..s.values)
  let out = s.values
  for d in range(_num-digits(maxv, base)) {
    let place = _ipow(base, d)
    out = _stable-sort-by(out, v => calc.rem(calc.quo(v, place), base), base)
  }
  out
}

/// The keys in sorted order, via Typst's builtin sort — the oracle a test
/// checks `counting` and `radix` against.
/// -> array
#let sorted(s) = s.values.sorted()

/// How many elements there are.
/// -> int
#let len(s) = s.values.len()

// The human-readable name of digit place `d` in `base`, for radix captions.
#let _place-name(d, base) = if base == 10 {
  ("ones", "tens", "hundreds", "thousands").at(d, default: "10^" + str(d))
} else { str(base) + "^" + str(d) }

// ===================================================================
// Construction
// ===================================================================

/// Build a sort from a list of elements.
///
/// Each is either a bare non-negative integer (the common case — both the
/// sort key and what is shown) or a `(value: <int>, label: <content>)` dict
/// for sorting an *enumeration*: the integer `value` is the sort key
/// (counting and radix index by it) and `label` is the content drawn in the
/// cell. The two may mix.
///
/// Accepts a splat of elements (`sort.new(3, 1, 4)`) or a single array of
/// them (`sort.new((3, 1, 4))`).
///
/// ```typ
/// #let s = sort.new(3, 1, 4, 1, 5)
/// #let week = sort.new(
///   (value: 2, label: [Tue]),
///   (value: 0, label: [Sun]),
///   (value: 1, label: [Mon]),
/// )
/// ```
///
/// -> dictionary
#let new(
  /// The elements — a splat of ints and/or `(value:, label:)` dicts, or one
  /// array of them.
  /// -> int | dictionary | array
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
        message: "sort.new: an element dict must have a 'value' key.",
      )
      for k in x.keys() {
        assert(
          k == "value" or k == "label",
          message: "sort.new: element dict keys must be 'value' / 'label', got '"
            + k
            + "'.",
        )
      }
      (x.value, x.at("label", default: auto))
    } else { (x, auto) }
    assert(
      type(key) == int and key >= 0,
      message: "sort.new: values must be non-negative integers, got " + repr(key) + ".",
    )
    values.push(key)
    labels.push(label)
  }
  (kind: "sort", values: values, labels: labels)
}

/// A one-line prose summary — the opening line of every alt text.
/// -> str
#let describe(s) = if s.values.len() == 0 {
  "array []"
} else { "array [" + _elems(s).map(_disp).join(", ") + "]" }

/// Check the structural invariants: every value is a non-negative integer and
/// the labels array is parallel to it. Returns `true` or panics.
/// -> bool
#let check-invariants(s) = {
  for v in s.values {
    assert(
      type(v) == int,
      message: "sort.check-invariants: values must be integers, got " + repr(v) + ".",
    )
    assert(
      v >= 0,
      message: "sort.check-invariants: values must be non-negative, got " + repr(v) + ".",
    )
  }
  assert(
    s.labels.len() == s.values.len(),
    message: "sort.check-invariants: labels must be parallel to values.",
  )
  true
}

// ===================================================================
// Rendering
// ===================================================================

// A cell's rendered value: `none` (empty), an int wrapped to content (the
// count and cumulative rows, and auto-labelled elements), or already-content
// (an explicit element label) passed through.
#let _cell-value(v) = if v == none {
  none
} else if type(v) == int { [#v] } else { v }

// One row of the positioned table. `values` may hold `none` for empty cells;
// `subs`, when given, supplies each cell's secondary annotation (radix's
// active digit). `indices: auto` labels the cells 0..n-1.
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

// The single-row table for a static render.
#let _static-table(s) = (
  rows: (_row("a", none, _elems(s).map(_disp-val)),),
  arrows: (),
)

/// The positioned-table dict the backend consumes — the entry point for a
/// hand-composed cetz canvas (`draw-array`) or the op command stream.
/// -> dictionary
#let positioned(s, cell-width: auto) = (
  .._static-table(s),
  cell-width: cell-width,
)

/// A `Renderer` over this array, bound to the array backend — the entry point
/// for driving an animation yourself with the op command stream. Pass
/// `sticky: true` when each frame's styling should accumulate.
/// -> dictionary
#let renderer(
  s,
  cell-width: auto,
  node-style: (:),
  edge-style: (:),
  sticky: false,
  theme: (:),
) = make-renderer(
  positioned(s, cell-width: cell-width),
  draw-array,
  node-style: node-style,
  edge-style: edge-style,
  sticky: sticky,
  theme: theme,
)

// Turn per-frame specs into frames. Each spec carries its own `table` (the
// rows mutate frame to frame) plus a `build(theme) => snapshot`.
//
// The one piece of real work is the global measurement set: the distinct
// non-empty cell bodies across ALL frames — array cells and bucket chain
// entries alike — threaded onto every frame's table so "fit" sizing measures
// the same superset each time. Without it the cells resize the moment a
// running count grows wider than the widest value, and the whole table jumps
// on the slide.
#let _frames(specs, theme, cell-width) = {
  let seen = (:)
  let measure-cells = ()
  for s in specs {
    for row in s.table.rows {
      for cell in row.cells + row.at("chains", default: ()).flatten() {
        if cell.at("value", default: none) != none {
          let k = repr(cell)
          if k not in seen {
            seen.insert(k, true)
            measure-cells.push(cell)
          }
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
    draw-array,
    theme: theme,
  )
}

// Stamp `step.result` onto the last spec — the sorted array as a structure,
// so a caller can carry it straight into the next display.
#let _stamp-result(specs, output) = {
  if specs.len() == 0 { return specs }
  let out = specs
  let i = out.len() - 1
  let s = out.at(i)
  let placed = output.filter(e => e != none)
  out.at(i) = (
    ..s,
    step: (
      ..s.step,
      result: (
        kind: "sort",
        values: placed.map(e => e.key),
        labels: placed.map(e => e.label),
      ),
    ),
  )
  out
}

// The output row's contents: each placed element's display value.
#let _out-vals(output) = output.map(e => if e == none { none } else { _disp-val(e) })

// The alt text of a terminal "sorted" frame.
#let _sorted-alt(output) = (
  "Sorted output: ["
    + output.map(e => if e == none { "" } else { _disp(e) }).join(", ")
    + "]."
)

// Every output cell settled — the styling of the terminal frame.
#let _all-settled(n) = th => {
  let s = blank-snapshot()
  for j in range(n) {
    s = with-node(
      s,
      cell-key("out", j),
      (fill: th.op.success-fill, stroke: th.op.settled-stroke),
    )
  }
  s
}

// ===================================================================
// Counting sort — the prefix (stable) engine, reused by radix
// ===================================================================
//
// The specs for one stable prefix-sum counting-sort pass over `elems`, keyed
// by `key` into `k` buckets. `subs` (radix: the extracted digit per input
// cell) rides along on the input row all pass. The `init-*` arguments
// override the leading frame — radix replaces "init" with a per-pass
// "pass-start" — and `with-settled` appends the terminal sorted frame, which
// radix sets only on its last pass. Returns `(specs, output)`, so radix can
// feed one pass's order into the next.
//
// With `separate-counts` the histogram and the cumulative sums live in two
// DISTINCT rows instead of one mutated in place: the count row keeps the raw
// histogram all pass, the sums build up in a cumulative row, and placement
// decrements that. Clearer — the original histogram stays visible — at the
// cost of a row. Only the prefix engine offers it.

// The count phase, shared by both count-row layouts: one frame per input
// element, incrementing its bucket.
#let _count-specs(elems, k, key, mk-table, empty-counts, empty-out) = {
  let counts = range(k).map(_ => 0)
  let specs = ()
  for i in range(elems.len()) {
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
      build: th => {
        let s = blank-snapshot()
        s = with-node(s, cell-key("in", ii), (stroke: th.op.search-stroke))
        s = with-node(s, cell-key("count", bb), (stroke: th.op.attention-stroke))
        with-edge(s, "read", (stroke: th.op.search-stroke))
      },
      caption: _cap("count[" + str(bb) + "] += 1"),
      step: (kind: "count", index: ii, bucket: bb),
      alt: "Read input["
        + str(ii)
        + "] = "
        + ds
        + "; increment count["
        + str(bb)
        + "].",
    ))
  }
  specs.push((
    table: mk-table(counts, empty-counts, empty-out, ()),
    build: _ => blank-snapshot(),
    caption: _cap("histogram complete"),
    step: (kind: "count-done"),
    alt: "Histogram complete: count = [" + counts.map(str).join(", ") + "].",
  ))
  (specs: specs, counts: counts)
}

// The separate-counts prefix phase: build a distinct cumulative row from the
// (untouched) histogram, one bucket per frame.
#let _carry-specs(counts, k, mk-table, empty-counts, empty-out) = {
  let cumulative = empty-counts
  cumulative.at(0) = counts.at(0)
  let c0 = counts.at(0)
  let carry(b) = (
    (id: "carry", from: (row: "count", col: b), to: (row: "cumul", col: b)),
  )
  let specs = ((
    table: mk-table(counts, cumulative, empty-out, carry(0)),
    build: th => {
      let s = blank-snapshot()
      s = with-node(s, cell-key("count", 0), (stroke: th.op.search-stroke))
      s = with-node(s, cell-key("cumul", 0), (stroke: th.op.attention-stroke))
      with-edge(s, "carry", (stroke: th.op.search-stroke))
    },
    caption: _cap("cumulative[0] = count[0]"),
    step: (kind: "prefix", bucket: 0),
    alt: "Cumulative sum: cumulative[0] = count[0] = " + str(c0) + ".",
  ),)
  for b in range(1, k) {
    cumulative.at(b) = cumulative.at(b - 1) + counts.at(b)
    let bb = b
    let cval = cumulative.at(b)
    specs.push((
      table: mk-table(counts, cumulative, empty-out, carry(bb)),
      build: th => {
        let s = blank-snapshot()
        s = with-node(s, cell-key("count", bb), (stroke: th.op.search-stroke))
        s = with-node(s, cell-key("cumul", bb - 1), (stroke: th.op.search-stroke))
        s = with-node(s, cell-key("cumul", bb), (stroke: th.op.attention-stroke))
        with-edge(s, "carry", (stroke: th.op.search-stroke))
      },
      caption: _cap(
        "cumulative[" + str(bb) + "] = cumulative[" + str(bb - 1) + "] + count[" + str(bb) + "]",
      ),
      step: (kind: "prefix", bucket: bb),
      alt: "Cumulative sum: cumulative["
        + str(bb)
        + "] becomes "
        + str(cval)
        + " (an end position).",
    ))
  }
  specs.push((
    table: mk-table(counts, cumulative, empty-out, ()),
    build: _ => blank-snapshot(),
    caption: [cumulative #sym.arrow end positions],
    step: (kind: "prefix-done"),
    alt: "Cumulative counts now hold each value's end position (decrement "
      + "first to get the 0-based slot): ["
      + cumulative.map(str).join(", ")
      + "].",
  ))
  (specs: specs, cumulative: cumulative)
}

// The single-row prefix phase: mutate the count row in place.
#let _prefix-specs(counts, k, mk-table, empty-out) = {
  let cur = counts
  let specs = ()
  for b in range(1, k) {
    cur.at(b) = cur.at(b) + cur.at(b - 1)
    let bb = b
    let cumulative = cur.at(b)
    specs.push((
      table: mk-table(cur, none, empty-out, ()),
      build: th => {
        let s = blank-snapshot()
        s = with-node(s, cell-key("count", bb - 1), (stroke: th.op.search-stroke))
        with-node(s, cell-key("count", bb), (stroke: th.op.attention-stroke))
      },
      caption: _cap("count[" + str(bb) + "] += count[" + str(bb - 1) + "]"),
      step: (kind: "prefix", bucket: bb),
      alt: "Prefix sum: count["
        + str(bb)
        + "] becomes "
        + str(cumulative)
        + " (an end position).",
    ))
  }
  specs.push((
    table: mk-table(cur, none, empty-out, ()),
    build: _ => blank-snapshot(),
    caption: [counts #sym.arrow end positions],
    step: (kind: "prefix-done"),
    alt: "Counts now hold each value's end position (decrement first to get "
      + "the 0-based slot): ["
      + cur.map(str).join(", ")
      + "].",
  ))
  (specs: specs, counts: cur)
}

// The place phase, right to left — which is what makes counting sort stable.
// `ends` is the row holding each bucket's end position: the cumulative row
// under `separate-counts`, the count row otherwise, and `ends-row` names it
// so the frames highlight and the arrow points at the right one.
#let _place-specs(elems, key, ends, ends-row, counts, mk-table, empty-out, separate) = {
  let cur = ends
  let output = empty-out
  let specs = ()
  for i in range(elems.len() - 1, -1, step: -1) {
    let e = elems.at(i)
    let b = key(e)
    cur.at(b) = cur.at(b) - 1
    let p = cur.at(b)
    output.at(p) = e
    let ii = i
    let bb = b
    let pp = p
    let dv = _disp-val(e)
    let ds = _disp(e)
    let (counts-row, cumul-row) = if separate { (counts, cur) } else { (cur, none) }
    specs.push((
      table: mk-table(
        counts-row,
        cumul-row,
        output,
        (
          (id: "read", from: (row: "in", col: ii), to: (row: "count", col: bb)),
          (id: "place", from: (row: ends-row, col: bb), to: (row: "out", col: pp)),
        ),
      ),
      build: th => {
        let s = blank-snapshot()
        s = with-node(s, cell-key("in", ii), (stroke: th.op.search-stroke))
        if separate {
          s = with-node(s, cell-key("count", bb), (stroke: th.op.search-stroke))
        }
        s = with-node(s, cell-key(ends-row, bb), (stroke: th.op.attention-stroke))
        s = with-node(
          s,
          cell-key("out", pp),
          (fill: th.op.success-fill, stroke: th.op.settled-stroke),
        )
        s = with-edge(s, "read", (stroke: th.op.search-stroke))
        with-edge(s, "place", (stroke: th.op.success-stroke))
      },
      caption: [place #dv #sym.arrow decrement #(if separate { "cumulative" } else { "count" }) #sym.arrow #("output[" + str(pp) + "]")],
      step: (kind: "place", index: ii, bucket: bb, pos: pp),
      alt: "Decrement "
        + (if separate { "cumulative[" } else { "count[" })
        + str(bb)
        + "] to "
        + str(pp)
        + " (its 0-based slot), then place input["
        + str(ii)
        + "] = "
        + ds
        + " into output["
        + str(pp)
        + "].",
    ))
  }
  (specs: specs, output: output, ends: cur)
}

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
  // The all-`none` (muted) cumulative row, before it is built.
  let empty-counts = range(k).map(_ => none)
  // `cumulative` is ignored unless `separate-counts`, when it becomes the
  // extra row between count and out.
  let mk-table(counts, cumulative, output, arrows) = {
    let rows = (
      _row("in", in-label, elems.map(_disp-val), subs: subs),
      _row("count", count-label, counts, kind: "count"),
    )
    if separate-counts {
      rows.push(_row("cumul", cumul-label, cumulative, kind: "count"))
    }
    rows.push(_row("out", out-label, _out-vals(output)))
    (rows: rows, arrows: arrows)
  }

  let specs = ((
    table: mk-table(range(k).map(_ => 0), empty-counts, empty-out, ()),
    build: _ => blank-snapshot(),
    caption: init-caption,
    step: init-step,
    alt: if init-alt != none {
      init-alt
    } else {
      "Counting sort. Input: [" + elems.map(_disp).join(", ") + "]."
    },
  ),)

  let counted = _count-specs(elems, k, key, mk-table, empty-counts, empty-out)
  specs += counted.specs

  let placed = if separate-counts {
    let carried = _carry-specs(counted.counts, k, mk-table, empty-counts, empty-out)
    specs += carried.specs
    _place-specs(
      elems,
      key,
      carried.cumulative,
      "cumul",
      counted.counts,
      mk-table,
      empty-out,
      true,
    )
  } else {
    let prefixed = _prefix-specs(counted.counts, k, mk-table, empty-out)
    specs += prefixed.specs
    _place-specs(elems, key, prefixed.counts, "count", none, mk-table, empty-out, false)
  }
  specs += placed.specs

  if with-settled {
    let (counts-row, cumul-row) = if separate-counts {
      (counted.counts, placed.ends)
    } else { (placed.ends, none) }
    specs.push((
      table: mk-table(counts-row, cumul-row, placed.output, ()),
      build: _all-settled(n),
      caption: _cap("sorted"),
      step: (kind: "settled"),
      alt: _sorted-alt(placed.output),
    ))
  }
  (specs: specs, output: placed.output)
}

// ===================================================================
// Counting sort — the reconstruct (intro, not stable) engine
// ===================================================================
//
// Histogram, then emit each value `v` into the output `count[v]` times, left
// to right. No prefix sums, no stability.
//
// Reconstruct rebuilds the output from the histogram alone — the bucket index
// (a key) is all it has, so it CANNOT tell which original element, and hence
// which label, each emitted copy was. That is exactly why it is the unstable
// variant. For labelled elements it shows the *first-seen* label per key, so
// with duplicate keys but distinct labels the copies share one label. The
// prefix engine and radix carry per-element labels faithfully.
#let _counting-reconstruct-specs(elems, k) = {
  let n = elems.len()
  let empty-out = range(n).map(_ => none)
  // First-seen label per key, so an emitted bucket value can display a label
  // rather than the bare key.
  let label-of = (:)
  for e in elems {
    let ks = str(e.key)
    if ks not in label-of { label-of.insert(ks, e.label) }
  }
  // The synthetic element for a bucket value — the emit phase has only a key.
  let bucket-elem(v) = (key: v, label: label-of.at(str(v), default: auto))
  let mk-table(counts, output, arrows) = (
    rows: (
      _row("in", [input], elems.map(_disp-val)),
      _row("count", [count], counts, kind: "count"),
      _row("out", [output], _out-vals(output)),
    ),
    arrows: arrows,
  )

  let specs = ((
    table: mk-table(range(k).map(_ => 0), empty-out, ()),
    build: _ => blank-snapshot(),
    caption: none,
    step: (kind: "init"),
    alt: "Counting sort (reconstruct). Input: ["
      + elems.map(_disp).join(", ")
      + "].",
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
      build: th => {
        let s = blank-snapshot()
        s = with-node(s, cell-key("in", ii), (stroke: th.op.search-stroke))
        s = with-node(s, cell-key("count", vv), (stroke: th.op.attention-stroke))
        with-edge(s, "read", (stroke: th.op.search-stroke))
      },
      caption: _cap("count[" + str(vv) + "] += 1"),
      step: (kind: "count", index: ii, bucket: vv),
      alt: "Read input["
        + str(ii)
        + "] = "
        + ds
        + "; increment count["
        + str(vv)
        + "].",
    ))
  }
  specs.push((
    table: mk-table(counts, empty-out, ()),
    build: _ => blank-snapshot(),
    caption: _cap("histogram complete"),
    step: (kind: "count-done"),
    alt: "Histogram complete: count = [" + counts.map(str).join(", ") + "].",
  ))

  // --- emit phase: sweep the buckets, writing each value count[v] times ---
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
        build: th => {
          let s = blank-snapshot()
          s = with-node(s, cell-key("count", vv), (stroke: th.op.attention-stroke))
          s = with-node(
            s,
            cell-key("out", pp),
            (fill: th.op.success-fill, stroke: th.op.settled-stroke),
          )
          with-edge(s, "emit", (stroke: th.op.success-stroke))
        },
        caption: [emit #dv #sym.arrow #("output[" + str(pp) + "]")],
        step: (kind: "emit", value: vv, pos: pp),
        alt: "Emit value "
          + ds
          + " into output["
          + str(pp)
          + "] (count["
          + str(vv)
          + "] = "
          + str(cc)
          + ").",
      ))
      pos = pos + 1
    }
  }

  specs.push((
    table: mk-table(counts, output, ()),
    build: _all-settled(n),
    caption: _cap("sorted"),
    step: (kind: "settled"),
    alt: _sorted-alt(output),
  ))
  (specs: specs, output: output)
}

// ===================================================================
// Counting sort — the buckets (chaining-hash-table) engine
// ===================================================================
//
// The space-inefficient, pedagogically direct view: instead of a histogram of
// counts, the count array is a *chaining hash table* (identity hash
// `h(v) = v`, `k` buckets). Distribute copies each input element into the
// chain of bucket `key`, appending at the tail; gather reads the buckets left
// to right, each chain head to tail, into the output — which makes it a
// stable sort, since tail-append plus head-first read preserves input order
// within a bucket. Rides the array backend's "buckets" row kind, where the
// chains hang down from the header cells.
#let _counting-buckets-specs(elems, k) = {
  let n = elems.len()
  // Histogram only to size the reserved chain depth (the deepest bucket), so
  // every frame reserves the same vertical band and the canvas stays fixed.
  let loads = range(k).map(_ => 0)
  for e in elems { loads.at(e.key) = loads.at(e.key) + 1 }
  let max-depth = if k == 0 { 0 } else { calc.max(0, ..loads) }

  let empty-out = range(n).map(_ => none)
  // `buckets` is an array of k chains, each a list of elements: k header cells
  // labelled by index, with the chains hanging down.
  let bucket-row(buckets) = (
    id: "buckets",
    label: [buckets],
    kind: "buckets",
    cells: range(k).map(i => (value: [#i], sub: none)),
    chains: buckets.map(chain => chain.map(e => (
      value: _cell-value(_disp-val(e)),
      sub: none,
    ))),
    chain-depth: max-depth,
    indices: none,
  )
  let mk-table(buckets, output, arrows) = (
    rows: (
      _row("in", [input], elems.map(_disp-val)),
      bucket-row(buckets),
      _row("out", [output], _out-vals(output)),
    ),
    arrows: arrows,
  )

  let buckets = range(k).map(_ => ())
  let specs = ((
    table: mk-table(buckets, empty-out, ()),
    build: _ => blank-snapshot(),
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
      table: mk-table(
        buckets,
        empty-out,
        (
          (
            id: "copy",
            from: (row: "in", col: ii),
            to: (row: "buckets", col: bb, depth: jj),
          ),
        ),
      ),
      build: th => {
        let s = blank-snapshot()
        s = with-node(s, cell-key("in", ii), (stroke: th.op.search-stroke))
        s = with-node(
          s,
          entry-key("buckets", bb, jj),
          (fill: th.op.success-fill, stroke: th.op.settled-stroke),
        )
        with-edge(s, "copy", (stroke: th.op.search-stroke))
      },
      caption: [copy #dv #sym.arrow bucket #bb],
      step: (kind: "distribute", index: ii, bucket: bb, depth: jj),
      alt: "Copy input["
        + str(ii)
        + "] = "
        + ds
        + " into bucket "
        + str(bb)
        + " (chain depth "
        + str(jj)
        + ").",
    ))
  }
  specs.push((
    table: mk-table(buckets, empty-out, ()),
    build: _ => blank-snapshot(),
    caption: _cap("all elements distributed"),
    step: (kind: "distribute-done"),
    alt: "Every element copied into its bucket; now read the buckets in order.",
  ))

  // --- gather phase: read the buckets in order, each chain head to tail ---
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
        table: mk-table(
          buckets,
          output,
          (
            (
              id: "gather",
              from: (row: "buckets", col: bb, depth: jj),
              to: (row: "out", col: pp),
            ),
          ),
        ),
        build: th => {
          let s = blank-snapshot()
          s = with-node(s, entry-key("buckets", bb, jj), (stroke: th.op.search-stroke))
          s = with-node(
            s,
            cell-key("out", pp),
            (fill: th.op.success-fill, stroke: th.op.settled-stroke),
          )
          with-edge(s, "gather", (stroke: th.op.success-stroke))
        },
        caption: [read bucket #bb #sym.arrow #("output[" + str(pp) + "]")],
        step: (kind: "gather", bucket: bb, depth: jj, pos: pp),
        alt: "Read bucket "
          + str(bb)
          + " (depth "
          + str(jj)
          + ") = "
          + ds
          + " into output["
          + str(pp)
          + "].",
      ))
      pos = pos + 1
    }
  }

  specs.push((
    table: mk-table(buckets, output, ()),
    build: _all-settled(n),
    caption: _cap("sorted"),
    step: (kind: "settled"),
    alt: _sorted-alt(output),
  ))
  (specs: specs, output: output)
}

// ===================================================================
// Radix sort (LSD) — one prefix counting-sort pass per digit place
// ===================================================================

#let _radix-specs(elems, base) = {
  let n = elems.len()
  if n == 0 { return (specs: (), output: ()) }
  let digits = _num-digits(calc.max(..elems.map(e => e.key)), base)
  let cur = elems
  let all-specs = ()
  for d in range(digits) {
    let place = _ipow(base, d)
    let keyf = e => calc.rem(calc.quo(e.key, place), base)
    let pass = _counting-prefix-specs(
      cur,
      base,
      key: keyf,
      subs: cur.map(e => [#keyf(e)]),
      init-caption: _cap(
        "pass " + str(d + 1) + ": " + _place-name(d, base) + " digit",
      ),
      init-step: (kind: "pass-start", digit: d),
      init-alt: "Radix pass "
        + str(d + 1)
        + " on the "
        + _place-name(d, base)
        + " digit (subscript = extracted digit). Current order: ["
        + cur.map(_disp).join(", ")
        + "].",
      with-settled: d == digits - 1,
    )
    all-specs += pass.specs
    cur = pass.output
  }
  (specs: all-specs, output: cur)
}

// ===================================================================
// Displays
// ===================================================================
//
// `cell-width` sizes the cells: `"fit"` (the default here) grows them to the
// widest body the animation will ever show, `auto` keeps the fixed footprint
// and never measures, and a number pins an exact width. `"fit"` is safe as a
// default only because these always render inside the `slides.typ` helpers'
// `context`, where `measure` is available.

/// The array as a single static frame — one row, no operation styling.
/// -> array
#let display(s, theme: (:), cell-width: "fit") = _frames(
  (
    (
      table: _static-table(s),
      build: _ => blank-snapshot(),
      caption: none,
      step: (kind: "static", result: s),
      alt: alt-describe(_DS, describe(s)),
    ),
  ),
  theme,
  cell-width,
)

/// Animate counting sort.
///
/// `variant: "prefix"` (the default) is the stable count → prefix-sum → place
/// version; `"reconstruct"` is the simpler histogram-then-emit intro version;
/// `"buckets"` is the space-inefficient chaining-hash-table view.
///
/// `separate-counts: true` (prefix only) splits the histogram and the
/// cumulative sums into two rows, so the raw counts stay visible while the
/// end positions build in their own row.
///
/// -> array
#let counting-display(
  s,
  /// The count-array size. `auto` is max + 1.
  /// -> auto | int
  k: auto,
  /// Which view: `"prefix"`, `"reconstruct"`, or `"buckets"`.
  /// -> str
  variant: "prefix",
  /// Give the cumulative sums their own row (prefix only).
  /// -> bool
  separate-counts: false,
  /// Partial theme override, merged over the ambient theme.
  /// -> dictionary
  theme: (:),
  /// Cell sizing: `"fit"`, `auto`, or an exact width.
  /// -> str | auto | float
  cell-width: "fit",
) = {
  assert(
    variants.contains(variant),
    message: "sort.counting-display: variant must be one of "
      + variants.map(v => "\"" + v + "\"").join(", ")
      + ", got "
      + repr(variant)
      + ".",
  )
  assert(
    not (separate-counts and variant != "prefix"),
    message: "sort.counting-display: separate-counts applies only to variant "
      + "\"prefix\".",
  )
  let kk = if k == auto { _k-of(s.values) } else { k }
  let elems = _elems(s)
  let built = if variant == "reconstruct" {
    _counting-reconstruct-specs(elems, kk)
  } else if variant == "buckets" {
    _counting-buckets-specs(elems, kk)
  } else {
    _counting-prefix-specs(elems, kk, separate-counts: separate-counts)
  }
  _frames(_stamp-result(built.specs, built.output), theme, cell-width)
}

/// Animate LSD radix sort: one stable prefix counting-sort pass per digit
/// place in `base`. Each input cell shows the digit the active pass extracted
/// as a subscript, and each pass starts from the previous pass's order.
/// -> array
#let radix-display(
  s,
  /// The radix. Ten gives the familiar ones / tens / hundreds passes.
  /// -> int
  base: 10,
  /// Partial theme override, merged over the ambient theme.
  /// -> dictionary
  theme: (:),
  /// Cell sizing: `"fit"`, `auto`, or an exact width.
  /// -> str | auto | float
  cell-width: "fit",
) = {
  assert(base >= 2, message: "sort.radix-display: base must be >= 2.")
  let built = _radix-specs(_elems(s), base)
  _frames(_stamp-result(built.specs, built.output), theme, cell-width)
}
