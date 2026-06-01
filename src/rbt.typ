#import "@preview/typsy:0.2.2": (
  Any,
  Int,
  Bool,
  None,
  Refine,
  Dictionary,
  Union,
  class,
)
#import "./tree-anim.typ" as tree-anim

// ===================================================================
// Red-black tree — core data structure + display
// ===================================================================
//
// A BST variant with an extra `red: Bool` field per node, plus
// rebalancing logic in `insert` / `delete` that keeps the four RB
// invariants:
//
//   1. Each node is red (red == true) or black (red == false).
//   2. The root is black after every public operation.
//   3. No red node has a red child.
//   4. Every root-to-NIL path passes through the same number of
//      black nodes.
//
// NIL leaves are represented as `none` and counted as black.
//
// Insert uses Okasaki's `balance`. Delete uses Stefan Kahrs's
// functional algorithm (`balleft` / `balright` / `app`) — we precheck
// `contains(v)` so the recursion can safely assume v is present.
//
// `rotate` is a *structural* operation — it preserves the per-node
// colors of the rotated nodes. Insert/delete fix-ups don't go through
// `rotate`; they apply the balance rules directly.

// --- node-construction helper --------------------------------------
//
// Every internal helper takes `cls` as its first argument so it can
// call `cls.new` without referring to `RBT` (which isn't defined yet
// at the point these helpers are declared).

#let _node(cls, red, l, v, lab, r) = (cls.new)(
  value: v,
  label: lab,
  red: red,
  left: l,
  right: r,
)

// A nil child counts as black.
#let _is-red(n) = n != none and n.red
#let _is-black(n) = n != none and not n.red

#let _blacken(cls, n) = if n == none { none } else if not n.red { n } else {
  _node(cls, false, n.left, n.value, n.label, n.right)
}
#let _redden(cls, n) = if n == none { none } else if n.red { n } else {
  _node(cls, true, n.left, n.value, n.label, n.right)
}

// Resolve a subtree by L/R path string. `path == ""` returns `node` itself.
// Caller is responsible for not walking off a none child mid-path.
#let _resolve-at(node, path) = if path == "" {
  node
} else if path.first() == "L" {
  _resolve-at(node.left, path.slice(1))
} else {
  _resolve-at(node.right, path.slice(1))
}

// Replace the subtree at `path` with `new`, rebuilding the spine above
// it and preserving each spine node's color/value/label/other-child.
#let _replace-at(cls, node, path, new) = if path == "" {
  new
} else if path.first() == "L" {
  _node(
    cls,
    node.red,
    _replace-at(cls, node.left, path.slice(1), new),
    node.value,
    node.label,
    node.right,
  )
} else {
  _node(
    cls,
    node.red,
    node.left,
    node.value,
    node.label,
    _replace-at(cls, node.right, path.slice(1), new),
  )
}

// Change the color of the node at `path`. Used by delete fix-up to
// paint nodes red/black without restructuring.
#let _paint-color-at(cls, tree, path, red) = {
  let n = _resolve-at(tree, path)
  let new = _node(cls, red, n.left, n.value, n.label, n.right)
  _replace-at(cls, tree, path, new)
}

// Copy `value` and `label` into the node at `path`, preserving the
// node's color and children. Used by delete to splice a successor's
// value into the target's position.
#let _set-value-at(cls, tree, path, value, label) = {
  let n = _resolve-at(tree, path)
  let new = _node(cls, n.red, n.left, value, label, n.right)
  _replace-at(cls, tree, path, new)
}

// Build an intermediate tree with `post`'s structure but `pre`'s
// per-value colors. Used by `delete-display` to insert a rotation-only
// frame before each rotate+recolor case (Case 1, 3, 4), so the
// structural change is visible before the color swap. Relies on BST
// ordering of `pre` to look up each node's pre-rotation color by value.
#let _color-preserve(cls, pre, post) = {
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
    let red = if pre-red == none { n.red } else { pre-red }
    _node(cls, red, rebuild(n.left), n.value, n.label, rebuild(n.right))
  }
  rebuild(post)
}

// CLRS-style insertion trace. Returns `(events, tree)` — `tree` is the
// fully-balanced post-insert tree; `events` is an ordered list of the
// steps an animation should show.
//
// We *don't* use Okasaki's balance for insertion: Okasaki collapses
// CLRS Case 2 + Case 3 into one atomic restructuring and has no
// explicit Case 1 (uncle red, recolor), so the operational shape it
// produces can't be narrated as the textbook three-case fix-up shown
// in the standard reference image. By tracing the CLRS algorithm
// directly, both `insert` and `insert-display` produce identical
// trees and the animation matches what `insert` actually does.
//
// Event kinds:
//   (kind: "init",          tree)
//   (kind: "descend",       visited, insert-path, tree)
//                          — single frame; `visited` lists every L/R
//                            path inspected on the way down (root
//                            first), `insert-path` is where the new
//                            leaf will be placed (one past the last
//                            visited node)
//   (kind: "insert",        path, tree)
//   (kind: "check",         path, parent-path, gp-path, uncle-path, tree)
//                          — red-red violation about to be fixed
//   (kind: "recolor",       gp-path, parent-path, uncle-path, tree)
//                          — Case 1 applied (parent + uncle → black,
//                            grandparent → red)
//   (kind: "rotate-zigzag", parent-path, tree)
//                          — Case 2 applied (rotate around parent to
//                            straighten the red-red pair)
//   (kind: "rotate-recolor", gp-path, tree)
//                          — Case 3 applied (rotate around grandparent
//                            + swap grandparent/parent colors)
//   (kind: "blacken-root",  tree)
#let _clrs-insert-trace(cls, tree, v, label) = {
  let events = ()

  // BST descent — record each visited path and the final insertion path
  // (one past the last visited node).
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

  // Splice a new red leaf at insert-path, rebuilding the spine above
  // it. We can't reuse `_replace-at` because the parent's child pointer
  // is `none` here, so we walk the path directly.
  let insert-at(node, path) = if path == "" {
    _node(cls, true, none, v, label, none)
  } else if path.first() == "L" {
    _node(
      cls,
      node.red,
      insert-at(node.left, path.slice(1)),
      node.value,
      node.label,
      node.right,
    )
  } else {
    _node(
      cls,
      node.red,
      node.left,
      node.value,
      node.label,
      insert-at(node.right, path.slice(1)),
    )
  }
  let cur-tree = insert-at(tree, insert-path)
  let cur-path = insert-path
  events.push((kind: "insert", path: cur-path, tree: cur-tree))

  // Fix-up loop. Invariant: `cur-path` is a (possibly) red node whose
  // parent (if any) must be checked for a red-red violation.
  let done = false
  while not done {
    if cur-path == "" {
      // Reached the root. Blacken if red.
      if cur-tree.red {
        cur-tree = _blacken(cls, cur-tree)
        events.push((kind: "blacken-root", tree: cur-tree))
      }
      done = true
    } else {
      let parent-path = cur-path.slice(0, cur-path.len() - 1)
      let parent = _resolve-at(cur-tree, parent-path)
      if not parent.red {
        // No violation. Root may already be black; nothing to do.
        done = true
      } else {
        // Parent is red ⇒ parent isn't the root ⇒ grandparent exists.
        let gp-path = parent-path.slice(0, parent-path.len() - 1)
        let gp = _resolve-at(cur-tree, gp-path)
        let parent-is-left = parent-path.last() == "L"
        let uncle-path = gp-path + (if parent-is-left { "R" } else { "L" })
        let uncle = _resolve-at(cur-tree, uncle-path)

        events.push((
          kind: "check",
          path: cur-path,
          parent-path: parent-path,
          gp-path: gp-path,
          uncle-path: uncle-path,
          tree: cur-tree,
        ))

        if _is-red(uncle) {
          // Case 1: recolor parent + uncle to black, grandparent to red.
          let new-parent = _node(
            cls,
            false,
            parent.left,
            parent.value,
            parent.label,
            parent.right,
          )
          let new-uncle = _node(
            cls,
            false,
            uncle.left,
            uncle.value,
            uncle.label,
            uncle.right,
          )
          let new-gp = if parent-is-left {
            _node(cls, true, new-parent, gp.value, gp.label, new-uncle)
          } else {
            _node(cls, true, new-uncle, gp.value, gp.label, new-parent)
          }
          cur-tree = _replace-at(cls, cur-tree, gp-path, new-gp)
          cur-path = gp-path
          events.push((
            kind: "recolor",
            gp-path: gp-path,
            parent-path: parent-path,
            uncle-path: uncle-path,
            tree: cur-tree,
          ))
        } else {
          // Uncle is black/nil. Case 2 (straighten) then Case 3.
          let current-is-left = cur-path.last() == "L"
          if parent-is-left != current-is-left {
            // Case 2: zigzag — rotate around parent.
            let new-parent-sub = if parent-is-left {
              // current was parent.right; left-rotate around parent.
              let c = parent.right
              _node(
                cls,
                c.red,
                _node(
                  cls,
                  parent.red,
                  parent.left,
                  parent.value,
                  parent.label,
                  c.left,
                ),
                c.value,
                c.label,
                c.right,
              )
            } else {
              // current was parent.left; right-rotate around parent.
              let c = parent.left
              _node(
                cls,
                c.red,
                c.left,
                c.value,
                c.label,
                _node(
                  cls,
                  parent.red,
                  c.right,
                  parent.value,
                  parent.label,
                  parent.right,
                ),
              )
            }
            cur-tree = _replace-at(cls, cur-tree, parent-path, new-parent-sub)
            // After zigzag, the lower red sits at parent-path + side
            // matching parent-is-left (LL for left-left, RR for right-right).
            cur-path = parent-path + (if parent-is-left { "L" } else { "R" })
            events.push((
              kind: "rotate-zigzag",
              parent-path: parent-path,
              tree: cur-tree,
            ))
            // Re-fetch parent: same path, different node (was child).
            parent = _resolve-at(cur-tree, parent-path)
          }

          // Case 3: straight line — rotate around grandparent, swap
          // grandparent/parent colors. gp is at gp-path with gp.red == false;
          // parent is at parent-path with parent.red == true. The result
          // takes gp's color (black) at the new subtree root and parent's
          // color (red) at the demoted grandparent.
          let new-gp = if parent-is-left {
            // Right-rotate around gp.
            _node(
              cls,
              gp.red,
              parent.left,
              parent.value,
              parent.label,
              _node(
                cls,
                parent.red,
                parent.right,
                gp.value,
                gp.label,
                gp.right,
              ),
            )
          } else {
            // Left-rotate around gp.
            _node(
              cls,
              gp.red,
              _node(
                cls,
                parent.red,
                gp.left,
                gp.value,
                gp.label,
                parent.left,
              ),
              parent.value,
              parent.label,
              parent.right,
            )
          }
          cur-tree = _replace-at(cls, cur-tree, gp-path, new-gp)
          events.push((
            kind: "rotate-recolor",
            gp-path: gp-path,
            tree: cur-tree,
          ))
          done = true
        }
      }
    }
  }

  (events: events, tree: cur-tree)
}

// CLRS-style deletion trace. Returns `(events, tree)`. The
// algorithm mirrors what the textbook reference image illustrates:
//
//   1. BST descent to find the target. If absent, return unchanged.
//   2. If the target has two children, walk to its in-order successor
//      (leftmost of the right subtree), transfer the successor's
//      value+label into the target slot, and switch the deletion
//      position to the successor (which has ≤ 1 child).
//   3. Excise the deletion-position node, splicing in its child (or
//      `none`) in its place.
//   4. Determine the fix-up branch from the excised node's color:
//      — excised was red:               nothing to do (black-height
//                                       unchanged).
//      — excised was black, promoted
//        child is red:                  paint the promoted child
//                                       black (absorbs the missing
//                                       black).
//      — excised was black, promoted
//        child is nil/black:            "double-black" at the
//                                       deletion path; run the four-
//                                       case fix-up loop.
//
// Fix-up loop (db-path is the path with one missing black; descends
// the four-case decision tree, mirrored for the symmetric
// "db is right child" branch):
//   — db-path == "":                    extra black is absorbed by
//                                       the root; done.
//   — node at db-path is red:           paint it black; done.
//   — sibling is red:                   Case 1. Rotate around parent,
//                                       swap parent/sibling colors.
//                                       The new sibling (sibling's
//                                       former near child) is black,
//                                       so the next iteration falls
//                                       into Case 2/3/4.
//   — sibling black, both nephews
//     black (or nil):                   Case 2. Paint sibling red and
//                                       push the double-black up to
//                                       parent.
//   — sibling black, near nephew red,
//     far nephew black:                 Case 3. Rotate around sibling,
//                                       swap sibling/near-nephew
//                                       colors. Falls through into
//                                       Case 4.
//   — sibling black, far nephew red:    Case 4. Rotate around parent,
//                                       swap parent/sibling colors,
//                                       paint far nephew black. Done.
//
// Event kinds:
//   (kind: "init",     tree)
//   (kind: "compare",  path, cmp, found, tree)
//                      — emitted only when with-search=true; one per
//                        BST comparison along the search path
//   (kind: "descend",  visited, tree)
//                      — emitted only when with-search=false; a single
//                        frame listing every L/R path inspected
//   (kind: "not-found", tree)
//                      — search ended without finding v; trace ends
//   (kind: "mark-target", target-path, tree)
//   (kind: "find-successor", walk, successor-path, target-path, tree)
//                      — `walk` is the list of paths visited in the
//                        right subtree down to the successor
//   (kind: "transfer", target-path, successor-path, new-value, tree)
//                      — successor's value+label copied into target's
//                        slot
//   (kind: "excise",   path, was-red, tree)
//                      — node physically removed; tree at `path` now
//                        holds the excised node's child (or none)
//   (kind: "paint-black-promoted", path, tree)
//                      — promoted child painted black to absorb the
//                        missing black
//   (kind: "paint-black-db", path, tree)
//                      — double-black hit a red node during loop;
//                        paint black to absorb
//   (kind: "check",    db-path, parent-path, sibling-path, tree)
//                      — about to apply one of Cases 1-4
//   (kind: "case-1",   parent-path, new-sibling-path, tree)
//   (kind: "case-2",   sibling-path, new-db-path, tree)
//   (kind: "case-3",   sibling-path, near-nephew-path, tree)
//   (kind: "case-4",   parent-path, tree)
#let _clrs-delete-trace(cls, tree, v, with-search) = {
  let events = ()

  // BST search: walk down recording each comparison, return the
  // target's path (or none if absent).
  let walk(node, p) = if node == none {
    (steps: (), found: none)
  } else if v == node.value {
    (steps: ((path: p, cmp: "=", found: true),), found: p)
  } else if v < node.value {
    let rest = walk(node.left, p + "L")
    (
      steps: ((path: p, cmp: "<", found: false),) + rest.steps,
      found: rest.found,
    )
  } else {
    let rest = walk(node.right, p + "R")
    (
      steps: ((path: p, cmp: ">", found: false),) + rest.steps,
      found: rest.found,
    )
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
  let target = _resolve-at(cur-tree, target-path)
  let two-children = target.left != none and target.right != none

  events.push((kind: "mark-target", target-path: target-path, tree: cur-tree))

  let excise-path = target-path
  if two-children {
    let succ-walk(p) = {
      let n = _resolve-at(cur-tree, p)
      if n.left == none { (p,) } else { (p,) + succ-walk(p + "L") }
    }
    let walk-paths = succ-walk(target-path + "R")
    let succ-path = walk-paths.last()
    let succ-node = _resolve-at(cur-tree, succ-path)

    events.push((
      kind: "find-successor",
      walk: walk-paths,
      successor-path: succ-path,
      target-path: target-path,
      tree: cur-tree,
    ))

    cur-tree = _set-value-at(
      cls,
      cur-tree,
      target-path,
      succ-node.value,
      succ-node.label,
    )
    events.push((
      kind: "transfer",
      target-path: target-path,
      successor-path: succ-path,
      new-value: succ-node.value,
      tree: cur-tree,
    ))
    excise-path = succ-path
  }

  let excise-node = _resolve-at(cur-tree, excise-path)
  let excise-was-red = excise-node.red
  let replacement = if excise-node.left != none {
    excise-node.left
  } else { excise-node.right }

  // Edge case: excising the root of a single-node tree leaves the
  // tree empty.
  if excise-path == "" and replacement == none {
    events.push((
      kind: "excise",
      path: excise-path,
      was-red: excise-was-red,
      tree: none,
    ))
    return (events: events, tree: none)
  }

  cur-tree = _replace-at(cls, cur-tree, excise-path, replacement)
  events.push((
    kind: "excise",
    path: excise-path,
    was-red: excise-was-red,
    tree: cur-tree,
  ))

  // Red excised: black-height unaffected; done.
  if excise-was-red {
    return (events: events, tree: cur-tree)
  }

  // Promoted child is red: paint it black to absorb the missing black.
  if replacement != none and replacement.red {
    cur-tree = _paint-color-at(cls, cur-tree, excise-path, false)
    events.push((
      kind: "paint-black-promoted",
      path: excise-path,
      tree: cur-tree,
    ))
    return (events: events, tree: cur-tree)
  }

  // Double-black at excise-path; run the four-case fix-up loop.
  let db-path = excise-path
  let done = false
  while not done {
    if db-path == "" {
      done = true
    } else {
      let db-node = _resolve-at(cur-tree, db-path)
      if _is-red(db-node) {
        cur-tree = _paint-color-at(cls, cur-tree, db-path, false)
        events.push((kind: "paint-black-db", path: db-path, tree: cur-tree))
        done = true
      } else {
        let parent-path = db-path.slice(0, db-path.len() - 1)
        let parent = _resolve-at(cur-tree, parent-path)
        let is-left = db-path.last() == "L"
        let sibling-path = parent-path + (if is-left { "R" } else { "L" })
        let sibling = _resolve-at(cur-tree, sibling-path)

        events.push((
          kind: "check",
          db-path: db-path,
          parent-path: parent-path,
          sibling-path: sibling-path,
          tree: cur-tree,
        ))

        if _is-red(sibling) {
          // Case 1: rotate parent, swap parent/sibling colors.
          let new-subtree = if is-left {
            _node(
              cls,
              false,
              _node(
                cls,
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
            _node(
              cls,
              false,
              sibling.left,
              sibling.value,
              sibling.label,
              _node(
                cls,
                true,
                sibling.right,
                parent.value,
                parent.label,
                parent.right,
              ),
            )
          }
          cur-tree = _replace-at(cls, cur-tree, parent-path, new-subtree)
          // db's new path: deeper by one (parent moved under former sibling).
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
          let far-nephew = _resolve-at(cur-tree, far-nephew-path)
          let near-nephew = _resolve-at(cur-tree, near-nephew-path)

          if not _is-red(far-nephew) and not _is-red(near-nephew) {
            // Case 2: paint sibling red, push db up to parent.
            cur-tree = _paint-color-at(cls, cur-tree, sibling-path, true)
            db-path = parent-path
            events.push((
              kind: "case-2",
              sibling-path: sibling-path,
              new-db-path: parent-path,
              tree: cur-tree,
            ))
          } else {
            if not _is-red(far-nephew) {
              // Case 3: rotate sibling, swap sibling/near-nephew colors.
              let new-sibling-sub = if is-left {
                _node(
                  cls,
                  false,
                  near-nephew.left,
                  near-nephew.value,
                  near-nephew.label,
                  _node(
                    cls,
                    true,
                    near-nephew.right,
                    sibling.value,
                    sibling.label,
                    sibling.right,
                  ),
                )
              } else {
                _node(
                  cls,
                  false,
                  _node(
                    cls,
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
              cur-tree = _replace-at(cls, cur-tree, sibling-path, new-sibling-sub)
              events.push((
                kind: "case-3",
                sibling-path: sibling-path,
                near-nephew-path: near-nephew-path,
                tree: cur-tree,
              ))
              // Re-fetch sibling and far-nephew for Case 4.
              sibling = _resolve-at(cur-tree, sibling-path)
              far-nephew = _resolve-at(cur-tree, far-nephew-path)
            }

            // Case 4: rotate parent, swap parent/sibling colors, paint
            // far nephew black.
            let new-subtree = if is-left {
              _node(
                cls,
                parent.red,
                _node(
                  cls,
                  false,
                  parent.left,
                  parent.value,
                  parent.label,
                  sibling.left,
                ),
                sibling.value,
                sibling.label,
                _node(
                  cls,
                  false,
                  far-nephew.left,
                  far-nephew.value,
                  far-nephew.label,
                  far-nephew.right,
                ),
              )
            } else {
              _node(
                cls,
                parent.red,
                _node(
                  cls,
                  false,
                  far-nephew.left,
                  far-nephew.value,
                  far-nephew.label,
                  far-nephew.right,
                ),
                sibling.value,
                sibling.label,
                _node(
                  cls,
                  false,
                  sibling.right,
                  parent.value,
                  parent.label,
                  parent.right,
                ),
              )
            }
            cur-tree = _replace-at(cls, cur-tree, parent-path, new-subtree)
            events.push((
              kind: "case-4",
              parent-path: parent-path,
              tree: cur-tree,
            ))
            done = true
          }
        }
      }
    }
  }

  (events: events, tree: cur-tree)
}

// ===================================================================
// RBT theme — the red/black color palette
// ===================================================================
//
// A small semantic layer above `default-render-theme` that supplies
// the per-node colors for red and black nodes. Operation-specific
// highlights (search/insert/delete/pivot strokes) will live elsewhere
// when the `*-display` methods land — this dict is just the palette.
//
// Each role is a plain color (or a stroke value cetz accepts). Defaults
// are the obvious choice: a red fill for red nodes, a black fill for
// black nodes, white text on both. Strokes match the fill so the node
// reads as a solid disc; override `red-stroke` / `black-stroke` if you
// want a contrasting border.

/// Default semantic theme for the RB tree palette. Pass a partial dict
/// to #raw("set-rbt-theme(..)") to override individual roles.
#let default-rbt-theme = (
  red-fill: red,
  red-stroke: red,
  red-text-fill: white,
  black-fill: black,
  black-stroke: black,
  black-text-fill: white,
)

#let _rbt-theme-keys = (
  "red-fill",
  "red-stroke",
  "red-text-fill",
  "black-fill",
  "black-stroke",
  "black-text-fill",
)

/// Typsy refinement: a dictionary whose keys are a subset of the
/// RBT-theme keys. Used by #raw("set-rbt-theme") and the per-call
/// #raw("theme:") arguments to give early errors on typos.
#let RbtTheme = Refine(
  Dictionary(..Any),
  d => d.keys().all(k => _rbt-theme-keys.contains(k)),
)

#let _rbt-theme-state = state("starling:rbt-theme", default-rbt-theme)

/// Override one or more RBT-theme keys for the rest of the document
/// (state-based, scoped by Typst's normal layout flow). Pass a partial
/// dictionary — only the keys you list are changed; the rest stay at
/// their current values. Unknown keys panic.
#let set-rbt-theme(theme) = {
  for k in theme.keys() {
    if not _rbt-theme-keys.contains(k) {
      panic(
        "set-rbt-theme: unknown key '"
          + k
          + "'. Valid keys: "
          + _rbt-theme-keys.join(", ")
          + ".",
      )
    }
  }
  _rbt-theme-state.update(prev => {
    let next = prev
    for (k, v) in theme.pairs() { next.insert(k, v) }
    next
  })
}

// Merge a partial rbt-theme override into `default-rbt-theme`,
// panicking on unknown keys. Used by per-call `theme:` arguments
// (the non-state path).
#let _merge-rbt-theme(override) = {
  for k in override.keys() {
    if not _rbt-theme-keys.contains(k) {
      panic(
        "rbt-theme: unknown key '"
          + k
          + "'. Valid keys: "
          + _rbt-theme-keys.join(", ")
          + ".",
      )
    }
  }
  let next = default-rbt-theme
  for (k, v) in override.pairs() { next.insert(k, v) }
  next
}

#let _resolve-rbt-theme-arg(theme) = if theme == auto {
  auto
} else { _merge-rbt-theme(theme) }
#let _resolve-render-theme-arg(theme) = if theme == auto {
  auto
} else { tree-anim._merge-render-theme(theme) }

// Apply the rbt-theme palette (red-fill / red-stroke / red-text-fill or
// the black equivalents) to every node in `tree`, returning the updated
// renderer. Used by `display` and `insert-display` to colorize a
// snapshot before layering operation-specific highlights on top. When
// `bits: true`, each node also gets a tag style carrying its
// black-height bit ("0" for red, "1" for black), drawn just outside
// the node's NE corner by `draw-tree`.
#let _paint-palette(r, tree, rbt, bits: false) = {
  let walk(node, path) = if node == none { () } else {
    (path,) + walk(node.left, path + "L") + walk(node.right, path + "R")
  }
  let paths = walk(tree, "")
  let result = r
  for p in paths {
    let n = _resolve-at(tree, p)
    let fill = if n.red { rbt.red-fill } else { rbt.black-fill }
    let stroke = if n.red { rbt.red-stroke } else { rbt.black-stroke }
    let text-fill = if n.red {
      rbt.red-text-fill
    } else { rbt.black-text-fill }
    let style = (fill: fill, stroke: stroke, text-fill: text-fill)
    if bits { style.insert("tag", if n.red { "0" } else { "1" }) }
    result = (result.patch)(f => (f.style-node)(p, ..style))
  }
  result
}

// ===================================================================
// Frame construction for RBT displays
// ===================================================================
//
// Parallel to bst.typ's `_make-frames`. The `op-arg` passed in by
// lib.typ helpers (the shared op-theme — see `src/op-theme.typ`) is
// forwarded to `build-snapshots` so future RBT operation animations
// can use it; the rbt-theme palette is read here from state, since
// the lib.typ helpers don't carry it. Each helper wraps itself in
// one `context { }` block, so the inline `_rbt-theme-state.get()`
// inside the builder runs in a context as required.
//
// `theme` is the per-call rbt-theme override (or `auto` to defer to
// state). It only shadows the rbt-theme reading; op-theme and
// render-theme are resolved independently from their own arguments.
#let _make-frames-rbt(
  tree,
  build-snapshots,
  captions,
  steps-meta,
  alts,
  theme,
  render-theme,
) = {
  let n = captions.len()
  range(n).map(i => (tree-anim.Frame.new)(
    _builder: (fn: (op-arg, rt-arg) => {
      let rbt = if theme == auto { _rbt-theme-state.get() } else { theme }
      let rt = if render-theme == auto { rt-arg } else { render-theme }
      let snaps = build-snapshots(rbt, op-arg, rt)
      tree-anim._render-canvas(tree, snaps.at(i), (:), (:), rt)
    }),
    caption: captions.at(i),
    step: steps-meta.at(i),
    alt: alts.at(i),
  ))
}

// Per-frame variant of `_make-frames-rbt` for animations that cross
// multiple tree states (e.g. `insert-display`, whose fix-up steps each
// produce a new tree). Each `specs` entry carries its own tree and its
// own `build(rbt, op, rt) -> Snapshot` closure. The closure should
// return a single snapshot — typically by calling `make-renderer(tree)`
// then `_paint-palette` then any operation-specific patches and
// returning `r.snapshots.first()`.
#let _make-frames-rbt-multi(specs, theme, render-theme) = {
  specs.map(s => (tree-anim.Frame.new)(
    _builder: (fn: (op-arg, rt-arg) => {
      let rbt = if theme == auto { _rbt-theme-state.get() } else { theme }
      let rt = if render-theme == auto { rt-arg } else { render-theme }
      let snap = (s.build)(rbt, op-arg, rt)
      tree-anim._render-canvas(s.tree, snap, (:), (:), rt)
    }),
    caption: s.caption,
    step: s.step,
    alt: s.alt,
  ))
}

// ===================================================================
// The RBT class
// ===================================================================
//
// `value` orders the BST. `label` is the rendered content (defaults to
// `auto` ⇒ `str(value)`, matching `BST`). `red` is the node color
// (`true` = red, `false` = black). `left` and `right` are child
// subtrees, with `none` standing in for NIL leaves.
//
// Animations (`*-display` methods) will land in a follow-up stage —
// this file is intentionally just the data structure.
#let RBT = class(
  name: "RBT",
  fields: (
    value: Int,
    label: Any,
    red: Bool,
    left: Union(None, Any),
    right: Union(None, Any),
  ),
  methods: (
    by-value: (self, v) => {
      let walk(node, path) = if node == none {
        panic("by-value: value not found in tree: " + repr(v))
      } else if v == node.value {
        path
      } else if v < node.value {
        walk(node.left, path + "L")
      } else {
        walk(node.right, path + "R")
      }
      walk(self, "")
    },
    path-to: (self, v) => {
      let walk(node, path) = if node == none {
        panic("path-to: value not found in tree: " + repr(v))
      } else if v == node.value {
        (path,)
      } else if v < node.value {
        (path,) + walk(node.left, path + "L")
      } else {
        (path,) + walk(node.right, path + "R")
      }
      walk(self, "")
    },
    resolve: (self, path) => {
      let walk(node, cps) = if node == none or cps.len() == 0 {
        node
      } else if cps.first() == "L" {
        walk(node.left, cps.slice(1))
      } else {
        walk(node.right, cps.slice(1))
      }
      walk(self, path.codepoints())
    },
    contains: (self, v) => if v == self.value {
      true
    } else if v < self.value {
      self.left != none and (self.left.contains)(v)
    } else {
      self.right != none and (self.right.contains)(v)
    },
    describe: self => {
      let c = if self.red { "R" } else { "B" }
      let head = str(self.value) + c
      if self.left == none and self.right == none {
        head
      } else {
        let l = if self.left == none { "empty" } else { (self.left.describe)() }
        let r = if self.right == none { "empty" } else {
          (self.right.describe)()
        }
        head + " (left: " + l + ", right: " + r + ")"
      }
    },
    in-order: (self) => {
      let walk(node, path) = if node == none { () } else {
        walk(node.left, path + "L") + (path,) + walk(node.right, path + "R")
      }
      walk(self, "")
    },
    pre-order: (self) => {
      let walk(node, path) = if node == none { () } else {
        (path,) + walk(node.left, path + "L") + walk(node.right, path + "R")
      }
      walk(self, "")
    },
    post-order: (self) => {
      let walk(node, path) = if node == none { () } else {
        walk(node.left, path + "L") + walk(node.right, path + "R") + (path,)
      }
      walk(self, "")
    },
    level-order: (self) => {
      let result = ()
      let queue = ("",)
      while queue.len() > 0 {
        let path = queue.first()
        queue = queue.slice(1)
        let n = (self.resolve)(path)
        if n != none {
          result.push(path)
          queue.push(path + "L")
          queue.push(path + "R")
        }
      }
      result
    },
    insert: (self, v, label: auto) => {
      let cls = self.meta.cls
      _clrs-insert-trace(cls, self, v, label).tree
    },
    // Convenience for the common int-only case. For custom labels,
    // chain `.insert(v, label: ...)` calls directly.
    insert-many: (self, ..vals) => {
      let tree = self
      for v in vals.pos() {
        tree = (tree.insert)(v)
      }
      tree
    },
    delete: (self, v) => {
      let cls = self.meta.cls
      let result = _clrs-delete-trace(cls, self, v, false).tree
      // CLRS's fix-up can leave a red root (e.g. after Case 2 propagates
      // a missing black to the root, or after Case 1 swaps the root's
      // color). Blacken unconditionally to restore the root-is-black
      // invariant.
      if result == none { none } else { _blacken(cls, result) }
    },
    rotate: (self, child) => {
      // Structural rotation — preserves each rotated node's color.
      // RB rebalancing in insert/delete does not go through here.
      let cls = self.meta.cls
      let child-path = (self.by-value)(child.value)
      if child-path == "" {
        panic("rotate: cannot rotate the root with itself")
      }
      let parent-path = child-path.slice(0, child-path.len() - 1)
      let parent = (self.resolve)(parent-path)
      let is-right = child-path.last() == "L"
      let rotated = if is-right {
        _node(
          cls,
          child.red,
          child.left,
          child.value,
          child.label,
          _node(
            cls,
            parent.red,
            child.right,
            parent.value,
            parent.label,
            parent.right,
          ),
        )
      } else {
        _node(
          cls,
          child.red,
          _node(
            cls,
            parent.red,
            parent.left,
            parent.value,
            parent.label,
            child.left,
          ),
          child.value,
          child.label,
          child.right,
        )
      }
      let replace-at(tree, path, new-subtree) = if path == "" {
        new-subtree
      } else if path.first() == "L" {
        _node(
          cls,
          tree.red,
          replace-at(tree.left, path.slice(1), new-subtree),
          tree.value,
          tree.label,
          tree.right,
        )
      } else {
        _node(
          cls,
          tree.red,
          tree.left,
          tree.value,
          tree.label,
          replace-at(tree.right, path.slice(1), new-subtree),
        )
      }
      replace-at(self, parent-path, rotated)
    },
    // Test helper. Verifies BST order plus the four RB invariants and
    // panics on the first violation. Returns true if everything checks
    // out, so callers can write `#assert((t.check-invariants)())`.
    check-invariants: (self) => {
      if self.red {
        panic(
          "RB invariant: root must be black, but value "
            + str(self.value)
            + " is red",
        )
      }
      let bh(node) = if node == none {
        0
      } else {
        if node.red {
          if _is-red(node.left) {
            panic(
              "RB invariant: red node "
                + str(node.value)
                + " has red left child "
                + str(node.left.value),
            )
          }
          if _is-red(node.right) {
            panic(
              "RB invariant: red node "
                + str(node.value)
                + " has red right child "
                + str(node.right.value),
            )
          }
        }
        if node.left != none and node.left.value > node.value {
          panic(
            "BST invariant violated at "
              + str(node.value)
              + ": left child "
              + str(node.left.value)
              + " > node",
          )
        }
        if node.right != none and node.right.value < node.value {
          panic(
            "BST invariant violated at "
              + str(node.value)
              + ": right child "
              + str(node.right.value)
              + " < node",
          )
        }
        let lb = bh(node.left)
        let rb = bh(node.right)
        if lb != rb {
          panic(
            "RB invariant: black-height mismatch at "
              + str(node.value)
              + " (left: "
              + str(lb)
              + ", right: "
              + str(rb)
              + ")",
          )
        }
        lb + (if node.red { 0 } else { 1 })
      }
      let _ = bh(self)
      true
    },
    display: (self, bits: false, theme: auto, render-theme: auto) => {
      // Returns a one-element Frame array — the static tree, with each
      // node colored from the active RBT palette by its `red` field.
      // `step` is none. With `bits: true`, each node gets a small
      // tag pinned outside its NE corner — "0" for red, "1" for
      // black — so users can count black-height down any path.
      let captions = (none,)
      let steps-meta = (none,)
      let alts = ("Red-black tree: " + (self.describe)() + ".",)
      let build-snapshots = (rbt, _op, _rt) => {
        let r = tree-anim.make-renderer(self)
        r = _paint-palette(r, self, rbt, bits: bits)
        r.snapshots
      }
      _make-frames-rbt(
        self,
        build-snapshots,
        captions,
        steps-meta,
        alts,
        _resolve-rbt-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
      )
    },
    insert-display: (self, v, bits: false, theme: auto, render-theme: auto) => {
      // CLRS-style insertion animation. Frame sequence (step.kind):
      //   1. "init"                   — pre-insertion tree
      //   2. "descend"                — search path highlighted at once
      //   3. "insert"                 — new red leaf appears
      //   4. (per fix-up iteration:)
      //      "check"                  — red-red violation annotated ↑check
      //      "recolor" | "rotate-zigzag" | "rotate-recolor"
      //                               — Case 1 / Case 2 / Case 3 applied
      //   5. "blacken-root"           — only if the root ended up red
      //
      // Frames share the rbt-theme palette so red and black nodes wear
      // their semantic colors; operation-specific strokes layer on top
      // from the op-theme (search-stroke on descent, settled-stroke on
      // the new leaf, danger-stroke + ↑check note on violations,
      // attention-stroke on Case-2 rotation pivots, settled-stroke +
      // success-stroke on the new subtree root after Case 1 / Case 3).
      let cls = self.meta.cls
      let trace = _clrs-insert-trace(cls, self, v, auto)
      let events = trace.events

      let resolved-rbt = _resolve-rbt-theme-arg(theme)
      let resolved-render = _resolve-render-theme-arg(render-theme)

      let init-alt = (
        "Red-black tree: "
          + (self.describe)()
          + ". About to insert "
          + str(v)
          + "."
      )

      let specs = ()
      for e in events {
        let event = e
        let caption = none
        let step = (kind: event.kind)
        let alt = ""

        if event.kind == "init" {
          step = (kind: "init")
          alt = init-alt
        } else if event.kind == "descend" {
          caption = [Search for #v]
          step = (
            kind: "descend",
            visited: event.visited,
            insert-path: event.insert-path,
          )
          alt = (
            "Walked the BST search path for "
              + str(v)
              + "; insertion point is one step beyond the last visited node."
          )
        } else if event.kind == "insert" {
          caption = [Insert #v as red leaf]
          step = (kind: "insert", path: event.path)
          alt = "Inserted " + str(v) + " as a new red leaf."
        } else if event.kind == "check" {
          caption = [Red-red violation]
          let cv = _resolve-at(event.tree, event.path).value
          let pv = _resolve-at(event.tree, event.parent-path).value
          step = (
            kind: "check",
            path: event.path,
            parent-path: event.parent-path,
            gp-path: event.gp-path,
            uncle-path: event.uncle-path,
          )
          alt = (
            "Red-red violation between nodes "
              + str(cv)
              + " and "
              + str(pv)
              + "."
          )
        } else if event.kind == "recolor" {
          caption = [Case 1: recolor]
          step = (
            kind: "recolor",
            gp-path: event.gp-path,
            parent-path: event.parent-path,
            uncle-path: event.uncle-path,
          )
          alt = (
            "Case 1: parent and uncle recolored black, grandparent recolored red. Continuing the check at the grandparent."
          )
        } else if event.kind == "rotate-zigzag" {
          caption = [Case 2: rotate to straighten]
          step = (kind: "rotate-zigzag", parent-path: event.parent-path)
          alt = (
            "Case 2: rotated around the parent to align the red-red pair into a straight line."
          )
        } else if event.kind == "rotate-recolor" {
          caption = [Case 3: rotate and color swap]
          step = (kind: "rotate-recolor", gp-path: event.gp-path)
          alt = (
            "Case 3: rotated around the grandparent and swapped its color with the new subtree root."
          )
        } else if event.kind == "blacken-root" {
          caption = [Blacken root]
          step = (kind: "blacken-root")
          alt = "Blackened the root to restore the RB invariants."
        }

        let build = (rbt, op, _rt) => {
          let r = tree-anim.make-renderer(event.tree)
          r = _paint-palette(r, event.tree, rbt, bits: bits)
          if event.kind == "descend" {
            for p in event.visited {
              r = (r.patch)(f => (f.style-node)(p, stroke: op.search-stroke))
            }
          } else if event.kind == "insert" {
            r = (r.patch)(f => (f.style-node)(event.path, stroke: op.settled-stroke))
            r = (r.patch)(f => (f.style-edge)(event.path, stroke: op.success-stroke))
          } else if event.kind == "check" {
            r = (r.patch)(f => (f.style-node)(event.path, stroke: op.attention-stroke))
            r = (r.patch)(f => (f.style-node)(event.parent-path, stroke: op.attention-stroke))
            r = (r.patch)(f => (f.note-node)(event.path, [↑ check]))
          } else if event.kind == "recolor" {
            r = (r.patch)(f => (f.style-node)(event.gp-path, stroke: op.settled-stroke))
            r = (r.patch)(f => (f.style-node)(event.parent-path, stroke: op.settled-stroke))
            if _resolve-at(event.tree, event.uncle-path) != none {
              r = (r.patch)(f => (f.style-node)(event.uncle-path, stroke: op.settled-stroke))
            }
          } else if event.kind == "rotate-zigzag" {
            r = (r.patch)(f => (f.style-node)(event.parent-path, stroke: op.attention-stroke))
          } else if event.kind == "rotate-recolor" {
            r = (r.patch)(f => (f.style-node)(event.gp-path, stroke: op.settled-stroke))
            r = (r.patch)(f => (f.style-edge)(event.gp-path, stroke: op.success-stroke))
          } else if event.kind == "blacken-root" {
            r = (r.patch)(f => (f.style-node)("", stroke: op.settled-stroke))
          }
          r.snapshots.first()
        }

        specs.push((
          tree: event.tree,
          build: build,
          caption: caption,
          step: step,
          alt: alt,
        ))
      }

      _make-frames-rbt-multi(specs, resolved-rbt, resolved-render)
    },
    delete-display: (
      self,
      v,
      search: false,
      bits: false,
      theme: auto,
      render-theme: auto,
    ) => {
      // CLRS-style deletion animation. Frame sequence (step.kind):
      //   1. "init"
      //   2. If `search: true`: one "compare" frame per BST comparison
      //      (mirrors BST `delete-display`). Otherwise: a single
      //      "descend" frame highlighting the full search path.
      //   3. If `v` is not in the tree: "not-found"; animation ends.
      //   4. "mark-target" — target node highlighted with attention-stroke.
      //   5. If target has two children: "find-successor" walks the
      //      right subtree to the in-order successor; "transfer" copies
      //      the successor's value+label into the target slot.
      //   6. "excise" — deletion-position node removed (its child, if
      //      any, takes its place).
      //   7. Branch on the excised node's color:
      //      — red: nothing more (black-height unaffected).
      //      — black, promoted child red: "paint-black-promoted".
      //      — black, no red promotion: enter the fix-up loop.
      //   8. Fix-up iterations (each is "check" + one case):
      //      "case-1" (sibling red, rotate parent),
      //      "case-2" (recolor sibling, propagate db up),
      //      "case-3" (rotate sibling),
      //      "case-4" (rotate parent, resolved).
      //      The loop may also terminate via "paint-black-db" if the
      //      missing black walks up to a red node.
      let cls = self.meta.cls
      let trace = _clrs-delete-trace(cls, self, v, search)
      let events = trace.events

      let resolved-rbt = _resolve-rbt-theme-arg(theme)
      let resolved-render = _resolve-render-theme-arg(render-theme)

      let init-alt = (
        "Red-black tree: "
          + (self.describe)()
          + ". About to delete "
          + str(v)
          + "."
      )

      // For compare frames (with search prefix), accumulate descended
      // paths so each frame shows the full search trail.
      let visited-by-event = ()
      let visited-acc = ()
      for e in events {
        if e.kind == "compare" {
          visited-acc = visited-acc + (e.path,)
        }
        visited-by-event.push(visited-acc)
      }

      // Per-event double-black path (or `none`). The trace doesn't carry
      // this directly, so we walk events once to compute it: db appears
      // after a black "excise" when the loop will run, persists across
      // "check", moves with cases 1 / 2, is unchanged by case 3, and is
      // resolved by case 4 / paint-black-db / paint-black-promoted.
      // The marker is drawn as an "o" mark at the child end of the edge
      // into the db node, matching the textbook convention. Root db
      // ("" path) has no parent edge — it propagates into root absorption
      // implicitly, so we just skip the marker rather than synthesising
      // a floating dot.
      let db-by-event = ()
      let cur-db = none
      for (idx, e) in events.enumerate() {
        if e.kind == "excise" and not e.was-red {
          let next-kind = if idx + 1 < events.len() {
            events.at(idx + 1).kind
          } else { none }
          if next-kind != "paint-black-promoted" {
            cur-db = e.path
          }
        } else if e.kind == "paint-black-promoted" {
          cur-db = none
        } else if e.kind == "case-1" {
          // After case 1 the db is the parent's new near grandchild:
          // parent moved under the former sibling, so db sits at
          // parent-path + "LL" (db was the left child) or "RR".
          let suffix = e.new-sibling-path.slice(e.parent-path.len())
          cur-db = if suffix == "LR" {
            e.parent-path + "LL"
          } else {
            e.parent-path + "RR"
          }
        } else if e.kind == "case-2" {
          // If db propagated up to a red node, the very next loop step
          // is paint-black-db (the red node absorbs the extra black).
          // Suppress the marker — "red + double-black" isn't a stable
          // node state and painting a red node as double-black reads
          // wrong.
          let new-db = e.new-db-path
          let new-db-node = if new-db == "" {
            none
          } else { _resolve-at(e.tree, new-db) }
          cur-db = if _is-red(new-db-node) { none } else { new-db }
        } else if e.kind == "case-3" {
          // db is unchanged by case 3; case 4 follows in the next event.
        } else if e.kind == "case-4" {
          cur-db = none
        } else if e.kind == "paint-black-db" {
          cur-db = none
        } else if e.kind == "check" {
          cur-db = e.db-path
        }
        db-by-event.push(cur-db)
      }

      let specs = ()
      for (i, e) in events.enumerate() {
        // The empty-tree excise of a single-node delete: skip the frame
        // (no tree to render). The previous "mark-target" frame already
        // conveys the imminent deletion via its caption.
        if e.tree == none { continue }
        // The "check" event marks each fix-up iteration's entry point;
        // its tree is identical to the previous frame's, and the
        // double-black dot already drawn on that frame conveys the same
        // information. Skip to avoid a redundant "Double-black" frame.
        if e.kind == "check" { continue }
        let event = e

        // Each rotate+recolor case (1 / 3 / 4) gets a rotation-only
        // intermediate frame inserted first: the post-rotation
        // structure repainted with the pre-rotation per-node colors,
        // so the structural pivot lands before the color swap. The
        // existing case-N spec then follows, captioned as the recolor.
        if event.kind == "case-1" or event.kind == "case-3" or event.kind == "case-4" {
          let pre-tree = events.at(i - 1).tree
          let intermediate-tree = _color-preserve(cls, pre-tree, event.tree)
          let prev-db = db-by-event.at(i - 1)
          // Rotation pushes db one level deeper for case-1 and case-4
          // (parent demoted under former sibling); case-3 only rearranges
          // the sibling's subtree, so db stays put.
          let int-db = if event.kind == "case-3" {
            prev-db
          } else {
            let is-left = prev-db.last() == "L"
            event.parent-path + (if is-left { "LL" } else { "RR" })
          }
          // The pivot lands at parent-path (case-1 / case-4: sibling
          // moves up) or sibling-path (case-3: near nephew moves up).
          let int-pivot = if event.kind == "case-3" {
            event.sibling-path
          } else {
            event.parent-path
          }
          let (int-caption, int-step, int-alt) = if event.kind == "case-1" {
            (
              [Case 1: rotate parent],
              (kind: "case-1-rotate", parent-path: event.parent-path),
              "Case 1: rotated around the parent — sibling moves up, parent demoted. Colors swap next.",
            )
          } else if event.kind == "case-3" {
            (
              [Case 3: rotate sibling],
              (kind: "case-3-rotate", sibling-path: event.sibling-path),
              "Case 3: rotated around the sibling — near nephew moves up, sibling demoted. Colors swap next.",
            )
          } else {
            (
              [Case 4: rotate parent],
              (kind: "case-4-rotate", parent-path: event.parent-path),
              "Case 4: rotated around the parent — sibling moves up, parent demoted. Colors swap and far nephew is painted black next.",
            )
          }
          let int-build = (rbt, op, rt) => {
            let r = tree-anim.make-renderer(intermediate-tree)
            r = _paint-palette(r, intermediate-tree, rbt, bits: bits)
            r = (r.patch)(f => (f.style-node)(int-pivot, stroke: op.success-stroke))
            if int-db != none and int-db != "" {
              r = (r.patch)(f => (f.style-edge)(
                int-db,
                mark: (end: "o", fill: rt.edge-stroke, scale: 2, offset: 0.2),
                force-show: true,
              ))
            }
            r.snapshots.first()
          }
          specs.push((
            tree: intermediate-tree,
            build: int-build,
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
          step = (kind: "init")
          alt = init-alt
        } else if event.kind == "compare" {
          let nv = _resolve-at(event.tree, event.path).value
          let cmp-text = str(v) + " " + event.cmp + " " + str(nv)
          caption = cmp-text
          step = (
            kind: "compare",
            path: event.path,
            cmp: event.cmp,
            found: event.found,
          )
          alt = if event.found {
            "Match found at node " + str(nv) + "; ready to delete."
          } else {
            "Comparing " + cmp-text + " at node " + str(nv) + "; descending."
          }
        } else if event.kind == "descend" {
          caption = [Search for #v]
          step = (kind: "descend", visited: event.visited)
          alt = (
            "Walked the BST search path for "
              + str(v)
              + "; ready to delete."
          )
        } else if event.kind == "not-found" {
          caption = [#v not in tree]
          step = (kind: "not-found")
          alt = str(v) + " is not in the tree; nothing to delete."
        } else if event.kind == "mark-target" {
          caption = [Delete #v]
          step = (kind: "mark-target", path: event.target-path)
          alt = "Marked node " + str(v) + " for deletion."
        } else if event.kind == "find-successor" {
          let sv = _resolve-at(event.tree, event.successor-path).value
          caption = [Find successor]
          step = (
            kind: "find-successor",
            walk: event.walk,
            successor-path: event.successor-path,
            target-path: event.target-path,
          )
          alt = (
            "Node "
              + str(v)
              + " has two children; walking the right subtree to find the in-order successor: "
              + str(sv)
              + "."
          )
        } else if event.kind == "transfer" {
          caption = [Transfer #(event.new-value)]
          step = (
            kind: "transfer",
            target-path: event.target-path,
            successor-path: event.successor-path,
          )
          alt = (
            "Copied successor's value "
              + str(event.new-value)
              + " into the target slot; about to remove the successor node."
          )
        } else if event.kind == "excise" {
          caption = [Remove node]
          step = (kind: "excise", path: event.path)
          alt = "Removed the deletion-position node from the tree."
        } else if event.kind == "paint-black-promoted" {
          caption = [Paint child black]
          step = (kind: "paint-black-promoted", path: event.path)
          alt = (
            "Excised a black node; painted the promoted red child black to restore black-height balance."
          )
        } else if event.kind == "paint-black-db" {
          caption = [Paint red node black]
          step = (kind: "paint-black-db", path: event.path)
          alt = (
            "Extra black met a red node; painting it black absorbs the extra black and resolves the fix-up."
          )
        } else if event.kind == "check" {
          caption = [Double-black]
          step = (
            kind: "check",
            db-path: event.db-path,
            parent-path: event.parent-path,
            sibling-path: event.sibling-path,
          )
          alt = (
            "Black-height short by one in this subtree; investigating the parent / sibling configuration."
          )
        } else if event.kind == "case-1" {
          caption = [Case 1: recolor]
          step = (
            kind: "case-1",
            parent-path: event.parent-path,
            new-sibling-path: event.new-sibling-path,
          )
          alt = (
            "Case 1: swapped parent/sibling colors after the rotation. The new sibling is black; continuing with Cases 2–4."
          )
        } else if event.kind == "case-2" {
          caption = [Case 2: recolor sibling]
          step = (
            kind: "case-2",
            sibling-path: event.sibling-path,
            new-db-path: event.new-db-path,
          )
          alt = (
            "Case 2: sibling and both nephews were black. Painted sibling red and propagated the missing black up to parent."
          )
        } else if event.kind == "case-3" {
          caption = [Case 3: recolor]
          step = (
            kind: "case-3",
            sibling-path: event.sibling-path,
            near-nephew-path: event.near-nephew-path,
          )
          alt = (
            "Case 3: swapped sibling/near-nephew colors after the rotation; Case 4 now applies."
          )
        } else if event.kind == "case-4" {
          caption = [Case 4: recolor]
          step = (kind: "case-4", parent-path: event.parent-path)
          alt = (
            "Case 4: swapped parent/sibling colors and painted the far nephew black after the rotation. Fix-up complete."
          )
        }

        let db-cur = db-by-event.at(i)

        let build = (rbt, op, rt) => {
          let r = tree-anim.make-renderer(event.tree)
          r = _paint-palette(r, event.tree, rbt, bits: bits)
          if event.kind == "compare" {
            for p in visited-snapshot {
              r = (r.patch)(f => (f.style-node)(p, stroke: op.search-stroke))
            }
            let nv = _resolve-at(event.tree, event.path).value
            r = (r.patch)(f => (f.note-node)(
              event.path,
              str(v) + " " + event.cmp + " " + str(nv),
            ))
          } else if event.kind == "descend" {
            for p in event.visited {
              r = (r.patch)(f => (f.style-node)(p, stroke: op.search-stroke))
            }
          } else if event.kind == "not-found" {
            for p in event.visited {
              r = (r.patch)(f => (f.style-node)(p, stroke: op.search-stroke))
            }
          } else if event.kind == "mark-target" {
            r = (r.patch)(f => (f.style-node)(event.target-path, stroke: op.attention-stroke))
            r = (r.patch)(f => (f.note-node)(event.target-path, [delete]))
          } else if event.kind == "find-successor" {
            r = (r.patch)(f => (f.style-node)(event.target-path, stroke: op.attention-stroke))
            for p in event.walk {
              r = (r.patch)(f => (f.style-node)(p, stroke: op.search-stroke))
            }
            r = (r.patch)(f => (f.note-node)(event.successor-path, [successor]))
          } else if event.kind == "transfer" {
            r = (r.patch)(f => (f.style-node)(event.target-path, stroke: op.settled-stroke))
            r = (r.patch)(f => (f.note-node)(
              event.target-path,
              [← #(event.new-value)],
            ))
            r = (r.patch)(f => (f.style-node)(event.successor-path, stroke: op.attention-stroke))
          } else if event.kind == "excise" {
            // No special highlight — the structural change speaks for itself.
          } else if event.kind == "paint-black-promoted" {
            r = (r.patch)(f => (f.style-node)(event.path, stroke: op.settled-stroke))
          } else if event.kind == "paint-black-db" {
            r = (r.patch)(f => (f.style-node)(event.path, stroke: op.settled-stroke))
          } else if event.kind == "check" {
            r = (r.patch)(f => (f.style-node)(event.parent-path, stroke: op.attention-stroke))
            r = (r.patch)(f => (f.style-node)(event.sibling-path, stroke: op.attention-stroke))
            let db-node = _resolve-at(event.tree, event.db-path)
            if db-node != none {
              r = (r.patch)(f => (f.style-node)(event.db-path, stroke: op.attention-stroke))
            }
          } else if event.kind == "case-1" {
            r = (r.patch)(f => (f.style-node)(event.parent-path, stroke: op.success-stroke))
            r = (r.patch)(f => (f.style-node)(event.new-sibling-path, stroke: op.attention-stroke))
          } else if event.kind == "case-2" {
            r = (r.patch)(f => (f.style-node)(event.sibling-path, stroke: op.settled-stroke))
          } else if event.kind == "case-3" {
            r = (r.patch)(f => (f.style-node)(event.sibling-path, stroke: op.success-stroke))
          } else if event.kind == "case-4" {
            r = (r.patch)(f => (f.style-node)(event.parent-path, stroke: op.settled-stroke))
          }
          // Mark the edge into the double-black node with a filled
          // circular end-cap (textbook convention — see the reference
          // image in repo root). Skip root db (no parent edge).
          // `force-show` makes the stub edge render even when the db
          // position is now nil (immediately after an excise or a
          // case-1 deepen), so the dot still lands where the missing
          // black logically lives. The dot's fill mirrors the edge
          // stroke so a render-theme override carries through.
          if db-cur != none and db-cur != "" {
            r = (r.patch)(f => (f.style-edge)(
              db-cur,
              mark: (end: "o", fill: rt.edge-stroke, scale: 2, offset: 0.2),
              force-show: true,
            ))
          }
          r.snapshots.first()
        }

        specs.push((
          tree: event.tree,
          build: build,
          caption: caption,
          step: step,
          alt: alt,
        ))
      }

      _make-frames-rbt-multi(specs, resolved-rbt, resolved-render)
    },
  ),
)

/// Factory: build an #raw("RBT") from a positional list of values. The
/// first argument becomes the (black) root; the rest are
/// #raw("insert")-ed in order, so the CLRS fix-ups produce the final
/// shape. Each argument is either a bare value (label defaults to
/// #raw("auto") ⇒ #raw("str(value)")) or a #raw("(value, label)")
/// 2-tuple. Equivalent to constructing the root with
/// #raw("(RBT.new)(value: v0, label: l0, red: false, left: none,
/// right: none)") and then chaining #raw(".insert(v, label: l)")
/// calls, but tighter to seed sample trees:
///
/// ```typc
/// // root 8, then insert 4, 12, 2, 6, 10, 14, 1
/// let t = rbt(8, 4, 12, 2, 6, 10, 14, 1)
///
/// // mixed labels
/// let t = rbt((8, [eight]), 4, (12, [XII]), 2)
/// ```
///
/// -> dictionary
#let rbt(
  /// Positional values. Each is either a bare value or a
  /// #raw("(value, label)") 2-tuple. At least one is required (the
  /// root).
  ..vals,
) = {
  let xs = vals.pos()
  assert(
    xs.len() > 0,
    message: "rbt: at least one value required (the root)",
  )
  let parse(x) = if type(x) == array {
    assert(
      x.len() == 2,
      message: "rbt: expected (value, label) 2-tuple, got " + repr(x),
    )
    (value: x.at(0), label: x.at(1))
  } else {
    (value: x, label: auto)
  }
  let head = parse(xs.first())
  let tree = (RBT.new)(
    value: head.value,
    label: head.label,
    red: false,
    left: none,
    right: none,
  )
  for x in xs.slice(1) {
    let p = parse(x)
    tree = (tree.insert)(p.value, label: p.label)
  }
  tree
}
