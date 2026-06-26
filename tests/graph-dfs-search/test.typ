// Depth-first *search*: like `bfs-display`, a non-`none` `target` stops
// the traversal the moment the target is visited and appends a terminal
// "found" / "not-found" frame. Here DFS dives along one branch and finds
// the target without exploring the rest of the graph.
#import "/src/lib.typ" as starling
#import starling: graph

#let g = graph(
  (("A", 0, 0), ("B", 3, 0.4), ("C", 1.5, 2.4), ("D", 4.5, 2.2), ("E", 6, 0.5)),
  edges: (
    ("A", "B", 7),
    ("B", "C", 2),
    ("A", "C", 4),
    ("C", "D", 5),
    ("B", "D", 1),
    ("D", "E", 3),
  ),
)

// Found.
#starling.stacked((g.dfs-display)("A", target: "D"))

// Not found: Z is unreachable, so the whole reachable component is
// visited before concluding.
#let h = graph(
  (("A", 0, 0), ("B", 3, 0), ("C", 1.5, 1.8), ("Z", 6, 0)),
  edges: (("A", "B", 1), ("A", "C", 2), ("B", "C", 3)),
)

#starling.stacked((h.dfs-display)("A", target: "Z"))
