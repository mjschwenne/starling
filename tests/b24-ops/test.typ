#import "/src/lib.typ": B24, b24

// Hand-built tree:
//
//          [10, 20]
//         /    |    \
//    [3, 7]  [15]  [25, 30]
//
// All leaves at depth 2.
#let leaf(..ks) = (B24.new)(
  keys: ks.pos(),
  labels: ks.pos().map(_ => auto),
  children: (),
)
#let t = (B24.new)(
  keys: (10, 20),
  labels: (auto, auto),
  children: (leaf(3, 7), leaf(15), leaf(25, 30)),
)
#assert.eq((t.check-invariants)(), none)

// contains: keys at every depth.
#assert((t.contains)(10))
#assert((t.contains)(20))
#assert((t.contains)(3))
#assert((t.contains)(7))
#assert((t.contains)(15))
#assert((t.contains)(25))
#assert((t.contains)(30))
#assert(not (t.contains)(0))
#assert(not (t.contains)(5))
#assert(not (t.contains)(12))
#assert(not (t.contains)(100))

// describe
#assert.eq(
  (t.describe)(),
  "[10, 20] (children: [3, 7], [15], [25, 30])",
)

// by-value: returns "<node-path>#<key-idx>".
#assert.eq((t.by-value)(10), "#0")
#assert.eq((t.by-value)(20), "#1")
#assert.eq((t.by-value)(7), "0#1")
#assert.eq((t.by-value)(15), "1#0")
#assert.eq((t.by-value)(25), "2#0")
#assert.eq((t.by-value)(30), "2#1")

// resolve: takes the node-path part (without the # suffix).
#assert.eq(((t.resolve)("0")).keys, (3, 7))
#assert.eq(((t.resolve)("")).keys, (10, 20))

// path-to: comparison sequence to reach 15.
#let p15 = (t.path-to)(15)
#assert.eq(p15.len(), 3)
#assert.eq(p15.at(0).cmp, "15 > 10")
#assert.eq(p15.at(1).cmp, "15 < 20")
#assert.eq(p15.at(2).cmp, "15 = 15")
#assert.eq(p15.last().found, true)

// === insert: top-down ============================================

// Insert 5 (no split needed). Goes into left leaf [3, 7] → [3, 5, 7].
#let t5 = (t.insert)(5, strategy: "top-down")
#assert.eq((t5.check-invariants)(), none)
#assert.eq(
  (t5.describe)(),
  "[10, 20] (children: [3, 5, 7], [15], [25, 30])",
)

// Insert 35 (no split needed). Goes into right leaf [25, 30] → [25, 30, 35].
#let t35 = (t.insert)(35, strategy: "top-down")
#assert.eq(
  (t35.describe)(),
  "[10, 20] (children: [3, 7], [15], [25, 30, 35])",
)

// Top-down preemptive split: after inserting 5 the left leaf is
// [3, 5, 7]; inserting 6 next requires splitting it. Promoted key
// is the middle (5), root becomes [5, 10, 20], 6 lands into the
// fresh sibling.
#let tfill = (((t.insert)(5)).insert)(6)
#assert.eq(
  (tfill.describe)(),
  "[5, 10, 20] (children: [3], [6, 7], [15], [25, 30])",
)
#assert.eq((tfill.check-invariants)(), none)

// Larger build to exercise multiple insertions and a root split.
#let rootful = b24(10, 5, 15, 1, 7, 12, 20, 25)
#assert.eq((rootful.check-invariants)(), none)
#for v in (10, 5, 15, 1, 7, 12, 20, 25) {
  assert((rootful.contains)(v))
}

// === insert: bottom-up produces a valid (but possibly differently-
//             shaped) tree containing the same keys.
//
// Top-down and bottom-up disagree whenever the inserted key falls in
// the upper half of an about-to-be-split node — top-down promotes
// the middle key of the pre-insert 3-node; bottom-up promotes the
// upper-middle key of the post-overflow 4-node, which may itself be
// the freshly inserted key. The sequence below exercises that
// divergence.

#let inputs = (10, 5, 15, 1, 7, 12, 20, 25, 30, 17, 19)
#let td-built = b24(..inputs)
#let bu-built = {
  let r = (B24.new)(keys: (inputs.first(),), labels: (auto,), children: ())
  for v in inputs.slice(1) {
    r = (r.insert)(v, strategy: "bottom-up")
  }
  r
}
#assert.eq((td-built.check-invariants)(), none)
#assert.eq((bu-built.check-invariants)(), none)

// Both contain the same keys. (Tree shapes legitimately differ.)
#for v in inputs {
  assert((td-built.contains)(v))
  assert((bu-built.contains)(v))
}

// Concrete shape sanity-check: the two trees are structurally
// distinct for this input.
#assert(
  (td-built.describe)() != (bu-built.describe)(),
  message: "td and bu unexpectedly produced the same tree — "
    + "the sequence no longer exercises the diverging split.",
)

// === delete: leaf with ≥ 2 keys is the simple case ===============

// Delete 7 from [3, 7]: leaf becomes [3], still 1 key (valid).
#let t-no-7 = (t.delete)(7, strategy: "top-down")
#assert.eq(
  (t-no-7.describe)(),
  "[10, 20] (children: [3], [15], [25, 30])",
)
#assert.eq((t-no-7.check-invariants)(), none)
#assert(not (t-no-7.contains)(7))

// Delete the second key from [25, 30] → [25].
#let t-no-30 = (t.delete)(30, strategy: "top-down")
#assert.eq(
  (t-no-30.describe)(),
  "[10, 20] (children: [3, 7], [15], [25])",
)

// === delete: internal key triggers predecessor swap ==============

// Delete 10 from root. Predecessor is 7 (rightmost-of-left subtree).
// Left child [3, 7] has 2 keys so we use the predecessor without
// merging. Result: root [7, 20], left leaf becomes [3].
#let t-no-10 = (t.delete)(10, strategy: "top-down")
#assert.eq(
  (t-no-10.describe)(),
  "[7, 20] (children: [3], [15], [25, 30])",
)
#assert.eq((t-no-10.check-invariants)(), none)
#assert(not (t-no-10.contains)(10))

// === delete: borrow from sibling =================================

// Delete 15 from the `t` tree. Target leaf [15] has 1 key — fix
// before removing. Both flanking siblings are rich; the top-down
// fixup prefers the left sibling, so [3, 7] donates its rightmost
// key: separator 10 slides down into the target, 7 slides up.
// After fixup the target leaf is [10, 15], descend, remove 15 → [10].
#let t-no-15 = (t.delete)(15, strategy: "top-down")
#assert.eq(
  (t-no-15.describe)(),
  "[7, 20] (children: [3], [10], [25, 30])",
)
#assert.eq((t-no-15.check-invariants)(), none)
#assert(not (t-no-15.contains)(15))

// Force a right-sibling borrow by making the left sibling 1-key.
#let right-borrow-fixture = (B24.new)(
  keys: (10,),
  labels: (auto,),
  children: (leaf(5), leaf(15, 20)),
)
#let rb = (right-borrow-fixture.delete)(5, strategy: "top-down")
#assert.eq((rb.describe)(), "[15] (children: [10], [20])")
#assert.eq((rb.check-invariants)(), none)

// === delete: merge (root collapses) ==============================

// 1-key root with two 1-key leaves: deleting any key forces a merge.
#let merge-fixture = (B24.new)(
  keys: (10,),
  labels: (auto,),
  children: (leaf(5), leaf(15)),
)
#assert.eq((merge-fixture.check-invariants)(), none)
#let merged = (merge-fixture.delete)(5, strategy: "top-down")
#assert.eq((merged.describe)(), "[10, 15]")
#assert.eq((merged.check-invariants)(), none)

// === delete: both strategies leave valid trees that still contain
//             the surviving keys (shapes may differ).

#let big = b24(10, 5, 15, 1, 7, 12, 20, 25, 30, 17, 19, 3, 8)
#let big-td = (big.delete)(10, strategy: "top-down")
#let big-bu = (big.delete)(10, strategy: "bottom-up")
#assert.eq((big-td.check-invariants)(), none)
#assert.eq((big-bu.check-invariants)(), none)
#assert(not (big-td.contains)(10))
#assert(not (big-bu.contains)(10))
#for v in (5, 15, 1, 7, 12, 20, 25, 30, 17, 19, 3, 8) {
  assert((big-td.contains)(v))
  assert((big-bu.contains)(v))
}

// === traversals ==================================================

// In-order: every key visited once in sorted order.
#let in-paths = (t.in-order)()
#let key-at(path) = {
  let parts = path.split("#")
  let node = (t.resolve)(parts.at(0))
  node.keys.at(int(parts.at(1)))
}
#assert.eq(in-paths.map(key-at), (3, 7, 10, 15, 20, 25, 30))

// Pre-order: root's keys first, then each child's pre-order.
#assert.eq(
  ((t.pre-order)()).map(key-at),
  (10, 20, 3, 7, 15, 25, 30),
)

// Post-order: each child's post-order first, then current node's keys.
#assert.eq(
  ((t.post-order)()).map(key-at),
  (3, 7, 15, 25, 30, 10, 20),
)

// Level-order: BFS over nodes, emitting each node's keys before
// queueing children.
#assert.eq(
  ((t.level-order)()).map(key-at),
  (10, 20, 3, 7, 15, 25, 30),
)

// === single-element trees ========================================

// Deleting the only key leaves an empty tree (surfaced as `none`).
#let single = b24(42)
#assert.eq((single.describe)(), "[42]")
#assert((single.contains)(42))
#assert.eq((single.delete)(42), none)

// === b24() constructor ===========================================

#let tf = b24(10, 5, 15, 1, 7, 12, 20, 25)
#assert.eq((tf.check-invariants)(), none)
#assert((tf.contains)(7))

// Tuple form for labels. After inserting (10, "ten"), 5, (15, "fifteen"),
// the root leaf is [5, 10, 15] with labels (auto, "ten", "fifteen").
#let tfl = b24((10, "ten"), 5, (15, "fifteen"))
#assert.eq(((tfl.resolve)("")).keys, (5, 10, 15))
#assert.eq(((tfl.resolve)("")).labels, (auto, "ten", "fifteen"))
#let label-at(tree, v) = {
  let parts = ((tree.by-value)(v)).split("#")
  ((tree.resolve)(parts.at(0))).labels.at(int(parts.at(1)))
}
#assert.eq(label-at(tfl, 10), "ten")
#assert.eq(label-at(tfl, 15), "fifteen")
#assert.eq(label-at(tfl, 5), auto)
