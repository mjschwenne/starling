#import "/src/lib.typ" as starling
#import starling: bst

#set page(width: auto, height: auto, margin: 0.5in)

#let t = bst.new(4, 1, 0, 7, 3, 6, 8)

#let panel(label, frames) = stack(
  dir: ttb,
  spacing: 0.5em,
  align(center, strong(label)),
  starling.last(frames, caption: true),
)

#grid(
  columns: 2,
  gutter: 1.5em,
  panel([In-order], bst.in-order-display(t)),
  panel([Pre-order], bst.pre-order-display(t)),
  panel([Post-order], bst.post-order-display(t)),
  panel([Level-order], bst.level-order-display(t)),
)
