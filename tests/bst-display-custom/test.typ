// Visual regression for custom node labels. Keys are ints (so ordering still
// works); the `label` field is a mix of `auto` (which draws the key), strings,
// and arbitrary content. The tree is hand-built with the literal builders so
// each node can carry a different label.

#import "/src/lib.typ" as starling
#import starling: bst

#let t = bst.node(
  4,
  bst.node(2, bst.leaf(1), bst.leaf(3), label: "two"),
  bst.leaf(7, label: [#text(fill: red)[seven]]),
  label: [*four*],
)

#starling.last(bst.display(t))
