// Double hashing: the probe step size comes from a second hash, so a
// collision jumps by h2(key) rather than by 1. The hash box shows both
// h1 (the slot) and h2 (the step).
#import "/src/lib.typ" as starling
#import starling: hashmap

#let d = hashmap(7, strategy: "double", entries: (14, 21, 7))
#starling.stacked((d.insert-display)(28))
