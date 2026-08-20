// Theming, and the precedence between its two entry points: a document-wide
// `set-theme` override, then a per-call `theme:` that layers ON TOP of it
// rather than replacing it — so the second panel keeps the state's green
// header stroke and red nil fill while overriding three other keys.
#import "/src/lib.typ" as starling
#import starling: set-theme, skiplist

#set page(width: auto, height: auto, margin: 10pt)

#let sl = skiplist.new(
  (value: 2, height: 1),
  (value: 5, height: 3),
  (value: 9, height: 2),
  (value: 14, height: 1),
)

// Document-wide palette override (state-based).
#set-theme((
  skiplist: (
    header-fill: rgb("#e8f7ee"),
    header-stroke: rgb("#2f855a"),
    nil-fill: rgb("#fdecec"),
    nil-stroke: rgb("#c53030"),
    pointer-stroke: rgb("#3355aa"),
    index-fill: rgb("#2f855a"),
  ),
))
#starling.last(skiplist.display(sl))

#v(1.5em)

// Per-call override, merged over the state: the header fill, nil text, and
// pointers change; the green header stroke and red nil stroke stay as
// `set-theme` left them.
#starling.last(skiplist.display(
  sl,
  theme: (
    skiplist: (
      header-fill: rgb("#f6f0ff"),
      nil-text-fill: rgb("#7c3aed"),
      pointer-stroke: rgb("#7c3aed"),
    ),
  ),
))
