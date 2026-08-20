// Bent edges via the `bend` edge-style key, driven through the op command
// stream. Two opposite directed edges (A->B and B->A) given the same positive
// bend fan to opposite sides — so a mutual pair reads as two distinct arcs
// instead of overlapping into one undirected-looking line. C->A is left
// straight (bend defaults to 0). Each arc keeps its own weight on the convex
// side and a filled arrowhead on the boundary.
#import "/src/lib.typ" as starling
#import starling: apply-ops, graph, render, set-alt, style-edge

#let d = graph.new(
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

#let r = apply-ops(
  graph.renderer(d, sticky: true),
  style-edge(
    graph.ek(d, "A", "B"),
    graph.ek(d, "B", "A"),
    graph.ek(d, "B", "C"),
    graph.ek(d, "C", "B"),
    bend: 0.6,
  )
    + set-alt("Mutual directed pairs fanned apart with bend."),
)

#let frames = render(r)
#assert.eq(frames.len(), 1)

#starling.last(frames)
