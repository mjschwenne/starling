// Kruskal's MST animation: edges considered in weight order
// (attention-stroke), added (success-stroke) or rejected as a cycle
// (danger-stroke); union-find components shown by node color.
#import "/src/lib.typ" as starling
#import starling: graph

#let g = graph(
  (("A", 0, 0), ("B", 3, 0.4), ("C", 1.5, 2.4), ("D", 4.5, 2.2)),
  edges: (
    ("A", "B", 7),
    ("B", "C", 2),
    ("A", "C", 4),
    ("C", "D", 5),
    ("B", "D", 1),
  ),
)

#starling.stacked((g.mst-kruskal-display)())
