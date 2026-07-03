#import "@preview/typsy:0.2.2": Any, Int, None, Union, class
#import "./tree-anim.typ" as tree-anim

// ===================================================================
// AVL tree — core data structure + display
// ===================================================================
//
// A BST variant with a per-node `height` field, kept up-to-date by
// every operation. Heights are 1-indexed (leaves have height 1, nil
// children count as height 0). After any insertion or deletion the
// AVL invariant is restored by single or double rotations:
//
//   bf(n) = h(n.left) - h(n.right)        // balance factor
//   |bf(n)| ≤ 1 for every node n          // AVL invariant
//
// Fix-up cases at an imbalanced node n (|bf(n)| == 2):
//
//   LL: bf(n) == +2, bf(n.left)  >= 0     → single right rotation at n
//   LR: bf(n) == +2, bf(n.left)  <  0     → left rotation at n.left, then
//                                            right rotation at n
//   RR: bf(n) == -2, bf(n.right) <= 0     → single left rotation at n
//   RL: bf(n) == -2, bf(n.right) >  0     → right rotation at n.right, then
//                                            left rotation at n
//
// (For insert, the child's balance factor at the imbalance point is
// strictly nonzero on whichever side caused the imbalance; the >=/<=
// branches above are exercised by delete, where the child can be
// balanced.)
//
// `rotate` is a *structural* primitive that preserves the rotated
// nodes' heights (recomputed from their new children). Insert/delete
// fix-ups don't go through `rotate` — they apply the case rules
// directly, recompute heights, and continue.

// --- node-construction helper --------------------------------------
//
// Every internal helper takes `cls` as its first argument so it can
// call `cls.new` without referring to `AVL` (which isn't defined yet
// at the point these helpers are declared).

#let _node(cls, h, l, v, lab, r) = (cls.new)(
  value: v,
  label: lab,
  height: h,
  left: l,
  right: r,
)

#let _height(n) = if n == none { 0 } else { n.height }
#let _bf(n) = if n == none { 0 } else { _height(n.left) - _height(n.right) }
#let _new-height(l, r) = 1 + calc.max(_height(l), _height(r))

// Build a copy of `n` with a freshly recomputed height. Used after any
// child swap to keep `n.height` in sync with its subtree.
#let _refresh(cls, n) = _node(
  cls,
  _new-height(n.left, n.right),
  n.left,
  n.value,
  n.label,
  n.right,
)

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
// it. Spine nodes are *not* refreshed — callers that need spine heights
// updated must do so explicitly (see `_recompute-height-at`).
#let _replace-at(cls, node, path, new) = if path == "" {
  new
} else if path.first() == "L" {
  _node(
    cls,
    node.height,
    _replace-at(cls, node.left, path.slice(1), new),
    node.value,
    node.label,
    node.right,
  )
} else {
  _node(
    cls,
    node.height,
    node.left,
    node.value,
    node.label,
    _replace-at(cls, node.right, path.slice(1), new),
  )
}

// Refresh the height of the node at `path` from its current children.
#let _recompute-height-at(cls, tree, path) = {
  let n = _resolve-at(tree, path)
  _replace-at(cls, tree, path, _refresh(cls, n))
}

// Copy `value` and `label` into the node at `path`, preserving the
// node's height and children. Used by delete to splice a predecessor's
// value into the target's position.
#let _set-value-at(cls, tree, path, value, label) = {
  let n = _resolve-at(tree, path)
  let new = _node(cls, n.height, n.left, value, label, n.right)
  _replace-at(cls, tree, path, new)
}

// Single rotations. Both refresh the rotated nodes' heights.
#let _rotate-right(cls, n) = {
  let l = n.left
  let new-n = _refresh(
    cls,
    _node(cls, 0, l.right, n.value, n.label, n.right),
  )
  _refresh(cls, _node(cls, 0, l.left, l.value, l.label, new-n))
}
#let _rotate-left(cls, n) = {
  let r = n.right
  let new-n = _refresh(
    cls,
    _node(cls, 0, n.left, n.value, n.label, r.left),
  )
  _refresh(cls, _node(cls, 0, new-n, r.value, r.label, r.right))
}

#let _rotate-right-at(cls, tree, path) = {
  let n = _resolve-at(tree, path)
  _replace-at(cls, tree, path, _rotate-right(cls, n))
}
#let _rotate-left-at(cls, tree, path) = {
  let n = _resolve-at(tree, path)
  _replace-at(cls, tree, path, _rotate-left(cls, n))
}

// Classify the imbalance case at a node. Returns "LL", "LR", "RR",
// "RL", or none.
#let _imbalance-case(n) = {
  let bf = _bf(n)
  if bf == 2 {
    if _bf(n.left) >= 0 { "LL" } else { "LR" }
  } else if bf == -2 {
    if _bf(n.right) <= 0 { "RR" } else { "RL" }
  } else { none }
}

// Apply the fix-up rules at a node (no trace emission). Returns the
// rebalanced subtree, height refreshed. The node is assumed to have
// already had its height recomputed.
#let _fix-at(cls, n) = {
  let case = _imbalance-case(n)
  if case == none {
    n
  } else if case == "LL" {
    _rotate-right(cls, n)
  } else if case == "RR" {
    _rotate-left(cls, n)
  } else if case == "LR" {
    let new-left = _rotate-left(cls, n.left)
    _rotate-right(cls, _node(cls, n.height, new-left, n.value, n.label, n.right))
  } else {
    let new-right = _rotate-right(cls, n.right)
    _rotate-left(cls, _node(cls, n.height, n.left, n.value, n.label, new-right))
  }
}

// Recursive AVL insert. Returns a rebalanced tree with all heights
// up-to-date. Used by `insert` (and by the trace generator to compare
// against, but the trace builds events directly).
#let _avl-insert(cls, node, v, label) = if node == none {
  _node(cls, 1, none, v, label, none)
} else {
  let new-node = if v <= node.value {
    let new-left = _avl-insert(cls, node.left, v, label)
    _node(cls, 0, new-left, node.value, node.label, node.right)
  } else {
    let new-right = _avl-insert(cls, node.right, v, label)
    _node(cls, 0, node.left, node.value, node.label, new-right)
  }
  _fix-at(cls, _refresh(cls, new-node))
}

// Peel off the rightmost node of a subtree (its in-order predecessor
// from the parent's perspective), rebalancing on the way up. Returns
// the new subtree with the rightmost gone.
#let _avl-delete-max(cls, n) = if n.right == none {
  n.left
} else {
  let new-right = _avl-delete-max(cls, n.right)
  _fix-at(
    cls,
    _refresh(cls, _node(cls, 0, n.left, n.value, n.label, new-right)),
  )
}

// Recursive AVL delete. Returns the rebalanced tree.
#let _avl-delete(cls, node, v) = {
  let recur(n) = if n == none {
    none
  } else if v < n.value {
    let new-left = recur(n.left)
    _fix-at(
      cls,
      _refresh(cls, _node(cls, 0, new-left, n.value, n.label, n.right)),
    )
  } else if v > n.value {
    let new-right = recur(n.right)
    _fix-at(
      cls,
      _refresh(cls, _node(cls, 0, n.left, n.value, n.label, new-right)),
    )
  } else if n.left == none {
    n.right
  } else if n.right == none {
    n.left
  } else {
    let find-max(m) = if m.right == none { m } else { find-max(m.right) }
    let pred = find-max(n.left)
    let new-left = _avl-delete-max(cls, n.left)
    _fix-at(
      cls,
      _refresh(
        cls,
        _node(cls, 0, new-left, pred.value, pred.label, n.right),
      ),
    )
  }
  recur(node)
}

// ===================================================================
// Insert trace
// ===================================================================
//
// Returns `(events, tree)` — `tree` is the fully-balanced post-insert
// tree, `events` is an ordered list of the steps the animation should
// show. The trace climbs through every BST ancestor on the way up,
// emitting one `recompute` frame per ancestor (so students see the
// height update propagating). On the first ancestor with |bf| == 2,
// it emits `check`, one `rotate-zigzag` (LR/RL only), and a
// `rotate-finish`, then stops — a single rotation restores the
// subtree's pre-insertion height, so further ancestors don't change.
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
//   (kind: "recompute",     path, height, tree)
//                          — one per ancestor on the climb (deepest
//                            first); `height` is the node's new
//                            height (which may equal the old one)
//   (kind: "check",         path, case, bf, tree)
//                          — imbalance found at `path`; `case` is one
//                            of "LL", "LR", "RR", "RL"
//   (kind: "rotate-zigzag", path, case, tree)
//                          — emitted only for LR/RL; the child of the
//                            imbalanced node has been rotated to
//                            straighten the configuration
//   (kind: "rotate-finish", path, case, tree)
//                          — final rotation at the imbalanced node
#let _avl-insert-trace(cls, tree, v, label) = {
  let events = ()

  // BST descent — record visited paths and where the new leaf lands.
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

  // Splice the new leaf at insert-path. Heights on the spine above are
  // stale until we recompute on the climb.
  let insert-at(node, path) = if path == "" {
    _node(cls, 1, none, v, label, none)
  } else if path.first() == "L" {
    _node(
      cls,
      node.height,
      insert-at(node.left, path.slice(1)),
      node.value,
      node.label,
      node.right,
    )
  } else {
    _node(
      cls,
      node.height,
      node.left,
      node.value,
      node.label,
      insert-at(node.right, path.slice(1)),
    )
  }
  let cur-tree = insert-at(tree, insert-path)
  events.push((kind: "insert", path: insert-path, tree: cur-tree))

  // Climb: walk visited ancestors deepest-first, recompute heights,
  // dispatch on imbalance.
  let i = visited.len() - 1
  let done = false
  while i >= 0 and not done {
    let anc-path = visited.at(i)
    cur-tree = _recompute-height-at(cls, cur-tree, anc-path)
    let anc = _resolve-at(cur-tree, anc-path)
    events.push((
      kind: "recompute",
      path: anc-path,
      height: anc.height,
      tree: cur-tree,
    ))
    let case = _imbalance-case(anc)
    if case != none {
      events.push((
        kind: "check",
        path: anc-path,
        case: case,
        bf: _bf(anc),
        tree: cur-tree,
      ))
      if case == "LR" {
        let child-path = anc-path + "L"
        cur-tree = _rotate-left-at(cls, cur-tree, child-path)
        events.push((
          kind: "rotate-zigzag",
          path: child-path,
          case: case,
          tree: cur-tree,
        ))
      } else if case == "RL" {
        let child-path = anc-path + "R"
        cur-tree = _rotate-right-at(cls, cur-tree, child-path)
        events.push((
          kind: "rotate-zigzag",
          path: child-path,
          case: case,
          tree: cur-tree,
        ))
      }
      if case == "LL" or case == "LR" {
        cur-tree = _rotate-right-at(cls, cur-tree, anc-path)
      } else {
        cur-tree = _rotate-left-at(cls, cur-tree, anc-path)
      }
      events.push((
        kind: "rotate-finish",
        path: anc-path,
        case: case,
        tree: cur-tree,
      ))
      // A single insertion fix-up restores the subtree's pre-insert
      // height; no further ancestors can become imbalanced.
      done = true
    }
    i = i - 1
  }

  (events: events, tree: cur-tree)
}

// ===================================================================
// Delete trace
// ===================================================================
//
// Event kinds (a superset of insert's, plus the BST-delete shape from
// rbt.typ):
//   (kind: "init",     tree)
//   (kind: "compare",  path, cmp, found, tree)
//                      — emitted only when with-search=true
//   (kind: "descend",  visited, tree)
//                      — emitted only when with-search=false
//   (kind: "not-found", visited, tree)
//   (kind: "mark-target", target-path, tree)
//   (kind: "find-predecessor", walk, predecessor-path, target-path, tree)
//   (kind: "transfer", target-path, predecessor-path, new-value, tree)
//   (kind: "excise",   path, tree)
//   (kind: "recompute", path, height, tree)
//   (kind: "check",    path, case, bf, tree)
//   (kind: "rotate-zigzag", path, case, tree)
//   (kind: "rotate-finish", path, case, tree)
//
// Unlike insert, delete may produce multiple fix-ups on the climb —
// each ancestor whose subtree shrank can become imbalanced, and the
// loop continues until the root is reached.
#let _avl-delete-trace(cls, tree, v, with-search) = {
  let events = ()

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
    let pred-walk(p) = {
      let n = _resolve-at(cur-tree, p)
      if n.right == none { (p,) } else { (p,) + pred-walk(p + "R") }
    }
    let walk-paths = pred-walk(target-path + "L")
    let pred-path = walk-paths.last()
    let pred-node = _resolve-at(cur-tree, pred-path)

    events.push((
      kind: "find-predecessor",
      walk: walk-paths,
      predecessor-path: pred-path,
      target-path: target-path,
      tree: cur-tree,
    ))

    cur-tree = _set-value-at(
      cls,
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
      new-label: tree-anim._alt-label(pred-node),
      tree: cur-tree,
    ))
    excise-path = pred-path
  }

  let excise-node = _resolve-at(cur-tree, excise-path)
  let replacement = if excise-node.left != none {
    excise-node.left
  } else { excise-node.right }

  // Edge case: excising the root of a single-node tree leaves the tree
  // empty.
  if excise-path == "" and replacement == none {
    events.push((kind: "excise", path: excise-path, tree: none))
    return (events: events, tree: none)
  }

  cur-tree = _replace-at(cls, cur-tree, excise-path, replacement)
  events.push((kind: "excise", path: excise-path, tree: cur-tree))

  // Climb every proper prefix of excise-path (deepest first), recompute
  // heights, dispatch on any imbalance found. Unlike insert, multiple
  // fix-ups on the way up are possible.
  let ancestors = ()
  let cur = excise-path
  while cur != "" {
    cur = cur.slice(0, cur.len() - 1)
    ancestors.push(cur)
  }
  // ancestors is now deepest-first by construction.

  for anc-path in ancestors {
    cur-tree = _recompute-height-at(cls, cur-tree, anc-path)
    let anc = _resolve-at(cur-tree, anc-path)
    events.push((
      kind: "recompute",
      path: anc-path,
      height: anc.height,
      tree: cur-tree,
    ))
    let case = _imbalance-case(anc)
    if case != none {
      events.push((
        kind: "check",
        path: anc-path,
        case: case,
        bf: _bf(anc),
        tree: cur-tree,
      ))
      if case == "LR" {
        let child-path = anc-path + "L"
        cur-tree = _rotate-left-at(cls, cur-tree, child-path)
        events.push((
          kind: "rotate-zigzag",
          path: child-path,
          case: case,
          tree: cur-tree,
        ))
      } else if case == "RL" {
        let child-path = anc-path + "R"
        cur-tree = _rotate-right-at(cls, cur-tree, child-path)
        events.push((
          kind: "rotate-zigzag",
          path: child-path,
          case: case,
          tree: cur-tree,
        ))
      }
      if case == "LL" or case == "LR" {
        cur-tree = _rotate-right-at(cls, cur-tree, anc-path)
      } else {
        cur-tree = _rotate-left-at(cls, cur-tree, anc-path)
      }
      events.push((
        kind: "rotate-finish",
        path: anc-path,
        case: case,
        tree: cur-tree,
      ))
    }
  }

  (events: events, tree: cur-tree)
}

// Run the AVL fix-up loop starting from `start-path`. Used by
// `fixup-display` so hand-crafted imbalanced configurations can be
// animated without going through insert/delete. The tree is NOT
// validated; callers may pass a tree with an imbalance that couldn't
// arise from a real insert (e.g. multiple imbalances on one spine, or
// a configuration deeper than insert can produce).
//
// Walks all proper prefixes of `start-path` deepest-first, emitting
// the same recompute / check / rotate-zigzag / rotate-finish events
// `_avl-delete-trace` does on its climb.
#let _avl-fixup-trace(cls, tree, start-path) = {
  let events = ()
  let cur-tree = tree

  let ancestors = ()
  let cur = start-path
  while cur != "" {
    cur = cur.slice(0, cur.len() - 1)
    ancestors.push(cur)
  }

  for anc-path in ancestors {
    cur-tree = _recompute-height-at(cls, cur-tree, anc-path)
    let anc = _resolve-at(cur-tree, anc-path)
    events.push((
      kind: "recompute",
      path: anc-path,
      height: anc.height,
      tree: cur-tree,
    ))
    let case = _imbalance-case(anc)
    if case != none {
      events.push((
        kind: "check",
        path: anc-path,
        case: case,
        bf: _bf(anc),
        tree: cur-tree,
      ))
      if case == "LR" {
        let child-path = anc-path + "L"
        cur-tree = _rotate-left-at(cls, cur-tree, child-path)
        events.push((
          kind: "rotate-zigzag",
          path: child-path,
          case: case,
          tree: cur-tree,
        ))
      } else if case == "RL" {
        let child-path = anc-path + "R"
        cur-tree = _rotate-right-at(cls, cur-tree, child-path)
        events.push((
          kind: "rotate-zigzag",
          path: child-path,
          case: case,
          tree: cur-tree,
        ))
      }
      if case == "LL" or case == "LR" {
        cur-tree = _rotate-right-at(cls, cur-tree, anc-path)
      } else {
        cur-tree = _rotate-left-at(cls, cur-tree, anc-path)
      }
      events.push((
        kind: "rotate-finish",
        path: anc-path,
        case: case,
        tree: cur-tree,
      ))
    }
  }

  (events: events, tree: cur-tree)
}

// ===================================================================
// Frame construction for AVL displays
// ===================================================================
//
// Mirrors bst.typ's `_make-frames`. AVL has no per-DS theme, so the
// builder forwards op-theme and render-theme through to the snapshot
// closure (matching BST's pattern, not RBT's).

#let _resolve-render-theme-arg(theme) = if theme == auto {
  auto
} else { tree-anim._merge-render-theme(theme) }

#let _make-frames-avl(
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
    _builder: (
      fn: (op-arg, rt-arg) => {
        let op = if theme == auto { op-arg } else { theme }
        let rt = if render-theme == auto { rt-arg } else { render-theme }
        let snaps = build-snapshots(op, rt)
        tree-anim._render-canvas(tree, snaps.at(i), (:), (:), rt)
      },
    ),
    caption: captions.at(i),
    step: steps-meta.at(i),
    alt: alts.at(i),
  ))
}

// Per-frame variant: each `specs` entry carries its own tree and
// `build(op, rt) -> Snapshot` closure. Used by insert-display /
// delete-display / fixup-display whose frames cross multiple tree
// states.
#let _make-frames-avl-multi(specs, theme, render-theme) = {
  specs.map(s => (tree-anim.Frame.new)(
    _builder: (
      fn: (op-arg, rt-arg) => {
        let op = if theme == auto { op-arg } else { theme }
        let rt = if render-theme == auto { rt-arg } else { render-theme }
        let snap = (s.build)(op, rt)
        tree-anim._render-canvas(s.tree, snap, (:), (:), rt)
      },
    ),
    caption: s.caption,
    step: s.step,
    alt: s.alt,
  ))
}

// Tag every node with its balance factor (signed, e.g. "+1", "0", "-1").
// Used by `display(factors: true)` and as a base layer for all *-display
// methods that want factors visible on the animation.
#let _tag-factors(r, tree) = {
  let walk(node, path) = if node == none { () } else {
    (path,) + walk(node.left, path + "L") + walk(node.right, path + "R")
  }
  let paths = walk(tree, "")
  let result = r
  for p in paths {
    let n = _resolve-at(tree, p)
    let bf = _bf(n)
    let tag = if bf > 0 { "+" + str(bf) } else { str(bf) }
    result = (result.patch)(f => (f.style-node)(p, tag: tag))
  }
  result
}

// Tag every edge with the height of its child subtree. Root is skipped
// (no incoming edge); an edge into the root would just label the height
// of the whole tree, easily read off the children's labels. Used by
// `display(heights: true)` and as a base layer for all *-display methods
// that want height labels visible on the animation.
#let _tag-heights(r, tree) = {
  let walk(node, path) = if node == none { () } else {
    let here = if path == "" { () } else { (path,) }
    here + walk(node.left, path + "L") + walk(node.right, path + "R")
  }
  let paths = walk(tree, "")
  let result = r
  for p in paths {
    let n = _resolve-at(tree, p)
    result = (result.patch)(f => (f.style-edge)(p, tag: str(n.height)))
  }
  result
}

// ===================================================================
// Op-theme resolution (matches BST's _resolve-op-theme-arg, inlined
// here so we don't have to thread an extra import).
// ===================================================================

#import "./op-theme.typ": _resolve-op-theme-arg

// ===================================================================
// Insert event → frame spec
// ===================================================================
//
// One spec per event. `factors` controls whether the balance-factor
// tag layer is applied to every snapshot. `init-alt` is the alt text
// for the "init" frame (varies per call site — insert-display vs
// fixup-display). `prev-tree` is the previous event's tree (or `none`
// for the first event): for `recompute` events we compute balance
// factors from `prev-tree` so the just-recomputed node's parent
// doesn't visually update its bf until the parent itself is the
// recompute target. Heights tags still use the current tree so the
// height label updates with the caption.
#let _insert-event-to-spec(event, v, factors, heights, init-alt, prev-tree) = {
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
      "Walked the BST search path for " + str(v) + "; insertion point is one step beyond the last visited node."
    )
  } else if event.kind == "insert" {
    caption = [Insert #v as new leaf]
    step = (kind: "insert", path: event.path)
    alt = "Inserted " + str(v) + " as a new leaf with height 1."
  } else if event.kind == "recompute" {
    caption = [Recompute height]
    step = (kind: "recompute", path: event.path, height: event.height)
    let nv = tree-anim._alt-label(_resolve-at(event.tree, event.path))
    alt = (
      "Recomputed height at node " + nv + ": new height is " + str(event.height) + "."
    )
  } else if event.kind == "check" {
    caption = [Imbalance: case #(event.case)]
    step = (kind: "check", path: event.path, case: event.case, bf: event.bf)
    let nv = tree-anim._alt-label(_resolve-at(event.tree, event.path))
    alt = (
      "Balance factor at node " + nv + " is " + str(event.bf) + "; case " + event.case + " applies."
    )
  } else if event.kind == "rotate-zigzag" {
    caption = [Rotate child]
    step = (kind: "rotate-zigzag", path: event.path, case: event.case)
    alt = (
      "Case " + event.case + " (zigzag): rotated the imbalanced node's child to straighten the configuration."
    )
  } else if event.kind == "rotate-finish" {
    caption = [Rotate (case #(event.case))]
    step = (kind: "rotate-finish", path: event.path, case: event.case)
    alt = (
      "Case " + event.case + ": rotated the imbalanced node; AVL invariant restored at this subtree."
    )
  }

  let bf-tree = if event.kind == "recompute" and prev-tree != none {
    prev-tree
  } else { event.tree }
  let build = (op, _rt) => {
    let r = tree-anim.make-renderer(event.tree)
    if factors { r = _tag-factors(r, bf-tree) }
    if heights { r = _tag-heights(r, event.tree) }
    if event.kind == "descend" {
      for p in event.visited {
        r = (r.patch)(f => (f.style-node)(p, stroke: op.search-stroke))
      }
    } else if event.kind == "insert" {
      r = (r.patch)(f => (f.style-node)(
        event.path,
        stroke: op.settled-stroke,
        fill: op.success-fill,
      ))
      r = (r.patch)(f => (f.style-edge)(
        event.path,
        stroke: op.success-stroke,
      ))
    } else if event.kind == "recompute" {
      r = (r.patch)(f => (f.style-node)(
        event.path,
        stroke: op.search-stroke,
      ))
    } else if event.kind == "check" {
      r = (r.patch)(f => (f.style-node)(
        event.path,
        stroke: op.attention-stroke,
      ))
      r = (r.patch)(f => (f.note-node)(event.path, event.case))
    } else if event.kind == "rotate-zigzag" {
      r = (r.patch)(f => (f.style-node)(
        event.path,
        stroke: op.attention-stroke,
      ))
    } else if event.kind == "rotate-finish" {
      r = (r.patch)(f => (f.style-node)(
        event.path,
        stroke: op.settled-stroke,
      ))
      r = (r.patch)(f => (f.style-edge)(
        event.path,
        stroke: op.success-stroke,
      ))
    }
    r.snapshots.first()
  }

  (tree: event.tree, build: build, caption: caption, step: step, alt: alt)
}

// ===================================================================
// Delete event → frame spec
// ===================================================================
//
// Most events overlap with insert; the search/excise/transfer events
// are unique to delete. `visited-snapshot` is the accumulated search
// trail for compare frames so each one shows the whole walk.
#let _delete-event-to-spec(event, v, factors, heights, init-alt, visited-snapshot, prev-tree) = {
  let caption = none
  let step = (kind: event.kind)
  let alt = ""

  if event.kind == "init" {
    step = (kind: "init")
    alt = init-alt
  } else if event.kind == "compare" {
    let node = _resolve-at(event.tree, event.path)
    let cmp-text = str(v) + " " + event.cmp + " " + str(node.value)
    let nlabel = tree-anim._alt-label(node)
    caption = cmp-text
    step = (
      kind: "compare",
      path: event.path,
      cmp: event.cmp,
      found: event.found,
    )
    alt = if event.found {
      "Match found at node " + nlabel + "; ready to delete."
    } else {
      "Comparing " + cmp-text + " at node " + nlabel + "; descending."
    }
  } else if event.kind == "descend" {
    caption = [Search for #v]
    step = (kind: "descend", visited: event.visited)
    alt = (
      "Walked the BST search path for " + str(v) + "; ready to delete."
    )
  } else if event.kind == "not-found" {
    caption = [#v not in tree]
    step = (kind: "not-found")
    alt = str(v) + " is not in the tree; nothing to delete."
  } else if event.kind == "mark-target" {
    let tlabel = tree-anim._alt-label(_resolve-at(event.tree, event.target-path))
    caption = [Delete #v]
    step = (kind: "mark-target", path: event.target-path)
    alt = "Marked node " + tlabel + " for deletion."
  } else if event.kind == "find-predecessor" {
    let tlabel = tree-anim._alt-label(_resolve-at(event.tree, event.target-path))
    let pv = tree-anim._alt-label(_resolve-at(event.tree, event.predecessor-path))
    caption = [Find predecessor]
    step = (
      kind: "find-predecessor",
      walk: event.walk,
      predecessor-path: event.predecessor-path,
      target-path: event.target-path,
    )
    alt = (
      "Node "
        + tlabel
        + " has two children; walking the left subtree to find the in-order predecessor: "
        + pv
        + "."
    )
  } else if event.kind == "transfer" {
    caption = [Transfer #(event.new-value)]
    step = (
      kind: "transfer",
      target-path: event.target-path,
      predecessor-path: event.predecessor-path,
    )
    alt = (
      "Copied predecessor's value "
        + event.new-label
        + " into the target slot; about to remove the predecessor node."
    )
  } else if event.kind == "excise" {
    caption = [Remove node]
    step = (kind: "excise", path: event.path)
    alt = "Removed the deletion-position node from the tree."
  } else if event.kind == "recompute" {
    caption = [Recompute height]
    step = (kind: "recompute", path: event.path, height: event.height)
    let nv = tree-anim._alt-label(_resolve-at(event.tree, event.path))
    alt = (
      "Recomputed height at node " + nv + ": new height is " + str(event.height) + "."
    )
  } else if event.kind == "check" {
    caption = [Imbalance: case #(event.case)]
    step = (kind: "check", path: event.path, case: event.case, bf: event.bf)
    let nv = tree-anim._alt-label(_resolve-at(event.tree, event.path))
    alt = (
      "Balance factor at node " + nv + " is " + str(event.bf) + "; case " + event.case + " applies."
    )
  } else if event.kind == "rotate-zigzag" {
    caption = [Rotate child]
    step = (kind: "rotate-zigzag", path: event.path, case: event.case)
    alt = (
      "Case " + event.case + " (zigzag): rotated the imbalanced node's child to straighten the configuration."
    )
  } else if event.kind == "rotate-finish" {
    caption = [Rotate (case #(event.case))]
    step = (kind: "rotate-finish", path: event.path, case: event.case)
    alt = (
      "Case " + event.case + ": rotated the imbalanced node; AVL invariant restored at this subtree."
    )
  }

  let bf-tree = if event.kind == "recompute" and prev-tree != none {
    prev-tree
  } else { event.tree }
  let build = (op, _rt) => {
    let r = tree-anim.make-renderer(event.tree)
    if factors { r = _tag-factors(r, bf-tree) }
    if heights { r = _tag-heights(r, event.tree) }
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
      r = (r.patch)(f => (f.style-node)(
        event.target-path,
        stroke: op.attention-stroke,
      ))
      r = (r.patch)(f => (f.note-node)(event.target-path, [delete]))
    } else if event.kind == "find-predecessor" {
      r = (r.patch)(f => (f.style-node)(
        event.target-path,
        stroke: op.attention-stroke,
      ))
      for p in event.walk {
        r = (r.patch)(f => (f.style-node)(p, stroke: op.search-stroke))
      }
      r = (r.patch)(f => (f.note-node)(event.predecessor-path, [pred]))
    } else if event.kind == "transfer" {
      r = (r.patch)(f => (f.style-node)(
        event.target-path,
        stroke: op.settled-stroke,
      ))
      r = (r.patch)(f => (f.note-node)(
        event.target-path,
        [← #(event.new-value)],
      ))
      r = (r.patch)(f => (f.style-node)(
        event.predecessor-path,
        stroke: op.attention-stroke,
      ))
    } else if event.kind == "recompute" {
      r = (r.patch)(f => (f.style-node)(
        event.path,
        stroke: op.search-stroke,
      ))
    } else if event.kind == "check" {
      r = (r.patch)(f => (f.style-node)(
        event.path,
        stroke: op.attention-stroke,
      ))
      r = (r.patch)(f => (f.note-node)(event.path, event.case))
    } else if event.kind == "rotate-zigzag" {
      r = (r.patch)(f => (f.style-node)(
        event.path,
        stroke: op.attention-stroke,
      ))
    } else if event.kind == "rotate-finish" {
      r = (r.patch)(f => (f.style-node)(
        event.path,
        stroke: op.settled-stroke,
      ))
      r = (r.patch)(f => (f.style-edge)(
        event.path,
        stroke: op.success-stroke,
      ))
    }
    r.snapshots.first()
  }

  (tree: event.tree, build: build, caption: caption, step: step, alt: alt)
}

// Concise per-visit animation shared by the four `*-order-display`
// methods. Mirrors bst.typ's `_render-traversal`.
#let _text-fill-for(bg) = {
  let l = bg.oklab().components().first()
  if l < 60% { white } else { black }
}

#let _render-traversal(self, paths, name, factors, heights, theme, render-theme) = {
  let n = paths.len()

  let captions = (none,)
  let steps-meta = ((kind: "init"),)
  let alts = (
    "AVL tree: " + (self.describe)() + ". About to traverse " + name + ".",
  )

  let output = ()
  for (i, p) in paths.enumerate() {
    let node = (self.resolve)(p)
    let disp = tree-anim._alt-label(node)
    output.push(disp)
    captions.push([Output: #raw("[" + output.join(", ") + "]")])
    steps-meta.push((
      kind: "visit",
      path: p,
      index: i + 1,
      value: node.value,
    ))
    alts.push(
      "Visited "
        + disp
        + " (visit "
        + str(i + 1)
        + " of "
        + str(n)
        + "); output so far: "
        + output.join(", ")
        + ".",
    )
  }

  let build-snapshots = (op, _rt) => {
    let g = gradient.linear(..op.traversal-palette)
    let r = tree-anim.make-renderer(self, sticky: true)
    if factors { r = _tag-factors(r, self) }
    if heights { r = _tag-heights(r, self) }
    for (i, p) in paths.enumerate() {
      let t = if n <= 1 { 0% } else { (i / (n - 1)) * 100% }
      let fill = g.sample(t)
      let txt-fill = _text-fill-for(fill)
      r = (r.push-with-node)(
        p,
        fill: fill,
        text-fill: txt-fill,
        note: str(i + 1),
      )
    }
    r.snapshots
  }

  _make-frames-avl(
    self,
    build-snapshots,
    captions,
    steps-meta,
    alts,
    theme,
    render-theme,
  )
}

// ===================================================================
// The AVL class
// ===================================================================
//
// `value` orders the BST. `label` is the rendered content (defaults to
// `auto` ⇒ `str(value)`, matching BST/RBT). `height` is the node's
// height (leaves = 1; nil children = 0). `left` and `right` are child
// subtrees, with `none` standing in for nil.
//
// `*-display` methods accept optional `theme:` and `render-theme:`
// arguments. `auto` (the default) reads the active theme from state at
// layout time. `factors:` toggles the per-node balance-factor tag.
// `heights:` toggles the per-edge subtree-height tag (rendered in the
// render theme's `edge-tag-fill` color); skips the root, since its
// incoming edge doesn't exist.
#let AVL = class(
  name: "AVL",
  fields: (
    value: Int,
    label: Any,
    height: Int,
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
      let head = tree-anim._alt-label(self) + ":" + str(self.height)
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
    in-order: self => {
      let walk(node, path) = if node == none { () } else {
        walk(node.left, path + "L") + (path,) + walk(node.right, path + "R")
      }
      walk(self, "")
    },
    pre-order: self => {
      let walk(node, path) = if node == none { () } else {
        (path,) + walk(node.left, path + "L") + walk(node.right, path + "R")
      }
      walk(self, "")
    },
    post-order: self => {
      let walk(node, path) = if node == none { () } else {
        walk(node.left, path + "L") + walk(node.right, path + "R") + (path,)
      }
      walk(self, "")
    },
    level-order: self => {
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
      _avl-insert(cls, self, v, label)
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
      _avl-delete(cls, self, v)
    },
    rotate: (self, child) => {
      // Structural rotation — preserves the BST shape and rotates
      // `child` up. Heights of the two rotated nodes are refreshed.
      // AVL rebalancing in insert/delete does not go through here.
      let cls = self.meta.cls
      let child-path = (self.by-value)(child.value)
      if child-path == "" {
        panic("rotate: cannot rotate the root with itself")
      }
      let parent-path = child-path.slice(0, child-path.len() - 1)
      let is-right = child-path.last() == "L"
      let rotated = if is-right {
        _rotate-right(cls, (self.resolve)(parent-path))
      } else {
        _rotate-left(cls, (self.resolve)(parent-path))
      }
      // Splice back and refresh spine heights above the rotation.
      let result = _replace-at(cls, self, parent-path, rotated)
      let refresh-spine(t, p) = if p == "" {
        _refresh(cls, t)
      } else if p.first() == "L" {
        let new-left = refresh-spine(t.left, p.slice(1))
        _refresh(cls, _node(cls, t.height, new-left, t.value, t.label, t.right))
      } else {
        let new-right = refresh-spine(t.right, p.slice(1))
        _refresh(cls, _node(cls, t.height, t.left, t.value, t.label, new-right))
      }
      refresh-spine(result, parent-path)
    },
    // Test helper. Verifies BST order, that every node's `height`
    // field matches the recomputed value, and that |bf(n)| <= 1 for
    // every node. Panics on the first violation; returns true if
    // everything checks out.
    check-invariants: self => {
      let walk(node) = if node == none {
        0
      } else {
        if node.left != none and node.left.value > node.value {
          panic(
            "BST invariant violated at " + str(node.value) + ": left child " + str(node.left.value) + " > node",
          )
        }
        if node.right != none and node.right.value < node.value {
          panic(
            "BST invariant violated at " + str(node.value) + ": right child " + str(node.right.value) + " < node",
          )
        }
        let lh = walk(node.left)
        let rh = walk(node.right)
        let expected = 1 + calc.max(lh, rh)
        if node.height != expected {
          panic(
            "AVL invariant: stored height "
              + str(node.height)
              + " at node "
              + str(node.value)
              + " disagrees with recomputed "
              + str(expected),
          )
        }
        let bf = lh - rh
        if bf < -1 or bf > 1 {
          panic(
            "AVL invariant: balance factor " + str(bf) + " at node " + str(node.value) + " (|bf| > 1)",
          )
        }
        expected
      }
      let _ = walk(self)
      true
    },
    display: (
      self,
      factors: false,
      heights: false,
      theme: auto,
      render-theme: auto,
    ) => {
      // Returns a one-element Frame array — the static tree. With
      // `factors: true`, each node is tagged with its signed balance
      // factor (e.g. "+1", "0", "-1") drawn just west of the node.
      // With `heights: true`, each edge is labeled with the height of
      // the subtree it points to (the root is skipped — no incoming
      // edge — but its children's heights make its balance factor
      // computable).
      let captions = (none,)
      let steps-meta = (none,)
      let alts = ("AVL tree: " + (self.describe)() + ".",)
      let build-snapshots = (_op, _rt) => {
        let r = tree-anim.make-renderer(self)
        if factors { r = _tag-factors(r, self) }
        if heights { r = _tag-heights(r, self) }
        r.snapshots
      }
      _make-frames-avl(
        self,
        build-snapshots,
        captions,
        steps-meta,
        alts,
        _resolve-op-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
      )
    },
    search-display: (
      self,
      v,
      factors: false,
      heights: false,
      theme: auto,
      render-theme: auto,
    ) => {
      // One frame per comparison along the search path. Mirrors BST's
      // search-display, with the optional balance-factor tag layer.
      let walk(node, path) = {
        let cmp = if v == node.value {
          str(v) + " = " + str(node.value)
        } else if v < node.value {
          str(v) + " < " + str(node.value)
        } else {
          str(v) + " > " + str(node.value)
        }
        let step = (path: path, cmp: cmp, found: v == node.value)
        if v == node.value or (node.left == none and node.right == none) {
          (step,)
        } else if v < node.value and node.left != none {
          (step,) + walk(node.left, path + "L")
        } else if v > node.value and node.right != none {
          (step,) + walk(node.right, path + "R")
        } else { (step,) }
      }
      let steps = walk(self, "")

      let captions = (none,)
      let steps-meta = ((kind: "init"),)
      let alts = (
        "AVL tree: " + (self.describe)() + ". About to search for " + str(v) + ".",
      )
      for (i, s) in steps.enumerate() {
        captions.push(s.cmp)
        steps-meta.push((
          kind: "compare",
          path: s.path,
          cmp: s.cmp,
          found: s.found,
        ))
        let node-value = tree-anim._alt-label((self.resolve)(s.path))
        let is-last = i == steps.len() - 1
        let alt = if s.found {
          "Match found at node " + node-value + "."
        } else if is-last {
          (
            "Comparing " + s.cmp + " at node " + node-value + "; search ends here, " + str(v) + " is not in the tree."
          )
        } else {
          (
            "Comparing " + s.cmp + " at node " + node-value + "; continuing search."
          )
        }
        alts.push(alt)
      }

      let build-snapshots = (op, _rt) => {
        let r = tree-anim.make-renderer(self, sticky: true)
        if factors { r = _tag-factors(r, self) }
        if heights { r = _tag-heights(r, self) }
        for s in steps {
          r = (r.push-with-node)(s.path, stroke: op.search-stroke)
          r = (r.patch)(f => (f.note-node)(s.path, s.cmp))
        }
        r.snapshots
      }

      _make-frames-avl(
        self,
        build-snapshots,
        captions,
        steps-meta,
        alts,
        _resolve-op-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
      )
    },
    in-order-display: (
      self,
      factors: false,
      heights: false,
      theme: auto,
      render-theme: auto,
    ) => _render-traversal(
      self,
      (self.in-order)(),
      "in-order",
      factors,
      heights,
      _resolve-op-theme-arg(theme),
      _resolve-render-theme-arg(render-theme),
    ),
    pre-order-display: (
      self,
      factors: false,
      heights: false,
      theme: auto,
      render-theme: auto,
    ) => _render-traversal(
      self,
      (self.pre-order)(),
      "pre-order",
      factors,
      heights,
      _resolve-op-theme-arg(theme),
      _resolve-render-theme-arg(render-theme),
    ),
    post-order-display: (
      self,
      factors: false,
      heights: false,
      theme: auto,
      render-theme: auto,
    ) => _render-traversal(
      self,
      (self.post-order)(),
      "post-order",
      factors,
      heights,
      _resolve-op-theme-arg(theme),
      _resolve-render-theme-arg(render-theme),
    ),
    level-order-display: (
      self,
      factors: false,
      heights: false,
      theme: auto,
      render-theme: auto,
    ) => _render-traversal(
      self,
      (self.level-order)(),
      "level-order",
      factors,
      heights,
      _resolve-op-theme-arg(theme),
      _resolve-render-theme-arg(render-theme),
    ),
    insert-display: (
      self,
      v,
      factors: false,
      heights: false,
      theme: auto,
      render-theme: auto,
    ) => {
      let cls = self.meta.cls
      let trace = _avl-insert-trace(cls, self, v, auto)
      let events = trace.events

      let resolved-op = _resolve-op-theme-arg(theme)
      let resolved-render = _resolve-render-theme-arg(render-theme)

      let init-alt = (
        "AVL tree: " + (self.describe)() + ". About to insert " + str(v) + "."
      )

      let specs = ()
      let prev-tree = none
      for e in events {
        specs.push(_insert-event-to-spec(
          e,
          v,
          factors,
          heights,
          init-alt,
          prev-tree,
        ))
        prev-tree = e.tree
      }
      _make-frames-avl-multi(specs, resolved-op, resolved-render)
    },
    fixup-display: (
      self,
      violation-path,
      factors: false,
      heights: false,
      theme: auto,
      render-theme: auto,
    ) => {
      // Animate the AVL fix-up starting from a hand-constructed
      // imbalanced tree. The tree is NOT validated; intended for
      // teaching configurations that can't arise from a single
      // insert or delete (e.g. multiple imbalances on one spine,
      // or showing a specific case in isolation). `violation-path`
      // is the deepest path from which the climb begins — usually
      // the path of the freshly modified leaf.
      let cls = self.meta.cls
      let fix = _avl-fixup-trace(cls, self, violation-path)
      let events = ((kind: "init", tree: self),) + fix.events

      let resolved-op = _resolve-op-theme-arg(theme)
      let resolved-render = _resolve-render-theme-arg(render-theme)

      let init-alt = (
        "AVL tree: "
          + (self.describe)()
          + ". Imbalance below \""
          + violation-path
          + "\"; about to run the fix-up climb."
      )

      let specs = ()
      let prev-tree = none
      for e in events {
        specs.push(_insert-event-to-spec(
          e,
          none,
          factors,
          heights,
          init-alt,
          prev-tree,
        ))
        prev-tree = e.tree
      }
      _make-frames-avl-multi(specs, resolved-op, resolved-render)
    },
    delete-display: (
      self,
      v,
      search: false,
      factors: false,
      heights: false,
      theme: auto,
      render-theme: auto,
    ) => {
      let cls = self.meta.cls
      let trace = _avl-delete-trace(cls, self, v, search)
      let events = trace.events

      let resolved-op = _resolve-op-theme-arg(theme)
      let resolved-render = _resolve-render-theme-arg(render-theme)

      // Name the target by its label when present (it displays that way);
      // fall back to the queried key when it isn't in the tree.
      let del-label = if (self.contains)(v) {
        tree-anim._alt-label(_resolve-at(self, (self.by-value)(v)))
      } else { str(v) }
      let init-alt = (
        "AVL tree: " + (self.describe)() + ". About to delete " + del-label + "."
      )

      // For compare frames (with search: true), accumulate descended
      // paths so each frame shows the full search trail.
      let visited-by-event = ()
      let visited-acc = ()
      for e in events {
        if e.kind == "compare" {
          visited-acc = visited-acc + (e.path,)
        }
        visited-by-event.push(visited-acc)
      }

      let specs = ()
      let prev-tree = none
      for (i, e) in events.enumerate() {
        // Skip empty-tree excise of a single-node delete.
        if e.tree == none { continue }
        specs.push(_delete-event-to-spec(
          e,
          v,
          factors,
          heights,
          init-alt,
          visited-by-event.at(i),
          prev-tree,
        ))
        prev-tree = e.tree
      }
      _make-frames-avl-multi(specs, resolved-op, resolved-render)
    },
    rotate-display: (
      self,
      child,
      factors: false,
      heights: false,
      theme: auto,
      render-theme: auto,
    ) => {
      // Animates a structural rotation around `child`. Six-phase
      // sequence matching BST's rotate-display: init, pivots, break,
      // restructure, connect, settle. Heights are refreshed in the
      // after-tree.
      let child-value = child.value
      let child-path = (self.by-value)(child-value)
      if child-path == "" {
        panic(
          "rotate-display: cannot rotate around root node " + str(child-value) + "; child must have a parent.",
        )
      }
      let parent-path = child-path.slice(0, child-path.len() - 1)
      let parent-subtree = (self.resolve)(parent-path)
      let is-right = child-path.last() == "L"
      let after = (self.rotate)(child)

      let has-grandparent = parent-path != ""
      let middle-path = parent-path + (if is-right { "LR" } else { "RL" })
      let has-middle = (self.resolve)(middle-path) != none
      let broken-paths = (
        (if has-grandparent { (parent-path,) } else { () })
          + (child-path,)
          + (if has-middle { (middle-path,) } else { () })
      )
      let new-parent-path = parent-path + (if is-right { "R" } else { "L" })
      let new-middle-path = parent-path + (if is-right { "RL" } else { "LR" })
      let has-new-middle = (after.resolve)(new-middle-path) != none
      let new-edge-paths = (
        (if has-grandparent { (parent-path,) } else { () })
          + (new-parent-path,)
          + (if has-new-middle { (new-middle-path,) } else { () })
      )

      let direction = if is-right { "right" } else { "left" }
      let parent-value = tree-anim._alt-label(parent-subtree)
      let child-value-str = tree-anim._alt-label(child)

      let resolved-op = _resolve-op-theme-arg(theme)
      let resolved-render = _resolve-render-theme-arg(render-theme)

      let captions-a = (
        none,
        [Rotate around #child-value],
        [Break edges],
      )
      let steps-meta-a = (
        (kind: "init"),
        (kind: "pivots", paths: (parent-path, child-path)),
        (kind: "break", paths: broken-paths),
      )
      let alts-a = (
        "AVL tree: " + (self.describe)() + ". About to " + direction + "-rotate around node " + child-value-str + ".",
        "Rotation pivots identified: parent " + parent-value + " and child " + child-value-str + ".",
        "Breaking the edges that will rotate.",
      )

      let build-snapshots-a = (op, _rt) => {
        let r = tree-anim.make-renderer(self, sticky: true)
        if factors { r = _tag-factors(r, self) }
        if heights { r = _tag-heights(r, self) }
        r = (r.push-with-node)(parent-path, stroke: op.attention-stroke)
        r = (r.patch)(f => (f.style-node)(
          child-path,
          stroke: op.attention-stroke,
        ))
        r = (r.push-with-edge)(child-path, hide: true)
        if has-middle {
          r = (r.patch)(f => (f.style-edge)(middle-path, hide: true))
        }
        if has-grandparent {
          r = (r.patch)(f => (f.style-edge)(parent-path, hide: true))
        }
        r.snapshots
      }

      let captions-b = (
        [Restructure tree],
        [Reconnect edges],
        none,
      )
      let steps-meta-b = (
        (kind: "restructure"),
        (kind: "connect", paths: new-edge-paths),
        (kind: "settle"),
      )
      let alts-b = (
        "Tree restructured: "
          + child-value-str
          + " is now the parent of "
          + parent-value
          + "; rotated edges are still hidden.",
        "Reconnecting rotated edges.",
        "Rotation complete.",
      )

      let build-snapshots-b = (op, _rt) => {
        let r = tree-anim.make-renderer(after, sticky: true)
        if factors { r = _tag-factors(r, after) }
        if heights { r = _tag-heights(r, after) }
        r = (r.patch)(f => (f.style-node)(
          parent-path,
          stroke: op.attention-stroke,
        ))
        r = (r.patch)(f => (f.style-node)(
          new-parent-path,
          stroke: op.attention-stroke,
        ))
        r = (r.patch)(f => (f.style-edge)(new-parent-path, hide: true))
        if has-new-middle {
          r = (r.patch)(f => (f.style-edge)(new-middle-path, hide: true))
        }
        if has-grandparent {
          r = (r.patch)(f => (f.style-edge)(parent-path, hide: true))
        }
        r = (r.push-with-edge)(
          new-parent-path,
          stroke: op.success-stroke,
          hide: false,
        )
        if has-new-middle {
          r = (r.patch)(f => (f.style-edge)(
            new-middle-path,
            stroke: op.success-stroke,
            hide: false,
          ))
        }
        if has-grandparent {
          r = (r.patch)(f => (f.style-edge)(
            parent-path,
            stroke: op.success-stroke,
            hide: false,
          ))
        }
        r = (r.push-with-node)(parent-path, stroke: op.reset-stroke)
        r = (r.patch)(f => (f.style-node)(
          new-parent-path,
          stroke: op.reset-stroke,
        ))
        r = (r.patch)(f => (f.style-edge)(
          new-parent-path,
          stroke: op.reset-stroke,
        ))
        if has-new-middle {
          r = (r.patch)(f => (f.style-edge)(
            new-middle-path,
            stroke: op.reset-stroke,
          ))
        }
        if has-grandparent {
          r = (r.patch)(f => (f.style-edge)(
            parent-path,
            stroke: op.reset-stroke,
          ))
        }
        r.snapshots
      }

      let frames-a = _make-frames-avl(
        self,
        build-snapshots-a,
        captions-a,
        steps-meta-a,
        alts-a,
        resolved-op,
        resolved-render,
      )
      let frames-b = _make-frames-avl(
        after,
        build-snapshots-b,
        captions-b,
        steps-meta-b,
        alts-b,
        resolved-op,
        resolved-render,
      )
      frames-a + frames-b
    },
  ),
)

/// Factory: build an #raw("AVL") from a positional list of values. The
/// first argument becomes the root (height 1); the rest are
/// #raw("insert")-ed in order, so the AVL rebalancing produces the
/// final shape. Each argument is either a bare value (label defaults
/// to #raw("auto") ⇒ #raw("str(value)")) or a #raw("(value, label)")
/// 2-tuple. Equivalent to constructing the root with #raw("(AVL.new)(
/// value: v0, label: l0, height: 1, left: none, right: none)") and
/// then chaining #raw(".insert(v, label: l)") calls, but tighter to
/// seed sample trees:
///
/// ```typc
/// // root 4, then insert 1, 7, 3, 6, 8
/// let t = avl(4, 1, 7, 3, 6, 8)
///
/// // mixed labels
/// let t = avl((4, [FOUR]), 1, 7, (6, [SIX]))
/// ```
///
/// -> dictionary
#let avl(
  /// Positional values. Each is either a bare value or a
  /// #raw("(value, label)") 2-tuple. At least one is required (the
  /// root).
  ..vals,
) = {
  let xs = vals.pos()
  assert(
    xs.len() > 0,
    message: "avl: at least one value required (the root)",
  )
  let parse(x) = if type(x) == array {
    assert(
      x.len() == 2,
      message: "avl: expected (value, label) 2-tuple, got " + repr(x),
    )
    (value: x.at(0), label: x.at(1))
  } else {
    (value: x, label: auto)
  }
  let head = parse(xs.first())
  let tree = (AVL.new)(
    value: head.value,
    label: head.label,
    height: 1,
    left: none,
    right: none,
  )
  for x in xs.slice(1) {
    let p = parse(x)
    tree = (tree.insert)(p.value, label: p.label)
  }
  tree
}
