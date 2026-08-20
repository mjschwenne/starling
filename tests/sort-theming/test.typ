// Theming, and the precedence between its two entry points: a document-wide
// `set-theme` override, then a per-call `theme:` that layers ON TOP of it
// rather than replacing it — so the second panel keeps the state's blue index
// labels and red digit subscripts while overriding two other keys.
#import "/src/lib.typ" as starling
#import starling: set-theme, sort

#set page(width: auto, height: auto, margin: 10pt)

// Document-wide palette override (state-based).
#set-theme((
  sort: (
    empty-fill: rgb("#eef3ff"),
    index-fill: rgb("#3355aa"),
    count-fill: rgb("#fff2e0"),
    active-digit-fill: rgb("#c0392b"),
  ),
))
#starling.last(sort.counting-display(sort.new(4, 2, 5, 1)))

#v(1.5em)

// Per-call override, merged over the state: `count-fill` and `row-label-fill`
// change, `index-fill` and `empty-fill` stay as `set-theme` left them.
#starling.last(sort.counting-display(
  sort.new(4, 2, 5, 1),
  theme: (sort: (count-fill: rgb("#f6f0ff"), row-label-fill: rgb("#7c3aed"))),
))
