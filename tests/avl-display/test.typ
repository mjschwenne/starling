#import "/src/lib.typ" as starling
#import starling: AVL, avl

#set page(width: auto, height: auto, margin: 1em)

// A balanced AVL tree of inserts 1..9, which exercises a mix of left
// and right rotations as it builds.
#let t = avl(5, 3, 7, 2, 4, 6, 8, 1, 9)

// 1. Default display — no per-node tags.
#starling.last((t.display)())

#pagebreak()

// 2. Display with balance-factor tags. Tags read 0 / +1 / -1 since
// the tree is balanced.
#starling.last((t.display)(factors: true))
