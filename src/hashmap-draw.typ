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
//            array with an arrow to cell `index`.
//   )
// Coordinates are derived deterministically from `capacity` +
// `orientation`; unlike graphs there is no explicit layout to supply.

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

// ===================================================================
// Layout geometry
// ===================================================================
//
// All measurements are in cetz units. The layout is fully determined by
// the slot index and orientation, so callers never supply positions.

// Cell footprint. Horizontal: cells run left→right, each `_CW` wide and
// `_CH` tall, sharing edges into a contiguous array. Vertical: cells run
// top→bottom (a memory-diagram column), `_CW` wide and `_CH` tall.
#let _CW = 1.4
#let _CH = 1.0
// Chain-entry box half-extents and the pitch between successive entries.
#let _EHW = 0.55
#let _EHH = 0.34
#let _EPITCH = 1.02

// `(corner0, corner1, center)` of cell `i` for the given orientation.
#let _cell-geom(i, orientation) = {
  if orientation == "vertical" {
    let y0 = -(i + 1) * _CH
    let y1 = -i * _CH
    ((0, y0), (_CW, y1), (_CW / 2, -(i + 0.5) * _CH))
  } else {
    let x0 = i * _CW
    let x1 = (i + 1) * _CW
    ((x0, 0), (x1, _CH), ((i + 0.5) * _CW, _CH / 2))
  }
}

// Center of chaining entry `j` hanging off bucket `i`.
#let _entry-center(i, j, orientation) = {
  let (_, _, c) = _cell-geom(i, orientation)
  if orientation == "vertical" {
    // Entries extend rightward from the cell's east face.
    (_CW + 0.7 + j * (2 * _EHW + 0.5), c.at(1))
  } else {
    // Entries hang downward below the cell's south face.
    (c.at(0), -0.95 - j * _EPITCH)
  }
}

// The point on cell `i`'s face from which its chain (head pointer)
// departs, and the point at which the whole array's index label sits.
#let _cell-chain-exit(i, orientation) = {
  let (c0, c1, c) = _cell-geom(i, orientation)
  if orientation == "vertical" {
    (c1.at(0), c.at(1)) // east-center
  } else {
    (c.at(0), c0.at(1)) // south-center (c0 holds the lower y)
  }
}

#let _index-label-pos(i, orientation) = {
  let (c0, c1, c) = _cell-geom(i, orientation)
  if orientation == "vertical" {
    (-0.35, c.at(1)) // west of the column
  } else {
    (c.at(0), c0.at(1) - 0.35) // below the row
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
      let exit = _cell-chain-exit(i, orientation)
      for (j, _entry) in chain.enumerate() {
        let ec = _entry-center(i, j, orientation)
        let top = if orientation == "vertical" {
          (ec.at(0) - _EHW, ec.at(1))
        } else { (ec.at(0), ec.at(1) + _EHH) }
        let from = if j == 0 {
          exit
        } else {
          let pc = _entry-center(i, j - 1, orientation)
          if orientation == "vertical" {
            (pc.at(0) + _EHW, pc.at(1))
          } else { (pc.at(0), pc.at(1) - _EHH) }
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
    let (c0, c1, center) = _cell-geom(i, orientation)
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

  // --- chain entry boxes (drawn after cells so links tuck under them) ---
  if strategy == "chaining" {
    for (i, chain) in cells.enumerate() {
      for (j, entry) in chain.enumerate() {
        let ec = _entry-center(i, j, orientation)
        let c0 = (ec.at(0) - _EHW, ec.at(1) - _EHH)
        let c1 = (ec.at(0) + _EHW, ec.at(1) + _EHH)
        let name = cell-prefix + "c" + str(i) + "-" + str(j)
        let label = entry.at("label", default: str(entry.key))
        draw-box(entry-key(i, j), name, c0, c1, ec, "entry", label, entry.at("value", default: none), true)
      }
    }
  }

  // --- index labels ---
  for i in range(m) {
    _haloed(
      draw,
      _index-label-pos(i, orientation),
      text(size: 0.75em, fill: index-fill, str(i)),
      render-theme,
    )
  }

  // --- hash-box overlay ---
  let hb = tbl.at("hash-box", default: none)
  if hb != none {
    let idx = hb.index
    let (bc0, bc1, bcenter) = _cell-geom(idx, orientation)
    let hb-stroke = render-theme.at("hash-box-stroke", default: render-theme.node-stroke)
    let hb-fill = render-theme.at("hash-box-fill", default: white)
    let body = [h(#hb.key) = #hb.expr = #text(weight: "bold")[#hb.index]]
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
      draw.line(
        (bc0.at(0) - 1.55, bcenter.at(1)),
        (bc0.at(0), bcenter.at(1)),
        stroke: render-theme.at("attention-stroke", default: (paint: rgb("#ffcd00"), thickness: 2pt)),
        mark: (end: ">"),
      )
    } else {
      // Box above the target cell (clamped to stay over the array),
      // arrow pointing down.
      let box-x = calc.max(1.1, calc.min((m - 1 + 0.5) * _CW - 0.1, bcenter.at(0)))
      let box-y = _CH + 1.5
      draw.content(
        (box-x, box-y),
        anchor: "south",
        frame: "rect",
        fill: hb-fill,
        stroke: hb-stroke,
        padding: 0.14,
        text(size: 0.85em, body),
      )
      draw.line(
        (box-x, box-y),
        (bcenter.at(0), _CH + 0.05),
        stroke: render-theme.at("attention-stroke", default: (paint: rgb("#ffcd00"), thickness: 2pt)),
        mark: (end: ">"),
      )
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
