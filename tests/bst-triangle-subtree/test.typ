// Visual regression for the `shape` node-style key and the `child-anchor`
// edge-style key. The motivating use case: a node drawn as a triangle to stand
// in for a whole subtree, with the incoming edge landing on the triangle's
// apex. Both the triangle and the rectangle shapes appear, so the test covers
// all three plus the named anchor overrides on the incoming edges.

#import "/src/lib.typ" as starling
#import starling: apply-ops, bst, render, set-alt, style-edge, style-node

#let t = bst.insert-many(bst.leaf(5), 2, 8, 1, 3)

#let ops = (
  // Left subtree summarised by a triangle; its incoming edge lands on the apex.
  style-node("L", shape: "triangle", fill: aqua.lighten(60%))
    + style-edge("L", child-anchor: "north")
    // Right child drawn as a rectangle, its edge landing flush on the top.
    + style-node("R", shape: "rectangle", fill: yellow.lighten(60%))
    + style-edge("R", child-anchor: "north")
    // Hide the descendants under the triangle so it visually stands in for the
    // subtree it summarises.
    + style-node("LL", "LR", hide: true)
    + style-edge("LL", "LR", hide: true)
    + set-alt(
      "Root with a triangle left subtree summary and a rectangle right child.",
    )
)

#let frames = render(apply-ops(bst.renderer(t, sticky: true), ops))
#assert.eq(frames.len(), 1)

#starling.last(frames)
