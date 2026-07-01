// Depth-first spanning tree: `spanning-tree: true` renders the DFS tree
// instead of the palette traversal. Each node joins the tree with a
// uniform commit style and its discovery edge (from the node whose push
// it was popped by) is highlighted, accumulating into the tree.
// `sort-frontier: true` fixes the tree shape deterministically.
#import "/src/lib.typ" as starling
#import starling: graph

#let g = graph(
  (
    ("A", 0, 2), ("B", 1.5, 2), ("C", 3, 2),
    ("D", 0, 0.5), ("E", 1.5, 0.5), ("F", 3, 0.5),
  ),
  edges: (
    ("A", "B", 1), ("B", "C", 1),
    ("A", "D", 1), ("B", "E", 1), ("C", "F", 1),
    ("D", "E", 1), ("E", "F", 1),
  ),
)

#starling.stacked((g.dfs-display)("A", sort-frontier: true, spanning-tree: true))
