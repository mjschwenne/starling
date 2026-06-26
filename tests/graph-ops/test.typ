#import "/src/lib.typ": Graph, graph, edge-key

// Hand-built undirected weighted graph:
//        C
//       /|\
//      4 2 5
//     /  |  \
//    A---7---B---1---D   (and B-C = 2, C-D = 5)
#let g = graph(
  (("A", 0, 0), ("B", 3, 1), ("C", 1.5, 2.6), ("D", 4.5, 2.6)),
  edges: (
    ("A", "B", 7),
    ("B", "C", 2),
    ("A", "C", 4),
    ("C", "D", 5),
    ("B", "D", 1),
  ),
)

// edge-key: undirected sorts endpoints into one canonical key.
#assert.eq(edge-key("A", "B"), "A--B")
#assert.eq(edge-key("B", "A"), "A--B")
#assert.eq(edge-key("A", "B", directed: true), "A->B")
#assert.eq(edge-key("B", "A", directed: true), "B->A")
#assert.eq((g.ek)("D", "C"), "C--D")

// membership
#assert((g.contains-node)("A"))
#assert(not (g.contains-node)("Z"))
#assert((g.contains-edge)("A", "B"))
#assert((g.contains-edge)("B", "A")) // undirected: order-independent
#assert(not (g.contains-edge)("A", "D"))

// weights are order-independent in an undirected graph
#assert.eq((g.weight)("A", "B"), 7)
#assert.eq((g.weight)("B", "A"), 7)
#assert.eq((g.weight)("B", "D"), 1)

// neighbours: every incident edge contributes the other endpoint
#assert.eq((g.neighbors)("A"), ((id: "B", weight: 7), (id: "C", weight: 4)))
#assert.eq(
  (g.neighbors)("C"),
  ((id: "B", weight: 2), (id: "A", weight: 4), (id: "D", weight: 5)),
)

// structural invariants hold
#assert((g.check-invariants)())

// positioned: maps node ids to (label, pos) and edges to canonical keys
#let pg = (g.positioned)()
#assert.eq(pg.directed, false)
#assert.eq(pg.nodes.A.pos, (0, 0))
#assert.eq(pg.nodes.C.pos, (1.5, 2.6))
#assert.eq(pg.nodes.A.label, auto)
#assert.eq(pg.edges.first().key, "A--B")
#assert.eq(pg.edges.first().weight, 7)
#assert.eq(pg.edges.len(), 5)

// positioned accepts an explicit override map (auto-layout result shape)
#let pg2 = (g.positioned)(positions: (
  A: (10, 10),
  B: (11, 10),
  C: (10, 11),
  D: (11, 11),
))
#assert.eq(pg2.nodes.A.pos, (10, 10))

// ---- directed graph: edges and neighbours are one-way ----
#let dg = graph(
  (("S", 0, 0), ("T", 3, 0), ("U", 1.5, 2)),
  edges: (("S", "T", 3), ("S", "U", 1), ("U", "T", 1)),
  directed: true,
)
#assert.eq((dg.ek)("S", "T"), "S->T")
#assert((dg.contains-edge)("S", "T"))
#assert(not (dg.contains-edge)("T", "S")) // directed: one-way
// out-neighbours only
#assert.eq((dg.neighbors)("S"), ((id: "T", weight: 3), (id: "U", weight: 1)))
#assert.eq((dg.neighbors)("T"), ())
#assert.eq((dg.neighbors)("U"), ((id: "T", weight: 1),))

// describe mentions kind, node count, and edge count
#assert.eq(
  (dg.describe)(),
  "directed graph with 3 nodes (S, T, U) and 3 edges: S -> T (w=3); S -> U (w=1); U -> T (w=1)",
)

// ---- builder methods compose immutably ----
#let g0 = (Graph.new)(nodes: (:), edges: (), directed: false, positions: (:))
#let g1 = (g0.add-node)("X", pos: (0, 0))
#let g2 = (g1.add-node)("Y", label: "why", pos: (1, 0))
#let g3 = (g2.add-edge)("X", "Y", weight: 9)
#assert((g3.contains-edge)("X", "Y"))
#assert.eq((g3.weight)("X", "Y"), 9)
#assert.eq(((g3.positioned)()).nodes.Y.label, "why")
// original is untouched (immutability)
#assert(not (g0.contains-node)("X"))
