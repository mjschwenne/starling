// Graph drawing backend.
//
// Turns a positioned graph plus one snapshot into cetz commands. Like the
// tree backend it knows nothing about graph *algorithms* — MST, Dijkstra,
// and the traversals live in `ds/graph.typ`.
//
// Element identity
// ----------------
// A graph has no root and no path-from-root, so tree paths do not apply:
//   * a node is keyed by its user-chosen string id ("A", "s", "0");
//   * an edge by `edge-key(u, v, directed)` — "u->v" when directed, sorted
//     "u--v" when undirected, so an undirected edge has one canonical key
//     regardless of which endpoint is named first.
// Both go through the shared `anchor` sanitizer for their cetz names.
//
// Positioned-graph input
// ----------------------
// The backend consumes an opaque "positioned graph" dict, built by
// `graph.positioned`:
//
//   (
//     directed: bool,
//     nodes: (id: (label: any, pos: (x, y))),
//     edges: (array of (key: str, u: str, v: str, weight: any, label: any)),
//   )
//
// Positions are in cetz units; computing them (by hand or via
// `auto-layout`) is the caller's business, which keeps this renderer
// layout-engine agnostic.

#import "@preview/cetz:0.5.2"
#import "../core/draw-util.typ": anchor, stroke-paint
#import "../core/style.typ": merge-into
#import "../core/theme.typ": default-theme

// ===================================================================
// Edge identity
// ===================================================================

/// The canonical snapshot key for the edge between `u` and `v`.
///
/// A directed graph keys edges "u->v" (order significant); an undirected
/// graph sorts the endpoints into "u--v", so the same edge has one key
/// however it is named.
///
/// -> str
#let edge-key(
  /// First endpoint id.
  /// -> str
  u,
  /// Second endpoint id.
  /// -> str
  v,
  /// Whether the graph is directed.
  /// -> bool
  directed: false,
) = {
  if directed {
    u + "->" + v
  } else if u <= v {
    u + "--" + v
  } else {
    v + "--" + u
  }
}

// ===================================================================
// Geometry helpers
// ===================================================================

// Perpendicular unit offset (scaled) for placing a label off an edge line.
// `dx`/`dy` is the edge direction; returns `(ox, oy)` to add to the
// midpoint. A degenerate (zero-length) edge gets no offset.
#let _perp-offset(dx, dy, amount) = {
  let len = calc.sqrt(dx * dx + dy * dy)
  if len == 0 { (0, 0) } else { (-dy / len * amount, dx / len * amount) }
}

// The compass anchor (vertical-first, e.g. "south-east") naming the side of
// a label box that faces the edge, given the perpendicular offset
// `(ox, oy)` that seats the box off the line. Anchoring that side at the
// offset point makes the box grow *away* from the line, so a wide
// multi-digit weight clears it by its own measured width rather than by a
// fixed center gap. Near-axis offsets (one component ~0) drop that axis so
// the box stays centered along it — a horizontal edge gets "south".
#let _tag-anchor(ox, oy) = {
  let h = if ox > 1e-6 { "west" } else if ox < -1e-6 { "east" } else { none }
  let v = if oy > 1e-6 { "south" } else if oy < -1e-6 { "north" } else { none }
  if h == none and v == none { "center" } else if h == none { v } else if (
    v == none
  ) { h } else { v + "-" + h }
}

// Place an edge's intrinsic weight/label (`tag`) at `pos` with a filled
// `note-bg` halo behind it, mirroring the node note/tag slots. `anchor`
// names which side of the label box sits at `pos`: a straight edge passes
// the near-side anchor (via `_tag-anchor`) with a small perpendicular gap,
// so the em-scaled box extends away from the line and never overlaps it
// however many digits the weight has — cetz measures the real box, so this
// stays font-size aware without a layout `context` for `measure` (and
// direct `cetz.canvas` use keeps working). Apex-placed tags (self-loops,
// bezier edges) pass the default "center". The opaque halo also masks any
// other edge passing beneath the label.
#let _edge-tag(draw, pos, tag, rt, anchor: "center") = draw.content(
  pos,
  anchor: anchor,
  frame: "rect",
  fill: rt.note-bg,
  stroke: none,
  padding: 0.06,
  text(fill: rt.edge-tag-fill, size: 0.8em, tag),
)

// Half-extents `(hw, hh)` of a node in cetz units, given its resolved style
// and (already-resolved) label. The shapes:
//   * "circle"             — `r` (default 0.6), hw == hh
//   * "ellipse"            — `rx`/`ry` (default 0.95 / 0.6)
//   * "rectangle"/"square" — `rx`/`ry` (default 0.6 / 0.6, the historical
//                            1.2x1.2 box)
// `autosize: true` overrides the fixed extents by measuring the label and
// padding it (`pad-x`/`pad-y`). For circle/ellipse the padded box is scaled
// by ~1.3 so the rectangular text bounds (near-)inscribe in the ellipse; a
// rectangle just takes the padded box. Autosize REQUIRES a layout context
// (it calls `measure`); the standard render path always supplies one (the
// `slides.typ` helpers wrap each frame in `context`). The cetz canvas
// default length is 1cm per unit, so pt -> unit is `/ 1cm`.
#let _node-extents(shape, s, label) = {
  if s.at("autosize", default: false) {
    let m = measure(text(weight: "bold", label))
    let mw = m.width / 1cm / 2
    let mh = m.height / 1cm / 2
    let px = s.at("pad-x", default: 0.22)
    let py = s.at("pad-y", default: 0.16)
    if shape == "circle" or shape == "ellipse" {
      // Enlarge the padded text box so it inscribes in the ellipse. A full
      // sqrt(2) fits the box corners exactly, but glyphs don't reach the
      // corners, so 1.3 looks tight without cropping descenders.
      ((mw + px) * 1.3, (mh + py) * 1.3)
    } else {
      (mw + px, mh + py)
    }
  } else if shape == "circle" {
    let r = s.at("r", default: 0.6)
    (r, r)
  } else if shape == "ellipse" {
    (s.at("rx", default: 0.95), s.at("ry", default: 0.6))
  } else {
    (s.at("rx", default: 0.6), s.at("ry", default: 0.6))
  }
}

// Distance from a node's center to its boundary along the unit direction
// `(ux, uy)`, used to trim an edge so its endpoint/arrowhead lands flush on
// the node outline. Ellipse (and circle, where `hw == hh`) uses the
// closed-form ray-ellipse intersection; rectangle uses the ray-box
// intersection. `(ux, uy)` must be unit length.
#let _boundary-dist(shape, hw, hh, ux, uy) = {
  if shape == "rectangle" or shape == "square" {
    let tx = if calc.abs(ux) < 1e-6 { none } else { hw / calc.abs(ux) }
    let ty = if calc.abs(uy) < 1e-6 { none } else { hh / calc.abs(uy) }
    if tx == none { ty } else if ty == none { tx } else { calc.min(tx, ty) }
  } else {
    1 / calc.sqrt(calc.pow(ux / hw, 2) + calc.pow(uy / hh, 2))
  }
}

// Move `from` toward `to` by the node's boundary distance along that
// direction, landing an edge endpoint on the node outline. Returns `from`
// unchanged for a degenerate (zero-length) direction. Trimming toward an
// arbitrary point (not just the other endpoint) lets a bent edge meet the
// boundary along its curve tangent.
#let _trim-toward(shape, hw, hh, from, to) = {
  let vx = to.at(0) - from.at(0)
  let vy = to.at(1) - from.at(1)
  let l = calc.sqrt(vx * vx + vy * vy)
  if l == 0 { return from }
  let (nx, ny) = (vx / l, vy / l)
  let d = _boundary-dist(shape, hw, hh, nx, ny)
  (from.at(0) + nx * d, from.at(1) + ny * d)
}

// ===================================================================
// draw-graph
// ===================================================================

/// Emit the cetz draw commands for one styled snapshot of a positioned
/// graph, _without_ wrapping them in a `cetz.canvas` — the caller owns the
/// canvas, so you can add your own annotations and anchor them with
/// `anchor(<id>)` or `anchor(edge-key(u, v))`.
///
/// Edges are drawn first and the filled node glyphs on top, so the line
/// ends are cleanly occluded by the nodes. Each edge's intrinsic
/// weight/label is drawn near its midpoint in `theme.render.edge-tag-fill`;
/// a snapshot edge `tag` overrides that text, and a snapshot `note` (gold)
/// draws an operation annotation on the edge. Directed graphs get filled
/// arrowheads (the mark fill follows the edge stroke) unless an edge sets
/// its own `mark`; filling them keeps a mutual pair from showing each line
/// through the other's tip. A self-edge (`u == v`) draws as a teardrop loop
/// above the node rather than a zero-length line.
///
/// Two edge-style keys shape an edge's geometry. `bend` (cetz units,
/// positive = left of the u->v direction) curves it into an arc; giving a
/// mutual directed pair the same bend fans the two arcs to opposite sides,
/// so they read as distinct edges instead of overlapping into one line.
/// `label-offset` (signed cetz units, default `0.12`) seats a *straight*
/// edge's weight/label off the line: the sign picks the side (same
/// convention as `bend`) and the magnitude the gap. A bent edge places its
/// label on the convex side and ignores `label-offset`.
///
/// -> content
#let draw-graph(
  /// The positioned graph — see the module header for its shape.
  /// -> dictionary
  pg,
  /// Style overlay for this snapshot; `blank-snapshot()` draws it
  /// unstyled.
  /// -> dictionary
  snapshot,
  /// Base node styling, applied beneath the snapshot's per-node styles.
  /// -> dictionary
  node-style: (:),
  /// Base edge styling, applied beneath the snapshot's per-edge styles.
  /// -> dictionary
  edge-style: (:),
  /// The full resolved theme. The backend reads `theme.render`.
  /// -> dictionary
  theme: default-theme,
  /// Wrap the whole graph in a cetz group of this name, qualifying every
  /// element anchor under it — `anchor(id, canvas: name)`. `none` draws
  /// into the enclosing canvas directly.
  /// -> none | str
  name: none,
) = {
  import cetz.draw
  let rt = theme.render
  let nodes = pg.nodes
  let directed = pg.at("directed", default: false)

  // Resolve every node's style, label, shape, and half-extents up front so
  // the edge pass can trim to each endpoint's true boundary (not a fixed
  // radius) and the node pass can draw at the right size. Sharing one
  // resolution keeps the two passes consistent and measures each autosize
  // label once (Typst's result cache covers the rest).
  let resolved = (:)
  for (id, n) in nodes {
    let s = merge-into(node-style, snapshot.nodes.at(id, default: (:)))
    let raw-label = n.at("label", default: auto)
    let default-label = if raw-label == auto { id } else { raw-label }
    let label = s.at("label", default: default-label)
    let shape = s.at("shape", default: "circle")
    let (hw, hh) = _node-extents(shape, s, label)
    resolved.insert(id, (style: s, label: label, shape: shape, hw: hw, hh: hh))
  }

  let body = {
    // --- edges first (occluded by the nodes drawn afterwards) ---
    for e in pg.edges {
      let s = merge-into(edge-style, snapshot.edges.at(e.key, default: (:)))
      if s.at("hide", default: false) { continue }
      let p = nodes.at(e.u).pos
      let q = nodes.at(e.v).pos
      let nm = anchor(e.key)
      let stroke-c = s.at("stroke", default: rt.edge-stroke)
      // Default directed arrowheads are *filled* (the mark fill follows the
      // edge stroke's paint). A hollow `>` lets the line show through the
      // tip — for a pair of opposite directed edges the two lines visibly
      // cross each arrowhead; a solid triangle occludes them cleanly.
      let mark = if "mark" in s {
        s.mark
      } else if directed {
        (end: ">", fill: stroke-paint(stroke-c))
      } else { none }

      // The intrinsic weight/label drawn near the edge; a snapshot `tag`
      // overrides it, a snapshot `note` is the gold operation annotation.
      let intrinsic = {
        let lbl = e.at("label", default: auto)
        if lbl == auto {
          let w = e.at("weight", default: none)
          if w == none { none } else { str(w) }
        } else { lbl }
      }
      // An explicitly empty label (`[]` or `""`) suppresses the weight
      // *and* its `note-bg` halo — otherwise an empty label box would still
      // be drawn.
      let tag = s.at("tag", default: intrinsic)
      if tag == [] or tag == "" { tag = none }
      let note = s.at("note", default: none)
      let gu = resolved.at(e.u)

      if e.u == e.v {
        // Self-loop: a teardrop bezier bulging out of the node's top face,
        // since a center-to-center line would collapse to a point. The
        // arrowhead (when directed) lands back on the node at the right
        // attach point; weight/note sit above the loop's apex.
        let (x, y) = p
        let r = calc.max(gu.hw, gu.hh)
        let attach(a) = {
          let (ux, uy) = (calc.cos(a), calc.sin(a))
          let d = _boundary-dist(gu.shape, gu.hw, gu.hh, ux, uy)
          (x + ux * d, y + uy * d)
        }
        let start = attach(110deg)
        let end = attach(70deg)
        let c1 = (x - r * 1.7, y + r * 3.2)
        let c2 = (x + r * 1.7, y + r * 3.2)
        draw.bezier(
          start,
          end,
          c1,
          c2,
          stroke: stroke-c,
          name: nm,
          ..if mark != none { (mark: mark) },
        )
        // The apex of the cubic (t = 0.5); anchor labels above it.
        let apex-y = (
          0.125 * start.at(1)
            + 0.375 * c1.at(1)
            + 0.375 * c2.at(1)
            + 0.125 * end.at(1)
        )
        if tag != none {
          _edge-tag(draw, (x, apex-y + 0.35), tag, rt)
        }
        if note != none {
          let nf = s.at("note-fill", default: rt.note-fill)
          draw.content((x, apex-y), text(fill: nf, size: 0.8em, note))
        }
        continue
      }

      let gv = resolved.at(e.v)
      let dx = q.at(0) - p.at(0)
      let dy = q.at(1) - p.at(1)
      if dx == 0 and dy == 0 { continue } // coincident distinct nodes
      let mid = ((p.at(0) + q.at(0)) / 2, (p.at(1) + q.at(1)) / 2)
      // `bend` (cetz units) curves the edge: the control point is the
      // straight midpoint pushed perpendicular by this much, positive =
      // left of the u->v travel direction. A mutual directed pair (A->B and
      // B->A) given one shared bend value bows to opposite sides, so the
      // two arcs read as distinct edges instead of overlapping into a
      // single line. 0 (the default) draws the straight edge.
      let bend = s.at("bend", default: 0)

      if bend == 0 {
        // Trim both ends to each endpoint's node boundary so a directed
        // edge's arrowhead lands just outside the target shape instead of
        // at its occluded center. Shape-aware: a wide ellipse or rectangle
        // is trimmed by more along its long axis than a circle would be.
        let p2 = _trim-toward(gu.shape, gu.hw, gu.hh, p, q)
        let q2 = _trim-toward(gv.shape, gv.hw, gv.hh, q, p)
        draw.line(
          p2,
          q2,
          stroke: stroke-c,
          name: nm,
          ..if mark != none { (mark: mark) },
        )
        // The intrinsic weight/label, off the line; a snapshot `tag`
        // overrides it. Push by a small gap, not to the box center, and
        // anchor the box's near side so a wide multi-digit weight grows
        // away from the edge. `label-offset` (signed cetz units) chooses
        // the side: positive = left of the u->v direction (the same sign
        // convention as `bend`), negative = right; the magnitude is the
        // gap. `_tag-anchor` reads the signed offset, so flipping the sign
        // moves the label to the other side *and* keeps its box growing
        // away from the line.
        if tag != none {
          let (ox, oy) = _perp-offset(dx, dy, s.at("label-offset", default: 0.12))
          _edge-tag(
            draw,
            (mid.at(0) + ox, mid.at(1) + oy),
            tag,
            rt,
            anchor: _tag-anchor(ox, oy),
          )
        }
        // The operation note (gold) on the edge midpoint.
        if note != none {
          let nf = s.at("note-fill", default: rt.note-fill)
          draw.content(mid, text(fill: nf, size: 0.8em, note))
        }
      } else {
        // Quadratic bezier; the control point is the perpendicular-offset
        // midpoint. Endpoints trim along the curve's end tangents (toward
        // the control point) so a directed arrowhead still meets the
        // boundary cleanly.
        let (ox, oy) = _perp-offset(dx, dy, bend)
        let ctrl = (mid.at(0) + ox, mid.at(1) + oy)
        let p2 = _trim-toward(gu.shape, gu.hw, gu.hh, p, ctrl)
        let q2 = _trim-toward(gv.shape, gv.hw, gv.hh, q, ctrl)
        draw.bezier(
          p2,
          q2,
          ctrl,
          stroke: stroke-c,
          name: nm,
          ..if mark != none { (mark: mark) },
        )
        // Labels at the arc's apex (quadratic t = 0.5), nudged further out
        // on the convex side so they clear the curve.
        let apex = (
          0.25 * p.at(0) + 0.5 * ctrl.at(0) + 0.25 * q.at(0),
          0.25 * p.at(1) + 0.5 * ctrl.at(1) + 0.25 * q.at(1),
        )
        if tag != none {
          let (tx, ty) = _perp-offset(dx, dy, if bend > 0 { 0.3 } else { -0.3 })
          _edge-tag(draw, (apex.at(0) + tx, apex.at(1) + ty), tag, rt)
        }
        if note != none {
          let nf = s.at("note-fill", default: rt.note-fill)
          draw.content(apex, text(fill: nf, size: 0.8em, note))
        }
      }
    }

    // --- nodes on top ---
    for (id, n) in nodes {
      let info = resolved.at(id)
      let s = info.style
      if s.at("hide", default: false) { continue }
      let pos = n.pos
      let (x, y) = pos
      let shape = info.shape
      let hw = info.hw
      let hh = info.hh
      let fill-c = s.at("fill", default: rt.node-fill)
      let stroke-c = s.at("stroke", default: rt.node-stroke)
      let nm = anchor(id)
      let glyph = {
        if shape == "circle" {
          draw.circle(pos, radius: hw, fill: fill-c, stroke: stroke-c, name: nm)
        } else if shape == "ellipse" {
          // cetz draws an ellipse when `radius` is an `(rx, ry)` pair.
          draw.circle(
            pos,
            radius: (hw, hh),
            fill: fill-c,
            stroke: stroke-c,
            name: nm,
          )
        } else if shape == "rectangle" or shape == "square" {
          draw.rect(
            (x - hw, y - hh),
            (x + hw, y + hh),
            fill: fill-c,
            stroke: stroke-c,
            name: nm,
          )
        } else {
          panic(
            "draw-graph: unknown node shape "
              + repr(shape)
              + "; supported: \"circle\", \"ellipse\", \"rectangle\"/\"square\".",
          )
        }
        let label = info.label
        let tf = s.at("text-fill", default: rt.node-text-fill)
        // Bold via `weight:` rather than `*..*` so an ambient `show strong`
        // rule can't override the contrast-aware fill.
        draw.content(pos, text(weight: "bold", fill: tf, label))
        // Note slot (gold) — east of the node, clearing its half-width.
        // Carries Dijkstra distances. A filled `note-bg` frame sits behind
        // it so the annotation stays legible when an edge leaving the node
        // passes underneath — graphs can't predict edge directions the way
        // trees can.
        let note = s.at("note", default: none)
        if note != none {
          let nf = s.at("note-fill", default: rt.note-fill)
          draw.content(
            (x + hw + 0.15, y),
            anchor: "west",
            frame: "rect",
            fill: rt.note-bg,
            stroke: none,
            padding: 0.06,
            text(fill: nf, size: 0.8em, note),
          )
        }
        // Tag slot — west of the node, in the marginal annotation colour.
        // Same `note-bg` backing as the note slot.
        let tag = s.at("tag", default: none)
        if tag != none {
          draw.content(
            (x - hw - 0.05, y),
            anchor: "east",
            frame: "rect",
            fill: rt.note-bg,
            stroke: none,
            padding: 0.06,
            text(fill: rt.edge-stroke, size: 0.7em, tag),
          )
        }
      }
      // `ghost` keeps the node's exact footprint and its anchors but paints
      // nothing — the progressive-reveal slot.
      if s.at("ghost", default: false) {
        draw.hide(glyph, bounds: true)
      } else { glyph }
    }
  }

  if name == none { body } else { draw.group(body, name: name) }
}
