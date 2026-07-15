// Per-DS theming: a document-wide `set-hashmap-theme` override and a
// per-call `theme:` override (the per-call form avoids the state read).
#import "/src/lib.typ" as starling
#import starling: hashmap, set-hashmap-theme

#set page(width: auto, height: auto, margin: 10pt)

// Document-wide palette override (state-based).
#set-hashmap-theme((
  empty-fill: rgb("#eef3ff"),
  index-fill: rgb("#3355aa"),
  tombstone-fill: rgb("#ffe0e0"),
  tombstone-stroke: rgb("#cc4444"),
  chain-stroke: rgb("#3355aa"),
))
#let c = hashmap(5, strategy: "chaining", entries: (5, 10, 7, 3))
#starling.last((c.display)())

#v(1.5em)

// Per-call override (does not touch state).
#let l = hashmap(7, strategy: "linear", entries: (14, 21, 7))
#starling.last(
  ((l.delete)(21).display)(theme: (
    empty-fill: rgb("#f6f0ff"),
    hash-box-stroke: rgb("#7c3aed"),
  )),
)
