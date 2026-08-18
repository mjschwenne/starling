// Linear probing: a collision walk to the next free slot.
#import "/src/lib.typ" as starling
#import starling: hashmap

#let l = hashmap.new(7, strategy: "linear", entries: (14, 21, 7))
#starling.stacked(hashmap.insert-display(l, 28))
