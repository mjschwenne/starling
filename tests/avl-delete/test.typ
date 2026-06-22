// Visual regression for AVL `delete-display`. Covers leaf, one-child,
// two-child (predecessor transfer), and a cascading rebalance where
// the climb back to root triggers multiple rotations.

#import "/src/lib.typ" as starling
#import starling: AVL, avl

#set page(width: auto, height: auto, margin: 1em)

== Delete leaf
#let t = avl(5, 3, 7, 2, 4, 6, 8, 1, 9)
#starling.stacked((t.delete-display)(1, factors: true))

#pagebreak()

== Delete one-child node, with search
#let t2 = avl(5, 3, 7, 2, 4, 6, 8, 1)
// 2 has only a left child (1) after deletion-eligible inserts.
#starling.stacked((t2.delete-display)(2, search: true, factors: true))

#pagebreak()

== Delete two-child node (predecessor transfer)
#let t3 = avl(5, 3, 7, 2, 4, 6, 8, 1, 9)
#starling.stacked((t3.delete-display)(3, factors: true))

#pagebreak()

== Climb up after leaf delete (no rotation)
// Deleting a leaf from a complete tree just recomputes heights on the
// way up — the visual covers the recompute-only climb path.
#let big = avl(8, 4, 12, 2, 6, 10, 14, 1, 3, 5, 7, 11, 13, 15)
#starling.stacked((big.delete-display)(15, factors: true))

#pagebreak()

== Delete triggers a rotation on the climb
// Hand-built Fibonacci-shape AVL tree of height 4: the left subtree
// is one taller than the right, so removing the right leaf shrinks
// the right side enough to trigger an LL rotation at the root.
#let leaf-(v) = (AVL.new)(
  value: v,
  label: auto,
  height: 1,
  left: none,
  right: none,
)
#let node-(v, h, l, r) = (AVL.new)(
  value: v,
  label: auto,
  height: h,
  left: l,
  right: r,
)
#let fib = node-(
  8,
  4,
  node-(4, 3, node-(2, 2, leaf-(1), none), leaf-(5)),
  node-(10, 2, none, leaf-(11)),
)
#starling.stacked((fib.delete-display)(11, factors: true))
