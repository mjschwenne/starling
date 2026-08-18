// Assertion-style test for the HashMap pure operations (no rendered
// output depended on; the page is just a placeholder for tytanic).
#import "/src/lib.typ": hashmap, result

// ---- Linear probing ----
#let l = hashmap.new(7, strategy: "linear")
#let l1 = hashmap.insert(l, 14) // h=0 -> slot 0
#let l2 = hashmap.insert(l1, 21) // h=0 collide -> slot 1
#let l3 = hashmap.insert(l2, 7) // h=0 collide,collide -> slot 2
#assert.eq(hashmap.hash-of(l3, 14), 0)
#assert.eq(hashmap.probe-seq(l3, 21), (0, 1, 2, 3, 4, 5, 6))
#assert(hashmap.contains(l3, 14) and hashmap.contains(l3, 21) and hashmap.contains(l3, 7))
#assert(not hashmap.contains(l3, 28))
#assert.eq(hashmap.size(l3), 3)
// delete 21 -> tombstone at 1; 7 still findable *through* the tombstone
#let l4 = hashmap.delete(l3, 21)
#assert(not hashmap.contains(l4, 21))
#assert(hashmap.contains(l4, 7))
#assert.eq(hashmap.size(l4), 2)
// insert 28 reuses the first tombstone (slot 1)
#let l5 = hashmap.insert(l4, 28)
#assert.eq(l5.slots.at(1).key, 28)
#assert(hashmap.check-invariants(l5))

// ---- Quadratic probing (prime m=7) ----
#let q = hashmap.new(7, strategy: "quadratic")
#assert.eq(hashmap.probe-seq(q, 0), (0, 1, 4, 2, 2, 4, 1))
#let q1 = hashmap.insert(q, 0) // slot 0
#let q2 = hashmap.insert(q1, 7) // +1 -> slot 1
#let q3 = hashmap.insert(q2, 14) // +4 -> slot 4
#let q4 = hashmap.insert(q3, 21) // +? -> slot 2
#assert.eq(q4.slots.at(0).key, 0)
#assert.eq(q4.slots.at(1).key, 7)
#assert.eq(q4.slots.at(4).key, 14)
#assert.eq(q4.slots.at(2).key, 21)

// ---- Chaining ----
#let c = hashmap.new(5, strategy: "chaining", entries: (5, 10, 7, 3, 8))
#assert.eq(c.slots.at(0).map(e => e.key), (5, 10)) // chain in bucket 0
#assert.eq(c.slots.at(3).map(e => e.key), (3, 8))
#assert(hashmap.contains(c, 10))
#assert.eq(hashmap.size(c), 5)
// update in place (not a second entry)
#let c2 = hashmap.insert(c, 10, value: "x")
#assert.eq(c2.slots.at(0).len(), 2)
#assert.eq(hashmap.get(c2, 10), "x")
// delete unlinks
#let c3 = hashmap.delete(c2, 5)
#assert.eq(c3.slots.at(0).map(e => e.key), (10,))
#assert.eq(hashmap.load-factor(c3), 4 / 5)

// ---- Resize / rehash ----
#let r = hashmap.resize(l5, 11)
#assert.eq(r.capacity, 11)
#assert(hashmap.contains(r, 14) and hashmap.contains(r, 7) and hashmap.contains(r, 28))
#assert.eq(hashmap.size(r), 3)
#assert(hashmap.check-invariants(r))

// ---- Double hashing ----
// h1 = k mod 7, h2 = 1 + (k mod 6). For 28: h1=0, h2=5 -> 0,5,3,1,6,4,2.
#let d = hashmap.new(7, strategy: "double", entries: (14, 21, 7))
#assert.eq(hashmap.probe-seq(d, 28), (0, 5, 3, 1, 6, 4, 2))
#assert.eq(d.slots.at(0).key, 14) // h1(14)=0
#assert.eq(d.slots.at(4).key, 21) // 0 + h2(21)=4 -> slot 4
#assert.eq(d.slots.at(2).key, 7) //  0 + h2(7)=2  -> slot 2
#let d2 = hashmap.insert(d, 28) // 0 occupied, +5 -> slot 5
#assert.eq(d2.slots.at(5).key, 28)
#assert(hashmap.contains(d2, 28) and hashmap.contains(d2, 21))
// A constant second hash makes the step fixed (must stay coprime to m
// for full coverage — 3 is coprime to 7).
#let dc = hashmap.new(7, strategy: "double", hash2: (k, m) => 3, hash2-repr: "3")
#assert.eq(hashmap.probe-seq(dc, 0), (0, 3, 6, 2, 5, 1, 4))
// A zero step is bumped to 1 so the probe never stalls.
#let dz = hashmap.new(5, strategy: "double", hash2: (k, m) => 0, hash2-repr: "0")
#assert.eq(hashmap.probe-seq(dz, 0), (0, 1, 2, 3, 4))

// ---- Custom hash function + repr ----
#let cu = hashmap.new(
  8,
  strategy: "linear",
  hash: (k, m) => calc.rem(k * 3, m),
  hash-repr: "3k mod m",
)
#assert.eq(hashmap.hash-of(cu, 5), calc.rem(15, 8)) // 7

// Every display's final frame carries the map the operation produced, so an
// animation and the state it advances to are written once, not twice.
#assert.eq(hashmap.describe(result(hashmap.insert-display(l4, 28))), hashmap.describe(l5))
#assert.eq(hashmap.describe(result(hashmap.delete-display(l3, 21))), hashmap.describe(l4))
#assert.eq(hashmap.describe(result(hashmap.resize-display(l5, 11))), hashmap.describe(r))
// A search leaves the table alone, so its result is the input.
#assert.eq(result(hashmap.search-display(l3, 7)), l3)
#assert.eq(result(hashmap.display(l3)), l3)

// A miss records why it missed, not just that it did.
#assert.eq(hashmap.search-display(l3, 99).last().step.reason, "empty")
#assert.eq(hashmap.search-display(c, 99).last().step.reason, "chain-end")

// Placeholder page (tytanic always compares a rendered page).
#set page(width: auto, height: auto, margin: 6pt)
HashMap pure-op assertions passed.
