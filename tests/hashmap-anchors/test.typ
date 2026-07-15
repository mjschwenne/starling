// Manual cetz annotation (cell-anchor / entry-anchor over draw-hashmap)
// and the Op command stream (make-hashmap-renderer + cell-key paths).
#import "/src/lib.typ" as starling
#import starling: hashmap
#import "@preview/cetz:0.5.2"

#set page(width: auto, height: auto, margin: 10pt)

// --- cetz anchors ---
#let c = hashmap(5, strategy: "chaining", entries: (5, 10, 7, 3))
#cetz.canvas({
  starling.draw-hashmap((c.positioned)(), starling.blank-snapshot())
  import cetz.draw: *
  circle(starling.cell-anchor(2), radius: 0.8, stroke: red + 2pt)
  content(starling.entry-anchor(0, 1) + ".east", anchor: "west", [ ← tail])
})

#v(1em)

// --- Op command stream ---
#let oa = hashmap(7, strategy: "linear", entries: (14, 21))
#let r = starling.make-hashmap-renderer((oa.positioned)(), sticky: true)
#let r = (r.with-caption)([h(7) = 0])
#let r = starling.apply-ops(r, (
  (starling.Op.Highlight.new)(path: starling.cell-key(0), color: blue),
  (starling.Op.Commit.new)(alt: "Probe slot 0; occupied."),
))
#let r = (r.with-caption)([probe → slot 2])
#let r = starling.apply-ops(r, (
  (starling.Op.Highlight.new)(path: starling.cell-key(1), color: blue),
  (starling.Op.StyleNode.new)(
    path: starling.cell-key(2),
    style: (fill: green.lighten(60%), stroke: green + 2pt),
  ),
  (starling.Op.Alt.new)(text: "Land at slot 2."),
))
#starling.stacked((r.render)())
