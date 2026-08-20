// Static tabular representations — adjacency matrix and adjacency list,
// undirected and directed, presence (1/0) and weighted. No cetz: these
// return placeable table content, not Frames.
#import "/src/lib.typ" as starling
#import starling: graph

#let g = graph.new(
  ("A", "B", "C", "D"),
  edges: (("A", "B", 7), ("B", "C", 2), ("A", "C", 4), ("C", "D", 5), ("B", "D", 1)),
)

// Undirected: presence then weighted, matrix and list.
#graph.adjacency-matrix(g)
#graph.adjacency-list(g)
#graph.adjacency-matrix(g, weights: true)
#graph.adjacency-list(g, weights: true)

// Directed: asymmetric matrix (row = source, column = target), a sink
// node (T) with no out-neighbors shows the empty marker in the list.
#let d = graph.new(
  ("S", "T", "U"),
  edges: (("S", "T", 3), ("S", "U", 1), ("U", "T", 1)),
  directed: true,
)
#graph.adjacency-matrix(d, weights: true)
#graph.adjacency-list(d, weights: true)

// Custom labels, an isolated node, and a render-theme override.
#let h = graph.new(
  (("X", 0, 0, [Node X]), "Y", "Z"),
  edges: (("X", "Y", 1),),
)
#graph.adjacency-list(h)
#graph.adjacency-matrix(h, theme: (render: (node-fill: rgb("#eef"))))
