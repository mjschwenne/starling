// Smoke test for the tree draw backend (`src/draw/tree.typ`) on the new
// core: a structure and an op stream through `make-renderer` / `apply-ops`
// / `render`, plus a hand-composed canvas exercising `name:` and the
// shared `el-` anchors.
//
// Page 1  the op-stream path — theme-ref styling (which must follow the
//         per-renderer theme override), a ghosted subtree, and a
//         materialized nil sentinel.
// Page 2  the hand-composed path — `draw-tree(.., name: "t")` with
//         callouts anchored at `anchor(path, canvas: "t")`, including a
//         compass sub-anchor.

#import "@preview/cetz:0.5.2"
#import "/src/core/draw-util.typ": anchor
#import "/src/core/frame.typ": make-renderer, render
#import "/src/core/ops.typ": annotate, apply-ops, commit, set-alt, style-node
#import "/src/core/snapshot.typ": blank-snapshot
#import "/src/core/style.typ": role
#import "/src/core/theme.typ": default-theme, resolve-theme
#import "/src/draw/tree.typ": draw-tree
#import "/src/styles.typ" as styles

// Plain-dict binary nodes — the shape `ds/bst.typ` will produce.
#let leaf(v) = (value: v, label: auto, left: none, right: none)
#let node(v, l, r) = (value: v, label: auto, left: l, right: r)
#let t = node(
  8,
  node(3, leaf(1), node(6, leaf(4), none)),
  node(10, none, leaf(14)),
)

// The op stream. `sticky: true` is explicit — accumulation is what this
// path is for, but the renderer no longer defaults to it.
#let r = make-renderer(t, draw-tree, sticky: true, theme: (op: (search-stroke: (paint: teal, thickness: 3pt))))
#let r = apply-ops(
  r,
  // A theme reference resolved at render time: this must come out teal
  // (the renderer's override), not the default blue.
  styles.search("", "L")
    + annotate("L", [3 < 8])
    + commit(alt: "Descending left from 8.")
    // Elided subtree + a ghosted branch: both keep their layout footprint,
    // so the drawn part of the tree does not shift between frames.
    + styles.subtree("LR")
    + styles.ghost("R", "RR")
    + style-node("LRL", fill: role("success-fill"))
    // A nil slot materialized as an explicit sentinel.
    + styles.nullify("LRR")
    + set-alt("Right subtree ghosted, left-right elided."),
)

#for f in render(r) {
  context (f.builder)(resolve-theme((:)))
}

#pagebreak()

// Hand-composed: no renderer, no context — the backend takes a plain
// `theme` default, so a bare `cetz.canvas` works outside any `context`.
#cetz.canvas({
  import cetz.draw: circle, content, line
  draw-tree(t, blank-snapshot(), name: "t")
  // Point anchor.
  circle(anchor("LRL", canvas: "t"), radius: 0.85, stroke: red + 2pt)
  // Compass sub-anchor, and the root's special "el-root" name.
  line(
    anchor("", canvas: "t") + ".north",
    (rel: (1.2, 0.8)),
    stroke: blue + 2pt,
    mark: (end: ">"),
  )
  content((rel: (0.1, 0.1)), anchor: "west", text(size: 0.8em, [root]))
})
