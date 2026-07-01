// Two-view aux strips for Kruskal's MST: each `mst-kruskal-display`
// frame carries an `aux-views` list holding the sorted edge list (with a
// cursor + per-edge status: added / rejected / current / pending) and
// the disjoint-set partition (one group box per component). `aux-strip`
// stacks both views by default; `view:` selects one for separate
// placement. The graph has a cycle edge (B–C) so a "rejected" status is
// exercised.
#import "/src/lib.typ" as starling
#import starling: graph, aux-strip

#let g = graph(
  (("A", 0, 0), ("B", 2, 0), ("C", 1, -1.5), ("D", 3, -1.5)),
  edges: (("A", "B", 3), ("A", "C", 1), ("B", "C", 5), ("B", "D", 4), ("C", "D", 2)),
)

#let frames = (g.mst-kruskal-display)()

// Lay out each frame as canvas + both aux views stacked beneath it.
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

= Kruskal edge list + disjoint-set partition
#with-strips(frames)

= Partition view only (view: "partition")
#grid(
  columns: frames.len(),
  column-gutter: 1em,
  align: center + top,
  ..frames.map(f => aux-strip(f.step, view: "partition")),
)
