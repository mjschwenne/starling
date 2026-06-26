// Static graph rendering — undirected (weights) and directed (arrowheads).
#import "/src/lib.typ" as starling
#import starling: graph

#let g = graph(
  (("A", 0, 0), ("B", 3, 1), ("C", 1.5, 2.6), ("D", 4.5, 2.6)),
  edges: (
    ("A", "B", 7),
    ("B", "C", 2),
    ("A", "C", 4),
    ("C", "D", 5),
    ("B", "D", 1),
  ),
)

#starling.last((g.display)())

#let d = graph(
  (("S", 0, 0), ("T", 3, 0), ("U", 1.5, 2)),
  edges: (("S", "T", 3), ("S", "U", 1), ("U", "T", 1)),
  directed: true,
)

#starling.last((d.display)())
