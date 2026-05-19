// Verify that an ambient `show strong: ...` rule in the user's
// document does NOT bleed into starling's node labels. The labels'
// fill is computed for contrast against their (possibly dark)
// background; a user theme that recolors bold must not silently
// override that decision.

#import "/src/lib.typ" as starling
#import starling: BST

// Hostile show rule: if our fix regresses, every bold thing — including
// node labels rendered as strong — turns blue, and the white-on-dark
// labels in the traversal go invisible.
#show strong: set text(fill: blue)

#let t = (BST.new)(value: 4, label: auto, left: none, right: none)
#let t = (t.insert-many)(1, 0, 7, 3, 6, 8)

== Static tree — labels should be black, not blue
#starling.last((t.display)())

== In-order traversal — labels should stay readable against gradient
#starling.last((t.in-order-display)())
