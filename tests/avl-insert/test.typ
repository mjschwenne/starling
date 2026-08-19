// Visual regression for the AVL `insert-display` animation. Each
// section sets up a fixture chosen to exercise one branch of the AVL
// fix-up: a clean insertion (no rotation), then LL / RR / LR / RL.
// Balance-factor tags are on so the imbalance check is visible.

#import "/src/lib.typ" as starling
#import starling: avl

#set page(width: auto, height: auto, margin: 1em)

== No fix-up needed
// Inserting a fresh leaf into a balanced tree with room to grow.
#let t1 = avl.node(4, avl.leaf(2), avl.leaf(6))
#starling.stacked(avl.insert-display(t1, 1, factors: true))

#pagebreak()

== LL — single right rotation
// Left-left chain: inserting 1 under 2 under 3 forces a right
// rotation at the root.
#let t2 = avl.node(3, avl.leaf(2), none)
#starling.stacked(avl.insert-display(t2, 1, factors: true))

#pagebreak()

== RR — single left rotation
#let t3 = avl.node(1, none, avl.leaf(2))
#starling.stacked(avl.insert-display(t3, 3, factors: true))

#pagebreak()

== LR — left-right zigzag
// Insert 2 under 3 under 1: the new node is the right child of the
// left child of the root.
#let t4 = avl.node(3, avl.leaf(1), none)
#starling.stacked(avl.insert-display(t4, 2, factors: true))

#pagebreak()

== RL — right-left zigzag
#let t5 = avl.node(1, none, avl.leaf(3))
#starling.stacked(avl.insert-display(t5, 2, factors: true))
