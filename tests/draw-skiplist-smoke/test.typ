// Smoke test for the skip-list draw backend (`src/draw/skiplist.typ`) on
// the new core.
//
// Page 1  the op-stream path — theme-ref styling (which must follow the
//         per-renderer theme override), a forward pointer styled by
//         `forward-key`, and a ghosted lane box.
// Page 2  the hand-composed path — `draw-skiplist(.., name: "s")` with
//         callouts anchored at `anchor(box-key(col, level), canvas: "s")`
//         and at a data box, including a compass sub-anchor.

#import "@preview/cetz:0.5.2"
#import "/src/core/draw-util.typ": anchor
#import "/src/core/frame.typ": make-renderer, render
#import "/src/core/ops.typ": apply-ops, commit, set-alt, style-edge
#import "/src/core/snapshot.typ": blank-snapshot
#import "/src/core/style.typ": role
#import "/src/core/theme.typ": resolve-theme
#import "/src/draw/skiplist.typ": box-key, data-key, draw-skiplist, forward-key
#import "/src/styles.typ" as styles

// A positioned table — the shape `ds/skiplist.typ`'s `positioned` produces.
#let dat(k, h, ..rest) = (
  kind: "data",
  height: h,
  key: k,
  label: str(k),
  state: "live",
  ..rest.named(),
)
#let tbl = (
  cols: (
    (kind: "header", height: 3, key: none, label: none, state: "live"),
    dat(3, 1),
    dat(9, 3),
    // Spliced out of its top lane: the pointers run over the grayed box.
    dat(17, 2, link-height: 1),
    dat(26, 1),
    (kind: "nil", height: 3, key: none, label: "NIL", state: "live"),
  ),
  cell-width: "fit",
)

#let r = make-renderer(
  tbl,
  draw-skiplist,
  sticky: true,
  theme: (op: (search-stroke: (paint: teal, thickness: 3pt))),
)
#let r = apply-ops(
  r,
  // The top-left descent: the header's top lane, then across to 9.
  styles.search(box-key(0, 2))
    + style-edge(forward-key(0, 2), stroke: role("search-stroke"))
    + styles.attention(box-key(2, 2))
    + commit(alt: "Descending from the header's top lane to 9."),
)
#let r = apply-ops(
  r,
  styles.success(data-key(2))
    // A ghosted lane box keeps its slot, so the grid does not reflow.
    + styles.ghost(box-key(4, 0))
    + set-alt("Found 9."),
)

#for f in render(r) {
  context (f.builder)(resolve-theme((:)))
}

#pagebreak()

// Hand-composed: no renderer — but "fit" sizing measures, so this one
// needs a `context`. (`cell-width: auto` would not.)
#context cetz.canvas({
  import cetz.draw: circle, content, line
  draw-skiplist(tbl, blank-snapshot(), name: "s")
  circle(anchor(box-key(3, 1), canvas: "s"), radius: 0.5, stroke: red + 2pt)
  line(
    anchor(data-key(4), canvas: "s") + ".south",
    (rel: (0, -0.8)),
    stroke: blue + 2pt,
    mark: (end: ">"),
  )
  content((rel: (0, -0.1)), anchor: "north", text(size: 0.8em, [tail]))
})
