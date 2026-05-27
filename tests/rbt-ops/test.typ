#import "/src/lib.typ": RBT

// --- helpers --------------------------------------------------------
#let bleaf(v, label: auto) = (RBT.new)(
  value: v,
  label: label,
  red: false,
  left: none,
  right: none,
)
#let rleaf(v, label: auto) = (RBT.new)(
  value: v,
  label: label,
  red: true,
  left: none,
  right: none,
)
#let bnode(v, l, r, label: auto) = (RBT.new)(
  value: v,
  label: label,
  red: false,
  left: l,
  right: r,
)
#let rnode(v, l, r, label: auto) = (RBT.new)(
  value: v,
  label: label,
  red: true,
  left: l,
  right: r,
)

// --- hand-built fixture --------------------------------------------
// Valid RB tree:
//         4B
//        /  \
//       2R   7B
//      /  \
//     1B   3B
#let t = bnode(4, rnode(2, bleaf(1), bleaf(3)), bleaf(7))

#assert((t.check-invariants)())
#assert.eq((t.describe)(), "4B (left: 2R (left: 1B, right: 3B), right: 7B)")

// --- contains -------------------------------------------------------
#assert((t.contains)(4))
#assert((t.contains)(1))
#assert((t.contains)(3))
#assert((t.contains)(7))
#assert(not (t.contains)(5))
#assert(not (t.contains)(0))

// --- path utilities -------------------------------------------------
#assert.eq((t.by-value)(3), "LR")
#assert.eq((t.path-to)(3), ("", "L", "LR"))
#assert.eq(((t.resolve)("L")).value, 2)
#assert.eq((t.resolve)("RRR"), none)

// --- traversal orders ----------------------------------------------
#let values-of(tree, paths) = paths.map(p => ((tree.resolve)(p)).value)
#assert.eq(values-of(t, (t.in-order)()), (1, 2, 3, 4, 7))
#assert.eq(values-of(t, (t.pre-order)()), (4, 2, 1, 3, 7))
#assert.eq(values-of(t, (t.post-order)()), (1, 3, 2, 7, 4))
#assert.eq(values-of(t, (t.level-order)()), (4, 2, 7, 1, 3))

// --- insert keeps invariants ---------------------------------------
#let t-ins = (t.insert)(5)
#assert((t-ins.check-invariants)())
#assert((t-ins.contains)(5))

// Insert a duplicate (goes left, like BST).
#let t-dup = (t.insert)(2)
#assert((t-dup.check-invariants)())

// Sequential ascending inserts — worst case for naive BST, fine for RB.
#let t-asc = (bleaf(1).insert-many)(2, 3, 4, 5, 6, 7, 8, 9, 10)
#assert((t-asc.check-invariants)())
#assert.eq(values-of(t-asc, (t-asc.in-order)()), (1, 2, 3, 4, 5, 6, 7, 8, 9, 10))

// Sequential descending inserts.
#let t-desc = (bleaf(10).insert-many)(9, 8, 7, 6, 5, 4, 3, 2, 1)
#assert((t-desc.check-invariants)())
#assert.eq(values-of(t-desc, (t-desc.in-order)()), (1, 2, 3, 4, 5, 6, 7, 8, 9, 10))

// Mixed inserts.
#let t-mix = (bleaf(50).insert-many)(25, 75, 12, 37, 62, 87, 6, 18, 30, 43, 56, 68, 81, 93)
#assert((t-mix.check-invariants)())

// --- delete keeps invariants ---------------------------------------
// Delete leaf.
#let t-d1 = (t.delete)(1)
#assert((t-d1.check-invariants)())
#assert(not (t-d1.contains)(1))

// Delete root with two children.
#let t-d4 = (t.delete)(4)
#assert((t-d4.check-invariants)())
#assert(not (t-d4.contains)(4))

// Delete internal node with two children (mid-tree).
#let t-d2 = (t.delete)(2)
#assert((t-d2.check-invariants)())
#assert(not (t-d2.contains)(2))

// Delete black sibling case.
#let t-d7 = (t.delete)(7)
#assert((t-d7.check-invariants)())
#assert(not (t-d7.contains)(7))

// Delete root of single-node tree → none.
#assert.eq((bleaf(5).delete)(5), none)

// Deleting a missing value is a no-op.
#let t-miss = (t.delete)(99)
#assert.eq((t-miss.describe)(), (t.describe)())

// Stress: build, delete every value, rebuild, delete some, check invariants
// at every step.
#let stress = (bleaf(50).insert-many)(25, 75, 12, 37, 62, 87, 6, 18, 30, 43, 56, 68, 81, 93)
#let after-d = stress
#for v in (50, 25, 87, 6, 43, 75, 30) {
  after-d = (after-d.delete)(v)
  assert((after-d.check-invariants)())
  assert(not (after-d.contains)(v))
}

// Delete-then-reinsert: invariants still hold, every value queryable.
#let cycled = (after-d.insert-many)(50, 25, 87, 6, 43, 75, 30)
#assert((cycled.check-invariants)())
#for v in (50, 25, 87, 6, 43, 75, 30) {
  assert((cycled.contains)(v))
}

// Insert-then-delete every value individually from a fresh tree.
#for to-remove in (12, 37, 62, 81, 93, 18, 56) {
  let one-removed = (stress.delete)(to-remove)
  assert((one-removed.check-invariants)())
  assert(not (one-removed.contains)(to-remove))
  // Every other value still present.
  for keep in (50, 25, 75, 12, 37, 62, 87, 6, 18, 30, 43, 56, 68, 81, 93) {
    if keep != to-remove {
      assert((one-removed.contains)(keep), message: "lost " + str(keep) + " after deleting " + str(to-remove))
    }
  }
}

// --- rotate: structural, preserves per-node colors -----------------
// Rotate around 2 (left child of root). 2 was red, 4 was black.
#let rt = (t.rotate)(t.left)
#assert.eq(rt.value, 2)
#assert.eq(rt.red, true)        // 2 kept its color
#assert.eq(rt.right.value, 4)
#assert.eq(rt.right.red, false) // 4 kept its color

// Rotate around a non-direct-child node: t.left.right = 3 at path "LR".
#let rt2 = (t.rotate)(t.left.right)
#assert.eq(((rt2.resolve)("L")).value, 3)
#assert.eq(((rt2.resolve)("LL")).value, 2)

// --- label preservation --------------------------------------------
#let tl = (bleaf(10).insert)(5, label: "five")
#assert.eq(((tl.resolve)((tl.by-value)(5))).label, "five")

// Insert more, label still reachable.
#let tl1 = (tl.insert-many)(3, 7, 1, 8)
#assert((tl1.check-invariants)())
#assert.eq(((tl1.resolve)((tl1.by-value)(5))).label, "five")

// Two-children delete: the successor's label travels with its value.
// (RBT delete uses the in-order successor, matching the CLRS reference
// image; BST delete uses the predecessor.)
#let lbl = bnode(5, rleaf(3), rleaf(8, label: "eight"))
#let lbl-del = (lbl.delete)(5)
#assert((lbl-del.check-invariants)())
#assert.eq(lbl-del.value, 8)
#assert.eq(lbl-del.label, "eight")
