// A failed chaining lookup / delete rings a phantom "null" cell hung one past
// the tail of the bucket (the slot the walk fell off the end into) rather than
// the keyless bucket header. Covers a populated bucket, an empty bucket
// (immediate null), delete, and the vertical orientation.
#import "/src/lib.typ" as starling
#import starling: hashmap

#set page(width: auto, height: auto, margin: 10pt)

#let c = hashmap(5, strategy: "chaining", entries: (5, 10, 7, 3, 8))

// Search miss: 15 -> bucket 0 (holds 5, 10); phantom past 10.
#starling.stacked((c.search-display)(15))

#v(1.5em)

// Search miss into an empty bucket: 4 -> bucket 4 (empty); phantom at depth 0.
#starling.last((c.search-display)(4))

#v(1.5em)

// Delete miss: same phantom treatment.
#starling.last((c.delete-display)(15))

#v(1.5em)

// Vertical orientation miss.
#starling.last((c.search-display)(15, orientation: "vertical"))
