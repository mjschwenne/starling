// Assertion-style test for the 2-3-4 tree's pure operations, both
// rebalancing strategies, path utilities, and factory forms.
#import "/src/lib.typ": b24, result

// Hand-built tree:
//
//          [10, 20]
//         /    |    \
//    [3, 7]  [15]  [25, 30]
//
// All leaves at depth 2.
#let t = b24.node((10, 20), b24.leaf(3, 7), b24.leaf(15), b24.leaf(25, 30))
#assert(b24.check-invariants(t))

// contains: keys at every depth.
#assert(b24.contains(t, 10))
#assert(b24.contains(t, 20))
#assert(b24.contains(t, 3))
#assert(b24.contains(t, 7))
#assert(b24.contains(t, 15))
#assert(b24.contains(t, 25))
#assert(b24.contains(t, 30))
#assert(not b24.contains(t, 0))
#assert(not b24.contains(t, 5))
#assert(not b24.contains(t, 12))
#assert(not b24.contains(t, 100))

// describe
#assert.eq(b24.describe(t), "[10, 20] (children: [3, 7], [15], [25, 30])")

// by-value: returns "<node-path>#<key-idx>".
#assert.eq(b24.by-value(t, 10), "#0")
#assert.eq(b24.by-value(t, 20), "#1")
#assert.eq(b24.by-value(t, 7), "0#1")
#assert.eq(b24.by-value(t, 15), "1#0")
#assert.eq(b24.by-value(t, 25), "2#0")
#assert.eq(b24.by-value(t, 30), "2#1")

// resolve: takes the node-path part (without the # suffix).
#assert.eq(b24.resolve(t, "0").keys, (3, 7))
#assert.eq(b24.resolve(t, "").keys, (10, 20))

// path-to: comparison sequence to reach 15.
#let p15 = b24.path-to(t, 15)
#assert.eq(p15.len(), 3)
#assert.eq(p15.at(0).cmp, "15 > 10")
#assert.eq(p15.at(1).cmp, "15 < 20")
#assert.eq(p15.at(2).cmp, "15 = 15")
#assert.eq(p15.last().found, true)

// The literal builders check arity, so a malformed tree can't be written
// down by accident.
#assert.eq(b24.leaf(3, 7).children, ())
#assert.eq(b24.node(10, b24.leaf(5), b24.leaf(15)).children.len(), 2)

// === insert: top-down ============================================

// Insert 5 (no split needed). Goes into left leaf [3, 7] → [3, 5, 7].
#let t5 = b24.insert(t, 5, strategy: "top-down")
#assert(b24.check-invariants(t5))
#assert.eq(b24.describe(t5), "[10, 20] (children: [3, 5, 7], [15], [25, 30])")

// Insert 35 (no split needed). Goes into right leaf [25, 30] → [25, 30, 35].
#let t35 = b24.insert(t, 35, strategy: "top-down")
#assert.eq(b24.describe(t35), "[10, 20] (children: [3, 7], [15], [25, 30, 35])")

// Top-down preemptive split: after inserting 5 the left leaf is
// [3, 5, 7]; inserting 6 next requires splitting it. The promoted key is
// the middle (5), the root becomes [5, 10, 20], and 6 lands in the fresh
// sibling.
#let tfill = b24.insert(b24.insert(t, 5), 6)
#assert.eq(b24.describe(tfill), "[5, 10, 20] (children: [3], [6, 7], [15], [25, 30])")
#assert(b24.check-invariants(tfill))

// Larger build to exercise multiple insertions and a root split.
#let rootful = b24.new(10, 5, 15, 1, 7, 12, 20, 25)
#assert(b24.check-invariants(rootful))
#for v in (10, 5, 15, 1, 7, 12, 20, 25) { assert(b24.contains(rootful, v)) }

// === insert: bottom-up produces a valid (but possibly differently-
//             shaped) tree containing the same keys.
//
// Top-down and bottom-up disagree whenever the inserted key falls in the
// upper half of an about-to-be-split node — top-down promotes the middle
// key of the pre-insert 3-node; bottom-up promotes the upper-middle key of
// the post-overflow 4-node, which may itself be the freshly inserted key.
// The sequence below exercises that divergence.

#let inputs = (10, 5, 15, 1, 7, 12, 20, 25, 30, 17, 19)
#let td-built = b24.new(..inputs)
#let bu-built = {
  let r = b24.leaf(inputs.first())
  for v in inputs.slice(1) { r = b24.insert(r, v, strategy: "bottom-up") }
  r
}
#assert(b24.check-invariants(td-built))
#assert(b24.check-invariants(bu-built))

// Both contain the same keys. (Tree shapes legitimately differ.)
#for v in inputs {
  assert(b24.contains(td-built, v))
  assert(b24.contains(bu-built, v))
}

// Concrete shape sanity-check: the two trees are structurally distinct for
// this input.
#assert(
  b24.describe(td-built) != b24.describe(bu-built),
  message: "td and bu unexpectedly produced the same tree — "
    + "the sequence no longer exercises the diverging split.",
)

// === delete: leaf with ≥ 2 keys is the simple case ===============

// Delete 7 from [3, 7]: the leaf becomes [3], still 1 key (valid).
#let t-no-7 = b24.delete(t, 7, strategy: "top-down")
#assert.eq(b24.describe(t-no-7), "[10, 20] (children: [3], [15], [25, 30])")
#assert(b24.check-invariants(t-no-7))
#assert(not b24.contains(t-no-7, 7))

// Delete the second key from [25, 30] → [25].
#let t-no-30 = b24.delete(t, 30, strategy: "top-down")
#assert.eq(b24.describe(t-no-30), "[10, 20] (children: [3, 7], [15], [25])")

// === delete: internal key triggers predecessor swap ==============

// Delete 10 from the root. The predecessor is 7 (rightmost of the left
// subtree). The left child [3, 7] has 2 keys, so the predecessor can be
// used without merging. Result: root [7, 20], left leaf [3].
#let t-no-10 = b24.delete(t, 10, strategy: "top-down")
#assert.eq(b24.describe(t-no-10), "[7, 20] (children: [3], [15], [25, 30])")
#assert(b24.check-invariants(t-no-10))
#assert(not b24.contains(t-no-10, 10))

// === delete: borrow from sibling =================================

// Delete 15. The target leaf [15] has 1 key — fix before removing. Both
// flanking siblings are rich; the top-down fixup prefers the left, so
// [3, 7] donates its rightmost key: separator 10 slides down into the
// target and 7 slides up. The target is then [10, 15]; remove 15 → [10].
#let t-no-15 = b24.delete(t, 15, strategy: "top-down")
#assert.eq(b24.describe(t-no-15), "[7, 20] (children: [3], [10], [25, 30])")
#assert(b24.check-invariants(t-no-15))
#assert(not b24.contains(t-no-15, 15))

// Force a right-sibling borrow by making the left sibling 1-key.
#let rb = b24.delete(
  b24.node(10, b24.leaf(5), b24.leaf(15, 20)),
  5,
  strategy: "top-down",
)
#assert.eq(b24.describe(rb), "[15] (children: [10], [20])")
#assert(b24.check-invariants(rb))

// === delete: merge (root collapses) ==============================

// 1-key root with two 1-key leaves: deleting any key forces a merge.
#let merge-fixture = b24.node(10, b24.leaf(5), b24.leaf(15))
#assert(b24.check-invariants(merge-fixture))
#let merged = b24.delete(merge-fixture, 5, strategy: "top-down")
#assert.eq(b24.describe(merged), "[10, 15]")
#assert(b24.check-invariants(merged))

// === delete: both strategies leave valid trees that still contain
//             the surviving keys (shapes may differ).

#let big = b24.new(10, 5, 15, 1, 7, 12, 20, 25, 30, 17, 19, 3, 8)
#let big-td = b24.delete(big, 10, strategy: "top-down")
#let big-bu = b24.delete(big, 10, strategy: "bottom-up")
#assert(b24.check-invariants(big-td))
#assert(b24.check-invariants(big-bu))
#assert(not b24.contains(big-td, 10))
#assert(not b24.contains(big-bu, 10))
#for v in (5, 15, 1, 7, 12, 20, 25, 30, 17, 19, 3, 8) {
  assert(b24.contains(big-td, v))
  assert(b24.contains(big-bu, v))
}

// === traversals ==================================================

#let key-at(path) = {
  let parts = path.split("#")
  b24.resolve(t, parts.at(0)).keys.at(int(parts.at(1)))
}

// In-order: every key visited once, in sorted order.
#assert.eq(b24.in-order(t).map(key-at), (3, 7, 10, 15, 20, 25, 30))
// Pre-order: the root's keys first, then each child's pre-order.
#assert.eq(b24.pre-order(t).map(key-at), (10, 20, 3, 7, 15, 25, 30))
// Post-order: each child's post-order first, then the node's own keys.
#assert.eq(b24.post-order(t).map(key-at), (3, 7, 15, 25, 30, 10, 20))
// Level-order: BFS over nodes, emitting each node's keys before queueing.
#assert.eq(b24.level-order(t).map(key-at), (10, 20, 3, 7, 15, 25, 30))

// === single-element trees ========================================

// Deleting the only key leaves an empty tree (surfaced as `none`).
#let single = b24.new(42)
#assert.eq(b24.describe(single), "[42]")
#assert(b24.contains(single, 42))
#assert.eq(b24.delete(single, 42), none)

// === b24.new(..) constructor =====================================

#let tf = b24.new(10, 5, 15, 1, 7, 12, 20, 25)
#assert(b24.check-invariants(tf))
#assert(b24.contains(tf, 7))

// Tuple form for labels. After inserting (10, "ten"), 5, (15, "fifteen"),
// the root leaf is [5, 10, 15] with labels (auto, "ten", "fifteen").
#let tfl = b24.new((10, "ten"), 5, (15, "fifteen"))
#assert.eq(b24.resolve(tfl, "").keys, (5, 10, 15))
#assert.eq(b24.resolve(tfl, "").labels, (auto, "ten", "fifteen"))
#let label-at(tree, v) = {
  let parts = b24.by-value(tree, v).split("#")
  b24.resolve(tree, parts.at(0)).labels.at(int(parts.at(1)))
}
#assert.eq(label-at(tfl, 10), "ten")
#assert.eq(label-at(tfl, 15), "fifteen")
#assert.eq(label-at(tfl, 5), auto)

// The literal builders take the same `(key, label)` pairs.
#assert.eq(b24.leaf((3, "three"), 7).labels, ("three", auto))

// === displays stamp their result =================================

// Every display's final frame carries the tree the operation produced, so
// an animation and the state it advances to are written once, not twice.
#for strategy in ("top-down", "bottom-up") {
  for v in (5, 6, 35, 12) {
    assert.eq(
      b24.describe(result(b24.insert-display(t, v, strategy: strategy))),
      b24.describe(b24.insert(t, v, strategy: strategy)),
    )
  }
  for v in (7, 10, 15, 30) {
    assert.eq(
      b24.describe(result(b24.delete-display(t, v, strategy: strategy))),
      b24.describe(b24.delete(t, v, strategy: strategy)),
    )
  }
}
// Deleting the last key leaves nothing behind.
#assert.eq(result(b24.delete-display(single, 42)), none)
// A search, traversal, or static display leaves the tree alone.
#assert.eq(result(b24.search-display(t, 15)), t)
#assert.eq(result(b24.in-order-display(t)), t)
#assert.eq(result(b24.display(t)), t)

// The search terminal frame reports the outcome rather than another compare.
#assert.eq(b24.search-display(t, 15).last().step.kind, "found")
#assert.eq(b24.search-display(t, 8).last().step.kind, "not-found")
#assert.eq(b24.display(t).first().step.kind, "static")

// `search: false` drops the descent entirely — no comparison frames.
#assert(
  b24.delete-display(t, 10, search: false).all(f => f.step.kind != "compare"),
)
#assert(b24.delete-display(t, 10).any(f => f.step.kind == "compare"))
