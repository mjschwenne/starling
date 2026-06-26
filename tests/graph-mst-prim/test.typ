// Prim's MST animation: frontier edges (search-stroke), chosen minimum
// (attention-stroke), committed tree edges (success-stroke), settled
// nodes, running tree weight in captions.
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

#starling.stacked((g.mst-prim-display)("A"))
