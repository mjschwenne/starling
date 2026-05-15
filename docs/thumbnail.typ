#import "/src/lib.typ" as starling
#import starling: BST

#set page(height: auto, margin: 5mm, fill: none)

// style thumbnail for light and dark theme
#let theme = sys.inputs.at("theme", default: "light")
#set text(white) if theme == "dark"

#set text(22pt)

#let tree = (BST.new)(value: 5, left: none, right: none)
#let tree = (tree.insert-many)(1, 10)
#let frames = (tree.insert-display)(7)
#grid(
  columns: 3,
  column-gutter: 1em,
  row-gutter: 1em,
  ..starling.figures(frames, caption: false),
)
