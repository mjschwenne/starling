#import "/src/lib.typ" as starling
#import starling: bst, figures

#set page(height: auto, margin: 5mm, fill: none)

// style thumbnail for light and dark theme
#let theme = sys.inputs.at("theme", default: "light")
#set text(white) if theme == "dark"

#set text(22pt)

#let tree = bst.insert-many(bst.leaf(5), 1, 10)
#let frames = bst.insert-display(tree, 7)
#grid(
  columns: 3,
  column-gutter: 1em,
  row-gutter: 1em,
  ..figures(frames, caption: false),
)
