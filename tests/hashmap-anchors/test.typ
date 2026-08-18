// Two ways to drive the hash-map backend by hand: cetz annotations anchored at
// `anchor(cell-key(..))` / `anchor(entry-key(..))` over `draw-hashmap`, and the
// op command stream over `hashmap.renderer`.
#import "@preview/cetz:0.5.2"
#import "/src/lib.typ" as starling
#import starling: (
  anchor, apply-ops, blank-snapshot, commit, draw-hashmap, hashmap, render,
  set-alt, set-caption, style-node,
)

#set page(width: auto, height: auto, margin: 10pt)

// --- cetz anchors ---
#let c = hashmap.new(5, strategy: "chaining", entries: (5, 10, 7, 3))
#context cetz.canvas({
  draw-hashmap(hashmap.positioned(c), blank-snapshot())
  // Import selectively: cetz.draw has an `anchor` of its own, and a glob
  // import would shadow starling's.
  import cetz.draw: circle, content
  circle(anchor(hashmap.cell-key(2)), radius: 0.8, stroke: red + 2pt)
  content(anchor(hashmap.entry-key(0, 1)) + ".east", anchor: "west", [ ← tail])
})

#v(1em)

// --- the op command stream ---
#let oa = hashmap.new(7, strategy: "linear", entries: (14, 21))
#let ops = (
  style-node(hashmap.cell-key(0), stroke: blue + 2pt)
    + commit(caption: [h(7) = 0], alt: "Probe slot 0; occupied.")
    + style-node(hashmap.cell-key(1), stroke: blue + 2pt)
    + style-node(
      hashmap.cell-key(2),
      fill: green.lighten(60%),
      stroke: green + 2pt,
    )
    + set-caption([probe → slot 2])
    + set-alt("Land at slot 2.")
)
#starling.stacked(render(apply-ops(hashmap.renderer(oa, sticky: true), ops)))
