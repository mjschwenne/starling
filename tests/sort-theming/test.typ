// Per-DS theming: a document-wide `set-sort-theme` override and a per-call
// `theme:` override (the per-call form avoids the state read).
#import "/src/lib.typ" as starling
#import starling: sort, set-sort-theme

#set page(width: auto, height: auto, margin: 10pt)

// Document-wide palette override (state-based).
#set-sort-theme((
  empty-fill: rgb("#eef3ff"),
  index-fill: rgb("#3355aa"),
  count-fill: rgb("#fff2e0"),
  active-digit-fill: rgb("#c0392b"),
))
#starling.last((sort(4, 2, 5, 1).counting-sort-display)())

#v(1.5em)

// Per-call override (does not touch state).
#starling.last(
  (sort(4, 2, 5, 1).counting-sort-display)(theme: (
    count-fill: rgb("#f6f0ff"),
    row-label-fill: rgb("#7c3aed"),
  )),
)
