// Dijkstra's shortest paths on a DIRECTED graph (exercises arrowheads).
// Tentative distances in the node note slot, current node
// (attention-stroke), finalized nodes (settled + fill), shortest-path
// tree edges (success-stroke), and the final S->T path (settled-stroke).
#import "/src/lib.typ" as starling
#import starling: graph

#let dg = graph(
  (("S", 0, 0), ("A", 2.5, 1.2), ("B", 2.5, -1.2), ("T", 5, 0)),
  edges: (
    ("S", "A", 1),
    ("S", "B", 4),
    ("A", "B", 1),
    ("A", "T", 5),
    ("B", "T", 1),
  ),
  directed: true,
)

= Default (distances on nodes, instant path)
#starling.stacked((dg.dijkstra-display)("S", target: "T"))

// `node-distances: false` drops the on-canvas distance notes (they live
// in the `dist` aux map instead); `reconstruct: true` appends the
// ConstructShortestPath phase — the route is built one hop at a time
// back from the end (settled stroke over the tree, the prepended node
// ringed) rather than highlighted all at once.
= node-distances: false + reconstruct: true
#starling.stacked((dg.dijkstra-display)("S", target: "T", node-distances: false, reconstruct: true))
