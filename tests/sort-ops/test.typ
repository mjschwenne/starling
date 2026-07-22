// Assertion-style test for the Sort pure operations (no rendered output
// depended on; the page is just a placeholder for tytanic).
#import "/src/lib.typ": Sort, sort

// ---- Counting sort matches the builtin sort oracle ----
#let a = sort(3, 1, 4, 1, 5, 9, 2, 6)
#assert.eq((a.counting-sort)(), (a.sorted)())
#assert.eq((a.counting-sort)(), (1, 1, 2, 3, 4, 5, 6, 9))
// Explicit k (>= max+1) works too.
#assert.eq((a.counting-sort)(k: 10), (a.sorted)())

// Duplicates must survive (and stay together).
#assert.eq((sort(2, 2, 2, 0, 1, 1).counting-sort)(), (0, 1, 1, 2, 2, 2))

// ---- Radix sort matches the oracle across bases ----
#let r = sort(170, 45, 75, 90, 802, 24, 2, 66)
#assert.eq((r.radix-sort)(), (r.sorted)())
#assert.eq((r.radix-sort)(), (2, 24, 45, 66, 75, 90, 170, 802))
#assert.eq((r.radix-sort)(base: 2), (r.sorted)())
#assert.eq((r.radix-sort)(base: 16), (r.sorted)())

// ---- Edge cases ----
#assert.eq((sort().counting-sort)(), ())
#assert.eq((sort().radix-sort)(), ())
#assert.eq((sort(7).counting-sort)(), (7,))
#assert.eq((sort(7).radix-sort)(), (7,))
#assert.eq((sort(0, 0, 0).counting-sort)(), (0, 0, 0))
#assert.eq((sort(0, 0, 0).radix-sort)(), (0, 0, 0))

// ---- Factory accepts a splat or a single array ----
#assert.eq((sort((5, 3, 8, 1)).counting-sort)(), (1, 3, 5, 8))
#assert.eq(sort(5, 3, 8, 1).values, (5, 3, 8, 1))
#assert.eq(sort((5, 3, 8, 1)).values, (5, 3, 8, 1))
#assert.eq((a.len)(), 8)
#assert((a.check-invariants)())

// ---- Enumerations: (value, label:) elements ----
// Bare ints get an `auto` label (parallel to values).
#assert.eq(sort(5, 3, 8, 1).labels, (auto, auto, auto, auto))
// A dict element splits key (sort) from label (display).
#let e = sort(
  (value: 2, label: [Tue]),
  (value: 0, label: [Sun]),
  (value: 1, label: [Mon]),
)
#assert.eq(e.values, (2, 0, 1))
#assert.eq(e.labels, ([Tue], [Sun], [Mon]))
#assert((e.check-invariants)())
// Pure ops still return the sorted integer KEYS (labels are display-only).
#assert.eq((e.counting-sort)(), (0, 1, 2))
#assert.eq((e.radix-sort)(), (0, 1, 2))
// Mixed bare-int and dict elements, and a single-array form of dicts.
#let m = sort(3, (value: 1, label: [one]), 2)
#assert.eq(m.values, (3, 1, 2))
#assert.eq(m.labels, (auto, [one], auto))
#assert.eq(sort(((value: 1, label: [a]), (value: 0, label: [b]))).values, (1, 0))
// A dict without an explicit label defaults to `auto`.
#assert.eq(sort((value: 4)).labels, (auto,))
// The displays don't panic over labelled elements (all counting variants + radix).
#assert.eq(type((e.counting-sort-display)()), array)
#assert.eq(type((e.counting-sort-display)(variant: "reconstruct")), array)
#assert.eq(type((e.counting-sort-display)(variant: "buckets")), array)
#assert.eq(type((e.counting-sort-display)(separate-counts: true)), array)
#assert.eq(type((e.radix-sort-display)()), array)

// The buckets variant is stable, so it reproduces the counting-sort order.
#assert.eq((a.counting-sort)(), (a.sorted)())
#assert.eq(type((sort(3, 1, 4, 1, 0).counting-sort-display)(variant: "buckets")), array)
// separate-counts only applies to the prefix variant (not buckets).
#assert.eq(
  type((sort(2, 0, 1).counting-sort-display)(variant: "buckets")),
  array,
)

// Placeholder page (tytanic always compares a rendered page).
#set page(width: auto, height: auto, margin: 6pt)
Sort pure-op assertions passed.
