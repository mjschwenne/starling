// Visual regression for the `shape` node-style key and the
// `parent-anchor` / `child-anchor` edge-style keys. Demonstrates the
// motivating use case: a node rendered as a triangle to stand in for a
// subtree, with the incoming edge connecting to the triangle's apex.
//
// The tree is built so that both the triangle and the rectangle nodes
// are present, so the test exercises all three shapes plus the named
// anchor overrides on the incoming edges.

#import "/src/lib.typ" as starling
#import starling: BST, Op, apply-ops, make-renderer

#let t = (BST.new)(value: 5, label: auto, left: none, right: none)
#let t = (t.insert-many)(2, 8, 1, 3)

#let ops = (
  // Left subtree summarised by a triangle; incoming edge lands on the apex.
  (Op.StyleNode.new)(path: "L", style: (shape: "triangle", fill: aqua.lighten(60%))),
  (Op.StyleEdge.new)(path: "L", style: (child-anchor: "north")),
  // Right child rendered as a rectangle; incoming edge lands on the
  // top-center of the rectangle for a flush meeting.
  (Op.StyleNode.new)(path: "R", style: (shape: "rectangle", fill: yellow.lighten(60%))),
  (Op.StyleEdge.new)(path: "R", style: (child-anchor: "north")),
  // Hide the descendants under the triangle so it visually stands in
  // for the subtree it summarises.
  (Op.StyleNode.new)(path: "LL", style: (hide: true)),
  (Op.StyleNode.new)(path: "LR", style: (hide: true)),
  (Op.StyleEdge.new)(path: "LL", style: (hide: true)),
  (Op.StyleEdge.new)(path: "LR", style: (hide: true)),
  (Op.Alt.new)(text: "Root with a triangle left subtree summary and a rectangle right child."),
)

#let r = make-renderer(t, sticky: true)
#let r = apply-ops(r, ops)
#let frames = (r.render)()
#assert.eq(frames.len(), 1)

#starling.last(frames)
