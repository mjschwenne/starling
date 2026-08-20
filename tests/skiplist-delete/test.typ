// Skip-list delete: search, then unlink top-down (each level's predecessor
// bypasses the target), leaving the node detached in place. Covers a tall
// node (5, unlinks at 3 levels) and a miss (99).
#import "/src/lib.typ" as starling
#import starling: skiplist

#set page(width: auto, height: auto, margin: 10pt)

#let sl = skiplist.new(
  (value: 2, height: 1),
  (value: 5, height: 3),
  (value: 8, height: 1),
  (value: 12, height: 2),
  (value: 17, height: 1),
  (value: 20, height: 2),
)

#starling.stacked(skiplist.delete-display(sl, 5))
#pagebreak()
#starling.stacked(skiplist.delete-display(sl, 99))
