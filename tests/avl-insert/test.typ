// Visual regression for the AVL `insert-display` animation. Each
// section sets up a fixture chosen to exercise one branch of the AVL
// fix-up: a clean insertion (no rotation), then LL / RR / LR / RL.
// Balance-factor tags are on so the imbalance check is visible.

#import "/src/lib.typ" as starling
#import starling: AVL, avl

#set page(width: auto, height: auto, margin: 1em)

#let leaf(v) = (AVL.new)(
  value: v,
  label: auto,
  height: 1,
  left: none,
  right: none,
)
#let node(v, h, l, r) = (AVL.new)(
  value: v,
  label: auto,
  height: h,
  left: l,
  right: r,
)

== No fix-up needed
// Inserting a fresh leaf into a balanced tree with room to grow.
#let t1 = node(4, 2, leaf(2), leaf(6))
#starling.stacked((t1.insert-display)(1, factors: true))

#pagebreak()

== LL — single right rotation
// Left-left chain: inserting 1 under 2 under 3 forces a right
// rotation at the root.
#let t2 = node(3, 2, leaf(2), none)
#starling.stacked((t2.insert-display)(1, factors: true))

#pagebreak()

== RR — single left rotation
#let t3 = node(1, 2, none, leaf(2))
#starling.stacked((t3.insert-display)(3, factors: true))

#pagebreak()

== LR — left-right zigzag
// Insert 2 under 3 under 1: the new node is the right child of the
// left child of the root.
#let t4 = node(3, 2, leaf(1), none)
#starling.stacked((t4.insert-display)(2, factors: true))

#pagebreak()

== RL — right-left zigzag
#let t5 = node(1, 2, none, leaf(3))
#starling.stacked((t5.insert-display)(2, factors: true))
