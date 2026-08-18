#import "/src/lib.typ" as starling
#import starling: bst

#let t = bst.new(4, 1, 0, 7, 3, 6, 8)

#starling.stacked(bst.rotate-display(t, bst.resolve(t, "L")))

// Rotation around a non-root parent — verifies `rotate-display` can rotate any
// parent/child pair, not just direct children of the root.
#starling.stacked(bst.rotate-display(t, bst.resolve(t, "RL")))
