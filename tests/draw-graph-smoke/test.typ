// Smoke test for the graph draw backend (`src/draw/graph.typ`) on the new
// core.
//
// Page 1  the op-stream path — theme-ref styling (which must follow the
//         per-renderer theme override), a ghosted node and its hidden
//         edges, an edge styled by `edge-key`, and per-node shapes.
// Page 2  the hand-composed path — `draw-graph(.., name: "g")` with
//         callouts anchored at `anchor(id, canvas: "g")` and at an
//         *edge*'s anchor, which this backend now emits.

#import "@preview/cetz:0.5.2"
#import "/src/core/draw-util.typ": anchor
#import "/src/core/frame.typ": make-renderer, render
#import "/src/core/ops.typ": annotate, apply-ops, commit, set-alt, style-edge
#import "/src/core/snapshot.typ": blank-snapshot
#import "/src/core/style.typ": role
#import "/src/core/theme.typ": resolve-theme
#import "/src/draw/graph.typ": draw-graph, edge-key
#import "/src/styles.typ" as styles

// A positioned graph — the shape `ds/graph.typ`'s `positioned` produces.
#let e(u, v, w) = (key: edge-key(u, v), u: u, v: v, weight: w, label: auto)
#let g = (
  directed: false,
  nodes: (
    A: (label: auto, pos: (0, 0)),
    B: (label: auto, pos: (3, 0.6)),
    C: (label: auto, pos: (1.5, 2.4)),
    D: (label: auto, pos: (4.4, 2.2)),
  ),
  edges: (e("A", "B", 7), e("B", "C", 2), e("A", "C", 4), e("B", "D", 5)),
)

#let r = make-renderer(
  g,
  draw-graph,
  sticky: true,
  node-style: (shape: "ellipse"),
  theme: (op: (success-fill: olive.lighten(60%))),
)
#let r = apply-ops(
  r,
  // Theme references: the success fill must come out olive (the
  // renderer's override), the settled stroke from the default theme.
  styles.success("A")
    + styles.attention("C")
    + style-edge(edge-key("A", "C"), stroke: role("success-stroke"))
    + annotate("C", [4])
    + commit(alt: "Committed edge A-C."),
  // Ghosting a node also hides its edges, and keeps the canvas the same
  // size — the node's slot is still reserved.
)
#let r = apply-ops(
  r,
  styles.ghost("D", edge-key("B", "D")) + set-alt("D not yet discovered."),
)

#for f in render(r) {
  context (f.builder)(resolve-theme((:)))
}

#pagebreak()

// Hand-composed: no renderer, no context — the backend takes a plain
// `theme` default, so a bare `cetz.canvas` works outside any `context`.
#cetz.canvas({
  import cetz.draw: circle, content, line
  draw-graph(g, blank-snapshot(), name: "g")
  circle(anchor("D", canvas: "g"), radius: 0.85, stroke: red + 2pt)
  // Edges are named too, so a callout can point at one.
  line(
    anchor(edge-key("A", "B"), canvas: "g"),
    (rel: (0, -1.1)),
    stroke: blue + 2pt,
    mark: (end: ">"),
  )
  content((rel: (0, -0.15)), anchor: "north", text(size: 0.8em, [heaviest]))
})
