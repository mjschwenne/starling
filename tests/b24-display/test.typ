// Visual regression for B24 static `display` — exercises 1-, 2-, and
// 3-key compartments at every depth so the variable-width rectangle
// rendering is sanity-checked end-to-end.

#import "/src/lib.typ" as starling
#import starling: B24, b24

#set page(width: auto, height: auto, margin: 1em)

#let leaf(..ks) = (B24.new)(
  keys: ks.pos(),
  labels: ks.pos().map(_ => auto),
  children: (),
)

== Single-key root
#let t1 = b24(42)
#starling.last((t1.display)())

#pagebreak()

== 2-key root, leaf children with mixed widths
#let t2 = (B24.new)(
  keys: (10, 20),
  labels: (auto, auto),
  children: (leaf(3, 7), leaf(15), leaf(25, 30)),
)
#starling.last((t2.display)())

#pagebreak()

== 3-key root, four leaf children including 3-key leaves
#let t3 = (B24.new)(
  keys: (5, 10, 20),
  labels: (auto, auto, auto),
  children: (leaf(1, 3), leaf(7), leaf(15), leaf(25, 28, 30)),
)
#starling.last((t3.display)())

#pagebreak()

== Three-level tree built by repeated insertion
// b24() uses top-down inserts. The sequence below forces a root
// split, so the resulting tree has two levels.
#let t4 = b24(10, 5, 15, 1, 7, 12, 20, 25, 30, 17, 19)
#starling.last((t4.display)())
