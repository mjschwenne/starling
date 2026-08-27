// Hash-map drawing backend.
//
// Turns a positioned hash table plus one snapshot into cetz commands. Like
// the tree and graph backends it knows nothing about hashing *algorithms*
// — probing, chaining, tombstones, and resizing live in `ds/hashmap.typ`.
//
// Element identity
// ----------------
// A hash table is a fixed-length array of cells indexed 0..m-1, so tree
// paths do not apply:
//   * an array slot is keyed `"c" + str(i)` ("c3");
//   * a chaining entry `"c" + i + ":" + j` — bucket i, depth j (0 = head);
//   * a chain link (edge) by its *target* entry, the same
//     `"c" + i + ":" + j` string, mirroring the tree convention of keying
//     an edge by its child. The link into entry 0 is the head pointer from
//     the array slot.
// Both go through the shared `anchor` sanitizer for their cetz names:
// `anchor(cell-key(3))` is "el-c3", `anchor(entry-key(3, 1))` "el-c3-1".
//
// Positioned-table input
// ----------------------
// The backend consumes an opaque "table" dict, built by
// `hashmap.positioned`:
//
//   (
//     capacity: int,
//     orientation: "horizontal" | "vertical",
//     strategy: "chaining" | "linear" | "quadratic" | "double",
//     cells: array of length capacity. For open addressing each element is
//            `none` (empty), an entry dict `(key:, label:, value:)`, or a
//            tombstone `(tombstone: true)`. For chaining each element is an
//            array of entry dicts.
//     hash-box: none | (key:, expr:, index:) — the operation overlay for
//            this frame: `h(<key>) = <expr> = <index>` above the array with
//            an arrow to cell `index`. A `ghost: true` key draws it
//            invisibly, reserving its footprint.
//     cell-width: auto | "fit" | number — the sizing mode (optional,
//            default `auto`); see `core/draw-util.typ`.
//     measure-cells: array of entry dicts (optional, default `()`) — the
//            superset of bodies an animation will ever show, so every frame
//            fits to the same footprint and the table never jumps.
//     phantom: none | (bucket:, depth:) — chaining only. One empty "null"
//            cell hung a step past the tail of `bucket` (the slot a failed
//            lookup falls off the end into), with a link into it. Stylable
//            via `entry-key(bucket, depth)` like a real entry.
//   )
//
// Coordinates are derived deterministically from `capacity` +
// `orientation` + the resolved cell width; unlike graphs there is no
// explicit layout to supply.

#import "@preview/cetz:0.5.2"
#import "../core/draw-util.typ": (
  PAD-X, PAD-Y, anchor, haloed, measure-max, resolve-dims, stroke-paint,
)
#import "../core/style.typ": merge-into, resolve-inputs
#import "../core/theme.typ": default-theme, merge-theme

// ===================================================================
// Cell / entry identity
// ===================================================================

/// The canonical snapshot key for the array cell (slot) at index `i`.
///
/// -> str
#let cell-key(
  /// Slot index.
  /// -> int
  i,
) = "c" + str(i)

/// The canonical snapshot key for the chaining entry at depth `j` in
/// bucket `i` (0 = the head entry). Also the key of the link *into* that
/// entry.
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

// ===================================================================
// Layout geometry
// ===================================================================
//
// All measurements are in cetz units. The layout is fully determined by
// the slot index and orientation, so callers never supply positions.

// The default cell footprint. Horizontal: cells run left to right, each
// `_CW` wide and `_CH` tall, sharing edges into a contiguous array.
// Vertical: cells run top to bottom (a memory-diagram column), the same
// size. These are the *floors* — "fit" widens a cell to its label but
// never below them, so short numeric tables render at the historical size.
#let _CW = 1.4
#let _CH = 1.0

// Chain-entry box half-extents, also floors: in "fit" mode both the
// half-width (`ehw`) and the half-height (`ehh`) grow to the widest /
// tallest label, so entries don't clip at large (touying-sized) fonts. The
// pitch between successive entries and the first-entry drop derive from
// `ehh`.
#let _EHW = 0.55
#let _EHH = 0.34

// The resolved layout dimensions for one render are threaded into the
// geometry helpers below: `cw`/`ch` are the array-cell footprint;
// `ehw`/`ehh` the chaining-entry half-extents; `epitch` the vertical pitch
// between horizontal-chain entries; `first-off` the drop from a cell to
// its first entry; `gap` the clear band (cell to first entry) the index
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

// The center of chaining entry `j` hanging off bucket `i`.
#let _entry-center(i, j, orientation, dims) = {
  let (_, _, c) = _cell-geom(i, orientation, dims)
  if orientation == "vertical" {
    // Entries extend rightward from the cell's east face; each is
    // `2*ehw` wide with a 0.5-unit gap, seated 0.15 past that face.
    (dims.cw + 0.15 + dims.ehw + j * (2 * dims.ehw + 0.5), c.at(1))
  } else {
    // Entries hang downward below the cell's south face.
    (c.at(0), -dims.first-off - j * dims.epitch)
  }
}

// The point on cell `i`'s face from which its chain (the head pointer)
// departs.
#let _cell-chain-exit(i, orientation, dims) = {
  let (c0, c1, c) = _cell-geom(i, orientation, dims)
  if orientation == "vertical" {
    (c1.at(0), c.at(1)) // east-center
  } else {
    (c.at(0), c0.at(1)) // south-center (c0 holds the lower y)
  }
}

// `(pos, anchor)` — the cetz point and the halo anchor that seat cell
// `i`'s index label.
#let _index-label-pos(i, orientation, strategy, dims) = {
  let (c0, c1, c) = _cell-geom(i, orientation, dims)
  if orientation == "vertical" {
    ((-0.35, c.at(1)), "center") // west of the column
  } else if strategy == "chaining" {
    // Horizontal chaining: the head-pointer arrow drops straight down the
    // cell center to the first entry, so a centered index would bury it
    // (its opaque halo covers the whole short arrow). Seat the index just
    // left of the arrow, in the clear band between cell and first entry.
    ((c.at(0) - 0.22, -dims.gap / 2), "east")
  } else {
    ((c.at(0), c0.at(1) - 0.35), "center") // below the row
  }
}

// ===================================================================
// Cell bodies and sizing
// ===================================================================

// The visible content of one entry/cell given its resolved key label and
// optional value. A value renders as a second, smaller line below the key;
// a key-only entry shows just the key.
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

// The body of an entry dict, for measuring.
#let _cell-body(text-fill) = e => _entry-body(
  e.at("label", default: str(e.key)),
  e.at("value", default: none),
  text-fill,
)

// Resolve the layout dimensions for one render.
//
// The two box families size independently, because only one of them is
// ever populated: open addressing puts its labels in the array cells and
// has no chain entries, chaining puts them in the entries and leaves the
// array cells as keyless bucket headers. `measure-cells` (the animation's
// global body superset) therefore goes to whichever family the strategy
// actually uses.
//
// Array cells go through the shared `resolve-dims`; chain entries through
// its companion `measure-max`, because their `ehw`/`ehh` are *half*
// extents and the padding is applied after halving.
#let _dims(cells, strategy, orientation, text-fill, cell-width, measure-cells) = {
  let m = cells.len()
  let chaining = strategy == "chaining"
  let body-fn = _cell-body(text-fill)

  let cell-subjects = if chaining { () } else {
    cells.filter(c => c != none and not c.at("tombstone", default: false))
  }
  let entry-subjects = if chaining { cells.flatten() } else { () }

  let cd = resolve-dims(
    cell-subjects,
    body-fn,
    cell-width,
    floor-w: _CW,
    floor-h: _CH,
    measure-cells: if chaining { () } else { measure-cells },
  )
  let cw = cd.w
  let ch = cd.h

  // "fit" is the only mode that measures — `auto` must stay usable outside
  // a layout context, and a pinned number needs no measurement either.
  let (ehw, ehh) = if cell-width == "fit" {
    let e = measure-max(
      entry-subjects,
      body-fn,
      measure-cells: if chaining { measure-cells } else { () },
    )
    (calc.max(_EHW, e.w / 2 + PAD-X), calc.max(_EHH, e.h / 2 + PAD-Y))
  } else { (_EHW, _EHH) }

  // The clear band between a cell and its first chain entry, widened in
  // "fit" mode to clear the font-scaled index label.
  let gap = if cell-width == "fit" {
    let idx-h = measure(text(size: 0.75em, str(calc.max(0, m - 1)))).height / 1cm
    calc.max(0.61, idx-h + 0.18)
  } else { 0.61 }

  // Horizontal chaining: entries hang under each bucket, so the array
  // pitch must clear adjacent chains (each entry is `2*ehw` wide).
  if chaining and orientation != "vertical" {
    cw = calc.max(cw, 2 * ehw + 0.2)
  }
  // `epitch` / `first-off` derive from `ehh` so taller entries stay clear
  // of one another and of the array (at the floor these reproduce the
  // historical 1.02 pitch / 0.95 drop exactly).
  (
    cw: cw,
    ch: ch,
    ehw: ehw,
    ehh: ehh,
    epitch: 2 * ehh + 0.34,
    first-off: ehh + gap,
    gap: gap,
  )
}

// ===================================================================
// draw-hashmap
// ===================================================================

/// Emit the cetz draw commands for one styled snapshot of a hash table,
/// _without_ wrapping them in a `cetz.canvas` — the caller owns the
/// canvas, so you can add your own annotations and anchor them with
/// `anchor(cell-key(i))` or `anchor(entry-key(i, j))`.
///
/// The array of cells is drawn first, then (for chaining) the chains
/// hanging off each bucket, then the hash-box overlay on top. Each cell's
/// structural state comes from the table dict (empty / occupied /
/// tombstone / chain); per-frame highlights come from the snapshot — the
/// probe walk in `search-stroke`, the landing in `success-fill`, and so
/// on.
///
/// -> content
#let draw-hashmap(
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
  /// Base link styling, applied beneath the snapshot's per-link styles.
  /// -> dictionary
  edge-style: (:),
  /// A theme, partial or whole — a partial one layers over the default, as
  /// on every DS entry point. The backend reads `theme.render`,
  /// `theme.hashmap`, and `theme.op.attention-stroke` (the hash-box
  /// arrow).
  /// -> dictionary
  theme: default-theme,
  /// Wrap the whole table in a cetz group of this name, qualifying every
  /// element anchor under it — `anchor(cell-key(i), canvas: name)`.
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
  let pal = theme.hashmap
  let m = tbl.capacity
  let orientation = tbl.at("orientation", default: "horizontal")
  let strategy = tbl.at("strategy", default: "chaining")
  let cells = tbl.cells

  // Resolve the cell/entry footprint so longer labels aren't clipped. The
  // table dict may pin a fixed `cell-width`; otherwise it fits the widest
  // label, floored at the historical size.
  let dims = _dims(
    cells,
    strategy,
    orientation,
    rt.node-text-fill,
    tbl.at("cell-width", default: auto),
    tbl.at("measure-cells", default: ()),
  )

  // Draw one cell/entry rectangle with a resolved style overlay. `state`
  // is the structural state ("empty" / "occupied" / "tombstone" /
  // "header" / "entry").
  let draw-box(key, c0, c1, center, state, label, value, is-chain) = {
    let s = merge-into(node-style, snapshot.nodes.at(key, default: (:)))
    if s.at("hide", default: false) { return () }
    let base-fill = if state == "empty" {
      pal.empty-fill
    } else if state == "tombstone" {
      pal.tombstone-fill
    } else if is-chain {
      pal.chain-fill
    } else { rt.node-fill }
    let base-stroke = if state == "tombstone" {
      pal.tombstone-stroke
    } else { rt.node-stroke }
    let fill-c = s.at("fill", default: base-fill)
    let stroke-c = s.at("stroke", default: base-stroke)
    let radius = if is-chain { 0.08 } else { 0 }
    let box = {
      draw.rect(
        c0,
        c1,
        fill: fill-c,
        stroke: stroke-c,
        radius: radius,
        name: anchor(key),
      )
      let tf = s.at("text-fill", default: rt.node-text-fill)
      let lbl = s.at("label", default: label)
      if state == "tombstone" {
        draw.content(
          center,
          text(weight: "bold", fill: pal.tombstone-stroke, size: 1.1em, [×]),
        )
      } else if state != "empty" and lbl != none {
        draw.content(center, _entry-body(lbl, value, tf))
      }
      // The operation note (gold), just outside the box on the far side.
      let note = s.at("note", default: none)
      if note != none {
        let nf = s.at("note-fill", default: rt.note-fill)
        let np = if orientation == "vertical" {
          (center.at(0), c1.at(1) + 0.28)
        } else {
          (c1.at(0) + 0.12, center.at(1))
        }
        let na = if orientation == "vertical" { "south" } else { "west" }
        haloed(draw, np, text(fill: nf, size: 0.8em, note), theme, anchor: na)
      }
    }
    // `ghost` keeps the box's exact footprint and its anchors but paints
    // nothing — the progressive-reveal slot.
    if s.at("ghost", default: false) {
      draw.hide(box, bounds: true)
    } else { box }
  }

  // Draw the link into chain entry `(i, j)` — the head pointer from the
  // array slot when `j == 0`, otherwise the link from entry `j - 1`.
  let draw-link(i, j) = {
    let ec = _entry-center(i, j, orientation, dims)
    let top = if orientation == "vertical" {
      (ec.at(0) - dims.ehw, ec.at(1))
    } else { (ec.at(0), ec.at(1) + dims.ehh) }
    let from = if j == 0 {
      _cell-chain-exit(i, orientation, dims)
    } else {
      let pc = _entry-center(i, j - 1, orientation, dims)
      if orientation == "vertical" {
        (pc.at(0) + dims.ehw, pc.at(1))
      } else { (pc.at(0), pc.at(1) - dims.ehh) }
    }
    let ls = merge-into(edge-style, snapshot.edges.at(entry-key(i, j), default: (:)))
    if ls.at("hide", default: false) { return () }
    let st = ls.at("stroke", default: pal.chain-stroke)
    draw.line(from, top, stroke: st, mark: (end: ">", fill: stroke-paint(st)))
  }

  let body = {
    // --- chains first (occluded by the cells drawn afterwards) ---
    if strategy == "chaining" {
      for (i, chain) in cells.enumerate() {
        if chain.len() == 0 { continue }
        for (j, _entry) in chain.enumerate() { draw-link(i, j) }
      }
    }

    // --- cells ---
    for (i, cell) in cells.enumerate() {
      let (c0, c1, center) = _cell-geom(i, orientation, dims)
      if strategy == "chaining" {
        // The array slot itself is the bucket header. An empty bucket
        // reads as a muted empty slot; a bucket with a chain reads as a
        // filled pointer slot (the entries below carry the keys).
        let state = if cell.len() == 0 { "empty" } else { "header" }
        draw-box(cell-key(i), c0, c1, center, state, none, none, false)
      } else {
        let state = if cell == none {
          "empty"
        } else if cell.at("tombstone", default: false) {
          "tombstone"
        } else { "occupied" }
        let label = if state == "occupied" {
          cell.at("label", default: str(cell.key))
        } else { none }
        let value = if state == "occupied" {
          cell.at("value", default: none)
        } else { none }
        draw-box(cell-key(i), c0, c1, center, state, label, value, false)
      }
    }

    // --- re-stroke highlighted array cells on top ---
    // Array cells form a contiguous row/column sharing edges, drawn in
    // index order, so cell i+1's (default) border paints over cell i's
    // shared edge — clipping a highlight applied to cell i. Redraw the
    // border of any cell carrying an explicit stroke override, on top of
    // every neighbour, so a probe / landing / miss highlight stays crisp
    // on all four sides. Stroke-only (no fill) leaves the content alone.
    for i in range(m) {
      let s = merge-into(node-style, snapshot.nodes.at(cell-key(i), default: (:)))
      if "stroke" in s and not s.at("hide", default: false) {
        let (c0, c1, _) = _cell-geom(i, orientation, dims)
        draw.rect(c0, c1, fill: none, stroke: s.stroke)
      }
    }

    // --- chain entry boxes (after the cells, so links tuck under them) ---
    if strategy == "chaining" {
      for (i, chain) in cells.enumerate() {
        for (j, entry) in chain.enumerate() {
          let ec = _entry-center(i, j, orientation, dims)
          let c0 = (ec.at(0) - dims.ehw, ec.at(1) - dims.ehh)
          let c1 = (ec.at(0) + dims.ehw, ec.at(1) + dims.ehh)
          draw-box(
            entry-key(i, j),
            c0,
            c1,
            ec,
            "entry",
            entry.at("label", default: str(entry.key)),
            entry.at("value", default: none),
            true,
          )
        }
      }
    }

    // --- the phantom chain cell ---
    // One empty "null" cell hung a step past the tail of a bucket, with a
    // link into it. It has no structural entry — it is the slot a failed
    // chaining lookup falls off the end into, so the miss can ring an
    // empty cell instead of the keyless bucket header. Stylable via its
    // `entry-key(bucket, depth)` like any entry. Drawn link-then-box so
    // the arrowhead tucks under, matching the real chain.
    let phantom = tbl.at("phantom", default: none)
    if strategy == "chaining" and phantom != none {
      let (i, d) = (phantom.bucket, phantom.depth)
      draw-link(i, d)
      let ec = _entry-center(i, d, orientation, dims)
      let c0 = (ec.at(0) - dims.ehw, ec.at(1) - dims.ehh)
      let c1 = (ec.at(0) + dims.ehw, ec.at(1) + dims.ehh)
      draw-box(entry-key(i, d), c0, c1, ec, "empty", none, none, true)
    }

    // --- index labels ---
    for i in range(m) {
      let (pos, a) = _index-label-pos(i, orientation, strategy, dims)
      haloed(
        draw,
        pos,
        text(size: 0.75em, fill: pal.index-fill, str(i)),
        theme,
        anchor: a,
      )
    }

    // --- the hash-box overlay ---
    let hb = tbl.at("hash-box", default: none)
    if hb != none {
      let idx = hb.index
      let (bc0, bc1, bcenter) = _cell-geom(idx, orientation, dims)
      // A "ghost" hash box reserves the box's exact footprint but draws
      // nothing visible: no frame, hidden (still laid-out) text, no arrow.
      // The walk-based displays put a ghost box on their leading pre-hash
      // frame so the canvas bounds — and hence the table's position on a
      // slide — don't jump when the real box appears on the next subslide.
      let ghost = hb.at("ghost", default: false)
      let hb-stroke = if ghost { none } else { pal.hash-box-stroke }
      let hb-fill = if ghost { none } else { pal.hash-box-fill }
      // Double hashing carries a second-hash line (the step size); the
      // other strategies show the single hash line.
      let expr2 = hb.at("expr2", default: none)
      let box-body = if expr2 == none {
        [h(#hb.key) = #hb.expr = #text(weight: "bold")[#hb.index]]
      } else {
        stack(
          dir: ttb,
          spacing: 0.35em,
          [h₁(#hb.key) = #hb.expr = #text(weight: "bold")[#hb.index]],
          [h₂(#hb.key) = #expr2 = #text(weight: "bold")[#hb.step]],
        )
      }
      // `hide` keeps the content's layout footprint (so the frame sizes
      // and the cetz bounds match a visible box) while rendering nothing.
      let box-body = if ghost { hide(box-body) } else { box-body }
      let arrow-stroke = theme.op.attention-stroke
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
          text(size: 0.85em, box-body),
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
        let box-x = calc.max(
          1.1,
          calc.min((m - 1 + 0.5) * dims.cw - 0.1, bcenter.at(0)),
        )
        let box-y = dims.ch + 1.5
        draw.content(
          (box-x, box-y),
          anchor: "south",
          frame: "rect",
          fill: hb-fill,
          stroke: hb-stroke,
          padding: 0.14,
          text(size: 0.85em, box-body),
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

  if name == none { body } else { draw.group(body, name: name) }
}
