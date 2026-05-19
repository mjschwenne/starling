// Verify theming: a state-set BST and render theme should produce
// recolored output for every `*-display` method, and a per-call
// `theme:` override should win over state for that one call.

#import "/src/lib.typ" as starling
#import starling: BST, set-bst-theme, set-render-theme

#let t = (BST.new)(value: 4, label: auto, left: none, right: none)
#let t = (t.insert-many)(1, 0, 7, 3, 6, 8)

#set-render-theme((
  node-fill: rgb("#f2f2f7"),
  edge-stroke: rgb("#555555"),
  note-fill: rgb("#9e2a5e"),
))

#set-bst-theme((
  search-stroke: (paint: teal, thickness: 2.5pt),
  pivot-stroke: (paint: purple, thickness: 2.5pt),
  success-stroke: (paint: olive, thickness: 2.5pt),
  settled-stroke: (paint: olive, thickness: 3.5pt),
  success-fill: olive.lighten(70%),
  danger-stroke: (paint: maroon, thickness: 2.5pt, dash: "dashed"),
  traversal-palette: color.map.viridis,
))

== Search (state-driven theme)
#starling.stacked((t.search-display)(6))

== Insert (state-driven theme)
#starling.stacked((t.insert-display)(5))

== Delete (one child, state-driven theme)
#starling.stacked((t.delete-display)(1))

== Rotate (state-driven theme)
#starling.stacked((t.rotate-display)(1))

== In-order traversal (state-driven theme)
#starling.stacked((t.in-order-display)())

== Per-call override beats state
#starling.last((t.search-display)(
  6,
  theme: (search-stroke: (paint: red, thickness: 4pt)),
))
