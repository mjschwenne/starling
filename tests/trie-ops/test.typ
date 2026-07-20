// Assertion-style regression for the Trie core operations (no rendered
// output depended on, like bst-ops / b24-ops). Still emits a placeholder
// page since tytanic always compares pages.

#import "/src/lib.typ": Trie, trie

#let t = trie("cat", "car", "card", "dog", "do")

// words() is lexicographically ordered (children kept sorted).
#assert.eq((t.words)(), ("car", "card", "cat", "do", "dog"))
#assert.eq((t.describe)(), "trie of \"car\", \"card\", \"cat\", \"do\", \"dog\"")
#assert.eq((t.check-invariants)(), none)

// contains vs has-prefix: "ca" is a prefix but not a stored word.
#assert((t.contains)("cat"))
#assert((t.contains)("do"))
#assert(not (t.contains)("ca"))
#assert(not (t.contains)("card" + "s"))
#assert((t.has-prefix)("ca"))
#assert((t.has-prefix)("car"))
#assert(not (t.has-prefix)("x"))

// resolve / path-to.
#assert.eq(((t.resolve)("car")).terminal, true)
#assert.eq(((t.resolve)("ca")).terminal, false)
#assert.eq((t.resolve)("zzz"), none)
#assert.eq((t.path-to)("card"), ("", "c", "ca", "car", "card"))

// insert: adds a new word without disturbing the others.
#let ti = (t.insert)("care")
#assert((ti.contains)("care"))
#assert.eq((ti.words)(), ("car", "card", "care", "cat", "do", "dog"))
#assert.eq((ti.check-invariants)(), none)

// insert an existing word is a no-op on membership.
#assert.eq(((t.insert)("cat").words)(), (t.words)())

// delete unmark-only: "car" has a child ("card"), so only its bit flips.
#let td-car = (t.delete)("car")
#assert(not (td-car.contains)("car"))
#assert((td-car.contains)("card"))
#assert((td-car.has-prefix)("car"))
#assert.eq((td-car.words)(), ("card", "cat", "do", "dog"))
#assert.eq((td-car.check-invariants)(), none)

// delete partial prune: "card" prunes only its "d" leaf, stopping at
// "car" (still a word).
#let td-card = (t.delete)("card")
#assert(not (td-card.contains)("card"))
#assert((td-card.contains)("car"))
#assert(not (td-card.has-prefix)("card"))
#assert.eq((td-card.words)(), ("car", "cat", "do", "dog"))

// delete full-chain prune: "dog" is pruned back to "do" (still a word),
// so "d" survives but "dog" is gone.
#let td-dog = (t.delete)("dog")
#assert(not (td-dog.contains)("dog"))
#assert((td-dog.contains)("do"))
#assert((td-dog.has-prefix)("do"))
#assert(not (td-dog.has-prefix)("dog"))
#assert.eq((td-dog.words)(), ("car", "card", "cat", "do"))

// delete a word whose whole branch is dead: on a trie without "do",
// deleting "dog" removes the entire d-o-g chain.
#let t2 = trie("cat", "dog")
#let t2d = (t2.delete)("dog")
#assert(not (t2d.has-prefix)("d"))
#assert.eq((t2d.words)(), ("cat",))
#assert.eq((t2d.check-invariants)(), none)

// deleting a non-stored prefix or absent word is a no-op.
#assert.eq(((t.delete)("ca").words)(), (t.words)())
#assert.eq(((t.delete)("xyz").words)(), (t.words)())

// emptying the trie leaves a valid empty root.
#let empty = (trie("a").delete)("a")
#assert.eq((empty.words)(), ())
#assert.eq((empty.describe)(), "empty trie")
#assert.eq((empty.check-invariants)(), none)

// the empty factory is an empty trie too.
#assert.eq((trie().words)(), ())

// insert-many mirrors chained inserts.
#assert.eq(
  ((trie().insert-many)("cat", "car", "card", "dog", "do").words)(),
  (t.words)(),
)

// display alt text names the trie; search-display's last frame reports
// the outcome.
#assert.eq((t.display)().first().alt, "Trie: " + (t.describe)() + ".")
#assert.eq(
  (t.search-display)("card").last().alt,
  "Reached \"card\", a stored word.",
)
#assert.eq(
  (t.search-display)("ca").last().alt,
  "Reached \"ca\", but it is only a prefix — not a stored word.",
)
#assert.eq(
  (t.search-display)("cab").last().alt,
  "No edge labelled 'b' from \"ca\"; \"cab\" is not in the trie.",
)

// Placeholder page so tytanic has something to compare.
Trie ops assertions passed.
