#import "/src/lib.typ": BST

// Hand-built tree:
//         4
//        / \
//       1   7
//      / \   \
//     0   3   8
//        /
//       2
#let leaf(v, label: auto) = (BST.new)(
  value: v,
  label: label,
  left: none,
  right: none,
)
#let t = (BST.new)(
  value: 4,
  label: auto,
  left: (BST.new)(
    value: 1,
    label: auto,
    left: leaf(0),
    right: (BST.new)(
      value: 3,
      label: auto,
      left: leaf(2),
      right: none,
    ),
  ),
  right: (BST.new)(
    value: 7,
    label: auto,
    left: none,
    right: leaf(8),
  ),
)

// contains
#assert((t.contains)(4))
#assert((t.contains)(0))
#assert((t.contains)(2))
#assert((t.contains)(8))
#assert(not (t.contains)(9))
#assert(not (t.contains)(5))

// insert: 5 goes right of 4, left of 7
#let t5 = (t.insert)(5)
#assert((t5.contains)(5))
#assert.eq(
  (t5.describe)(),
  "4 (left: 1 (left: 0, right: 3 (left: 2, right: empty)), right: 7 (left: 5, right: 8))",
)

// delete leaf (0): 1's left becomes none
#let t0 = (t.delete)(0)
#assert(not (t0.contains)(0))
#assert.eq(
  (t0.describe)(),
  "4 (left: 1 (left: empty, right: 3 (left: 2, right: empty)), right: 7 (left: empty, right: 8))",
)

// delete one-child left-only (3): only descendant (2) takes its slot
#let t3 = (t.delete)(3)
#assert(not (t3.contains)(3))
#assert.eq(
  (t3.describe)(),
  "4 (left: 1 (left: 0, right: 2), right: 7 (left: empty, right: 8))",
)

// delete one-child right-only (7): only descendant (8) takes its slot
#let t7 = (t.delete)(7)
#assert(not (t7.contains)(7))
#assert.eq(
  (t7.describe)(),
  "4 (left: 1 (left: 0, right: 3 (left: 2, right: empty)), right: 8)",
)

// delete two-children (1): replaced by in-order predecessor (largest in left
// subtree = 0). 0 was a leaf, so its slot becomes empty.
#let t1 = (t.delete)(1)
#assert(not (t1.contains)(1))
#assert.eq(
  (t1.describe)(),
  "4 (left: 0 (left: empty, right: 3 (left: 2, right: empty)), right: 7 (left: empty, right: 8))",
)

// delete two-children root (4): in-order predecessor is rightmost in 4's left
// subtree = 3. 3's left child (2) takes its slot.
#let t4 = (t.delete)(4)
#assert(not (t4.contains)(4))
#assert.eq(
  (t4.describe)(),
  "3 (left: 1 (left: 0, right: 2), right: 7 (left: empty, right: 8))",
)

// rotate at root with left child 1 -> right rotation
#let tr = (t.rotate)(t.left)
#assert.eq(
  (tr.describe)(),
  "1 (left: 0, right: 4 (left: 3 (left: 2, right: empty), right: 7 (left: empty, right: 8)))",
)

// path utilities
#assert.eq((t.by-value)(2), "LRL")
#assert.eq((t.path-to)(2), ("", "L", "LR", "LRL"))
#assert.eq(((t.resolve)("LR")).value, 3)
#assert.eq((t.resolve)("RRR"), none)

// label preservation: a custom label attached via insert is reachable
// through resolve, survives a non-affecting delete, and travels with
// its key when the node is the in-order predecessor in a two-children
// delete.
#let td = (t.insert)(5, label: "five")
#assert.eq(((td.resolve)((td.by-value)(5))).label, "five")

// Deleting 0 (a leaf) leaves the labelled 5 in place.
#let td0 = (td.delete)(0)
#assert.eq(((td0.resolve)((td0.by-value)(5))).label, "five")

// Two-children delete: the predecessor's label must travel with its
// value. Build a minimal tree where the root has two children, the
// left child (the predecessor) carries a custom label, and the right
// child does not — then delete the root.
#let tdpx = (BST.new)(
  value: 1,
  label: auto,
  left: (BST.new)(value: 0, label: "zero", left: none, right: none),
  right: (BST.new)(value: 2, label: auto, left: none, right: none),
)
#let tdpx1 = (tdpx.delete)(1)
#assert.eq(tdpx1.value, 0)
#assert.eq(tdpx1.label, "zero")

// rotate preserves labels on both rotated nodes.
#let tr2 = (BST.new)(
  value: 2,
  label: "two",
  left: (BST.new)(value: 1, label: "one", left: none, right: none),
  right: none,
)
#let tr2r = (tr2.rotate)(tr2.left)
#assert.eq(tr2r.value, 1)
#assert.eq(tr2r.label, "one")
#assert.eq(tr2r.right.value, 2)
#assert.eq(tr2r.right.label, "two")
