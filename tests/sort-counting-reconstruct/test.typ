// Counting sort, reconstruct (intro, not stable) variant: histogram, then
// emit each value count[v] times into the output.
#import "/src/lib.typ" as starling
#import starling: sort

#set page(width: auto, height: auto, margin: 10pt)

#starling.stacked(
  (sort(2, 0, 1, 2, 0).counting-sort-display)(variant: "reconstruct"),
)
