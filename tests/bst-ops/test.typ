#import "/src/lib.typ": BST

// Hand-built tree:
//         4
//        / \
//       1   7
//      / \   \
//     0   3   8
//        /
//       2
#let leaf(v) = (BST.new)(value: v, left: none, right: none)
#let t = (BST.new)(
  value: 4,
  left: (BST.new)(
    value: 1,
    left: leaf(0),
    right: (BST.new)(value: 3, left: leaf(2), right: none),
  ),
  right: (BST.new)(
    value: 7,
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

// delete two-children (1): replaced by in-order successor (smallest in right
// subtree = 2). The 2 slot then becomes empty under the new 3.
#let t1 = (t.delete)(1)
#assert(not (t1.contains)(1))
#assert.eq(
  (t1.describe)(),
  "4 (left: 2 (left: 0, right: 3), right: 7 (left: empty, right: 8))",
)

// delete two-children root (4): in-order successor is leftmost in 4's right
// subtree. 7.left == none, so successor is 7 itself; 7's slot collapses to 8.
#let t4 = (t.delete)(4)
#assert(not (t4.contains)(4))
#assert.eq(
  (t4.describe)(),
  "7 (left: 1 (left: 0, right: 3 (left: 2, right: empty)), right: 8)",
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
