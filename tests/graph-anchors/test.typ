// Verify graph cetz integration: draw-graph emits a graph without
// wrapping it in cetz.canvas, and node-anchor names line up with the
// anchors draw-graph creates so user-drawn annotations can target
// nodes by id.
#import "@preview/cetz:0.5.2"
#import "/src/lib.typ" as starling
#import starling: graph

#let g = graph(
  (("A", 0, 0), ("B", 3, 1), ("C", 1.5, 2.6)),
  edges: (("A", "B", 7), ("B", "C", 2), ("A", "C", 4)),
)

// Empty snapshot — no per-node style overrides.
#let snapshot = starling.blank-snapshot()

#cetz.canvas({
  starling.draw-graph((g.positioned)(), snapshot)
  import cetz.draw: *
  // Call out node C with a red ring and node A with a blue ring,
  // targeting them via node-anchor.
  circle(starling.node-anchor("C"), radius: 0.85, stroke: red + 2pt)
  circle(starling.node-anchor("A"), radius: 0.85, stroke: blue + 2pt)
})
