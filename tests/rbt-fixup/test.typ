// Visual regression for the RBT `fixup-display` animation. Each `=`
// heading sets up a hand-built tree with a single red-red violation
// somewhere in the middle (a configuration that can't arise from a
// single `insert` call) and walks the fix-up to completion. Cases:
// straight Case 3, zigzag Case 2 → Case 3, single Case 1, and a
// multi-level Case 1 chain that ends in `blacken-root`.

#import "/src/lib.typ" as starling
#import starling: rbt

#set page(width: auto, height: auto, margin: 1em)

== Case 3 alone (straight-line: rotate + color swap)
// Mid-tree red-red between R(5) and R(3); uncle (sibling of R(5)) is
// nil/black. Single rotate around the black grandparent.
#let t1 = rbt.black(
  20,
  rbt.black(10, rbt.red(5, rbt.red(3), none), none),
  rbt.black(30),
)
#starling.stacked(rbt.fixup-display(t1, "LLL"))

#pagebreak()

== Case 2 + Case 3 (zigzag, then rotate + color swap)
// Mid-tree red-red between R(5) and R(7); zigzag relative to gp
// B(10). Case 2 straightens, then Case 3 rotates and swaps colors.
#let t2 = rbt.black(
  20,
  rbt.black(10, rbt.red(5, none, rbt.red(7)), none),
  rbt.black(30),
)
#starling.stacked(rbt.fixup-display(t2, "LLR"))

#pagebreak()

== Case 1 alone (recolor, no propagation)
// Mid-tree red-red between R(5) and R(3); uncle R(15) is red, so
// Case 1 recolors parent + uncle to black and grandparent to red.
// Grandparent's parent (the root) is already black, so the fix-up
// terminates after one step.
#let t3 = rbt.black(
  20,
  rbt.black(10, rbt.red(5, rbt.red(3), none), rbt.red(15)),
  rbt.black(30),
)
#starling.stacked(rbt.fixup-display(t3, "LLL"))

#pagebreak()

== Case 1 propagation ending in blacken-root
// The case the user wants to teach: a red-red in the middle that
// can't come from a single insertion. Each Case 1 recolor pushes the
// violation up one level, and the final step has to blacken the
// root. Three fix-up iterations: two recolors plus blacken-root.
#let t4 = rbt.black(
  50,
  rbt.red(
    20,
    rbt.black(10, rbt.red(5, rbt.red(3), rbt.red(7)), rbt.red(15)),
    rbt.black(30),
  ),
  rbt.red(70),
)
#starling.stacked(rbt.fixup-display(t4, "LLLL"))
