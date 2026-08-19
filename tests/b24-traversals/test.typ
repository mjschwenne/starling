// Visual regression for B24 traversal animations. Each traversal
// fans the operation theme's palette across the per-compartment
// visit order; the final frame carries the full color signature.

#import "/src/lib.typ" as starling
#import starling: b24

#set page(width: auto, height: auto, margin: 1em)

// 3-key root with mixed-width leaf children — exercises every
// compartment-arity at depth >= 1.
#let t = b24.node(
  (10, 20, 30),
  b24.leaf(3, 7),
  b24.leaf(15),
  b24.leaf(25),
  b24.leaf(35, 40),
)

== in-order
#starling.last(b24.in-order-display(t))

#pagebreak()

== pre-order
#starling.last(b24.pre-order-display(t))

#pagebreak()

== post-order
#starling.last(b24.post-order-display(t))

#pagebreak()

== level-order
#starling.last(b24.level-order-display(t))
