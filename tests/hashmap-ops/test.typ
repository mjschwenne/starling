// Assertion-style test for the HashMap pure operations (no rendered
// output depended on; the page is just a placeholder for tytanic).
#import "/src/lib.typ": HashMap, hashmap

// ---- Linear probing ----
#let l = hashmap(7, strategy: "linear")
#let l1 = (l.insert)(14) // h=0 -> slot 0
#let l2 = (l1.insert)(21) // h=0 collide -> slot 1
#let l3 = (l2.insert)(7) // h=0 collide,collide -> slot 2
#assert.eq((l3.hash-of)(14), 0)
#assert.eq((l3.probe-seq)(21), (0, 1, 2, 3, 4, 5, 6))
#assert((l3.contains)(14) and (l3.contains)(21) and (l3.contains)(7))
#assert(not (l3.contains)(28))
#assert.eq((l3.size)(), 3)
// delete 21 -> tombstone at 1; 7 still findable *through* the tombstone
#let l4 = (l3.delete)(21)
#assert(not (l4.contains)(21))
#assert((l4.contains)(7))
#assert.eq((l4.size)(), 2)
// insert 28 reuses the first tombstone (slot 1)
#let l5 = (l4.insert)(28)
#assert.eq((l5.slots).at(1).key, 28)
#assert((l5.check-invariants)())

// ---- Quadratic probing (prime m=7) ----
#let q = hashmap(7, strategy: "quadratic")
#assert.eq((q.probe-seq)(0), (0, 1, 4, 2, 2, 4, 1))
#let q1 = (q.insert)(0) // slot 0
#let q2 = (q1.insert)(7) // +1 -> slot 1
#let q3 = (q2.insert)(14) // +4 -> slot 4
#let q4 = (q3.insert)(21) // +? -> slot 2
#assert.eq((q4.slots).at(0).key, 0)
#assert.eq((q4.slots).at(1).key, 7)
#assert.eq((q4.slots).at(4).key, 14)
#assert.eq((q4.slots).at(2).key, 21)

// ---- Chaining ----
#let c = hashmap(5, strategy: "chaining", entries: (5, 10, 7, 3, 8))
#assert.eq((c.slots).at(0).map(e => e.key), (5, 10)) // chain in bucket 0
#assert.eq((c.slots).at(3).map(e => e.key), (3, 8))
#assert((c.contains)(10))
#assert.eq((c.size)(), 5)
// update in place (not a second entry)
#let c2 = (c.insert)(10, value: "x")
#assert.eq((c2.slots).at(0).len(), 2)
#assert.eq((c2.get)(10), "x")
// delete unlinks
#let c3 = (c2.delete)(5)
#assert.eq((c3.slots).at(0).map(e => e.key), (10,))
#assert.eq((c3.load-factor)(), 4 / 5)

// ---- Resize / rehash ----
#let r = (l5.resize)(11)
#assert.eq(r.capacity, 11)
#assert((r.contains)(14) and (r.contains)(7) and (r.contains)(28))
#assert.eq((r.size)(), 3)
#assert((r.check-invariants)())

// ---- Double hashing ----
// h1 = k mod 7, h2 = 1 + (k mod 6). For 28: h1=0, h2=5 -> 0,5,3,1,6,4,2.
#let d = hashmap(7, strategy: "double", entries: (14, 21, 7))
#assert.eq((d.probe-seq)(28), (0, 5, 3, 1, 6, 4, 2))
#assert.eq((d.slots).at(0).key, 14) // h1(14)=0
#assert.eq((d.slots).at(4).key, 21) // 0 + h2(21)=4 -> slot 4
#assert.eq((d.slots).at(2).key, 7) //  0 + h2(7)=2  -> slot 2
#let d2 = (d.insert)(28) // 0 occupied, +5 -> slot 5
#assert.eq((d2.slots).at(5).key, 28)
#assert((d2.contains)(28) and (d2.contains)(21))
// A constant second hash makes the step fixed (must stay coprime to m
// for full coverage — 3 is coprime to 7).
#let dc = hashmap(7, strategy: "double", hash2: (k, m) => 3, hash2-repr: "3")
#assert.eq((dc.probe-seq)(0), (0, 3, 6, 2, 5, 1, 4))
// A zero step is bumped to 1 so the probe never stalls.
#let dz = hashmap(5, strategy: "double", hash2: (k, m) => 0, hash2-repr: "0")
#assert.eq((dz.probe-seq)(0), (0, 1, 2, 3, 4))

// ---- Custom hash function + repr ----
#let cu = hashmap(
  8,
  strategy: "linear",
  hash: (k, m) => calc.rem(k * 3, m),
  hash-repr: "3k mod m",
)
#assert.eq((cu.hash-of)(5), calc.rem(15, 8)) // 7

// Placeholder page (tytanic always compares a rendered page).
#set page(width: auto, height: auto, margin: 6pt)
HashMap pure-op assertions passed.
