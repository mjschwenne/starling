// Visual regression for B24 `search-display`. Three searches:
//   - hit at the root (single comparison)
//   - hit on a deep compartment (multi-level descent + compartment scan)
//   - miss (search ends at a leaf without finding the value)

#import "/src/lib.typ" as starling
#import starling: B24, b24

#set page(width: auto, height: auto, margin: 1em)

#let t = b24(10, 5, 15, 1, 7, 12, 20, 25, 30, 17, 19)

== Hit at the root (15)
#starling.stacked((t.search-display)(15))

#pagebreak()

== Hit on a deep compartment (19)
#starling.stacked((t.search-display)(19))

#pagebreak()

== Miss (8 is not in the tree)
#starling.stacked((t.search-display)(8))
