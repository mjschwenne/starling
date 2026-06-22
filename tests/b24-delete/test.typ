// Visual regression for B24 `delete-display` — exercises the
// rebalancing branches of both algorithms.

#import "/src/lib.typ" as starling
#import starling: B24, b24

#set page(width: auto, height: auto, margin: 1em)

#let leaf(..ks) = (B24.new)(
  keys: ks.pos(),
  labels: ks.pos().map(_ => auto),
  children: (),
)

#let t = (B24.new)(
  keys: (10, 20),
  labels: (auto, auto),
  children: (leaf(3, 7), leaf(15), leaf(25, 30)),
)

== Top-down: leaf with ≥ 2 keys (simple remove)
// Delete 7 from [3, 7]: target leaf has 2 keys, no fixup needed.
#starling.stacked((t.delete-display)(7))

#pagebreak()

== Top-down: borrow from left sibling
// Delete 15: target leaf [15] is 1-key; left sibling [3, 7] is
// rich, so borrow.
#starling.stacked((t.delete-display)(15))

#pagebreak()

== Top-down: borrow from right sibling
// Build a fixture where only the right sibling is rich.
#let rb = (B24.new)(
  keys: (10,),
  labels: (auto,),
  children: (leaf(5), leaf(15, 20)),
)
#starling.stacked((rb.delete-display)(5))

#pagebreak()

== Top-down: merge (root collapses)
// Delete from a tree where both siblings are 1-key — forces a
// merge that consumes the root's only key.
#let mf = (B24.new)(
  keys: (10,),
  labels: (auto,),
  children: (leaf(5), leaf(15)),
)
#starling.stacked((mf.delete-display)(5))

#pagebreak()

== Top-down: delete an internal key (predecessor swap)
// Delete 10 from the root: predecessor (7) swaps in, then 7 is
// removed from the leaf.
#starling.stacked((t.delete-display)(10))

#pagebreak()

== Bottom-up: leaf with ≥ 2 keys
#starling.stacked((t.delete-display)(7, strategy: "bottom-up"))

#pagebreak()

== Bottom-up: borrow propagates underflow
#starling.stacked((t.delete-display)(15, strategy: "bottom-up"))

#pagebreak()

== Bottom-up: internal key (predecessor swap)
#starling.stacked((t.delete-display)(10, strategy: "bottom-up"))
