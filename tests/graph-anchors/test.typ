// Verify graph cetz integration: `draw-graph` emits a graph without wrapping
// it in `cetz.canvas`, and `anchor(<key>)` names the elements it draws, so
// user-drawn annotations can target a node by its id or an edge by its key.
//
// Note the selective `import cetz.draw:` — a glob import would shadow
// starling's `anchor` with cetz's own two-argument one.
#import "@preview/cetz:0.5.2"
#import "/src/lib.typ" as starling
#import starling: anchor, graph

#let g = graph.new(
  (("A", 0, 0), ("B", 3, 1), ("C", 1.5, 2.6)),
  edges: (("A", "B", 7), ("B", "C", 2), ("A", "C", 4)),
)

// Empty snapshot — no per-node style overrides.
#let snapshot = starling.blank-snapshot()

#cetz.canvas({
  import cetz.draw: circle
  starling.draw-graph(graph.positioned(g), snapshot)
  // Call out node C with a red ring and node A with a blue ring, targeting
  // them through the shared anchor scheme.
  circle(anchor("C"), radius: 0.85, stroke: red + 2pt)
  circle(anchor("A"), radius: 0.85, stroke: blue + 2pt)
})
