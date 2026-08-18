// Verify that an ambient `show strong: ...` rule in the user's document does
// NOT bleed into starling's node labels. Their fill is computed for contrast
// against a possibly-dark background; a user theme that recolors bold must not
// silently override that decision.

#import "/src/lib.typ" as starling
#import starling: bst

// Hostile show rule: if the fix regresses, every bold thing — including node
// labels rendered as strong — turns blue, and the white-on-dark labels in the
// traversal go invisible.
#show strong: set text(fill: blue)

#let t = bst.new(4, 1, 0, 7, 3, 6, 8)

== Static tree — labels should be black, not blue
#starling.last(bst.display(t))

== In-order traversal — labels should stay readable against gradient
#starling.last(bst.in-order-display(t))
