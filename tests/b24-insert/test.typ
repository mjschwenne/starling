// Visual regression for B24 `insert-display` — exercises each
// rebalancing branch of both algorithms.

#import "/src/lib.typ" as starling
#import starling: b24

#set page(width: auto, height: auto, margin: 1em)

== Top-down: insert into a non-full leaf
// No splits — just descend and add.
#let t1 = b24.node((10, 20), b24.leaf(3, 7), b24.leaf(15), b24.leaf(25, 30))
#starling.stacked(b24.insert-display(t1, 5))

#pagebreak()

== Top-down: descent triggers a child pre-split
// Left leaf is full [1, 3, 5]; insert 2 → pre-split [1] | 3 | [5],
// promote 3 to root, then insert 2 into [1].
#let t2 = b24.node(10, b24.leaf(1, 3, 5), b24.leaf(15, 20))
#starling.stacked(b24.insert-display(t2, 2))

#pagebreak()

== Top-down: root pre-split + child pre-split cascade
// Root is full and the descent target is also full — both
// preemptive splits happen before reaching the leaf.
#let t3 = b24.node(
  (10, 20, 30),
  b24.leaf(3, 7),
  b24.leaf(15),
  b24.leaf(25),
  b24.leaf(35, 40, 50),
)
#starling.stacked(b24.insert-display(t3, 45))

#pagebreak()

== Bottom-up: insert into a non-full leaf
// Same fixture as the first top-down test for comparison.
#starling.stacked(b24.insert-display(t1, 5, strategy: "bottom-up"))

#pagebreak()

== Bottom-up: overflow at the leaf, single split
// Insert 2 into [1, 3, 5] gives [1, 2, 3, 5] overflow; split at
// index 2 → [1, 2] | 3 | [5].
#starling.stacked(b24.insert-display(t2, 2, strategy: "bottom-up"))

#pagebreak()

== Bottom-up: overflow cascades through the root
// Both the leaf and the (already-full) root overflow on insert.
#starling.stacked(b24.insert-display(t3, 45, strategy: "bottom-up"))
