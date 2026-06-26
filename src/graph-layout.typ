// Optional auto-layout for graphs via diagraph-layout (a WASM-graphviz
// Typst package — no external graphviz binary). This is the ONE file in
// starling that imports diagraph-layout, and NOTHING on the `lib.typ`
// path imports this file, so `import starling` never pulls the
// dependency. Users who want automatic layout import this module
// explicitly:
//
//   #import "@preview/starling:<ver>/src/graph-layout.typ": auto-layout
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

#import "@preview/diagraph-layout:0.0.1" as dl

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
) = {
  let node-specs = g.nodes.keys().map(id => dl.node(id))
  // edge(tail, head): the first argument is the tail, second the head,
  // so an arrow points u -> v for a directed graph.
  let edge-specs = g.edges.map(e => dl.edge(e.u, e.v))
  let result = dl.layout-graph(
    ..node-specs,
    ..edge-specs,
    engine: engine,
    directed: g.directed,
  )
  let positions = (:)
  for nd in result.nodes {
    positions.insert(nd.name, (nd.x / unit, nd.y / unit))
  }
  positions
}
