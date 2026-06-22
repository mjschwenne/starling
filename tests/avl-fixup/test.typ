// Visual regression for AVL `fixup-display`. Hand-built imbalanced
// trees with deliberately-incorrect heights exercise the fix-up climb
// in isolation, including configurations that can't arise from a
// single insert.

#import "/src/lib.typ" as starling
#import starling: AVL

#set page(width: auto, height: auto, margin: 1em)

#let leaf(v, h: 1) = (AVL.new)(
  value: v,
  label: auto,
  height: h,
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

== LR fix-up at the root
// Pre-insertion shape: root 4 with a left subtree (2) and a fresh leaf
// 3 grafted as 2's right child — the LR configuration. Heights stale.
#let t-lr = node(4, 2, node(2, 1, none, leaf(3)), none)
#starling.stacked((t-lr.fixup-display)("LR", factors: true))

#pagebreak()

== Multi-level climb — LL twice
// Two imbalances on one spine: rotating the inner one restores enough
// of the structure that the outer one *also* becomes balanced after
// its own recompute. This shape can't come from a single insert.
#let t-mm = node(
  5,
  3,
  node(3, 2, node(2, 1, leaf(1), none), none),
  none,
)
#starling.stacked((t-mm.fixup-display)("LLL", factors: true))
