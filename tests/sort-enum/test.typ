// Sorting an enumeration: each element is a `(value, label:)` pair — the
// integer `value` is the sort key (counting/radix bucket by it), the
// `label` content is what's drawn. Exercises both the stable prefix
// counting sort and a radix pass carrying labels through placement.
#import "/src/lib.typ" as starling
#import starling: sort

#set page(width: auto, height: auto, margin: 10pt)

// Weekdays keyed by their ordinal, displayed by name — out of order so
// placement visibly reorders the labels, not just the keys.
#let days = sort(
  (value: 3, label: [Wed]),
  (value: 1, label: [Mon]),
  (value: 0, label: [Sun]),
  (value: 2, label: [Tue]),
)

#starling.stacked((days.counting-sort-display)())

// Radix over labelled numbers: the digit subscripts read off the key while
// the label rides along to the sorted output.
#let nums = sort(
  (value: 23, label: [23kg]),
  (value: 4, label: [4kg]),
  (value: 8, label: [8kg]),
)

#starling.stacked((nums.radix-sort-display)())
