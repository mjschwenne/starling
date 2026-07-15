// Search: a hit that walks *through* a tombstone (proving a tombstone
// is not treated as an empty terminator), and a miss.
#import "/src/lib.typ" as starling
#import starling: hashmap

#set page(width: auto, height: auto, margin: 10pt)

#let l = hashmap(7, strategy: "linear", entries: (14, 21, 7))
#let l1 = (l.delete)(21) // tombstone at slot 1

// Hit — must probe past the tombstone at slot 1 to find 7 at slot 2.
#starling.stacked((l1.search-display)(7))

#v(1.5em)

// Miss — probe runs off into an empty slot.
#starling.stacked((l1.search-display)(99))
