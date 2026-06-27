#import "@preview/typsy:0.2.2": Any, Bool, Array, Dictionary, class
#import "./anim-core.typ" as core
#import "./graph-draw.typ" as graph-draw
#import "./graph-layout.typ" as graph-layout
#import "./op-theme.typ": _resolve-op-theme-arg

// The Graph class — an undirected-or-directed weighted graph for
// teaching MST (Prim / Kruskal), Dijkstra's shortest paths, and BFS /
// DFS traversals. Like the tree classes, the algorithm `*-display`
// methods return `Array(Frame)` (one Frame per animation step) and read
// operation strokes / fills / palettes from the shared `op-theme`
// (`src/op-theme.typ`) and structural defaults from `render-theme`
// (`src/anim-core.typ`). Graphs have no intrinsic per-DS theme.
//
// Layout is decoupled: the class stores optional manual `positions`
// (id -> (x, y) in cetz units) and the renderer (`graph-draw.typ`) just
// consumes them. `auto-layout` (optional, `graph-layout.typ`) can
// produce a positions map via graphviz; nothing here depends on it.
//
// Node ids are strings; edges are keyed by `graph-draw.edge-key`. See
// `graph-draw.typ` for the identity model and the positioned-graph
// shape the display methods feed to the renderer.

// Resolve a `render-theme:` argument that may be `auto` (read state) or
// a partial dict (merge into default). Mirrors the helper in `bst.typ`.
#let _resolve-render-theme-arg(theme) = if theme == auto {
  auto
} else { core._merge-render-theme(theme) }

// Pick a readable text fill for a colored node background by inspecting
// the oklab L component (mirrors the BST traversal helper) so the id
// inside a gradient- or component-colored node stays legible.
#let _text-fill-for(bg) = {
  let l = bg.oklab().components().first()
  if l < 60% { white } else { black }
}

// Resolve the node positions a display will draw with. With
// `layout: none` the caller's manual `positions` (or, via `auto`, the
// graph's own) are used unchanged and `diagraph-layout` is never
// touched. With `layout: <engine>` (e.g. "neato") the display lays the
// graph out itself through `auto-layout`, passing `sizes: auto` so
// graphviz reserves room per node from a cheap label-length estimate
// (graph-layout.typ). Gating the call behind opt-in is what keeps
// `diagraph-layout` an OPTIONAL dependency — importing starling and
// using manual positions pulls none of the WASM layout package; only a
// non-`none` `layout:` does. Tradeoff: the layout estimate is eager
// (no `measure`, so it can run here outside a context) while the drawn
// node size is measured precisely in `draw-graph`. The two only
// approximate each other, but graphviz's node margins absorb the slack;
// tune absolute spacing with `layout-unit:`/`scale:` if needed.
#let _resolve-positions(self, positions, layout, layout-unit) = {
  if layout == none {
    positions
  } else {
    graph-layout.auto-layout(self, engine: layout, unit: layout-unit, sizes: auto)
  }
}

// Union-find root of `x` given a `parent` map. No path compression —
// teaching graphs are small, and keeping it a pure function of its
// arguments lets it run against a per-frame snapshot of the map.
#let _uf-find(parent, x) = {
  let r = x
  while parent.at(r) != r { r = parent.at(r) }
  r
}

// Shared per-visit traversal animation for BFS / DFS. `order` is the
// precomputed visit order (array of node ids); `name` appears in the
// initial alt text. One frame per visit: the visited node gets a
// gradient fill sampled from the active op-theme's `traversal-palette`
// and a badge note showing its 1-indexed position; the caption
// accumulates the visit sequence. Mirrors `_render-traversal` in
// `bst.typ`.
//
// When `target` is non-`none` the animation is a *search*: the caller
// has truncated `order` at the target (or run it to completion if the
// target was unreachable), and a final terminal frame states the
// outcome. On success the target node gains a `settled-stroke` ring.
//
// step.kind values: "init" (initial frame), "visit" (per node, with
// node id and 1-indexed position), and — in search mode — a terminal
// "found" (node, visits) or "not-found" (target, visits).
#let _render-graph-traversal(self, pg, order, name, theme, render-theme, target: none, node-style: (:)) = {
  let n = order.len()
  let searching = target != none
  let found = searching and order.contains(target)
  let captions = (none,)
  let steps-meta = ((kind: "init"),)
  let start = if n > 0 { order.first() } else { "" }
  let intro = if searching {
    "About to search " + name + " from " + start + " for " + target + "."
  } else {
    "About to traverse " + name + " from " + start + "."
  }
  let alts = ("Graph: " + (self.describe)() + ". " + intro,)
  let output = ()
  for (i, id) in order.enumerate() {
    output.push(id)
    captions.push([Visited: #raw("[" + output.join(", ") + "]")])
    steps-meta.push((kind: "visit", node: id, index: i + 1))
    let suffix = if searching and id == target { " — this is the target." } else { "." }
    alts.push(
      "Visited "
        + id
        + " (visit "
        + str(i + 1)
        + " of "
        + str(n)
        + ")"
        + suffix,
    )
  }
  if searching {
    if found {
      captions.push([Found #target])
      steps-meta.push((kind: "found", node: target, visits: n))
      alts.push(
        "Found " + target + " after visiting " + str(n) + " node(s); the search stops here.",
      )
    } else {
      captions.push([#target not found])
      steps-meta.push((kind: "not-found", target: target, visits: n))
      alts.push(
        "Visited all " + str(n) + " reachable node(s); " + target + " was not found.",
      )
    }
  }
  let build-snapshots = (op, _rt) => {
    let g = gradient.linear(..op.traversal-palette)
    let r = graph-draw.make-graph-renderer(pg, sticky: true)
    for (i, id) in order.enumerate() {
      let t = if n <= 1 { 0% } else { (i / (n - 1)) * 100% }
      let fill = g.sample(t)
      r = (r.push-with-node)(
        id,
        fill: fill,
        text-fill: _text-fill-for(fill),
        note: str(i + 1),
      )
    }
    if searching {
      r = (r.push-frame)()
      if found {
        r = (r.patch)(f => (f.style-node)(target, stroke: op.settled-stroke))
      }
    }
    r.snapshots
  }
  core._make-frames(
    pg,
    graph-draw._draw-graph-backend,
    build-snapshots,
    captions,
    steps-meta,
    alts,
    theme,
    render-theme,
    default-node-style: node-style,
  )
}

// ===================================================================
// Tabular (non-cetz) representations
// ===================================================================
//
// The adjacency matrix / list are plain Typst tables — no cetz, no
// Frame machinery — so the Graph methods below return directly-placeable
// content rather than an `Array(Frame)`. They still honor the render
// theme: when `render-theme` is `auto` the method wraps the table build
// in a `context` block that reads the active theme state (so a
// doc-wide `set-render-theme` propagates); an explicit dict skips state.

// Run `build(render-theme)` with a resolved render-theme dict, deferring
// to theme state (inside `context`) only when the argument is `auto`.
// Returns placeable content either way.
#let _with-render-theme(arg, build) = if arg == auto {
  context { build(core._render-theme-state.get()) }
} else {
  build(core._merge-render-theme(arg))
}

// A muted version of a theme color, for de-emphasizing absent matrix
// cells (the 0 / none-marker entries) and empty adjacency rows so the
// populated entries read first.
#let _muted(c) = c.transparentize(55%)

// Render an adjacency matrix as a styled Typst table. `headers` is the
// array of per-node header labels (row i and column i share one);
// `cells` is the n×n grid of `(present: bool, value: <content>)` entries
// already resolved by the caller (1/0 presence, or weight/label).
// Header cells take the render theme's node fill + bold node-text-fill;
// absent cells are muted. The empty top-left corner squares the grid.
#let _adjacency-matrix-content(headers, cells, rt) = {
  let n = headers.len()
  let hdr = c => text(weight: "bold", fill: rt.node-text-fill, c)
  let head = (table.cell(fill: rt.node-fill)[],)
  for h in headers { head.push(table.cell(fill: rt.node-fill, hdr(h))) }
  let body = ()
  for (i, row) in cells.enumerate() {
    body.push(table.cell(fill: rt.node-fill, hdr(headers.at(i))))
    for cell in row {
      let col = if cell.present { rt.node-text-fill } else { _muted(rt.node-text-fill) }
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

// Render an adjacency list as a two-column styled table. Each `rows`
// entry is `(header: <label>, items: (array of <content>))`; an empty
// `items` shows `empty-marker` muted. The left column is node-styled
// like the matrix headers; the right column is the comma-joined list.
#let _adjacency-list-content(rows, empty-marker, rt) = {
  let hdr = c => text(weight: "bold", fill: rt.node-text-fill, c)
  let body = ()
  for r in rows {
    body.push(table.cell(fill: rt.node-fill, hdr(r.header)))
    let listing = if r.items.len() == 0 {
      text(fill: _muted(rt.node-text-fill), empty-marker)
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

#let Graph = class(
  name: "Graph",
  fields: (
    // id -> (label: Any). `label` of `auto` renders as the id.
    nodes: Dictionary(..Any),
    // array of (u: str, v: str, weight: Any, label: Any).
    edges: Array(..Any),
    directed: Bool,
    // id -> (x, y) in cetz units. May omit nodes (auto-layout fills in).
    positions: Dictionary(..Any),
  ),
  methods: (
    // Canonical edge key for this graph's directedness.
    ek: (self, u, v) => graph-draw.edge-key(u, v, directed: self.directed),
    contains-node: (self, id) => id in self.nodes,
    contains-edge: (self, u, v) => {
      let k = (self.ek)(u, v)
      self.edges.any(e => graph-draw.edge-key(
        e.u,
        e.v,
        directed: self.directed,
      ) == k)
    },
    add-node: (self, id, label: auto, pos: none) => {
      let cls = self.meta.cls
      let nodes = self.nodes
      nodes.insert(id, (label: label))
      let positions = self.positions
      if pos != none { positions.insert(id, pos) }
      (cls.new)(
        nodes: nodes,
        edges: self.edges,
        directed: self.directed,
        positions: positions,
      )
    },
    add-edge: (self, u, v, weight: 1, label: auto) => {
      let cls = self.meta.cls
      assert(
        u in self.nodes and v in self.nodes,
        message: "add-edge: both endpoints must exist (" + u + ", " + v + ").",
      )
      (cls.new)(
        nodes: self.nodes,
        edges: self.edges + ((u: u, v: v, weight: weight, label: label),),
        directed: self.directed,
        positions: self.positions,
      )
    },
    with-position: (self, id, pos) => {
      let cls = self.meta.cls
      let positions = self.positions
      positions.insert(id, pos)
      (cls.new)(
        nodes: self.nodes,
        edges: self.edges,
        directed: self.directed,
        positions: positions,
      )
    },
    // Out-neighbours of `id` as an array of (id:, weight:). For an
    // undirected graph every incident edge contributes its other
    // endpoint; for a directed graph only edges leaving `id` do.
    neighbors: (self, id) => {
      let out = ()
      for e in self.edges {
        if e.u == id {
          out.push((id: e.v, weight: e.weight))
        } else if not self.directed and e.v == id {
          out.push((id: e.u, weight: e.weight))
        }
      }
      out
    },
    // The weight of the edge between u and v (panics if absent).
    weight: (self, u, v) => {
      let k = (self.ek)(u, v)
      for e in self.edges {
        if graph-draw.edge-key(e.u, e.v, directed: self.directed) == k {
          return e.weight
        }
      }
      panic("weight: no edge between " + u + " and " + v + ".")
    },
    describe: (self) => {
      let ids = self.nodes.keys()
      let kind = if self.directed { "directed" } else { "undirected" }
      let edge-strs = self.edges.map(e => {
        let conn = if self.directed { " -> " } else { " - " }
        e.u + conn + e.v + " (w=" + str(e.weight) + ")"
      })
      (
        kind
          + " graph with "
          + str(ids.len())
          + " nodes ("
          + ids.join(", ")
          + ") and "
          + str(self.edges.len())
          + " edges: "
          + edge-strs.join("; ")
      )
    },
    // Structural invariants: edge endpoints exist; no duplicate edges
    // (by canonical key). Returns true or panics with the first
    // violation. Positions are validated lazily in `positioned`.
    check-invariants: (self) => {
      let seen = ()
      for e in self.edges {
        assert(
          e.u in self.nodes and e.v in self.nodes,
          message: "check-invariants: edge endpoint missing ("
            + e.u
            + ", "
            + e.v
            + ").",
        )
        let k = graph-draw.edge-key(e.u, e.v, directed: self.directed)
        assert(
          not seen.contains(k),
          message: "check-invariants: duplicate edge " + k + ".",
        )
        seen.push(k)
      }
      true
    },
    // Build the positioned-graph dict the renderer consumes. Uses the
    // stored positions unless an explicit map is passed. Panics if any
    // node lacks a position. `scale` multiplies every coordinate (about
    // the origin), spreading nodes apart while their drawn size stays
    // fixed — the manual-layout analog of `auto-layout`'s `unit:`.
    positioned: (self, positions: auto, scale: 1) => {
      let pos-map = if positions == auto { self.positions } else { positions }
      let nodes = (:)
      for (id, data) in self.nodes {
        assert(
          id in pos-map,
          message: "positioned: node '"
            + id
            + "' has no position; pass manual positions or use auto-layout.",
        )
        let p = pos-map.at(id)
        let pos = (p.at(0) * scale, p.at(1) * scale)
        nodes.insert(id, (label: data.at("label", default: auto), pos: pos))
      }
      let edges = self.edges.map(e => (
        key: graph-draw.edge-key(e.u, e.v, directed: self.directed),
        u: e.u,
        v: e.v,
        weight: e.at("weight", default: none),
        label: e.at("label", default: auto),
      ))
      (directed: self.directed, nodes: nodes, edges: edges)
    },
    // Returns a one-element Frame array — the static graph, no styling.
    display: (self, positions: auto, scale: 1, node-style: (:), layout: none, layout-unit: 36pt, theme: auto, render-theme: auto) => {
      let positions = _resolve-positions(self, positions, layout, layout-unit)
      let pg = (self.positioned)(positions: positions, scale: scale)
      let captions = (none,)
      let steps-meta = (none,)
      let alts = ("Graph: " + (self.describe)() + ".",)
      let build-snapshots = (_op, _rt) => (core.blank-snapshot(),)
      core._make-frames(
        pg,
        graph-draw._draw-graph-backend,
        build-snapshots,
        captions,
        steps-meta,
        alts,
        _resolve-op-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
        default-node-style: node-style,
      )
    },
    // ---- Adjacency matrix (static, non-cetz) ----
    // A Typst table indexed by node. Cells default to 1/0 presence;
    // `weights: true` shows each edge's display label (its label if set,
    // else its weight) and `none-marker` for non-edges. Undirected
    // graphs give a symmetric matrix; directed graphs read row = source,
    // column = target (a self-loop lands on the diagonal). Returns
    // placeable content (not a Frame) — wrap it in a figure yourself for
    // a caption or alt text. Honors the render theme (node fill/stroke/
    // text-fill); `render-theme: auto` reads theme state, a dict bakes
    // it in.
    adjacency-matrix: (self, weights: false, none-marker: "·", render-theme: auto) => {
      let ids = self.nodes.keys()
      let emap = (:)
      for e in self.edges {
        emap.insert(graph-draw.edge-key(e.u, e.v, directed: self.directed), e)
      }
      let label-of(id) = {
        let l = self.nodes.at(id).at("label", default: auto)
        if l == auto { id } else { l }
      }
      let headers = ids.map(label-of)
      let cells = ids.map(u => ids.map(v => {
        let k = graph-draw.edge-key(u, v, directed: self.directed)
        if k in emap {
          if weights {
            let e = emap.at(k)
            let lbl = e.at("label", default: auto)
            let val = if lbl == auto { str(e.at("weight", default: 1)) } else { lbl }
            (present: true, value: val)
          } else {
            (present: true, value: "1")
          }
        } else {
          (present: false, value: if weights { none-marker } else { "0" })
        }
      }))
      _with-render-theme(render-theme, rt => _adjacency-matrix-content(headers, cells, rt))
    },
    // ---- Adjacency list (static, non-cetz) ----
    // A two-column Typst table pairing each node with its adjacency. A
    // directed graph lists out-neighbors (successors); an undirected
    // graph lists every incident neighbor (a self-loop appears once).
    // `weights: false` (default) lists bare neighbor labels; `weights:
    // true` appends each edge's display label in parentheses. Isolated
    // nodes show `empty-marker`. Returns placeable content (not a Frame);
    // honors the render theme like `adjacency-matrix`.
    adjacency-list: (self, weights: false, empty-marker: "—", render-theme: auto) => {
      let label-of(id) = {
        let l = self.nodes.at(id).at("label", default: auto)
        if l == auto { id } else { l }
      }
      let rows = self.nodes.keys().map(u => {
        let items = ()
        for e in self.edges {
          let other = if e.u == u {
            e.v
          } else if (not self.directed) and e.v == u {
            e.u
          } else {
            none
          }
          if other != none {
            if weights {
              let lbl = e.at("label", default: auto)
              let val = if lbl == auto { str(e.at("weight", default: 1)) } else { lbl }
              items.push([#label-of(other) (#val)])
            } else {
              items.push(label-of(other))
            }
          }
        }
        (header: label-of(u), items: items)
      })
      _with-render-theme(render-theme, rt => _adjacency-list-content(rows, empty-marker, rt))
    },
    // ---- Prim's minimum spanning tree ----
    // Grows the tree from `start`, repeatedly adding the lightest edge
    // crossing the cut. Two frames per selection: "consider" (frontier
    // edges in search-stroke, the chosen min in attention-stroke) and
    // "commit" (chosen edge success-stroke, new node settled + filled).
    // Visited nodes / tree edges accumulate; the closure recomputes the
    // full styling per frame (sticky: false) so transient frontier
    // highlights clear cleanly.
    mst-prim-display: (self, start, positions: auto, scale: 1, node-style: (:), layout: none, layout-unit: 36pt, theme: auto, render-theme: auto) => {
      let positions = _resolve-positions(self, positions, layout, layout-unit)
      let pg = (self.positioned)(positions: positions, scale: scale)
      let all-ids = self.nodes.keys()
      assert(
        start in self.nodes,
        message: "mst-prim-display: start node '" + start + "' not in graph.",
      )
      let visited = (start,)
      let tree-keys = ()
      let total = 0
      let moments = (
        (kind: "init", visited: visited, tree-keys: (), frontier: (), chosen: none, total: 0),
      )
      let stop = false
      while visited.len() < all-ids.len() and not stop {
        let crossing = self.edges.filter(e => (
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
          let frontier = crossing.map(e => graph-draw.edge-key(
            e.u,
            e.v,
            directed: self.directed,
          ))
          moments.push((
            kind: "consider",
            visited: visited,
            tree-keys: tree-keys,
            frontier: frontier,
            chosen: chosen,
            total: total,
          ))
          let new-node = if visited.contains(chosen.u) { chosen.v } else { chosen.u }
          visited = visited + (new-node,)
          tree-keys = tree-keys + (graph-draw.edge-key(
            chosen.u,
            chosen.v,
            directed: self.directed,
          ),)
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
      moments.push((
        kind: "done",
        visited: visited,
        tree-keys: tree-keys,
        frontier: (),
        chosen: none,
        total: total,
      ))

      let pfx = "Minimum spanning tree (Prim) on " + (self.describe)() + ". "
      let captions = ()
      let steps-meta = ()
      let alts = ()
      for m in moments {
        if m.kind == "init" {
          captions.push([Start at #start])
          steps-meta.push((kind: "init", start: start))
          alts.push(pfx + "Starting Prim's algorithm at node " + start + ".")
        } else if m.kind == "consider" {
          let c = m.chosen
          captions.push([Min crossing edge: #(c.u)–#(c.v) (#(c.weight))])
          steps-meta.push((kind: "consider", edge: (c.u, c.v), weight: c.weight))
          alts.push(
            "Examining the frontier; the lightest crossing edge is "
              + c.u + "–" + c.v + " with weight " + str(c.weight) + ".",
          )
        } else if m.kind == "commit" {
          let c = m.chosen
          captions.push([Add #(c.u)–#(c.v); tree weight #(m.total)])
          steps-meta.push((kind: "commit", edge: (c.u, c.v), node: m.new-node, total: m.total))
          alts.push(
            "Adding edge " + c.u + "–" + c.v + " and node " + m.new-node
              + "; tree weight is now " + str(m.total) + ".",
          )
        } else {
          captions.push([MST weight #(m.total)])
          steps-meta.push((kind: "done", total: m.total))
          alts.push("Minimum spanning tree complete; total weight " + str(m.total) + ".")
        }
      }

      let build-snapshots = (op, _rt) => {
        let r = graph-draw.make-graph-renderer(pg, sticky: false)
        for (i, m) in moments.enumerate() {
          if i > 0 { r = (r.push-frame)() }
          for id in m.visited {
            r = (r.patch)(f => (f.style-node)(id, stroke: op.settled-stroke, fill: op.success-fill))
          }
          for k in m.tree-keys {
            r = (r.patch)(f => (f.style-edge)(k, stroke: op.success-stroke))
          }
          if m.kind == "consider" {
            for k in m.frontier {
              r = (r.patch)(f => (f.style-edge)(k, stroke: op.search-stroke))
            }
            r = (r.patch)(f => (f.style-edge)(
              graph-draw.edge-key(m.chosen.u, m.chosen.v, directed: self.directed),
              stroke: op.attention-stroke,
            ))
          }
        }
        r.snapshots
      }

      core._make-frames(
        pg,
        graph-draw._draw-graph-backend,
        build-snapshots,
        captions,
        steps-meta,
        alts,
        _resolve-op-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
        default-node-style: node-style,
      )
    },
    // ---- Kruskal's minimum spanning tree ----
    // Considers edges in weight order, adding an edge unless it would
    // join two nodes already in the same component (cycle). Components
    // (the union-find forest) are shown by node color: same color = same
    // set. Three frames per edge: "consider" (attention), then "add"
    // (success-stroke, components merge → recolor) or "reject"
    // (danger-stroke).
    mst-kruskal-display: (self, positions: auto, scale: 1, node-style: (:), layout: none, layout-unit: 36pt, theme: auto, render-theme: auto) => {
      let positions = _resolve-positions(self, positions, layout, layout-unit)
      let pg = (self.positioned)(positions: positions, scale: scale)
      let all-ids = self.nodes.keys()
      let n = all-ids.len()
      let id-index = (:)
      for (i, id) in all-ids.enumerate() { id-index.insert(id, i) }
      let sorted-edges = self.edges.sorted(key: e => e.weight)
      let parent = (:)
      for id in all-ids { parent.insert(id, id) }
      let tree-keys = ()
      let total = 0
      let moments = (
        (kind: "init", parent: parent, tree-keys: (), edge: none, total: 0),
      )
      for e in sorted-edges {
        let ru = _uf-find(parent, e.u)
        let rv = _uf-find(parent, e.v)
        moments.push((kind: "consider", parent: parent, tree-keys: tree-keys, edge: e, total: total))
        if ru != rv {
          parent.insert(ru, rv)
          tree-keys = tree-keys + (graph-draw.edge-key(e.u, e.v, directed: self.directed),)
          total = total + e.weight
          moments.push((kind: "add", parent: parent, tree-keys: tree-keys, edge: e, total: total))
        } else {
          moments.push((kind: "reject", parent: parent, tree-keys: tree-keys, edge: e, total: total))
        }
      }
      moments.push((kind: "done", parent: parent, tree-keys: tree-keys, edge: none, total: total))

      let pfx = "Minimum spanning tree (Kruskal) on " + (self.describe)() + ". "
      let captions = ()
      let steps-meta = ()
      let alts = ()
      for m in moments {
        if m.kind == "init" {
          captions.push([Sort edges by weight])
          steps-meta.push((kind: "init"))
          alts.push(pfx + "Consider edges in increasing weight order; each node starts in its own component.")
        } else if m.kind == "consider" {
          let e = m.edge
          captions.push([Consider #(e.u)–#(e.v) (#(e.weight))])
          steps-meta.push((kind: "consider", edge: (e.u, e.v), weight: e.weight))
          alts.push("Considering edge " + e.u + "–" + e.v + " with weight " + str(e.weight) + ".")
        } else if m.kind == "add" {
          let e = m.edge
          captions.push([Add #(e.u)–#(e.v); weight #(m.total)])
          steps-meta.push((kind: "add", edge: (e.u, e.v), total: m.total))
          alts.push(
            e.u + " and " + e.v + " are in different components; add the edge and merge them. Total weight "
              + str(m.total) + ".",
          )
        } else if m.kind == "reject" {
          let e = m.edge
          captions.push([Reject #(e.u)–#(e.v) (cycle)])
          steps-meta.push((kind: "reject", edge: (e.u, e.v)))
          alts.push(e.u + " and " + e.v + " are already connected; this edge would form a cycle, so skip it.")
        } else {
          captions.push([MST weight #(m.total)])
          steps-meta.push((kind: "done", total: m.total))
          alts.push("Minimum spanning tree complete; total weight " + str(m.total) + ".")
        }
      }

      let build-snapshots = (op, _rt) => {
        let g = gradient.linear(..op.traversal-palette)
        let color-of(root) = {
          let idx = id-index.at(root)
          let t = if n <= 1 { 0% } else { (idx / (n - 1)) * 100% }
          g.sample(t)
        }
        let r = graph-draw.make-graph-renderer(pg, sticky: false)
        for (i, m) in moments.enumerate() {
          if i > 0 { r = (r.push-frame)() }
          for id in all-ids {
            let fill = color-of(_uf-find(m.parent, id))
            r = (r.patch)(f => (f.style-node)(id, fill: fill, text-fill: _text-fill-for(fill)))
          }
          for k in m.tree-keys {
            r = (r.patch)(f => (f.style-edge)(k, stroke: op.success-stroke))
          }
          if m.kind == "consider" {
            r = (r.patch)(f => (f.style-edge)(
              graph-draw.edge-key(m.edge.u, m.edge.v, directed: self.directed),
              stroke: op.attention-stroke,
            ))
          } else if m.kind == "reject" {
            r = (r.patch)(f => (f.style-edge)(
              graph-draw.edge-key(m.edge.u, m.edge.v, directed: self.directed),
              stroke: op.danger-stroke,
            ))
          }
        }
        r.snapshots
      }

      core._make-frames(
        pg,
        graph-draw._draw-graph-backend,
        build-snapshots,
        captions,
        steps-meta,
        alts,
        _resolve-op-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
        default-node-style: node-style,
      )
    },
    // ---- Dijkstra's shortest paths ----
    // Every node carries its tentative distance in the gold note slot
    // (∞ until reached). Two frames per round: "select" (the unvisited
    // node with smallest distance gets attention-stroke and is
    // finalized), then "relax" (its outgoing edges are tried in
    // search-stroke and improved distances update). The shortest-path
    // tree (predecessor edges) accumulates in success-stroke. With a
    // `target`, the search stops early and the path is highlighted in
    // settled-stroke.
    dijkstra-display: (self, source, target: none, positions: auto, scale: 1, node-style: (:), layout: none, layout-unit: 36pt, theme: auto, render-theme: auto) => {
      let positions = _resolve-positions(self, positions, layout, layout-unit)
      let pg = (self.positioned)(positions: positions, scale: scale)
      let all-ids = self.nodes.keys()
      assert(
        source in self.nodes,
        message: "dijkstra-display: source node '" + source + "' not in graph.",
      )
      let dlabel(d) = if d == none { "∞" } else { str(d) }
      let tree-keys-of(prev) = prev.pairs().map(((v, u)) => graph-draw.edge-key(u, v, directed: self.directed))
      let dist = (:)
      for id in all-ids { dist.insert(id, none) }
      dist.insert(source, 0)
      let prev = (:)
      let visited = ()
      let moments = (
        (kind: "init", dist: dist, visited: (), u: none, relaxed: (), tree-keys: ()),
      )
      let stop = false
      while not stop {
        let cand = all-ids.filter(id => not visited.contains(id) and dist.at(id) != none)
        if cand.len() == 0 {
          stop = true
        } else {
          let u = cand.fold(cand.first(), (m, id) => if dist.at(id) < dist.at(m) { id } else { m })
          visited = visited + (u,)
          moments.push((kind: "select", dist: dist, visited: visited, u: u, relaxed: (), tree-keys: tree-keys-of(prev)))
          let relaxed = ()
          for nb in (self.neighbors)(u) {
            let v = nb.id
            if not visited.contains(v) {
              let nd = dist.at(u) + nb.weight
              if dist.at(v) == none or nd < dist.at(v) {
                dist.insert(v, nd)
                prev.insert(v, u)
                relaxed.push(graph-draw.edge-key(u, v, directed: self.directed))
              }
            }
          }
          moments.push((kind: "relax", dist: dist, visited: visited, u: u, relaxed: relaxed, tree-keys: tree-keys-of(prev)))
          if target != none and u == target { stop = true }
        }
      }
      let path-keys = ()
      let path-nodes = ()
      if target != none and dist.at(target) != none {
        let cur = target
        path-nodes = (cur,)
        while cur != source and (cur in prev) {
          let p = prev.at(cur)
          path-keys.push(graph-draw.edge-key(p, cur, directed: self.directed))
          path-nodes.push(p)
          cur = p
        }
      }
      moments.push((
        kind: "done",
        dist: dist,
        visited: visited,
        u: none,
        relaxed: (),
        tree-keys: tree-keys-of(prev),
        path-keys: path-keys,
        path-nodes: path-nodes,
      ))

      let pfx = "Shortest paths (Dijkstra) on " + (self.describe)() + ". "
      let captions = ()
      let steps-meta = ()
      let alts = ()
      for m in moments {
        if m.kind == "init" {
          captions.push([Initialize: #source = 0])
          steps-meta.push((kind: "init", source: source))
          alts.push(pfx + "Initialize tentative distances: " + source + " = 0, all others infinity.")
        } else if m.kind == "select" {
          captions.push([Visit #(m.u) (#(dlabel(m.dist.at(m.u))))])
          steps-meta.push((kind: "select", node: m.u, dist: m.dist.at(m.u)))
          alts.push(
            "Selecting " + m.u + ", the unvisited node with the smallest tentative distance ("
              + dlabel(m.dist.at(m.u)) + "); finalizing it.",
          )
        } else if m.kind == "relax" {
          captions.push([Relax from #(m.u)])
          steps-meta.push((kind: "relax", node: m.u, relaxed: m.relaxed))
          alts.push("Relaxing edges out of " + m.u + "; " + str(m.relaxed.len()) + " distance(s) improved.")
        } else {
          if target != none {
            captions.push([Shortest path to #target: #(dlabel(m.dist.at(target)))])
            steps-meta.push((kind: "done", target: target, dist: m.dist.at(target)))
            alts.push(
              "Dijkstra complete; shortest distance from " + source + " to " + target + " is "
                + dlabel(m.dist.at(target)) + ".",
            )
          } else {
            captions.push([Done])
            steps-meta.push((kind: "done"))
            alts.push("Dijkstra complete; all reachable nodes finalized.")
          }
        }
      }

      let build-snapshots = (op, _rt) => {
        let r = graph-draw.make-graph-renderer(pg, sticky: false)
        for (i, m) in moments.enumerate() {
          if i > 0 { r = (r.push-frame)() }
          for id in all-ids {
            r = (r.patch)(f => (f.style-node)(id, note: dlabel(m.dist.at(id))))
          }
          for id in m.visited {
            r = (r.patch)(f => (f.style-node)(id, stroke: op.settled-stroke, fill: op.success-fill))
          }
          for k in m.tree-keys {
            r = (r.patch)(f => (f.style-edge)(k, stroke: op.success-stroke))
          }
          if m.u != none {
            r = (r.patch)(f => (f.style-node)(m.u, stroke: op.attention-stroke))
          }
          if m.kind == "relax" {
            for k in m.relaxed {
              r = (r.patch)(f => (f.style-edge)(k, stroke: op.search-stroke))
            }
          }
          if m.kind == "done" {
            for k in m.at("path-keys", default: ()) {
              r = (r.patch)(f => (f.style-edge)(k, stroke: op.settled-stroke))
            }
            for id in m.at("path-nodes", default: ()) {
              r = (r.patch)(f => (f.style-node)(id, stroke: op.settled-stroke, fill: op.success-fill))
            }
          }
        }
        r.snapshots
      }

      core._make-frames(
        pg,
        graph-draw._draw-graph-backend,
        build-snapshots,
        captions,
        steps-meta,
        alts,
        _resolve-op-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
        default-node-style: node-style,
      )
    },
    // ---- Breadth-first traversal / search ----
    // With `target: none` this is a full traversal of the reachable
    // component. Pass a `target` node id to turn it into a search that
    // stops the moment the target is dequeued (or runs to completion if
    // the target is unreachable); `_render-graph-traversal` then appends
    // a terminal "found" / "not-found" frame.
    bfs-display: (self, start, target: none, positions: auto, scale: 1, node-style: (:), layout: none, layout-unit: 36pt, theme: auto, render-theme: auto) => {
      let positions = _resolve-positions(self, positions, layout, layout-unit)
      let pg = (self.positioned)(positions: positions, scale: scale)
      assert(start in self.nodes, message: "bfs-display: start node '" + start + "' not in graph.")
      assert(
        target == none or target in self.nodes,
        message: "bfs-display: target node " + repr(target) + " not in graph.",
      )
      let order = ()
      let seen = (start,)
      let queue = (start,)
      while queue.len() > 0 {
        let u = queue.first()
        queue = queue.slice(1)
        order.push(u)
        if u == target { break }
        for nb in (self.neighbors)(u) {
          if not seen.contains(nb.id) {
            seen.push(nb.id)
            queue.push(nb.id)
          }
        }
      }
      _render-graph-traversal(
        self,
        pg,
        order,
        "breadth-first",
        _resolve-op-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
        target: target,
        node-style: node-style,
      )
    },
    // ---- Depth-first traversal / search (iterative pre-order) ----
    // As with `bfs-display`, a non-`none` `target` turns the traversal
    // into a search that stops the moment the target is visited.
    dfs-display: (self, start, target: none, positions: auto, scale: 1, node-style: (:), layout: none, layout-unit: 36pt, theme: auto, render-theme: auto) => {
      let positions = _resolve-positions(self, positions, layout, layout-unit)
      let pg = (self.positioned)(positions: positions, scale: scale)
      assert(start in self.nodes, message: "dfs-display: start node '" + start + "' not in graph.")
      assert(
        target == none or target in self.nodes,
        message: "dfs-display: target node " + repr(target) + " not in graph.",
      )
      let order = ()
      let seen = ()
      let stack = (start,)
      while stack.len() > 0 {
        let u = stack.last()
        stack = stack.slice(0, stack.len() - 1)
        if not seen.contains(u) {
          seen.push(u)
          order.push(u)
          if u == target { break }
          // Push unseen neighbours reversed so the first neighbour is
          // explored first (pre-order).
          let nbs = (self.neighbors)(u).map(nb => nb.id).filter(id => not seen.contains(id))
          for id in nbs.rev() { stack.push(id) }
        }
      }
      _render-graph-traversal(
        self,
        pg,
        order,
        "depth-first",
        _resolve-op-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
        target: target,
        node-style: node-style,
      )
    },
  ),
)

/// Factory: build a #raw("Graph") from a positional list of nodes plus
/// a named list of edges. Each node is one of:
///
/// - a bare id string (no position — supply positions later, e.g. via
///   #raw("auto-layout") in #raw("graph-layout.typ"), or pass
///   #raw("positions:") to a #raw("*-display") method),
/// - an #raw("(id, x, y)") tuple (label defaults to the id), or
/// - an #raw("(id, x, y, label)") tuple.
///
/// Each edge is an #raw("(u, v)") tuple (weight defaults to #raw("1"))
/// or #raw("(u, v, weight)"). Positions are in cetz units.
///
/// ```typc
/// // hand-placed
/// let g = graph(
///   (("A", 0, 0), ("B", 3, 1), ("C", 1.5, 2.4)),
///   edges: (("A", "B", 7), ("B", "C", 2), ("A", "C", 4)),
/// )
/// // position-less (lay out later)
/// let h = graph(("A", "B", "C"), edges: (("A", "B", 7),))
/// ```
///
/// -> Graph
#let graph(
  /// Positional array of nodes. Each is a bare id, an
  /// #raw("(id, label)") 2-tuple (a custom display label, no manual
  /// position — handy with #raw("auto-layout")), an #raw("(id, x, y)")
  /// tuple (manual position, label defaults to the id), or an
  /// #raw("(id, x, y, label)") tuple (both).
  /// -> array
  nodes,
  /// Edges — each an #raw("(u, v)") pair optionally followed by a
  /// weight and/or label. The third slot dispatches by type: a number
  /// is the edge #raw("weight"), a string/content is a display
  /// #raw("label") drawn in place of the weight. An
  /// #raw("(u, v, weight, label)") 4-tuple sets both — the numeric
  /// weight still drives Dijkstra/MST while the label is what's shown.
  /// -> array
  edges: (),
  /// Whether the graph is directed (arrowheads + ordered edge keys).
  /// -> bool
  directed: false,
) = {
  let g = (Graph.new)(nodes: (:), edges: (), directed: directed, positions: (:))
  for nd in nodes {
    if type(nd) == str {
      g = (g.add-node)(nd)
    } else {
      assert(
        type(nd) == array and nd.len() >= 2 and nd.len() <= 4,
        message: "graph: node must be an id, (id, label), (id, x, y), "
          + "or (id, x, y, label); got "
          + repr(nd),
      )
      let id = nd.at(0)
      if nd.len() == 2 {
        // (id, label) — custom label, no manual position.
        g = (g.add-node)(id, label: nd.at(1))
      } else {
        // (id, x, y) or (id, x, y, label).
        let pos = (nd.at(1), nd.at(2))
        let label = if nd.len() > 3 { nd.at(3) } else { auto }
        g = (g.add-node)(id, label: label, pos: pos)
      }
    }
  }
  for e in edges {
    assert(
      type(e) == array and e.len() >= 2,
      message: "graph: edge needs at least (u, v); got " + repr(e),
    )
    let weight = 1
    let label = auto
    if e.len() == 3 {
      // Third slot dispatches by type: a number is the weight,
      // anything else (str/content) is a display label.
      let third = e.at(2)
      if type(third) == int or type(third) == float {
        weight = third
      } else {
        label = third
      }
    } else if e.len() >= 4 {
      weight = e.at(2)
      label = e.at(3)
    }
    g = (g.add-edge)(e.at(0), e.at(1), weight: weight, label: label)
  }
  g
}
