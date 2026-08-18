// Array drawing backend.
//
// Draws several parallel labeled rows of boxes — input / count / output,
// or one count row per radix pass — with per-frame arrows between cells.
// Those arrows are the one primitive the tree, graph, and hash-map
// backends lack. It knows nothing about sorting *algorithms*; counting and
// radix live in `ds/sort.typ`.
//
// Element identity
// ----------------
// A sort visualization is several parallel arrays, so there is no single
// index space:
//   * a cell is keyed `"<row>:<col>"` ("in:3", "count:5"), built by
//     `cell-key(row, col)`;
//   * a chain entry — the "buckets" row kind, a chaining-hash-table view
//     of the count array — is keyed `"<row>:<i>:<j>"` (bucket i, chain
//     depth j, 0 = head), built by `entry-key(row, i, j)` and styled
//     through the snapshot's `nodes` slot like a cell;
//   * an arrow is keyed by its own opaque id and styled through the
//     snapshot's `edges` slot, exactly like a graph edge or a chain link.
// All three go through the shared `anchor` sanitizer for their cetz names:
// `anchor(cell-key("count", 5))` is "el-count-5".
//
// Positioned-table input
// ----------------------
// The backend consumes an opaque "table" dict, built by `sort.positioned`:
//
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
//                                            // "count"/"buckets" cells take the
//                                            // palette's count fill
//         chains:  array (buckets only) — one entry-list per header cell, each
//                    entry a cell dict; drawn as a chain hanging DOWN from the
//                    header. Keyed by `entry-key`.
//         chain-depth: int (buckets only) — chain slots to reserve below the
//                    header row, so the next row clears the deepest chain and
//                    the canvas keeps a fixed height as chains grow.
//       )
//     arrows: array of arrow dicts (per-frame operation overlays):
//       (
//         id:   str,
//         from: (row: str, col: int, depth?: int),  // depth => a chain entry
//         to:   (row: str, col: int, depth?: int),
//       )
//     cell-width: auto | "fit" | number      // sizing (optional, default auto)
//     measure-cells: array of cell dicts (optional) — the superset of bodies
//            an animation will ever show, so every frame fits to the same
//            footprint and the canvas never jumps as a running count grows
//            wider than the widest value.
//   )
//
// Coordinates are derived deterministically from the row/column indices
// plus the resolved cell size; unlike graphs there is no explicit layout
// to supply.

#import "@preview/cetz:0.5.2"
#import "../core/draw-util.typ": anchor, haloed, resolve-dims, stroke-paint
#import "../core/style.typ": merge-into
#import "../core/theme.typ": default-theme

// ===================================================================
// Cell / entry identity
// ===================================================================

/// The canonical snapshot key for the cell at column `col` of row `row` —
/// `cell-key("count", 5)` is `"count:5"`.
///
/// -> str
#let cell-key(
  /// Row id.
  /// -> str
  row,
  /// Column index within the row.
  /// -> int
  col,
) = row + ":" + str(col)

/// The canonical snapshot key for the chain entry at depth `j` (0 = the
/// head) below bucket header `i` of row `row` — the "buckets" row kind.
/// `entry-key("buckets", 2, 0)` is `"buckets:2:0"`. The entry box is
/// styled through the snapshot's `nodes` slot, just like a cell; its three
/// parts are what distinguish it from a two-part `cell-key`.
///
/// -> str
#let entry-key(
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

// ===================================================================
// Layout geometry
// ===================================================================
//
// All measurements are in cetz units. Rows stack top->bottom (row 0 at the
// top, y = 0, descending into negative y); cells within a row run left to
// right sharing edges into a contiguous array. The layout is fully
// determined by the row/column indices and the resolved cell size, so
// callers never supply positions.

// The default cell footprint floors. "fit" widens `cw`/`ch` to longer
// labels but never below these, so short numeric tables render at the
// historical size.
#let _CW = 1.2
#let _CH = 0.9
// Vertical clearance between one row's cells and the next: room for the
// index labels plus a comfortable arrow span.
#let _ROW-GAP = 1.15
// Vertical gap between a bucket header and its first chain entry, and
// between successive chain entries (the "buckets" row kind). One entry
// occupies `ch` plus this gap of vertical space.
#let _CHAIN-GAP = 0.35

// The visible content of one cell: `value` on top, an optional smaller
// `sub` line below (the radix active-digit annotation). The two lines go
// in a single-column grid with `align: center`, so the narrower subscript
// centers under the value rather than left-aligning beneath it.
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

// The body of a cell dict, for measuring. Both lines measure in the same
// fill — the colour doesn't change the metrics, and the sub fill isn't
// resolved yet at sizing time.
#let _measure-body(text-fill) = cell => _cell-body(
  cell.at("value", default: none),
  cell.at("sub", default: none),
  text-fill,
  text-fill,
)

// The vertical space a bucket row reserves *below* its header cells for
// the hanging chains: `depth` entries, each `ch` tall on `_CHAIN-GAP`
// pitch, plus the first `_CHAIN-GAP` gap under the header. Zero for other
// rows.
#let _chain-reserve(row, dims) = if row.at("kind", default: "data") == "buckets" {
  let depth = row.at("chain-depth", default: 0)
  if depth <= 0 { 0 } else {
    _CHAIN-GAP + depth * (dims.ch + _CHAIN-GAP) - _CHAIN-GAP
  }
} else { 0 }

// The y of each row's top edge, walking `rows` top->bottom. A "buckets"
// row consumes its header height plus the reserved chain region below it,
// so the next row clears the deepest chain (kept constant per animation
// via the row's `chain-depth`, so the canvas doesn't jump as chains grow).
#let _row-tops(rows, dims) = {
  let y = 0
  let tops = ()
  for row in rows {
    tops.push(y)
    y = y - dims.ch - _chain-reserve(row, dims) - dims.row-gap
  }
  tops
}

// `(corner0, corner1, center)` of the cell at column `c` whose row top is
// at `top` (from `_row-tops`).
#let _cell-box(top, c, dims) = {
  let x0 = c * dims.cw
  let x1 = (c + 1) * dims.cw
  ((x0, top - dims.ch), (x1, top), ((c + 0.5) * dims.cw, top - dims.ch / 2))
}

// `(corner0, corner1, center)` of chain entry `j` (0 = head) hanging below
// bucket header `i`, whose row top is at `header-top`. Entries share the
// array-cell footprint (`cw` x `ch`) and column, so a bucket's chain sits
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

/// Emit the cetz draw commands for one styled snapshot of a multi-row
/// array, _without_ wrapping them in a `cetz.canvas` — the caller owns the
/// canvas, so you can add your own annotations and anchor them with
/// `anchor(cell-key(row, col))`.
///
/// Arrows are drawn first, so the cells drawn afterwards occlude the line
/// where it enters a box and leave a clean arrowhead in the inter-row gap.
/// Then come the cell rectangles, then a re-stroke pass for highlighted
/// cells (contiguous cells share edges, so a neighbour's border can clip a
/// highlight — redraw it on top), then the row and index labels.
///
/// -> content
#let draw-array(
  /// The positioned table — see the module header for its shape.
  /// -> dictionary
  tbl,
  /// Style overlay for this snapshot; `blank-snapshot()` draws it
  /// unstyled.
  /// -> dictionary
  snapshot,
  /// Base cell styling, applied beneath the snapshot's per-cell styles.
  /// -> dictionary
  node-style: (:),
  /// Base arrow styling, applied beneath the snapshot's per-arrow styles.
  /// -> dictionary
  edge-style: (:),
  /// The full resolved theme. The backend reads `theme.render` and
  /// `theme.sort`.
  /// -> dictionary
  theme: default-theme,
  /// Wrap the whole table in a cetz group of this name, qualifying every
  /// element anchor under it — `anchor(cell-key(row, col), canvas: name)`.
  /// `none` draws into the enclosing canvas directly.
  /// -> none | str
  name: none,
) = {
  import cetz.draw
  let rt = theme.render
  let pal = theme.sort
  let rows = tbl.rows
  let arrows = tbl.at("arrows", default: ())

  // Default subjects for "fit" sizing: every cell of every row plus the
  // chain entries, so a bucket's entries size to the same width as the
  // array cells. An animation overrides them wholesale with its global
  // `measure-cells` superset.
  let dims = {
    let subjects = rows
      .map(r => r.cells + r.at("chains", default: ()).flatten())
      .flatten()
    let d = resolve-dims(
      subjects,
      _measure-body(rt.node-text-fill),
      tbl.at("cell-width", default: auto),
      floor-w: _CW,
      floor-h: _CH,
      measure-cells: tbl.at("measure-cells", default: ()),
    )
    (cw: d.w, ch: d.h, row-gap: _ROW-GAP)
  }

  // Map row id -> its index in `rows`, so arrows can resolve endpoints.
  let row-index = (:)
  for (r, row) in rows.enumerate() { row-index.insert(row.id, r) }
  // Each row's top-edge y (accounting for a bucket row's reserved chains).
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

  // Draw one box (cell or chain entry) with a resolved style overlay.
  // `kind` is the structural cell kind ("data" / "count" / "buckets"); an
  // empty cell (no value) reads as a muted slot.
  let draw-box(key, c0, c1, center, kind, value, sub) = {
    let s = merge-into(node-style, snapshot.nodes.at(key, default: (:)))
    if s.at("hide", default: false) { return () }
    let base-fill = if value == none {
      pal.empty-fill
    } else if kind == "count" or kind == "buckets" {
      pal.count-fill
    } else { rt.node-fill }
    let fill-c = s.at("fill", default: base-fill)
    let stroke-c = s.at("stroke", default: rt.node-stroke)
    let box = {
      draw.rect(c0, c1, fill: fill-c, stroke: stroke-c, name: anchor(key))
      let tf = s.at("text-fill", default: rt.node-text-fill)
      let lbl = s.at("label", default: value)
      let body = _cell-body(lbl, sub, tf, pal.active-digit-fill)
      if body != none { draw.content(center, body) }
      // The operation note (gold), just above the box.
      let note = s.at("note", default: none)
      if note != none {
        let nf = s.at("note-fill", default: rt.note-fill)
        haloed(
          draw,
          (center.at(0), c1.at(1) + 0.24),
          text(fill: nf, size: 0.8em, note),
          theme,
          anchor: "south",
        )
      }
    }
    // `ghost` keeps the box's exact footprint and its anchors but paints
    // nothing — the progressive-reveal slot.
    if s.at("ghost", default: false) {
      draw.hide(box, bounds: true)
    } else { box }
  }

  let body = {
    // --- arrows first (occluded by the cells / entries drawn after) ---
    for arrow in arrows {
      let es = merge-into(edge-style, snapshot.edges.at(arrow.id, default: (:)))
      if es.at("hide", default: false) { continue }
      let (fc0, fc1, fctr) = endpoint-box(arrow.from)
      let (tc0, tc1, tctr) = endpoint-box(arrow.to)
      // Depart the source face pointing toward the target and land on the
      // target's near face, so the arrowhead sits in the gap between the
      // boxes (visible, not occluded). `c0` holds the lower y (box
      // bottom), `c1` the upper y (box top). Cells and chain entries
      // alike.
      let going-down = tctr.at(1) <= fctr.at(1)
      let from-pt = (fctr.at(0), if going-down { fc0.at(1) } else { fc1.at(1) })
      let to-pt = (tctr.at(0), if going-down { tc1.at(1) } else { tc0.at(1) })
      let stroke-c = es.at("stroke", default: rt.edge-stroke)
      draw.line(
        from-pt,
        to-pt,
        stroke: stroke-c,
        mark: (end: ">", fill: stroke-paint(stroke-c)),
      )
    }

    // --- chain links (structural connectors, occluded by the boxes) ---
    // A head pointer drops from each bucket header's south face into entry
    // 0, then a link runs from each entry into the next. Drawn before the
    // boxes so the boxes cover the line ends, leaving a clean arrowhead in
    // each gap.
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
            stroke: pal.chain-stroke,
            mark: (end: ">", fill: stroke-paint(pal.chain-stroke)),
          )
        }
      }
    }

    // --- cells ---
    for (r, row) in rows.enumerate() {
      let kind = row.at("kind", default: "data")
      for (c, cell) in row.cells.enumerate() {
        let (c0, c1, center) = _cell-box(tops.at(r), c, dims)
        draw-box(
          cell-key(row.id, c),
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
          draw-box(
            entry-key(row.id, i, j),
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
    // default border paints over cell c's shared edge — clipping a
    // highlight on cell c. Redraw the border of any cell carrying an
    // explicit stroke override, on top of every neighbour, so a highlight
    // stays crisp on all four sides. Stroke-only (no fill) leaves the
    // content alone. Chain entries don't share edges — `_CHAIN-GAP`
    // separates them — so they need no re-stroke.
    for (r, row) in rows.enumerate() {
      for (c, _cell) in row.cells.enumerate() {
        let key = cell-key(row.id, c)
        let s = merge-into(node-style, snapshot.nodes.at(key, default: (:)))
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
          text(fill: pal.row-label-fill, lbl),
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
        let lbl = if indices == auto { str(c) } else {
          indices.at(c, default: str(c))
        }
        haloed(
          draw,
          (center.at(0), top - dims.ch - 0.3),
          text(size: 0.75em, fill: pal.index-fill, lbl),
          theme,
          anchor: "center",
        )
      }
    }
  }

  if name == none { body } else { draw.group(body, name: name) }
}
