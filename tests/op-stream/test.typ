#import "/src/lib.typ": BST, Op, apply-ops, make-renderer

#let t = (BST.new)(value: 4, left: none, right: none)
#let t = (t.insert-many)(2, 6, 1, 7)

// Exercise every Op variant in one fold:
//   Highlight, Annotate, StyleNode, StyleEdge, Caption, Commit, ClearNotes.
#let ops = (
  (Op.Caption.new)(text: [frame 1]),
  (Op.Highlight.new)(path: "", color: blue),
  (Op.Annotate.new)(path: "", text: [root]),
  (Op.StyleNode.new)(path: "L", style: (fill: yellow)),
  (Op.StyleEdge.new)(path: "L", style: (stroke: red + 2pt)),
  (Op.Commit.new)(),
  (Op.ClearNotes.new)(),
  (Op.Caption.new)(text: [frame 2]),
  (Op.StyleNode.new)(path: "R", style: (fill: aqua)),
  (Op.StyleEdge.new)(path: "R", style: (stroke: green + 2pt)),
  (Op.Annotate.new)(path: "R", text: [right]),
)

#let r = apply-ops(make-renderer(t, sticky: true), ops)
#let frames = (r.render)()
#assert.eq(frames.len(), 2)

#stack(dir: ttb, spacing: 1em, ..frames)
