#import "/src/lib.typ" as starling
#import starling: RBT

#set page(width: auto, height: auto, margin: 1em)

// Build a small RB tree by sequential inserts. The shape and coloring
// fall out of the RB rebalancing rules — same fixture as `rbt-display`
// so the bit annotations land on a known palette of red/black nodes.
#let t = (RBT.new)(
  value: 4,
  label: auto,
  red: false,
  left: none,
  right: none,
)
#let t = (t.insert-many)(1, 0, 7, 3, 6, 8, 9, 2, 5)

// 1. Static display with bits — every node carries its black-height bit
// at the NE corner (0 for red, 1 for black).
#starling.last((t.display)(bits: true))

#pagebreak()

// 2. Insertion animation with bits — bits update frame-to-frame as
// recolor / rotate cases fire, so the bit on each node always matches
// what's actually rendered.
#starling.stacked((t.insert-display)(11, bits: true))

#pagebreak()

// 3. Deletion animation with bits — covers the case where colors
// change across `_color-preserve` intermediate frames too.
#starling.stacked((t.delete-display)(7, bits: true))
