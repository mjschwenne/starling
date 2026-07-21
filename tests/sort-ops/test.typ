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

// Placeholder page (tytanic always compares a rendered page).
#set page(width: auto, height: auto, margin: 6pt)
Sort pure-op assertions passed.
