// Verify theming: a document-wide `set-theme` should recolor the output of
// every `*-display`, and a per-call `theme:` override should win over the
// state for that one call.

#import "/src/lib.typ" as starling
#import starling: bst, set-theme

#let t = bst.new(4, 1, 0, 7, 3, 6, 8)

#set-theme((
  render: (
    node-fill: rgb("#f2f2f7"),
    edge-stroke: rgb("#555555"),
    note-fill: rgb("#9e2a5e"),
  ),
  op: (
    search-stroke: (paint: teal, thickness: 2.5pt),
    attention-stroke: (paint: purple, thickness: 2.5pt),
    success-stroke: (paint: olive, thickness: 2.5pt),
    settled-stroke: (paint: olive, thickness: 3.5pt),
    success-fill: olive.lighten(70%),
    danger-stroke: (paint: maroon, thickness: 2.5pt, dash: "dashed"),
    traversal-palette: color.map.viridis,
  ),
))

== Search (state-driven theme)
#starling.stacked(bst.search-display(t, 6))

== Insert (state-driven theme)
#starling.stacked(bst.insert-display(t, 5))

== Delete (one child, state-driven theme)
#starling.stacked(bst.delete-display(t, 1))

== Rotate (state-driven theme)
#starling.stacked(bst.rotate-display(t, bst.resolve(t, "L")))

== In-order traversal (state-driven theme)
#starling.stacked(bst.in-order-display(t))

== Per-call override beats state
#starling.last(bst.search-display(
  t,
  6,
  theme: (op: (search-stroke: (paint: red, thickness: 4pt))),
))
