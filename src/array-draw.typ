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
//   * Chain entries (the "buckets" row kind — a chaining-hash-table view
//     of the count array) are keyed by `"<row>:<i>:<j>"` (bucket i, chain
//     depth j; 0 = head), built by `array-entry-key(row, i, j)`. Styled
//     via the snapshot's `nodes` slot like a cell.
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
//         kind:    "data" | "count" | "buckets",
//                                            // "count"/"buckets" cells use the
//                                            // count fill
//         chains:  array (buckets only) — one entry-list per header cell, each
//                    entry a cell dict; drawn as a chain hanging DOWN from the
//                    header (chaining-hash-table look). Keyed `array-entry-key`.
//         chain-depth: int (buckets only) — chain slots to reserve below the
//                    header row so the next row clears the deepest chain and the
//                    canvas stays a fixed height as chains grow.
//       )
//     arrows: array of arrow dicts (per-frame operation overlays):
//       (
//         id:   str,
//         from: (row: str, col: int, depth?: int),  // depth => a chain entry
//         to:   (row: str, col: int, depth?: int),
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

/// Canonical snapshot key for the chain entry at depth #raw("j") (0 = the
/// head) hanging below bucket header #raw("i") of row #raw("row") — the
/// "buckets" row kind (e.g. #raw("array-entry-key(\"buckets\", 2, 0)") ->
/// #raw("\"buckets:2:0\"")). The entry box is styled via the snapshot's
/// #raw("nodes") slot, just like a cell. Distinct from @@array-cell-key()
/// (two-part key) by its three parts.
///
/// -> str
#let array-entry-key(
  /// Row id (a "buckets" row).
  /// -> str
  row,
  /// Bucket (column) index within the row.
  /// -> int
  i,
  /// Depth in the chain (0 = head).
  /// -> int
  j,
) = row + ":" + str(i) + ":" + str(j)

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

/// The fully-qualified cetz anchor name for the chain entry at depth
/// #raw("j") (0 = head) of bucket #raw("i") in row #raw("row") drawn by
/// @@draw-array() — the counterpart of @@array-cell-anchor() for chain
/// entries (the "buckets" row kind). Sub-anchors follow.
///
/// -> str
#let array-entry-anchor(
  /// Row id (a "buckets" row).
  /// -> str
  row,
  /// Bucket (column) index within the row.
  /// -> int
  i,
  /// Depth in the chain (0 = head).
  /// -> int
  j,
  /// Per-cell name prefix; must match #raw("draw-array")'s
  /// #raw("cell-prefix").
  /// -> str
  prefix: "acell-",
) = prefix + row + "-" + str(i) + "-" + str(j)

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
// Vertical gap between a bucket header and its first chain entry, and
// between successive chain entries (the "buckets" row kind). One entry
// occupies `ch` + this gap of vertical space.
#let _CHAIN-GAP = 0.35

// The visible content of one cell: `value` on top, an optional smaller
// `sub` line below (used for the radix active-digit annotation). The two
// lines are laid out in a single-column grid with `align: center` so the
// (narrower) subscript is centered under the value rather than left-aligned
// beneath it.
#let _cell-body(value, sub, text-fill, sub-fill) = {
  if value == none {
    none
  } else if sub == none {
    text(weight: "bold", fill: text-fill, value)
  } else {
    grid(
      columns: 1,
      align: center,
      row-gutter: 0.15em,
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
    } else {
      // Include chain entries (the "buckets" row kind) so a bucket's
      // entries size to the same fit width as the array cells.
      rows.map(r => r.cells + r.at("chains", default: ()).flatten()).flatten()
    }
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

// The vertical space a bucket row reserves *below* its header cells for the
// hanging chains: `depth` entries, each `ch` tall on `_CHAIN-GAP` pitch,
// plus the first `_CHAIN-GAP` gap under the header. Zero for other rows.
#let _chain-reserve(row, dims) = if row.at("kind", default: "data") == "buckets" {
  let depth = row.at("chain-depth", default: 0)
  if depth <= 0 { 0 } else { _CHAIN-GAP + depth * (dims.ch + _CHAIN-GAP) - _CHAIN-GAP }
} else { 0 }

// The y of each row's top edge, walking `rows` top→bottom. A "buckets" row
// consumes its header height plus the reserved chain region below it, so the
// next row clears the deepest chain (kept constant per animation via the
// row's `chain-depth`, so the canvas doesn't jump as chains grow).
#let _row-tops(rows, dims) = {
  let y = 0
  let tops = ()
  for row in rows {
    tops.push(y)
    y = y - dims.ch - _chain-reserve(row, dims) - dims.row-gap
  }
  tops
}

// `(corner0, corner1, center)` of the cell at column `c` whose row top is at
// `top` (from `_row-tops`).
#let _cell-box(top, c, dims) = {
  let x0 = c * dims.cw
  let x1 = (c + 1) * dims.cw
  ((x0, top - dims.ch), (x1, top), ((c + 0.5) * dims.cw, top - dims.ch / 2))
}

// `(corner0, corner1, center)` of chain entry `j` (0 = head) hanging below
// bucket header `i`, whose row top is at `header-top`. Entries share the
// array-cell footprint (`cw` × `ch`) and column, so a bucket's chain sits
// directly under its header and fits the same label width. Mirrors the
// hash-map backend's downward horizontal-chaining geometry.
#let _entry-box(header-top, i, j, dims) = {
  let header-bottom = header-top - dims.ch
  let top = header-bottom - _CHAIN-GAP - j * (dims.ch + _CHAIN-GAP)
  let x0 = i * dims.cw
  let x1 = (i + 1) * dims.cw
  ((x0, top - dims.ch), (x1, top), ((i + 0.5) * dims.cw, top - dims.ch / 2))
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

  let chain-stroke = render-theme.at("chain-stroke", default: rgb("#999999"))

  // Map row id -> its index in `rows`, so arrows can resolve endpoints.
  let row-index = (:)
  for (r, row) in rows.enumerate() { row-index.insert(row.id, r) }
  // Each row's top-edge y (accounts for bucket rows' reserved chain region).
  let tops = _row-tops(rows, dims)

  // Resolve an arrow endpoint `(row:, col:, depth?:)` to its box
  // `(c0, c1, center)`. A `depth` key targets a chain entry (the "buckets"
  // row kind); otherwise a plain cell.
  let endpoint-box(ep) = {
    let r = row-index.at(ep.row)
    let depth = ep.at("depth", default: none)
    if depth == none {
      _cell-box(tops.at(r), ep.col, dims)
    } else {
      _entry-box(tops.at(r), ep.col, depth, dims)
    }
  }

  // --- arrows first (occluded by cells / entries drawn afterwards) ---
  for arrow in arrows {
    let ak = array-arrow-key(arrow.id)
    let es = _merge-into(default-edge-style, snapshot.edges.at(ak, default: (:)))
    if es.at("hide", default: false) { continue }
    let (fc0, fc1, fctr) = endpoint-box(arrow.from)
    let (tc0, tc1, tctr) = endpoint-box(arrow.to)
    // Depart the source face pointing toward the target and land on the
    // target's near face, so the arrowhead sits in the gap between the boxes
    // (visible, not occluded). `c0` holds the lower y (box bottom), `c1` the
    // upper y (box top). Works for cells and chain entries alike.
    let going-down = tctr.at(1) <= fctr.at(1)
    let from-pt = (fctr.at(0), if going-down { fc0.at(1) } else { fc1.at(1) })
    let to-pt = (tctr.at(0), if going-down { tc1.at(1) } else { tc0.at(1) })
    let stroke-c = es.at("stroke", default: render-theme.edge-stroke)
    draw.line(
      from-pt,
      to-pt,
      stroke: stroke-c,
      mark: (end: ">", fill: _stroke-paint(stroke-c)),
    )
  }

  // --- chain links (structural connectors, occluded by the boxes) ---
  // A head pointer drops from each bucket header's south face into entry 0,
  // then a link from each entry into the next. Drawn before the boxes so the
  // boxes cover the line ends, leaving a clean arrowhead in each gap.
  for (r, row) in rows.enumerate() {
    if row.at("kind", default: "data") != "buckets" { continue }
    let r-top = tops.at(r)
    for (i, chain) in row.at("chains", default: ()).enumerate() {
      for j in range(chain.len()) {
        let (ec0, ec1, ectr) = _entry-box(r-top, i, j, dims)
        let to-pt = (ectr.at(0), ec1.at(1)) // entry top-center
        let from-pt = if j == 0 {
          let (hc0, _, hctr) = _cell-box(r-top, i, dims)
          (hctr.at(0), hc0.at(1)) // header bottom-center
        } else {
          let (pc0, _, pctr) = _entry-box(r-top, i, j - 1, dims)
          (pctr.at(0), pc0.at(1)) // previous entry bottom-center
        }
        draw.line(
          from-pt,
          to-pt,
          stroke: chain-stroke,
          mark: (end: ">", fill: _stroke-paint(chain-stroke)),
        )
      }
    }
  }

  // Draw one box (cell or chain entry) with a resolved style overlay. `kind`
  // is the structural cell kind ("data" / "count" / "buckets"); an empty cell
  // (no value) reads as a muted slot. Returns nothing; draws in place.
  let draw-box(key, name, c0, c1, center, kind, value, sub) = {
    let s = _merge-into(default-node-style, snapshot.nodes.at(key, default: (:)))
    if s.at("hide", default: false) { return }
    let base-fill = if value == none {
      empty-fill
    } else if kind == "count" or kind == "buckets" {
      count-fill
    } else { render-theme.node-fill }
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
      let (c0, c1, center) = _cell-box(tops.at(r), c, dims)
      let name = cell-prefix + row.id + "-" + str(c)
      draw-box(
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

  // --- chain entries (below the bucket headers) ---
  for (r, row) in rows.enumerate() {
    if row.at("kind", default: "data") != "buckets" { continue }
    let r-top = tops.at(r)
    for (i, chain) in row.at("chains", default: ()).enumerate() {
      for (j, entry) in chain.enumerate() {
        let (c0, c1, center) = _entry-box(r-top, i, j, dims)
        let name = cell-prefix + row.id + "-" + str(i) + "-" + str(j)
        draw-box(
          array-entry-key(row.id, i, j),
          name,
          c0,
          c1,
          center,
          "data",
          entry.at("value", default: none),
          entry.at("sub", default: none),
        )
      }
    }
  }

  // --- re-stroke highlighted cells on top ---
  // Cells in a row share edges (drawn in column order), so cell c+1's
  // default border paints over cell c's shared edge — clipping a highlight
  // on cell c. Redraw the border of any cell carrying an explicit stroke
  // override, on top of every neighbour, so a highlight stays crisp on all
  // four sides. Stroke-only (no fill) leaves the content untouched. (Chain
  // entries don't share edges — separated by `_CHAIN-GAP` — so they need no
  // re-stroke.)
  for (r, row) in rows.enumerate() {
    for (c, _cell) in row.cells.enumerate() {
      let key = array-cell-key(row.id, c)
      let s = _merge-into(default-node-style, snapshot.nodes.at(key, default: (:)))
      if "stroke" in s and not s.at("hide", default: false) {
        let (c0, c1, _) = _cell-box(tops.at(r), c, dims)
        draw.rect(c0, c1, fill: none, stroke: s.stroke)
      }
    }
  }

  // --- row labels (left of each row) ---
  for (r, row) in rows.enumerate() {
    let lbl = row.at("label", default: none)
    if lbl != none {
      let top = tops.at(r)
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
    let top = tops.at(r)
    for (c, _cell) in row.cells.enumerate() {
      let (_, _, center) = _cell-box(tops.at(r), c, dims)
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
