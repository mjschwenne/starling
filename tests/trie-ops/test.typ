// Assertion-style regression for the trie's core operations (no rendered
// output depended on, like bst-ops / b24-ops). Still emits a placeholder
// page since tytanic always compares pages.

#import "/src/lib.typ": result, trie

#let t = trie.new("cat", "car", "card", "dog", "do")

// words() is lexicographically ordered (children kept sorted).
#assert.eq(trie.words(t), ("car", "card", "cat", "do", "dog"))
#assert.eq(trie.describe(t), "trie of \"car\", \"card\", \"cat\", \"do\", \"dog\"")
#assert(trie.check-invariants(t))

// contains vs has-prefix: "ca" is a prefix but not a stored word.
#assert(trie.contains(t, "cat"))
#assert(trie.contains(t, "do"))
#assert(not trie.contains(t, "ca"))
#assert(not trie.contains(t, "cards"))
#assert(trie.has-prefix(t, "ca"))
#assert(trie.has-prefix(t, "car"))
#assert(not trie.has-prefix(t, "x"))

// resolve / path-to.
#assert.eq(trie.resolve(t, "car").terminal, true)
#assert.eq(trie.resolve(t, "ca").terminal, false)
#assert.eq(trie.resolve(t, "zzz"), none)
#assert.eq(trie.path-to(t, "card"), ("", "c", "ca", "car", "card"))

// insert: adds a new word without disturbing the others.
#let ti = trie.insert(t, "care")
#assert(trie.contains(ti, "care"))
#assert.eq(trie.words(ti), ("car", "card", "care", "cat", "do", "dog"))
#assert(trie.check-invariants(ti))

// Inserting an existing word is a no-op on membership.
#assert.eq(trie.words(trie.insert(t, "cat")), trie.words(t))

// delete unmark-only: "car" has a child ("card"), so only its bit flips.
#let td-car = trie.delete(t, "car")
#assert(not trie.contains(td-car, "car"))
#assert(trie.contains(td-car, "card"))
#assert(trie.has-prefix(td-car, "car"))
#assert.eq(trie.words(td-car), ("card", "cat", "do", "dog"))
#assert(trie.check-invariants(td-car))

// delete partial prune: "card" prunes only its "d" leaf, stopping at "car"
// (still a word).
#let td-card = trie.delete(t, "card")
#assert(not trie.contains(td-card, "card"))
#assert(trie.contains(td-card, "car"))
#assert(not trie.has-prefix(td-card, "card"))
#assert.eq(trie.words(td-card), ("car", "cat", "do", "dog"))

// delete full-chain prune: "dog" is pruned back to "do" (still a word), so
// "d" survives but "dog" is gone.
#let td-dog = trie.delete(t, "dog")
#assert(not trie.contains(td-dog, "dog"))
#assert(trie.contains(td-dog, "do"))
#assert(trie.has-prefix(td-dog, "do"))
#assert(not trie.has-prefix(td-dog, "dog"))
#assert.eq(trie.words(td-dog), ("car", "card", "cat", "do"))

// delete a word whose whole branch is dead: on a trie without "do",
// deleting "dog" removes the entire d-o-g chain.
#let t2d = trie.delete(trie.new("cat", "dog"), "dog")
#assert(not trie.has-prefix(t2d, "d"))
#assert.eq(trie.words(t2d), ("cat",))
#assert(trie.check-invariants(t2d))

// Deleting a non-stored prefix or an absent word is a no-op.
#assert.eq(trie.words(trie.delete(t, "ca")), trie.words(t))
#assert.eq(trie.words(trie.delete(t, "xyz")), trie.words(t))

// Emptying the trie leaves a valid empty root — unlike the other
// structures, an emptied trie is still a trie, never `none`.
#let empty = trie.delete(trie.new("a"), "a")
#assert.eq(trie.words(empty), ())
#assert.eq(trie.describe(empty), "empty trie")
#assert(trie.check-invariants(empty))

// The empty factory is an empty trie too.
#assert.eq(trie.words(trie.new()), ())

// insert-many mirrors chained inserts.
#assert.eq(
  trie.words(trie.insert-many(trie.new(), "cat", "car", "card", "dog", "do")),
  trie.words(t),
)

// display alt text names the trie; search-display's last frame reports the
// outcome.
#assert.eq(trie.display(t).first().alt, "Trie: " + trie.describe(t) + ".")
#assert.eq(
  trie.search-display(t, "card").last().alt,
  "Reached \"card\", a stored word.",
)
#assert.eq(
  trie.search-display(t, "ca").last().alt,
  "Reached \"ca\", but it is only a prefix — not a stored word.",
)
#assert.eq(
  trie.search-display(t, "cab").last().alt,
  "No edge labelled 'b' from \"ca\"; \"cab\" is not in the trie.",
)

// The terminal frame's step kind reports the outcome.
#assert.eq(trie.search-display(t, "card").last().step.kind, "found")
#assert.eq(trie.search-display(t, "ca").last().step.kind, "prefix")
#assert.eq(trie.search-display(t, "cab").last().step.kind, "not-found")
#assert.eq(trie.display(t).first().step.kind, "static")

// Every display's final frame carries the trie the operation produced, so
// an animation and the state it advances to are written once, not twice.
#assert.eq(trie.words(result(trie.insert-display(t, "care"))), trie.words(ti))
#assert.eq(trie.words(result(trie.insert-display(t, "bat"))), trie.words(trie.insert(t, "bat")))
// Inserting a word that is already there still reports the trie.
#assert.eq(trie.words(result(trie.insert-display(t, "cat"))), trie.words(t))
#for w in ("car", "card", "dog", "do", "cat") {
  assert.eq(
    trie.words(result(trie.delete-display(t, w))),
    trie.words(trie.delete(t, w)),
  )
  assert.eq(
    trie.words(result(trie.delete-display(t, w, search: false))),
    trie.words(trie.delete(t, w)),
  )
}
// A search leaves the trie alone, so its result is the input.
#assert.eq(result(trie.search-display(t, "cab")), t)
#assert.eq(result(trie.display(t)), t)

// `search: false` drops the descent frames.
#assert(trie.delete-display(t, "dog", search: false).all(f => f.step.kind != "walk"))
#assert(trie.delete-display(t, "dog").any(f => f.step.kind == "walk"))

// Placeholder page so tytanic has something to compare.
Trie ops assertions passed.
