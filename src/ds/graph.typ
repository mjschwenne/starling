// Graph — an undirected-or-directed weighted graph, and the four classic
// algorithms taught on one.
//
// The structure is small: a node map, an edge list, a directedness flag, and
// an optional positions map. Everything interesting is in the animations —
// Prim, Kruskal, Dijkstra, and the two traversals — each of which walks the
// graph once, records a *moment* per step, and turns those into frames.
//
// Layout is deliberately decoupled. Positions (id -> (x, y) in cetz units)
// are data the caller supplies; `auto-layout` (graph-layout.typ, optional)
// can compute them via graphviz, and every display takes a `layout:` argument
// that calls it. Nothing here depends on that package unless you ask for it.
//
// Identity: a node is its user-chosen string id, an edge is
// `edge-key(u, v, directed)`. Tree paths do not apply — a graph has no root.
//
// step.kind vocabulary
// --------------------
//   static                 the one frame of `display`
//   init                   the opening frame of every animation
//   consider / commit      Prim: weigh the frontier, then add the min edge
//   consider / add / reject    Kruskal: weigh an edge, then take or skip it
//   visit / update / skip  Dijkstra: poll the min, relax it, discard a stale
//                          duplicate
//   recon                  Dijkstra: one hop of the path reconstruction
//   visit                  BFS / DFS: one node reached
//   found / not-found      how a targeted traversal ended
//   spanning-tree          the terminal prune frame, showing the tree alone
//   settled                terminal success (an algorithm run to completion)
// Every frame of an algorithm display also carries `step.aux-views` — the
// algorithm's own bookkeeping, for `aux-strip` (aux.typ). The final frame
// carries `step.result`, which for a graph is always the unchanged input:
// none of these algorithms mutates the structure.

#import "../core/draw-util.typ": anchor, muted, text-fill-for
#import "../core/frame.typ": make-frames, make-renderer
#import "../core/snapshot.typ": blank-snapshot, with-edge, with-node
#import "../core/text.typ": alt-describe, alt-intro
#import "../core/theme.typ": resolve-theme
#import "../draw/graph.typ": draw-graph, edge-key
#import "../graph-layout.typ" as _layout

#let _DS = "Graph"

// ===================================================================
// Construction
// ===================================================================

/// Add a node. `pos` is its `(x, y)` in cetz units, or `none` to leave it
/// unplaced (for `auto-layout`, or for positions passed to a display).
/// -> dictionary
#let add-node(g, id, label: auto, pos: none) = {
  let nodes = g.nodes
  nodes.insert(id, (label: label))
  let positions = g.positions
  if pos != none { positions.insert(id, pos) }
  (..g, nodes: nodes, positions: positions)
}

/// Add an edge between two existing nodes. `weight` drives the algorithms;
/// `label`, when set, is what gets drawn in its place.
/// -> dictionary
#let add-edge(g, u, v, weight: 1, label: auto) = {
  assert(
    u in g.nodes and v in g.nodes,
    message: "graph.add-edge: both endpoints must exist (" + u + ", " + v + ").",
  )
  (..g, edges: g.edges + ((u: u, v: v, weight: weight, label: label),))
}

/// Place (or move) a node.
/// -> dictionary
#let with-position(g, id, pos) = {
  let positions = g.positions
  positions.insert(id, pos)
  (..g, positions: positions)
}

/// Build a graph from a list of nodes plus a list of edges.
///
/// Each node is one of:
/// - a bare id string (unplaced — supply positions later),
/// - an `(id, label)` pair (a display label, still unplaced),
/// - an `(id, x, y)` triple (placed, label defaults to the id), or
/// - an `(id, x, y, label)` 4-tuple (both).
///
/// Each edge is `(u, v)` optionally followed by a weight and/or a label. The
/// third slot dispatches by type: a number is the `weight`, anything else is
/// a display `label` drawn in its place. `(u, v, weight, label)` sets both —
/// the numeric weight still drives Dijkstra and the MSTs.
///
/// ```typ
/// #let g = graph.new(
///   (("A", 0, 0), ("B", 3, 1), ("C", 1.5, 2.4)),
///   edges: (("A", "B", 7), ("B", "C", 2), ("A", "C", 4)),
/// )
/// ```
///
/// -> dictionary
#let new(
  /// The nodes — see above for the four accepted forms.
  /// -> array
  nodes,
  /// The edges, each `(u, v)` plus an optional weight and/or label.
  /// -> array
  edges: (),
  /// Whether edges are one-way (arrowheads, ordered edge keys).
  /// -> bool
  directed: false,
) = {
  let g = (kind: "graph", nodes: (:), edges: (), directed: directed, positions: (:))
  for nd in nodes {
    if type(nd) == str {
      g = add-node(g, nd)
    } else {
      assert(
        type(nd) == array and nd.len() >= 2 and nd.len() <= 4,
        message: "graph.new: a node is an id, (id, label), (id, x, y), or "
          + "(id, x, y, label); got "
          + repr(nd)
          + ".",
      )
      let id = nd.at(0)
      if nd.len() == 2 {
        g = add-node(g, id, label: nd.at(1))
      } else {
        let label = if nd.len() > 3 { nd.at(3) } else { auto }
        g = add-node(g, id, label: label, pos: (nd.at(1), nd.at(2)))
      }
    }
  }
  for e in edges {
    assert(
      type(e) == array and e.len() >= 2,
      message: "graph.new: an edge needs at least (u, v); got " + repr(e) + ".",
    )
    let weight = 1
    let label = auto
    if e.len() == 3 {
      let third = e.at(2)
      if type(third) == int or type(third) == float {
        weight = third
      } else { label = third }
    } else if e.len() >= 4 {
      weight = e.at(2)
      label = e.at(3)
    }
    g = add-edge(g, e.at(0), e.at(1), weight: weight, label: label)
  }
  g
}

// ===================================================================
// Queries
// ===================================================================

/// This graph's canonical key for the edge between `u` and `v` — the key its
/// snapshots and `anchor` use. `edge-key(u, v, directed:)` is the same
/// function without a graph to read the directedness from.
/// -> str
#let ek(g, u, v) = edge-key(u, v, directed: g.directed)

/// Whether `id` is a node of this graph.
/// -> bool
#let contains-node(g, id) = id in g.nodes

/// Whether an edge joins `u` and `v`. Undirected graphs answer the same
/// either way round; directed ones do not.
/// -> bool
#let contains-edge(g, u, v) = {
  let k = ek(g, u, v)
  g.edges.any(e => ek(g, e.u, e.v) == k)
}

/// The out-neighbours of `id`, as an array of `(id, weight)`. Every incident
/// edge contributes its other endpoint in an undirected graph; only edges
/// leaving `id` do in a directed one.
/// -> array
#let neighbors(g, id) = {
  let out = ()
  for e in g.edges {
    if e.u == id {
      out.push((id: e.v, weight: e.weight))
    } else if not g.directed and e.v == id {
      out.push((id: e.u, weight: e.weight))
    }
  }
  out
}

/// The weight of the edge between `u` and `v`. Panics when there is none.
/// -> any
#let weight(g, u, v) = {
  let k = ek(g, u, v)
  for e in g.edges {
    if ek(g, e.u, e.v) == k { return e.weight }
  }
  panic("graph.weight: no edge between " + u + " and " + v + ".")
}

// A node's *display* label: its own when set, else its id. Used by the
// adjacency tables, which place content directly.
#let _disp-label(g, id) = {
  let l = g.nodes.at(id).at("label", default: auto)
  if l == auto { id } else { l }
}

// A node's name in prose — the same rule, but a label that isn't a plain
// string can't be spliced into a caption or alt string, so it falls back to
// the id.
#let _text-label(g, id) = {
  let l = g.nodes.at(id).at("label", default: auto)
  if type(l) == str { l } else { id }
}

/// A one-line prose summary — the opening line of every alt text.
/// -> str
#let describe(g) = {
  let ids = g.nodes.keys()
  let kind = if g.directed { "directed" } else { "undirected" }
  let conn = if g.directed { " -> " } else { " - " }
  let edge-strs = g.edges.map(e => (
    _text-label(g, e.u) + conn + _text-label(g, e.v) + " (w=" + str(e.weight) + ")"
  ))
  (
    kind
      + " graph with "
      + str(ids.len())
      + " nodes ("
      + ids.map(id => _text-label(g, id)).join(", ")
      + ") and "
      + str(g.edges.len())
      + " edges: "
      + edge-strs.join("; ")
  )
}

/// Check the structural invariants: every edge's endpoints exist, and no two
/// edges share a canonical key. Returns `true` or panics with the first
/// violation. Positions are validated lazily, by `positioned`.
/// -> bool
#let check-invariants(g) = {
  let seen = ()
  for e in g.edges {
    assert(
      e.u in g.nodes and e.v in g.nodes,
      message: "graph.check-invariants: edge endpoint missing ("
        + e.u
        + ", "
        + e.v
        + ").",
    )
    let k = ek(g, e.u, e.v)
    assert(
      not seen.contains(k),
      message: "graph.check-invariants: duplicate edge " + k + ".",
    )
    seen.push(k)
  }
  true
}

// ===================================================================
// Rendering
// ===================================================================

/// The positioned-graph dict the backend consumes — the entry point for a
/// hand-composed cetz canvas (`draw-graph`) or the op command stream. Uses
/// the graph's own positions unless an explicit map is passed; panics if any
/// node lacks one.
///
/// `scale` multiplies every coordinate about the origin, spreading nodes
/// apart while their drawn size stays fixed — the manual-layout analog of
/// `auto-layout`'s `unit:`.
///
/// -> dictionary
#let positioned(g, positions: auto, scale: 1) = {
  let pos-map = if positions == auto { g.positions } else { positions }
  let nodes = (:)
  for (id, data) in g.nodes {
    assert(
      id in pos-map,
      message: "graph.positioned: node '"
        + id
        + "' has no position; pass manual positions or use auto-layout.",
    )
    let p = pos-map.at(id)
    nodes.insert(id, (
      label: data.at("label", default: auto),
      pos: (p.at(0) * scale, p.at(1) * scale),
    ))
  }
  let edges = g.edges.map(e => (
    key: ek(g, e.u, e.v),
    u: e.u,
    v: e.v,
    weight: e.at("weight", default: none),
    label: e.at("label", default: auto),
  ))
  (directed: g.directed, nodes: nodes, edges: edges)
}

// The positions a display will draw with. With `layout: none` the caller's
// map (or, via `auto`, the graph's own) is used unchanged and
// `diagraph-layout` is never touched — which is what keeps that package an
// optional dependency. A non-`none` engine name lays the graph out here
// instead, passing `sizes: auto` so graphviz reserves room per node from a
// cheap label-length estimate. That estimate is eager (no `measure`, so it
// runs outside a context) while the drawn size is measured precisely in
// `draw-graph`; the two only approximate each other, and graphviz's node
// margins absorb the slack. Tune absolute spacing with `layout-unit:` or
// `scale:`.
#let _resolve-positions(g, positions, layout, layout-unit) = if layout == none {
  positions
} else {
  _layout.auto-layout(g, engine: layout, unit: layout-unit, sizes: auto)
}

// The one place a display turns its layout arguments into a positioned graph.
#let _pg(g, positions, scale, layout, layout-unit) = positioned(
  g,
  positions: _resolve-positions(g, positions, layout, layout-unit),
  scale: scale,
)

/// A `Renderer` over this graph, bound to the graph backend — the entry point
/// for driving an animation yourself with the op command stream. Pass
/// `sticky: true` when each frame's styling should accumulate.
/// -> dictionary
#let renderer(
  g,
  positions: auto,
  scale: 1,
  layout: none,
  layout-unit: 36pt,
  node-style: (:),
  edge-style: (:),
  sticky: false,
  theme: (:),
) = make-renderer(
  _pg(g, positions, scale, layout, layout-unit),
  draw-graph,
  node-style: node-style,
  edge-style: edge-style,
  sticky: sticky,
  theme: theme,
)

// Turn per-frame specs into frames. Every graph animation draws the same
// positioned graph in every frame — the structure never changes — so unlike
// the trees there is nothing to swap per spec.
#let _frames(pg, specs, theme, node-style) = make-frames(
  specs.map(s => (structure: pg, ..s)),
  draw-graph,
  theme: theme,
  node-style: node-style,
)

// ===================================================================
// Tabular (non-cetz) representations
// ===================================================================
//
// The adjacency matrix and list are plain Typst tables — no cetz, no frames —
// so they return directly-placeable content rather than an array of frames.
// They still follow the theme, resolving it in their own `context` (the
// `slides.typ` helpers never see them).

// Render an adjacency matrix. `headers` holds the per-node header labels (row
// i and column i share one); `cells` is the n x n grid of
// `(present, value)` entries the caller resolved. Header cells take the
// render theme's node fill + bold text; absent cells are muted. The empty
// top-left corner squares the grid.
#let _matrix-content(headers, cells, rt) = {
  let n = headers.len()
  let hdr = c => text(weight: "bold", fill: rt.node-text-fill, c)
  let head = (table.cell(fill: rt.node-fill)[],)
  for h in headers { head.push(table.cell(fill: rt.node-fill, hdr(h))) }
  let body = ()
  for (i, row) in cells.enumerate() {
    body.push(table.cell(fill: rt.node-fill, hdr(headers.at(i))))
    for cell in row {
      let col = if cell.present { rt.node-text-fill } else {
        muted(rt.node-text-fill)
      }
      body.push(text(fill: col, cell.value))
    }
  }
  table(
    columns: n + 1,
    align: center + horizon,
    stroke: 0.5pt + rt.node-stroke,
    inset: (x: 0.6em, y: 0.45em),
    ..head,
    ..body,
  )
}

// Render an adjacency list as a two-column table. Each `rows` entry is
// `(header, items)`; an empty `items` shows `empty-marker`, muted.
#let _list-content(rows, empty-marker, rt) = {
  let hdr = c => text(weight: "bold", fill: rt.node-text-fill, c)
  let body = ()
  for r in rows {
    body.push(table.cell(fill: rt.node-fill, hdr(r.header)))
    let listing = if r.items.len() == 0 {
      text(fill: muted(rt.node-text-fill), empty-marker)
    } else {
      text(fill: rt.node-text-fill, r.items.join([, ]))
    }
    body.push(table.cell(align: left + horizon, listing))
  }
  table(
    columns: (auto, auto),
    align: (center + horizon, left + horizon),
    stroke: 0.5pt + rt.node-stroke,
    inset: (x: 0.6em, y: 0.45em),
    ..body,
  )
}

// An edge's display value: its label when it has one, else its weight.
#let _edge-value(e) = {
  let lbl = e.at("label", default: auto)
  if lbl == auto { str(e.at("weight", default: 1)) } else { lbl }
}

/// The adjacency matrix as placeable table content (not frames — wrap it in a
/// figure yourself for a caption or alt text).
///
/// Cells default to 1/0 presence; `weights: true` shows each edge's display
/// value and `none-marker` for non-edges. An undirected graph gives a
/// symmetric matrix; a directed one reads row = source, column = target, with
/// self-loops on the diagonal.
///
/// -> content
#let adjacency-matrix(
  g,
  /// Show edge values instead of 1/0 presence.
  /// -> bool
  weights: false,
  /// What to draw where there is no edge, when `weights: true`.
  /// -> str
  none-marker: "·",
  /// Partial theme override, merged over the ambient theme.
  /// -> dictionary
  theme: (:),
) = {
  let ids = g.nodes.keys()
  let emap = (:)
  for e in g.edges { emap.insert(ek(g, e.u, e.v), e) }
  let headers = ids.map(id => _disp-label(g, id))
  let cells = ids.map(u => ids.map(v => {
    let k = ek(g, u, v)
    if k in emap {
      (present: true, value: if weights { _edge-value(emap.at(k)) } else { "1" })
    } else {
      (present: false, value: if weights { none-marker } else { "0" })
    }
  }))
  context _matrix-content(headers, cells, resolve-theme(theme).render)
}

/// The adjacency list as placeable table content, pairing each node with its
/// adjacency. A directed graph lists out-neighbours; an undirected one lists
/// every incident neighbour (a self-loop appears once). `weights: true`
/// appends each edge's display value in parentheses.
///
/// -> content
#let adjacency-list(
  g,
  /// Append each edge's display value to its neighbour.
  /// -> bool
  weights: false,
  /// What to draw for a node with no neighbours.
  /// -> str
  empty-marker: "—",
  /// Partial theme override, merged over the ambient theme.
  /// -> dictionary
  theme: (:),
) = {
  let rows = g.nodes.keys().map(u => {
    let items = ()
    for e in g.edges {
      let other = if e.u == u {
        e.v
      } else if (not g.directed) and e.v == u { e.u } else { none }
      if other != none {
        items.push(if weights {
          [#_disp-label(g, other) (#_edge-value(e))]
        } else { _disp-label(g, other) })
      }
    }
    (header: _disp-label(g, u), items: items)
  })
  context _list-content(rows, empty-marker, resolve-theme(theme).render)
}

// ===================================================================
// The static display
// ===================================================================

/// The graph as a single static frame.
/// -> array
#let display(
  g,
  /// Node positions, or `auto` for the graph's own.
  /// -> auto | dictionary
  positions: auto,
  /// Multiplier on every coordinate, spreading nodes apart at a fixed drawn
  /// size.
  /// -> float
  scale: 1,
  /// One base node style applied beneath every per-frame style — where a
  /// whole-graph `shape` / `autosize` / `rx` / `ry` goes.
  /// -> dictionary
  node-style: (:),
  /// A graphviz engine name (e.g. `"neato"`) to lay the graph out internally,
  /// or `none` to use `positions`. Only a non-`none` value loads the optional
  /// `diagraph-layout` dependency.
  /// -> none | str
  layout: none,
  /// The cetz-unit size of one graphviz layout unit.
  /// -> length
  layout-unit: 36pt,
  /// Partial theme override, merged over the ambient theme.
  /// -> dictionary
  theme: (:),
) = {
  let pg = _pg(g, positions, scale, layout, layout-unit)
  _frames(
    pg,
    (
      (
        build: _ => blank-snapshot(),
        caption: none,
        step: (kind: "static", result: g),
        alt: alt-describe(_DS, describe(g)),
      ),
    ),
    theme,
    node-style,
  )
}

// ===================================================================
// Prim's minimum spanning tree
// ===================================================================
//
// Grow the tree from `start`, repeatedly adding the lightest edge crossing
// the cut. Two frames per selection: "consider" (the frontier in the search
// stroke, its minimum ringed in the attention stroke) and "commit" (that edge
// in the success stroke, the new node settled and filled). Visited nodes and
// tree edges accumulate.

// Walk Prim's algorithm, recording one moment per frame.
#let _prim-moments(g, start) = {
  let all-ids = g.nodes.keys()
  let visited = (start,)
  let tree-keys = ()
  let total = 0
  let moments = (
    (kind: "init", visited: visited, tree-keys: (), frontier: (), chosen: none, total: 0),
  )
  let stop = false
  while visited.len() < all-ids.len() and not stop {
    let crossing = g.edges.filter(e => (
      (visited.contains(e.u) and not visited.contains(e.v))
        or (visited.contains(e.v) and not visited.contains(e.u))
    ))
    if crossing.len() == 0 {
      stop = true
    } else {
      let chosen = crossing.fold(
        crossing.first(),
        (m, e) => if e.weight < m.weight { e } else { m },
      )
      moments.push((
        kind: "consider",
        visited: visited,
        tree-keys: tree-keys,
        frontier: crossing.map(e => ek(g, e.u, e.v)),
        chosen: chosen,
        total: total,
      ))
      let new-node = if visited.contains(chosen.u) { chosen.v } else { chosen.u }
      visited = visited + (new-node,)
      tree-keys = tree-keys + (ek(g, chosen.u, chosen.v),)
      total = total + chosen.weight
      moments.push((
        kind: "commit",
        visited: visited,
        tree-keys: tree-keys,
        frontier: (),
        chosen: chosen,
        new-node: new-node,
        total: total,
      ))
    }
  }
  let tail = (
    visited: visited,
    tree-keys: tree-keys,
    frontier: (),
    chosen: none,
    total: total,
  )
  // The run ends twice over: once on the finished tree, then on a terminal
  // prune frame that drops every non-tree edge so the animation closes on the
  // spanning tree alone (the same close as the BFS/DFS spanning-tree mode).
  moments + ((kind: "settled", ..tail), (kind: "prune", ..tail))
}

// The frontier priority queue for `aux-strip`: the crossing edges relative to
// `visited`, sorted ascending by weight. On a "consider" moment the minimum
// is the edge the canvas rings, so tag it `chosen`.
#let _prim-pq(g, visited, mark-chosen) = {
  let crossing = g.edges.filter(e => (
    (visited.contains(e.u) and not visited.contains(e.v))
      or (visited.contains(e.v) and not visited.contains(e.u))
  ))
  crossing
    .sorted(key: e => e.weight)
    .enumerate()
    .map(((i, e)) => (
      u: e.u,
      v: e.v,
      weight: e.weight,
      status: if mark-chosen and i == 0 { "chosen" } else { "candidate" },
    ))
}

// One spec per moment: caption, step metadata, alt text.
#let _prim-specs(g, start, moments, build-all) = {
  let name = id => _text-label(g, id)
  let pq-note = items => if items.len() == 0 {
    " Frontier is empty."
  } else {
    let listing = items
      .map(it => name(it.u) + "–" + name(it.v) + " (" + str(it.weight) + ")")
      .join(", ")
    " Frontier: " + listing + "."
  }
  moments
    .enumerate()
    .map(((i, m)) => {
      let pq = _prim-pq(g, m.visited, m.kind == "consider")
      let views = ((kind: "pq", items: pq),)
      let spec = if m.kind == "init" {
        (
          caption: [Start at #start],
          step: (kind: "init", start: start),
          alt: alt-intro(_DS, describe(g), "run Prim's algorithm from " + name(start))
            + pq-note(pq),
        )
      } else if m.kind == "consider" {
        let c = m.chosen
        (
          caption: [Min crossing edge: #(c.u)–#(c.v) (#(c.weight))],
          step: (kind: "consider", edge: (c.u, c.v), weight: c.weight),
          alt: "Examining the frontier; the lightest crossing edge is "
            + name(c.u)
            + "–"
            + name(c.v)
            + " with weight "
            + str(c.weight)
            + "."
            + pq-note(pq),
        )
      } else if m.kind == "commit" {
        let c = m.chosen
        (
          caption: [Add #(c.u)–#(c.v); tree weight #(m.total)],
          step: (kind: "commit", edge: (c.u, c.v), node: m.new-node, total: m.total),
          alt: "Adding edge "
            + name(c.u)
            + "–"
            + name(c.v)
            + " and node "
            + name(m.new-node)
            + "; tree weight is now "
            + str(m.total)
            + "."
            + pq-note(pq),
        )
      } else if m.kind == "settled" {
        (
          caption: [MST weight #(m.total)],
          step: (kind: "settled", total: m.total),
          alt: "Minimum spanning tree complete; total weight "
            + str(m.total)
            + "."
            + pq-note(pq),
        )
      } else {
        (
          caption: [Spanning tree],
          step: (
            kind: "spanning-tree",
            edges: m.tree-keys.len(),
            nodes: m.visited.len(),
            total: m.total,
          ),
          alt: "Removed the non-tree edges; the minimum spanning tree ("
            + str(m.tree-keys.len())
            + " edge(s) over "
            + str(m.visited.len())
            + " node(s), total weight "
            + str(m.total)
            + ") remains."
            + pq-note(pq),
        )
      }
      (
        build: th => build-all(th).at(i),
        caption: spec.caption,
        step: (
          ..spec.step,
          aux-views: views,
          ..if i == moments.len() - 1 { (result: g) },
        ),
        alt: spec.alt,
      )
    })
}

/// Animate Prim's minimum spanning tree, growing from `start`.
/// -> array
#let prim-display(
  g,
  /// The node the tree grows from.
  /// -> str
  start,
  positions: auto,
  scale: 1,
  node-style: (:),
  layout: none,
  layout-unit: 36pt,
  theme: (:),
) = {
  assert(
    start in g.nodes,
    message: "graph.prim-display: start node '" + start + "' not in graph.",
  )
  let pg = _pg(g, positions, scale, layout, layout-unit)
  let moments = _prim-moments(g, start)

  // One shared closure builds every snapshot; each frame indexes into the
  // result, so Typst's call cache pays for the walk once. The styling is
  // recomputed per moment rather than accumulated — the transient frontier
  // highlights have to clear cleanly.
  let build-all = th => moments.map(m => {
    let s = blank-snapshot()
    for id in m.visited {
      s = with-node(s, id, (stroke: th.op.settled-stroke, fill: th.op.success-fill))
    }
    for k in m.tree-keys { s = with-edge(s, k, (stroke: th.op.success-stroke)) }
    if m.kind == "consider" {
      for k in m.frontier { s = with-edge(s, k, (stroke: th.op.search-stroke)) }
      s = with-edge(
        s,
        ek(g, m.chosen.u, m.chosen.v),
        (stroke: th.op.attention-stroke),
      )
    } else if m.kind == "prune" {
      // Hide every edge that isn't in the spanning tree.
      for e in pg.edges {
        if not m.tree-keys.contains(e.key) { s = with-edge(s, e.key, (hide: true)) }
      }
    }
    s
  })

  _frames(pg, _prim-specs(g, start, moments, build-all), theme, node-style)
}

// ===================================================================
// Kruskal's minimum spanning tree
// ===================================================================
//
// Consider edges in weight order, adding each unless its endpoints are
// already connected (which would close a cycle). The components — the
// union-find forest — are shown by node color: same color, same set. Three
// frames per edge: "consider", then "add" or "reject".

// The union-find root of `x` under a `parent` map. No path compression:
// teaching graphs are small, and keeping this a pure function of its
// arguments lets it run against any moment's snapshot of the map.
#let _uf-find(parent, x) = {
  let r = x
  while parent.at(r) != r { r = parent.at(r) }
  r
}

// Walk Kruskal's algorithm, recording one moment per frame. `processed`
// counts the edges already decided and `current` indexes the one under
// consideration (or `none`); together they drive the edge-list aux view's
// per-edge status and its cursor.
#let _kruskal-moments(g, sorted-edges) = {
  let parent = (:)
  for id in g.nodes.keys() { parent.insert(id, id) }
  let tree-keys = ()
  let total = 0
  let moments = (
    (
      kind: "init",
      parent: parent,
      tree-keys: (),
      edge: none,
      total: 0,
      processed: 0,
      current: none,
    ),
  )
  for (ci, e) in sorted-edges.enumerate() {
    let ru = _uf-find(parent, e.u)
    let rv = _uf-find(parent, e.v)
    moments.push((
      kind: "consider",
      parent: parent,
      tree-keys: tree-keys,
      edge: e,
      total: total,
      processed: ci,
      current: ci,
    ))
    if ru != rv {
      parent.insert(ru, rv)
      tree-keys = tree-keys + (ek(g, e.u, e.v),)
      total = total + e.weight
    }
    moments.push((
      kind: if ru != rv { "add" } else { "reject" },
      parent: parent,
      tree-keys: tree-keys,
      edge: e,
      total: total,
      processed: ci + 1,
      current: none,
    ))
  }
  let tail = (
    parent: parent,
    tree-keys: tree-keys,
    edge: none,
    total: total,
    processed: sorted-edges.len(),
    current: none,
  )
  moments + ((kind: "settled", ..tail), (kind: "prune", ..tail))
}

// The node ids grouped by union-find root — one group per component, in
// first-seen order.
#let _partition(all-ids, parent) = {
  let groups = (:)
  let order = ()
  for id in all-ids {
    let r = _uf-find(parent, id)
    if r in groups {
      groups.at(r).push(id)
    } else {
      groups.insert(r, (id,))
      order.push(r)
    }
  }
  order.map(r => groups.at(r))
}

// A moment's two aux views. The edge list tags each sorted edge: `added` if
// it is a tree edge, `current` if it is the one under consideration,
// `rejected` if already decided but not added, else `pending`.
#let _kruskal-views(g, sorted-edges, sorted-keys, m) = {
  let items = range(sorted-edges.len()).map(j => {
    let e = sorted-edges.at(j)
    (
      u: e.u,
      v: e.v,
      weight: e.weight,
      status: if m.tree-keys.contains(sorted-keys.at(j)) {
        "added"
      } else if m.current != none and j == m.current {
        "current"
      } else if j < m.processed { "rejected" } else { "pending" },
    )
  })
  (
    (kind: "edge-list", items: items),
    (kind: "partition", items: _partition(g.nodes.keys(), m.parent)),
  )
}

// The caption / step / alt for one Kruskal moment. `name` labels a node the
// way it is drawn and `aux-note` spells the current partition out for the
// alt text, both closed over by the caller.
#let _kruskal-meta(m, g, all-ids, name, aux-note) = if m.kind == "init" {
  (
    caption: [Sort edges by weight],
    step: (kind: "init"),
    alt: alt-intro(_DS, describe(g), "run Kruskal's algorithm")
      + " Edges are considered in increasing weight order; each node "
      + "starts in its own component."
      + aux-note(m),
  )
} else if m.kind == "consider" {
  let e = m.edge
  (
    caption: [Consider #(e.u)–#(e.v) (#(e.weight))],
    step: (kind: "consider", edge: (e.u, e.v), weight: e.weight),
    alt: "Considering edge "
      + name(e.u)
      + "–"
      + name(e.v)
      + " with weight "
      + str(e.weight)
      + "."
      + aux-note(m),
  )
} else if m.kind == "add" {
  let e = m.edge
  (
    caption: [Add #(e.u)–#(e.v); weight #(m.total)],
    step: (kind: "add", edge: (e.u, e.v), total: m.total),
    alt: name(e.u)
      + " and "
      + name(e.v)
      + " are in different components; add the edge and merge them. "
      + "Total weight "
      + str(m.total)
      + "."
      + aux-note(m),
  )
} else if m.kind == "reject" {
  let e = m.edge
  (
    caption: [Reject #(e.u)–#(e.v) (cycle)],
    step: (kind: "reject", edge: (e.u, e.v)),
    alt: name(e.u)
      + " and "
      + name(e.v)
      + " are already connected; this edge would form a cycle, so skip "
      + "it."
      + aux-note(m),
  )
} else if m.kind == "settled" {
  (
    caption: [MST weight #(m.total)],
    step: (kind: "settled", total: m.total),
    alt: "Minimum spanning tree complete; total weight "
      + str(m.total)
      + "."
      + aux-note(m),
  )
} else {
  (
    caption: [Spanning tree],
    step: (
      kind: "spanning-tree",
      edges: m.tree-keys.len(),
      nodes: all-ids.len(),
      total: m.total,
    ),
    alt: "Removed the non-tree edges; the minimum spanning tree ("
      + str(m.tree-keys.len())
      + " edge(s) over "
      + str(all-ids.len())
      + " node(s), total weight "
      + str(m.total)
      + ") remains."
      + aux-note(m),
  )
}

// One spec per moment.
#let _kruskal-specs(g, sorted-edges, sorted-keys, moments, build-all) = {
  let all-ids = g.nodes.keys()
  let name = id => _text-label(g, id)
  let aux-note = m => (
    " Components: "
      + _partition(all-ids, m.parent)
        .map(gr => "{" + gr.map(name).join(", ") + "}")
        .join(" ")
      + "."
  )
  moments
    .enumerate()
    .map(((i, m)) => {
      let views = _kruskal-views(g, sorted-edges, sorted-keys, m)
      let spec = _kruskal-meta(m, g, all-ids, name, aux-note)
      (
        build: th => build-all(th).at(i),
        caption: spec.caption,
        step: (
          ..spec.step,
          aux-views: views,
          ..if i == moments.len() - 1 { (result: g) },
        ),
        alt: spec.alt,
      )
    })
}

/// Animate Kruskal's minimum spanning tree.
/// -> array
#let kruskal-display(
  g,
  positions: auto,
  scale: 1,
  node-style: (:),
  layout: none,
  layout-unit: 36pt,
  theme: (:),
) = {
  let pg = _pg(g, positions, scale, layout, layout-unit)
  let all-ids = g.nodes.keys()
  let n = all-ids.len()
  let id-index = (:)
  for (i, id) in all-ids.enumerate() { id-index.insert(id, i) }
  let sorted-edges = g.edges.sorted(key: e => e.weight)
  let sorted-keys = sorted-edges.map(e => ek(g, e.u, e.v))
  let moments = _kruskal-moments(g, sorted-edges)

  // One shared closure for every snapshot. Component membership is drawn by
  // sampling the traversal palette at the root's index, so a merge shows up
  // as two groups of nodes taking one color.
  let build-all = th => {
    let grad = gradient.linear(..th.op.traversal-palette)
    let color-of = root => {
      let idx = id-index.at(root)
      grad.sample(if n <= 1 { 0% } else { (idx / (n - 1)) * 100% })
    }
    moments.map(m => {
      let s = blank-snapshot()
      for id in all-ids {
        let fill = color-of(_uf-find(m.parent, id))
        s = with-node(s, id, (fill: fill, text-fill: text-fill-for(fill)))
      }
      for k in m.tree-keys { s = with-edge(s, k, (stroke: th.op.success-stroke)) }
      if m.kind == "consider" {
        s = with-edge(s, ek(g, m.edge.u, m.edge.v), (stroke: th.op.attention-stroke))
      } else if m.kind == "reject" {
        s = with-edge(s, ek(g, m.edge.u, m.edge.v), (stroke: th.op.danger-stroke))
      } else if m.kind == "prune" {
        for e in pg.edges {
          if not m.tree-keys.contains(e.key) { s = with-edge(s, e.key, (hide: true)) }
        }
      }
      s
    })
  }

  _frames(
    pg,
    _kruskal-specs(g, sorted-edges, sorted-keys, moments, build-all),
    theme,
    node-style,
  )
}

// ===================================================================
// Dijkstra's shortest paths
// ===================================================================
//
// Every node carries its tentative distance in the note slot (∞ until
// reached). The priority queue is modelled *explicitly*, with the
// add-as-you-go, new-instance semantics students actually implement: it holds
// `(node, dist)` entries, starts with the source alone, and each improving
// relaxation adds a FRESH entry rather than decreasing an existing key — so a
// node can appear several times. Polling a stale duplicate for an
// already-visited node is discarded on a "skip" frame, which is exactly why
// the loop needs its `if u not visited` guard.

// A tentative distance in prose.
#let _dlabel(d) = if d == none { "∞" } else { str(d) }

// Poll order: min by `(dist, node)` — distance first, node id alphabetically
// to break ties, so a run is reproducible.
#let _sort-pq(entries) = entries.sorted(key: e => (e.dist, e.node))

// One priority-queue snapshot for `aux-strip`. `head-status` rings the front
// (min) entry; `added` (a set of `(node, dist)` pairs) marks the entries this
// moment enqueued.
#let _pq-view(entries, head-status: none, added: ()) = {
  _sort-pq(entries)
    .enumerate()
    .map(((i, e)) => (
      node: e.node,
      dist: e.dist,
      status: if head-status != none and i == 0 {
        head-status
      } else if added.contains((e.node, e.dist)) { "added" } else { "candidate" },
    ))
}

// The predecessor edges as a set of edge keys — the shortest-path tree so far.
#let _tree-keys-of(g, prev) = prev.pairs().map(((v, u)) => ek(g, u, v))

// Walk Dijkstra's algorithm, recording one moment per frame. Stops early when
// `target` is polled. When `reconstruct` is on and the target was reached, a
// run of "recon" moments walks `prev` back from the end.
#let _dijkstra-moments(g, source, target, reconstruct) = {
  let all-ids = g.nodes.keys()
  let dist = (:)
  for id in all-ids { dist.insert(id, none) }
  dist.insert(source, 0)
  let prev = (:)
  let visited = ()
  let pq = ((node: source, dist: 0),)
  let blank = (u: none, relaxed: (), updated: ())
  let moments = (
    (
      kind: "init",
      dist: dist,
      prev: prev,
      visited: (),
      tree-keys: (),
      pq-view: _pq-view(pq, added: ((source, 0),)),
      ..blank,
    ),
  )
  let stop = false
  while pq.len() > 0 and not stop {
    let sorted = _sort-pq(pq)
    let head = sorted.first()
    let u = head.node
    // Remove the polled entry; the rest carries forward.
    pq = sorted.slice(1)
    if visited.contains(u) {
      // Stale duplicate: the entry that queued `u` was beaten by an earlier,
      // cheaper poll. Discard it and poll again.
      moments.push((
        ..blank,
        kind: "skip",
        dist: dist,
        prev: prev,
        visited: visited,
        u: u,
        du: head.dist,
        tree-keys: _tree-keys-of(g, prev),
        pq-view: _pq-view(sorted, head-status: "rejected"),
      ))
    } else {
      visited = visited + (u,)
      moments.push((
        ..blank,
        kind: "visit",
        dist: dist,
        prev: prev,
        visited: visited,
        u: u,
        du: head.dist,
        tree-keys: _tree-keys-of(g, prev),
        pq-view: _pq-view(sorted, head-status: "chosen"),
      ))
      if target != none and u == target {
        stop = true
      } else {
        let relaxed = ()
        let updated = ()
        let added = ()
        for nb in neighbors(g, u) {
          let v = nb.id
          if not visited.contains(v) {
            let nd = dist.at(u) + nb.weight
            if dist.at(v) == none or nd < dist.at(v) {
              dist.insert(v, nd)
              prev.insert(v, u)
              pq.push((node: v, dist: nd))
              relaxed.push(ek(g, u, v))
              updated.push(v)
              added.push((v, nd))
            }
          }
        }
        moments.push((
          kind: "update",
          dist: dist,
          prev: prev,
          visited: visited,
          u: u,
          relaxed: relaxed,
          updated: updated,
          tree-keys: _tree-keys-of(g, prev),
          pq-view: _pq-view(pq, added: added),
        ))
      }
    }
  }
  // The route to the target, read back through `prev`.
  let path-keys = ()
  let path-nodes = ()
  if target != none and dist.at(target) != none {
    let cur = target
    path-nodes = (cur,)
    while cur != source and (cur in prev) {
      let p = prev.at(cur)
      path-keys.push(ek(g, p, cur))
      path-nodes.push(p)
      cur = p
    }
  }
  // With `reconstruct` on and the end reachable, the closing frame does NOT
  // light the whole path — the reconstruction frames build it up instead.
  let recon-active = reconstruct and target != none and dist.at(target) != none
  moments.push((
    ..blank,
    kind: "settled",
    dist: dist,
    prev: prev,
    visited: visited,
    tree-keys: _tree-keys-of(g, prev),
    pq-view: _pq-view(pq),
    path-keys: if recon-active { () } else { path-keys },
    path-nodes: if recon-active { () } else { path-nodes },
    reconstruct: recon-active,
  ))
  // ConstructShortestPath: walk `prev` back from the end, inserting each node
  // at the front of the path. `full-path` runs source -> end, so the partial
  // after k inserts is its last k nodes ([end], [prev, end], …, the lot).
  if recon-active {
    let full-path = path-nodes.rev()
    let n = full-path.len()
    for k in range(1, n + 1) {
      let partial = full-path.slice(n - k)
      moments.push((
        ..blank,
        kind: "recon",
        dist: dist,
        prev: prev,
        visited: visited,
        tree-keys: _tree-keys-of(g, prev),
        pq-view: _pq-view(pq),
        path-nodes: partial,
        path-keys: range(partial.len() - 1).map(i => ek(
          g,
          partial.at(i),
          partial.at(i + 1),
        )),
        new-node: partial.first(),
        complete: k == n,
      ))
    }
  }
  moments
}

// The three aux views of one moment: the priority queue, and the `dist` and
// `prev` maps. `u` is marked `current`; nodes in `updated` are `added` (a
// value just improved).
#let _dijkstra-views(g, all-ids, m) = {
  let name = id => _text-label(g, id)
  let map-items(values) = all-ids.map(k => (
    key: k,
    value: values.at(k),
    status: if m.updated.contains(k) {
      "added"
    } else if (m.kind == "visit" or m.kind == "update") and m.u == k {
      "current"
    } else { "candidate" },
  ))
  // During reconstruction the search is over and the live structure is
  // `prev`, read back from the end: mark the cell read on this frame
  // (`prev[path[1]]`, which yielded the new front) `current` and the cells
  // read on earlier frames `added`, so the chain lights up as it is traced.
  // `dist` stays neutral.
  let recon-items(values, trace) = {
    let read-now = if m.path-nodes.len() >= 2 { m.path-nodes.at(1) } else { none }
    let read-before = if m.path-nodes.len() > 2 { m.path-nodes.slice(2) } else { () }
    all-ids.map(k => (
      key: k,
      value: values.at(k),
      status: if not trace {
        "candidate"
      } else if k == read-now {
        "current"
      } else if read-before.contains(k) { "added" } else { "candidate" },
    ))
  }
  let dvals = (:)
  for k in all-ids { dvals.insert(k, _dlabel(m.dist.at(k))) }
  let pvals = (:)
  for k in all-ids {
    let p = m.prev.at(k, default: none)
    pvals.insert(k, if p == none { "∅" } else { name(p) })
  }
  if m.kind == "recon" {
    (
      (kind: "dist-pq", items: m.pq-view),
      (kind: "dist-map", items: recon-items(dvals, false)),
      (kind: "prev-map", items: recon-items(pvals, true)),
    )
  } else {
    (
      (kind: "dist-pq", items: m.pq-view),
      (kind: "dist-map", items: map-items(dvals)),
      (kind: "prev-map", items: map-items(pvals)),
    )
  }
}

// The closing frame — which reads differently depending on whether there was
// a target, and whether a reconstruction phase follows.
#let _dijkstra-settled(g, source, target, m, dist-note) = {
  let name = id => _text-label(g, id)
  if m.reconstruct {
    (
      caption: [Reached #target (#(_dlabel(m.dist.at(target))))],
      step: (kind: "settled", target: target, dist: m.dist.at(target), reconstruct: true),
      alt: "Search complete; shortest distance from "
        + name(source)
        + " to "
        + name(target)
        + " is "
        + _dlabel(m.dist.at(target))
        + ". Now reconstruct the path from "
        + name(target)
        + " back through prev."
        + dist-note(m.dist),
    )
  } else if target != none {
    (
      caption: [Shortest path to #target: #(_dlabel(m.dist.at(target)))],
      step: (kind: "settled", target: target, dist: m.dist.at(target)),
      alt: "Dijkstra complete; shortest distance from "
        + name(source)
        + " to "
        + name(target)
        + " is "
        + _dlabel(m.dist.at(target))
        + "."
        + dist-note(m.dist),
    )
  } else {
    (
      caption: [Done],
      step: (kind: "settled"),
      alt: "Dijkstra complete; all reachable nodes visited." + dist-note(m.dist),
    )
  }
}

// One spec per moment.
#let _dijkstra-specs(g, source, target, moments, build-all) = {
  let all-ids = g.nodes.keys()
  let name = id => _text-label(g, id)
  // A compact "Distances: A=0, B=2, …" listing, appended to each alt.
  let dist-note = d => (
    " Distances: "
      + all-ids.map(k => name(k) + "=" + _dlabel(d.at(k))).join(", ")
      + "."
  )
  moments
    .enumerate()
    .map(((i, m)) => {
      let spec = if m.kind == "init" {
        (
          caption: [Add #source to queue],
          step: (kind: "init", source: source),
          alt: alt-intro(_DS, describe(g), "run Dijkstra's algorithm from " + name(source))
            + " Add "
            + name(source)
            + " to the priority queue with distance 0; every other distance "
            + "is infinity and every predecessor undefined."
            + dist-note(m.dist),
        )
      } else if m.kind == "visit" {
        (
          caption: [Visit #(m.u) (#(_dlabel(m.du)))],
          step: (kind: "visit", node: m.u, dist: m.du),
          alt: "Poll "
            + name(m.u)
            + " (distance "
            + _dlabel(m.du)
            + "), the queue's minimum; mark it visited."
            + dist-note(m.dist),
        )
      } else if m.kind == "update" {
        (
          caption: [Update neighbors of #(m.u)],
          step: (kind: "update", node: m.u, updated: m.updated),
          alt: "Update the unvisited neighbors of "
            + name(m.u)
            + "; "
            + str(m.updated.len())
            + " distance(s) improved and re-added to the queue."
            + dist-note(m.dist),
        )
      } else if m.kind == "skip" {
        (
          caption: [Skip #(m.u) — already visited],
          step: (kind: "skip", node: m.u),
          alt: "Poll "
            + name(m.u)
            + ", but it is already visited; discard this stale queue entry "
            + "and poll again."
            + dist-note(m.dist),
        )
      } else if m.kind == "recon" {
        let path-str = m.path-nodes.map(name).join(" → ")
        if m.complete {
          (
            caption: [Shortest path: #path-str (#(_dlabel(m.dist.at(target))))],
            step: (kind: "recon", path: m.path-nodes, complete: true),
            alt: "Reconstruction complete; the shortest path from "
              + name(source)
              + " to "
              + name(target)
              + " is "
              + m.path-nodes.map(name).join(" to ")
              + ", total distance "
              + _dlabel(m.dist.at(target))
              + ".",
          )
        } else {
          (
            caption: [Path: #path-str],
            step: (kind: "recon", path: m.path-nodes, complete: false),
            alt: "Reconstructing the path: prepend "
              + name(m.new-node)
              + " (its predecessor), giving "
              + m.path-nodes.map(name).join(" to ")
              + " so far.",
          )
        }
      } else {
        _dijkstra-settled(g, source, target, m, dist-note)
      }
      (
        build: th => build-all(th).at(i),
        caption: spec.caption,
        step: (
          ..spec.step,
          aux-views: _dijkstra-views(g, all-ids, m),
          ..if i == moments.len() - 1 { (result: g) },
        ),
        alt: spec.alt,
      )
    })
}

/// Animate Dijkstra's shortest paths from `source`.
///
/// With a `target:` the search stops the moment that node is polled. Add
/// `reconstruct: true` to follow it with the `ConstructShortestPath` phase,
/// which walks `prev` back from the end one hop per frame instead of lighting
/// the whole route at once.
///
/// -> array
#let dijkstra-display(
  g,
  /// The node distances are measured from.
  /// -> str
  source,
  /// Stop as soon as this node is polled; `none` runs to completion.
  /// -> none | str
  target: none,
  /// Show each node's tentative distance in its note slot. Turn it off when
  /// the `dist` aux map already carries them.
  /// -> bool
  node-distances: true,
  /// Append the path-reconstruction phase (requires a `target:`).
  /// -> bool
  reconstruct: false,
  positions: auto,
  scale: 1,
  node-style: (:),
  layout: none,
  layout-unit: 36pt,
  theme: (:),
) = {
  assert(
    source in g.nodes,
    message: "graph.dijkstra-display: source node '" + source + "' not in graph.",
  )
  assert(
    not reconstruct or target != none,
    message: "graph.dijkstra-display: reconstruct: true needs a `target:` — "
      + "the end of the path to walk back from.",
  )
  let pg = _pg(g, positions, scale, layout, layout-unit)
  let all-ids = g.nodes.keys()
  let moments = _dijkstra-moments(g, source, target, reconstruct)

  let build-all = th => moments.map(m => {
    let s = blank-snapshot()
    if node-distances {
      for id in all-ids { s = with-node(s, id, (note: _dlabel(m.dist.at(id)))) }
    }
    for id in m.visited {
      s = with-node(s, id, (stroke: th.op.settled-stroke, fill: th.op.success-fill))
    }
    for k in m.tree-keys { s = with-edge(s, k, (stroke: th.op.success-stroke)) }
    if m.u != none {
      // The polled node: attention on a fresh visit or update, danger on a
      // "skip" (a stale duplicate being discarded).
      let ring = if m.kind == "skip" { th.op.danger-stroke } else {
        th.op.attention-stroke
      }
      s = with-node(s, m.u, (stroke: ring))
    }
    if m.kind == "update" {
      for k in m.relaxed { s = with-edge(s, k, (stroke: th.op.search-stroke)) }
    }
    if m.kind == "settled" or m.kind == "recon" {
      // The route, drawn over the tree edges. During reconstruction it grows
      // one hop per frame, the just-prepended node ringed in attention.
      for k in m.at("path-keys", default: ()) {
        s = with-edge(s, k, (stroke: th.op.settled-stroke))
      }
      for id in m.at("path-nodes", default: ()) {
        s = with-node(s, id, (stroke: th.op.settled-stroke, fill: th.op.success-fill))
      }
      if m.kind == "recon" and not m.complete {
        s = with-node(s, m.new-node, (stroke: th.op.attention-stroke))
      }
    }
    s
  })

  _frames(pg, _dijkstra-specs(g, source, target, moments, build-all), theme, node-style)
}

// ===================================================================
// Breadth- and depth-first traversal
// ===================================================================
//
// One frame per visit: the node fills from the theme's `traversal-palette`
// and wears a badge with its 1-indexed position, while the caption
// accumulates the visit sequence — the graph counterpart of the trees'
// `*-order-display`s.
//
// Three variations ride the same renderer. A `target` makes it a *search*:
// the caller truncates `order` at the target (or runs to completion if it is
// unreachable) and a terminal frame reports the outcome. `tree-edges` swaps
// the palette for the spanning tree: each node joins with one uniform commit
// style, its discovery edge lights up, and a closing prune frame drops every
// edge that isn't in the tree.

// One shared closure for every snapshot of a traversal: the walk
// accumulates, so each frame carries the previous one's styling plus its
// own. Index 0 is the untouched graph, index i+1 the state after visiting
// `order.at(i)`; a search or a prune appends one more.
#let _traversal-build-all(pg, order, tree-edges, target) = th => {
  let n = order.len()
  let grad = gradient.linear(..th.op.traversal-palette)
  let cur = blank-snapshot()
  let out = (cur,)
  for (i, id) in order.enumerate() {
    if tree-edges == none {
      // Traversal: sample the palette across the visit order.
      let fill = grad.sample(if n <= 1 { 0% } else { (i / (n - 1)) * 100% })
      cur = with-node(
        cur,
        id,
        (fill: fill, text-fill: text-fill-for(fill), note: str(i + 1)),
      )
    } else {
      // Spanning tree: the node joins with one uniform commit style and its
      // discovery edge lights up. The root's entry is `none`.
      cur = with-node(
        cur,
        id,
        (
          fill: th.op.success-fill,
          text-fill: text-fill-for(th.op.success-fill),
          stroke: th.op.settled-stroke,
        ),
      )
      let k = tree-edges.at(i)
      if k != none { cur = with-edge(cur, k, (stroke: th.op.success-stroke)) }
    }
    out.push(cur)
  }
  if target != none {
    if order.contains(target) {
      cur = with-node(cur, target, (stroke: th.op.settled-stroke))
    }
    out.push(cur)
  }
  if tree-edges != none {
    // Prune: hide every edge that isn't a discovery edge. The tree styling
    // carries through, so only the surplus goes.
    let tree-keys = tree-edges.filter(e => e != none)
    for e in pg.edges {
      if not tree-keys.contains(e.key) { cur = with-edge(cur, e.key, (hide: true)) }
    }
    out.push(cur)
  }
  out
}

// The terminal frame of a *search*: the target was reached, or the walk ran
// out of reachable nodes without it.
#let _traversal-search-spec(build-all, n, target, label, found, aux) = if found {
  (
    build: th => build-all(th).at(n + 1),
    caption: [Found #label(target)],
    step: (kind: "found", node: target, visits: n),
    alt: "Found "
      + label(target)
      + " after visiting "
      + str(n)
      + " node(s); the search stops here.",
    aux: aux,
  )
} else {
  (
    build: th => build-all(th).at(n + 1),
    caption: [#label(target) not found],
    step: (kind: "not-found", target: target, visits: n),
    alt: "Visited all "
      + str(n)
      + " reachable node(s); "
      + label(target)
      + " was not found.",
    aux: aux,
  )
}

// The terminal frame of a spanning-tree run: everything but the discovery
// edges goes, leaving the tree alone.
#let _traversal-prune-spec(build-all, n, tree-edges, name, aux) = {
  let n-tree = tree-edges.filter(e => e != none).len()
  (
    build: th => build-all(th).at(n + 1),
    caption: [Spanning tree],
    step: (kind: "spanning-tree", edges: n-tree, nodes: n),
    alt: "Removed the non-tree edges; the "
      + name
      + " spanning tree ("
      + str(n-tree)
      + " edge(s) over "
      + str(n)
      + " node(s)) remains.",
    // The final (post-traversal) structure, so this frame's strip reads
    // like any other in the sequence.
    aux: aux,
  )
}

// Shared per-visit animation. `aux-states` is parallel to the frame sequence:
// index 0 is the initial structure, index i its state after visiting
// order[i-1].
#let _render-traversal(
  g,
  pg,
  order,
  name,
  aux-states,
  aux-kind,
  target: none,
  tree-edges: none,
  node-style: (:),
  theme: (:),
) = {
  let n = order.len()
  let searching = target != none
  let found = searching and order.contains(target)
  let label = id => _text-label(g, id)
  let start = if n > 0 { order.first() } else { "" }
  let aux-of = i => aux-states.at(i, default: ())
  let aux-title = if aux-kind == "queue" { "Queue" } else { "Stack" }
  let aux-str = a => if a.len() == 0 {
    "(empty)"
  } else { "[" + a.map(label).join(", ") + "]" }

  let build-all = _traversal-build-all(pg, order, tree-edges, target)

  let specs = (
    (
      build: th => build-all(th).at(0),
      caption: none,
      step: (kind: "init"),
      alt: alt-intro(
        _DS,
        describe(g),
        if searching {
          "search " + name + " from " + label(start) + " for " + label(target)
        } else { "traverse " + name + " from " + label(start) },
      )
        + " "
        + aux-title
        + " starts: "
        + aux-str(aux-of(0))
        + ".",
      aux: aux-of(0),
    ),
  )
  let output = ()
  for (i, id) in order.enumerate() {
    let a = aux-of(i + 1)
    output.push(label(id))
    specs.push((
      build: th => build-all(th).at(i + 1),
      caption: [Visited: #raw("[" + output.join(", ") + "]")],
      step: (kind: "visit", node: id, index: i + 1),
      alt: "Visited "
        + label(id)
        + " (visit "
        + str(i + 1)
        + " of "
        + str(n)
        + ")"
        + (if searching and id == target { " — this is the target." } else { "." })
        + " "
        + aux-title
        + " now: "
        + aux-str(a)
        + ".",
      aux: a,
    ))
  }
  if searching {
    specs.push(_traversal-search-spec(
      build-all,
      n,
      target,
      label,
      found,
      aux-states.at(-1, default: ()),
    ))
  }
  if tree-edges != none {
    specs.push(_traversal-prune-spec(
      build-all,
      n,
      tree-edges,
      name,
      aux-states.at(-1, default: ()),
    ))
  }
  // Fold each spec's aux snapshot into its step as the one-view list every
  // display emits, and stamp the result on the last frame.
  let last = specs.len() - 1
  _frames(
    pg,
    specs
      .enumerate()
      .map(((i, s)) => (
        build: s.build,
        caption: s.caption,
        step: (
          ..s.step,
          aux-views: ((kind: aux-kind, items: s.aux),),
          ..if i == last { (result: g) },
        ),
        alt: s.alt,
      )),
    theme,
    node-style,
  )
}

// The discovery edge of each visited node, parallel to `order` — the entry
// for the root is `none`.
#let _tree-edges(g, order, parents) = order.map(id => if id in parents {
  ek(g, parents.at(id), id)
} else { none })

// Guard the arguments shared by both traversals.
#let _assert-traversal(who, g, start, target, spanning-tree) = {
  assert(
    start in g.nodes,
    message: who + ": start node '" + start + "' not in graph.",
  )
  assert(
    target == none or target in g.nodes,
    message: who + ": target node " + repr(target) + " not in graph.",
  )
  assert(
    not spanning-tree or target == none,
    message: who + ": spanning-tree mode spans the whole reachable component; "
      + "it does not support a target.",
  )
}

/// Animate a breadth-first traversal from `start`.
///
/// A `target:` turns it into a search that stops the moment that node is
/// dequeued. `spanning-tree: true` renders the BFS tree instead of the
/// palette walk, closing on the tree alone.
///
/// -> array
#let bfs-display(
  g,
  /// Where the traversal begins.
  /// -> str
  start,
  /// Stop as soon as this node is visited; `none` covers the whole reachable
  /// component.
  /// -> none | str
  target: none,
  /// Enqueue each node's unseen neighbours in ascending id order rather than
  /// edge-declaration order, for a deterministic visit sequence.
  /// -> bool
  sort-frontier: false,
  /// Render the BFS spanning tree instead of the palette traversal.
  /// -> bool
  spanning-tree: false,
  positions: auto,
  scale: 1,
  node-style: (:),
  layout: none,
  layout-unit: 36pt,
  theme: (:),
) = {
  _assert-traversal("graph.bfs-display", g, start, target, spanning-tree)
  let pg = _pg(g, positions, scale, layout, layout-unit)
  let order = ()
  // The BFS-tree parent of each node: whoever first enqueued it.
  let parents = (:)
  // Parallel to the frame sequence: index 0 is the initial queue, index i the
  // queue after visiting order[i-1] — the frontier heading into the next
  // dequeue.
  let aux-states = ((start,),)
  let seen = (start,)
  let queue = (start,)
  while queue.len() > 0 {
    let u = queue.first()
    queue = queue.slice(1)
    order.push(u)
    if u == target {
      aux-states.push(queue)
      break
    }
    let frontier = neighbors(g, u)
    if sort-frontier { frontier = frontier.sorted(key: nb => nb.id) }
    for nb in frontier {
      if not seen.contains(nb.id) {
        seen.push(nb.id)
        parents.insert(nb.id, u)
        queue.push(nb.id)
      }
    }
    aux-states.push(queue)
  }
  _render-traversal(
    g,
    pg,
    order,
    "breadth-first",
    aux-states,
    "queue",
    target: target,
    tree-edges: if spanning-tree { _tree-edges(g, order, parents) } else { none },
    node-style: node-style,
    theme: theme,
  )
}

/// Animate a depth-first traversal from `start` (iterative, pre-order).
///
/// A `target:` turns it into a search that stops the moment that node is
/// visited. `spanning-tree: true` renders the DFS tree instead of the palette
/// walk, closing on the tree alone.
///
/// -> array
#let dfs-display(
  g,
  /// Where the traversal begins.
  /// -> str
  start,
  /// Stop as soon as this node is visited; `none` covers the whole reachable
  /// component.
  /// -> none | str
  target: none,
  /// Explore each node's unseen neighbours in ascending id order rather than
  /// edge-declaration order, for a deterministic visit sequence.
  /// -> bool
  sort-frontier: false,
  /// Render the DFS spanning tree instead of the palette traversal.
  /// -> bool
  spanning-tree: false,
  positions: auto,
  scale: 1,
  node-style: (:),
  layout: none,
  layout-unit: 36pt,
  theme: (:),
) = {
  _assert-traversal("graph.dfs-display", g, start, target, spanning-tree)
  let pg = _pg(g, positions, scale, layout, layout-unit)
  let order = ()
  // The DFS-tree parent of each node: whoever's push got it popped. The stack
  // holds (id, parent) pairs, so this stays faithful even when several
  // parents push a node before it is popped.
  let parents = (:)
  // Parallel to the frame sequence, and faithful to the iterative algorithm:
  // a node can sit in the stack more than once and be popped-and-skipped
  // later, so duplicates are kept.
  let aux-states = ((start,),)
  let seen = ()
  let stack = ((id: start, parent: none),)
  while stack.len() > 0 {
    let top = stack.last()
    let u = top.id
    stack = stack.slice(0, stack.len() - 1)
    if not seen.contains(u) {
      seen.push(u)
      order.push(u)
      if top.parent != none { parents.insert(u, top.parent) }
      if u == target {
        aux-states.push(stack.map(e => e.id))
        break
      }
      // Push unseen neighbours reversed, so the first is explored first.
      let nbs = neighbors(g, u).map(nb => nb.id).filter(id => not seen.contains(id))
      if sort-frontier { nbs = nbs.sorted() }
      for id in nbs.rev() { stack.push((id: id, parent: u)) }
      aux-states.push(stack.map(e => e.id))
    }
  }
  _render-traversal(
    g,
    pg,
    order,
    "depth-first",
    aux-states,
    "stack",
    target: target,
    tree-edges: if spanning-tree { _tree-edges(g, order, parents) } else { none },
    node-style: node-style,
    theme: theme,
  )
}
