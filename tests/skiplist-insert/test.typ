// Skip-list insert: search (the new node's column reserved as a ghost so
// the grid stays put), materialize the tower, then splice it in one level
// at a time. Explicit height keeps the reference deterministic.
#import "/src/lib.typ" as starling
#import starling: skiplist

#set page(width: auto, height: auto, margin: 10pt)

#let sl = skiplist(
  (value: 2, height: 1),
  (value: 5, height: 3),
  (value: 8, height: 1),
  (value: 12, height: 2),
  (value: 17, height: 1),
  (value: 20, height: 2),
)

// A tall insert in the middle (splices at levels 0, 1, 2).
#starling.stacked((sl.insert-display)(9, height: 3))
#pagebreak()
// A height-1 insert at the tail (single splice at level 0).
#starling.stacked((sl.insert-display)(23, height: 1))
