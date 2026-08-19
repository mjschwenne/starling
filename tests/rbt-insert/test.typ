// Visual regression for the RBT `insert-display` animation. Each
// `=` heading sets up a fixture chosen to exercise one branch of the
// CLRS fix-up: a clean black-parent insertion (no fix-up), Case 1
// (uncle red, recolor and continue), Case 3 alone (straight-line
// rotate + color swap), and Case 2 → Case 3 (zigzag straighten then
// rotate). The full frame sequence is stacked on each page so any
// regression in caption/coloring/rotation geometry shows up.

#import "/src/lib.typ" as starling
#import starling: rbt

#set page(width: auto, height: auto, margin: 1em)

== No fix-up needed — black parent
#let t1 = rbt.black(4, rbt.black(2), rbt.black(7))
#starling.stacked(rbt.insert-display(t1, 1))

#pagebreak()

== Case 1 (uncle red, recolor)
// Parent of the new node must be red. Red nodes can only appear as
// children of black nodes, so we need a 4-level tree with the
// "red below black below red below black-root" shape. Inserting 1
// under 2R triggers a red-red between 1 and 2 with red uncle 6.
#let t2 = rbt.black(
  8,
  rbt.black(4, rbt.red(2), rbt.red(6)),
  rbt.black(12, rbt.red(10), rbt.red(14)),
)
#starling.stacked(rbt.insert-display(t2, 1))

#pagebreak()

== Case 3 alone (straight-line: rotate + color swap)
#let t3 = rbt.black(4, rbt.red(2), none)
#starling.stacked(rbt.insert-display(t3, 1))

#pagebreak()

== Case 2 + Case 3 (zigzag, then rotate + color swap)
#let t4 = rbt.black(4, rbt.red(2), none)
#starling.stacked(rbt.insert-display(t4, 3))
