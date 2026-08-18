// Quadratic probing: the (h + i^2) mod m probe sequence.
#import "/src/lib.typ" as starling
#import starling: hashmap

#let q = hashmap.new(7, strategy: "quadratic", entries: (0, 7, 14))
#starling.stacked(hashmap.insert-display(q, 21))
