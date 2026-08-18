// Resize / rehash: grow the array and replay every live entry through
// the new capacity (the linear case even re-collides during rehash).
#import "/src/lib.typ" as starling
#import starling: hashmap

#let l = hashmap.new(7, strategy: "linear", entries: (14, 21, 7, 3))
#starling.stacked(hashmap.resize-display(l, 11))
