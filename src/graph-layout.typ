// Optional auto-layout for graphs via diagraph-layout (a WASM-graphviz
// Typst package — no external graphviz binary). The `diagraph-layout`
// import lives INSIDE `auto-layout` (not at module scope), so it is
// only resolved when `auto-layout` is actually called — Typst evaluates
// an `import` lazily when it sits in a function body. That keeps the
// dependency optional even though `lib.typ` re-exports `auto-layout`:
// `import starling` loads this module but never touches the import
// until you call the function. Users reach it through the package
// entrypoint like everything else:
//
//   #import "@preview/starling:<ver>": auto-layout
//   // or, working in-tree:
//   #import "/src/graph-layout.typ": auto-layout
//
// then feed the result to a Graph display:
//
//   #let g = graph(("A", "B", "C"), edges: (("A", "B", 7),))
//   #last((g.dijkstra-display)("A", positions: auto-layout(g)))
//
// Manual positions remain the first-class path; this is a convenience
// for larger graphs where hand-placement is tedious.
//
// NOTE: Typst has no subpath package import — `@preview/starling:<ver>`
// resolves to the entrypoint only, never `.../src/graph-layout.typ`.
// That is why `auto-layout` must be re-exported from `lib.typ` rather
// than imported from this file's path by external users.

// Rough per-node box for `sizes: auto`. Estimates width from the
// label's character count (height fixed), expressed in the same pt
// scale as `diagraph-layout`'s defaults (75pt per inch, where the
// default node is 0.75in × 0.5in). No `measure` call, so it stays eager
// and usable outside a `context` — that is the whole point of the
// heuristic (see the `sizes` docs). Opaque content (anything that isn't
// a plain string or a single text element) falls back to a medium
// width, erring toward more spacing rather than overlap.
#let _estimate-size(label, id) = {
  let s = if label == auto { id } else { label }
  let chars = if type(s) == str {
    s.clusters().len()
  } else if type(s) == content and "text" in s.fields() {
    s.text.clusters().len()
  } else {
    8
  }
  (width: 22pt + calc.max(chars, 1) * 8.5pt, height: 36pt)
}

/// Compute node positions for #raw("g") with graphviz and return a
/// #raw("(id: (x, y))") map in cetz units, suitable for the
/// #raw("positions:") argument of any #raw("Graph") #raw("*-display")
/// method (or #raw("Graph.positioned")).
///
/// diagraph-layout returns node centers in points (y-up, matching
/// cetz); each coordinate is divided by #raw("unit") to convert to
/// cetz units. The default #raw("36pt") (½ inch) gives spacing that
/// suits the renderer's radius-0.6 nodes; lower it to spread the graph
/// out, raise it to pack it tighter. Edge spline points from graphviz
/// are ignored — starling draws straight edges.
///
/// #raw("sizes") controls how much room graphviz reserves per node:
/// #raw("none") uses graphviz's default node size (fine for short,
/// circular nodes); #raw("auto") estimates each node's box from its
/// label's character count so wide labels get spread apart; a
/// #raw("(id: (width, height))") dict supplies explicit lengths. The
/// #raw("auto") estimate is intentionally rough — it is computed
/// eagerly (no #raw("measure"), so #raw("auto-layout") stays callable
/// outside a #raw("context")) while #raw("draw-graph") sizes the drawn
/// node *exactly* by measuring the label. The two only approximate each
/// other, but graphviz's node margins absorb the slack; nudge
/// #raw("unit")/the display's #raw("scale:") if spacing looks off. The
/// #raw("*-display") methods pass #raw("sizes: auto") automatically
/// when you use their #raw("layout:") argument.
///
/// -> dictionary
#let auto-layout(
  /// The #raw("Graph") to lay out. Its positions (if any) are ignored;
  /// only nodes, edges, and directedness are used.
  /// -> Graph
  g,
  /// graphviz layout engine — #raw("\"dot\"") (layered, the default),
  /// #raw("\"neato\""), #raw("\"fdp\""), #raw("\"sfdp\""),
  /// #raw("\"circo\""), or #raw("\"twopi\"").
  /// -> str
  engine: "dot",
  /// Points per cetz unit used to scale graphviz's output.
  /// -> length
  unit: 36pt,
  /// Per-node box sizing fed to graphviz: #raw("none") (graphviz
  /// default), #raw("auto") (estimate from label length), or a
  /// #raw("(id: (width, height))") dict of explicit lengths.
  /// -> none | auto | dictionary
  sizes: none,
) = {
  // Lazy import: resolved only when this function runs, so merely
  // importing starling (which re-exports `auto-layout`) never pulls
  // the `diagraph-layout` dependency. See the file header.
  import "@preview/diagraph-layout:0.0.1" as dl
  let node-specs = g.nodes.keys().map(id => {
    if sizes == none {
      dl.node(id)
    } else {
      let sz = if sizes == auto {
        _estimate-size(g.nodes.at(id).at("label", default: auto), id)
      } else {
        let wh = sizes.at(id)
        (width: wh.at(0), height: wh.at(1))
      }
      dl.node(id, width: sz.width, height: sz.height)
    }
  })
  // edge(tail, head): the first argument is the tail, second the head,
  // so an arrow points u -> v for a directed graph.
  let edge-specs = g.edges.map(e => dl.edge(e.u, e.v))
  // When per-node sizes are supplied, ask graphviz to keep nodes from
  // overlapping. The layered `dot` engine already reserves node space by
  // construction, but the force-directed engines (`neato`/`fdp`/`sfdp`)
  // default to `overlap=true` and would pack sized nodes on top of each
  // other; `overlap=false` runs post-layout overlap removal using the
  // node sizes, which is what makes the `sizes` estimate spread wide
  // labels apart. A named arg to `layout-graph` becomes a GRAPH
  // attribute; `dot` harmlessly ignores `overlap`.
  let extra-attrs = if sizes == none { (:) } else { (overlap: "false") }
  let result = dl.layout-graph(
    ..node-specs,
    ..edge-specs,
    engine: engine,
    directed: g.directed,
    ..extra-attrs,
  )
  let positions = (:)
  for nd in result.nodes {
    positions.insert(nd.name, (nd.x / unit, nd.y / unit))
  }
  positions
}
