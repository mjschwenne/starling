// Visual regression for B24 `insert-display` — exercises each
// rebalancing branch of both algorithms.

#import "/src/lib.typ" as starling
#import starling: B24, b24

#set page(width: auto, height: auto, margin: 1em)

#let leaf(..ks) = (B24.new)(
  keys: ks.pos(),
  labels: ks.pos().map(_ => auto),
  children: (),
)

== Top-down: insert into a non-full leaf
// No splits — just descend and add.
#let t1 = (B24.new)(
  keys: (10, 20),
  labels: (auto, auto),
  children: (leaf(3, 7), leaf(15), leaf(25, 30)),
)
#starling.stacked((t1.insert-display)(5))

#pagebreak()

== Top-down: descent triggers a child pre-split
// Left leaf is full [1, 3, 5]; insert 2 → pre-split [1] | 3 | [5],
// promote 3 to root, then insert 2 into [1].
#let t2 = (B24.new)(
  keys: (10,),
  labels: (auto,),
  children: (leaf(1, 3, 5), leaf(15, 20)),
)
#starling.stacked((t2.insert-display)(2))

#pagebreak()

== Top-down: root pre-split + child pre-split cascade
// Root is full and the descent target is also full — both
// preemptive splits happen before reaching the leaf.
#let t3 = (B24.new)(
  keys: (10, 20, 30),
  labels: (auto, auto, auto),
  children: (leaf(3, 7), leaf(15), leaf(25), leaf(35, 40, 50)),
)
#starling.stacked((t3.insert-display)(45))

#pagebreak()

== Bottom-up: insert into a non-full leaf
// Same fixture as the first top-down test for comparison.
#starling.stacked((t1.insert-display)(5, strategy: "bottom-up"))

#pagebreak()

== Bottom-up: overflow at the leaf, single split
// Insert 2 into [1, 3, 5] gives [1, 2, 3, 5] overflow; split at
// index 2 → [1, 2] | 3 | [5].
#starling.stacked((t2.insert-display)(2, strategy: "bottom-up"))

#pagebreak()

== Bottom-up: overflow cascades through the root
// Both the leaf and the (already-full) root overflow on insert.
#starling.stacked((t3.insert-display)(45, strategy: "bottom-up"))
