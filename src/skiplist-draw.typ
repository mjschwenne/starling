// Skip-list rendering backend — the skip-list-specific layer on top of
// the structure-agnostic kernel in `anim-core.typ`. Holds the cetz
// drawing (`draw-skiplist`), box/pointer identity helpers, and the
// skip-list-bound `make-skiplist-renderer` wrapper that injects
// `draw-skiplist` into the generic `Renderer`.
//
// This is the skip-list analog of `array-draw.typ` / `hashmap-draw.typ`:
// it knows how to *draw* a sparse grid of node towers with horizontal
// forward pointers, but nothing about search / insert / delete — that
// lives in the `Skiplist` class in `skiplist.typ`. The two are
// deliberately split. Modeled on `array-draw.typ` (fixed cells, snapshot
// styling, "fit" sizing, occlusion drawing order), but with skip-list
// geometry:
//
//   * A skip list is a *sparse grid*. Columns are the sorted nodes: a
//     left HEADER sentinel at column 0, then one column per key
//     (columns 1..n), then an optional NIL tail sentinel at column n+1.
//     Rows are levels, with LEVEL 0 AT THE BOTTOM and towers rising.
//   * A node of tower `height` h occupies boxes in the bottom h rows of
//     its column; absent levels leave gaps (unlike the array backend,
//     where every column has a cell in every row).
//   * FORWARD POINTERS are horizontal arrows at each level, from a box's
//     right face to the LEFT face of the next node present at that level
//     — skipping over columns whose towers don't reach that level. This
//     is the one drawing primitive the array backend lacks (its arrows
//     are vertical, between stacked rows).
//
// Box / pointer identity
// ----------------------
//   * Boxes are keyed by `"b<col>:<level>"`, built by `sl-box-key(col,
//     level)`. Styled via the snapshot's `nodes` slot like any node.
//   * Forward pointers are keyed by their SOURCE `"f<col>:<level>"`
//     (the pointer leaving `col` at `level`; its target is derived),
//     built by `sl-forward-key(col, level)`. Styled via the snapshot's
//     `edges` slot like a graph edge / chain link.
// Snapshot dicts (from `anim-core.typ`) use these strings as keys; the
// core never interprets them.
//
// Positioned-table input
// ----------------------
// `draw-skiplist` consumes an opaque "table" dict (built by the
// `Skiplist` class):
//   (
//     cols: array of column dicts, index 0 = header, 1..n = data, and
//       (n+1 = nil when `nil` is true). Each column:
//         (
//           kind:        "header" | "data" | "nil",
//           height:      int,          // boxes drawn in this tower
//           key:         any,          // display value (data); ignored
//                                      // for header/nil
//           label:       content|none, // optional explicit box label
//           state:       "live" | "ghost",
//                          // "ghost" reserves the column's horizontal
//                          // slot (so neighbours don't shift) but draws
//                          // nothing — used to hold an about-to-appear
//                          // node's place during the search phase.
//           link-height: int,          // levels this column is LINKED
//                                      // into the list for pointer
//                                      // routing (0..link-height-1);
//                                      // defaults to `height`. Lets an
//                                      // insert splice / delete unlink
//                                      // animate level by level while
//                                      // the tower stays drawn.
//         )
//     cell-width:   auto | "fit" | number,   // box sizing (see array-draw)
//     measure-cells: array,                  // fit-measurement superset
//   )
// The number of levels drawn is derived from the live data columns'
// heights (`_levels`), so the header/nil sentinels are exactly as tall as
// the list currently reaches — level 0 is pinned at y = 0, so growing a
// level adds a row on TOP and never shifts existing boxes.

#import "@preview/typsy:0.2.2": *
#import "@preview/cetz:0.5.2"
#import "./anim-core.typ": *
#import "./anim-core.typ" as core

// ===================================================================
// Box / pointer identity
// ===================================================================

/// Canonical snapshot key for the box at `level` of column `col`
/// (0 = header, 1..n = data, n+1 = nil), e.g.
/// #raw("sl-box-key(2, 0)") -> #raw("\"b2:0\""). Styled via the
/// snapshot's #raw("nodes") slot like any node.
///
/// -> str
#let sl-box-key(
  /// Column index (0 = header).
  /// -> int
  col,
  /// Level within the tower (0 = bottom).
  /// -> int
  level,
) = "b" + str(col) + ":" + str(level)

/// Canonical snapshot key for the forward pointer LEAVING column `col`
/// at `level` (its target — the next node present at that level — is
/// derived by the backend), e.g. #raw("sl-forward-key(0, 2)") ->
/// #raw("\"f0:2\""). Styled via the snapshot's #raw("edges") slot like a
/// graph edge.
///
/// -> str
#let sl-forward-key(
  /// Source column index.
  /// -> int
  col,
  /// Level of the pointer (0 = bottom).
  /// -> int
  level,
) = "f" + str(col) + ":" + str(level)

/// The fully-qualified cetz anchor name for the box at `level` of column
/// `col` drawn by @@draw-skiplist(). Use it to attach your own callouts
/// when you call #raw("draw-skiplist") inside your own
/// #raw("cetz.canvas"). The #raw("prefix") must match the
/// #raw("cell-prefix") passed to #raw("draw-skiplist"). Sub-anchors
/// follow (e.g. #raw("sl-box-anchor(2, 0) + \".north\"")).
///
/// -> str
#let sl-box-anchor(
  /// Column index (0 = header).
  /// -> int
  col,
  /// Level within the tower (0 = bottom).
  /// -> int
  level,
  /// Per-box cetz name prefix; must match #raw("draw-skiplist")'s
  /// #raw("cell-prefix").
  /// -> str
  prefix: "slbox-",
) = prefix + str(col) + "-" + str(level)

/// The fully-qualified cetz anchor name for the forward-pointer line
/// leaving column `col` at `level` drawn by @@draw-skiplist() — the
/// pointer counterpart of @@sl-box-anchor().
///
/// -> str
#let sl-forward-anchor(
  /// Source column index.
  /// -> int
  col,
  /// Level of the pointer (0 = bottom).
  /// -> int
  level,
  /// Per-element cetz name prefix; must match #raw("draw-skiplist")'s
  /// #raw("cell-prefix").
  /// -> str
  prefix: "slbox-",
) = prefix + "fwd-" + str(col) + "-" + str(level)

// ===================================================================
// Layout geometry
// ===================================================================
//
// All measurements are in cetz units. Columns run left->right sharing a
// fixed pitch (box width + a gap so the horizontal pointers are
// visible); levels stack bottom->top (level 0 at y = 0, rising). The
// layout is fully determined by the column/level indices and the
// resolved box size, so callers never supply positions.

// Default box footprint floors. `draw-skiplist` widens `bw`/`bh` to fit
// longer labels in "fit" mode but never below these.
#let _BW = 1.2
#let _BH = 0.7
// Horizontal gap between adjacent columns (room for a pointer + its
// arrowhead in the clear band between towers).
#let _COL-GAP = 1.0
// Vertical gap between successive levels of one tower.
#let _ROW-GAP = 0.35
// Padding (per side) between a label and its box edge when sizing to fit.
#let _PAD-X = 0.22
#let _PAD-Y = 0.15

// The visible content of one box: the node's display value (or an
// explicit `label` override). Header / nil sentinels pass their own
// content (or `none`).
#let _box-body(value, text-fill) = if value == none {
  none
} else {
  text(weight: "bold", fill: text-fill, value)
}

// Number of levels drawn: the tallest LIVE data tower (at least 1).
// Ghost columns don't count — they reserve a horizontal slot only — so
// an about-to-appear node doesn't inflate the header height during the
// search phase.
#let _levels(cols) = {
  let m = 1
  for c in cols {
    if c.kind == "data" and c.at("state", default: "live") == "live" {
      m = calc.max(m, c.height)
    }
  }
  m
}

// Resolve box dimensions for one render (mirrors `array-draw`'s
// `_resolve-dims`): `auto` = fixed footprint (never measures), `"fit"` =
// grow to the widest/tallest label (floored, REQUIRES a layout context),
// a number pins the width. `measure-cells` (when non-empty) is measured
// instead of this frame's own labels, so every frame of an animation
// sizes to the same superset and the grid never jumps.
#let _resolve-dims(cols, text-fill, cell-width, measure-cells: ()) = {
  let bw = _BW
  let bh = _BH
  if cell-width == "fit" {
    let cells = if measure-cells.len() > 0 {
      measure-cells
    } else {
      cols.map(c => (value: c.at("label", default: none))).filter(c => c.value != none)
    }
    let max-w = 0
    let max-h = 0
    for cell in cells {
      let body = _box-body(cell.at("value", default: none), text-fill)
      if body != none {
        let d = measure(body)
        max-w = calc.max(max-w, d.width / 1cm)
        max-h = calc.max(max-h, d.height / 1cm)
      }
    }
    bw = calc.max(_BW, max-w + 2 * _PAD-X)
    bh = calc.max(_BH, max-h + 2 * _PAD-Y)
  } else if cell-width != auto {
    bw = cell-width
  }
  (bw: bw, bh: bh)
}

// `(corner0, corner1, center)` of the box at column `c`, level `L`.
#let _box(c, L, dims) = {
  let x0 = c * (dims.bw + _COL-GAP)
  let x1 = x0 + dims.bw
  let y0 = L * (dims.bh + _ROW-GAP)
  let y1 = y0 + dims.bh
  ((x0, y0), (x1, y1), (x0 + dims.bw / 2, y0 + dims.bh / 2))
}

// `(corner0, corner1, center)` of a nil sentinel spanning all `levels`
// rows of column `c` as ONE tall box.
#let _nil-box(c, levels, dims) = {
  let x0 = c * (dims.bw + _COL-GAP)
  let x1 = x0 + dims.bw
  let y0 = 0
  let y1 = (levels - 1) * (dims.bh + _ROW-GAP) + dims.bh
  ((x0, y0), (x1, y1), (x0 + dims.bw / 2, (y0 + y1) / 2))
}

// ===================================================================
// draw-skiplist
// ===================================================================

// The paint (color) of a stroke spec, for filling a pointer's arrowhead
// to match its line (mirrors the array / graph / hash-map backends).
#let _stroke-paint(s) = {
  if s == auto or s == none { return black }
  let st = stroke(s)
  if st.paint == auto { black } else { st.paint }
}

// A filled `note-bg` halo behind a small piece of content, so labels
// stay legible over pointer lines beneath them (mirrors array-draw).
#let _haloed(draw, pos, body, render-theme, anchor: "center") = draw.content(
  pos,
  anchor: anchor,
  frame: "rect",
  fill: render-theme.note-bg,
  stroke: none,
  padding: 0.05,
  body,
)

// Whether column `c` (a resolved col dict at index `ci`) is LINKED into
// the list at level `L` — i.e. participates in pointer routing there.
// Header and nil sentinels span every level; a data column is linked at
// levels below its `link-height` when live (never when ghost).
#let _linked-at(col, L) = {
  if col.kind == "header" or col.kind == "nil" { return true }
  if col.at("state", default: "live") != "live" { return false }
  L < col.at("link-height", default: col.height)
}

/// Emit the cetz draw commands for one styled snapshot of a skip list,
/// _without_ wrapping them in a #raw("cetz.canvas"). The caller wraps
/// the canvas — use this to add your own cetz annotations alongside the
/// towers — see @@sl-box-anchor().
///
/// Draw order follows the array backend's occlusion trick: forward
/// pointers first (so the boxes drawn afterwards occlude each line where
/// it meets a box, leaving a clean arrowhead in the gap), then the box
/// rectangles, then a re-stroke pass for highlighted boxes, then the
/// labels. The theme argument is a merged render-theme plus the per-DS
/// skip-list palette (passed together as one dict).
///
/// -> content
#let draw-skiplist(
  /// The positioned table — see the module header for its shape.
  /// -> dictionary
  tbl,
  /// Style overlay for this snapshot. Use #raw("blank-snapshot()") for
  /// an unstyled table.
  /// -> Snapshot
  snapshot,
  /// Default node-style overrides applied before per-box overrides.
  /// -> dictionary
  default-node-style: (:),
  /// Default edge-style overrides applied before per-pointer overrides.
  /// -> dictionary
  default-edge-style: (:),
  /// Structural defaults plus the skip-list palette, merged into one
  /// dict.
  /// -> dictionary
  render-theme: default-render-theme,
  /// Per-box cetz element-name prefix. Must match @@sl-box-anchor()'s
  /// #raw("prefix").
  /// -> str
  cell-prefix: "slbox-",
) = {
  import cetz.draw
  let cols = tbl.cols
  let levels = _levels(cols)

  let dims = _resolve-dims(
    cols,
    render-theme.node-text-fill,
    tbl.at("cell-width", default: auto),
    measure-cells: tbl.at("measure-cells", default: ()),
  )

  // Palette fallbacks. `render-theme` carries both the structural keys
  // and the skip-list keys (the class merges them before calling), but
  // default each so a bare `draw-skiplist` call still works.
  let header-fill = render-theme.at("header-fill", default: rgb("#eef4fb"))
  let header-stroke = render-theme.at("header-stroke", default: render-theme.node-stroke)
  let header-text-fill = render-theme.at("header-text-fill", default: render-theme.node-text-fill)
  let nil-fill = render-theme.at("nil-fill", default: rgb("#f2f2f2"))
  let nil-stroke = render-theme.at("nil-stroke", default: render-theme.node-stroke)
  let nil-text-fill = render-theme.at("nil-text-fill", default: rgb("#666666"))
  let index-fill = render-theme.at("index-fill", default: rgb("#888888"))
  let pointer-stroke = render-theme.at("pointer-stroke", default: render-theme.edge-stroke)

  // Center-left / center of a box (or the nil sentinel) at (col, level),
  // used as pointer endpoints. Returns `(left, right, center)` points.
  let faces(ci, L) = {
    if cols.at(ci).kind == "nil" {
      let (c0, c1, ctr) = _nil-box(ci, levels, dims)
      // A nil pointer lands on the left face at the level's own y.
      let y = L * (dims.bh + _ROW-GAP) + dims.bh / 2
      ((c0.at(0), y), (c1.at(0), y), (ctr.at(0), y))
    } else {
      let (c0, c1, ctr) = _box(ci, L, dims)
      ((c0.at(0), ctr.at(1)), (c1.at(0), ctr.at(1)), ctr)
    }
  }

  // --- forward pointers first (occluded by boxes drawn afterwards) ---
  // For each level, walk the columns present (linked) at that level in
  // order and connect each to the next one.
  for L in range(levels) {
    let present = range(cols.len()).filter(ci => _linked-at(cols.at(ci), L))
    for i in range(present.len() - 1) {
      let sc = present.at(i)
      let tc = present.at(i + 1)
      let fk = sl-forward-key(sc, L)
      let es = _merge-into(default-edge-style, snapshot.edges.at(fk, default: (:)))
      if es.at("hide", default: false) { continue }
      let (_, sright, _) = faces(sc, L)
      let (tleft, _, _) = faces(tc, L)
      let stroke-c = es.at("stroke", default: pointer-stroke)
      draw.line(
        sright,
        tleft,
        stroke: stroke-c,
        mark: (end: ">", fill: _stroke-paint(stroke-c)),
        name: sl-forward-anchor(sc, L, prefix: cell-prefix),
      )
    }
  }

  // Draw one box with a resolved style overlay. Returns nothing.
  let draw-box(key, name, c0, c1, center, base-fill, base-stroke, base-text, value) = {
    let s = _merge-into(default-node-style, snapshot.nodes.at(key, default: (:)))
    if s.at("hide", default: false) { return }
    let fill-c = s.at("fill", default: base-fill)
    let stroke-c = s.at("stroke", default: base-stroke)
    draw.rect(c0, c1, fill: fill-c, stroke: stroke-c, name: name)
    let tf = s.at("text-fill", default: base-text)
    let lbl = s.at("label", default: value)
    let body = _box-body(lbl, tf)
    if body != none { draw.content(center, body) }
    // Operation note (gold), just above the box.
    let note = s.at("note", default: none)
    if note != none {
      let nf = s.at("note-fill", default: render-theme.note-fill)
      _haloed(
        draw,
        (center.at(0), c1.at(1) + 0.22),
        text(fill: nf, size: 0.8em, note),
        render-theme,
        anchor: "south",
      )
    }
  }

  // --- boxes / towers ---
  for (ci, col) in cols.enumerate() {
    let state = col.at("state", default: "live")
    if col.kind == "nil" {
      let (c0, c1, center) = _nil-box(ci, levels, dims)
      if state == "ghost" {
        draw.rect(c0, c1, fill: none, stroke: none) // reserve slot, draw nothing
      } else {
        draw-box(
          sl-box-key(ci, 0),
          cell-prefix + str(ci) + "-0",
          c0,
          c1,
          center,
          nil-fill,
          nil-stroke,
          nil-text-fill,
          col.at("label", default: "NIL"),
        )
      }
      continue
    }
    // A ghost column reserves its horizontal slot at the current level
    // count, drawing nothing (an invisible rect still contributes to the
    // canvas bounds, so neighbours don't shift when it later appears).
    let tower = if col.kind == "header" { levels } else { col.height }
    for L in range(tower) {
      let (c0, c1, center) = _box(ci, L, dims)
      if state == "ghost" {
        draw.rect(c0, c1, fill: none, stroke: none)
        continue
      }
      let (bf, bs, bt, val) = if col.kind == "header" {
        (header-fill, header-stroke, header-text-fill, col.at("label", default: none))
      } else {
        (render-theme.node-fill, render-theme.node-stroke, render-theme.node-text-fill, col.at("label", default: none))
      }
      draw-box(
        sl-box-key(ci, L),
        cell-prefix + str(ci) + "-" + str(L),
        c0,
        c1,
        center,
        bf,
        bs,
        bt,
        val,
      )
    }
  }

  // --- re-stroke highlighted boxes on top ---
  // Boxes in one tower are separated by `_ROW-GAP`, so they don't clip
  // each other; but a pointer line can cross a box edge, and adjacent
  // columns' highlights read cleaner drawn last. Redraw the border of any
  // box carrying an explicit stroke override, on top.
  for (ci, col) in cols.enumerate() {
    if col.at("state", default: "live") != "live" { continue }
    if col.kind == "nil" {
      let key = sl-box-key(ci, 0)
      let s = _merge-into(default-node-style, snapshot.nodes.at(key, default: (:)))
      if "stroke" in s and not s.at("hide", default: false) {
        let (c0, c1, _) = _nil-box(ci, levels, dims)
        draw.rect(c0, c1, fill: none, stroke: s.stroke)
      }
      continue
    }
    let tower = if col.kind == "header" { levels } else { col.height }
    for L in range(tower) {
      let key = sl-box-key(ci, L)
      let s = _merge-into(default-node-style, snapshot.nodes.at(key, default: (:)))
      if "stroke" in s and not s.at("hide", default: false) {
        let (c0, c1, _) = _box(ci, L, dims)
        draw.rect(c0, c1, fill: none, stroke: s.stroke)
      }
    }
  }

  // --- column captions (below level 0) ---
  // The header gets a "head" caption; data columns show nothing extra
  // (the key is in every box). Ghost columns stay silent.
  for (ci, col) in cols.enumerate() {
    if col.at("state", default: "live") != "live" { continue }
    let cap = if col.kind == "header" { "head" } else { none }
    if cap != none {
      let (c0, _, center) = _box(ci, 0, dims)
      _haloed(
        draw,
        (center.at(0), c0.at(1) - 0.3),
        text(size: 0.75em, fill: index-fill, cap),
        render-theme,
        anchor: "center",
      )
    }
  }
}

// ===================================================================
// Skip-list-bound wrappers over the generic kernel
// ===================================================================

// The draw backend the skip-list renderer injects into the generic
// `Renderer`. Wrapped in a singleton dict `(fn: ..)` so typsy doesn't
// self-inject on the function-typed `draw` field (see `anim-core.typ`).
#let _draw-skiplist-backend = (
  fn: (structure, snapshot, dns, des, rt) => draw-skiplist(
    structure,
    snapshot,
    default-node-style: dns,
    default-edge-style: des,
    render-theme: rt,
  ),
)

/// Build a skip-list #raw("Renderer") seeded with one blank initial
/// frame, bound to the @@draw-skiplist() backend. Thin wrapper over the
/// generic #raw("make-renderer") in #raw("anim-core.typ") that injects
/// the skip-list draw backend.
///
/// -> Renderer
#let make-skiplist-renderer(
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
  _draw-skiplist-backend,
  default-node-style: default-node-style,
  default-edge-style: default-edge-style,
  sticky: sticky,
  theme: theme,
)
