// Visual regression for B24 traversal animations. Each traversal
// fans the operation-theme's palette across the per-compartment
// visit order; the final frame carries the full color signature.

#import "/src/lib.typ" as starling
#import starling: B24, b24

#set page(width: auto, height: auto, margin: 1em)

#let leaf(..ks) = (B24.new)(
  keys: ks.pos(),
  labels: ks.pos().map(_ => auto),
  children: (),
)

// 3-key root with mixed-width leaf children — exercises every
// compartment-arity at depth ≥ 1.
#let t = (B24.new)(
  keys: (10, 20, 30),
  labels: (auto, auto, auto),
  children: (leaf(3, 7), leaf(15), leaf(25), leaf(35, 40)),
)

== in-order
#starling.last((t.in-order-display)())

#pagebreak()

== pre-order
#starling.last((t.pre-order-display)())

#pagebreak()

== post-order
#starling.last((t.post-order-display)())

#pagebreak()

== level-order
#starling.last((t.level-order-display)())
