// Bent edges via the `bend` edge-style key, driven through the Op
// command stream. Two opposite directed edges (A->B and B->A) given the
// same positive bend fan to opposite sides — so a mutual pair reads as
// two distinct arcs instead of overlapping into one undirected-looking
// line. C->A is left straight (bend defaults to 0). Each arc keeps its
// own weight on the convex side and a filled arrowhead on the boundary.
#import "/src/lib.typ" as starling
#import starling: graph, Op, apply-ops, make-graph-renderer, edge-key

#let d = graph(
  (("A", 0, 0), ("B", 3, 0), ("C", 1.5, 2.4)),
  edges: (
    ("A", "B", 1),
    ("B", "A", 2), // mutual pair with A->B
    ("B", "C", 3),
    ("C", "B", 4), // mutual pair with B->C
    ("C", "A", 5), // single edge, stays straight
  ),
  directed: true,
)

#let r = make-graph-renderer((d.positioned)(), sticky: true)
#let r = apply-ops(
  r,
  (
    (Op.StyleEdge.new)(path: edge-key("A", "B", directed: true), style: (bend: 0.6)),
    (Op.StyleEdge.new)(path: edge-key("B", "A", directed: true), style: (bend: 0.6)),
    (Op.StyleEdge.new)(path: edge-key("B", "C", directed: true), style: (bend: 0.6)),
    (Op.StyleEdge.new)(path: edge-key("C", "B", directed: true), style: (bend: 0.6)),
    (Op.Alt.new)(text: "Mutual directed pairs fanned apart with bend."),
  ),
)

#let frames = (r.render)()
#assert.eq(frames.len(), 1)

#starling.last(frames)
