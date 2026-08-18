// Smoke test for the array draw backend (`src/draw/array.typ`) on the new
// core.
//
// Page 1  the op-stream path — theme-ref styling (which must follow the
//         per-renderer theme override), arrows styled through the `edges`
//         slot by their own id, and a ghosted output cell.
// Page 2  the hand-composed path — `draw-array(.., name: "a")` with
//         callouts anchored at `anchor(cell-key(row, col), canvas: "a")`,
//         including a compass sub-anchor.

#import "@preview/cetz:0.5.2"
#import "/src/core/draw-util.typ": anchor
#import "/src/core/frame.typ": make-renderer, render
#import "/src/core/ops.typ": annotate, apply-ops, commit, set-alt, style-edge
#import "/src/core/snapshot.typ": blank-snapshot
#import "/src/core/style.typ": role
#import "/src/core/theme.typ": resolve-theme
#import "/src/draw/array.typ": cell-key, draw-array
#import "/src/styles.typ" as styles

// A positioned table — the shape `ds/sort.typ`'s `positioned` produces.
#let c(v) = (value: v, sub: none)
#let tbl = (
  rows: (
    (
      id: "in",
      label: [input],
      cells: (c([2]), c([0]), c([3]), c([0])),
      indices: auto,
      kind: "data",
    ),
    (
      id: "count",
      label: [count],
      cells: (c([2]), c([0]), c([1]), c([1])),
      indices: auto,
      kind: "count",
    ),
    (
      id: "out",
      label: [output],
      cells: (c([0]), c([0]), c(none), c(none)),
      indices: none,
      kind: "data",
    ),
  ),
  arrows: (
    (id: "read", from: (row: "in", col: 2), to: (row: "count", col: 3)),
    (id: "place", from: (row: "count", col: 3), to: (row: "out", col: 3)),
  ),
  cell-width: "fit",
)

#let r = make-renderer(
  tbl,
  draw-array,
  sticky: true,
  theme: (op: (search-stroke: (paint: teal, thickness: 3pt))),
)
#let r = apply-ops(
  r,
  styles.search(cell-key("in", 2))
    + styles.attention(cell-key("count", 3))
    + style-edge("read", stroke: role("search-stroke"))
    + style-edge("place", hide: true)
    + annotate(cell-key("count", 3), [+1])
    + commit(alt: "Counting the 3."),
)
#let r = apply-ops(
  r,
  styles.success(cell-key("out", 3))
    + style-edge("place", stroke: role("success-stroke"), hide: false)
    // A ghosted cell keeps its slot, so the row does not reflow.
    + styles.ghost(cell-key("out", 2))
    + set-alt("Placed the 3."),
)

#for f in render(r) {
  context (f.builder)(resolve-theme((:)))
}

#pagebreak()

// Hand-composed: no renderer — but "fit" sizing measures, so this one
// needs a `context`. (`cell-width: auto` would not.)
#context cetz.canvas({
  import cetz.draw: circle, content, line
  draw-array(tbl, blank-snapshot(), name: "a")
  circle(anchor(cell-key("count", 0), canvas: "a"), radius: 0.55, stroke: red + 2pt)
  line(
    anchor(cell-key("in", 3), canvas: "a") + ".north",
    (rel: (0, 0.8)),
    stroke: blue + 2pt,
    mark: (end: ">"),
  )
  content((rel: (0, 0.1)), anchor: "south", text(size: 0.8em, [last read]))
})
