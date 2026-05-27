#import "/src/lib.typ" as starling
#import starling: RBT, set-rbt-theme

#set page(width: auto, height: auto, margin: 1em)

// Build a small RB tree by sequential inserts. The shape and coloring
// fall out of the RB rebalancing rules — this fixture exists to give
// the visual regression something interesting to compare against.
#let t = (starling.RBT.new)(
  value: 4,
  label: auto,
  red: false,
  left: none,
  right: none,
)
#let t = (t.insert-many)(1, 0, 7, 3, 6, 8, 9, 2, 5)

// 1. Default theme: classic red / black palette, white text.
#starling.last((t.display)())

#pagebreak()

// 2. Per-call theme override: pastel palette with darker text.
#starling.last((t.display)(theme: (
  red-fill: rgb("#fca5a5"),
  red-stroke: rgb("#dc2626"),
  red-text-fill: rgb("#7f1d1d"),
  black-fill: rgb("#9ca3af"),
  black-stroke: rgb("#1f2937"),
  black-text-fill: rgb("#111827"),
)))

#pagebreak()

// 3. State-based theme: set-rbt-theme overrides propagate to subsequent
// renders without a per-call argument.
#set-rbt-theme((
  red-fill: rgb("#f59e0b"),
  red-stroke: rgb("#92400e"),
  red-text-fill: white,
  black-fill: rgb("#1e3a8a"),
  black-stroke: rgb("#1e40af"),
  black-text-fill: white,
))
#starling.last((t.display)())
