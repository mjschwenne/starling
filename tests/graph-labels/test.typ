// Custom node/edge labels through the graph(..) factory.
// Node specs: bare id, (id, label), (id, x, y), (id, x, y, label).
// Edge third slot dispatches by type: number -> weight, str/content ->
// label drawn in its place; (u, v, weight, label) sets both.
#import "/src/lib.typ" as starling
#import starling: graph

#let g = graph(
  (
    ("A", 0, 0, [Start]),
    ("B", 3, 1, [Server]),
    ("C", 1.5, 2.6),
    ("D", 4.5, 2.6, [End]),
  ),
  edges: (
    ("A", "B", 7), // numeric weight
    ("B", "C", [TLS]), // content label, no weight shown
    ("A", "C", 4, [4 ms]), // weight 4 (for algorithms) shown as "4 ms"
    ("C", "D", 5),
    ("B", "D", 1),
  ),
)

#starling.last((g.display)())

// Labels survive into an algorithm display: weights still drive Prim,
// but labelled edges show their label.
#starling.last((g.mst-prim-display)("A"))
