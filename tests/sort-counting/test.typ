// Counting sort, prefix-sum (stable) variant: histogram -> cumulative
// prefix sums -> right-to-left placement into the output row.
#import "/src/lib.typ" as starling
#import starling: sort

#set page(width: auto, height: auto, margin: 10pt)

#starling.stacked((sort(1, 0, 2, 1, 3, 0).counting-sort-display)())
