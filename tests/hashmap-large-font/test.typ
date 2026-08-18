// At large font sizes (e.g. a touying deck) the chaining entry boxes must
// grow to fit their labels (the "fit" sizing scales height as well as width),
// and the head-pointer arrow from a bucket to its first chain entry must stay
// visible — the index label is seated just left of the arrow instead of on top
// of it. Covers both orientations plus wide string labels.
#import "/src/lib.typ" as starling
#import starling: hashmap

#set page(width: auto, height: auto, margin: 12pt)
#set text(size: 24pt)

// Horizontal chaining, numeric labels: several buckets with head arrows.
#let c = hashmap.new(5, strategy: "chaining", entries: (5, 10, 7, 3, 8, 13))
#starling.last(hashmap.display(c))

#v(1.5em)

// Horizontal chaining, wide string labels: entry boxes must fit the text.
#let w = hashmap.new(3, strategy: "chaining")
#let w = hashmap.insert(w, 1, label: "apple")
#let w = hashmap.insert(w, 4, label: "grape")
#let w = hashmap.insert(w, 7, label: "fig")
#starling.last(hashmap.display(w))

#v(1.5em)

// Vertical (memory-diagram) chaining at the same large font.
#starling.last(hashmap.display(w, orientation: "vertical"))
