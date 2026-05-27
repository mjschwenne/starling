// Visual regression for the RBT `insert-display` animation. Each
// `=` heading sets up a fixture chosen to exercise one branch of the
// CLRS fix-up: a clean black-parent insertion (no fix-up), Case 1
// (uncle red, recolor and continue), Case 3 alone (straight-line
// rotate + color swap), and Case 2 → Case 3 (zigzag straighten then
// rotate). The full frame sequence is stacked on each page so any
// regression in caption/coloring/rotation geometry shows up.

#import "/src/lib.typ" as starling
#import starling: RBT

#set page(width: auto, height: auto, margin: 1em)

#let bleaf(v, label: auto) = (RBT.new)(
  value: v,
  label: label,
  red: false,
  left: none,
  right: none,
)
#let rleaf(v, label: auto) = (RBT.new)(
  value: v,
  label: label,
  red: true,
  left: none,
  right: none,
)
#let bnode(v, l, r, label: auto) = (RBT.new)(
  value: v,
  label: label,
  red: false,
  left: l,
  right: r,
)
#let rnode(v, l, r, label: auto) = (RBT.new)(
  value: v,
  label: label,
  red: true,
  left: l,
  right: r,
)

== No fix-up needed — black parent
#let t1 = bnode(4, bleaf(2), bleaf(7))
#starling.stacked((t1.insert-display)(1))

#pagebreak()

== Case 1 (uncle red, recolor)
// Parent of the new node must be red. Red nodes can only appear as
// children of black nodes, so we need a 4-level tree with the
// "red below black below red below black-root" shape. Inserting 1
// under 2R triggers a red-red between 1 and 2 with red uncle 6.
#let t2 = bnode(
  8,
  bnode(4, rleaf(2), rleaf(6)),
  bnode(12, rleaf(10), rleaf(14)),
)
#starling.stacked((t2.insert-display)(1))

#pagebreak()

== Case 3 alone (straight-line: rotate + color swap)
#let t3 = bnode(4, rleaf(2), none)
#starling.stacked((t3.insert-display)(1))

#pagebreak()

== Case 2 + Case 3 (zigzag, then rotate + color swap)
#let t4 = bnode(4, rleaf(2), none)
#starling.stacked((t4.insert-display)(3))
