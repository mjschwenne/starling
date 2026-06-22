#import "/src/lib.typ": AVL, avl

// --- helpers --------------------------------------------------------
#let leaf(v, label: auto) = (AVL.new)(
  value: v,
  label: label,
  height: 1,
  left: none,
  right: none,
)
#let node(v, h, l, r, label: auto) = (AVL.new)(
  value: v,
  label: label,
  height: h,
  left: l,
  right: r,
)

// --- hand-built fixture --------------------------------------------
// Balanced AVL tree:
//         4 (h=3)
//        /     \
//       2       6 (h=2)
//      / \       \
//     1   3       7 (h=1)
#let t = node(
  4,
  3,
  node(2, 2, leaf(1), leaf(3)),
  node(6, 2, none, leaf(7)),
)

#assert((t.check-invariants)())
#assert.eq(
  (t.describe)(),
  "4:3 (left: 2:2 (left: 1:1, right: 3:1), right: 6:2 (left: empty, right: 7:1))",
)

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
#assert.eq(values-of(t, (t.in-order)()), (1, 2, 3, 4, 6, 7))
#assert.eq(values-of(t, (t.pre-order)()), (4, 2, 1, 3, 6, 7))
#assert.eq(values-of(t, (t.post-order)()), (1, 3, 2, 7, 6, 4))
#assert.eq(values-of(t, (t.level-order)()), (4, 2, 6, 1, 3, 7))

// --- insert keeps invariants ---------------------------------------
#let t-ins = (t.insert)(5)
#assert((t-ins.check-invariants)())
#assert((t-ins.contains)(5))

// Inserting 0 triggers an LL fix-up at node 2.
#let t-ll = (t.insert)(0)
#assert((t-ll.check-invariants)())
#assert((t-ll.contains)(0))

// Sequential ascending inserts — worst-case rotation cascade.
#let t-asc = (leaf(1).insert-many)(2, 3, 4, 5, 6, 7, 8, 9, 10)
#assert((t-asc.check-invariants)())
#assert.eq(
  values-of(t-asc, (t-asc.in-order)()),
  (1, 2, 3, 4, 5, 6, 7, 8, 9, 10),
)

// Sequential descending inserts.
#let t-desc = (leaf(10).insert-many)(9, 8, 7, 6, 5, 4, 3, 2, 1)
#assert((t-desc.check-invariants)())
#assert.eq(
  values-of(t-desc, (t-desc.in-order)()),
  (1, 2, 3, 4, 5, 6, 7, 8, 9, 10),
)

// Mixed inserts — zigzag insertions trigger LR/RL cases.
#let t-mix = (leaf(50).insert-many)(
  25,
  75,
  12,
  37,
  62,
  87,
  6,
  18,
  30,
  43,
  56,
  68,
  81,
  93,
)
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

// Delete internal node with one child.
#let t-d6 = (t.delete)(6)
#assert((t-d6.check-invariants)())
#assert(not (t-d6.contains)(6))

// Delete every value from a tree of consecutive inserts, in reverse
// of insertion order. The tree must stay balanced after every step
// and end up with the correct remaining membership.
#let t-many = (leaf(8).insert-many)(4, 12, 2, 6, 10, 14, 1, 3, 5, 7, 9, 11, 13, 15)
#let removed = ()
#let tt = t-many
#for v in (15, 13, 11, 9, 7, 5, 3, 1, 14, 10, 6, 2, 12, 4) {
  tt = (tt.delete)(v)
  removed.push(v)
  if tt != none { assert((tt.check-invariants)()) }
}
// Only the root (value 8) should remain.
#assert(tt != none and tt.value == 8 and tt.left == none and tt.right == none)

// Delete from a single-node tree leaves none.
#let solo = leaf(42)
#assert.eq((solo.delete)(42), none)

// Delete a value that isn't present is a no-op.
#let t-nop = (t.delete)(999)
#assert((t-nop.check-invariants)())
#assert.eq((t-nop.describe)(), (t.describe)())

// --- rotate is structural (BST order preserved) --------------------
// `rotate` is a structural primitive — it does NOT enforce the AVL
// invariant, only BST order, and refreshes the rotated nodes' heights.
#let t-rot = (t.rotate)((t.resolve)("R"))
#assert((t-rot.contains)(4))
#assert((t-rot.contains)(7))
// In-order traversal is invariant under any BST rotation.
#assert.eq(values-of(t-rot, (t-rot.in-order)()), (1, 2, 3, 4, 6, 7))
// New root is the rotated-up child.
#assert.eq(t-rot.value, 6)
