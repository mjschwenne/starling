// Graph rendering backend — the graph-specific layer on top of the
// structure-agnostic kernel in `anim-core.typ`. Holds the cetz graph
// drawing (`draw-graph`), node/edge identity helpers (`edge-key`,
// `node-anchor`), and the graph-bound `make-graph-renderer` wrapper
// that injects `draw-graph` into the generic `Renderer`.
//
// This is the graph analog of `tree-anim.typ`: it knows how to *draw* a
// laid-out graph but nothing about graph algorithms — that lives in the
// `Graph` class in `graph.typ`, mirroring how `bst.typ` rides on
// `draw-tree`. The two are deliberately split.
//
// Node / edge identity
// --------------------
// Graphs have no root and no path-from-root, so `PathId` (binary/n-ary
// tree paths) does not apply. Instead:
//   * Nodes are keyed by a user-chosen string id (e.g. "A", "s", "0").
//   * Edges are keyed by `edge-key(u, v, directed)` — `"u->v"` when
//     directed, sorted `"u--v"` when undirected (so an undirected edge
//     has one canonical key regardless of endpoint order).
// Snapshot dicts (from `anim-core.typ`) use these strings as keys; the
// core never interprets them.
//
// Positioned-graph input
// ----------------------
// `draw-graph` consumes an opaque "positioned graph" dict (built by
// `Graph.positioned` in `graph.typ`):
//   (
//     directed: bool,
//     nodes: (id: (label: any, pos: (x, y))),
//     edges: (array of (key: str, u: str, v: str, weight: any, label: any)),
//   )
// Positions are in cetz units; layout (manual or auto) is the caller's
// concern, keeping the renderer layout-engine agnostic.

#import "@preview/typsy:0.2.2": *
#import "@preview/cetz:0.5.2"
#import "./anim-core.typ": *
#import "./anim-core.typ" as core

// ===================================================================
// Node / edge identity
// ===================================================================

/// Typsy refinement: a graph node id. Any string.
#let GraphNodeId = Str

/// Canonical snapshot key for the edge between #raw("u") and #raw("v").
/// Directed graphs key edges by #raw("\"u->v\"") (order significant);
/// undirected graphs sort the endpoints into #raw("\"u--v\"") so the
/// same edge has one key regardless of which endpoint is named first.
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

/// The fully-qualified cetz anchor name for the node #raw("id") drawn by
/// @@draw-graph(). Use it to attach your own callouts to a node when you
/// call #raw("draw-graph") inside your own #raw("cetz.canvas"). The
/// #raw("prefix") must match the #raw("node-prefix") passed to
/// #raw("draw-graph"). Sub-anchors follow (e.g.
/// #raw("node-anchor(\"A\") + \".north\"")).
///
/// -> str
#let node-anchor(
  /// Node id.
  /// -> str
  id,
  /// Per-node name prefix; must match #raw("draw-graph")'s
  /// #raw("node-prefix").
  /// -> str
  prefix: "node-",
) = prefix + id

// ===================================================================
// draw-graph
// ===================================================================

// Perpendicular unit offset (scaled) for placing a label off an edge
// line. `dx`/`dy` is the edge direction; returns `(ox, oy)` to add to
// the midpoint. Degenerate (zero-length) edges get no offset.
#let _perp-offset(dx, dy, amount) = {
  let len = calc.sqrt(dx * dx + dy * dy)
  if len == 0 { (0, 0) } else { (-dy / len * amount, dx / len * amount) }
}

// Compass anchor (vertical-first, e.g. "south-east") naming the side of a
// label box that faces the edge, given the perpendicular offset `(ox, oy)`
// that seats the box off the line. Anchoring that side at the offset point
// makes the box grow *away* from the line, so a wide multi-digit weight
// clears it by its own measured width rather than crossing back over a
// fixed center gap. Near-axis offsets (one component ~0) drop that axis so
// the box stays centered along it (e.g. a horizontal edge gets "south").
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
// so the em-scaled box extends away from the line and never overlaps it no
// matter how many digits the weight has — cetz measures the real box, so
// this stays font-size aware without a layout `context` for `measure` (and
// direct `cetz.canvas` use still works). Apex-placed tags (self/bezier
// edges) pass the default `"center"`. The opaque halo still masks any other
// edge that happens to pass beneath the label.
#let _edge-tag(draw, pos, tag, render-theme, anchor: "center") = draw.content(
  pos,
  anchor: anchor,
  frame: "rect",
  fill: render-theme.note-bg,
  stroke: none,
  padding: 0.06,
  text(fill: render-theme.edge-tag-fill, size: 0.8em, tag),
)

// The paint (color) of a stroke spec, for filling a directed edge's
// arrowhead to match its line. Accepts a color, dict, or stroke; falls
// back to black for `auto`/`none` or a stroke with no explicit paint.
#let _stroke-paint(s) = {
  if s == auto or s == none { return black }
  let st = stroke(s)
  if st.paint == auto { black } else { st.paint }
}

// Half-extents `(hw, hh)` of a node in cetz units, given its resolved
// style and (already-resolved) label. The shapes:
//   * "circle"             — `r` (default 0.6), hw == hh
//   * "ellipse"            — `rx`/`ry` (default 0.95 / 0.6)
//   * "rectangle"/"square" — `rx`/`ry` (default 0.6 / 0.6, the historical
//                            1.2×1.2 box)
// `autosize: true` overrides the fixed extents by measuring the label
// and padding it (`pad-x`/`pad-y`). For circle/ellipse the padded box is
// scaled by ~1.3 so the rectangular text bounds (near-)inscribe in the
// ellipse; a rectangle just takes the padded box. Autosize REQUIRES a layout
// context (it calls `measure`); the standard render path always supplies
// one (the lib helpers wrap each frame in `context { }`). The cetz
// canvas default length is 1cm per unit, so pt → unit is `/ 1cm`.
#let _node-extents(shape, s, label) = {
  if s.at("autosize", default: false) {
    let m = measure(text(weight: "bold", label))
    let mw = m.width / 1cm / 2
    let mh = m.height / 1cm / 2
    let px = s.at("pad-x", default: 0.22)
    let py = s.at("pad-y", default: 0.16)
    if shape == "circle" or shape == "ellipse" {
      // Enlarge the padded text box so it inscribes in the ellipse.
      // A full √2 fits the box corners exactly, but glyphs don't reach
      // the corners, so 1.3 looks tight without cropping descenders.
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

// Distance from a node's center to its boundary along the unit
// direction `(ux, uy)`, used to trim an edge so its endpoint/arrowhead
// lands flush on the node outline. Ellipse (and circle, where
// `hw == hh`) uses the closed-form ray–ellipse intersection; rectangle
// uses the ray–box intersection. `(ux, uy)` must be unit length.
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
// direction, landing an edge endpoint on the node outline. Returns
// `from` unchanged for a degenerate (zero-length) direction. Trimming
// toward an arbitrary point (not just the other endpoint) lets a bent
// edge meet the boundary along its curve tangent.
#let _trim-toward(shape, hw, hh, from, to) = {
  let vx = to.at(0) - from.at(0)
  let vy = to.at(1) - from.at(1)
  let l = calc.sqrt(vx * vx + vy * vy)
  if l == 0 { return from }
  let (nx, ny) = (vx / l, vy / l)
  let d = _boundary-dist(shape, hw, hh, nx, ny)
  (from.at(0) + nx * d, from.at(1) + ny * d)
}

/// Emit the cetz draw commands for one styled snapshot of a positioned
/// graph, _without_ wrapping them in a #raw("cetz.canvas"). The caller
/// wraps the canvas — use this to add your own cetz annotations
/// alongside the graph — see @@node-anchor().
///
/// Edges are drawn first (straight lines between node centers) and the
/// filled node glyphs on top, so the line ends are cleanly occluded by
/// the nodes. Each edge's intrinsic weight/label is drawn at its
/// midpoint in the render theme's #raw("edge-tag-fill"); a snapshot
/// edge #raw("tag") overrides that text, and a snapshot #raw("note")
/// (gold) draws an operation annotation on the edge. Directed graphs
/// get filled arrowheads (the mark fill follows the edge stroke) unless
/// an edge sets its own #raw("mark"); the fill keeps a pair of opposite
/// edges from showing the line through each other's arrowhead. A
/// self-edge (#raw("u == v")) is drawn as a teardrop loop above the
/// node rather than a zero-length line. An edge-style #raw("bend")
/// (cetz units, positive = left of the u→v direction) curves the edge
/// into an arc; giving a mutual directed pair the same bend fans the two
/// arcs to opposite sides so they no longer overlap into one line.
///
/// -> content
#let draw-graph(
  /// The positioned graph — see the module header for its shape.
  /// -> dictionary
  pg,
  /// Style overlay for this snapshot. Use #raw("blank-snapshot()")
  /// (from the animation core) for an unstyled graph.
  /// -> Snapshot
  snapshot,
  /// Default node-style overrides applied before per-node overrides.
  /// -> dictionary
  default-node-style: (:),
  /// Default edge-style overrides applied before per-edge overrides.
  /// -> dictionary
  default-edge-style: (:),
  /// Structural defaults — the lowest layer of the style chain.
  /// -> dictionary
  render-theme: default-render-theme,
  /// Per-node cetz element-name prefix. Must match the #raw("prefix")
  /// argument to @@node-anchor().
  /// -> str
  node-prefix: "node-",
) = {
  import cetz.draw
  let nodes = pg.nodes
  let directed = pg.at("directed", default: false)

  // Resolve every node's style, label, shape, and half-extents up front
  // so the edge pass can trim to each endpoint's true boundary (not a
  // fixed radius) and the node pass can draw at the right size. Sharing
  // one resolution keeps the two passes consistent and measures each
  // autosize label once (Typst's result cache covers the rest).
  let resolved = (:)
  for (id, n) in nodes {
    let s = _merge-into(default-node-style, snapshot.nodes.at(id, default: (:)))
    let raw-label = n.at("label", default: auto)
    let default-label = if raw-label == auto { id } else { raw-label }
    let label = s.at("label", default: default-label)
    let shape = s.at("shape", default: "circle")
    let (hw, hh) = _node-extents(shape, s, label)
    resolved.insert(id, (style: s, label: label, shape: shape, hw: hw, hh: hh))
  }

  // --- edges first (occluded by nodes drawn afterwards) ---
  for e in pg.edges {
    let s = _merge-into(
      default-edge-style,
      snapshot.edges.at(e.key, default: (:)),
    )
    if s.at("hide", default: false) { continue }
    let p = nodes.at(e.u).pos
    let q = nodes.at(e.v).pos
    let stroke-c = s.at("stroke", default: render-theme.edge-stroke)
    // Default directed arrowheads are *filled* (mark fill follows the
    // edge stroke's paint). A hollow `>` lets the line show through the
    // tip — for a pair of opposite directed edges the two lines visibly
    // cross each arrowhead; a solid triangle occludes them cleanly.
    let mark = if "mark" in s {
      s.mark
    } else if directed { (end: ">", fill: _stroke-paint(stroke-c)) } else { none }

    // Intrinsic weight/label drawn near the edge; snapshot `tag`
    // overrides it, snapshot `note` is the gold operation annotation.
    let intrinsic = {
      let lbl = e.at("label", default: auto)
      if lbl == auto {
        let w = e.at("weight", default: none)
        if w == none { none } else { str(w) }
      } else { lbl }
    }
    let tag = s.at("tag", default: intrinsic)
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
        ..if mark != none { (mark: mark) },
      )
      // Apex of the cubic (t = 0.5); anchor labels above it.
      let apex-y = (
        0.125 * start.at(1) + 0.375 * c1.at(1) + 0.375 * c2.at(1) + 0.125 * end.at(1)
      )
      if tag != none {
        _edge-tag(draw, (x, apex-y + 0.35), tag, render-theme)
      }
      if note != none {
        let nf = s.at("note-fill", default: render-theme.note-fill)
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
    // left of the u->v travel direction. A mutual directed pair (A->B
    // and B->A) given one shared bend value bows to opposite sides, so
    // the two arcs read as distinct edges instead of overlapping into a
    // single line. 0 (default) draws the straight edge.
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
        ..if mark != none { (mark: mark) },
      )
      // Intrinsic weight/label, off the line; snapshot `tag` overrides.
      // Push by a small gap, not to the box center, and anchor the box's
      // near side so a wide multi-digit weight grows away from the edge.
      if tag != none {
        let (ox, oy) = _perp-offset(dx, dy, 0.12)
        _edge-tag(
          draw,
          (mid.at(0) + ox, mid.at(1) + oy),
          tag,
          render-theme,
          anchor: _tag-anchor(ox, oy),
        )
      }
      // Operation note (gold) on the edge midpoint.
      if note != none {
        let nf = s.at("note-fill", default: render-theme.note-fill)
        draw.content(mid, text(fill: nf, size: 0.8em, note))
      }
    } else {
      // Quadratic bezier; control point is the perpendicular-offset
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
        _edge-tag(draw, (apex.at(0) + tx, apex.at(1) + ty), tag, render-theme)
      }
      if note != none {
        let nf = s.at("note-fill", default: render-theme.note-fill)
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
    let fill-c = s.at("fill", default: render-theme.node-fill)
    let stroke-c = s.at("stroke", default: render-theme.node-stroke)
    let nm = node-prefix + id
    if shape == "circle" {
      draw.circle(pos, radius: hw, fill: fill-c, stroke: stroke-c, name: nm)
    } else if shape == "ellipse" {
      // cetz draws an ellipse when `radius` is a `(rx, ry)` pair.
      draw.circle(pos, radius: (hw, hh), fill: fill-c, stroke: stroke-c, name: nm)
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
    let tf = s.at("text-fill", default: render-theme.node-text-fill)
    // Bold via `weight:` rather than `*..*` so an ambient
    // `show strong` rule can't override the contrast-aware fill.
    draw.content(pos, text(weight: "bold", fill: tf, label))
    // Note slot (gold) — east of the node, clearing its half-width.
    // Carries Dijkstra distances. A filled `note-bg` frame sits behind
    // it so the annotation stays legible when an edge leaving the node
    // passes underneath — graphs can't predict edge directions the way
    // trees can.
    let note = s.at("note", default: none)
    if note != none {
      let nf = s.at("note-fill", default: render-theme.note-fill)
      draw.content(
        (x + hw + 0.15, y),
        anchor: "west",
        frame: "rect",
        fill: render-theme.note-bg,
        stroke: none,
        padding: 0.06,
        text(fill: nf, size: 0.8em, note),
      )
    }
    // Tag slot — west of the node, marginal annotation color. Same
    // `note-bg` backing as the note slot.
    let tag = s.at("tag", default: none)
    if tag != none {
      draw.content(
        (x - hw - 0.05, y),
        anchor: "east",
        frame: "rect",
        fill: render-theme.note-bg,
        stroke: none,
        padding: 0.06,
        text(fill: render-theme.edge-stroke, size: 0.7em, tag),
      )
    }
  }
}

// ===================================================================
// Graph-bound wrappers over the generic kernel
// ===================================================================

// The draw backend the graph renderer injects into the generic
// `Renderer`. Wrapped in a singleton dict `(fn: ..)` so typsy doesn't
// self-inject on the function-typed `draw` field (see `anim-core.typ`).
#let _draw-graph-backend = (
  fn: (structure, snapshot, dns, des, rt) => draw-graph(
    structure,
    snapshot,
    default-node-style: dns,
    default-edge-style: des,
    render-theme: rt,
  ),
)

/// Build a graph #raw("Renderer") seeded with one blank initial frame,
/// bound to the @@draw-graph() backend. Thin wrapper over the generic
/// #raw("make-renderer") in #raw("anim-core.typ") that injects the
/// graph draw backend.
///
/// -> Renderer
#let make-graph-renderer(
  /// The positioned graph to render.
  /// -> dictionary
  pg,
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
  pg,
  _draw-graph-backend,
  default-node-style: default-node-style,
  default-edge-style: default-edge-style,
  sticky: sticky,
  theme: theme,
)
