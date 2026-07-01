#import "@preview/typsy:0.2.2": Any, Bool, Array, Dictionary, class
#import "./anim-core.typ" as core
#import "./graph-draw.typ" as graph-draw
#import "./graph-layout.typ" as graph-layout
#import "./op-theme.typ": _resolve-op-theme-arg, _op-theme-state, _merge-op-theme

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
#let _render-graph-traversal(
  self,
  pg,
  order,
  name,
  theme,
  render-theme,
  target: none,
  node-style: (:),
  // `aux` is a per-frame snapshot of the traversal's helper structure
  // (queue for BFS, stack for DFS), parallel to the frame sequence:
  // index 0 is the init frame, index i the state after visiting
  // order[i-1]. `aux-kind` is "queue" / "stack" (or none to opt out).
  // Each is threaded onto the `step` metadata for `aux-strip`.
  aux: (),
  aux-kind: none,
  // When non-`none`, render the spanning tree instead of the palette
  // traversal: parallel to `order`, entry i is the edge-key of node
  // order[i]'s discovery edge (`none` for the root). Each node then
  // joins the tree with a uniform commit style and its discovery edge
  // is highlighted, accumulating into the BFS/DFS tree.
  tree-edges: none,
) = {
  let n = order.len()
  let searching = target != none
  let found = searching and order.contains(target)
  // Format an aux snapshot (array of ids) for the alt-text track.
  let aux-label = if aux-kind == "queue" { "Queue" } else if aux-kind == "stack" { "Stack" } else { "Structure" }
  let aux-str = a => if a.len() == 0 { "(empty)" } else { "[" + a.join(", ") + "]" }
  let aux-note = a => if aux-kind == none { "" } else { " " + aux-label + " now: " + aux-str(a) + "." }
  let captions = (none,)
  let steps-meta = ((kind: "init", aux: aux.at(0, default: ()), aux-kind: aux-kind),)
  let start = if n > 0 { order.first() } else { "" }
  let intro = if searching {
    "About to search " + name + " from " + start + " for " + target + "."
  } else {
    "About to traverse " + name + " from " + start + "."
  }
  let init-aux = if aux-kind == none { "" } else { " " + aux-label + " starts: " + aux-str(aux.at(0, default: ())) + "." }
  let alts = ("Graph: " + (self.describe)() + ". " + intro + init-aux,)
  let output = ()
  for (i, id) in order.enumerate() {
    output.push(id)
    captions.push([Visited: #raw("[" + output.join(", ") + "]")])
    let a = aux.at(i + 1, default: ())
    steps-meta.push((kind: "visit", node: id, index: i + 1, aux: a, aux-kind: aux-kind))
    let suffix = if searching and id == target { " — this is the target." } else { "." }
    alts.push(
      "Visited "
        + id
        + " (visit "
        + str(i + 1)
        + " of "
        + str(n)
        + ")"
        + suffix
        + aux-note(a),
    )
  }
  if searching {
    let a = aux.at(-1, default: ())
    if found {
      captions.push([Found #target])
      steps-meta.push((kind: "found", node: target, visits: n, aux: a, aux-kind: aux-kind))
      alts.push(
        "Found " + target + " after visiting " + str(n) + " node(s); the search stops here.",
      )
    } else {
      captions.push([#target not found])
      steps-meta.push((kind: "not-found", target: target, visits: n, aux: a, aux-kind: aux-kind))
      alts.push(
        "Visited all " + str(n) + " reachable node(s); " + target + " was not found.",
      )
    }
  }
  // Spanning-tree mode closes with a prune frame: every non-tree edge is
  // dropped so only the accumulated tree remains. (Mutually exclusive
  // with `searching` — spanning-tree asserts `target == none`.)
  if tree-edges != none {
    let n-tree = tree-edges.filter(e => e != none).len()
    captions.push([Spanning tree])
    // Carry the final (post-traversal, empty) aux state and its kind so
    // `aux-strip` can render this frame like any other in the sequence.
    steps-meta.push((
      kind: "spanning-tree",
      edges: n-tree,
      nodes: n,
      aux: aux.at(-1, default: ()),
      aux-kind: aux-kind,
    ))
    alts.push(
      "Removed the non-tree edges; the "
        + name
        + " spanning tree ("
        + str(n-tree)
        + " edge(s) over "
        + str(n)
        + " node(s)) remains.",
    )
  }
  let build-snapshots = (op, _rt) => {
    let g = gradient.linear(..op.traversal-palette)
    let r = graph-draw.make-graph-renderer(pg, sticky: true)
    for (i, id) in order.enumerate() {
      if tree-edges == none {
        // Traversal: sample the palette across the visit order.
        let t = if n <= 1 { 0% } else { (i / (n - 1)) * 100% }
        let fill = g.sample(t)
        r = (r.push-with-node)(
          id,
          fill: fill,
          text-fill: _text-fill-for(fill),
          note: str(i + 1),
        )
      } else {
        // Spanning tree: the node joins the tree with a uniform commit
        // style and its discovery edge lights up (sticky, so the tree
        // accumulates). The root's `tree-edges` entry is `none`.
        r = (r.push-with-node)(
          id,
          fill: op.success-fill,
          text-fill: _text-fill-for(op.success-fill),
          stroke: op.settled-stroke,
        )
        let ek = tree-edges.at(i)
        if ek != none {
          r = (r.patch)(f => (f.style-edge)(ek, stroke: op.success-stroke))
        }
      }
    }
    if searching {
      r = (r.push-frame)()
      if found {
        r = (r.patch)(f => (f.style-node)(target, stroke: op.settled-stroke))
      }
    }
    if tree-edges != none {
      // Prune frame: hide every edge that isn't a discovery (tree) edge.
      // The tree styling is sticky, so this frame inherits the fully
      // built tree and just removes the remaining graph edges.
      let tree-keys = tree-edges.filter(e => e != none)
      r = (r.push-frame)()
      for e in pg.edges {
        if not tree-keys.contains(e.key) {
          r = (r.patch)(f => (f.style-edge)(e.key, hide: true))
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

// Run `build(op-theme, render-theme)` with both themes resolved. Used by
// `aux-strip`, whose MST kinds (`pq` / `edge-list` / `partition`) color
// elements by operation status (attention / success / danger) and so
// need the op-theme, unlike the purely structural queue/stack kinds.
// Each `auto` argument defers to its state inside one shared `context`;
// an explicit dict bakes that theme in. (`context` is harmless when
// neither argument is `auto`, so we always take that branch when either
// is — it keeps both reads in a single layout pass.)
#let _with-strip-themes(op-arg, rt-arg, build) = {
  let both = op-arg == auto or rt-arg == auto
  let resolve = () => {
    let op = if op-arg == auto { _op-theme-state.get() } else { _merge-op-theme(op-arg) }
    let rt = if rt-arg == auto { core._render-theme-state.get() } else { core._merge-render-theme(rt-arg) }
    build(op, rt)
  }
  if both { context resolve() } else { resolve() }
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

// A single strip cell: a node-styled box carrying `body`. `fill`,
// `stroke` (a ready stroke value — the caller decides thickness), and
// `text-fill` are passed in so the MST kinds can recolor cells by
// operation status while the queue/stack kinds keep render-theme styling.
// `inset` defaults to the horizontal-strip padding; the vertical
// edge-list cells tighten it.
#let _strip-box(body, fill, stroke, text-fill, inset: (x: 0.6em, y: 0.45em)) = box(
  fill: fill,
  stroke: stroke,
  inset: inset,
  radius: 2pt,
  text(fill: text-fill, body),
)

// A small muted annotation (end labels like front/rear/min, cursors,
// per-view titles).
#let _strip-end-label(rt, t) = text(size: 0.75em, fill: _muted(rt.node-text-fill), t)

// Style one MST element box by its operation `status`, pulling colors
// from the op-theme so the strip matches the canvas:
//   chosen / current -> attention-stroke ring (about to be popped/examined)
//   added            -> success fill + stroke (an accepted tree edge)
//   rejected         -> danger stroke, muted text (a cycle edge, skipped)
//   candidate / pending / other -> neutral render-theme styling
#let _status-box(body, status, op, rt, inset: (x: 0.6em, y: 0.45em)) = {
  let stroke = if status == "chosen" or status == "current" {
    op.attention-stroke
  } else if status == "added" {
    op.success-stroke
  } else if status == "rejected" {
    op.danger-stroke
  } else {
    0.5pt + rt.node-stroke
  }
  let fill = if status == "added" { op.success-fill } else { rt.node-fill }
  let text-fill = if status == "added" {
    _text-fill-for(op.success-fill)
  } else if status == "rejected" {
    _muted(rt.node-text-fill)
  } else {
    rt.node-text-fill
  }
  _strip-box(body, fill, stroke, text-fill, inset: inset)
}

// Format an edge element `(u, v, weight)` as `u–v (w)` content, honoring
// the `labels` id -> content map for the endpoints.
#let _edge-body(item, labels) = {
  let lu = labels.at(item.u, default: item.u)
  let lv = labels.at(item.v, default: item.v)
  [#lu–#lv (#item.weight)]
}

// A tall, narrow variant of `_edge-body`: the endpoints stacked over a
// short connector with the weight beneath, so a long horizontal edge
// list stays compact.
//
//   u
//   |
//   v
//  (w)
//
// The connector inherits the surrounding text fill (set by `_status-box`)
// so a rejected edge's label greys out as one piece.
#let _edge-body-vertical(item, labels) = {
  let lu = labels.at(item.u, default: item.u)
  let lv = labels.at(item.v, default: item.v)
  align(center, stack(
    dir: ttb,
    spacing: 0.18em,
    lu,
    text(size: 0.9em, "|"),
    lv,
    text(size: 0.85em, [(#item.weight)]),
  ))
}

// Queue / stack view (BFS / DFS): a horizontal strip of node-styled
// boxes. `ids` is the element order (front-first for a queue,
// bottom-first for a stack). End annotations mark the live ends:
// front/rear for a queue, top (the push/pop end, drawn rightmost) for a
// stack.
#let _aux-nodes-content(ids, kind, labels, rt) = {
  let neutral = body => _strip-box(body, rt.node-fill, 0.5pt + rt.node-stroke, rt.node-text-fill)
  if ids.len() == 0 {
    return stack(
      dir: ttb,
      spacing: 0.3em,
      _strip-box("(empty)", rt.node-fill, 0.5pt + rt.node-stroke, _muted(rt.node-text-fill)),
      _strip-end-label(rt, if kind == "stack" { "top" } else { "front" }),
    )
  }
  let boxes = ids.map(id => neutral(labels.at(id, default: id)))
  let last = ids.len() - 1
  let labels-row = range(ids.len()).map(i => if kind == "stack" {
    // Stack top is the right end (where we push and pop).
    if i == last { _strip-end-label(rt, "top") } else { [] }
  } else if ids.len() == 1 {
    _strip-end-label(rt, "front / rear")
  } else if i == 0 {
    _strip-end-label(rt, "front")
  } else if i == last {
    _strip-end-label(rt, "rear")
  } else { [] })
  grid(
    columns: ids.len(),
    column-gutter: 0.4em,
    row-gutter: 0.3em,
    align: center,
    ..boxes,
    ..labels-row,
  )
}

// Prim priority-queue view: crossing (candidate) edges sorted ascending
// by weight, min at the front. Each `items` entry is
// `(u, v, weight, status)` with status `candidate` or `chosen` (the min
// about to be popped, drawn with an attention ring). Rendered as a
// vertical column (a priority queue's natural orientation, and it stays
// narrow when the frontier is wide) with the `min` marked at the top.
#let _aux-pq-content(items, labels, op, rt) = {
  if items.len() == 0 {
    return grid(
      columns: (auto, auto),
      column-gutter: 0.4em,
      align: (right + horizon, left + horizon),
      _strip-end-label(rt, "min"),
      _strip-box("(empty)", rt.node-fill, 0.5pt + rt.node-stroke, _muted(rt.node-text-fill)),
    )
  }
  let cells = ()
  for (i, it) in items.enumerate() {
    cells.push(if i == 0 { _strip-end-label(rt, "min") } else { [] })
    cells.push(_status-box(_edge-body(it, labels), it.status, op, rt))
  }
  grid(
    columns: (auto, auto),
    column-gutter: 0.4em,
    row-gutter: 0.35em,
    align: (right + horizon, left + horizon),
    ..cells,
  )
}

// Kruskal sorted-edge-list view: every edge in weight order, each tagged
// with a status (`pending` / `current` / `added` / `rejected`). A cursor
// (▲) sits under the current edge.
#let _aux-edge-list-content(items, labels, op, rt) = {
  if items.len() == 0 {
    return _strip-box("(no edges)", rt.node-fill, 0.5pt + rt.node-stroke, _muted(rt.node-text-fill))
  }
  // Vertical (tall, narrow) edge labels keep the strip compact even when
  // the graph has many edges.
  let boxes = items.map(it => _status-box(
    _edge-body-vertical(it, labels),
    it.status,
    op,
    rt,
    inset: (x: 0.45em, y: 0.4em),
  ))
  let cursor-row = items.map(it => if it.status == "current" {
    _strip-end-label(rt, "▲")
  } else { [] })
  grid(
    columns: items.len(),
    column-gutter: 0.4em,
    row-gutter: 0.3em,
    align: center,
    ..boxes,
    ..cursor-row,
  )
}

// Kruskal disjoint-set view: one bordered group per component, each
// holding its members as node boxes. `groups` is an array of id arrays.
#let _aux-partition-content(groups, labels, rt) = {
  if groups.len() == 0 {
    return _strip-box("(empty)", rt.node-fill, 0.5pt + rt.node-stroke, _muted(rt.node-text-fill))
  }
  let group-box = ids => box(
    stroke: 0.75pt + rt.node-stroke,
    radius: 3pt,
    inset: 0.35em,
    grid(
      columns: ids.len(),
      column-gutter: 0.3em,
      ..ids.map(id => _strip-box(
        labels.at(id, default: id),
        rt.node-fill,
        0.5pt + rt.node-stroke,
        rt.node-text-fill,
      )),
    ),
  )
  grid(
    columns: groups.len(),
    column-gutter: 0.6em,
    align: horizon,
    ..groups.map(g => group-box(g)),
  )
}

// A short heading shown above each strip when a step carries more than
// one view (Kruskal's edge-list + partition), so the two are labeled.
#let _view-title(kind) = if kind == "edge-list" {
  "Sorted edges"
} else if kind == "partition" {
  "Components"
} else if kind == "pq" {
  "Frontier"
} else if kind == "queue" {
  "Queue"
} else if kind == "stack" {
  "Stack"
} else { "" }

// Dispatch one aux view (a `(kind, items)` pair, `items` being ids /
// edge dicts / id-group arrays depending on kind) to its content builder.
#let _aux-view(kind, items, labels, op, rt) = if kind == "queue" or kind == "stack" {
  _aux-nodes-content(items, kind, labels, rt)
} else if kind == "pq" {
  _aux-pq-content(items, labels, op, rt)
} else if kind == "edge-list" {
  _aux-edge-list-content(items, labels, op, rt)
} else if kind == "partition" {
  _aux-partition-content(items, labels, rt)
} else {
  panic("aux-strip: unknown aux-kind '" + repr(kind) + "'.")
}

/// Render the auxiliary helper structure captured for one animation
/// frame as a placeable strip of boxes — a teaching aid so students can
/// track the algorithm's bookkeeping alongside the graph canvas. Pass a
/// frame's #raw("step") metadata; the strip reads whatever auxiliary
/// state that display stashed:
///
/// - #raw("bfs-display") / #raw("dfs-display") — the BFS queue / DFS
///   stack (a single #raw("aux") array + #raw("aux-kind"); the DFS stack
///   is shown faithfully, duplicates and all, since a node may be pushed
///   more than once before an earlier copy is popped).
/// - #raw("mst-prim-display") — the frontier priority queue of crossing
///   edges, min first, the chosen edge ringed.
/// - #raw("mst-kruskal-display") — two stacked views (an #raw("aux-views")
///   list): the sorted edge list with a cursor and per-edge status, plus
///   the disjoint-set partition (one group per component).
///
/// Returns plain Typst content (not a #raw("Frame")), so it drops
/// anywhere — e.g. beside #raw("canvases-only(frames)") in a touying
/// layout. When a step carries several views they stack vertically;
/// pass #raw("view:") to render just one for separate placement.
///
/// -> content
#let aux-strip(
  /// One frame's #raw("step") metadata dict, as produced by
  /// #raw("bfs-display") / #raw("dfs-display") /
  /// #raw("mst-prim-display") / #raw("mst-kruskal-display").
  /// -> dictionary
  step,
  /// Optional #raw("id -> content") map giving each node a display label
  /// (e.g. to match custom node labels; also used for the endpoints of
  /// edge elements). Ids not present fall back to the id string itself.
  /// -> dictionary
  labels: (:),
  /// Select a single view by its #raw("aux-kind") when the step carries
  /// more than one (e.g. #raw("\"partition\"") for Kruskal's disjoint
  /// sets). #raw("auto") renders every view the step holds, stacked.
  /// -> auto | str
  view: auto,
  /// Op-theme override, used to color MST elements by status
  /// (attention / success / danger). #raw("auto") reads the active
  /// #raw("set-op-theme") state; a dict bakes it in. Unused by the
  /// queue/stack kinds.
  /// -> auto | dictionary
  theme: auto,
  /// Render-theme override. #raw("auto") reads the active
  /// #raw("set-render-theme") state; a dict bakes it in.
  /// -> auto | dictionary
  render-theme: auto,
) = {
  assert(
    type(step) == dictionary
      and (step.at("aux-views", default: none) != none or step.at("aux-kind", default: none) != none),
    message: "aux-strip: expected a `step` dict carrying `aux`/`aux-kind` (from "
      + "`bfs-display` / `dfs-display` / `mst-prim-display`) or `aux-views` "
      + "(from `mst-kruskal-display`); got "
      + repr(step),
  )
  // Normalize to a list of `(kind, items)` views: the multi-view
  // `aux-views` key if present, else the single `(aux-kind, aux)` pair.
  let views = if step.at("aux-views", default: none) != none {
    step.aux-views
  } else {
    ((kind: step.aux-kind, items: step.at("aux", default: ())),)
  }
  if view != auto { views = views.filter(v => v.kind == view) }
  _with-strip-themes(theme, render-theme, (op, rt) => {
    let multi = views.len() > 1
    let rendered = views.map(v => {
      let body = _aux-view(v.kind, v.items, labels, op, rt)
      if multi {
        stack(dir: ttb, spacing: 0.25em, _strip-end-label(rt, _view-title(v.kind)), body)
      } else { body }
    })
    if rendered.len() == 1 { rendered.first() } else { stack(dir: ttb, spacing: 0.7em, ..rendered) }
  })
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
      // Terminal prune frame: drop every non-tree edge so the animation
      // ends on the spanning tree alone (mirrors the BFS/DFS
      // spanning-tree mode).
      moments.push((
        kind: "prune",
        visited: visited,
        tree-keys: tree-keys,
        frontier: (),
        chosen: none,
        total: total,
      ))

      // The frontier priority queue for `aux-strip`: crossing edges
      // relative to `visited`, sorted ascending by weight (min first).
      // On a "consider" moment the min is the chosen edge (ringed on the
      // canvas), so tag it accordingly; otherwise all are candidates.
      let prim-pq(visited, mark-chosen) = self.edges
        .filter(e => (
          (visited.contains(e.u) and not visited.contains(e.v))
            or (visited.contains(e.v) and not visited.contains(e.u))
        ))
        .sorted(key: e => e.weight)
        .enumerate()
        .map(((i, e)) => (
          u: e.u,
          v: e.v,
          weight: e.weight,
          status: if mark-chosen and i == 0 { "chosen" } else { "candidate" },
        ))
      let pq-note(items) = if items.len() == 0 {
        " Frontier is empty."
      } else {
        let listing = items.map(it => it.u + "–" + it.v + " (" + str(it.weight) + ")").join(", ")
        " Frontier: " + listing + "."
      }

      let pfx = "Minimum spanning tree (Prim) on " + (self.describe)() + ". "
      let captions = ()
      let steps-meta = ()
      let alts = ()
      for m in moments {
        let pq = prim-pq(m.visited, m.kind == "consider")
        if m.kind == "init" {
          captions.push([Start at #start])
          steps-meta.push((kind: "init", start: start, aux: pq, aux-kind: "pq"))
          alts.push(pfx + "Starting Prim's algorithm at node " + start + "." + pq-note(pq))
        } else if m.kind == "consider" {
          let c = m.chosen
          captions.push([Min crossing edge: #(c.u)–#(c.v) (#(c.weight))])
          steps-meta.push((kind: "consider", edge: (c.u, c.v), weight: c.weight, aux: pq, aux-kind: "pq"))
          alts.push(
            "Examining the frontier; the lightest crossing edge is "
              + c.u + "–" + c.v + " with weight " + str(c.weight) + "." + pq-note(pq),
          )
        } else if m.kind == "commit" {
          let c = m.chosen
          captions.push([Add #(c.u)–#(c.v); tree weight #(m.total)])
          steps-meta.push((
            kind: "commit",
            edge: (c.u, c.v),
            node: m.new-node,
            total: m.total,
            aux: pq,
            aux-kind: "pq",
          ))
          alts.push(
            "Adding edge " + c.u + "–" + c.v + " and node " + m.new-node
              + "; tree weight is now " + str(m.total) + "." + pq-note(pq),
          )
        } else if m.kind == "done" {
          captions.push([MST weight #(m.total)])
          steps-meta.push((kind: "done", total: m.total, aux: pq, aux-kind: "pq"))
          alts.push("Minimum spanning tree complete; total weight " + str(m.total) + "." + pq-note(pq))
        } else {
          captions.push([Spanning tree])
          steps-meta.push((
            kind: "spanning-tree",
            edges: m.tree-keys.len(),
            nodes: m.visited.len(),
            total: m.total,
            aux: pq,
            aux-kind: "pq",
          ))
          alts.push(
            "Removed the non-tree edges; the minimum spanning tree ("
              + str(m.tree-keys.len()) + " edge(s) over " + str(m.visited.len())
              + " node(s), total weight " + str(m.total) + ") remains." + pq-note(pq),
          )
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
          } else if m.kind == "prune" {
            // Hide every edge that isn't in the spanning tree.
            for e in pg.edges {
              if not m.tree-keys.contains(e.key) {
                r = (r.patch)(f => (f.style-edge)(e.key, hide: true))
              }
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
      let sorted-keys = sorted-edges.map(e => graph-draw.edge-key(e.u, e.v, directed: self.directed))
      let parent = (:)
      for id in all-ids { parent.insert(id, id) }
      let tree-keys = ()
      let total = 0
      // `processed` counts edges already decided (added or rejected);
      // `current` is the index of the edge under consideration (or none).
      // Both drive the sorted-edge-list aux view's status/cursor.
      let moments = (
        (kind: "init", parent: parent, tree-keys: (), edge: none, total: 0, processed: 0, current: none),
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
          tree-keys = tree-keys + (graph-draw.edge-key(e.u, e.v, directed: self.directed),)
          total = total + e.weight
          moments.push((
            kind: "add",
            parent: parent,
            tree-keys: tree-keys,
            edge: e,
            total: total,
            processed: ci + 1,
            current: none,
          ))
        } else {
          moments.push((
            kind: "reject",
            parent: parent,
            tree-keys: tree-keys,
            edge: e,
            total: total,
            processed: ci + 1,
            current: none,
          ))
        }
      }
      moments.push((
        kind: "done",
        parent: parent,
        tree-keys: tree-keys,
        edge: none,
        total: total,
        processed: sorted-edges.len(),
        current: none,
      ))
      // Terminal prune frame: drop every non-tree edge so the animation
      // ends on the spanning tree alone (mirrors the BFS/DFS
      // spanning-tree mode).
      moments.push((
        kind: "prune",
        parent: parent,
        tree-keys: tree-keys,
        edge: none,
        total: total,
        processed: sorted-edges.len(),
        current: none,
      ))

      // Build a moment's two aux views. The edge-list tags each sorted
      // edge by status: `added` if it's a tree edge, `current` if it's
      // the one under consideration, `rejected` if already decided but
      // not added, else `pending`. The partition groups the node ids by
      // their union-find root (one group per component).
      let edge-list-items(m) = range(sorted-edges.len()).map(j => {
        let e = sorted-edges.at(j)
        let status = if m.tree-keys.contains(sorted-keys.at(j)) {
          "added"
        } else if m.current != none and j == m.current {
          "current"
        } else if j < m.processed {
          "rejected"
        } else {
          "pending"
        }
        (u: e.u, v: e.v, weight: e.weight, status: status)
      })
      let partition(parent) = {
        let groups = (:)
        let order = ()
        for id in all-ids {
          let r = _uf-find(parent, id)
          if r in groups { groups.at(r).push(id) } else {
            groups.insert(r, (id,))
            order.push(r)
          }
        }
        order.map(r => groups.at(r))
      }
      let aux-note(m) = {
        let listing = partition(m.parent).map(g => "{" + g.join(", ") + "}").join(" ")
        " Components: " + listing + "."
      }
      let aux-views-of(m) = (
        (kind: "edge-list", items: edge-list-items(m)),
        (kind: "partition", items: partition(m.parent)),
      )

      let pfx = "Minimum spanning tree (Kruskal) on " + (self.describe)() + ". "
      let captions = ()
      let steps-meta = ()
      let alts = ()
      for m in moments {
        let views = aux-views-of(m)
        if m.kind == "init" {
          captions.push([Sort edges by weight])
          steps-meta.push((kind: "init", aux-views: views))
          alts.push(
            pfx + "Consider edges in increasing weight order; each node starts in its own component."
              + aux-note(m),
          )
        } else if m.kind == "consider" {
          let e = m.edge
          captions.push([Consider #(e.u)–#(e.v) (#(e.weight))])
          steps-meta.push((kind: "consider", edge: (e.u, e.v), weight: e.weight, aux-views: views))
          alts.push("Considering edge " + e.u + "–" + e.v + " with weight " + str(e.weight) + "." + aux-note(m))
        } else if m.kind == "add" {
          let e = m.edge
          captions.push([Add #(e.u)–#(e.v); weight #(m.total)])
          steps-meta.push((kind: "add", edge: (e.u, e.v), total: m.total, aux-views: views))
          alts.push(
            e.u + " and " + e.v + " are in different components; add the edge and merge them. Total weight "
              + str(m.total) + "." + aux-note(m),
          )
        } else if m.kind == "reject" {
          let e = m.edge
          captions.push([Reject #(e.u)–#(e.v) (cycle)])
          steps-meta.push((kind: "reject", edge: (e.u, e.v), aux-views: views))
          alts.push(
            e.u + " and " + e.v + " are already connected; this edge would form a cycle, so skip it."
              + aux-note(m),
          )
        } else if m.kind == "done" {
          captions.push([MST weight #(m.total)])
          steps-meta.push((kind: "done", total: m.total, aux-views: views))
          alts.push("Minimum spanning tree complete; total weight " + str(m.total) + "." + aux-note(m))
        } else {
          captions.push([Spanning tree])
          steps-meta.push((
            kind: "spanning-tree",
            edges: m.tree-keys.len(),
            nodes: all-ids.len(),
            total: m.total,
            aux-views: views,
          ))
          alts.push(
            "Removed the non-tree edges; the minimum spanning tree ("
              + str(m.tree-keys.len()) + " edge(s) over " + str(all-ids.len())
              + " node(s), total weight " + str(m.total) + ") remains." + aux-note(m),
          )
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
          } else if m.kind == "prune" {
            // Hide every edge that isn't in the spanning tree.
            for e in pg.edges {
              if not m.tree-keys.contains(e.key) {
                r = (r.patch)(f => (f.style-edge)(e.key, hide: true))
              }
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
    // `sort-frontier: true` enqueues each node's unseen neighbours in
    // ascending node-id order (a lexicographic string sort) instead of
    // edge-declaration order, giving a deterministic A-before-B / "0"-
    // before-"1" visit sequence.
    // `spanning-tree: true` renders the BFS tree instead of the palette
    // traversal: each node joins the tree with a uniform commit style and
    // its discovery edge (the edge from the node that first enqueued it)
    // is highlighted. Full-component only — incompatible with `target`.
    bfs-display: (self, start, target: none, sort-frontier: false, spanning-tree: false, positions: auto, scale: 1, node-style: (:), layout: none, layout-unit: 36pt, theme: auto, render-theme: auto) => {
      let positions = _resolve-positions(self, positions, layout, layout-unit)
      let pg = (self.positioned)(positions: positions, scale: scale)
      assert(start in self.nodes, message: "bfs-display: start node '" + start + "' not in graph.")
      assert(
        target == none or target in self.nodes,
        message: "bfs-display: target node " + repr(target) + " not in graph.",
      )
      assert(
        not spanning-tree or target == none,
        message: "bfs-display: spanning-tree mode spans the whole reachable component; it does not support a target.",
      )
      let order = ()
      // BFS-tree parent of each node: the node that first enqueued it.
      let parents = (:)
      // Parallel to the frame sequence: index 0 is the initial queue,
      // index i the queue state after visiting order[i-1] (the frontier
      // heading into the next dequeue). Drives `aux-strip`.
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
        let frontier = (self.neighbors)(u)
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
      let tree-edges = if spanning-tree {
        order.map(id => if id in parents {
          graph-draw.edge-key(parents.at(id), id, directed: self.directed)
        } else { none })
      } else { none }
      _render-graph-traversal(
        self,
        pg,
        order,
        "breadth-first",
        _resolve-op-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
        target: target,
        node-style: node-style,
        aux: aux-states,
        aux-kind: "queue",
        tree-edges: tree-edges,
      )
    },
    // ---- Depth-first traversal / search (iterative pre-order) ----
    // As with `bfs-display`, a non-`none` `target` turns the traversal
    // into a search that stops the moment the target is visited.
    // `sort-frontier: true` explores each node's unseen neighbours in
    // ascending node-id order (a lexicographic string sort): the ids are
    // sorted ascending, then pushed reversed so the smallest lands on top
    // of the stack and is popped first.
    // `spanning-tree: true` renders the DFS tree instead of the palette
    // traversal: each node joins the tree with a uniform commit style and
    // its discovery edge (from the node whose push it was popped by) is
    // highlighted. Full-component only — incompatible with `target`.
    dfs-display: (self, start, target: none, sort-frontier: false, spanning-tree: false, positions: auto, scale: 1, node-style: (:), layout: none, layout-unit: 36pt, theme: auto, render-theme: auto) => {
      let positions = _resolve-positions(self, positions, layout, layout-unit)
      let pg = (self.positioned)(positions: positions, scale: scale)
      assert(start in self.nodes, message: "dfs-display: start node '" + start + "' not in graph.")
      assert(
        target == none or target in self.nodes,
        message: "dfs-display: target node " + repr(target) + " not in graph.",
      )
      assert(
        not spanning-tree or target == none,
        message: "dfs-display: spanning-tree mode spans the whole reachable component; it does not support a target.",
      )
      let order = ()
      // DFS-tree parent of each node: whoever's push got it popped. The
      // stack holds (id, parent) pairs so this is captured faithfully
      // even when a node is pushed by several parents before being popped.
      let parents = (:)
      // Parallel to the frame sequence: index 0 is the initial stack,
      // index i the stack state after visiting order[i-1]. Faithful to
      // the iterative algorithm: a node can sit in the stack more than
      // once and be popped-and-skipped later, so duplicates are kept.
      // Drives `aux-strip` (mapped back to bare ids).
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
          // Push unseen neighbours reversed so the first neighbour is
          // explored first (pre-order).
          let nbs = (self.neighbors)(u).map(nb => nb.id).filter(id => not seen.contains(id))
          if sort-frontier { nbs = nbs.sorted() }
          for id in nbs.rev() { stack.push((id: id, parent: u)) }
          aux-states.push(stack.map(e => e.id))
        }
      }
      let tree-edges = if spanning-tree {
        order.map(id => if id in parents {
          graph-draw.edge-key(parents.at(id), id, directed: self.directed)
        } else { none })
      } else { none }
      _render-graph-traversal(
        self,
        pg,
        order,
        "depth-first",
        _resolve-op-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
        target: target,
        node-style: node-style,
        aux: aux-states,
        aux-kind: "stack",
        tree-edges: tree-edges,
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
