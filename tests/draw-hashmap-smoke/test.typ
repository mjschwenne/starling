// Smoke test for the hash-map draw backend (`src/draw/hashmap.typ`) on the
// new core.
//
// Page 1  the op-stream path — theme-ref styling (which must follow the
//         per-renderer theme override), a ghosted cell, a chain link
//         styled by `entry-key`, and a note.
// Page 2  the hand-composed path — `draw-hashmap(.., name: "m")` with
//         callouts anchored at `anchor(cell-key(i), canvas: "m")` and at a
//         chain entry, including a compass sub-anchor.

#import "@preview/cetz:0.5.2"
#import "/src/core/draw-util.typ": anchor
#import "/src/core/frame.typ": make-renderer, render
#import "/src/core/ops.typ": annotate, apply-ops, commit, set-alt, style-edge
#import "/src/core/snapshot.typ": blank-snapshot
#import "/src/core/style.typ": role
#import "/src/core/theme.typ": resolve-theme
#import "/src/draw/hashmap.typ": cell-key, draw-hashmap, entry-key
#import "/src/styles.typ" as styles

// A positioned table — the shape `ds/hashmap.typ`'s `positioned` produces.
#let e(k) = (key: k, label: str(k))
#let tbl = (
  capacity: 5,
  orientation: "horizontal",
  strategy: "chaining",
  cells: ((e(10), e(15)), (), (e(7),), (), (e(9), e(14))),
  hash-box: (key: "15", expr: "15 mod 5", index: 0),
  cell-width: "fit",
)

#let r = make-renderer(
  tbl,
  draw-hashmap,
  sticky: true,
  theme: (op: (search-stroke: (paint: teal, thickness: 3pt))),
)
#let r = apply-ops(
  r,
  // The walk: the bucket, then each entry compared, then the hit.
  styles.search(cell-key(0))
    + annotate(cell-key(0), [h = 0])
    + commit(alt: "Hashed 15 to bucket 0."),
)
#let r = apply-ops(
  r,
  styles.search(entry-key(0, 0))
    + styles.success(entry-key(0, 1))
    + style-edge(entry-key(0, 1), stroke: role("success-stroke"))
    // A ghosted bucket keeps its slot, so the array does not reflow.
    + styles.ghost(cell-key(3))
    + set-alt("Found 15 at depth 1."),
)

#for f in render(r) {
  context (f.builder)(resolve-theme((:)))
}

#pagebreak()

// Hand-composed: no renderer — but "fit" sizing measures, so this one
// needs a `context`. (`cell-width: auto` would not.)
#context cetz.canvas({
  import cetz.draw: circle, content, line
  draw-hashmap(tbl, blank-snapshot(), name: "m")
  circle(anchor(entry-key(4, 1), canvas: "m"), radius: 0.55, stroke: red + 2pt)
  line(
    anchor(cell-key(2), canvas: "m") + ".south",
    (rel: (0, -0.9)),
    stroke: blue + 2pt,
    mark: (end: ">"),
  )
  content((rel: (0, -0.1)), anchor: "north", text(size: 0.8em, [bucket 2]))
})
