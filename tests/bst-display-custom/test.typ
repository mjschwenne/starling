// Visual regression for custom node labels. Keys are int (so ordering
// still works); the `label` field is a mix of `auto` (renders the key),
// strings, and arbitrary content. The tree is hand-built so each node
// can carry a different label.

#import "/src/lib.typ" as starling
#import starling: BST

#let leaf(v, l) = (BST.new)(value: v, label: l, left: none, right: none)
#let t = (BST.new)(
  value: 4,
  label: [*four*],
  left: (BST.new)(
    value: 2,
    label: "two",
    left: leaf(1, auto),
    right: leaf(3, auto),
  ),
  right: leaf(7, [#text(fill: red)[seven]]),
)

#starling.last((t.display)())
