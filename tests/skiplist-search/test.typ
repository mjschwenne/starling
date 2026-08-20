// Skip-list search: the top-left descent — move right while the next
// key is below the target, drop a level when it would overshoot. Covers a
// hit (17) and a miss (10).
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

#starling.stacked(skiplist.search-display(sl, 17))
#pagebreak()
#starling.stacked(skiplist.search-display(sl, 10))
