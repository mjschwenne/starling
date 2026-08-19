// Visual regression for B24 static `display` — exercises 1-, 2-, and
// 3-key compartments at every depth so the variable-width rectangle
// rendering is sanity-checked end-to-end.

#import "/src/lib.typ" as starling
#import starling: b24

#set page(width: auto, height: auto, margin: 1em)

== Single-key root
#let t1 = b24.new(42)
#starling.last(b24.display(t1))

#pagebreak()

== 2-key root, leaf children with mixed widths
#let t2 = b24.node((10, 20), b24.leaf(3, 7), b24.leaf(15), b24.leaf(25, 30))
#starling.last(b24.display(t2))

#pagebreak()

== 3-key root, four leaf children including 3-key leaves
#let t3 = b24.node(
  (5, 10, 20),
  b24.leaf(1, 3),
  b24.leaf(7),
  b24.leaf(15),
  b24.leaf(25, 28, 30),
)
#starling.last(b24.display(t3))

#pagebreak()

== Three-level tree built by repeated insertion
// `b24.new` uses top-down inserts. The sequence below forces a root
// split, so the resulting tree has two levels.
#let t4 = b24.new(10, 5, 15, 1, 7, 12, 20, 25, 30, 17, 19)
#starling.last(b24.display(t4))
