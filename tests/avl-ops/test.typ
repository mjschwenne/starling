// Assertion-style test for the AVL tree's pure operations, path utilities,
// factory forms, and the height bookkeeping every mutation has to keep true.
#import "/src/lib.typ": avl, result

// --- hand-built fixture --------------------------------------------
// Balanced AVL tree (heights fall out of the literal builders):
//         4 (h=3)
//        /     \
//       2       6 (h=2)
//      / \       \
//     1   3       7 (h=1)
#let t = avl.node(
  4,
  avl.node(2, avl.leaf(1), avl.leaf(3)),
  avl.node(6, none, avl.leaf(7)),
)

#assert(avl.check-invariants(t))
#assert.eq(
  avl.describe(t),
  "4:3 (left: 2:2 (left: 1:1, right: 3:1), right: 6:2 (left: empty, right: 7:1))",
)

// The literal builders compute heights, so a hand-built tree is as
// trustworthy as one grown by `insert` — no reimplemented recursion.
#assert.eq(t.height, 3)
#assert.eq(avl.resolve(t, "R").height, 2)
#assert.eq(avl.leaf(9).height, 1)

// `height:` is the escape hatch for a tree caught mid-operation, which is
// what `fixup-display` animates: a leaf grafted on, nothing recomputed yet.
#let stale = avl.node(4, avl.node(2, none, avl.leaf(3), height: 1), none, height: 2)
#assert.eq(stale.height, 2)
#assert.eq(avl.balance-factor(stale, ""), "+1") // the stale factor
#assert.eq(avl.balance-factor(t, ""), "0")
// `str(-1)` is a Unicode minus, not a hyphen — the tag matches whatever
// Typst renders, so compare against `str` rather than a typed literal.
#assert.eq(avl.balance-factor(t, "R"), str(-1))
#assert.eq(avl.balance-factor(t, "L"), "0")

// --- contains -------------------------------------------------------
#assert(avl.contains(t, 4))
#assert(avl.contains(t, 1))
#assert(avl.contains(t, 3))
#assert(avl.contains(t, 7))
#assert(not avl.contains(t, 5))
#assert(not avl.contains(t, 0))

// --- path utilities -------------------------------------------------
#assert.eq(avl.by-value(t, 3), "LR")
#assert.eq(avl.path-to(t, 3), ("", "L", "LR"))
#assert.eq(avl.resolve(t, "L").value, 2)
#assert.eq(avl.resolve(t, "RRR"), none)

// --- traversal orders ----------------------------------------------
#let values-of(tree, paths) = paths.map(p => avl.resolve(tree, p).value)
#assert.eq(values-of(t, avl.in-order(t)), (1, 2, 3, 4, 6, 7))
#assert.eq(values-of(t, avl.pre-order(t)), (4, 2, 1, 3, 6, 7))
#assert.eq(values-of(t, avl.post-order(t)), (1, 3, 2, 7, 6, 4))
#assert.eq(values-of(t, avl.level-order(t)), (4, 2, 6, 1, 3, 7))

// --- imbalance classification ---------------------------------------
#assert.eq(avl.imbalance-case(t), none)
#assert.eq(avl.imbalance-case(avl.node(3, avl.node(2, avl.leaf(1), none), none)), "LL")
#assert.eq(avl.imbalance-case(avl.node(3, avl.node(1, none, avl.leaf(2)), none)), "LR")
#assert.eq(avl.imbalance-case(avl.node(1, none, avl.node(2, none, avl.leaf(3)))), "RR")
#assert.eq(avl.imbalance-case(avl.node(1, none, avl.node(3, avl.leaf(2), none))), "RL")

// --- insert keeps invariants ---------------------------------------
#let t-ins = avl.insert(t, 5)
#assert(avl.check-invariants(t-ins))
#assert(avl.contains(t-ins, 5))

// Inserting 0 triggers an LL fix-up at node 2.
#let t-ll = avl.insert(t, 0)
#assert(avl.check-invariants(t-ll))
#assert(avl.contains(t-ll, 0))

// Sequential ascending inserts — worst-case rotation cascade.
#let t-asc = avl.insert-many(avl.leaf(1), 2, 3, 4, 5, 6, 7, 8, 9, 10)
#assert(avl.check-invariants(t-asc))
#assert.eq(values-of(t-asc, avl.in-order(t-asc)), (1, 2, 3, 4, 5, 6, 7, 8, 9, 10))

// Sequential descending inserts.
#let t-desc = avl.insert-many(avl.leaf(10), 9, 8, 7, 6, 5, 4, 3, 2, 1)
#assert(avl.check-invariants(t-desc))
#assert.eq(values-of(t-desc, avl.in-order(t-desc)), (1, 2, 3, 4, 5, 6, 7, 8, 9, 10))

// Mixed inserts — zigzag insertions trigger LR/RL cases.
#let t-mix = avl.insert-many(
  avl.leaf(50),
  25, 75, 12, 37, 62, 87, 6, 18, 30, 43, 56, 68, 81, 93,
)
#assert(avl.check-invariants(t-mix))

// --- delete keeps invariants ---------------------------------------
// Delete leaf.
#let t-d1 = avl.delete(t, 1)
#assert(avl.check-invariants(t-d1))
#assert(not avl.contains(t-d1, 1))

// Delete root with two children.
#let t-d4 = avl.delete(t, 4)
#assert(avl.check-invariants(t-d4))
#assert(not avl.contains(t-d4, 4))

// Delete internal node with one child.
#let t-d6 = avl.delete(t, 6)
#assert(avl.check-invariants(t-d6))
#assert(not avl.contains(t-d6, 6))

// Delete every value from a tree of consecutive inserts, in reverse of
// insertion order. The tree must stay balanced after every step and end up
// with the correct remaining membership.
#let t-many = avl.insert-many(avl.leaf(8), 4, 12, 2, 6, 10, 14, 1, 3, 5, 7, 9, 11, 13, 15)
#let tt = t-many
#for v in (15, 13, 11, 9, 7, 5, 3, 1, 14, 10, 6, 2, 12, 4) {
  tt = avl.delete(tt, v)
  if tt != none { assert(avl.check-invariants(tt)) }
}
// Only the root (value 8) should remain.
#assert(tt != none and tt.value == 8 and tt.left == none and tt.right == none)

// Delete from a single-node tree leaves none.
#assert.eq(avl.delete(avl.leaf(42), 42), none)

// Deleting a value that isn't present is a no-op.
#let t-nop = avl.delete(t, 999)
#assert(avl.check-invariants(t-nop))
#assert.eq(avl.describe(t-nop), avl.describe(t))

// --- rotate is structural (BST order preserved) --------------------
// `rotate` is a structural primitive — it does NOT enforce the AVL
// invariant, only search-tree order, and refreshes the rotated heights.
#let t-rot = avl.rotate(t, avl.resolve(t, "R"))
#assert(avl.contains(t-rot, 4))
#assert(avl.contains(t-rot, 7))
// In-order traversal is invariant under any rotation.
#assert.eq(values-of(t-rot, avl.in-order(t-rot)), (1, 2, 3, 4, 6, 7))
// New root is the rotated-up child.
#assert.eq(t-rot.value, 6)

// --- avl.new(..) factory --------------------------------------------
#let tf = avl.new(4, 2, 6, 1, 3, 7)
#assert(avl.check-invariants(tf))
#assert.eq(avl.describe(tf), avl.describe(t))
#assert.eq(avl.describe(avl.new(4)), "4:1")

// Tuple form for labels.
#let tfl = avl.new((4, "four"), 2, (6, "six"))
#assert.eq(tfl.label, "four")
#assert.eq(avl.resolve(tfl, avl.by-value(tfl, 6)).label, "six")
#assert.eq(avl.resolve(tfl, avl.by-value(tfl, 2)).label, auto)

// --- the traces agree with the pure operations ----------------------
// insert-display and delete-display re-derive the rebalancing to emit one
// frame per step; `step.result` is what proves the two implementations
// still agree.
#assert.eq(avl.describe(result(avl.insert-display(t, 5))), avl.describe(t-ins))
#assert.eq(avl.describe(result(avl.insert-display(t, 0))), avl.describe(t-ll))
#assert.eq(avl.describe(result(avl.delete-display(t, 1))), avl.describe(t-d1))
#assert.eq(avl.describe(result(avl.delete-display(t, 4, search: true))), avl.describe(t-d4))
#assert.eq(avl.describe(result(avl.delete-display(t, 6))), avl.describe(t-d6))
#for v in (1, 2, 3, 4, 6, 7) {
  assert.eq(
    avl.describe(result(avl.delete-display(t-many, v))),
    avl.describe(avl.delete(t-many, v)),
  )
  assert.eq(
    avl.describe(result(avl.insert-display(t-many, v * 10))),
    avl.describe(avl.insert(t-many, v * 10)),
  )
}
// Deleting the last node leaves nothing behind.
#assert.eq(result(avl.delete-display(avl.leaf(5), 5)), none)
// A search, traversal, or static display leaves the tree alone.
#assert.eq(result(avl.search-display(t, 3)), t)
#assert.eq(result(avl.post-order-display(t)), t)
#assert.eq(result(avl.display(t)), t)
// A rotation's result is the rotated tree.
#assert.eq(
  avl.describe(result(avl.rotate-display(t, avl.resolve(t, "R")))),
  avl.describe(t-rot),
)

// The search terminal frame reports the outcome rather than another compare.
#assert.eq(avl.search-display(t, 3).last().step.kind, "found")
#assert.eq(avl.search-display(t, 5).last().step.kind, "not-found")
#assert.eq(avl.display(t).first().step.kind, "static")

// --- the style vocabulary returns ops ------------------------------
#assert.eq(avl.unbalanced("L", "R").len(), 2)
#assert.eq(avl.unbalanced("").first().op, "style-node")
#assert(not ("note" in avl.unbalanced("").first().style))
#assert.eq(avl.unbalanced("", case: "LR").first().style.note, "LR")
