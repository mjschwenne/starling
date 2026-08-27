// Skip-list drawing backend.
//
// Draws a sparse grid of node towers joined by horizontal forward
// pointers — the one primitive the array backend lacks, whose arrows run
// vertically between stacked rows. It knows nothing about searching,
// inserting, or deleting; those live in `ds/skiplist.typ`.
//
// The geometry, in one paragraph:
//
//   * A skip list is a *sparse grid*. Columns are the sorted nodes: a left
//     HEADER sentinel at column 0, then one column per key (1..n), then an
//     optional NIL tail sentinel at column n+1. Rows are levels, with
//     LEVEL 0 AT THE BOTTOM and towers rising.
//   * A node of tower `height` h occupies boxes in the bottom h rows of
//     its column; absent levels leave gaps, unlike the array backend where
//     every column has a cell in every row.
//   * FORWARD POINTERS are horizontal arrows at each level, from a box's
//     right face to the LEFT face of the next node present at that level —
//     skipping over columns whose towers don't reach that level.
//
// Box / pointer identity
// ----------------------
//   * a LANE box is keyed `"b<col>:<level>"`, built by `box-key(col,
//     level)`, and styled through the snapshot's `nodes` slot. A lane box
//     is a pure pointer cell: it carries no key.
//   * the DATA box — the box holding a node's key, drawn once BELOW the
//     whole tower, where no forward pointer attaches, so a link never
//     crosses the key — is keyed `"d<col>"`, built by `data-key(col)`.
//   * a forward pointer is keyed by its SOURCE, `"f<col>:<level>"` (its
//     target is derived), built by `forward-key(col, level)` and styled
//     through the snapshot's `edges` slot like a graph edge.
// All three go through the shared `anchor` sanitizer for their cetz names:
// `anchor(box-key(2, 0))` is "el-b2-0".
//
// Positioned-table input
// ----------------------
// The backend consumes an opaque "table" dict, built by
// `skiplist.positioned`:
//
//   (
//     cols: array of column dicts, index 0 = header, 1..n = data, and
//       (n+1 = nil when the list draws its tail sentinel). Each column:
//         (
//           kind:        "header" | "data" | "nil",
//           height:      int,          // boxes drawn in this tower
//           key:         any,          // display value (data); ignored
//                                      // for header/nil
//           label:       content|none, // optional explicit box label
//           state:       "live" | "ghost",
//                          // "ghost" reserves the column's horizontal
//                          // slot (so neighbours don't shift) but draws
//                          // nothing — how an about-to-appear node holds
//                          // its place during the search phase.
//           link-min:    int,          // lowest level this column is
//                                      // LINKED at (default 0)
//           link-height: int,          // one past the highest level it is
//                                      // LINKED at (default `height`)
//         )
//     cell-width:   auto | "fit" | number,   // box sizing
//     measure-cells: array,                  // fit-measurement superset
//   )
//
// A column is linked — participates in pointer routing — across the
// half-open range `[link-min, link-height)`. That range is what lets a
// top-down insert splice (raise the linked range from the top by lowering
// `link-min` from `height` to 0) or a top-down delete unlink (lower
// `link-height` from `height` to 0) animate level by level while the tower
// stays drawn.
//
// The number of levels drawn derives from the live data columns' heights,
// so the header/nil sentinels are exactly as tall as the list currently
// reaches — level 0 is pinned at y = 0, so growing a level adds a row on
// TOP and never shifts existing boxes.

#import "@preview/cetz:0.5.2"
#import "../core/draw-util.typ": anchor, haloed, resolve-dims, stroke-paint
#import "../core/style.typ": merge-into, resolve-inputs
#import "../core/theme.typ": default-theme, merge-theme

// ===================================================================
// Box / pointer identity
// ===================================================================

/// The canonical snapshot key for the lane box at `level` of column `col`
/// (0 = header, 1..n = data, n+1 = nil) — `box-key(2, 0)` is `"b2:0"`.
/// Styled through the snapshot's `nodes` slot like any node.
///
/// -> str
#let box-key(
  /// Column index (0 = header).
  /// -> int
  col,
  /// Level within the tower (0 = bottom).
  /// -> int
  level,
) = "b" + str(col) + ":" + str(level)

/// The canonical snapshot key for the forward pointer LEAVING column `col`
/// at `level` — `forward-key(0, 2)` is `"f0:2"`. Its target, the next node
/// present at that level, is derived by the backend. Styled through the
/// snapshot's `edges` slot like a graph edge.
///
/// -> str
#let forward-key(
  /// Source column index.
  /// -> int
  col,
  /// Level of the pointer (0 = bottom).
  /// -> int
  level,
) = "f" + str(col) + ":" + str(level)

/// The canonical snapshot key for the DATA box of column `col` — the box
/// holding the node's key, drawn once *below* the whole tower, where no
/// forward pointer attaches. `data-key(2)` is `"d2"`.
///
/// -> str
#let data-key(
  /// Column index (0 = header).
  /// -> int
  col,
) = "d" + str(col)

// ===================================================================
// Layout geometry
// ===================================================================
//
// All measurements are in cetz units. Columns run left to right on a fixed
// pitch (box width plus a gap, so the horizontal pointers show); levels
// stack bottom to top (level 0 at y = 0, rising). The layout is fully
// determined by the column/level indices and the resolved box size, so
// callers never supply positions.

// The default box footprint floors. "fit" widens `bw`/`bh` to longer
// labels but never below these.
#let _BW = 1.2
#let _BH = 0.7
// Horizontal gap between adjacent columns — room for a pointer and its
// arrowhead in the clear band between towers.
#let _COL-GAP = 1.0
// Vertical gap between successive levels of one tower. Zero, so a tower's
// boxes stack flush into one contiguous column (adjacent borders coincide
// into a shared line): a real node is one cell tall per level, not a
// ladder of floating boxes.
#let _ROW-GAP = 0.0

// The visible content of one box: the node's display value (or an explicit
// `label` override). Header / nil sentinels pass their own content.
#let _box-body(value, text-fill) = if value == none {
  none
} else {
  text(weight: "bold", fill: text-fill, value)
}

// The body of a measurement subject, for "fit" sizing.
#let _measure-body(text-fill) = cell => _box-body(
  cell.at("value", default: none),
  text-fill,
)

// The number of levels drawn: the tallest LIVE data tower (at least 1).
// Ghost columns don't count — they reserve a horizontal slot only — so an
// about-to-appear node doesn't inflate the header height during the search
// phase.
#let _levels(cols) = {
  let m = 1
  for c in cols {
    if c.kind == "data" and c.at("state", default: "live") == "live" {
      m = calc.max(m, c.height)
    }
  }
  m
}

// `(corner0, corner1, center)` of the box at column `c`, level `L`.
#let _box(c, L, dims) = {
  let x0 = c * (dims.bw + _COL-GAP)
  let x1 = x0 + dims.bw
  let y0 = L * (dims.bh + _ROW-GAP)
  let y1 = y0 + dims.bh
  ((x0, y0), (x1, y1), (x0 + dims.bw / 2, y0 + dims.bh / 2))
}

// `(corner0, corner1, center)` of the DATA box of column `c` — one box
// flush BELOW level 0 (the whole tower sits above it), holding the node's
// key. No forward pointer attaches here, so a link never crosses the key.
#let _data-box(c, dims) = {
  let x0 = c * (dims.bw + _COL-GAP)
  let x1 = x0 + dims.bw
  ((x0, -dims.bh), (x1, 0), (x0 + dims.bw / 2, -dims.bh / 2))
}

// `(corner0, corner1, center)` of a nil sentinel spanning all `levels` rows
// of column `c` as ONE tall box. It also extends down through the data-box
// row (`y0 = -bh`) so its bottom lines up with the header / data columns —
// the whole column reads as one flush block.
#let _nil-box(c, levels, dims) = {
  let x0 = c * (dims.bw + _COL-GAP)
  let x1 = x0 + dims.bw
  let y0 = -dims.bh
  let y1 = (levels - 1) * (dims.bh + _ROW-GAP) + dims.bh
  ((x0, y0), (x1, y1), (x0 + dims.bw / 2, (y0 + y1) / 2))
}

// Whether column `col` is LINKED into the list at level `L` — i.e.
// participates in pointer routing there. Header and nil sentinels span
// every level; a live data column is linked across the half-open range
// `[link-min, link-height)`, never when ghost.
#let _linked-at(col, L) = {
  if col.kind == "header" or col.kind == "nil" { return true }
  if col.at("state", default: "live") != "live" { return false }
  let lo = col.at("link-min", default: 0)
  let hi = col.at("link-height", default: col.height)
  lo <= L and L < hi
}

// ===================================================================
// draw-skiplist
// ===================================================================

/// Emit the cetz draw commands for one styled snapshot of a skip list,
/// _without_ wrapping them in a `cetz.canvas` — the caller owns the
/// canvas, so you can add your own annotations and anchor them with
/// `anchor(box-key(col, level))`.
///
/// The draw order is layered so the occlusion tells the linked/unlinked
/// story:
///
/// + the UNLINKED lane boxes — a data column's boxes at levels outside its
///   `[link-min, link-height)` range — in the muted palette;
/// + the forward pointers, so they run OVER those grayed boxes: the cue
///   that the list *skips past* such a node rather than stopping on it;
/// + the linked lane boxes, the header/nil sentinels, the data boxes, and
///   the ghost reserves, which occlude the pointer line ends into clean
///   arrowheads (a linked box's intact border versus a grayed box's
///   pointer-crossed one is itself a cue);
/// + a re-stroke pass for highlighted lane boxes, so a just-unlinked
///   grayed box keeps its ring above the pointer running through it;
/// + the labels, on top, so nothing occludes a key.
///
/// -> content
#let draw-skiplist(
  /// The positioned table — see the module header for its shape.
  /// -> dictionary
  tbl,
  /// Style overlay for this snapshot; `blank-snapshot()` draws it
  /// unstyled.
  /// -> dictionary
  snapshot,
  /// Base box styling, applied beneath the snapshot's per-box styles.
  /// -> dictionary
  node-style: (:),
  /// Base pointer styling, applied beneath the snapshot's per-pointer
  /// styles.
  /// -> dictionary
  edge-style: (:),
  /// A theme, partial or whole — a partial one layers over the default, as
  /// on every DS entry point. The backend reads `theme.render` and
  /// `theme.skiplist`.
  /// -> dictionary
  theme: default-theme,
  /// Wrap the whole list in a cetz group of this name, qualifying every
  /// element anchor under it — `anchor(box-key(c, l), canvas: name)`.
  /// `none` draws into the enclosing canvas directly.
  /// -> none | str
  name: none,
) = {
  import cetz.draw
  // Layer a partial theme over the default, so a direct call takes the same
  // partial `theme:` every DS-level entry point does. The full resolved theme
  // `make-canvas` passes merges to itself, leaving the animation path alone.
  let theme = merge-theme(default-theme, theme)
  // Resolve theme references so the public direct-call path works: a
  // snapshot straight from a DS `renderer()` or a `styles.*` helper carries
  // refs that only `make-canvas` would otherwise resolve.
  let (snapshot, node-style, edge-style) = resolve-inputs(
    snapshot,
    node-style,
    edge-style,
    theme,
  )
  let rt = theme.render
  let pal = theme.skiplist
  let cols = tbl.cols
  let levels = _levels(cols)

  let dims = {
    let subjects = cols
      .map(c => (value: c.at("label", default: none)))
      .filter(c => c.value != none)
    let d = resolve-dims(
      subjects,
      _measure-body(rt.node-text-fill),
      tbl.at("cell-width", default: auto),
      floor-w: _BW,
      floor-h: _BH,
      measure-cells: tbl.at("measure-cells", default: ()),
    )
    (bw: d.w, bh: d.h)
  }

  // Center-left / center-right / center of a box (or the nil sentinel) at
  // (col, level), used as pointer endpoints.
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

  // Resolve a snapshot style over a base tuple `(fill, stroke, text-fill,
  // value)`; `none` when the box is hidden.
  let resolve(key, base) = {
    let (bf, bs, bt, value) = base
    let s = merge-into(node-style, snapshot.nodes.at(key, default: (:)))
    if s.at("hide", default: false) { return none }
    (
      fill: s.at("fill", default: bf),
      stroke: s.at("stroke", default: bs),
      text-fill: s.at("text-fill", default: bt),
      label: s.at("label", default: value),
      note: s.at("note", default: none),
      note-fill: s.at("note-fill", default: rt.note-fill),
      ghost: s.at("ghost", default: false),
    )
  }

  // `ghost` keeps a box's exact footprint and its anchors but paints
  // nothing — the progressive-reveal slot. (A whole column's `state:
  // "ghost"` is the structural version of the same idea, applied by the
  // insert animation before the node exists.)
  let ghosted(cmds, st) = if st.ghost {
    draw.hide(cmds, bounds: true)
  } else { cmds }

  // Base style of a LANE box at (col, L): a pure pointer cell. Header/nil
  // take the sentinel palettes; a data node takes the normal palette when
  // LINKED at this level, or the muted one when not (a spliced-out /
  // not-yet-spliced-in lane). Lane boxes never carry the key — it lives in
  // the data box below — so `value` is always `none`, except the nil
  // sentinel, whose one box IS its "NIL" label.
  let lane-base(col, L) = if col.kind == "header" {
    (pal.header-fill, pal.header-stroke, pal.header-text-fill, none)
  } else if col.kind == "nil" {
    (pal.nil-fill, pal.nil-stroke, pal.nil-text-fill, col.at("label", default: "NIL"))
  } else if _linked-at(col, L) {
    (rt.node-fill, rt.node-stroke, rt.node-text-fill, none)
  } else {
    (pal.unlinked-fill, pal.unlinked-stroke, pal.unlinked-text-fill, none)
  }

  // Base style of the DATA box of a column: the header's is an empty
  // sentinel box (bottom-aligning the head column with the data columns);
  // a data node's carries its key. The data box tracks node IDENTITY, so
  // it is NOT muted by link state (the lanes carry that) — only the
  // snapshot (settled / deleted / found highlights) restyles it.
  let data-base(col) = if col.kind == "header" {
    (pal.header-fill, pal.header-stroke, pal.header-text-fill, none)
  } else {
    (rt.node-fill, rt.node-stroke, rt.node-text-fill, col.at("label", default: none))
  }

  let body = {
    // --- unlinked lane boxes first, so the pointers drawn next cross OVER
    //     them — the cue that the list skips past a spliced-out /
    //     not-yet-linked node rather than stopping on it ---
    for (ci, col) in cols.enumerate() {
      if col.kind != "data" or col.at("state", default: "live") != "live" {
        continue
      }
      for L in range(col.height) {
        if not _linked-at(col, L) {
          let st = resolve(box-key(ci, L), lane-base(col, L))
          if st != none {
            let (c0, c1, _) = _box(ci, L, dims)
            ghosted(
              draw.rect(
                c0,
                c1,
                fill: st.fill,
                stroke: st.stroke,
                name: anchor(box-key(ci, L)),
              ),
              st,
            )
          }
        }
      }
    }

    // --- forward pointers (over the grayed boxes above; the linked boxes
    //     drawn next occlude the line ends into clean arrowheads) ---
    // For each level, walk the columns present (linked) at that level in
    // order and connect each to the next.
    for L in range(levels) {
      let present = range(cols.len()).filter(ci => _linked-at(cols.at(ci), L))
      for i in range(present.len() - 1) {
        let sc = present.at(i)
        let tc = present.at(i + 1)
        let fk = forward-key(sc, L)
        let es = merge-into(edge-style, snapshot.edges.at(fk, default: (:)))
        if es.at("hide", default: false) { continue }
        let (_, sright, _) = faces(sc, L)
        let (tleft, _, _) = faces(tc, L)
        let stroke-c = es.at("stroke", default: pal.pointer-stroke)
        draw.line(
          sright,
          tleft,
          stroke: stroke-c,
          mark: (end: ">", fill: stroke-paint(stroke-c)),
          name: anchor(fk),
        )
      }
    }

    // --- linked lane boxes + header/nil sentinels + data boxes + ghost
    //     reserves ---
    for (ci, col) in cols.enumerate() {
      let state = col.at("state", default: "live")
      if col.kind == "nil" {
        let (c0, c1, _) = _nil-box(ci, levels, dims)
        if state == "ghost" {
          // Reserve the slot, draw nothing.
          draw.rect(c0, c1, fill: none, stroke: none)
        } else {
          let st = resolve(box-key(ci, 0), lane-base(col, 0))
          if st != none {
            ghosted(
              draw.rect(
                c0,
                c1,
                fill: st.fill,
                stroke: st.stroke,
                name: anchor(box-key(ci, 0)),
              ),
              st,
            )
          }
        }
        continue
      }
      // A ghost column reserves its horizontal slot (an invisible rect
      // still contributes to the canvas bounds, so neighbours don't shift
      // when it later appears) across the lane tower AND the data box.
      let tower = if col.kind == "header" { levels } else { col.height }
      for L in range(tower) {
        let (c0, c1, _) = _box(ci, L, dims)
        if state == "ghost" {
          draw.rect(c0, c1, fill: none, stroke: none)
          continue
        }
        // Unlinked lane boxes were already drawn (grayed) under the
        // pointers.
        if col.kind == "data" and not _linked-at(col, L) { continue }
        let st = resolve(box-key(ci, L), lane-base(col, L))
        if st != none {
          ghosted(
            draw.rect(
              c0,
              c1,
              fill: st.fill,
              stroke: st.stroke,
              name: anchor(box-key(ci, L)),
            ),
            st,
          )
        }
      }
      // The data box below the tower (the header's is empty).
      let (d0, d1, _) = _data-box(ci, dims)
      if state == "ghost" {
        draw.rect(d0, d1, fill: none, stroke: none)
      } else {
        let st = resolve(data-key(ci), data-base(col))
        if st != none {
          ghosted(
            draw.rect(
              d0,
              d1,
              fill: st.fill,
              stroke: st.stroke,
              name: anchor(data-key(ci)),
            ),
            st,
          )
        }
      }
    }

    // --- re-stroke highlighted lane boxes on top ---
    // A pointer line can cross a lane box's edge, and adjacent columns'
    // highlights read cleaner drawn last. Redraw the border of any lane
    // box carrying an explicit stroke override, on top — so a
    // just-unlinked grayed box keeps its danger ring above the pointer
    // running through it. The data box is never crossed by a pointer, so
    // it needs none.
    for (ci, col) in cols.enumerate() {
      if col.at("state", default: "live") != "live" { continue }
      if col.kind == "nil" {
        let s = merge-into(
          node-style,
          snapshot.nodes.at(box-key(ci, 0), default: (:)),
        )
        if (
          "stroke" in s
            and not s.at("hide", default: false)
            and not s.at("ghost", default: false)
        ) {
          let (c0, c1, _) = _nil-box(ci, levels, dims)
          draw.rect(c0, c1, fill: none, stroke: s.stroke)
        }
        continue
      }
      let tower = if col.kind == "header" { levels } else { col.height }
      for L in range(tower) {
        let s = merge-into(
          node-style,
          snapshot.nodes.at(box-key(ci, L), default: (:)),
        )
        if (
          "stroke" in s
            and not s.at("hide", default: false)
            and not s.at("ghost", default: false)
        ) {
          let (c0, c1, _) = _box(ci, L, dims)
          draw.rect(c0, c1, fill: none, stroke: s.stroke)
        }
      }
    }

    // --- labels on top (the nil "NIL" in its tall box; each data node's
    //     key in its data box). Lane boxes carry no label. Drawn last so
    //     nothing occludes a key. ---
    for (ci, col) in cols.enumerate() {
      if col.at("state", default: "live") != "live" { continue }
      if col.kind == "nil" {
        let st = resolve(box-key(ci, 0), lane-base(col, 0))
        if st != none {
          let (_, _, center) = _nil-box(ci, levels, dims)
          let text-body = _box-body(st.label, st.text-fill)
          if text-body != none { ghosted(draw.content(center, text-body), st) }
        }
        continue
      }
      let st = resolve(data-key(ci), data-base(col))
      if st != none {
        let (_, _, center) = _data-box(ci, dims)
        let text-body = _box-body(st.label, st.text-fill)
        if text-body != none { ghosted(draw.content(center, text-body), st) }
      }
    }

    // --- the head caption (below the header's data box) ---
    for (ci, col) in cols.enumerate() {
      if col.at("state", default: "live") != "live" or col.kind != "header" {
        continue
      }
      let (c0, _, center) = _data-box(ci, dims)
      haloed(
        draw,
        (center.at(0), c0.at(1) - 0.3),
        text(size: 0.75em, fill: pal.index-fill, "head"),
        theme,
        anchor: "center",
      )
    }
  }

  if name == none { body } else { draw.group(body, name: name) }
}
