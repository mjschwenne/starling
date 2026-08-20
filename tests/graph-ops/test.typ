#import "/src/lib.typ": graph

// Hand-built undirected weighted graph:
//        C
//       /|\
//      4 2 5
//     /  |  \
//    A---7---B---1---D   (and B-C = 2, C-D = 5)
#let g = graph.new(
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
#assert.eq(graph.edge-key("A", "B"), "A--B")
#assert.eq(graph.edge-key("B", "A"), "A--B")
#assert.eq(graph.edge-key("A", "B", directed: true), "A->B")
#assert.eq(graph.edge-key("B", "A", directed: true), "B->A")
// `ek` is the same thing, reading directedness off the graph.
#assert.eq(graph.ek(g, "D", "C"), "C--D")

// membership
#assert(graph.contains-node(g, "A"))
#assert(not graph.contains-node(g, "Z"))
#assert(graph.contains-edge(g, "A", "B"))
#assert(graph.contains-edge(g, "B", "A")) // undirected: order-independent
#assert(not graph.contains-edge(g, "A", "D"))

// weights are order-independent in an undirected graph
#assert.eq(graph.weight(g, "A", "B"), 7)
#assert.eq(graph.weight(g, "B", "A"), 7)
#assert.eq(graph.weight(g, "B", "D"), 1)

// neighbours: every incident edge contributes the other endpoint
#assert.eq(graph.neighbors(g, "A"), ((id: "B", weight: 7), (id: "C", weight: 4)))
#assert.eq(
  graph.neighbors(g, "C"),
  ((id: "B", weight: 2), (id: "A", weight: 4), (id: "D", weight: 5)),
)

// structural invariants hold
#assert(graph.check-invariants(g))

// positioned: maps node ids to (label, pos) and edges to canonical keys
#let pg = graph.positioned(g)
#assert.eq(pg.directed, false)
#assert.eq(pg.nodes.A.pos, (0, 0))
#assert.eq(pg.nodes.C.pos, (1.5, 2.6))
#assert.eq(pg.nodes.A.label, auto)
#assert.eq(pg.edges.first().key, "A--B")
#assert.eq(pg.edges.first().weight, 7)
#assert.eq(pg.edges.len(), 5)

// positioned accepts an explicit override map (auto-layout result shape)
#let pg2 = graph.positioned(
  g,
  positions: (A: (10, 10), B: (11, 10), C: (10, 11), D: (11, 11)),
)
#assert.eq(pg2.nodes.A.pos, (10, 10))

// ---- directed graph: edges and neighbours are one-way ----
#let dg = graph.new(
  (("S", 0, 0), ("T", 3, 0), ("U", 1.5, 2)),
  edges: (("S", "T", 3), ("S", "U", 1), ("U", "T", 1)),
  directed: true,
)
#assert.eq(graph.ek(dg, "S", "T"), "S->T")
#assert(graph.contains-edge(dg, "S", "T"))
#assert(not graph.contains-edge(dg, "T", "S")) // directed: one-way
// out-neighbours only
#assert.eq(graph.neighbors(dg, "S"), ((id: "T", weight: 3), (id: "U", weight: 1)))
#assert.eq(graph.neighbors(dg, "T"), ())
#assert.eq(graph.neighbors(dg, "U"), ((id: "T", weight: 1),))

// describe mentions kind, node count, and edge count
#assert.eq(
  graph.describe(dg),
  "directed graph with 3 nodes (S, T, U) and 3 edges: S -> T (w=3); S -> U (w=1); U -> T (w=1)",
)

// ---- builders compose immutably ----
#let g0 = graph.new(())
#let g1 = graph.add-node(g0, "X", pos: (0, 0))
#let g2 = graph.add-node(g1, "Y", label: "why", pos: (1, 0))
#let g3 = graph.add-edge(g2, "X", "Y", weight: 9)
#assert(graph.contains-edge(g3, "X", "Y"))
#assert.eq(graph.weight(g3, "X", "Y"), 9)
#assert.eq(graph.positioned(g3).nodes.Y.label, "why")
// `with-position` moves a node without touching anything else.
#assert.eq(graph.positioned(graph.with-position(g3, "Y", (5, 5))).nodes.Y.pos, (5, 5))
// the originals are untouched (immutability)
#assert(not graph.contains-node(g0, "X"))
#assert.eq(graph.positioned(g3).nodes.Y.pos, (1, 0))

// ---- every algorithm display stamps its result: the unchanged graph ----
#import "/src/lib.typ": result
#assert.eq(result(graph.display(g)), g)
#assert.eq(result(graph.prim-display(g, "A")), g)
#assert.eq(result(graph.kruskal-display(g)), g)
#assert.eq(result(graph.dijkstra-display(dg, "S")), dg)
#assert.eq(result(graph.bfs-display(g, "A")), g)
#assert.eq(result(graph.dfs-display(g, "A")), g)

// ---- and every algorithm frame carries its aux views ----
#let kinds(frames) = frames.map(f => f.step.aux-views.map(v => v.kind)).dedup()
#assert.eq(kinds(graph.bfs-display(g, "A")), (("queue",),))
#assert.eq(kinds(graph.dfs-display(g, "A")), (("stack",),))
#assert.eq(kinds(graph.prim-display(g, "A")), (("pq",),))
#assert.eq(kinds(graph.kruskal-display(g)), (("edge-list", "partition"),))
#assert.eq(
  kinds(graph.dijkstra-display(dg, "S")),
  (("dist-pq", "dist-map", "prev-map"),),
)
