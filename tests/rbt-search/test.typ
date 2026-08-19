// Visual regression for the RBT `search-display` animation — the shared
// binary-tree search walk laid over the red-black palette, so the search
// stroke has to stay legible against both a red and a black node. Two
// panels: a hit and a miss, the second with black-height bits on.

#import "/src/lib.typ" as starling
#import starling: rbt

#set page(width: auto, height: auto, margin: 1em)

#let t = rbt.new(8, 4, 12, 2, 6, 10, 14, 1)

== Found — the walk ends on a match
#starling.stacked(rbt.search-display(t, 6))

#pagebreak()

== Not found — the walk runs off the tree
#starling.stacked(rbt.search-display(t, 13, bits: true))
