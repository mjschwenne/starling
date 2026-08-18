// Verify the cetz integration: `draw-tree` emits a tree *without* wrapping it
// in a `cetz.canvas`, and the `anchor(<path>)` names line up with the elements
// it draws, so user-drawn annotations can target a node by its path.

#import "@preview/cetz:0.5.2"
#import "/src/lib.typ" as starling
#import starling: anchor, blank-snapshot, bst, draw-tree

#let t = bst.new(4, 1, 7, 3, 6, 8)

#cetz.canvas({
  // Empty snapshot — no per-node style overrides.
  draw-tree(t, blank-snapshot())
  // Import selectively: cetz.draw has an `anchor` of its own, and a glob
  // import would shadow starling's.
  import cetz.draw: circle
  // Call out the leaf at path "LR" (value 3) with a red ring.
  circle(anchor("LR"), radius: 0.85, stroke: red + 2pt)
  // And the root (path "") with a blue ring.
  circle(anchor(""), radius: 0.85, stroke: blue + 2pt)
})
