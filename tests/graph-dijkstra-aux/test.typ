// Auxiliary strips for Dijkstra: each `dijkstra-display` frame carries
// three `aux-views` — the priority queue of `(node, dist)` entries (min
// first, the polled entry ringed), and the `dist` and `prev` maps.
// `aux-strip` renders all three stacked beneath the canvas. This runs a
// full traversal (no `target`) so the terminal "skip" frames appear: a
// stale duplicate polled for an already-visited node is ringed in
// danger-stroke in both the queue and on the canvas — the payoff of the
// add-a-new-instance model.
#import "/src/lib.typ" as starling
#import starling: aux-strip, canvas, graph

#let dg = graph.new(
  (("S", 0, 0), ("A", 2.5, 1.2), ("B", 2.5, -1.2), ("T", 5, 0)),
  edges: (
    ("S", "A", 1),
    ("S", "B", 4),
    ("A", "B", 1),
    ("A", "T", 5),
    ("B", "T", 1),
  ),
  directed: true,
)

#let frames = graph.dijkstra-display(dg, "S")

// Canvas + all three aux views per frame, wrapped into a grid so the
// full 12-frame run stays a reasonable shape.
= Priority queue + dist / prev maps
#grid(
  columns: 3,
  column-gutter: 2.6em,
  row-gutter: 1.6em,
  align: center + top,
  ..frames.map(f => stack(
    dir: ttb,
    spacing: 0.6em,
    canvas(f),
    aux-strip(f.step),
    text(0.8em, f.caption),
  )),
)

// The `view:` selector isolates one aux view for separate placement,
// e.g. laying the priority queue and the two maps in different spots of
// a slide. `title: true` keeps each view's name (which is only shown by
// default when several views are stacked). Exercise both on the "update
// neighbors of A" frame.
#let mid = frames.at(4)
= Single views (`view:` + `title: true`)
#grid(
  columns: 3,
  column-gutter: 1.6em,
  align: center + top,
  aux-strip(mid.step, view: "dist-pq", title: true),
  aux-strip(mid.step, view: "dist-map", title: true),
  aux-strip(mid.step, view: "prev-map", title: true),
)

// Reconstruction phase (`reconstruct: true`, `node-distances: false`):
// the terminal frames walk `prev` back from the end. The canvas grows
// the route one hop at a time (prepended node ringed) and the `prev` map
// traces the chain being read — the cell read this hop marked `current`,
// earlier reads `added`.
#let recon = graph.dijkstra-display(dg, "S", target: "T", node-distances: false, reconstruct: true)
= Path reconstruction (`prev` trace)
#stack(
  dir: ttb,
  spacing: 1em,
  ..recon.slice(recon.len() - 5).map(f => grid(
    columns: (auto, auto, auto),
    column-gutter: 1.5em,
    align: horizon + left,
    canvas(f),
    aux-strip(f.step, view: "prev-map", title: true),
    text(0.85em, f.caption),
  )),
)
