// Delete: chaining unlinks a middle entry; open addressing writes a
// tombstone (×) so later probes still pass through the slot.
#import "/src/lib.typ" as starling
#import starling: hashmap

#set page(width: auto, height: auto, margin: 10pt)

// Chaining: remove the middle of a three-entry chain.
#let c = hashmap.new(5, strategy: "chaining", entries: (5, 10, 15, 7))
#starling.stacked(hashmap.delete-display(c, 10))

#v(1.5em)

// Linear probing: deleting the collided key leaves a tombstone.
#let l = hashmap.new(7, strategy: "linear", entries: (14, 21, 7))
#starling.stacked(hashmap.delete-display(l, 21))
