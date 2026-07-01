// Auxiliary-structure strips for BFS/DFS: each frame's `aux-strip`
// renders the helper structure (queue for BFS, stack for DFS) captured
// in `frame.step`. The diamond-plus-tail graph makes the DFS stack hold
// a duplicate (C is pushed before an earlier copy is popped), which the
// faithful strip shows verbatim.
#import "/src/lib.typ" as starling
#import starling: graph, aux-strip

#let g = graph(
  (("A", 0, 0), ("B", -1.5, -1.5), ("C", 1.5, -1.5), ("D", 0, -3), ("E", 0, -4.5)),
  edges: (("A", "B"), ("A", "C"), ("B", "D"), ("C", "D"), ("D", "E")),
)

// Lay out each frame as canvas + aux-strip beneath it.
#let with-strips(frames) = grid(
  columns: frames.len(),
  column-gutter: 1.2em,
  align: center + top,
  ..frames.map(f => stack(
    dir: ttb,
    spacing: 0.6em,
    starling.canvases-only((f,)).first(),
    aux-strip(f.step),
  )),
)

= BFS queue
#with-strips((g.bfs-display)("A"))

= DFS stack (faithful — note the duplicate C)
#with-strips((g.dfs-display)("A"))

= DFS search for E (terminal frame keeps last stack)
#with-strips((g.dfs-display)("A", target: "E"))
