// Visual regression for AVL `fixup-display`. Hand-built imbalanced
// trees with deliberately-stale heights exercise the fix-up climb in
// isolation, including configurations that can't arise from a single
// insert. `height:` on the literal builders is what expresses "caught
// mid-operation": the spine has not been recomputed yet.

#import "/src/lib.typ" as starling
#import starling: avl

#set page(width: auto, height: auto, margin: 1em)

== LR fix-up at the root
// Pre-insertion shape: root 4 with a left subtree (2) and a fresh leaf
// 3 grafted as 2's right child — the LR configuration. Heights stale.
#let t-lr = avl.node(4, avl.node(2, none, avl.leaf(3), height: 1), none, height: 2)
#starling.stacked(avl.fixup-display(t-lr, "LR", factors: true))

#pagebreak()

== Multi-level climb — LL twice
// Two imbalances on one spine: rotating the inner one restores enough
// of the structure that the outer one *also* becomes balanced after
// its own recompute. This shape can't come from a single insert.
#let t-mm = avl.node(
  5,
  avl.node(3, avl.node(2, avl.leaf(1), none, height: 1), none, height: 2),
  none,
  height: 3,
)
#starling.stacked(avl.fixup-display(t-mm, "LLL", factors: true))
