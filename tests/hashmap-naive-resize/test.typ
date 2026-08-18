// Naive resize (`rehash: false`): grow the array but copy every entry to
// its OLD index instead of rehashing. Because the table is now longer,
// `h(k) mod new-cap` points elsewhere, so a later search for a moved key
// probes the wrong slot and (wrongly) misses — the demonstration of why
// a real resize must rehash. Contrast with `hashmap-resize` (the correct
// rehash).
#import "/src/lib.typ" as starling
#import starling: hashmap

#set page(width: auto, height: auto, margin: 10pt)

// 14, 21, 7 all hash to slot 0 (k mod 7) and probe to 0, 1, 2.
#let l = hashmap.new(7, strategy: "linear", entries: (14, 21, 7))

// Buggy resize to 11: copies 14/21/7 into slots 0/1/2 without rehashing.
#starling.stacked(hashmap.resize-display(l, 11, rehash: false))

#v(1.5em)

// The bug: h(7) mod 11 = 7, so searching 7 probes empty slot 7 and misses
// even though 7 is still sitting in slot 2.
#let broken = hashmap.resize(l, 11, rehash: false)
#starling.stacked(hashmap.search-display(broken, 7))

#pagebreak()

// Chaining keeps entries in their old buckets rather than rehashing them.
#let c = hashmap.new(5, strategy: "chaining", entries: (5, 10, 7, 3))
#starling.stacked(hashmap.resize-display(c, 9, rehash: false))
