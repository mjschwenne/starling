// Visual regression for the four RBT `*-order-display` traversals. Each
// stacks its whole animation, so the running output caption and the
// traversal gradient are both under regression — and the gradient fill has
// to override the red/black palette fill while the palette's stroke stays.

#import "/src/lib.typ" as starling
#import starling: rbt

#set page(width: auto, height: auto, margin: 1em)

#let t = rbt.new(8, 4, 12, 2, 6, 10)

== In-order
#starling.stacked(rbt.in-order-display(t))

#pagebreak()

== Pre-order
#starling.stacked(rbt.pre-order-display(t))

#pagebreak()

== Post-order
#starling.stacked(rbt.post-order-display(t))

#pagebreak()

== Level-order (with bits)
#starling.stacked(rbt.level-order-display(t, bits: true))
