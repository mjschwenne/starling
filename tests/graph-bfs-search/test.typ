// Breadth-first *search*: passing `target:` stops the traversal the
// moment the target is dequeued, then appends a terminal frame that
// rings the found node in settled-stroke and captions "Found <t>".
// The second graph exercises the unreachable case (terminal
// "<t> not found" frame, nothing ringed).
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

// Found: stops at D before E is ever visited.
#starling.stacked((g.bfs-display)("A", target: "D"))

// Not found: Z is in its own component, unreachable from A.
#let h = graph(
  (("A", 0, 0), ("B", 3, 0), ("C", 1.5, 1.8), ("Z", 6, 0)),
  edges: (("A", "B", 1), ("A", "C", 2), ("B", "C", 3)),
)

#starling.stacked((h.bfs-display)("A", target: "Z"))
