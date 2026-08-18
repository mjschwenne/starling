#import "/src/lib.typ" as starling
#import starling: (
  annotate, apply-ops, bst, commit, render, set-alt, set-caption, style-edge,
  style-node,
)

#let t = bst.insert-many(bst.leaf(4), 2, 6, 1, 7)

// Exercise the whole op vocabulary: style-node, style-edge, annotate, commit
// (which carries the caption and alt of the frame it closes), and the two
// trailing-frame setters (`set-caption` / `set-alt`), which the last frame
// needs because no `commit` follows it.
//
// `sticky: true` makes each frame start from the previous one's styling, which
// is what the accumulate-as-you-go path exists for — note that frame 2 keeps
// frame 1's blue root ring and yellow left child. A note is transient, though,
// so frame 2 clears the root's with an explicit `note: none`.
#let frame1 = (
  style-node("", stroke: blue + 2pt)
    + annotate("", [root])
    + style-node("L", fill: yellow)
    + style-edge("L", stroke: red + 2pt)
    + commit(caption: [frame 1], alt: "Highlighted root and left edge.")
)
#let frame2 = (
  style-node("", note: none)
    + style-node("R", fill: aqua)
    + style-edge("R", stroke: green + 2pt)
    + annotate("R", [right])
    + set-caption([frame 2])
    + set-alt("Highlighted right edge and styled right child.")
)

#let frames = render(apply-ops(bst.renderer(t, sticky: true), frame1 + frame2))

#assert.eq(frames.len(), 2)
#assert.eq(frames.at(0).caption, [frame 1])
#assert.eq(frames.at(0).alt, "Highlighted root and left edge.")
#assert.eq(frames.at(1).caption, [frame 2])
#assert.eq(frames.at(1).alt, "Highlighted right edge and styled right child.")

#starling.stacked(frames)
