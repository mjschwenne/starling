// Frontier priority-queue strip for Prim's MST: each `mst-prim-display`
// frame carries an `aux`/`aux-kind: "pq"` snapshot of the crossing edges
// sorted by weight (min first). `aux-strip` renders it beneath the
// canvas; the chosen (min) edge is ringed to match the canvas attention
// stroke, so a student can read off which edge Prim pops next.
#import "/src/lib.typ" as starling
#import starling: graph, aux-strip

#let g = graph(
  (("A", 0, 0), ("B", 2, 0), ("C", 1, -1.5), ("D", 3, -1.5)),
  edges: (("A", "B", 3), ("A", "C", 1), ("B", "C", 5), ("B", "D", 4), ("C", "D", 2)),
)

// Lay out each frame as canvas + frontier strip beneath it.
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

= Prim frontier priority queue
#with-strips((g.mst-prim-display)("A"))
