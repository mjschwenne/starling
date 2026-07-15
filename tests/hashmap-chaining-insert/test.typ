// Separate chaining: insert appends to the tail of a bucket after
// walking the existing chain.
#import "/src/lib.typ" as starling
#import starling: hashmap

#let c = hashmap(5, strategy: "chaining", entries: (5, 10, 7))
#starling.stacked((c.insert-display)(20))
