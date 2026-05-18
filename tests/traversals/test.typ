#import "/src/lib.typ" as starling
#import starling: BST

#set page(width: auto, height: auto, margin: 0.5in)

#let t = (BST.new)(value: 4, label: auto, left: none, right: none)
#let t = (t.insert-many)(1, 0, 7, 3, 6, 8)

#let panel(label, frames) = stack(
  dir: ttb,
  spacing: 0.5em,
  align(center, strong(label)),
  starling.last(frames, caption: true),
)

#grid(
  columns: 2,
  gutter: 1.5em,
  panel([In-order], (t.in-order-display)()),
  panel([Pre-order], (t.pre-order-display)()),
  panel([Post-order], (t.post-order-display)()),
  panel([Level-order], (t.level-order-display)()),
)
