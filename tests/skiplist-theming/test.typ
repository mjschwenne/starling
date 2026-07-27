// Per-DS theming: a document-wide `set-skiplist-theme` override and a
// per-call `theme:` override (the per-call form avoids the state read).
#import "/src/lib.typ" as starling
#import starling: skiplist, set-skiplist-theme

#set page(width: auto, height: auto, margin: 10pt)

#let sl = skiplist(
  (value: 2, height: 1),
  (value: 5, height: 3),
  (value: 9, height: 2),
  (value: 14, height: 1),
)

// Document-wide palette override (state-based).
#set-skiplist-theme((
  header-fill: rgb("#e8f7ee"),
  header-stroke: rgb("#2f855a"),
  nil-fill: rgb("#fdecec"),
  nil-stroke: rgb("#c53030"),
  pointer-stroke: rgb("#3355aa"),
  index-fill: rgb("#2f855a"),
))
#starling.last((sl.display)())

#v(1.5em)

// Per-call override (does not touch state).
#starling.last(
  (sl.display)(theme: (
    header-fill: rgb("#f6f0ff"),
    nil-text-fill: rgb("#7c3aed"),
    pointer-stroke: rgb("#7c3aed"),
  )),
)
