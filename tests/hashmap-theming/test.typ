// Theming precedence: `default-theme` < `set-theme` state < a per-call
// `theme:` override. The second panel below sets only two keys per call, so it
// must keep the document-wide `index-fill` / `tombstone-*` from the state and
// change only what it names — the pre-1.0 per-call form reset to the defaults
// instead, which is the behaviour this replaces.
#import "/src/lib.typ" as starling
#import starling: hashmap, set-theme

#set page(width: auto, height: auto, margin: 10pt)

// Document-wide palette override (state-based).
#set-theme((
  hashmap: (
    empty-fill: rgb("#eef3ff"),
    index-fill: rgb("#3355aa"),
    tombstone-fill: rgb("#ffe0e0"),
    tombstone-stroke: rgb("#cc4444"),
    chain-stroke: rgb("#3355aa"),
  ),
))
#let c = hashmap.new(5, strategy: "chaining", entries: (5, 10, 7, 3))
#starling.last(hashmap.display(c))

#v(1.5em)

// Per-call override: `empty-fill` and `hash-box-stroke` win here, while the
// blue index labels and pink tombstone from the state carry through.
#let l = hashmap.new(7, strategy: "linear", entries: (14, 21, 7))
#starling.last(hashmap.display(
  hashmap.delete(l, 21),
  theme: (hashmap: (
    empty-fill: rgb("#f6f0ff"),
    hash-box-stroke: rgb("#7c3aed"),
  )),
))
