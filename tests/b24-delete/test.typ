// Visual regression for B24 `delete-display` — exercises the
// rebalancing branches of both algorithms.

#import "/src/lib.typ" as starling
#import starling: b24

#set page(width: auto, height: auto, margin: 1em)

#let t = b24.node((10, 20), b24.leaf(3, 7), b24.leaf(15), b24.leaf(25, 30))

== Top-down: leaf with ≥ 2 keys (simple remove)
// Delete 7 from [3, 7]: target leaf has 2 keys, no fixup needed.
#starling.stacked(b24.delete-display(t, 7))

#pagebreak()

== Top-down: borrow from left sibling
// Delete 15: target leaf [15] is 1-key; left sibling [3, 7] is
// rich, so borrow.
#starling.stacked(b24.delete-display(t, 15))

#pagebreak()

== Top-down: borrow from right sibling
// Build a fixture where only the right sibling is rich.
#let rb = b24.node(10, b24.leaf(5), b24.leaf(15, 20))
#starling.stacked(b24.delete-display(rb, 5))

#pagebreak()

== Top-down: merge (root collapses)
// Delete from a tree where both siblings are 1-key — forces a
// merge that consumes the root's only key.
#let mf = b24.node(10, b24.leaf(5), b24.leaf(15))
#starling.stacked(b24.delete-display(mf, 5))

#pagebreak()

== Top-down: delete an internal key (predecessor swap)
// Delete 10 from the root: predecessor (7) swaps in, then 7 is
// removed from the leaf.
#starling.stacked(b24.delete-display(t, 10))

#pagebreak()

== Bottom-up: leaf with ≥ 2 keys
#starling.stacked(b24.delete-display(t, 7, strategy: "bottom-up"))

#pagebreak()

== Bottom-up: borrow propagates underflow
#starling.stacked(b24.delete-display(t, 15, strategy: "bottom-up"))

#pagebreak()

== Bottom-up: internal key (predecessor swap)
#starling.stacked(b24.delete-display(t, 10, strategy: "bottom-up"))

#pagebreak()

== `search: false` — only the structural work
// The same top-down deletion with the descent dropped: no comparison
// frames, and none of their highlights inherited by what remains.
#starling.stacked(b24.delete-display(t, 10, search: false))
