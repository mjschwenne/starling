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
#let c = hashmap(5, strategy: "chaining", entries: (5, 10, 7, 3, 8, 13))
#starling.last((c.display)())

#v(1.5em)

// Horizontal chaining, wide string labels: entry boxes must fit the text.
#let w = hashmap(3, strategy: "chaining")
#let w = (w.insert)(1, label: "apple")
#let w = (w.insert)(4, label: "grape")
#let w = (w.insert)(7, label: "fig")
#starling.last((w.display)())

#v(1.5em)

// Vertical (memory-diagram) chaining at the same large font.
#starling.last((w.display)(orientation: "vertical"))
