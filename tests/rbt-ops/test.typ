// Assertion-style test for the red-black tree's pure operations, path
// utilities, factory forms, and the invariants every mutation restores.
#import "/src/lib.typ": rbt, result

// --- hand-built fixture --------------------------------------------
// Valid RB tree:
//         4B
//        /  \
//       2R   7B
//      /  \
//     1B   3B
#let t = rbt.black(4, rbt.red(2, rbt.black(1), rbt.black(3)), rbt.black(7))

#assert(rbt.check-invariants(t))
#assert.eq(rbt.describe(t), "4 B (left: 2 R (left: 1 B, right: 3 B), right: 7 B)")

// --- contains -------------------------------------------------------
#assert(rbt.contains(t, 4))
#assert(rbt.contains(t, 1))
#assert(rbt.contains(t, 3))
#assert(rbt.contains(t, 7))
#assert(not rbt.contains(t, 5))
#assert(not rbt.contains(t, 0))

// --- path utilities -------------------------------------------------
#assert.eq(rbt.by-value(t, 3), "LR")
#assert.eq(rbt.path-to(t, 3), ("", "L", "LR"))
#assert.eq(rbt.resolve(t, "L").value, 2)
#assert.eq(rbt.resolve(t, "RRR"), none)

// --- traversal orders ----------------------------------------------
#let values-of(tree, paths) = paths.map(p => rbt.resolve(tree, p).value)
#assert.eq(values-of(t, rbt.in-order(t)), (1, 2, 3, 4, 7))
#assert.eq(values-of(t, rbt.pre-order(t)), (4, 2, 1, 3, 7))
#assert.eq(values-of(t, rbt.post-order(t)), (1, 3, 2, 7, 4))
#assert.eq(values-of(t, rbt.level-order(t)), (4, 2, 7, 1, 3))

// --- insert keeps invariants ---------------------------------------
#let t-ins = rbt.insert(t, 5)
#assert(rbt.check-invariants(t-ins))
#assert(rbt.contains(t-ins, 5))

// Insert a duplicate (goes left, like BST).
#assert(rbt.check-invariants(rbt.insert(t, 2)))

// Sequential ascending inserts — worst case for a naive BST, fine for RB.
#let t-asc = rbt.insert-many(rbt.black(1), 2, 3, 4, 5, 6, 7, 8, 9, 10)
#assert(rbt.check-invariants(t-asc))
#assert.eq(values-of(t-asc, rbt.in-order(t-asc)), (1, 2, 3, 4, 5, 6, 7, 8, 9, 10))

// Sequential descending inserts.
#let t-desc = rbt.insert-many(rbt.black(10), 9, 8, 7, 6, 5, 4, 3, 2, 1)
#assert(rbt.check-invariants(t-desc))
#assert.eq(values-of(t-desc, rbt.in-order(t-desc)), (1, 2, 3, 4, 5, 6, 7, 8, 9, 10))

// Mixed inserts.
#let t-mix = rbt.insert-many(
  rbt.black(50),
  25, 75, 12, 37, 62, 87, 6, 18, 30, 43, 56, 68, 81, 93,
)
#assert(rbt.check-invariants(t-mix))

// --- delete keeps invariants ---------------------------------------
// Delete leaf.
#let t-d1 = rbt.delete(t, 1)
#assert(rbt.check-invariants(t-d1))
#assert(not rbt.contains(t-d1, 1))

// Delete root with two children.
#let t-d4 = rbt.delete(t, 4)
#assert(rbt.check-invariants(t-d4))
#assert(not rbt.contains(t-d4, 4))

// Delete internal node with two children (mid-tree).
#let t-d2 = rbt.delete(t, 2)
#assert(rbt.check-invariants(t-d2))
#assert(not rbt.contains(t-d2, 2))

// Delete black sibling case.
#let t-d7 = rbt.delete(t, 7)
#assert(rbt.check-invariants(t-d7))
#assert(not rbt.contains(t-d7, 7))

// Delete the root of a single-node tree → none.
#assert.eq(rbt.delete(rbt.black(5), 5), none)

// Deleting a missing value is a no-op.
#assert.eq(rbt.describe(rbt.delete(t, 99)), rbt.describe(t))

// Stress: build, delete every value, rebuild, delete some, check invariants
// at every step.
#let stress = rbt.insert-many(
  rbt.black(50),
  25, 75, 12, 37, 62, 87, 6, 18, 30, 43, 56, 68, 81, 93,
)
#let after-d = stress
#for v in (50, 25, 87, 6, 43, 75, 30) {
  after-d = rbt.delete(after-d, v)
  assert(rbt.check-invariants(after-d))
  assert(not rbt.contains(after-d, v))
}

// Delete-then-reinsert: invariants still hold, every value queryable.
#let cycled = rbt.insert-many(after-d, 50, 25, 87, 6, 43, 75, 30)
#assert(rbt.check-invariants(cycled))
#for v in (50, 25, 87, 6, 43, 75, 30) {
  assert(rbt.contains(cycled, v))
}

// Insert-then-delete every value individually from a fresh tree.
#for to-remove in (12, 37, 62, 81, 93, 18, 56) {
  let one-removed = rbt.delete(stress, to-remove)
  assert(rbt.check-invariants(one-removed))
  assert(not rbt.contains(one-removed, to-remove))
  // Every other value still present.
  for keep in (50, 25, 75, 12, 37, 62, 87, 6, 18, 30, 43, 56, 68, 81, 93) {
    if keep != to-remove {
      assert(
        rbt.contains(one-removed, keep),
        message: "lost " + str(keep) + " after deleting " + str(to-remove),
      )
    }
  }
}

// --- rotate: structural, preserves per-node colors -----------------
// Rotate around 2 (left child of root). 2 was red, 4 was black.
#let rt = rbt.rotate(t, t.left)
#assert.eq(rt.value, 2)
#assert.eq(rt.red, true) // 2 kept its color
#assert.eq(rt.right.value, 4)
#assert.eq(rt.right.red, false) // 4 kept its color

// Rotate around a non-direct-child node: t.left.right = 3 at path "LR".
#let rt2 = rbt.rotate(t, t.left.right)
#assert.eq(rbt.resolve(rt2, "L").value, 3)
#assert.eq(rbt.resolve(rt2, "LL").value, 2)

// --- label preservation --------------------------------------------
#let tl = rbt.insert(rbt.black(10), 5, label: "five")
#assert.eq(rbt.resolve(tl, rbt.by-value(tl, 5)).label, "five")

// Insert more, label still reachable.
#let tl1 = rbt.insert-many(tl, 3, 7, 1, 8)
#assert(rbt.check-invariants(tl1))
#assert.eq(rbt.resolve(tl1, rbt.by-value(tl1, 5)).label, "five")

// Two-children delete: the predecessor's label travels with its value.
// BST and RBT delete the same way — replace with the in-order predecessor
// (rightmost of the left subtree).
#let lbl = rbt.black(5, rbt.red(3, label: "three"), rbt.red(8))
#let lbl-del = rbt.delete(lbl, 5)
#assert(rbt.check-invariants(lbl-del))
#assert.eq(lbl-del.value, 3)
#assert.eq(lbl-del.label, "three")

// --- rbt.new(..) factory --------------------------------------------
// First arg = black root; the rest are inserted in order (so the CLRS
// fix-ups run and the result is a valid RB tree).
#let rf = rbt.new(8, 4, 12, 2, 6, 10, 14, 1)
#assert(rbt.check-invariants(rf))
#assert.eq(
  rbt.describe(rf),
  rbt.describe(rbt.insert-many(rbt.black(8), 4, 12, 2, 6, 10, 14, 1)),
)
#assert.eq(rf.red, false)

// Single-arg = root only.
#assert.eq(rbt.describe(rbt.new(8)), "8 B")

// Tuple form for labels.
#let rfl = rbt.new((8, "eight"), 4, (12, "twelve"))
#assert.eq(rfl.label, "eight")
#assert.eq(rbt.resolve(rfl, rbt.by-value(rfl, 12)).label, "twelve")
#assert.eq(rbt.resolve(rfl, rbt.by-value(rfl, 4)).label, auto)

// --- displays stamp their result -----------------------------------
// Every display's final frame carries the tree the operation produced, so an
// animation and the state it advances to are written once, not twice.
#assert.eq(rbt.describe(result(rbt.insert-display(t, 5))), rbt.describe(t-ins))
#assert.eq(rbt.describe(result(rbt.delete-display(t, 7))), rbt.describe(t-d7))
#assert.eq(
  rbt.describe(result(rbt.delete-display(t, 1, search: true))),
  rbt.describe(t-d1),
)
// Deleting the last node leaves nothing behind.
#assert.eq(result(rbt.delete-display(rbt.black(5), 5)), none)
// A search or traversal leaves the tree alone, so its result is the input.
#assert.eq(result(rbt.search-display(t, 3)), t)
#assert.eq(result(rbt.level-order-display(t)), t)
#assert.eq(result(rbt.display(t)), t)

// The search terminal frame reports the outcome rather than another compare.
#assert.eq(rbt.search-display(t, 3).last().step.kind, "found")
#assert.eq(rbt.search-display(t, 5).last().step.kind, "not-found")
#assert.eq(rbt.display(t).first().step.kind, "static")

// --- the style vocabulary returns ops ------------------------------
// Each helper is variadic over paths and yields one op per path, so they
// compose with `+` and drop into `apply-ops`.
#assert.eq(rbt.paint-red("L", "LR").len(), 2)
#assert.eq(rbt.paint-black("").first().op, "style-node")
// A double-black marks the node and its incoming edge.
#assert.eq(rbt.double-black("L").map(o => o.op), ("style-node", "style-edge"))
