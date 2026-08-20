// Counting sort, buckets (chaining-hash-table) variant: copy each element
// into the chain of bucket = its value, then read the buckets in order into
// the output. Space-inefficient but direct — the count array is drawn as a
// chaining hash table (identity hash), chains hanging down from each header.
// Covers plain integers plus a labelled enumeration (labels ride the chains).
#import "/src/lib.typ" as starling
#import starling: sort

#set page(width: auto, height: auto, margin: 10pt)

#starling.stacked(sort.counting-display(sort.new(3, 1, 4, 1, 0), variant: "buckets"))

// Enumeration: weekday labels distributed by ordinal, gathered in order.
#starling.stacked(sort.counting-display(
  sort.new(
    (value: 2, label: [Tue]),
    (value: 0, label: [Sun]),
    (value: 2, label: [Tue]),
    (value: 1, label: [Mon]),
  ),
  variant: "buckets",
))
