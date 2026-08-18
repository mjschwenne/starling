// Assertion-style test for the BST's pure operations, path utilities, factory
// forms, and the prose that captions and alt text are built from.
#import "/src/lib.typ": bst, result

// Hand-built tree, via the literal builders:
//         4
//        / \
//       1   7
//      / \   \
//     0   3   8
//        /
//       2
#let t = bst.node(
  4,
  bst.node(1, bst.leaf(0), bst.node(3, bst.leaf(2), none)),
  bst.node(7, none, bst.leaf(8)),
)

// contains
#assert(bst.contains(t, 4))
#assert(bst.contains(t, 0))
#assert(bst.contains(t, 2))
#assert(bst.contains(t, 8))
#assert(not bst.contains(t, 9))
#assert(not bst.contains(t, 5))

// The ordering invariant holds for the hand-built tree.
#assert(bst.check-invariants(t))

// insert: 5 goes right of 4, left of 7
#let t5 = bst.insert(t, 5)
#assert(bst.contains(t5, 5))
#assert.eq(
  bst.describe(t5),
  "4 (left: 1 (left: 0, right: 3 (left: 2, right: empty)), right: 7 (left: 5, right: 8))",
)

// delete leaf (0): 1's left becomes none
#let t0 = bst.delete(t, 0)
#assert(not bst.contains(t0, 0))
#assert.eq(
  bst.describe(t0),
  "4 (left: 1 (left: empty, right: 3 (left: 2, right: empty)), right: 7 (left: empty, right: 8))",
)

// delete one-child left-only (3): its only descendant (2) takes its slot
#let t3 = bst.delete(t, 3)
#assert(not bst.contains(t3, 3))
#assert.eq(
  bst.describe(t3),
  "4 (left: 1 (left: 0, right: 2), right: 7 (left: empty, right: 8))",
)

// delete one-child right-only (7): its only descendant (8) takes its slot
#let t7 = bst.delete(t, 7)
#assert(not bst.contains(t7, 7))
#assert.eq(
  bst.describe(t7),
  "4 (left: 1 (left: 0, right: 3 (left: 2, right: empty)), right: 8)",
)

// delete two-children (1): replaced by its in-order predecessor (the largest
// in the left subtree = 0). 0 was a leaf, so its slot becomes empty.
#let t1 = bst.delete(t, 1)
#assert(not bst.contains(t1, 1))
#assert.eq(
  bst.describe(t1),
  "4 (left: 0 (left: empty, right: 3 (left: 2, right: empty)), right: 7 (left: empty, right: 8))",
)

// delete a two-children root (4): the predecessor is the rightmost of 4's left
// subtree = 3, and 3's left child (2) takes its slot.
#let t4 = bst.delete(t, 4)
#assert(not bst.contains(t4, 4))
#assert.eq(
  bst.describe(t4),
  "3 (left: 1 (left: 0, right: 2), right: 7 (left: empty, right: 8))",
)

// rotate at the root with left child 1 -> right rotation
#let tr = bst.rotate(t, t.left)
#assert.eq(
  bst.describe(tr),
  "1 (left: 0, right: 4 (left: 3 (left: 2, right: empty), right: 7 (left: empty, right: 8)))",
)

// path utilities
#assert.eq(bst.by-value(t, 2), "LRL")
#assert.eq(bst.path-to(t, 2), ("", "L", "LR", "LRL"))
#assert.eq(bst.resolve(t, "LR").value, 3)
#assert.eq(bst.resolve(t, "RRR"), none)

// traversal orders
#let values-of(paths) = paths.map(p => bst.resolve(t, p).value)
#assert.eq(values-of(bst.in-order(t)), (0, 1, 2, 3, 4, 7, 8))
#assert.eq(values-of(bst.pre-order(t)), (4, 1, 0, 3, 2, 7, 8))
#assert.eq(values-of(bst.post-order(t)), (0, 2, 3, 1, 8, 7, 4))
#assert.eq(values-of(bst.level-order(t)), (4, 1, 7, 0, 3, 8, 2))

// Label preservation: a custom label attached via insert is reachable through
// resolve, survives an unrelated delete, and travels with its key when its node
// is the in-order predecessor in a two-children delete.
#let td = bst.insert(t, 5, label: "five")
#assert.eq(bst.resolve(td, bst.by-value(td, 5)).label, "five")

// Deleting 0 (a leaf) leaves the labelled 5 in place.
#let td0 = bst.delete(td, 0)
#assert.eq(bst.resolve(td0, bst.by-value(td0, 5)).label, "five")

// Two-children delete: the predecessor's label must travel with its value.
#let tdpx = bst.node(1, bst.leaf(0, label: "zero"), bst.leaf(2))
#let tdpx1 = bst.delete(tdpx, 1)
#assert.eq(tdpx1.value, 0)
#assert.eq(tdpx1.label, "zero")

// rotate preserves the labels on both rotated nodes.
#let tr2 = bst.node(2, bst.leaf(1, label: "one"), none, label: "two")
#let tr2r = bst.rotate(tr2, tr2.left)
#assert.eq(tr2r.value, 1)
#assert.eq(tr2r.label, "one")
#assert.eq(tr2r.right.value, 2)
#assert.eq(tr2r.right.label, "two")

// rotate accepts any node in the tree, not just a direct child of the root.
// Rotating around `t.left.right` (node 3, at path "LR") pivots 3 above 1 within
// the left subtree, leaving 4 as the root.
#let trd = bst.rotate(t, t.left.right)
#assert.eq(
  bst.describe(trd),
  "4 (left: 3 (left: 1 (left: 0, right: 2), right: empty), right: 7 (left: empty, right: 8))",
)

// `bst.new(..)`: the first argument becomes the root, the rest are inserted in
// order. It should match the long-form construction node for node.
#let tf = bst.new(4, 1, 7, 0, 3, 8, 2)
#assert.eq(bst.describe(tf), bst.describe(t))

// A single argument means root only.
#assert.eq(bst.describe(bst.new(4)), "4")

// Tuple form: (value, label). Labels propagate.
#let tfl = bst.new((4, "four"), 1, (7, "seven"))
#assert.eq(tfl.label, "four")
#assert.eq(bst.resolve(tfl, bst.by-value(tfl, 7)).label, "seven")
#assert.eq(bst.resolve(tfl, bst.by-value(tfl, 1)).label, auto)

// Captions and alt text name a node by its string label when it has one,
// falling back to the ordering value otherwise (node 1 is unlabelled).
#assert.eq(bst.describe(tfl), "four (left: 1, right: seven)")
#assert.eq(bst.search-display(tfl, 7).last().alt, "Match found at node seven.")
#assert.eq(
  bst.in-order-display(tfl).at(2).alt,
  "Visited four (visit 2 of 3); output so far: 1, four.",
)

// Every display's final frame carries the structure the operation produced, so
// an animation and the state it advances to are written once, not twice.
#assert.eq(bst.describe(result(bst.insert-display(t, 5))), bst.describe(t5))
#assert.eq(bst.describe(result(bst.delete-display(t, 3))), bst.describe(t3))
#assert.eq(bst.describe(result(bst.rotate-display(t, t.left))), bst.describe(tr))
// A search leaves the tree alone, so its result is the input.
#assert.eq(result(bst.search-display(t, 2)), t)
#assert.eq(result(bst.in-order-display(t)), t)
#assert.eq(result(bst.display(t)), t)
