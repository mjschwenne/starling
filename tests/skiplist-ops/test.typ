// Assertion-style test for the pure skip-list operations (no rendered output
// depended on; the page is just a placeholder for tytanic).
#import "/src/lib.typ": result, skiplist

// ---- Construction keeps keys sorted & unique ----
#let s = skiplist.new(3, 1, 4, 7, 5, seed: 7)
#assert.eq(skiplist.keys(s), (1, 3, 4, 5, 7))
#assert(skiplist.contains(s, 3))
#assert(not skiplist.contains(s, 2))
#assert(skiplist.check-invariants(s))

// ---- Explicit heights ----
#let e = skiplist.new(
  (value: 1, height: 1),
  (value: 3, height: 3),
  (value: 7, height: 2),
)
#assert.eq(skiplist.keys(e), (1, 3, 7))
#assert.eq(skiplist.levels(e), 3)
#assert.eq(e.nodes.at(1).height, 3)
#assert(skiplist.check-invariants(e))

// ---- Insert is immutable, sorted, and searchable ----
#let e2 = skiplist.insert(e, 5, height: 2)
#assert.eq(skiplist.keys(e2), (1, 3, 5, 7))
#assert(skiplist.contains(e2, 5))
#assert(not skiplist.contains(e, 5)) // original unchanged
#assert(skiplist.check-invariants(e2))

// Insert of an existing key updates the label in place (no new node).
#let e3 = skiplist.insert(e, 3, label: [three])
#assert.eq(skiplist.keys(e3), (1, 3, 7))
#assert.eq(skiplist.get(e3, 3), [three])

// Insert into the empty list and at the ends.
#assert.eq(skiplist.keys(skiplist.insert(skiplist.new(), 9, height: 1)), (9,))
#assert.eq(skiplist.keys(skiplist.insert(e, 0, height: 1)), (0, 1, 3, 7))
#assert.eq(skiplist.keys(skiplist.insert(e, 99, height: 1)), (1, 3, 7, 99))

// ---- Delete is immutable; an absent key is a no-op ----
#let e4 = skiplist.delete(e2, 3)
#assert.eq(skiplist.keys(e4), (1, 5, 7))
#assert(not skiplist.contains(e4, 3))
#assert.eq(skiplist.keys(skiplist.delete(e2, 999)), (1, 3, 5, 7))

// ---- Seeded coin flips are deterministic (same seed -> same towers) ----
#let a = skiplist.new(10, 20, 30, 40, 50, seed: 42)
#let b = skiplist.new(10, 20, 30, 40, 50, seed: 42)
#assert.eq(a.nodes.map(nd => nd.height), b.nodes.map(nd => nd.height))
// Heights are always within 1..max-level.
#assert(a.nodes.map(nd => nd.height).all(h => h >= 1 and h <= a.max-level))
// A smaller max-level caps the towers.
#let c = skiplist.new(1, 2, 3, 4, 5, 6, 7, 8, seed: 3, max-level: 2)
#assert(c.nodes.map(nd => nd.height).all(h => h <= 2))

// ---- Factory forms ----
#assert.eq(skiplist.keys(skiplist.new((8, 2, 5))), (2, 5, 8)) // single array
#let m = skiplist.new(3, (value: 1, label: [one], height: 2), 2, seed: 1)
#assert.eq(skiplist.keys(m), (1, 2, 3))
#assert.eq(skiplist.get(m, 1), [one])
#assert.eq(m.nodes.at(0).height, 2) // explicit height honored
#assert.eq(skiplist.len(skiplist.new()), 0)
#assert.eq(skiplist.len(s), 5)

// ---- describe / positioned / display return the expected types ----
#assert.eq(type(skiplist.describe(e)), str)
#assert.eq(type(skiplist.positioned(e)), dictionary)
#assert.eq(type(skiplist.display(e)), array)
#assert.eq(type(skiplist.search-display(e, 3)), array)
#assert.eq(type(skiplist.search-display(e, 6)), array) // miss
#assert.eq(type(skiplist.insert-display(e, 5, height: 2)), array)
#assert.eq(type(skiplist.insert-display(e, 6)), array) // seeded height
#assert.eq(type(skiplist.delete-display(e, 3)), array)
#assert.eq(type(skiplist.delete-display(e, 6)), array) // miss
// nil: false still renders.
#assert.eq(type(skiplist.display(skiplist.new(1, 2, 3, nil: false, seed: 1))), array)

// ---- Every display ends on the list the operation produced ----
#assert.eq(result(skiplist.display(e)), e)
#assert.eq(result(skiplist.search-display(e, 3)), e) // a search changes nothing
#assert.eq(
  skiplist.keys(result(skiplist.insert-display(e, 5, height: 2))),
  (1, 3, 5, 7),
)
#assert.eq(skiplist.keys(result(skiplist.delete-display(e, 3))), (1, 7))

// `search: false` keeps the pointer surgery and drops the walk that found it,
// so the frames are strictly fewer and no `advance` / `drop` survives.
#let full = skiplist.delete-display(e, 3)
#let quiet = skiplist.delete-display(e, 3, search: false)
#assert(quiet.len() < full.len())
#assert(quiet.all(f => not ("advance", "drop").contains(f.step.kind)))
#assert.eq(quiet.first().step.kind, "init")
#assert.eq(quiet.last().step.kind, "deleted")
#assert.eq(skiplist.keys(result(quiet)), (1, 7))

// Placeholder page (tytanic always compares a rendered page).
#set page(width: auto, height: auto, margin: 6pt)
Skiplist pure-op assertions passed.
