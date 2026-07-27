// Assertion-style test for the Skiplist pure operations (no rendered
// output depended on; the page is just a placeholder for tytanic).
#import "/src/lib.typ": Skiplist, skiplist

// ---- Construction keeps keys sorted & unique ----
#let s = skiplist(3, 1, 4, 7, 5, seed: 7)
#assert.eq((s.keys)(), (1, 3, 4, 5, 7))
#assert((s.contains)(3))
#assert(not (s.contains)(2))
#assert((s.check-invariants)())

// ---- Explicit heights ----
#let e = skiplist(
  (value: 1, height: 1),
  (value: 3, height: 3),
  (value: 7, height: 2),
)
#assert.eq((e.keys)(), (1, 3, 7))
#assert.eq((e.levels)(), 3)
#assert.eq(e.nodes.at(1).height, 3)
#assert((e.check-invariants)())

// ---- Insert is immutable, sorted, and searchable ----
#let e2 = (e.insert)(5, height: 2)
#assert.eq((e2.keys)(), (1, 3, 5, 7))
#assert((e2.contains)(5))
#assert(not (e.contains)(5)) // original unchanged
#assert((e2.check-invariants)())

// Insert of an existing key updates the label in place (no new node).
#let e3 = (e.insert)(3, label: [three])
#assert.eq((e3.keys)(), (1, 3, 7))
#assert.eq((e3.get)(3), [three])

// Insert into the empty list and at the ends.
#assert.eq(((skiplist().insert)(9, height: 1).keys)(), (9,))
#assert.eq(((e.insert)(0, height: 1).keys)(), (0, 1, 3, 7))
#assert.eq(((e.insert)(99, height: 1).keys)(), (1, 3, 7, 99))

// ---- Delete is immutable; absent key is a no-op ----
#let e4 = (e2.delete)(3)
#assert.eq((e4.keys)(), (1, 5, 7))
#assert(not (e4.contains)(3))
#let e5 = (e2.delete)(999)
#assert.eq((e5.keys)(), (1, 3, 5, 7))

// ---- Seeded coin flips are deterministic (same seed -> same towers) ----
#let a = skiplist(10, 20, 30, 40, 50, seed: 42)
#let b = skiplist(10, 20, 30, 40, 50, seed: 42)
#assert.eq(a.nodes.map(nd => nd.height), b.nodes.map(nd => nd.height))
// Heights are always within 1..max-level.
#assert(a.nodes.map(nd => nd.height).all(h => h >= 1 and h <= a.max-level))
// A smaller max-level caps the towers.
#let c = skiplist(1, 2, 3, 4, 5, 6, 7, 8, seed: 3, max-level: 2)
#assert(c.nodes.map(nd => nd.height).all(h => h <= 2))

// ---- Factory forms ----
#assert.eq((skiplist((8, 2, 5)).keys)(), (2, 5, 8)) // single array
#let m = skiplist(3, (value: 1, label: [one], height: 2), 2, seed: 1)
#assert.eq((m.keys)(), (1, 2, 3))
#assert.eq((m.get)(1), [one])
#assert.eq(m.nodes.at(0).height, 2) // explicit height honored
#assert.eq((skiplist().len)(), 0)
#assert.eq((s.len)(), 5)

// ---- describe / positioned / display return the expected types ----
#assert.eq(type((e.describe)()), str)
#assert.eq(type((e.positioned)()), dictionary)
#assert.eq(type((e.display)()), array)
#assert.eq(type((e.search-display)(3)), array)
#assert.eq(type((e.search-display)(6)), array) // miss
#assert.eq(type((e.insert-display)(5, height: 2)), array)
#assert.eq(type((e.insert-display)(6)), array) // seeded height
#assert.eq(type((e.delete-display)(3)), array)
#assert.eq(type((e.delete-display)(6)), array) // miss
// nil: false still renders.
#assert.eq(type((skiplist(1, 2, 3, nil: false, seed: 1).display)()), array)

// Placeholder page (tytanic always compares a rendered page).
#set page(width: auto, height: auto, margin: 6pt)
Skiplist pure-op assertions passed.
