// Hash-map rendering backend — the hash-table-specific layer on top of
// the structure-agnostic kernel in `anim-core.typ`. Holds the cetz
// drawing (`draw-hashmap`), node/edge identity helpers (`cell-anchor`,
// `entry-key`), and the hash-map-bound `make-hashmap-renderer` wrapper
// that injects `draw-hashmap` into the generic `Renderer`.
//
// This is the hash-map analog of `tree-anim.typ` / `graph-draw.typ`: it
// knows how to *draw* a hash table but nothing about hashing algorithms
// — that lives in the `HashMap` class in `hashmap.typ`. The two are
// deliberately split.
//
// Node / edge identity
// --------------------
// A hash table is a fixed-length array of cells indexed 0..m-1, so
// `PathId` (tree paths) does not apply. Instead:
//   * Cells (array slots) are keyed by `"c" + str(i)` (e.g. "c3").
//   * Chain entries (separate chaining) are keyed by
//     `"c" + i + ":" + j` — bucket i, depth j (0 = the head entry).
//   * Chain links (edges) are keyed by their *target* entry — the same
//     `"c" + i + ":" + j` string (mirrors the tree convention of keying
//     an edge by its child). The link into entry 0 is the head pointer
//     from the array slot.
// Snapshot dicts (from `anim-core.typ`) use these strings as keys; the
// core never interprets them.
//
// Positioned-table input
// ----------------------
// `draw-hashmap` consumes an opaque "table" dict (built by the `HashMap`
// class):
//   (
//     capacity: int,
//     orientation: "horizontal" | "vertical",
//     strategy: "chaining" | "linear" | "quadratic",
//     cells: array length capacity. For open addressing (linear /
//            quadratic) each element is `none` (empty), an entry dict
//            `(key:, label:, value:)`, or a tombstone `(tombstone: true)`.
//            For chaining each element is an array of entry dicts.
//     hash-box: none | (key:, expr:, index:) — the operation overlay for
//            this frame: renders `h(<key>) = <expr> = <index>` above the
//            array with an arrow to cell `index`. A `ghost: true` key draws
//            it invisibly (reserving its footprint) — see the hash-box code.
//     cell-width: auto | "fit" | number — cell sizing (optional, default
//            `auto`). `auto` keeps the fixed historical footprint; "fit"
//            grows cells/entries to the widest label (measures, so it
//            needs a layout context); a number pins an exact cell width.
//     phantom: none | (bucket:, depth:) — chaining only. Draws one empty
//            "null" cell hung one past the tail of `bucket` (the slot a
//            failed lookup falls off the end into), with a link into it.
//            Stylable via `entry-key(bucket, depth)` like a real entry.
//   )
// Coordinates are derived deterministically from `capacity` +
// `orientation` + the resolved cell width; unlike graphs there is no
// explicit layout to supply.

#import "@preview/typsy:0.2.2": *
#import "@preview/cetz:0.5.2"
#import "./anim-core.typ": *
#import "./anim-core.typ" as core

// ===================================================================
// Node / edge identity
// ===================================================================

/// Canonical snapshot key for the array cell (slot) at index #raw("i").
///
/// -> str
#let cell-key(
  /// Slot index.
  /// -> int
  i,
) = "c" + str(i)

/// Canonical snapshot key for the chaining entry at depth #raw("j") in
/// bucket #raw("i") (0 = the head entry). Also the key of the link
/// *into* that entry.
///
/// -> str
#let entry-key(
  /// Bucket (slot) index.
  /// -> int
  i,
  /// Depth in the chain (0 = head).
  /// -> int
  j,
) = "c" + str(i) + ":" + str(j)

/// The fully-qualified cetz anchor name for the array cell #raw("i")
/// drawn by @@draw-hashmap(). Use it to attach your own callouts when you
/// call #raw("draw-hashmap") inside your own #raw("cetz.canvas"). The
/// #raw("prefix") must match the #raw("cell-prefix") passed to
/// #raw("draw-hashmap"). Sub-anchors follow (e.g.
/// #raw("cell-anchor(3) + \".north\"")).
///
/// -> str
#let cell-anchor(
  /// Slot index.
  /// -> int
  i,
  /// Per-cell name prefix; must match #raw("draw-hashmap")'s
  /// #raw("cell-prefix").
  /// -> str
  prefix: "cell-",
) = prefix + "c" + str(i)

/// The fully-qualified cetz anchor name for the chaining entry at depth
/// #raw("j") in bucket #raw("i") (0 = the head entry) drawn by
/// @@draw-hashmap(). The counterpart of @@cell-anchor() for chain
/// entries. Sub-anchors follow (e.g. #raw("entry-anchor(3, 0) +
/// \".east\"")). Only meaningful for the #raw("\"chaining\"") strategy.
///
/// -> str
#let entry-anchor(
  /// Bucket (slot) index.
  /// -> int
  i,
  /// Depth in the chain (0 = head).
  /// -> int
  j,
  /// Per-cell name prefix; must match #raw("draw-hashmap")'s
  /// #raw("cell-prefix").
  /// -> str
  prefix: "cell-",
) = prefix + "c" + str(i) + "-" + str(j)

// ===================================================================
// Layout geometry
// ===================================================================
//
// All measurements are in cetz units. The layout is fully determined by
// the slot index and orientation, so callers never supply positions.

// Default cell footprint. Horizontal: cells run left→right, each `_CW`
// wide and `_CH` tall, sharing edges into a contiguous array. Vertical:
// cells run top→bottom (a memory-diagram column), `_CW` wide and `_CH`
// tall. These are the *floors*: `draw-hashmap` widens `cw` (and the chain
// entry half-width) to fit longer labels, but never below these, so
// short (numeric) tables render at the historical size (see `_resolve-dims`).
#let _CW = 1.4
#let _CH = 1.0
// Chain-entry box half-extents. These are *floors*: in "fit" mode both the
// half-width (`ehw`) and the half-height (`ehh`) grow to the widest / tallest
// label, so entries don't clip at large (e.g. touying) font sizes. The pitch
// between successive entries and the first-entry drop are derived from `ehh`.
#let _EHW = 0.55
#let _EHH = 0.34

// The resolved layout dimensions for one render (`_resolve-dims`) are threaded
// into the geometry helpers below: `cw`/`ch` are the array-cell footprint;
// `ehw`/`ehh` the chaining-entry half-extents; `epitch` the vertical pitch
// between horizontal-chain entries; `first-off` the drop from a cell to its
// first entry; `gap` the clear vertical band (cell → first entry) the index
// label is seated in for horizontal chaining.

// `(corner0, corner1, center)` of cell `i` for the given orientation.
#let _cell-geom(i, orientation, dims) = {
  let (cw, ch) = (dims.cw, dims.ch)
  if orientation == "vertical" {
    let y0 = -(i + 1) * ch
    let y1 = -i * ch
    ((0, y0), (cw, y1), (cw / 2, -(i + 0.5) * ch))
  } else {
    let x0 = i * cw
    let x1 = (i + 1) * cw
    ((x0, 0), (x1, ch), ((i + 0.5) * cw, ch / 2))
  }
}

// Center of chaining entry `j` hanging off bucket `i`.
#let _entry-center(i, j, orientation, dims) = {
  let (_, _, c) = _cell-geom(i, orientation, dims)
  if orientation == "vertical" {
    // Entries extend rightward from the cell's east face; each entry is
    // `2*ehw` wide with a 0.5-unit gap, seated 0.15 past the cell's east
    // face (matches the historical offset when `ehw == _EHW`).
    (dims.cw + 0.15 + dims.ehw + j * (2 * dims.ehw + 0.5), c.at(1))
  } else {
    // Entries hang downward below the cell's south face.
    (c.at(0), -dims.first-off - j * dims.epitch)
  }
}

// The point on cell `i`'s face from which its chain (head pointer)
// departs, and the point at which the whole array's index label sits.
#let _cell-chain-exit(i, orientation, dims) = {
  let (c0, c1, c) = _cell-geom(i, orientation, dims)
  if orientation == "vertical" {
    (c1.at(0), c.at(1)) // east-center
  } else {
    (c.at(0), c0.at(1)) // south-center (c0 holds the lower y)
  }
}

// Returns `(pos, anchor)` — the cetz point and the `_haloed` anchor that seats
// the index label there.
#let _index-label-pos(i, orientation, strategy, dims) = {
  let (c0, c1, c) = _cell-geom(i, orientation, dims)
  if orientation == "vertical" {
    ((-0.35, c.at(1)), "center") // west of the column
  } else if strategy == "chaining" {
    // Horizontal chaining: the head-pointer arrow drops straight down the cell
    // center to the first entry, so a centered index would bury it (its opaque
    // halo covers the whole short arrow). Seat the index just left of the
    // arrow, in the clear band between the cell and the first entry.
    ((c.at(0) - 0.22, -dims.gap / 2), "east")
  } else {
    ((c.at(0), c0.at(1) - 0.35), "center") // below the row
  }
}

// ===================================================================
// draw-hashmap
// ===================================================================

// The paint (color) of a stroke spec, for filling a chain link's
// arrowhead to match its line (mirrors the graph backend's helper of the
// same name). Falls back to black for `auto`/`none`.
#let _stroke-paint(s) = {
  if s == auto or s == none { return black }
  let st = stroke(s)
  if st.paint == auto { black } else { st.paint }
}

// A filled `note-bg` halo behind a small piece of content, so index
// labels and edge tags stay legible over any connector line beneath
// them (mirrors the graph backend's `_edge-tag`).
#let _haloed(draw, pos, body, render-theme, anchor: "center") = draw.content(
  pos,
  anchor: anchor,
  frame: "rect",
  fill: render-theme.note-bg,
  stroke: none,
  padding: 0.05,
  body,
)

// The visible content of one entry/cell given its resolved key label and
// optional value. A value renders as a second, smaller line below the
// key; key-only entries show just the key.
#let _entry-body(label, value, text-fill) = {
  if value == none {
    text(weight: "bold", fill: text-fill, label)
  } else {
    stack(
      dir: ttb,
      spacing: 0.15em,
      text(weight: "bold", fill: text-fill, label),
      text(size: 0.7em, fill: text-fill, value),
    )
  }
}

// Padding (per side, cetz units) between a label and its box edge when sizing
// to fit. `_PAD-X` matches the graph backend's `pad-x`; `_PAD-Y` keeps a
// comfortable band above/below the (possibly large) label text.
#let _PAD-X = 0.22
#let _PAD-Y = 0.15

// Resolve the layout dimensions for one render. `cell-width` selects the
// sizing mode:
//   * `auto`   — the historical fixed footprint (`_CW` / `_EHW`). Never
//                measures, so it is safe outside a layout context.
//   * "fit"    — grow `cw` to fit the widest occupied-cell label (open
//                addressing) and `ehw` to fit the widest chain-entry
//                label (chaining), each floored at the historical size so
//                short (numeric) tables are unchanged. Calls `measure`, so
//                it REQUIRES a layout context (the `*-display` methods,
//                wrapped by the lib frame helpers, always supply one).
//   * a number — pin `cw` to that exact width (no measure).
// Either way, horizontal chaining widens the array pitch (`cw`) so a
// bucket's hanging chain clears its neighbours. Structural labels (from
// the table, not per-frame snapshot overrides) drive the measurement, so
// `cw` stays constant across an animation.
#let _resolve-dims(cells, strategy, orientation, text-fill, cell-width) = {
  let m = cells.len()
  let ehw = _EHW
  let ehh = _EHH
  let cw = _CW
  let ch = _CH
  let gap = 0.61 // clear band between a cell and its first chain entry
  if cell-width == "fit" {
    let dims-of(label, value) = measure(_entry-body(label, value, text-fill))
    let max-cell-w = 0
    let max-cell-h = 0
    let max-entry-w = 0
    let max-entry-h = 0
    for cell in cells {
      if strategy == "chaining" {
        for e in cell {
          let d = dims-of(e.at("label", default: str(e.key)), e.at("value", default: none))
          max-entry-w = calc.max(max-entry-w, d.width / 1cm)
          max-entry-h = calc.max(max-entry-h, d.height / 1cm)
        }
      } else if cell != none and not cell.at("tombstone", default: false) {
        let d = dims-of(cell.at("label", default: str(cell.key)), cell.at("value", default: none))
        max-cell-w = calc.max(max-cell-w, d.width / 1cm)
        max-cell-h = calc.max(max-cell-h, d.height / 1cm)
      }
    }
    ehw = calc.max(_EHW, max-entry-w / 2 + _PAD-X)
    ehh = calc.max(_EHH, max-entry-h / 2 + _PAD-Y)
    cw = calc.max(_CW, max-cell-w + 2 * _PAD-X)
    ch = calc.max(_CH, max-cell-h + 2 * _PAD-Y)
    // Widen the cell→first-entry band to clear the (font-scaled) index label.
    let idx-h = measure(text(size: 0.75em, str(calc.max(0, m - 1)))).height / 1cm
    gap = calc.max(0.61, idx-h + 0.18)
  } else if cell-width != auto {
    cw = cell-width
  }
  // Horizontal chaining: entries hang under each bucket, so the array
  // pitch must clear adjacent chains (each entry is `2*ehw` wide).
  if strategy == "chaining" and orientation != "vertical" {
    cw = calc.max(cw, 2 * ehw + 0.2)
  }
  // `epitch`/`first-off` derive from `ehh` so taller entries stay clear of one
  // another and of the array (at the floor these reproduce the historical
  // 1.02 pitch / 0.95 drop exactly).
  (cw: cw, ch: ch, ehw: ehw, ehh: ehh, epitch: 2 * ehh + 0.34, first-off: ehh + gap, gap: gap)
}

/// Emit the cetz draw commands for one styled snapshot of a hash table,
/// _without_ wrapping them in a #raw("cetz.canvas"). The caller wraps the
/// canvas — use this to add your own cetz annotations alongside the table
/// — see @@cell-anchor().
///
/// The array of cells is drawn first, then (for chaining) the chains
/// hanging off each bucket, then the hash-box overlay on top. Each cell's
/// structural state comes from the table dict (empty / occupied /
/// tombstone / chain); per-frame highlights come from the snapshot
/// (probe walk in #raw("search-stroke"), landing in #raw("success-fill"),
/// etc.). The theme argument is a merged render-theme plus the per-DS
/// hash-map palette (passed together as one dict — see the #raw("hm-")
/// keys read below).
///
/// -> content
#let draw-hashmap(
  /// The positioned table — see the module header for its shape.
  /// -> dictionary
  tbl,
  /// Style overlay for this snapshot. Use #raw("blank-snapshot()") for
  /// an unstyled table.
  /// -> Snapshot
  snapshot,
  /// Default node-style overrides applied before per-cell overrides.
  /// -> dictionary
  default-node-style: (:),
  /// Default edge-style overrides applied before per-link overrides.
  /// -> dictionary
  default-edge-style: (:),
  /// Structural defaults plus the hash-map palette, merged into one dict.
  /// -> dictionary
  render-theme: default-render-theme,
  /// Per-cell cetz element-name prefix. Must match @@cell-anchor()'s
  /// #raw("prefix").
  /// -> str
  cell-prefix: "cell-",
) = {
  import cetz.draw
  let m = tbl.capacity
  let orientation = tbl.at("orientation", default: "horizontal")
  let strategy = tbl.at("strategy", default: "chaining")
  let cells = tbl.cells

  // Resolve the cell/entry footprint so longer labels aren't clipped. The
  // table dict may pin a fixed `cell-width`; otherwise it fits the widest
  // label (floored at the historical size — numeric tables are unchanged).
  let dims = _resolve-dims(
    cells,
    strategy,
    orientation,
    render-theme.node-text-fill,
    tbl.at("cell-width", default: auto),
  )

  // Palette fallbacks. `render-theme` carries both the structural keys
  // and the hash-map keys (the class merges them before calling), but we
  // default each so a bare `draw-hashmap` call still works.
  let empty-fill = render-theme.at("empty-fill", default: rgb("#f2f2f2"))
  let index-fill = render-theme.at("index-fill", default: rgb("#888888"))
  let tomb-fill = render-theme.at("tombstone-fill", default: rgb("#e0e0e0"))
  let tomb-stroke = render-theme.at("tombstone-stroke", default: rgb("#999999"))
  let chain-stroke = render-theme.at("chain-stroke", default: render-theme.edge-stroke)
  let chain-fill = render-theme.at("chain-fill", default: white)

  // Draw one cell/entry rectangle with a resolved style overlay. `state`
  // is the structural state ("empty" / "occupied" / "tombstone" /
  // "entry"). Returns nothing; draws in place.
  let draw-box(key, name, c0, c1, center, state, label, value, is-chain) = {
    let s = _merge-into(default-node-style, snapshot.nodes.at(key, default: (:)))
    if s.at("hide", default: false) { return }
    let base-fill = if state == "empty" {
      empty-fill
    } else if state == "tombstone" {
      tomb-fill
    } else if is-chain {
      chain-fill
    } else { render-theme.node-fill }
    let base-stroke = if state == "tombstone" {
      tomb-stroke
    } else { render-theme.node-stroke }
    let fill-c = s.at("fill", default: base-fill)
    let stroke-c = s.at("stroke", default: base-stroke)
    let radius = if is-chain { 0.08 } else { 0 }
    draw.rect(c0, c1, fill: fill-c, stroke: stroke-c, radius: radius, name: name)
    let tf = s.at("text-fill", default: render-theme.node-text-fill)
    let lbl = s.at("label", default: label)
    if state == "tombstone" {
      draw.content(center, text(weight: "bold", fill: tomb-stroke, size: 1.1em, [×]))
    } else if state != "empty" and lbl != none {
      draw.content(center, _entry-body(lbl, value, tf))
    }
    // Operation note (gold), just outside the box on the far side.
    let note = s.at("note", default: none)
    if note != none {
      let nf = s.at("note-fill", default: render-theme.note-fill)
      let np = if orientation == "vertical" {
        (center.at(0), c1.at(1) + 0.28)
      } else {
        (c1.at(0) + 0.12, center.at(1))
      }
      let na = if orientation == "vertical" { "south" } else { "west" }
      _haloed(
        draw,
        np,
        text(fill: nf, size: 0.8em, note),
        render-theme,
        anchor: na,
      )
    }
  }

  // --- chains first (occluded by cells drawn afterwards where they meet) ---
  if strategy == "chaining" {
    for (i, chain) in cells.enumerate() {
      if chain.len() == 0 { continue }
      // Head pointer: array slot -> entry 0.
      let exit = _cell-chain-exit(i, orientation, dims)
      for (j, _entry) in chain.enumerate() {
        let ec = _entry-center(i, j, orientation, dims)
        let top = if orientation == "vertical" {
          (ec.at(0) - dims.ehw, ec.at(1))
        } else { (ec.at(0), ec.at(1) + dims.ehh) }
        let from = if j == 0 {
          exit
        } else {
          let pc = _entry-center(i, j - 1, orientation, dims)
          if orientation == "vertical" {
            (pc.at(0) + dims.ehw, pc.at(1))
          } else { (pc.at(0), pc.at(1) - dims.ehh) }
        }
        let lk = entry-key(i, j)
        let ls = _merge-into(default-edge-style, snapshot.edges.at(lk, default: (:)))
        if not ls.at("hide", default: false) {
          draw.line(
            from,
            top,
            stroke: ls.at("stroke", default: chain-stroke),
            mark: (end: ">", fill: _stroke-paint(ls.at("stroke", default: chain-stroke))),
          )
        }
      }
    }
  }

  // --- cells ---
  for (i, cell) in cells.enumerate() {
    let (c0, c1, center) = _cell-geom(i, orientation, dims)
    let name = cell-prefix + "c" + str(i)
    if strategy == "chaining" {
      // The array slot itself is the bucket header. An empty bucket reads
      // as a muted empty slot; a bucket with a chain reads as a filled
      // pointer slot (the entries below carry the keys).
      let state = if cell.len() == 0 { "empty" } else { "header" }
      draw-box(cell-key(i), name, c0, c1, center, state, none, none, false)
    } else {
      let state = if cell == none {
        "empty"
      } else if cell.at("tombstone", default: false) {
        "tombstone"
      } else { "occupied" }
      let label = if state == "occupied" {
        cell.at("label", default: str(cell.key))
      } else { none }
      let value = if state == "occupied" { cell.at("value", default: none) } else { none }
      draw-box(cell-key(i), name, c0, c1, center, state, label, value, false)
    }
  }

  // --- re-stroke highlighted array cells on top ---
  // Array cells form a contiguous row/column sharing edges, drawn in
  // index order, so cell i+1's (default) border is painted over cell i's
  // shared edge — clipping a highlight applied to cell i. Redraw the
  // border of any cell carrying an explicit stroke override, on top of
  // every neighbour, so a probe/landing/miss highlight stays crisp on
  // all four sides. Stroke-only (no fill) leaves the content untouched.
  for i in range(m) {
    let s = _merge-into(default-node-style, snapshot.nodes.at(cell-key(i), default: (:)))
    if "stroke" in s and not s.at("hide", default: false) {
      let (c0, c1, _) = _cell-geom(i, orientation, dims)
      draw.rect(c0, c1, fill: none, stroke: s.stroke)
    }
  }

  // --- chain entry boxes (drawn after cells so links tuck under them) ---
  if strategy == "chaining" {
    for (i, chain) in cells.enumerate() {
      for (j, entry) in chain.enumerate() {
        let ec = _entry-center(i, j, orientation, dims)
        let c0 = (ec.at(0) - dims.ehw, ec.at(1) - dims.ehh)
        let c1 = (ec.at(0) + dims.ehw, ec.at(1) + dims.ehh)
        let name = cell-prefix + "c" + str(i) + "-" + str(j)
        let label = entry.at("label", default: str(entry.key))
        draw-box(entry-key(i, j), name, c0, c1, ec, "entry", label, entry.at("value", default: none), true)
      }
    }
  }

  // --- phantom chain cell ---
  // A single empty "null" cell hung one past the tail of a bucket (`(bucket,
  // depth)`), with a link into it. It has no structural entry — it's the slot
  // a failed chaining lookup falls off the end into, so the miss can ring an
  // empty cell instead of the (keyless) bucket header. Stylable via its
  // `entry-key(bucket, depth)` like any entry (the miss frame rings it in
  // `danger-stroke`). Drawn link-then-box so the arrowhead tucks under, matching
  // the real chain.
  let phantom = tbl.at("phantom", default: none)
  if strategy == "chaining" and phantom != none {
    let (i, d) = (phantom.bucket, phantom.depth)
    let ec = _entry-center(i, d, orientation, dims)
    let from = if d == 0 {
      _cell-chain-exit(i, orientation, dims)
    } else {
      let pc = _entry-center(i, d - 1, orientation, dims)
      if orientation == "vertical" { (pc.at(0) + dims.ehw, pc.at(1)) } else { (pc.at(0), pc.at(1) - dims.ehh) }
    }
    let top = if orientation == "vertical" { (ec.at(0) - dims.ehw, ec.at(1)) } else { (ec.at(0), ec.at(1) + dims.ehh) }
    let lk = entry-key(i, d)
    let ls = _merge-into(default-edge-style, snapshot.edges.at(lk, default: (:)))
    if not ls.at("hide", default: false) {
      draw.line(
        from,
        top,
        stroke: ls.at("stroke", default: chain-stroke),
        mark: (end: ">", fill: _stroke-paint(ls.at("stroke", default: chain-stroke))),
      )
    }
    let c0 = (ec.at(0) - dims.ehw, ec.at(1) - dims.ehh)
    let c1 = (ec.at(0) + dims.ehw, ec.at(1) + dims.ehh)
    draw-box(lk, cell-prefix + "c" + str(i) + "-" + str(d), c0, c1, ec, "empty", none, none, true)
  }

  // --- index labels ---
  for i in range(m) {
    let (pos, anchor) = _index-label-pos(i, orientation, strategy, dims)
    _haloed(
      draw,
      pos,
      text(size: 0.75em, fill: index-fill, str(i)),
      render-theme,
      anchor: anchor,
    )
  }

  // --- hash-box overlay ---
  let hb = tbl.at("hash-box", default: none)
  if hb != none {
    let idx = hb.index
    let (bc0, bc1, bcenter) = _cell-geom(idx, orientation, dims)
    // A "ghost" hash box reserves the box's exact footprint but draws nothing
    // visible: no frame, hidden (still laid-out) text, no arrow. The walk-based
    // displays put a ghost box on their leading pre-hash frame so the canvas
    // bounds — and hence the table's on-slide position — don't jump when the
    // real hash box appears on the next subslide.
    let ghost = hb.at("ghost", default: false)
    let hb-stroke = if ghost { none } else {
      render-theme.at("hash-box-stroke", default: render-theme.node-stroke)
    }
    let hb-fill = if ghost { none } else {
      render-theme.at("hash-box-fill", default: white)
    }
    // Double hashing carries a second-hash line (the step size); other
    // strategies show the single hash line.
    let expr2 = hb.at("expr2", default: none)
    let body = if expr2 == none {
      [h(#hb.key) = #hb.expr = #text(weight: "bold")[#hb.index]]
    } else {
      stack(
        dir: ttb,
        spacing: 0.35em,
        [h₁(#hb.key) = #hb.expr = #text(weight: "bold")[#hb.index]],
        [h₂(#hb.key) = #expr2 = #text(weight: "bold")[#hb.step]],
      )
    }
    // `hide` keeps the content's layout footprint (so the frame sizes and the
    // cetz bounds are identical to a visible box) while rendering nothing.
    let body = if ghost { hide(body) } else { body }
    let arrow-stroke = render-theme.at("attention-stroke", default: (paint: rgb("#ffcd00"), thickness: 2pt))
    if orientation == "vertical" {
      // Box to the left of the target cell, arrow pointing right.
      let anchor-pt = (bc0.at(0) - 1.6, bcenter.at(1))
      draw.content(
        anchor-pt,
        anchor: "east",
        frame: "rect",
        fill: hb-fill,
        stroke: hb-stroke,
        padding: 0.14,
        text(size: 0.85em, body),
      )
      if not ghost {
        draw.line(
          (bc0.at(0) - 1.55, bcenter.at(1)),
          (bc0.at(0), bcenter.at(1)),
          stroke: arrow-stroke,
          mark: (end: ">"),
        )
      }
    } else {
      // Box above the target cell (clamped to stay over the array),
      // arrow pointing down.
      let box-x = calc.max(1.1, calc.min((m - 1 + 0.5) * dims.cw - 0.1, bcenter.at(0)))
      let box-y = dims.ch + 1.5
      draw.content(
        (box-x, box-y),
        anchor: "south",
        frame: "rect",
        fill: hb-fill,
        stroke: hb-stroke,
        padding: 0.14,
        text(size: 0.85em, body),
      )
      if not ghost {
        draw.line(
          (box-x, box-y),
          (bcenter.at(0), dims.ch + 0.05),
          stroke: arrow-stroke,
          mark: (end: ">"),
        )
      }
    }
  }
}

// ===================================================================
// Hash-map-bound wrappers over the generic kernel
// ===================================================================

// The draw backend the hash-map renderer injects into the generic
// `Renderer`. Wrapped in a singleton dict `(fn: ..)` so typsy doesn't
// self-inject on the function-typed `draw` field (see `anim-core.typ`).
#let _draw-hashmap-backend = (
  fn: (structure, snapshot, dns, des, rt) => draw-hashmap(
    structure,
    snapshot,
    default-node-style: dns,
    default-edge-style: des,
    render-theme: rt,
  ),
)

/// Build a hash-map #raw("Renderer") seeded with one blank initial frame,
/// bound to the @@draw-hashmap() backend. Thin wrapper over the generic
/// #raw("make-renderer") in #raw("anim-core.typ") that injects the
/// hash-map draw backend.
///
/// -> Renderer
#let make-hashmap-renderer(
  /// The positioned table to render.
  /// -> dictionary
  tbl,
  /// Default node-style overrides applied before per-snapshot overrides.
  /// -> dictionary
  default-node-style: (:),
  /// Default edge-style overrides applied before per-snapshot overrides.
  /// -> dictionary
  default-edge-style: (:),
  /// When #raw("true"), new frames inherit the previous frame's style.
  /// -> bool
  sticky: true,
  /// Render-theme override; #raw("auto") reads state at layout time.
  /// -> auto | dictionary
  theme: auto,
) = core.make-renderer(
  tbl,
  _draw-hashmap-backend,
  default-node-style: default-node-style,
  default-edge-style: default-edge-style,
  sticky: sticky,
  theme: theme,
)
