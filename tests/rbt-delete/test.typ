// Visual regression for the RBT `delete-display` animation. Each
// `=` heading sets up a fixture exercising one branch of the CLRS
// delete fix-up: a red-leaf delete (no fix-up), Case 4 (far nephew
// red, terminal), Case 3 → Case 4 (near nephew red, zigzag), Case 2
// (recolor, propagates), Case 1 (sibling red, reduces), and a two-
// children delete with predecessor transfer.

#import "/src/lib.typ" as starling
#import starling: rbt

#set page(width: auto, height: auto, margin: 1em)

== Delete red leaf — no fix-up needed
#let t1 = rbt.black(4, rbt.red(2), rbt.black(7))
#starling.stacked(rbt.delete-display(t1, 2))

#pagebreak()

== Case 4 directly — far nephew red
#let t2 = rbt.black(4, rbt.black(2), rbt.black(7, none, rbt.red(9)))
#starling.stacked(rbt.delete-display(t2, 2))

#pagebreak()

== Case 3 → Case 4 — near nephew red (zigzag)
#let t3 = rbt.black(4, rbt.black(2), rbt.black(7, rbt.red(5), none))
#starling.stacked(rbt.delete-display(t3, 2))

#pagebreak()

== Case 2 — recolor sibling, propagates up
#let t4 = rbt.black(
  8,
  rbt.black(4, rbt.black(2), rbt.black(6)),
  rbt.black(12, rbt.black(10), rbt.black(14)),
)
#starling.stacked(rbt.delete-display(t4, 2))

#pagebreak()

== Case 1 — sibling red, then resolves
#let t5 = rbt.black(4, rbt.black(2), rbt.red(7, rbt.black(5), rbt.black(9)))
#starling.stacked(rbt.delete-display(t5, 2))

#pagebreak()

== Two-children delete — predecessor transfer
#let t6 = rbt.black(5, rbt.red(3), rbt.red(8))
#starling.stacked(rbt.delete-display(t6, 5))
