// Edge weight-label side via the `label-offset` edge-style key, driven
// through the Op command stream. The default (+0.12) seats the weight on
// the left of the u->v direction; a negative offset flips it to the other
// side, and a larger magnitude widens the gap. Three horizontal directed
// edges share the same geometry so the placement is the only difference:
// A->B keeps the default (above the rightward edge), C->D flips below,
// E->F flips below with a wider gap.
#import "/src/lib.typ" as starling
#import starling: graph, Op, apply-ops, make-graph-renderer, edge-key

#let d = graph(
  (
    ("A", 0, 0), ("B", 3, 0),
    ("C", 0, -1.5), ("D", 3, -1.5),
    ("E", 0, -3), ("F", 3, -3),
  ),
  edges: (
    ("A", "B", 1), // default label-offset: left of A->B (above)
    ("C", "D", 2), // flipped to the right (below)
    ("E", "F", 3), // flipped, wider gap
  ),
  directed: true,
)

#let r = make-graph-renderer((d.positioned)(), sticky: true)
#let r = apply-ops(
  r,
  (
    (Op.StyleEdge.new)(path: edge-key("C", "D", directed: true), style: (label-offset: -0.12)),
    (Op.StyleEdge.new)(path: edge-key("E", "F", directed: true), style: (label-offset: -0.5)),
    (Op.Alt.new)(text: "Edge weight labels seated on chosen sides via label-offset."),
  ),
)

#let frames = (r.render)()
#assert.eq(frames.len(), 1)

#starling.last(frames)
