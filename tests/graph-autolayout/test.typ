// Optional auto-layout via diagraph-layout (WASM graphviz). This test
// imports /src/graph-layout.typ DIRECTLY — the lib.typ path never pulls
// the dependency, so the rest of the suite stays diagraph-free. A
// position-less graph is laid out by graphviz and rendered statically
// and through an algorithm display (positions threaded in).
#import "/src/lib.typ": graph, last, stacked
#import "/src/graph-layout.typ": auto-layout

// No coordinates — positions come from graphviz.
#let g = graph(
  ("A", "B", "C", "D", "E"),
  edges: (
    ("A", "B", 7),
    ("B", "C", 2),
    ("A", "C", 4),
    ("C", "D", 5),
    ("B", "D", 1),
    ("C", "E", 6),
    ("D", "E", 3),
  ),
)

#let pos = auto-layout(g)

// Static render with the computed layout.
#last((g.display)(positions: pos))

// An algorithm display also accepts the computed positions.
#last((g.mst-prim-display)("A", positions: pos))
