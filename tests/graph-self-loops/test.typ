// Self-edges (loops) and bidirectional directed edges. A self-edge
// (u == v) draws as a teardrop loop above the node — with a filled
// arrowhead landing back on the node when directed, plain otherwise.
// Opposite directed edges (A->B and B->A) get solid filled arrowheads
// so neither line shows through the other's tip.
#import "/src/lib.typ" as starling
#import starling: graph

#let d = graph(
  (("A", 0, 0), ("B", 3, 0), ("C", 1.5, 2.4)),
  edges: (
    ("A", "B", 1),
    ("B", "A", 2), // opposite direction — exercises filled arrowheads
    ("B", "C", 3),
    ("C", "A", 4),
    ("A", "A", 9), // directed self-loop with a weight
    ("C", "C"), // directed self-loop, no weight
  ),
  directed: true,
)

#starling.last((d.display)())

// Undirected self-loop draws the teardrop with no arrowhead.
#let u = graph(
  (("X", 0, 0), ("Y", 2.5, 0)),
  edges: (("X", "Y", 5), ("X", "X", 1)),
)

#starling.last((u.display)())
