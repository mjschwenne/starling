// Visual regression for the RBT `delete-display` animation. Each
// `=` heading sets up a fixture exercising one branch of the CLRS
// delete fix-up: a red-leaf delete (no fix-up), Case 4 (far nephew
// red, terminal), Case 3 → Case 4 (near nephew red, zigzag), Case 2
// (recolor, propagates), Case 1 (sibling red, reduces), and a two-
// children delete with successor transfer.

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

== Delete red leaf — no fix-up needed
#let t1 = bnode(4, rleaf(2), bleaf(7))
#starling.stacked((t1.delete-display)(2))

#pagebreak()

== Case 4 directly — far nephew red
#let t2 = bnode(4, bleaf(2), bnode(7, none, rleaf(9)))
#starling.stacked((t2.delete-display)(2))

#pagebreak()

== Case 3 → Case 4 — near nephew red (zigzag)
#let t3 = bnode(4, bleaf(2), bnode(7, rleaf(5), none))
#starling.stacked((t3.delete-display)(2))

#pagebreak()

== Case 2 — recolor sibling, propagates up
#let t4 = bnode(
  8,
  bnode(4, bleaf(2), bleaf(6)),
  bnode(12, bleaf(10), bleaf(14)),
)
#starling.stacked((t4.delete-display)(2))

#pagebreak()

== Case 1 — sibling red, then resolves
#let t5 = bnode(4, bleaf(2), rnode(7, bleaf(5), bleaf(9)))
#starling.stacked((t5.delete-display)(2))

#pagebreak()

== Two-children delete — successor transfer
#let t6 = bnode(5, rleaf(3), rleaf(8))
#starling.stacked((t6.delete-display)(5))
