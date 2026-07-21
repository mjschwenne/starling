// Array rendering backend — the multi-row-array-specific layer on top of
// the structure-agnostic kernel in `anim-core.typ`. Holds the cetz
// drawing (`draw-array`), cell/arrow identity helpers, and the
// array-bound `make-array-renderer` wrapper that injects `draw-array`
// into the generic `Renderer`.
//
// This is the array analog of `tree-anim.typ` / `graph-draw.typ` /
// `hashmap-draw.typ`: it knows how to *draw* a set of parallel labeled
// rows of boxes (with per-frame arrows between cells) but nothing about
// sorting algorithms — that lives in the `Sort` class in `sort.typ`. The
// two are deliberately split. Modeled closely on `hashmap-draw.typ`
// (fixed cells, snapshot styling, "fit" sizing, occlusion drawing order).
//
// Node / edge identity
// --------------------
// A sort visualization is several parallel arrays (input / count /
// output, or per-pass count rows), so there is no single index space:
//   * Cells are keyed by `"<row>:<col>"` (e.g. "in:3", "count:5"),
//     built by `array-cell-key(row, col)`.
//   * Arrows (operation overlays between two cells) are keyed by an
//     opaque id string (`array-arrow-key(id)`), styled via the snapshot's
//     `edges` slot just like a graph edge or a chain link.
// Snapshot dicts (from `anim-core.typ`) use these strings as keys; the
// core never interprets them.
//
// Positioned-table input
// ----------------------
// `draw-array` consumes an opaque "table" dict (built by the `Sort`
// class):
//   (
//     rows: array of row dicts, stacked top->bottom in declared order:
//       (
//         id:      str,                      // "in" / "count" / "out" / ...
//         label:   content | none,           // row caption, drawn to the left
//         cells:   array of cell dicts:
//                    (value: content | none, sub: content | none)
//         indices: auto | array | none,      // auto = 0..n-1 below each cell;
//                                            // an array supplies custom labels;
//                                            // none draws no index row
//         kind:    "data" | "count",         // "count" cells use the count fill
//       )
//     arrows: array of arrow dicts (per-frame operation overlays):
//       (
//         id:   str,
//         from: (row: str, col: int),
//         to:   (row: str, col: int),
//       )
//     cell-width: auto | "fit" | number      // sizing (optional, default auto)
//   )
// Coordinates are derived deterministically from the row/column indices
// plus the resolved cell size; unlike graphs there is no explicit layout
// to supply.

#import "@preview/typsy:0.2.2": *
#import "@preview/cetz:0.5.2"
#import "./anim-core.typ": *
#import "./anim-core.typ" as core

// ===================================================================
// Node / edge identity
// ===================================================================

/// Canonical snapshot key for the cell at column #raw("col") of row
/// #raw("row") (e.g. #raw("array-cell-key(\"count\", 5)") -> #raw("\"count:5\"")).
///
/// -> str
#let array-cell-key(
  /// Row id.
  /// -> str
  row,
  /// Column index within the row.
  /// -> int
  col,
) = row + ":" + str(col)

/// Canonical snapshot key for the arrow with id #raw("id"). The arrow is
/// styled via the snapshot's #raw("edges") slot (stroke / mark / hide),
/// exactly like a graph edge. The id is opaque — the backend never
/// interprets it.
///
/// -> str
#let array-arrow-key(
  /// Opaque arrow id.
  /// -> str
  id,
) = id

/// The fully-qualified cetz anchor name for the cell at column
/// #raw("col") of row #raw("row") drawn by @@draw-array(). Use it to
/// attach your own callouts when you call #raw("draw-array") inside your
/// own #raw("cetz.canvas"). The #raw("prefix") must match the
/// #raw("cell-prefix") passed to #raw("draw-array"). Sub-anchors follow
/// (e.g. #raw("array-cell-anchor(\"in\", 3) + \".north\"")).
///
/// -> str
#let array-cell-anchor(
  /// Row id.
  /// -> str
  row,
  /// Column index within the row.
  /// -> int
  col,
  /// Per-cell name prefix; must match #raw("draw-array")'s
  /// #raw("cell-prefix").
  /// -> str
  prefix: "acell-",
) = prefix + row + "-" + str(col)

// ===================================================================
// Layout geometry
// ===================================================================
//
// All measurements are in cetz units. Rows stack top->bottom (row 0 at
// the top, y = 0, descending into negative y); cells within a row run
// left->right sharing edges into a contiguous array. The layout is fully
// determined by the row/column indices and the resolved cell size, so
// callers never supply positions.

// Default cell footprint floors. `draw-array` widens `cw`/`ch` to fit
// longer labels in "fit" mode but never below these, so short (numeric)
// tables render at the historical size (see `_resolve-dims`).
#let _CW = 1.2
#let _CH = 0.9
// Vertical clearance between one row's cells and the next: room for the
// index labels plus a comfortable arrow span.
#let _ROW-GAP = 1.15
// Padding (per side, cetz units) between a label and its box edge when
// sizing to fit.
#let _PAD-X = 0.22
#let _PAD-Y = 0.15

// The visible content of one cell: `value` on top, an optional smaller
// `sub` line below (used for the radix active-digit annotation).
#let _cell-body(value, sub, text-fill, sub-fill) = {
  if value == none {
    none
  } else if sub == none {
    text(weight: "bold", fill: text-fill, value)
  } else {
    stack(
      dir: ttb,
      spacing: 0.15em,
      text(weight: "bold", fill: text-fill, value),
      text(size: 0.7em, fill: sub-fill, sub),
    )
  }
}

// Resolve the layout dimensions for one render. `cell-width` selects the
// sizing mode (mirrors `hashmap-draw.typ`'s `_resolve-dims`):
//   * `auto`   — the historical fixed footprint. Never measures, so it is
//                safe outside a layout context.
//   * "fit"    — grow `cw`/`ch` to fit the widest/tallest cell body,
//                floored at the historical size. Calls `measure`, so it
//                REQUIRES a layout context (the `*-display` methods,
//                wrapped by the lib frame helpers, always supply one).
//   * a number — pin `cw` to that exact width (no measure).
// `measure-cells`, when non-empty, is the set of cells actually measured
// in "fit" mode instead of the frame's own `rows`. Animations pass the
// *global* set of cells across all frames here (see `_sort-make-frames-multi`
// in `sort.typ`), so every frame measures the same superset and `cw`/`ch`
// stay constant across the animation — the canvas never jumps as a running
// count grows wider than the widest value.
#let _resolve-dims(rows, text-fill, cell-width, measure-cells: ()) = {
  let cw = _CW
  let ch = _CH
  if cell-width == "fit" {
    let cells = if measure-cells.len() > 0 {
      measure-cells
    } else { rows.map(r => r.cells).flatten() }
    let max-w = 0
    let max-h = 0
    for cell in cells {
      let body = _cell-body(
        cell.at("value", default: none),
        cell.at("sub", default: none),
        text-fill,
        text-fill,
      )
      if body != none {
        let d = measure(body)
        max-w = calc.max(max-w, d.width / 1cm)
        max-h = calc.max(max-h, d.height / 1cm)
      }
    }
    cw = calc.max(_CW, max-w + 2 * _PAD-X)
    ch = calc.max(_CH, max-h + 2 * _PAD-Y)
  } else if cell-width != auto {
    cw = cell-width
  }
  (cw: cw, ch: ch, row-gap: _ROW-GAP)
}

// Row index (position in `rows`) -> the y of its top edge.
#let _row-top(r, dims) = -r * (dims.ch + dims.row-gap)

// `(corner0, corner1, center)` of the cell at column `c` of row index `r`.
#let _cell-geom(r, c, dims) = {
  let top = _row-top(r, dims)
  let x0 = c * dims.cw
  let x1 = (c + 1) * dims.cw
  ((x0, top - dims.ch), (x1, top), ((c + 0.5) * dims.cw, top - dims.ch / 2))
}

// ===================================================================
// draw-array
// ===================================================================

// The paint (color) of a stroke spec, for filling an arrow's arrowhead to
// match its line (mirrors the graph / hash-map backends' helper of the
// same name). Falls back to black for `auto`/`none`.
#let _stroke-paint(s) = {
  if s == auto or s == none { return black }
  let st = stroke(s)
  if st.paint == auto { black } else { st.paint }
}

// A filled `note-bg` halo behind a small piece of content, so index
// labels stay legible over any arrow line beneath them (mirrors the
// hash-map backend's `_haloed`).
#let _haloed(draw, pos, body, render-theme, anchor: "center") = draw.content(
  pos,
  anchor: anchor,
  frame: "rect",
  fill: render-theme.note-bg,
  stroke: none,
  padding: 0.05,
  body,
)

/// Emit the cetz draw commands for one styled snapshot of a multi-row
/// array, _without_ wrapping them in a #raw("cetz.canvas"). The caller
/// wraps the canvas — use this to add your own cetz annotations alongside
/// the rows — see @@array-cell-anchor().
///
/// Arrows are drawn first (so cells drawn afterwards occlude the line
/// where it enters a box, leaving a clean arrowhead in the inter-row
/// gap), then the cell rectangles, then a re-stroke pass for highlighted
/// cells (contiguous cells share edges, so a neighbour's border can clip a
/// highlight — redraw it on top), then row labels and index labels. The
/// theme argument is a merged render-theme plus the per-DS sort palette
/// (passed together as one dict).
///
/// -> content
#let draw-array(
  /// The positioned table — see the module header for its shape.
  /// -> dictionary
  tbl,
  /// Style overlay for this snapshot. Use #raw("blank-snapshot()") for an
  /// unstyled table.
  /// -> Snapshot
  snapshot,
  /// Default node-style overrides applied before per-cell overrides.
  /// -> dictionary
  default-node-style: (:),
  /// Default edge-style overrides applied before per-arrow overrides.
  /// -> dictionary
  default-edge-style: (:),
  /// Structural defaults plus the sort palette, merged into one dict.
  /// -> dictionary
  render-theme: default-render-theme,
  /// Per-cell cetz element-name prefix. Must match @@array-cell-anchor()'s
  /// #raw("prefix").
  /// -> str
  cell-prefix: "acell-",
) = {
  import cetz.draw
  let rows = tbl.rows
  let arrows = tbl.at("arrows", default: ())

  let dims = _resolve-dims(
    rows,
    render-theme.node-text-fill,
    tbl.at("cell-width", default: auto),
    measure-cells: tbl.at("measure-cells", default: ()),
  )

  // Palette fallbacks. `render-theme` carries both the structural keys and
  // the sort keys (the class merges them before calling), but default each
  // so a bare `draw-array` call still works.
  let empty-fill = render-theme.at("empty-fill", default: rgb("#f2f2f2"))
  let index-fill = render-theme.at("index-fill", default: rgb("#888888"))
  let row-label-fill = render-theme.at("row-label-fill", default: render-theme.node-text-fill)
  let count-fill = render-theme.at("count-fill", default: white)
  let sub-fill = render-theme.at("active-digit-fill", default: rgb("#2b6cb0"))

  // Map row id -> its index in `rows`, so arrows can resolve endpoints.
  let row-index = (:)
  for (r, row) in rows.enumerate() { row-index.insert(row.id, r) }

  // --- arrows first (occluded by cells drawn afterwards) ---
  for arrow in arrows {
    let ak = array-arrow-key(arrow.id)
    let es = _merge-into(default-edge-style, snapshot.edges.at(ak, default: (:)))
    if es.at("hide", default: false) { continue }
    let (fr, fc) = (row-index.at(arrow.from.row), arrow.from.col)
    let (tr, tc) = (row-index.at(arrow.to.row), arrow.to.col)
    let (_, _, from-c) = _cell-geom(fr, fc, dims)
    let (_, _, to-c) = _cell-geom(tr, tc, dims)
    // Depart the face of the source cell that points toward the target and
    // land on the target's near face, so the arrowhead sits in the gap
    // between the two rows (visible, not occluded by either box). Rows lower
    // in `rows` are further down the page, so a larger row index is below.
    let going-down = tr >= fr
    let from-y = if going-down { _row-top(fr, dims) - dims.ch } else { _row-top(fr, dims) }
    let to-y = if going-down { _row-top(tr, dims) } else { _row-top(tr, dims) - dims.ch }
    let from-pt = (from-c.at(0), from-y)
    let to-pt = (to-c.at(0), to-y)
    let stroke-c = es.at("stroke", default: render-theme.edge-stroke)
    draw.line(
      from-pt,
      to-pt,
      stroke: stroke-c,
      mark: (end: ">", fill: _stroke-paint(stroke-c)),
    )
  }

  // Draw one cell rectangle with a resolved style overlay. `kind` is the
  // structural cell kind ("data" / "count"); an empty cell (no value)
  // reads as a muted slot. Returns nothing; draws in place.
  let draw-cell(key, name, c0, c1, center, kind, value, sub) = {
    let s = _merge-into(default-node-style, snapshot.nodes.at(key, default: (:)))
    if s.at("hide", default: false) { return }
    let base-fill = if value == none {
      empty-fill
    } else if kind == "count" { count-fill } else { render-theme.node-fill }
    let fill-c = s.at("fill", default: base-fill)
    let stroke-c = s.at("stroke", default: render-theme.node-stroke)
    draw.rect(c0, c1, fill: fill-c, stroke: stroke-c, name: name)
    let tf = s.at("text-fill", default: render-theme.node-text-fill)
    let lbl = s.at("label", default: value)
    let body = _cell-body(lbl, sub, tf, sub-fill)
    if body != none { draw.content(center, body) }
    // Operation note (gold), just above the box.
    let note = s.at("note", default: none)
    if note != none {
      let nf = s.at("note-fill", default: render-theme.note-fill)
      _haloed(
        draw,
        (center.at(0), c1.at(1) + 0.24),
        text(fill: nf, size: 0.8em, note),
        render-theme,
        anchor: "south",
      )
    }
  }

  // --- cells ---
  for (r, row) in rows.enumerate() {
    let kind = row.at("kind", default: "data")
    for (c, cell) in row.cells.enumerate() {
      let (c0, c1, center) = _cell-geom(r, c, dims)
      let name = cell-prefix + row.id + "-" + str(c)
      draw-cell(
        array-cell-key(row.id, c),
        name,
        c0,
        c1,
        center,
        kind,
        cell.at("value", default: none),
        cell.at("sub", default: none),
      )
    }
  }

  // --- re-stroke highlighted cells on top ---
  // Cells in a row share edges (drawn in column order), so cell c+1's
  // default border paints over cell c's shared edge — clipping a highlight
  // on cell c. Redraw the border of any cell carrying an explicit stroke
  // override, on top of every neighbour, so a highlight stays crisp on all
  // four sides. Stroke-only (no fill) leaves the content untouched.
  for (r, row) in rows.enumerate() {
    for (c, _cell) in row.cells.enumerate() {
      let key = array-cell-key(row.id, c)
      let s = _merge-into(default-node-style, snapshot.nodes.at(key, default: (:)))
      if "stroke" in s and not s.at("hide", default: false) {
        let (c0, c1, _) = _cell-geom(r, c, dims)
        draw.rect(c0, c1, fill: none, stroke: s.stroke)
      }
    }
  }

  // --- row labels (left of each row) ---
  for (r, row) in rows.enumerate() {
    let lbl = row.at("label", default: none)
    if lbl != none {
      let top = _row-top(r, dims)
      draw.content(
        (-0.3, top - dims.ch / 2),
        anchor: "east",
        text(fill: row-label-fill, lbl),
      )
    }
  }

  // --- index labels (below each row's cells) ---
  for (r, row) in rows.enumerate() {
    let indices = row.at("indices", default: auto)
    if indices == none { continue }
    let top = _row-top(r, dims)
    for (c, _cell) in row.cells.enumerate() {
      let (_, _, center) = _cell-geom(r, c, dims)
      let lbl = if indices == auto { str(c) } else { indices.at(c, default: str(c)) }
      _haloed(
        draw,
        (center.at(0), top - dims.ch - 0.3),
        text(size: 0.75em, fill: index-fill, lbl),
        render-theme,
        anchor: "center",
      )
    }
  }
}

// ===================================================================
// Array-bound wrappers over the generic kernel
// ===================================================================

// The draw backend the array renderer injects into the generic
// `Renderer`. Wrapped in a singleton dict `(fn: ..)` so typsy doesn't
// self-inject on the function-typed `draw` field (see `anim-core.typ`).
#let _draw-array-backend = (
  fn: (structure, snapshot, dns, des, rt) => draw-array(
    structure,
    snapshot,
    default-node-style: dns,
    default-edge-style: des,
    render-theme: rt,
  ),
)

/// Build an array #raw("Renderer") seeded with one blank initial frame,
/// bound to the @@draw-array() backend. Thin wrapper over the generic
/// #raw("make-renderer") in #raw("anim-core.typ") that injects the array
/// draw backend.
///
/// -> Renderer
#let make-array-renderer(
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
  _draw-array-backend,
  default-node-style: default-node-style,
  default-edge-style: default-edge-style,
  sticky: sticky,
  theme: theme,
)
