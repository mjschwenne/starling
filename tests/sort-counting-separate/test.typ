// Counting sort, prefix-sum (stable) variant with `separate-counts: true`:
// the raw histogram (count row) and the cumulative prefix sums (cumulative
// row) live in two distinct rows instead of one mutated-in-place row.
#import "/src/lib.typ" as starling
#import starling: sort

#set page(width: auto, height: auto, margin: 10pt)

#starling.stacked(
  (sort(1, 0, 2, 1, 3, 0).counting-sort-display)(separate-counts: true),
)
