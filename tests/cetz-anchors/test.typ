// Verify Phase 2 cetz integration: draw-tree emits a tree without
// wrapping it in cetz.canvas, and path-anchor names line up with the
// anchors cetz-tree creates so user-drawn annotations can target nodes
// by path.

#import "@preview/cetz:0.5.2"
#import "/src/lib.typ" as starling

#let t = (starling.BST.new)(value: 4, left: none, right: none)
#let t = (t.insert-many)(1, 7, 3, 6, 8)

// Empty snapshot — no per-node style overrides.
#let snapshot = starling.blank-snapshot()

#cetz.canvas({
  starling.draw-tree(t, snapshot)
  import cetz.draw: *
  // Call out the leaf at path "LR" (value 3) with a red ring.
  circle(starling.path-anchor("LR"), radius: 0.85, stroke: red + 2pt)
  // And the root (path "") with a blue ring.
  circle(starling.path-anchor(""), radius: 0.85, stroke: blue + 2pt)
})
