// Assertion-style test for the pure sort operations (no rendered output
// depended on; the page is just a placeholder for tytanic).
#import "/src/lib.typ": result, sort

// ---- Counting sort matches the builtin sort oracle ----
#let a = sort.new(3, 1, 4, 1, 5, 9, 2, 6)
#assert.eq(sort.counting(a), sort.sorted(a))
#assert.eq(sort.counting(a), (1, 1, 2, 3, 4, 5, 6, 9))
// Explicit k (>= max+1) works too.
#assert.eq(sort.counting(a, k: 10), sort.sorted(a))

// Duplicates must survive (and stay together).
#assert.eq(sort.counting(sort.new(2, 2, 2, 0, 1, 1)), (0, 1, 1, 2, 2, 2))

// ---- Radix sort matches the oracle across bases ----
#let r = sort.new(170, 45, 75, 90, 802, 24, 2, 66)
#assert.eq(sort.radix(r), sort.sorted(r))
#assert.eq(sort.radix(r), (2, 24, 45, 66, 75, 90, 170, 802))
#assert.eq(sort.radix(r, base: 2), sort.sorted(r))
#assert.eq(sort.radix(r, base: 16), sort.sorted(r))

// ---- Edge cases ----
#assert.eq(sort.counting(sort.new()), ())
#assert.eq(sort.radix(sort.new()), ())
#assert.eq(sort.counting(sort.new(7)), (7,))
#assert.eq(sort.radix(sort.new(7)), (7,))
#assert.eq(sort.counting(sort.new(0, 0, 0)), (0, 0, 0))
#assert.eq(sort.radix(sort.new(0, 0, 0)), (0, 0, 0))

// ---- The factory accepts a splat or a single array ----
#assert.eq(sort.counting(sort.new((5, 3, 8, 1))), (1, 3, 5, 8))
#assert.eq(sort.new(5, 3, 8, 1).values, (5, 3, 8, 1))
#assert.eq(sort.new((5, 3, 8, 1)).values, (5, 3, 8, 1))
#assert.eq(sort.len(a), 8)
#assert(sort.check-invariants(a))

// ---- Enumerations: (value, label:) elements ----
// Bare ints get an `auto` label (parallel to values).
#assert.eq(sort.new(5, 3, 8, 1).labels, (auto, auto, auto, auto))
// A dict element splits key (sort) from label (display).
#let e = sort.new(
  (value: 2, label: [Tue]),
  (value: 0, label: [Sun]),
  (value: 1, label: [Mon]),
)
#assert.eq(e.values, (2, 0, 1))
#assert.eq(e.labels, ([Tue], [Sun], [Mon]))
#assert(sort.check-invariants(e))
// Pure ops still return the sorted integer KEYS (labels are display-only).
#assert.eq(sort.counting(e), (0, 1, 2))
#assert.eq(sort.radix(e), (0, 1, 2))
// Mixed bare-int and dict elements, and a single-array form of dicts.
#let m = sort.new(3, (value: 1, label: [one]), 2)
#assert.eq(m.values, (3, 1, 2))
#assert.eq(m.labels, (auto, [one], auto))
#assert.eq(sort.new(((value: 1, label: [a]), (value: 0, label: [b]))).values, (1, 0))
// A dict without an explicit label defaults to `auto`.
#assert.eq(sort.new((value: 4)).labels, (auto,))
// The displays don't panic over labelled elements (all counting variants + radix).
#assert.eq(type(sort.counting-display(e)), array)
#assert.eq(type(sort.counting-display(e, variant: "reconstruct")), array)
#assert.eq(type(sort.counting-display(e, variant: "buckets")), array)
#assert.eq(type(sort.counting-display(e, separate-counts: true)), array)
#assert.eq(type(sort.radix-display(e)), array)

// ---- Every animation ends on the sorted array, as a structure ----
// This is what lets a caller carry an animation's output into the next one
// instead of re-running the sort by hand.
#assert.eq(result(sort.counting-display(a)).values, sort.sorted(a))
#assert.eq(result(sort.counting-display(a, separate-counts: true)).values, sort.sorted(a))
#assert.eq(result(sort.radix-display(r)).values, sort.sorted(r))
// The stable variants carry each element's own label to its sorted slot.
#assert.eq(result(sort.counting-display(e)).labels, ([Sun], [Mon], [Tue]))
#assert.eq(result(sort.counting-display(e, variant: "buckets")).labels, ([Sun], [Mon], [Tue]))
// The reconstruct variant rebuilds from the histogram, so it only knows the
// first-seen label per key — the reason it is the unstable one.
#assert.eq(result(sort.counting-display(e, variant: "reconstruct")).values, (0, 1, 2))
// `display` stamps the untouched array.
#assert.eq(result(sort.display(a)), a)

// ---- Bad input is rejected ----
#assert.eq(sort.variants, ("prefix", "reconstruct", "buckets"))

// Placeholder page (tytanic always compares a rendered page).
#set page(width: auto, height: auto, margin: 6pt)
Sort pure-op assertions passed.
