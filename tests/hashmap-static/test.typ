// Static display of all three collision strategies, including a
// tombstone (deleted open-addressing slot) and multi-entry chains.
#import "/src/lib.typ" as starling
#import starling: hashmap

#set page(width: auto, height: auto, margin: 10pt)

// Chaining: buckets with 0, 1, and multiple entries.
#let c = hashmap.new(5, strategy: "chaining", entries: (5, 10, 7, 3, 8, 13))
#starling.last(hashmap.display(c))

#v(1.5em)

// Linear probing with a deletion, leaving a tombstone (×).
#let l = hashmap.new(7, strategy: "linear", entries: (14, 21, 7))
#starling.last(hashmap.display(hashmap.delete(l, 21)))

#v(1.5em)

// Quadratic probing.
#let q = hashmap.new(7, strategy: "quadratic", entries: (0, 7, 14, 21))
#starling.last(hashmap.display(q))
