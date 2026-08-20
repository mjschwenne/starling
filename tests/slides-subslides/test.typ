// `subslides` — one composed piece of content per frame: the canvas, the
// algorithm's auxiliary strip, and the step's caption laid out together and
// wrapped in the frame's alt figure, ready to splat into touying's
// `alternatives(..)`. This is the hand-built grid sandwich (a `canvas`
// column, an `aux-strip` column, a caption row, each in its own
// `alternatives`) collapsed into one call.
//
// Each subslide is rendered on its own page here, which is what touying
// does with them. `fit: (20cm, 12cm)` measures every frame and applies ONE
// common scale factor, so the drawing keeps a constant size across the
// subslides instead of resizing under each step — check that by eye: the
// graph must not move or resize from page to page.
#import "@preview/cetz:0.5.2"
#import "/src/lib.typ" as starling
#import starling: anchor, graph, last, overlay, subslides

#let g = graph.new(
  (
    ("A", 0, 0),
    ("B", -1.6, -1.6),
    ("C", 1.6, -1.6),
    ("D", 0, -3.2),
    ("E", 3.2, -3.2),
  ),
  edges: (("A", "B"), ("A", "C"), ("B", "D"), ("C", "D"), ("C", "E")),
)

#let frames = graph.bfs-display(g, "A", sort-frontier: true)

// Slide-shaped pages: the strip on the right, everything scaled to fill.
#set page(width: 21cm, height: 13.5cm, margin: 8pt)

#for s in subslides(frames, aux: "right", fit: (20cm, 12cm)) [
  #s
  #pagebreak(weak: true)
]

#set page(width: auto, height: auto, margin: 8pt)

// The other two placements and the ratio form of `fit:`, one frame apiece:
// the queue under the canvas on the left, and to the left of it on the
// right (which also drops the caption).
#let below = subslides(frames, aux: "below", fit: 55%)
#let left = subslides(frames, aux: "left", fit: 55%, caption: false)
#grid(
  columns: 2,
  column-gutter: 2em,
  align: horizon,
  below.at(2),
  left.at(2),
)

#pagebreak()

// A single frame, with a cetz callout drawn into its canvas: `overlay`
// appends commands inside the same canvas, so the backend's `el-` anchors
// are in scope, and `last` takes the lone frame without re-wrapping it in a
// one-tuple.
#let annotated = overlay(
  frames,
  at: -1,
  draw: theme => {
    import cetz.draw: content, line
    line(
      (rel: (-1.5, -1.1), to: anchor("D")),
      anchor("D") + ".south-west",
      stroke: theme.op.attention-stroke,
      mark: (end: ">"),
    )
    content(
      (rel: (-1.6, -1.2), to: anchor("D")),
      [last one out],
      anchor: "north-east",
    )
  },
)

#last(annotated.last(), caption: true)
