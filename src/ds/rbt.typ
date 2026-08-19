// Red-black tree.
//
// A binary search tree with one extra bit per node and two rebalancing
// algorithms that keep four invariants:
//
//   1. Every node is red or black.
//   2. The root is black after every public operation.
//   3. No red node has a red child.
//   4. Every root-to-NIL path passes through the same number of black nodes.
//
// NIL leaves are `none` and count as black.
//
// A node is `(kind: "rbt", value, label, red, left, right)`. `value` orders
// the tree, `label` is what gets drawn (`auto` falls back to `str(value)`),
// and `red` is the colour bit.
//
// Insert and delete both trace the CLRS algorithms directly rather than
// using Okasaki's `balance` / Kahrs's `app`: those are shorter to write but
// collapse the textbook cases into single atomic rewrites, so an animation
// built on them cannot narrate the three-case insert fix-up or the four-case
// delete fix-up that students are taught. Tracing CLRS means `insert` and
// `insert-display` produce the same tree by construction — the animation is
// the algorithm, not a retelling of it.
//
// `rotate` is a *structural* operation: it preserves the rotated nodes'
// colours and makes no attempt to restore the invariants. The fix-ups do not
// go through it.
//
// step.kind vocabulary
// --------------------
//   static                       the one frame of `display`
//   init                         the opening frame of every animation
//   compare                      one comparison along a descent
//   found / not-found            how a search ended
//   descend                      the whole search path in one frame
//   insert                       the new red leaf has appeared
//   check                        a red-red violation, about to be fixed
//   recolor                      insert Case 1 (parent + uncle black, gp red)
//   rotate-zigzag                insert Case 2 (straighten the red-red pair)
//   rotate-recolor               insert Case 3 (rotate gp, swap colours)
//   blacken-root                 the root ended up red
//   mark-target                  the deletion target
//   find-predecessor / transfer  the walk to the in-order predecessor, and
//                                its value moving into the target's slot
//   excise                       the deletion-position node is gone
//   paint-black-promoted         the promoted red child absorbs the black
//   paint-black-db               the extra black met a red node
//   case-1 … case-4              the delete fix-up cases (each preceded by a
//   case-1-rotate / case-3-rotate / case-4-rotate
//                                rotation-only frame, so the structural
//                                pivot lands before the colour swap)
//   visit                        one node of a traversal
// The final frame of every display carries `step.result` — the tree the
// operation produced (the unchanged input, for a search or traversal).

#import "../core/draw-util.typ": anchor
#import "../core/frame.typ": make-frames, make-renderer, patch
#import "../core/ops.typ": style-edge, style-node
#import "../core/snapshot.typ": blank-snapshot, note-node, with-edge, with-node
#import "../core/style.typ": theme-ref
#import "../core/text.typ": alt-describe, alt-intro, alt-label
#import "../draw/tree.typ": draw-tree
#import "tree-common.typ" as tc
#import "tree-common.typ": (
  by-value, contains, in-order, level-order, path-to, post-order, pre-order,
  resolve,
)

#let _DS = "Red-black tree"

// ===================================================================
// Construction
// ===================================================================

/// A node holding `value`, with either no children (a leaf) or both — pass
/// `none` for a missing one.
///
/// ```typ
/// rbt.node(8, rbt.red(4), rbt.black(12), red: false)
/// ```
///
/// -> dictionary
#let node(
  /// The ordering key.
  /// -> int
  value,
  /// Either nothing (a leaf) or exactly two children, left then right.
  /// -> dictionary | none
  ..children,
  /// The colour bit: `true` red, `false` black.
  /// -> bool
  red: false,
  /// What to draw in the node; `auto` draws `str(value)`.
  /// -> auto | any
  label: auto,
) = {
  let cs = children.pos()
  assert(
    cs.len() == 0 or cs.len() == 2,
    message: "rbt.node: expected no children or exactly two (left, right), got "
      + str(cs.len())
      + ".",
  )
  (
    kind: "rbt",
    value: value,
    label: label,
    red: red,
    left: cs.at(0, default: none),
    right: cs.at(1, default: none),
  )
}

/// A red node — `node(.., red: true)`. With no children it is a red leaf.
///
/// ```typ
/// rbt.black(4, rbt.red(2), rbt.red(6))
/// ```
///
/// -> dictionary
#let red(
  /// The ordering key.
  /// -> int
  value,
  /// Either nothing (a leaf) or exactly two children, left then right.
  /// -> dictionary | none
  ..children,
  /// What to draw in the node; `auto` draws `str(value)`.
  /// -> auto | any
  label: auto,
) = node(value, ..children, red: true, label: label)

/// A black node — `node(.., red: false)`. With no children it is a black
/// leaf.
/// -> dictionary
#let black(
  /// The ordering key.
  /// -> int
  value,
  /// Either nothing (a leaf) or exactly two children, left then right.
  /// -> dictionary | none
  ..children,
  /// What to draw in the node; `auto` draws `str(value)`.
  /// -> auto | any
  label: auto,
) = node(value, ..children, red: false, label: label)

// The internal constructor, argument-ordered the way the CLRS rewrites read
// (colour, left, value, label, right).
#let _mk(is-red, l, v, lab, r) = (
  kind: "rbt",
  value: v,
  label: lab,
  red: is-red,
  left: l,
  right: r,
)

// A nil child counts as black.
#let _is-red(n) = n != none and n.red

#let _blacken(n) = if n == none or not n.red { n } else {
  _mk(false, n.left, n.value, n.label, n.right)
}

// Replace the subtree at `path`, rebuilding the spine above it and
// preserving each spine node's colour, value, label, and other child.
#let _replace-at(n, path, new) = if path == "" {
  new
} else if path.first() == "L" {
  _mk(n.red, _replace-at(n.left, path.slice(1), new), n.value, n.label, n.right)
} else {
  _mk(n.red, n.left, n.value, n.label, _replace-at(n.right, path.slice(1), new))
}

// Recolour the node at `path` without restructuring — what the delete
// fix-up does when it paints a node red or black.
#let _paint-color-at(tree, path, is-red) = {
  let n = resolve(tree, path)
  _replace-at(tree, path, _mk(is-red, n.left, n.value, n.label, n.right))
}

// Copy `value` and `label` into the node at `path`, keeping its colour and
// children — the predecessor transfer of a two-child delete.
#let _set-value-at(tree, path, value, label) = {
  let n = resolve(tree, path)
  _replace-at(tree, path, _mk(n.red, n.left, value, label, n.right))
}

// `post`'s structure wearing `pre`'s per-value colours. `delete-display`
// puts one of these between each rotation and its recolour, so the
// structural pivot is visible before the colours change. Relies on BST
// ordering to look each node's pre-rotation colour up by value.
#let _color-preserve(pre, post) = {
  let find-color(val, n) = if n == none {
    none
  } else if n.value == val {
    n.red
  } else if val < n.value {
    find-color(val, n.left)
  } else {
    find-color(val, n.right)
  }
  let rebuild(n) = if n == none { none } else {
    let pre-red = find-color(n.value, pre)
    _mk(
      if pre-red == none { n.red } else { pre-red },
      rebuild(n.left),
      n.value,
      n.label,
      rebuild(n.right),
    )
  }
  rebuild(post)
}

// ===================================================================
// The CLRS traces
// ===================================================================
//
// Each trace runs the algorithm once and records what happened as an
// ordered list of events, every event carrying the tree as it stood after
// that step. The pure operations take the final tree and throw the events
// away; the displays turn each event into a frame. One implementation, so
// the two can never disagree.

// The red-red fix-up loop, starting at `start-path` — a node whose parent,
// if any, is checked for a violation. Returns `(events, tree)`.
//
// Deliberately does NOT validate its input: `fixup-display` hands it
// hand-built trees whose red-red configuration could not arise from a single
// insertion, which is exactly the teaching case. Emits the "check",
// "recolor", "rotate-zigzag", "rotate-recolor" and "blacken-root" events.
#let _insert-fixup(tree, start-path) = {
  let events = ()
  let cur-tree = tree
  let cur-path = start-path
  let done = false
  while not done {
    if cur-path == "" {
      // Reached the root. Blacken if red.
      if cur-tree.red {
        cur-tree = _blacken(cur-tree)
        events.push((kind: "blacken-root", tree: cur-tree))
      }
      done = true
    } else {
      let parent-path = cur-path.slice(0, cur-path.len() - 1)
      let parent = resolve(cur-tree, parent-path)
      if not parent.red {
        // No violation. The root may already be black; nothing to do.
        done = true
      } else {
        // A red parent is never the root, so the grandparent exists.
        let gp-path = parent-path.slice(0, parent-path.len() - 1)
        let gp = resolve(cur-tree, gp-path)
        let parent-is-left = parent-path.last() == "L"
        let uncle-path = gp-path + (if parent-is-left { "R" } else { "L" })
        let uncle = resolve(cur-tree, uncle-path)

        events.push((
          kind: "check",
          path: cur-path,
          parent-path: parent-path,
          gp-path: gp-path,
          uncle-path: uncle-path,
          tree: cur-tree,
        ))

        if _is-red(uncle) {
          // Case 1: parent and uncle go black, grandparent goes red.
          let new-parent = _mk(
            false,
            parent.left,
            parent.value,
            parent.label,
            parent.right,
          )
          let new-uncle = _mk(
            false,
            uncle.left,
            uncle.value,
            uncle.label,
            uncle.right,
          )
          let new-gp = if parent-is-left {
            _mk(true, new-parent, gp.value, gp.label, new-uncle)
          } else {
            _mk(true, new-uncle, gp.value, gp.label, new-parent)
          }
          cur-tree = _replace-at(cur-tree, gp-path, new-gp)
          cur-path = gp-path
          events.push((
            kind: "recolor",
            gp-path: gp-path,
            parent-path: parent-path,
            uncle-path: uncle-path,
            tree: cur-tree,
          ))
        } else {
          // Uncle is black or nil: Case 2 (straighten) then Case 3.
          let current-is-left = cur-path.last() == "L"
          if parent-is-left != current-is-left {
            // Case 2: zigzag — rotate around the parent.
            let new-parent-sub = if parent-is-left {
              // Current was parent.right; left-rotate around parent.
              let c = parent.right
              _mk(
                c.red,
                _mk(parent.red, parent.left, parent.value, parent.label, c.left),
                c.value,
                c.label,
                c.right,
              )
            } else {
              // Current was parent.left; right-rotate around parent.
              let c = parent.left
              _mk(
                c.red,
                c.left,
                c.value,
                c.label,
                _mk(
                  parent.red,
                  c.right,
                  parent.value,
                  parent.label,
                  parent.right,
                ),
              )
            }
            cur-tree = _replace-at(cur-tree, parent-path, new-parent-sub)
            // After the zigzag the lower red sits below the parent on the
            // side the parent itself hangs from (LL or RR).
            cur-path = parent-path + (if parent-is-left { "L" } else { "R" })
            events.push((
              kind: "rotate-zigzag",
              parent-path: parent-path,
              tree: cur-tree,
            ))
            // Same path, different node: re-fetch the parent.
            parent = resolve(cur-tree, parent-path)
          }

          // Case 3: straight line — rotate around the grandparent and swap
          // the grandparent's and parent's colours. The new subtree root
          // takes the grandparent's colour (black) and the demoted
          // grandparent the parent's (red).
          let new-gp = if parent-is-left {
            // Right-rotate around gp.
            _mk(
              gp.red,
              parent.left,
              parent.value,
              parent.label,
              _mk(parent.red, parent.right, gp.value, gp.label, gp.right),
            )
          } else {
            // Left-rotate around gp.
            _mk(
              gp.red,
              _mk(parent.red, gp.left, gp.value, gp.label, parent.left),
              parent.value,
              parent.label,
              parent.right,
            )
          }
          cur-tree = _replace-at(cur-tree, gp-path, new-gp)
          events.push((kind: "rotate-recolor", gp-path: gp-path, tree: cur-tree))
          done = true
        }
      }
    }
  }
  (events: events, tree: cur-tree)
}

// The whole insertion: BST descent, splice a red leaf, then the fix-up.
// Returns `(events, tree)`.
#let _insert-trace(tree, v, label) = {
  let events = ()

  // BST descent, recording each visited path and the insertion path (one
  // step past the last visited node).
  let visited = ()
  let p = ""
  let n = tree
  while n != none {
    visited.push(p)
    if v <= n.value {
      p = p + "L"
      n = n.left
    } else {
      p = p + "R"
      n = n.right
    }
  }
  let insert-path = p

  events.push((kind: "init", tree: tree))
  events.push((
    kind: "descend",
    visited: visited,
    insert-path: insert-path,
    tree: tree,
  ))

  // Splice a new red leaf at `insert-path`. `_replace-at` can't do it: the
  // parent's child pointer is `none` there, so the walk goes down directly.
  let insert-at(n, path) = if path == "" {
    _mk(true, none, v, label, none)
  } else if path.first() == "L" {
    _mk(n.red, insert-at(n.left, path.slice(1)), n.value, n.label, n.right)
  } else {
    _mk(n.red, n.left, n.value, n.label, insert-at(n.right, path.slice(1)))
  }
  let cur-tree = insert-at(tree, insert-path)
  events.push((kind: "insert", path: insert-path, tree: cur-tree))

  let fix = _insert-fixup(cur-tree, insert-path)
  (events: events + fix.events, tree: fix.tree)
}

// The whole deletion. Follows the textbook decision tree but takes the
// in-order *predecessor* rather than the successor, so the structural pivot
// matches `bst.delete`:
//
//   1. Descend to the target. Absent ⇒ the tree is unchanged.
//   2. Two children ⇒ walk to the in-order predecessor, transfer its
//      value + label into the target slot, and switch the deletion position
//      to the predecessor (which has at most one child).
//   3. Excise the deletion-position node, splicing its child (or `none`)
//      into its place.
//   4. Branch on the excised node's colour:
//        red                          ⇒ nothing to do.
//        black, promoted child red    ⇒ paint the child black.
//        black, promoted child black  ⇒ "double-black" at the deletion
//                                       path; run the four-case loop.
//
// The four cases, mirrored for a right-child double-black:
//
//   sibling red                        Case 1. Rotate the parent, swap
//                                      parent/sibling colours. The new
//                                      sibling is black, so the next
//                                      iteration lands in Cases 2-4.
//   sibling black, both nephews black  Case 2. Paint the sibling red and
//                                      push the double-black up to parent.
//   sibling black, near nephew red     Case 3. Rotate the sibling, swap
//                                      sibling/near-nephew colours; falls
//                                      through into Case 4.
//   sibling black, far nephew red      Case 4. Rotate the parent, swap
//                                      parent/sibling colours, paint the
//                                      far nephew black. Done.
//
// Returns `(events, tree)`. With `with-search: true` the descent is reported
// one comparison per event; otherwise as a single "descend" event.
#let _delete-trace(tree, v, with-search) = {
  let events = ()

  // BST search: record each comparison, return the target's path or `none`.
  let walk(n, p) = if n == none {
    (steps: (), found: none)
  } else if v == n.value {
    (steps: ((path: p, cmp: "=", found: true),), found: p)
  } else if v < n.value {
    let rest = walk(n.left, p + "L")
    (steps: ((path: p, cmp: "<", found: false),) + rest.steps, found: rest.found)
  } else {
    let rest = walk(n.right, p + "R")
    (steps: ((path: p, cmp: ">", found: false),) + rest.steps, found: rest.found)
  }
  let search = walk(tree, "")
  let target-path = search.found
  let search-steps = search.steps

  events.push((kind: "init", tree: tree))
  if with-search {
    for s in search-steps {
      events.push((
        kind: "compare",
        path: s.path,
        cmp: s.cmp,
        found: s.found,
        tree: tree,
      ))
    }
  } else {
    events.push((
      kind: "descend",
      visited: search-steps.map(s => s.path),
      tree: tree,
    ))
  }

  if target-path == none {
    events.push((
      kind: "not-found",
      visited: search-steps.map(s => s.path),
      tree: tree,
    ))
    return (events: events, tree: tree)
  }

  let cur-tree = tree
  let target = resolve(cur-tree, target-path)
  let two-children = target.left != none and target.right != none

  events.push((kind: "mark-target", target-path: target-path, tree: cur-tree))

  let excise-path = target-path
  if two-children {
    let pred-walk(p) = {
      let n = resolve(cur-tree, p)
      if n.right == none { (p,) } else { (p,) + pred-walk(p + "R") }
    }
    let walk-paths = pred-walk(target-path + "L")
    let pred-path = walk-paths.last()
    let pred-node = resolve(cur-tree, pred-path)

    events.push((
      kind: "find-predecessor",
      walk: walk-paths,
      predecessor-path: pred-path,
      target-path: target-path,
      tree: cur-tree,
    ))

    cur-tree = _set-value-at(
      cur-tree,
      target-path,
      pred-node.value,
      pred-node.label,
    )
    events.push((
      kind: "transfer",
      target-path: target-path,
      predecessor-path: pred-path,
      new-value: pred-node.value,
      new-label: alt-label(pred-node),
      tree: cur-tree,
    ))
    excise-path = pred-path
  }

  let excise-node = resolve(cur-tree, excise-path)
  let excise-was-red = excise-node.red
  let replacement = if excise-node.left != none {
    excise-node.left
  } else { excise-node.right }

  // Excising the root of a single-node tree leaves the tree empty.
  if excise-path == "" and replacement == none {
    events.push((
      kind: "excise",
      path: excise-path,
      was-red: excise-was-red,
      tree: none,
    ))
    return (events: events, tree: none)
  }

  cur-tree = _replace-at(cur-tree, excise-path, replacement)
  events.push((
    kind: "excise",
    path: excise-path,
    was-red: excise-was-red,
    tree: cur-tree,
  ))

  // A red node carried no black height; nothing to repair.
  if excise-was-red {
    return (events: events, tree: cur-tree)
  }

  // A red promoted child can absorb the missing black by turning black.
  if replacement != none and replacement.red {
    cur-tree = _paint-color-at(cur-tree, excise-path, false)
    events.push((kind: "paint-black-promoted", path: excise-path, tree: cur-tree))
    return (events: events, tree: cur-tree)
  }

  // Otherwise: double-black at `excise-path`. Run the four-case loop.
  let db-path = excise-path
  let done = false
  while not done {
    if db-path == "" {
      done = true
    } else {
      let db-node = resolve(cur-tree, db-path)
      if _is-red(db-node) {
        cur-tree = _paint-color-at(cur-tree, db-path, false)
        events.push((kind: "paint-black-db", path: db-path, tree: cur-tree))
        done = true
      } else {
        let parent-path = db-path.slice(0, db-path.len() - 1)
        let parent = resolve(cur-tree, parent-path)
        let is-left = db-path.last() == "L"
        let sibling-path = parent-path + (if is-left { "R" } else { "L" })
        let sibling = resolve(cur-tree, sibling-path)

        events.push((
          kind: "check",
          db-path: db-path,
          parent-path: parent-path,
          sibling-path: sibling-path,
          tree: cur-tree,
        ))

        if _is-red(sibling) {
          // Case 1: rotate the parent, swap parent/sibling colours.
          let new-subtree = if is-left {
            _mk(
              false,
              _mk(
                true,
                parent.left,
                parent.value,
                parent.label,
                sibling.left,
              ),
              sibling.value,
              sibling.label,
              sibling.right,
            )
          } else {
            _mk(
              false,
              sibling.left,
              sibling.value,
              sibling.label,
              _mk(
                true,
                sibling.right,
                parent.value,
                parent.label,
                parent.right,
              ),
            )
          }
          cur-tree = _replace-at(cur-tree, parent-path, new-subtree)
          // The parent moved under the former sibling, so the double-black
          // is now one level deeper.
          db-path = parent-path + (if is-left { "LL" } else { "RR" })
          events.push((
            kind: "case-1",
            parent-path: parent-path,
            new-sibling-path: parent-path + (if is-left { "LR" } else { "RL" }),
            tree: cur-tree,
          ))
        } else {
          let far-nephew-path = sibling-path + (if is-left { "R" } else { "L" })
          let near-nephew-path = sibling-path + (if is-left { "L" } else { "R" })
          let far-nephew = resolve(cur-tree, far-nephew-path)
          let near-nephew = resolve(cur-tree, near-nephew-path)

          if not _is-red(far-nephew) and not _is-red(near-nephew) {
            // Case 2: paint the sibling red, push the double-black up.
            cur-tree = _paint-color-at(cur-tree, sibling-path, true)
            db-path = parent-path
            events.push((
              kind: "case-2",
              sibling-path: sibling-path,
              new-db-path: parent-path,
              tree: cur-tree,
            ))
          } else {
            if not _is-red(far-nephew) {
              // Case 3: rotate the sibling, swap sibling/near-nephew.
              let new-sibling-sub = if is-left {
                _mk(
                  false,
                  near-nephew.left,
                  near-nephew.value,
                  near-nephew.label,
                  _mk(
                    true,
                    near-nephew.right,
                    sibling.value,
                    sibling.label,
                    sibling.right,
                  ),
                )
              } else {
                _mk(
                  false,
                  _mk(
                    true,
                    sibling.left,
                    sibling.value,
                    sibling.label,
                    near-nephew.left,
                  ),
                  near-nephew.value,
                  near-nephew.label,
                  near-nephew.right,
                )
              }
              cur-tree = _replace-at(cur-tree, sibling-path, new-sibling-sub)
              events.push((
                kind: "case-3",
                sibling-path: sibling-path,
                near-nephew-path: near-nephew-path,
                tree: cur-tree,
              ))
              // Case 4 works on the new shape.
              sibling = resolve(cur-tree, sibling-path)
              far-nephew = resolve(cur-tree, far-nephew-path)
            }

            // Case 4: rotate the parent, swap parent/sibling colours, paint
            // the far nephew black.
            let new-subtree = if is-left {
              _mk(
                parent.red,
                _mk(
                  false,
                  parent.left,
                  parent.value,
                  parent.label,
                  sibling.left,
                ),
                sibling.value,
                sibling.label,
                _mk(
                  false,
                  far-nephew.left,
                  far-nephew.value,
                  far-nephew.label,
                  far-nephew.right,
                ),
              )
            } else {
              _mk(
                parent.red,
                _mk(
                  false,
                  far-nephew.left,
                  far-nephew.value,
                  far-nephew.label,
                  far-nephew.right,
                ),
                sibling.value,
                sibling.label,
                _mk(
                  false,
                  sibling.right,
                  parent.value,
                  parent.label,
                  parent.right,
                ),
              )
            }
            cur-tree = _replace-at(cur-tree, parent-path, new-subtree)
            events.push((kind: "case-4", parent-path: parent-path, tree: cur-tree))
            done = true
          }
        }
      }
    }
  }

  (events: events, tree: cur-tree)
}

// ===================================================================
// Pure operations
// ===================================================================

/// Insert `v`, returning a new tree with the invariants restored. Ties
/// descend left, so equal values are legal and land in the left subtree.
/// -> dictionary
#let insert(
  /// The tree.
  /// -> dictionary
  tree,
  /// The ordering key to insert.
  /// -> int
  v,
  /// What to draw in the new node; `auto` draws `str(v)`.
  /// -> auto | any
  label: auto,
) = _insert-trace(tree, v, label).tree

/// Insert several values in order. Each is a bare key or a
/// `(value, label)` pair.
/// -> dictionary
#let insert-many(
  /// The tree.
  /// -> dictionary
  tree,
  /// The values to insert.
  /// -> any
  ..vals,
) = tc.insert-many(tree, insert, vals.pos(), who: "rbt.insert-many")

/// Build a tree from a list of values: the first becomes the black root,
/// the rest are inserted in order, so the CLRS fix-ups produce the final
/// shape. Each is a bare key or a `(value, label)` pair.
///
/// ```typ
/// rbt.new(8, 4, 12, 2, 6, 10, 14, 1)
/// rbt.new((8, [eight]), 4, (12, [XII]))
/// ```
///
/// -> dictionary
#let new(
  /// The values. At least one is required — it becomes the root.
  /// -> any
  ..vals,
) = {
  let xs = vals.pos()
  assert(xs.len() > 0, message: "rbt.new: at least one value is required (the root).")
  let head = tc.parse-value(xs.first(), "rbt.new")
  tc.insert-many(
    black(head.value, label: head.label),
    insert,
    xs.slice(1),
    who: "rbt.new",
  )
}

/// Delete `v`, returning a new tree (or `none` if the last node went). A
/// node with two children is replaced by its in-order predecessor — value
/// *and* label — which is then excised from the left subtree.
/// -> dictionary | none
#let delete(
  /// The tree.
  /// -> dictionary
  tree,
  /// The ordering key to delete.
  /// -> int
  v,
) = {
  // The fix-up can leave a red root — Case 2 propagating the missing black
  // all the way up, or Case 1 swapping the root's colour. Blackening is
  // always safe and always restores invariant 2.
  _blacken(_delete-trace(tree, v, false).tree)
}

/// Rotate around `child` — anywhere in the tree, not only at the root.
/// `child` is located by searching for its value, so its parent and the
/// direction are inferred.
///
/// This is a *structural* rotation: each rotated node keeps its colour, and
/// the result need not satisfy the red-black invariants. The insert and
/// delete fix-ups do not go through it.
/// -> dictionary
#let rotate(
  /// The tree.
  /// -> dictionary
  tree,
  /// The node that should become the new subtree root.
  /// -> dictionary
  child,
) = {
  let child-path = by-value(tree, child.value)
  if child-path == "" {
    panic("rbt.rotate: cannot rotate the root with itself.")
  }
  let parent-path = child-path.slice(0, child-path.len() - 1)
  let parent = resolve(tree, parent-path)
  let is-right = child-path.last() == "L"
  let rotated = if is-right {
    // child is the left child of parent -> right rotation
    _mk(
      child.red,
      child.left,
      child.value,
      child.label,
      _mk(parent.red, child.right, parent.value, parent.label, parent.right),
    )
  } else {
    // child is the right child of parent -> left rotation
    _mk(
      child.red,
      _mk(parent.red, parent.left, parent.value, parent.label, child.left),
      child.value,
      child.label,
      child.right,
    )
  }
  _replace-at(tree, parent-path, rotated)
}

/// A recursive textual rendering of the tree, used in alt text. Each node's
/// colour follows its label, separated by a space so a single-letter label
/// doesn't fuse with it.
/// -> str
#let describe(
  /// The tree.
  /// -> dictionary
  tree,
) = tc.describe(
  tree,
  head: n => alt-label(n) + " " + (if n.red { "R" } else { "B" }),
)

/// Check the search-tree ordering plus the four red-black invariants.
/// Returns `true` or panics naming the first violation.
/// -> bool
#let check-invariants(
  /// The tree.
  /// -> dictionary
  tree,
) = {
  assert(
    not tree.red,
    message: "rbt.check-invariants: the root must be black, but "
      + str(tree.value)
      + " is red.",
  )
  // Returns the subtree's black height, panicking on the way up.
  let bh(n) = if n == none { 0 } else {
    if n.red {
      assert(
        not _is-red(n.left),
        message: "rbt.check-invariants: red node "
          + str(n.value)
          + " has a red left child.",
      )
      assert(
        not _is-red(n.right),
        message: "rbt.check-invariants: red node "
          + str(n.value)
          + " has a red right child.",
      )
    }
    assert(
      n.left == none or n.left.value <= n.value,
      message: "rbt.check-invariants: search-tree order violated at "
        + str(n.value)
        + " — left child is larger.",
    )
    assert(
      n.right == none or n.right.value >= n.value,
      message: "rbt.check-invariants: search-tree order violated at "
        + str(n.value)
        + " — right child is smaller.",
    )
    let lb = bh(n.left)
    let rb = bh(n.right)
    assert(
      lb == rb,
      message: "rbt.check-invariants: black-height mismatch at "
        + str(n.value)
        + " (left "
        + str(lb)
        + ", right "
        + str(rb)
        + ").",
    )
    lb + (if n.red { 0 } else { 1 })
  }
  let _ = bh(tree)
  true
}

// ===================================================================
// The palette
// ===================================================================

// The red/black styling for one node, as theme *references* rather than
// concrete colours: the snapshot is often built long before the frame is
// drawn (a renderer handed to the op stream, a display whose theme override
// arrives later), and a reference follows whichever theme wins.
#let _node-style(n, bits) = {
  let side = if n.red { "red" } else { "black" }
  let style = (
    fill: theme-ref("rbt", side + "-fill"),
    stroke: theme-ref("rbt", side + "-stroke"),
    text-fill: theme-ref("rbt", side + "-text-fill"),
  )
  if bits { style.insert("tag", if n.red { "0" } else { "1" }) }
  style
}

// Paint every node of `tree` with its colour. With `bits: true` each node
// also carries its black-height bit ("0" red, "1" black) in the tag slot,
// drawn just outside the node by the tree backend — so a reader can count
// black height down any path.
#let _paint(tree, bits: false) = {
  let walk(n, path) = if n == none { () } else {
    (path,) + walk(n.left, path + "L") + walk(n.right, path + "R")
  }
  let snap = blank-snapshot()
  for p in walk(tree, "") {
    snap = with-node(snap, p, _node-style(resolve(tree, p), bits))
  }
  snap
}

// ===================================================================
// Style vocabulary
// ===================================================================
//
// The red-black counterpart to `styles.attention(..)` and friends: helpers
// that say what a node *is* rather than what colour to paint it, each
// variadic over paths and each returning an op array, so they compose with
// `+` and drop straight into `apply-ops`.

/// Paint nodes red, with the black-height bit `0`.
///
/// ```typ
/// apply-ops(r, rbt.paint-red("L", "RR") + commit())
/// ```
///
/// -> array
#let paint-red(
  /// The paths to paint.
  /// -> str
  ..keys,
) = style-node(
  ..keys.pos(),
  fill: theme-ref("rbt", "red-fill"),
  stroke: theme-ref("rbt", "red-stroke"),
  text-fill: theme-ref("rbt", "red-text-fill"),
  tag: "0",
)

/// Paint nodes black, with the black-height bit `1`.
/// -> array
#let paint-black(
  /// The paths to paint.
  /// -> str
  ..keys,
) = style-node(
  ..keys.pos(),
  fill: theme-ref("rbt", "black-fill"),
  stroke: theme-ref("rbt", "black-stroke"),
  text-fill: theme-ref("rbt", "black-text-fill"),
  tag: "1",
)

// The textbook double-black marker: a filled dot at the child end of the
// edge into the node carrying the extra black. `force-show` draws that edge
// even when the position is now nil — right after an excise, the missing
// black still lives there.
#let _db-edge-style = (
  mark: (
    end: "o",
    fill: theme-ref("render", "edge-stroke"),
    scale: 2,
    offset: 0.2,
  ),
  force-show: true,
)

/// Mark nodes as double-black: the bit `2` on the node and a filled dot on
/// its incoming edge, the way the textbook draws a subtree one black short.
/// -> array
#let double-black(
  /// The paths to mark.
  /// -> str
  ..keys,
) = (
  style-node(..keys.pos(), tag: "2") + style-edge(..keys.pos(), .._db-edge-style)
)

// ===================================================================
// Rendering
// ===================================================================

/// A `Renderer` over this tree, bound to the tree backend and pre-painted
/// with the red-black palette — the entry point for driving an animation
/// yourself with the `Op` command stream. Pass `sticky: true` so the palette
/// (and your own highlights) carry from frame to frame.
/// -> dictionary
#let renderer(
  /// The tree.
  /// -> dictionary
  tree,
  /// Whether every node carries its black-height bit.
  /// -> bool
  bits: false,
  /// Base node styling beneath every frame's snapshot.
  /// -> dictionary
  node-style: (:),
  /// Base edge styling beneath every frame's snapshot.
  /// -> dictionary
  edge-style: (:),
  /// Whether new frames inherit the previous frame's styling.
  /// -> bool
  sticky: false,
  /// Partial theme override for this renderer.
  /// -> dictionary
  theme: (:),
) = patch(
  make-renderer(
    tree,
    draw-tree,
    node-style: node-style,
    edge-style: edge-style,
    sticky: sticky,
    theme: theme,
  ),
  _ => _paint(tree, bits: bits),
)

// Every display shares this: build the frames on the tree backend with the
// caller's style layers and theme override.
#let _frames(specs, theme, node-style, edge-style) = make-frames(
  specs,
  draw-tree,
  theme: theme,
  node-style: node-style,
  edge-style: edge-style,
)

/// The tree as a single static frame, every node wearing its colour.
/// -> array
#let display(
  /// The tree.
  /// -> dictionary
  tree,
  /// Whether every node carries its black-height bit.
  /// -> bool
  bits: false,
  /// Base node styling.
  /// -> dictionary
  node-style: (:),
  /// Base edge styling.
  /// -> dictionary
  edge-style: (:),
  /// Partial theme override for this call.
  /// -> dictionary
  theme: (:),
) = _frames(
  (
    (
      structure: tree,
      build: _ => _paint(tree, bits: bits),
      caption: none,
      step: (kind: "static", result: tree),
      alt: alt-describe(_DS, describe(tree)),
    ),
  ),
  theme,
  node-style,
  edge-style,
)

/// Animate searching for `v`: one frame per comparison along the search
/// path, each highlighting the visited node and drawing the comparison
/// beside it. The walk ends at a match, or where the search runs off the
/// tree.
/// -> array
#let search-display(
  /// The tree.
  /// -> dictionary
  tree,
  /// The ordering key to search for.
  /// -> int
  v,
  /// Whether every node carries its black-height bit.
  /// -> bool
  bits: false,
  /// Base node styling.
  /// -> dictionary
  node-style: (:),
  /// Base edge styling.
  /// -> dictionary
  edge-style: (:),
  /// Partial theme override for this call.
  /// -> dictionary
  theme: (:),
) = tc.render-search(
  tree,
  v,
  _DS,
  describe(tree),
  base: _ => _paint(tree, bits: bits),
  node-style: node-style,
  edge-style: edge-style,
  theme: theme,
)

// One frame per insert-trace event. Shared by `insert-display` (the whole
// trace) and `fixup-display` (the fix-up alone — same event kinds, a
// subset). `init-alt` differs per call site, and `v` is read only by the
// "descend" and "insert" branches, which the fix-up never emits.
#let _insert-spec(event, v, bits, init-alt) = {
  let caption = none
  let step = (kind: event.kind)
  let alt = ""

  if event.kind == "init" {
    alt = init-alt
  } else if event.kind == "descend" {
    caption = [Search for #v]
    step = (
      kind: "descend",
      visited: event.visited,
      insert-path: event.insert-path,
    )
    alt = ("Walked the search path for "
      + str(v)
      + "; the insertion point is one step beyond the last visited node.")
  } else if event.kind == "insert" {
    caption = [Insert #v as red leaf]
    step = (kind: "insert", path: event.path)
    alt = "Inserted " + str(v) + " as a new red leaf."
  } else if event.kind == "check" {
    caption = [Red-red violation]
    step = (
      kind: "check",
      path: event.path,
      parent-path: event.parent-path,
      gp-path: event.gp-path,
      uncle-path: event.uncle-path,
    )
    alt = ("Red-red violation between nodes "
      + alt-label(resolve(event.tree, event.path))
      + " and "
      + alt-label(resolve(event.tree, event.parent-path))
      + ".")
  } else if event.kind == "recolor" {
    caption = [Recolor]
    step = (
      kind: "recolor",
      gp-path: event.gp-path,
      parent-path: event.parent-path,
      uncle-path: event.uncle-path,
    )
    alt = ("Case 1: parent and uncle recolored black, grandparent recolored "
      + "red. Continuing the check at the grandparent.")
  } else if event.kind == "rotate-zigzag" {
    caption = [Rotate to straighten]
    step = (kind: "rotate-zigzag", parent-path: event.parent-path)
    alt = ("Case 2: rotated around the parent to align the red-red pair into "
      + "a straight line.")
  } else if event.kind == "rotate-recolor" {
    caption = [Rotate and color swap]
    step = (kind: "rotate-recolor", gp-path: event.gp-path)
    alt = ("Case 3: rotated around the grandparent and swapped its color with "
      + "the new subtree root.")
  } else if event.kind == "blacken-root" {
    caption = [Blacken root]
    alt = "Blackened the root to restore the red-black invariants."
  }

  let build = th => {
    let cur = _paint(event.tree, bits: bits)
    if event.kind == "descend" {
      for p in event.visited {
        cur = with-node(cur, p, (stroke: th.op.search-stroke))
      }
    } else if event.kind == "insert" {
      cur = with-node(cur, event.path, (stroke: th.op.settled-stroke))
      cur = with-edge(cur, event.path, (stroke: th.op.success-stroke))
    } else if event.kind == "check" {
      cur = with-node(cur, event.path, (stroke: th.op.attention-stroke))
      cur = with-node(cur, event.parent-path, (stroke: th.op.attention-stroke))
      cur = note-node(cur, event.path, [↑])
    } else if event.kind == "recolor" {
      cur = with-node(cur, event.gp-path, (stroke: th.op.settled-stroke))
      cur = with-node(cur, event.parent-path, (stroke: th.op.settled-stroke))
      if resolve(event.tree, event.uncle-path) != none {
        cur = with-node(cur, event.uncle-path, (stroke: th.op.settled-stroke))
      }
    } else if event.kind == "rotate-zigzag" {
      cur = with-node(cur, event.parent-path, (stroke: th.op.attention-stroke))
    } else if event.kind == "rotate-recolor" {
      cur = with-node(cur, event.gp-path, (stroke: th.op.settled-stroke))
      cur = with-edge(cur, event.gp-path, (stroke: th.op.success-stroke))
    } else if event.kind == "blacken-root" {
      cur = with-node(cur, "", (stroke: th.op.settled-stroke))
    }
    cur
  }

  (
    structure: event.tree,
    build: build,
    caption: caption,
    step: step,
    alt: alt,
  )
}

/// Animate inserting `v`: the search descent in one frame, the new red leaf
/// appearing, then one frame per fix-up step — the red-red check, and
/// whichever of Case 1 (recolor), Case 2 (straighten) and Case 3 (rotate and
/// swap) applies — ending at a blackened root if the fix-up reached it.
/// -> array
#let insert-display(
  /// The tree.
  /// -> dictionary
  tree,
  /// The ordering key to insert.
  /// -> int
  v,
  /// What to draw in the new node; `auto` draws `str(v)`.
  /// -> auto | any
  label: auto,
  /// Whether every node carries its black-height bit.
  /// -> bool
  bits: false,
  /// Base node styling.
  /// -> dictionary
  node-style: (:),
  /// Base edge styling.
  /// -> dictionary
  edge-style: (:),
  /// Partial theme override for this call.
  /// -> dictionary
  theme: (:),
) = {
  let trace = _insert-trace(tree, v, label)
  let init-alt = alt-intro(_DS, describe(tree), "insert " + str(v))
  _frames(
    tc.stamp-result(
      trace.events.map(e => _insert-spec(e, v, bits, init-alt)),
      trace.tree,
    ),
    theme,
    node-style,
    edge-style,
  )
}

/// Animate the red-red fix-up on a hand-built tree that already has a
/// violation at `violation-path` — the *lower* of the two reds.
///
/// The tree is deliberately not validated: the point is to show fix-up
/// configurations that a single `insert` cannot produce, such as a red-red
/// in the middle of a tree, or a multi-level Case 1 propagation that ends by
/// blackening the root.
/// -> array
#let fixup-display(
  /// The tree.
  /// -> dictionary
  tree,
  /// The path of the lower of the two red nodes.
  /// -> str
  violation-path,
  /// Whether every node carries its black-height bit.
  /// -> bool
  bits: false,
  /// Base node styling.
  /// -> dictionary
  node-style: (:),
  /// Base edge styling.
  /// -> dictionary
  edge-style: (:),
  /// Partial theme override for this call.
  /// -> dictionary
  theme: (:),
) = {
  let fix = _insert-fixup(tree, violation-path)
  let init-alt = (alt-describe(_DS, describe(tree))
    + " Red-red violation at path \""
    + violation-path
    + "\"; about to apply fix-up.")
  let events = ((kind: "init", tree: tree),) + fix.events
  _frames(
    tc.stamp-result(
      events.map(e => _insert-spec(e, none, bits, init-alt)),
      fix.tree,
    ),
    theme,
    node-style,
    edge-style,
  )
}

/// Animate deleting `v`, following the CLRS decision tree.
///
/// The target is marked, a two-child target hands its slot to its in-order
/// predecessor, the deletion-position node is excised, and then — if that
/// node was black and nothing red was promoted in its place — the
/// double-black fix-up runs, one pair of frames per case: the rotation
/// first, so the shape change is visible, then the recolor.
///
/// With `search: true` the deletion is preceded by one frame per comparison
/// on the way down, instead of a single frame showing the whole path.
/// -> array
#let delete-display(
  /// The tree.
  /// -> dictionary
  tree,
  /// The ordering key to delete.
  /// -> int
  v,
  /// Whether to walk to the target one comparison at a time.
  /// -> bool
  search: false,
  /// Whether every node carries its black-height bit.
  /// -> bool
  bits: false,
  /// Base node styling.
  /// -> dictionary
  node-style: (:),
  /// Base edge styling.
  /// -> dictionary
  edge-style: (:),
  /// Partial theme override for this call.
  /// -> dictionary
  theme: (:),
) = {
  let trace = _delete-trace(tree, v, search)
  let events = trace.events
  let after = _blacken(trace.tree)

  // Name the target by its label when it has one — that is how it is drawn.
  let del-label = if contains(tree, v) {
    alt-label(resolve(tree, by-value(tree, v)))
  } else { str(v) }
  let init-alt = alt-intro(_DS, describe(tree), "delete " + del-label)

  // The search trail, accumulated so each comparison frame shows the whole
  // path walked so far rather than just the current node.
  let visited-by-event = ()
  let visited-acc = ()
  for e in events {
    if e.kind == "compare" { visited-acc = visited-acc + (e.path,) }
    visited-by-event.push(visited-acc)
  }

  // Where the missing black sits at each event. The trace doesn't carry it
  // — it is a property of the animation, not the algorithm — so walk the
  // events once: it appears after a black excise that the loop will follow,
  // persists across a check, moves with Cases 1 and 2, is untouched by Case
  // 3, and is resolved by Case 4 or either paint-black.
  let db-by-event = ()
  let cur-db = none
  for (idx, e) in events.enumerate() {
    if e.kind == "excise" and not e.was-red {
      let next-kind = if idx + 1 < events.len() {
        events.at(idx + 1).kind
      } else { none }
      if next-kind != "paint-black-promoted" { cur-db = e.path }
    } else if e.kind == "paint-black-promoted" {
      cur-db = none
    } else if e.kind == "case-1" {
      // The parent moved under the former sibling, so the double-black is
      // now the parent's near grandchild.
      let suffix = e.new-sibling-path.slice(e.parent-path.len())
      cur-db = e.parent-path + (if suffix == "LR" { "LL" } else { "RR" })
    } else if e.kind == "case-2" {
      // If the double-black propagated up to a red node, the next step is
      // paint-black-db. Suppress the marker: "red and double-black" is not
      // a stable node state, and drawing it reads wrong.
      let new-db = e.new-db-path
      let new-db-node = if new-db == "" { none } else { resolve(e.tree, new-db) }
      cur-db = if _is-red(new-db-node) { none } else { new-db }
    } else if e.kind == "case-4" or e.kind == "paint-black-db" {
      cur-db = none
    } else if e.kind == "check" {
      cur-db = e.db-path
    }
    db-by-event.push(cur-db)
  }

  // The double-black dot, drawn on the edge into the node one black short.
  // The root has no incoming edge, so a root double-black shows nothing —
  // it is absorbed immediately anyway.
  let db-mark(cur, db) = if db == none or db == "" { cur } else {
    with-edge(cur, db, _db-edge-style)
  }

  let specs = ()
  for (i, e) in events.enumerate() {
    // The excise that empties a single-node tree has no tree to draw; the
    // preceding mark-target frame already says what is about to happen.
    if e.tree == none { continue }
    // A check event's tree is identical to the previous frame's, and the
    // dot already drawn there says the same thing.
    if e.kind == "check" { continue }
    let event = e

    // Each rotate-and-recolor case gets a rotation-only frame first: the
    // post-rotation structure repainted with the pre-rotation colours, so
    // the pivot lands before the colours change. The case's own frame then
    // follows, captioned as the recolor.
    if event.kind in ("case-1", "case-3", "case-4") {
      let intermediate-tree = _color-preserve(events.at(i - 1).tree, event.tree)
      let prev-db = db-by-event.at(i - 1)
      // Cases 1 and 4 demote the parent under the former sibling, pushing
      // the double-black one level deeper; Case 3 only rearranges the
      // sibling's subtree, so it stays put.
      let int-db = if event.kind == "case-3" { prev-db } else {
        event.parent-path + (if prev-db.last() == "L" { "LL" } else { "RR" })
      }
      // The pivot: the sibling moves up in Cases 1 and 4, the near nephew
      // in Case 3.
      let int-pivot = if event.kind == "case-3" {
        event.sibling-path
      } else { event.parent-path }
      let (int-caption, int-step, int-alt) = if event.kind == "case-1" {
        (
          [Rotate parent],
          (kind: "case-1-rotate", parent-path: event.parent-path),
          "Case 1: rotated around the parent — sibling moves up, parent "
            + "demoted. Colors swap next.",
        )
      } else if event.kind == "case-3" {
        (
          [Rotate sibling],
          (kind: "case-3-rotate", sibling-path: event.sibling-path),
          "Case 3: rotated around the sibling — near nephew moves up, "
            + "sibling demoted. Colors swap next.",
        )
      } else {
        (
          [Rotate parent],
          (kind: "case-4-rotate", parent-path: event.parent-path),
          "Case 4: rotated around the parent — sibling moves up, parent "
            + "demoted. Colors swap and the far nephew is painted black next.",
        )
      }
      specs.push((
        structure: intermediate-tree,
        build: th => db-mark(
          with-node(
            _paint(intermediate-tree, bits: bits),
            int-pivot,
            (stroke: th.op.success-stroke),
          ),
          int-db,
        ),
        caption: int-caption,
        step: int-step,
        alt: int-alt,
      ))
    }

    let visited-snapshot = visited-by-event.at(i)
    let caption = none
    let step = (kind: event.kind)
    let alt = ""

    if event.kind == "init" {
      alt = init-alt
    } else if event.kind == "compare" {
      let n = resolve(event.tree, event.path)
      let cmp-text = str(v) + " " + event.cmp + " " + str(n.value)
      caption = cmp-text
      step = (
        kind: if event.found { "found" } else { "compare" },
        path: event.path,
        cmp: event.cmp,
        found: event.found,
      )
      alt = if event.found {
        "Match found at node " + alt-label(n) + "; ready to delete."
      } else {
        "Comparing " + cmp-text + " at node " + alt-label(n) + "; descending."
      }
    } else if event.kind == "descend" {
      caption = [Search for #v]
      step = (kind: "descend", visited: event.visited)
      alt = "Walked the search path for " + str(v) + "; ready to delete."
    } else if event.kind == "not-found" {
      caption = [#v not in tree]
      alt = str(v) + " is not in the tree; nothing to delete."
    } else if event.kind == "mark-target" {
      caption = [Delete #v]
      step = (kind: "mark-target", path: event.target-path)
      alt = ("Marked node "
        + alt-label(resolve(event.tree, event.target-path))
        + " for deletion.")
    } else if event.kind == "find-predecessor" {
      caption = [Find predecessor]
      step = (
        kind: "find-predecessor",
        walk: event.walk,
        predecessor-path: event.predecessor-path,
        target-path: event.target-path,
      )
      alt = ("Node "
        + alt-label(resolve(event.tree, event.target-path))
        + " has two children; walking the left subtree to find the in-order "
        + "predecessor: "
        + alt-label(resolve(event.tree, event.predecessor-path))
        + ".")
    } else if event.kind == "transfer" {
      caption = [Transfer #(event.new-value)]
      step = (
        kind: "transfer",
        target-path: event.target-path,
        predecessor-path: event.predecessor-path,
      )
      alt = ("Copied the predecessor's value "
        + event.new-label
        + " into the target slot; about to remove the predecessor node.")
    } else if event.kind == "excise" {
      caption = [Remove node]
      step = (kind: "excise", path: event.path)
      alt = "Removed the deletion-position node from the tree."
    } else if event.kind == "paint-black-promoted" {
      caption = [Paint child black]
      step = (kind: "paint-black-promoted", path: event.path)
      alt = ("Excised a black node; painted the promoted red child black to "
        + "restore the black height.")
    } else if event.kind == "paint-black-db" {
      caption = [Paint red node black]
      step = (kind: "paint-black-db", path: event.path)
      alt = ("The extra black met a red node; painting it black absorbs the "
        + "extra black and resolves the fix-up.")
    } else if event.kind == "case-1" {
      caption = [Recolor]
      step = (
        kind: "case-1",
        parent-path: event.parent-path,
        new-sibling-path: event.new-sibling-path,
      )
      alt = ("Case 1: swapped parent and sibling colors after the rotation. "
        + "The new sibling is black; continuing with Cases 2 to 4.")
    } else if event.kind == "case-2" {
      caption = [Recolor sibling]
      step = (
        kind: "case-2",
        sibling-path: event.sibling-path,
        new-db-path: event.new-db-path,
      )
      alt = ("Case 2: sibling and both nephews were black. Painted the sibling "
        + "red and propagated the missing black up to the parent.")
    } else if event.kind == "case-3" {
      caption = [Recolor]
      step = (
        kind: "case-3",
        sibling-path: event.sibling-path,
        near-nephew-path: event.near-nephew-path,
      )
      alt = ("Case 3: swapped sibling and near-nephew colors after the "
        + "rotation; Case 4 now applies.")
    } else if event.kind == "case-4" {
      caption = [Recolor]
      step = (kind: "case-4", parent-path: event.parent-path)
      alt = ("Case 4: swapped parent and sibling colors and painted the far "
        + "nephew black after the rotation. Fix-up complete.")
    }

    let db-cur = db-by-event.at(i)
    let build = th => {
      let cur = _paint(event.tree, bits: bits)
      if event.kind == "compare" {
        for p in visited-snapshot {
          cur = with-node(cur, p, (stroke: th.op.search-stroke))
        }
        cur = note-node(
          cur,
          event.path,
          str(v) + " " + event.cmp + " " + str(resolve(event.tree, event.path).value),
        )
      } else if event.kind == "descend" or event.kind == "not-found" {
        for p in event.visited {
          cur = with-node(cur, p, (stroke: th.op.search-stroke))
        }
      } else if event.kind == "mark-target" {
        cur = with-node(cur, event.target-path, (stroke: th.op.attention-stroke))
        cur = note-node(cur, event.target-path, [delete])
      } else if event.kind == "find-predecessor" {
        cur = with-node(cur, event.target-path, (stroke: th.op.attention-stroke))
        for p in event.walk {
          cur = with-node(cur, p, (stroke: th.op.search-stroke))
        }
        cur = note-node(cur, event.predecessor-path, [predecessor])
      } else if event.kind == "transfer" {
        cur = with-node(cur, event.target-path, (stroke: th.op.settled-stroke))
        cur = note-node(cur, event.target-path, [← #(event.new-value)])
        cur = with-node(
          cur,
          event.predecessor-path,
          (stroke: th.op.attention-stroke),
        )
      } else if event.kind == "paint-black-promoted" or event.kind == "paint-black-db" {
        cur = with-node(cur, event.path, (stroke: th.op.settled-stroke))
      } else if event.kind == "case-1" {
        cur = with-node(cur, event.parent-path, (stroke: th.op.success-stroke))
        cur = with-node(
          cur,
          event.new-sibling-path,
          (stroke: th.op.attention-stroke),
        )
      } else if event.kind == "case-2" {
        cur = with-node(cur, event.sibling-path, (stroke: th.op.settled-stroke))
      } else if event.kind == "case-3" {
        cur = with-node(cur, event.sibling-path, (stroke: th.op.success-stroke))
      } else if event.kind == "case-4" {
        cur = with-node(cur, event.parent-path, (stroke: th.op.settled-stroke))
      }
      // "excise" gets no highlight — the structural change speaks for itself.
      db-mark(cur, db-cur)
    }

    specs.push((
      structure: event.tree,
      build: build,
      caption: caption,
      step: step,
      alt: alt,
    ))
  }

  _frames(tc.stamp-result(specs, after), theme, node-style, edge-style)
}

// ===================================================================
// Traversals
// ===================================================================

#let _traversal(tree, paths, name, bits, node-style, edge-style, theme) = tc.render-traversal(
  tree,
  paths,
  name,
  _DS,
  describe(tree),
  base: _ => _paint(tree, bits: bits),
  node-style: node-style,
  edge-style: edge-style,
  theme: theme,
)

/// Animate an in-order (left, root, right) traversal — the sorted walk.
/// -> array
#let in-order-display(
  /// The tree.
  /// -> dictionary
  tree,
  /// Whether every node carries its black-height bit.
  /// -> bool
  bits: false,
  /// Base node styling.
  /// -> dictionary
  node-style: (:),
  /// Base edge styling.
  /// -> dictionary
  edge-style: (:),
  /// Partial theme override for this call.
  /// -> dictionary
  theme: (:),
) = _traversal(
  tree,
  in-order(tree),
  "in-order",
  bits,
  node-style,
  edge-style,
  theme,
)

/// Animate a pre-order (root, left, right) traversal.
/// -> array
#let pre-order-display(
  /// The tree.
  /// -> dictionary
  tree,
  /// Whether every node carries its black-height bit.
  /// -> bool
  bits: false,
  /// Base node styling.
  /// -> dictionary
  node-style: (:),
  /// Base edge styling.
  /// -> dictionary
  edge-style: (:),
  /// Partial theme override for this call.
  /// -> dictionary
  theme: (:),
) = _traversal(
  tree,
  pre-order(tree),
  "pre-order",
  bits,
  node-style,
  edge-style,
  theme,
)

/// Animate a post-order (left, right, root) traversal.
/// -> array
#let post-order-display(
  /// The tree.
  /// -> dictionary
  tree,
  /// Whether every node carries its black-height bit.
  /// -> bool
  bits: false,
  /// Base node styling.
  /// -> dictionary
  node-style: (:),
  /// Base edge styling.
  /// -> dictionary
  edge-style: (:),
  /// Partial theme override for this call.
  /// -> dictionary
  theme: (:),
) = _traversal(
  tree,
  post-order(tree),
  "post-order",
  bits,
  node-style,
  edge-style,
  theme,
)

/// Animate a level-order (breadth-first) traversal.
/// -> array
#let level-order-display(
  /// The tree.
  /// -> dictionary
  tree,
  /// Whether every node carries its black-height bit.
  /// -> bool
  bits: false,
  /// Base node styling.
  /// -> dictionary
  node-style: (:),
  /// Base edge styling.
  /// -> dictionary
  edge-style: (:),
  /// Partial theme override for this call.
  /// -> dictionary
  theme: (:),
) = _traversal(
  tree,
  level-order(tree),
  "level-order",
  bits,
  node-style,
  edge-style,
  theme,
)
