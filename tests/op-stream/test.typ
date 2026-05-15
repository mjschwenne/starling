#import "/src/lib.typ" as starling
#import starling: BST, Op, apply-ops, make-renderer

#let t = (BST.new)(value: 4, label: auto, left: none, right: none)
#let t = (t.insert-many)(2, 6, 1, 7)

// Exercise every remaining Op variant:
//   Highlight, Annotate, StyleNode, StyleEdge, Commit, ClearNotes.
// Captions are no longer ops — they're set directly on the renderer
// between Op batches via `r.with-caption(...)`.
#let frame1-ops = (
  (Op.Highlight.new)(path: "", color: blue),
  (Op.Annotate.new)(path: "", text: [root]),
  (Op.StyleNode.new)(path: "L", style: (fill: yellow)),
  (Op.StyleEdge.new)(path: "L", style: (stroke: red + 2pt)),
)
#let frame2-ops = (
  (Op.ClearNotes.new)(),
  (Op.StyleNode.new)(path: "R", style: (fill: aqua)),
  (Op.StyleEdge.new)(path: "R", style: (stroke: green + 2pt)),
  (Op.Annotate.new)(path: "R", text: [right]),
)

#let r = make-renderer(t, sticky: true)
#let r = (r.with-caption)([frame 1])
#let r = apply-ops(r, frame1-ops)
#let r = (r.push-frame)()
#let r = (r.with-caption)([frame 2])
#let r = apply-ops(r, frame2-ops)

#let frames = (r.render)()
#assert.eq(frames.len(), 2)

#starling.stacked(frames)
