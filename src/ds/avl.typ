// AVL tree.
//
// A binary search tree that keeps itself shallow by storing a height per
// node and rotating whenever a subtree gets one level lopsided:
//
//   bf(n) = height(n.left) - height(n.right)      the balance factor
//   |bf(n)| <= 1 for every node n                 the AVL invariant
//
// Heights are 1-indexed: a leaf has height 1, a nil child height 0.
//
// A node is `(kind: "avl", value, label, height, left, right)`. `value`
// orders the tree, `label` is what gets drawn (`auto` falls back to
// `str(value)`), and `height` is kept up to date by every operation — it is
// never a parameter the caller supplies.
//
// Fix-up cases at an imbalanced node n (|bf(n)| == 2):
//
//   LL: bf(n) == +2, bf(n.left)  >= 0   single right rotation at n
//   LR: bf(n) == +2, bf(n.left)  <  0   left rotation at n.left, then
//                                       right rotation at n
//   RR: bf(n) == -2, bf(n.right) <= 0   single left rotation at n
//   RL: bf(n) == -2, bf(n.right) >  0   right rotation at n.right, then
//                                       left rotation at n
//
// (For an insert the child's balance factor is strictly nonzero on the side
// that caused the imbalance; the >= / <= branches are what delete needs,
// where the child can be balanced.)
//
// An insert stops after one fix-up — a single rotation restores the
// subtree's pre-insertion height, so no ancestor above it can have changed.
// A delete may rotate several times on the way up, because removing a node
// can shorten a subtree and push the imbalance upward.
//
// `rotate` is a *structural* primitive: it rotates a node up and refreshes
// the two rotated heights, but makes no attempt to restore the invariant.
// The fix-ups do not go through it.
//
// step.kind vocabulary
// --------------------
//   static                       the one frame of `display`
//   init                         the opening frame of every animation
//   compare                      one comparison along a descent
//   found / not-found            how a search ended
//   descend                      the whole search path in one frame
//   insert                       the new leaf has appeared
//   recompute                    one ancestor's height recomputed on the
//                                climb (deepest first)
//   check                        |bf| == 2 here; the case is named
//   rotate-zigzag                the LR/RL straightening rotation
//   rotate-finish                the rotation at the imbalanced node
//   mark-target                  the deletion target
//   find-predecessor / transfer  the walk to the in-order predecessor, and
//                                its value moving into the target's slot
//   excise                       the deletion-position node is gone
//   pivots / break / restructure / connect
//                                the shape-changing rotation steps
//   visit                        one node of a traversal
//   settled                      terminal success of a mutation
// The final frame of every display carries `step.result` — the tree the
// operation produced (the unchanged input, for a search or traversal).

#import "../core/draw-util.typ": anchor
#import "../core/frame.typ": make-frames, make-renderer, patch
#import "../core/ops.typ": style-node
#import "../core/snapshot.typ": blank-snapshot, note-node, with-edge, with-node
#import "../core/style.typ": role
#import "../core/text.typ": alt-describe, alt-intro, alt-label
#import "../draw/tree.typ": draw-tree
#import "tree-common.typ" as tc
#import "tree-common.typ": (
  by-value, contains, in-order, level-order, path-to, post-order, pre-order,
  resolve,
)

#let _DS = "AVL tree"

// ===================================================================
// Heights
// ===================================================================

#let _height(n) = if n == none { 0 } else { n.height }
#let _bf(n) = if n == none { 0 } else { _height(n.left) - _height(n.right) }
#let _new-height(l, r) = 1 + calc.max(_height(l), _height(r))

// The internal constructor, argument-ordered the way the rotations read
// (height, left, value, label, right).
#let _mk(h, l, v, lab, r) = (
  kind: "avl",
  value: v,
  label: lab,
  height: h,
  left: l,
  right: r,
)

// `n` with its height recomputed from its current children — what every
// child swap has to be followed by.
#let _refresh(n) = _mk(
  _new-height(n.left, n.right),
  n.left,
  n.value,
  n.label,
  n.right,
)

// ===================================================================
// Construction
// ===================================================================

/// A node holding `value`, with either no children (a leaf) or both — pass
/// `none` for a missing one. The height is *computed* from the children, so
/// a hand-built literal is as trustworthy as one grown by `insert` and
/// nobody has to reimplement the height recursion.
///
/// ```typ
/// avl.node(8, avl.leaf(3), avl.node(10, none, avl.leaf(14)))
/// ```
///
/// The one reason to pass `height:` explicitly is to build a tree caught
/// *mid-operation*, with a stale spine — which is exactly what
/// @@fixup-display() animates. `avl.node(4, avl.node(2, none,
/// avl.leaf(3)), none, height: 2)` is "a leaf was just grafted on and
/// nothing has been recomputed yet".
///
/// -> dictionary
#let node(
  /// The ordering key.
  /// -> int
  value,
  /// Either nothing (a leaf) or exactly two children, left then right.
  /// -> dictionary | none
  ..children,
  /// What to draw in the node; `auto` draws `str(value)`.
  /// -> auto | any
  label: auto,
  /// The stored height. `auto` computes it from the children; an explicit
  /// integer builds a deliberately stale node.
  /// -> auto | int
  height: auto,
) = {
  let cs = children.pos()
  assert(
    cs.len() == 0 or cs.len() == 2,
    message: "avl.node: expected no children or exactly two (left, right), got "
      + str(cs.len())
      + ".",
  )
  let l = cs.at(0, default: none)
  let r = cs.at(1, default: none)
  _mk(if height == auto { _new-height(l, r) } else { height }, l, value, label, r)
}

/// A childless node of height 1 — `node(value)` with the intent spelled out.
/// -> dictionary
#let leaf(
  /// The ordering key.
  /// -> int
  value,
  /// What to draw in the node; `auto` draws `str(value)`.
  /// -> auto | any
  label: auto,
  /// The stored height. `auto` is 1; an explicit integer builds a
  /// deliberately stale node.
  /// -> auto | int
  height: auto,
) = node(value, label: label, height: height)

// ===================================================================
// Rotations and the fix-up rules
// ===================================================================

#let _rotate-right(n) = {
  let l = n.left
  _refresh(_mk(0, l.left, l.value, l.label, _refresh(_mk(0, l.right, n.value, n.label, n.right))))
}

#let _rotate-left(n) = {
  let r = n.right
  _refresh(_mk(0, _refresh(_mk(0, n.left, n.value, n.label, r.left)), r.value, r.label, r.right))
}

// Replace the subtree at `path`, rebuilding the spine above it. Spine
// heights are deliberately NOT refreshed — the climb does that one node at
// a time, which is the thing the animation is showing.
#let _replace-at(n, path, new) = if path == "" {
  new
} else if path.first() == "L" {
  _mk(
    n.height,
    _replace-at(n.left, path.slice(1), new),
    n.value,
    n.label,
    n.right,
  )
} else {
  _mk(
    n.height,
    n.left,
    n.value,
    n.label,
    _replace-at(n.right, path.slice(1), new),
  )
}

#let _recompute-height-at(tree, path) = _replace-at(
  tree,
  path,
  _refresh(resolve(tree, path)),
)

// Copy `value` and `label` into the node at `path`, keeping its height and
// children — the predecessor transfer of a two-child delete.
#let _set-value-at(tree, path, value, label) = {
  let n = resolve(tree, path)
  _replace-at(tree, path, _mk(n.height, n.left, value, label, n.right))
}

#let _rotate-right-at(tree, path) = _replace-at(
  tree,
  path,
  _rotate-right(resolve(tree, path)),
)
#let _rotate-left-at(tree, path) = _replace-at(
  tree,
  path,
  _rotate-left(resolve(tree, path)),
)

/// Which imbalance case applies at `n` — `"LL"`, `"LR"`, `"RR"`, `"RL"`, or
/// `none` when the node is balanced.
/// -> str | none
#let imbalance-case(
  /// The node.
  /// -> dictionary | none
  n,
) = {
  let bf = _bf(n)
  if bf == 2 {
    if _bf(n.left) >= 0 { "LL" } else { "LR" }
  } else if bf == -2 {
    if _bf(n.right) <= 0 { "RR" } else { "RL" }
  } else { none }
}

// Apply the fix-up rules at a node whose height is already up to date,
// returning the rebalanced subtree.
#let _fix-at(n) = {
  let case = imbalance-case(n)
  if case == none {
    n
  } else if case == "LL" {
    _rotate-right(n)
  } else if case == "RR" {
    _rotate-left(n)
  } else if case == "LR" {
    _rotate-right(_mk(n.height, _rotate-left(n.left), n.value, n.label, n.right))
  } else {
    _rotate-left(_mk(n.height, n.left, n.value, n.label, _rotate-right(n.right)))
  }
}

// ===================================================================
// Pure operations
// ===================================================================

// Recursive AVL insert: descend, splice, then rebalance on the way back up.
#let _avl-insert(n, v, label) = if n == none {
  _mk(1, none, v, label, none)
} else if v <= n.value {
  _fix-at(_refresh(_mk(0, _avl-insert(n.left, v, label), n.value, n.label, n.right)))
} else {
  _fix-at(_refresh(_mk(0, n.left, n.value, n.label, _avl-insert(n.right, v, label))))
}

/// Insert `v`, returning a new tree with the AVL invariant restored. Ties
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
) = _avl-insert(tree, v, label)

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
) = tc.insert-many(tree, insert, vals.pos(), who: "avl.insert-many")

/// Build a tree from a list of values: the first becomes the root, the rest
/// are inserted in order, so the rebalancing produces the final shape. Each
/// is a bare key or a `(value, label)` pair.
///
/// ```typ
/// avl.new(4, 1, 7, 3, 6, 8)
/// avl.new((4, [FOUR]), 1, 7, (6, [SIX]))
/// ```
///
/// -> dictionary
#let new(
  /// The values. At least one is required — it becomes the root.
  /// -> any
  ..vals,
) = {
  let xs = vals.pos()
  assert(xs.len() > 0, message: "avl.new: at least one value is required (the root).")
  let head = tc.parse-value(xs.first(), "avl.new")
  tc.insert-many(leaf(head.value, label: head.label), insert, xs.slice(1), who: "avl.new")
}

// Peel the rightmost node off a subtree — the in-order predecessor, from
// the parent's point of view — rebalancing on the way up.
#let _delete-max(n) = if n.right == none { n.left } else {
  _fix-at(_refresh(_mk(0, n.left, n.value, n.label, _delete-max(n.right))))
}

/// Delete `v`, returning a new tree (or `none` if the last node went). A
/// node with two children is replaced by its in-order predecessor — value
/// *and* label. Rebalancing runs on the whole climb back to the root, so
/// one deletion may rotate several times.
/// -> dictionary | none
#let delete(
  /// The tree.
  /// -> dictionary
  tree,
  /// The ordering key to delete.
  /// -> int
  v,
) = {
  let recur(n) = if n == none {
    none
  } else if v < n.value {
    _fix-at(_refresh(_mk(0, recur(n.left), n.value, n.label, n.right)))
  } else if v > n.value {
    _fix-at(_refresh(_mk(0, n.left, n.value, n.label, recur(n.right))))
  } else if n.left == none {
    n.right
  } else if n.right == none {
    n.left
  } else {
    let find-max(m) = if m.right == none { m } else { find-max(m.right) }
    let pred = find-max(n.left)
    _fix-at(_refresh(_mk(0, _delete-max(n.left), pred.value, pred.label, n.right)))
  }
  recur(tree)
}

/// Rotate around `child` — anywhere in the tree, not only at the root.
/// `child` is located by searching for its value, so its parent and the
/// direction are inferred.
///
/// This is a *structural* rotation: the two rotated nodes get fresh heights
/// and the spine above is refreshed, but the AVL invariant is not restored.
/// The insert and delete fix-ups do not go through it.
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
    panic("avl.rotate: cannot rotate the root with itself.")
  }
  let parent-path = child-path.slice(0, child-path.len() - 1)
  let is-right = child-path.last() == "L"
  let parent = resolve(tree, parent-path)
  let rotated = if is-right { _rotate-right(parent) } else { _rotate-left(parent) }
  let spliced = _replace-at(tree, parent-path, rotated)
  // Heights above the rotation are stale; refresh the spine bottom-up.
  let refresh-spine(t, p) = if p == "" { _refresh(t) } else if p.first() == "L" {
    _refresh(_mk(t.height, refresh-spine(t.left, p.slice(1)), t.value, t.label, t.right))
  } else {
    _refresh(_mk(t.height, t.left, t.value, t.label, refresh-spine(t.right, p.slice(1))))
  }
  refresh-spine(spliced, parent-path)
}

/// A recursive textual rendering of the tree, used in alt text. Each node's
/// height follows its label after a colon.
/// -> str
#let describe(
  /// The tree.
  /// -> dictionary
  tree,
) = tc.describe(tree, head: n => alt-label(n) + ":" + str(n.height))

/// Check the search-tree ordering, that every stored `height` agrees with
/// the recomputed one, and that `|bf| <= 1` everywhere. Returns `true` or
/// panics naming the first violation.
/// -> bool
#let check-invariants(
  /// The tree.
  /// -> dictionary
  tree,
) = {
  // Returns the subtree's height, panicking on the way up.
  let walk(n) = if n == none { 0 } else {
    assert(
      n.left == none or n.left.value <= n.value,
      message: "avl.check-invariants: search-tree order violated at "
        + str(n.value)
        + " — left child is larger.",
    )
    assert(
      n.right == none or n.right.value >= n.value,
      message: "avl.check-invariants: search-tree order violated at "
        + str(n.value)
        + " — right child is smaller.",
    )
    let lh = walk(n.left)
    let rh = walk(n.right)
    let expected = 1 + calc.max(lh, rh)
    assert(
      n.height == expected,
      message: "avl.check-invariants: stored height "
        + str(n.height)
        + " at node "
        + str(n.value)
        + " disagrees with the recomputed "
        + str(expected)
        + ".",
    )
    assert(
      calc.abs(lh - rh) <= 1,
      message: "avl.check-invariants: balance factor "
        + str(lh - rh)
        + " at node "
        + str(n.value)
        + " — the subtree is more than one level lopsided.",
    )
    expected
  }
  let _ = walk(tree)
  true
}

// ===================================================================
// The traces
// ===================================================================
//
// Each trace runs the algorithm once and records what happened as an
// ordered list of events, every event carrying the tree as it stood after
// that step. The pure operations above are the plain recursive form; the
// displays walk these events. The rebalancing rules are written twice, but
// they are checked against each other by `avl-ops`, and the alternative —
// threading an event log through the recursion — makes the pure operations
// much harder to read than the algorithm they implement.

// Every proper prefix of `path`, deepest first — the ancestors a fix-up
// climbs through.
#let _ancestors(path) = {
  let out = ()
  let cur = path
  while cur != "" {
    cur = cur.slice(0, cur.len() - 1)
    out.push(cur)
  }
  out
}

// The climb shared by all three traces: recompute each ancestor's height
// deepest-first, and rebalance wherever |bf| hits 2. With
// `stop-after-fix: true` the climb ends at the first rotation — which is
// what an insert wants, since one rotation restores the subtree's original
// height and nothing above it can have changed.
#let _climb(tree, ancestors, stop-after-fix: false) = {
  let events = ()
  let cur-tree = tree
  for anc-path in ancestors {
    cur-tree = _recompute-height-at(cur-tree, anc-path)
    let anc = resolve(cur-tree, anc-path)
    events.push((
      kind: "recompute",
      path: anc-path,
      height: anc.height,
      tree: cur-tree,
    ))
    let case = imbalance-case(anc)
    if case != none {
      events.push((
        kind: "check",
        path: anc-path,
        case: case,
        bf: _bf(anc),
        tree: cur-tree,
      ))
      if case == "LR" or case == "RL" {
        let child-path = anc-path + (if case == "LR" { "L" } else { "R" })
        cur-tree = if case == "LR" {
          _rotate-left-at(cur-tree, child-path)
        } else { _rotate-right-at(cur-tree, child-path) }
        events.push((
          kind: "rotate-zigzag",
          path: child-path,
          case: case,
          tree: cur-tree,
        ))
      }
      cur-tree = if case == "LL" or case == "LR" {
        _rotate-right-at(cur-tree, anc-path)
      } else { _rotate-left-at(cur-tree, anc-path) }
      events.push((
        kind: "rotate-finish",
        path: anc-path,
        case: case,
        tree: cur-tree,
      ))
      if stop-after-fix { break }
    }
  }
  (events: events, tree: cur-tree)
}

// Insert: descend, splice the leaf, climb. Returns `(events, tree)`.
#let _insert-trace(tree, v, label) = {
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

  // Splice the new leaf. Heights on the spine above stay stale until the
  // climb recomputes them one at a time — which is the point of the
  // animation, so the trace must not shortcut it.
  let insert-at(n, path) = if path == "" {
    _mk(1, none, v, label, none)
  } else if path.first() == "L" {
    _mk(n.height, insert-at(n.left, path.slice(1)), n.value, n.label, n.right)
  } else {
    _mk(n.height, n.left, n.value, n.label, insert-at(n.right, path.slice(1)))
  }
  let cur-tree = insert-at(tree, insert-path)

  let climb = _climb(cur-tree, visited.rev(), stop-after-fix: true)
  (
    events: (
      (kind: "init", tree: tree),
      (
        kind: "descend",
        visited: visited,
        insert-path: insert-path,
        tree: tree,
      ),
      (kind: "insert", path: insert-path, tree: cur-tree),
    )
      + climb.events,
    tree: climb.tree,
  )
}

// Delete: descend, hand a two-child target its predecessor's value, excise,
// climb. Returns `(events, tree)`. With `with-search: true` the descent is
// reported one comparison per event; otherwise as a single "descend" event.
#let _delete-trace(tree, v, with-search) = {
  let events = ()

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
  let replacement = if excise-node.left != none {
    excise-node.left
  } else { excise-node.right }

  // Excising the root of a single-node tree leaves the tree empty.
  if excise-path == "" and replacement == none {
    events.push((kind: "excise", path: excise-path, tree: none))
    return (events: events, tree: none)
  }

  cur-tree = _replace-at(cur-tree, excise-path, replacement)
  events.push((kind: "excise", path: excise-path, tree: cur-tree))

  // Unlike an insert, a delete can shorten a subtree, so the imbalance may
  // reappear further up: the climb runs all the way to the root.
  let climb = _climb(cur-tree, _ancestors(excise-path))
  (events: events + climb.events, tree: climb.tree)
}

// The fix-up climb alone, from `start-path` — usually the path of whatever
// was just modified by hand. Deliberately does NOT validate its input:
// `fixup-display` uses it to show configurations a single insert or delete
// cannot produce, such as several imbalances on one spine.
#let _fixup-trace(tree, start-path) = _climb(tree, _ancestors(start-path))

// ===================================================================
// The tag layers
// ===================================================================

// Every path in the tree, root first.
#let _all-paths(tree) = {
  let walk(n, path) = if n == none { () } else {
    (path,) + walk(n.left, path + "L") + walk(n.right, path + "R")
  }
  walk(tree, "")
}

/// The signed balance factor of the node at `path`, formatted the way the
/// `factors:` layer draws it — `"+1"`, `"0"`, `"-1"`.
/// -> str
#let balance-factor(
  /// The tree.
  /// -> dictionary
  tree,
  /// The L/R path of the node.
  /// -> str
  path,
) = {
  let bf = _bf(resolve(tree, path))
  if bf > 0 { "+" + str(bf) } else { str(bf) }
}

// The structural layer under every animation: balance factors in the node
// tag slot, subtree heights in the edge tag slot. `bf-tree` is where the
// balance factors are read from — normally the tree being drawn, but a
// `recompute` frame reads the *previous* tree so a node's factor doesn't
// silently update before the climb reaches it. The root has no incoming
// edge, so its own height isn't labelled; its children's are, which is
// what makes its balance factor readable.
#let _base(tree, factors, heights, bf-tree: auto) = {
  let snap = blank-snapshot()
  if factors {
    let bft = if bf-tree == auto { tree } else { bf-tree }
    for p in _all-paths(bft) {
      snap = with-node(snap, p, (tag: balance-factor(bft, p)))
    }
  }
  if heights {
    for p in _all-paths(tree) {
      if p != "" {
        snap = with-edge(snap, p, (tag: str(resolve(tree, p).height)))
      }
    }
  }
  snap
}

// ===================================================================
// Style vocabulary
// ===================================================================

/// Ring nodes as imbalanced — the way a `check` frame marks the node whose
/// balance factor has hit ±2 — optionally naming the case that applies in
/// the operation-note slot.
///
/// ```typ
/// apply-ops(r, avl.unbalanced("L", case: "LR") + commit())
/// ```
///
/// -> array
#let unbalanced(
  /// The paths to mark.
  /// -> str
  ..keys,
  /// The imbalance case (`"LL"`, `"LR"`, `"RR"`, `"RL"`), drawn in the note
  /// slot; `none` draws no note.
  /// -> str | none
  case: none,
) = style-node(
  ..keys.pos(),
  stroke: role("attention-stroke"),
  ..if case != none { (note: case) },
)

// ===================================================================
// Rendering
// ===================================================================

/// A `Renderer` over this tree, bound to the tree backend and pre-painted
/// with whichever tag layers you ask for — the entry point for driving an
/// animation yourself with the `Op` command stream. Pass `sticky: true` so
/// the tags (and your own highlights) carry from frame to frame.
/// -> dictionary
#let renderer(
  /// The tree.
  /// -> dictionary
  tree,
  /// Whether every node carries its signed balance factor.
  /// -> bool
  factors: false,
  /// Whether every non-root edge carries the height of the subtree below it.
  /// -> bool
  heights: false,
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
  _ => _base(tree, factors, heights),
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

/// The tree as a single static frame.
/// -> array
#let display(
  /// The tree.
  /// -> dictionary
  tree,
  /// Whether every node carries its signed balance factor.
  /// -> bool
  factors: false,
  /// Whether every non-root edge carries the height of the subtree below it.
  /// -> bool
  heights: false,
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
      build: _ => _base(tree, factors, heights),
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
  /// Whether every node carries its signed balance factor.
  /// -> bool
  factors: false,
  /// Whether every non-root edge carries the height of the subtree below it.
  /// -> bool
  heights: false,
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
  base: _ => _base(tree, factors, heights),
  node-style: node-style,
  edge-style: edge-style,
  theme: theme,
)

// ===================================================================
// Events to frames
// ===================================================================

// The caption / step / alt for the climb kinds — everything that happens on
// the way back up, after the tree has changed shape. Split from
// `_event-meta` because it is its own vocabulary: heights are recomputed at
// each ancestor, and where one is out of balance, the case name says which
// pair of rotations restores it.
#let _climb-meta(event, node-at) = if event.kind == "recompute" {
  (
    caption: [Recompute height],
    step: (kind: "recompute", path: event.path, height: event.height),
    alt: "Recomputed height at node "
      + node-at(event.path)
      + ": new height is "
      + str(event.height)
      + ".",
  )
} else if event.kind == "check" {
  (
    caption: [Imbalance: case #(event.case)],
    step: (kind: "check", path: event.path, case: event.case, bf: event.bf),
    alt: "Balance factor at node "
      + node-at(event.path)
      + " is "
      + str(event.bf)
      + "; case "
      + event.case
      + " applies.",
  )
} else if event.kind == "rotate-zigzag" {
  (
    caption: [Rotate child],
    step: (kind: "rotate-zigzag", path: event.path, case: event.case),
    alt: "Case "
      + event.case
      + " (zigzag): rotated the imbalanced node's child to straighten the "
      + "configuration.",
  )
} else {
  (
    caption: [Rotate (case #(event.case))],
    step: (kind: "rotate-finish", path: event.path, case: event.case),
    alt: "Case "
      + event.case
      + ": rotated the imbalanced node; the AVL invariant is restored in "
      + "this subtree.",
  )
}

// The caption / step / alt for one trace event. `init-alt` belongs to the
// caller (it names the tree being operated on); `v` is read by the branches
// that narrate the search.
#let _event-meta(event, v, init-alt) = {
  let caption = none
  let step = (kind: event.kind)
  let alt = ""
  let node-at(p) = alt-label(resolve(event.tree, p))

  if event.kind == "init" {
    alt = init-alt
  } else if event.kind == "compare" {
    let cmp-text = str(v) + " " + event.cmp + " " + str(resolve(event.tree, event.path).value)
    caption = cmp-text
    step = (
      kind: if event.found { "found" } else { "compare" },
      path: event.path,
      cmp: event.cmp,
      found: event.found,
    )
    alt = if event.found {
      "Match found at node " + node-at(event.path) + "; ready to delete."
    } else {
      ("Comparing "
        + cmp-text
        + " at node "
        + node-at(event.path)
        + "; descending.")
    }
  } else if event.kind == "descend" {
    caption = [Search for #v]
    let inserting = "insert-path" in event
    step = (
      kind: "descend",
      visited: event.visited,
      ..if inserting { (insert-path: event.insert-path) },
    )
    alt = if inserting {
      ("Walked the search path for "
        + str(v)
        + "; the insertion point is one step beyond the last visited node.")
    } else {
      "Walked the search path for " + str(v) + "; ready to delete."
    }
  } else if event.kind == "not-found" {
    caption = [#v not in tree]
    alt = str(v) + " is not in the tree; nothing to delete."
  } else if event.kind == "insert" {
    caption = [Insert #v as new leaf]
    step = (kind: "insert", path: event.path)
    alt = "Inserted " + str(v) + " as a new leaf with height 1."
  } else if event.kind == "mark-target" {
    caption = [Delete #v]
    step = (kind: "mark-target", path: event.target-path)
    alt = "Marked node " + node-at(event.target-path) + " for deletion."
  } else if event.kind == "find-predecessor" {
    caption = [Find predecessor]
    step = (
      kind: "find-predecessor",
      walk: event.walk,
      predecessor-path: event.predecessor-path,
      target-path: event.target-path,
    )
    alt = ("Node "
      + node-at(event.target-path)
      + " has two children; walking the left subtree to find the in-order "
      + "predecessor: "
      + node-at(event.predecessor-path)
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
  } else {
    let m = _climb-meta(event, node-at)
    caption = m.caption
    step = m.step
    alt = m.alt
  }

  (caption: caption, step: step, alt: alt)
}

// The snapshot builder for one trace event: the structural painting (balance
// factors, height tags) plus that event's highlight.
#let _event-build(event, v, factors, heights, visited, bf-tree) = th => {
  let cur = _base(event.tree, factors, heights, bf-tree: bf-tree)
  if event.kind == "compare" {
    for p in visited { cur = with-node(cur, p, (stroke: th.op.search-stroke)) }
    cur = note-node(
      cur,
      event.path,
      str(v) + " " + event.cmp + " " + str(resolve(event.tree, event.path).value),
    )
  } else if event.kind == "descend" or event.kind == "not-found" {
    for p in event.visited {
      cur = with-node(cur, p, (stroke: th.op.search-stroke))
    }
  } else if event.kind == "insert" {
    cur = with-node(
      cur,
      event.path,
      (stroke: th.op.settled-stroke, fill: th.op.success-fill),
    )
    cur = with-edge(cur, event.path, (stroke: th.op.success-stroke))
  } else if event.kind == "mark-target" {
    cur = with-node(cur, event.target-path, (stroke: th.op.attention-stroke))
    cur = note-node(cur, event.target-path, [delete])
  } else if event.kind == "find-predecessor" {
    cur = with-node(cur, event.target-path, (stroke: th.op.attention-stroke))
    for p in event.walk { cur = with-node(cur, p, (stroke: th.op.search-stroke)) }
    cur = note-node(cur, event.predecessor-path, [pred])
  } else if event.kind == "transfer" {
    cur = with-node(cur, event.target-path, (stroke: th.op.settled-stroke))
    cur = note-node(cur, event.target-path, [← #(event.new-value)])
    cur = with-node(
      cur,
      event.predecessor-path,
      (stroke: th.op.attention-stroke),
    )
  } else if event.kind == "recompute" {
    cur = with-node(cur, event.path, (stroke: th.op.search-stroke))
  } else if event.kind == "check" {
    cur = with-node(cur, event.path, (stroke: th.op.attention-stroke))
    cur = note-node(cur, event.path, event.case)
  } else if event.kind == "rotate-zigzag" {
    cur = with-node(cur, event.path, (stroke: th.op.attention-stroke))
  } else if event.kind == "rotate-finish" {
    cur = with-node(cur, event.path, (stroke: th.op.settled-stroke))
    cur = with-edge(cur, event.path, (stroke: th.op.success-stroke))
  }
  // "excise" gets no highlight — the structural change speaks for itself.
  cur
}

// One spec per trace event. Insert, delete and fix-up all draw from the
// same vocabulary — the climb is literally the same events — so one
// translation serves all three. The two `descend` flavours are told apart
// by `insert-path`, which only an insert's descent carries.
//
// `visited` is the accumulated search trail, so a `compare` frame shows the
// whole walk rather than just the current node. `prev-tree` is the previous
// event's tree: a `recompute` frame reads balance factors from *it*, so a
// node's factor doesn't update before the climb reaches it. Height tags
// always come from the current tree, so the label moves with the caption.
#let _event-spec(
  event,
  v,
  factors,
  heights,
  init-alt,
  visited: (),
  prev-tree: none,
) = {
  let bf-tree = if event.kind == "recompute" and prev-tree != none {
    prev-tree
  } else { auto }
  (
    structure: event.tree,
    build: _event-build(event, v, factors, heights, visited, bf-tree),
    .._event-meta(event, v, init-alt),
  )
}

// Turn a whole event list into specs, threading the previous event's tree
// and (for a delete) the accumulating search trail.
#let _event-specs(events, v, factors, heights, init-alt) = {
  let visited-acc = ()
  let prev-tree = none
  let specs = ()
  for e in events {
    if e.kind == "compare" { visited-acc = visited-acc + (e.path,) }
    // The excise that empties a single-node tree has no tree to draw; the
    // preceding mark-target frame already says what is about to happen.
    if e.tree != none {
      specs.push(_event-spec(
        e,
        v,
        factors,
        heights,
        init-alt,
        visited: visited-acc,
        prev-tree: prev-tree,
      ))
      prev-tree = e.tree
    }
  }
  specs
}

/// Animate inserting `v`: the search descent in one frame, the new leaf
/// appearing, then the climb — one `recompute` frame per ancestor, and at
/// the first node whose balance factor reaches ±2, a `check` naming the
/// case, the straightening rotation if the case is LR or RL, and the
/// rotation at the imbalanced node itself. The climb stops there: one
/// rotation restores the subtree's pre-insertion height.
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
  /// Whether every node carries its signed balance factor.
  /// -> bool
  factors: false,
  /// Whether every non-root edge carries the height of the subtree below it.
  /// -> bool
  heights: false,
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
  _frames(
    tc.stamp-result(
      _event-specs(
        trace.events,
        v,
        factors,
        heights,
        alt-intro(_DS, describe(tree), "insert " + str(v)),
      ),
      trace.tree,
    ),
    theme,
    node-style,
    edge-style,
  )
}

/// Animate deleting `v`: the target is marked, a two-child target hands its
/// slot to its in-order predecessor, the deletion-position node is excised,
/// and the climb rebalances all the way to the root — a delete can shorten
/// a subtree, so unlike an insert it may rotate several times.
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
  /// Whether every node carries its signed balance factor.
  /// -> bool
  factors: false,
  /// Whether every non-root edge carries the height of the subtree below it.
  /// -> bool
  heights: false,
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
  // Name the target by its label when it has one — that is how it is drawn.
  let del-label = if contains(tree, v) {
    alt-label(resolve(tree, by-value(tree, v)))
  } else { str(v) }
  _frames(
    tc.stamp-result(
      _event-specs(
        trace.events,
        v,
        factors,
        heights,
        alt-intro(_DS, describe(tree), "delete " + del-label),
      ),
      trace.tree,
    ),
    theme,
    node-style,
    edge-style,
  )
}

/// Animate the fix-up climb on a hand-built tree that is already
/// imbalanced, starting from `violation-path` — usually the path of
/// whatever was just modified by hand.
///
/// The tree is deliberately not validated: the point is to show
/// configurations a single insert or delete cannot produce, such as several
/// imbalances on one spine, or one case shown in isolation.
/// -> array
#let fixup-display(
  /// The tree.
  /// -> dictionary
  tree,
  /// The deepest path the climb starts from.
  /// -> str
  violation-path,
  /// Whether every node carries its signed balance factor.
  /// -> bool
  factors: false,
  /// Whether every non-root edge carries the height of the subtree below it.
  /// -> bool
  heights: false,
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
  let fix = _fixup-trace(tree, violation-path)
  let init-alt = (alt-describe(_DS, describe(tree))
    + " Imbalance below \""
    + violation-path
    + "\"; about to run the fix-up climb.")
  _frames(
    tc.stamp-result(
      _event-specs(
        ((kind: "init", tree: tree),) + fix.events,
        none,
        factors,
        heights,
        init-alt,
      ),
      fix.tree,
    ),
    theme,
    node-style,
    edge-style,
  )
}

/// Animate a rotation around `child` — anywhere in the tree, not only at
/// the root. `child` is the node that should become the new subtree root;
/// its parent and the direction are inferred from the search path.
///
/// Six frames: the pivots are marked, the edges that will move are broken,
/// the tree restructures with those edges still hidden, they reconnect, and
/// the highlights clear.
/// -> array
#let rotate-display(
  /// The tree.
  /// -> dictionary
  tree,
  /// The node that should become the new subtree root.
  /// -> dictionary
  child,
  /// Whether every node carries its signed balance factor.
  /// -> bool
  factors: false,
  /// Whether every non-root edge carries the height of the subtree below it.
  /// -> bool
  heights: false,
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
  let after = rotate(tree, child)
  tc.render-rotate(
    tree,
    after,
    child,
    _DS,
    describe(tree),
    who: "avl.rotate-display",
    // Phase B draws the rotated tree, so its tags must come from `after` —
    // a rotation changes the heights on both sides of the pivot.
    base: _ => _base(tree, factors, heights),
    after-base: _ => _base(after, factors, heights),
    node-style: node-style,
    edge-style: edge-style,
    theme: theme,
  )
}

// ===================================================================
// Traversals
// ===================================================================

#let _traversal(tree, paths, name, factors, heights, node-style, edge-style, theme) = tc.render-traversal(
  tree,
  paths,
  name,
  _DS,
  describe(tree),
  base: _ => _base(tree, factors, heights),
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
  /// Whether every node carries its signed balance factor.
  /// -> bool
  factors: false,
  /// Whether every non-root edge carries the height of the subtree below it.
  /// -> bool
  heights: false,
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
  factors,
  heights,
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
  /// Whether every node carries its signed balance factor.
  /// -> bool
  factors: false,
  /// Whether every non-root edge carries the height of the subtree below it.
  /// -> bool
  heights: false,
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
  factors,
  heights,
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
  /// Whether every node carries its signed balance factor.
  /// -> bool
  factors: false,
  /// Whether every non-root edge carries the height of the subtree below it.
  /// -> bool
  heights: false,
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
  factors,
  heights,
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
  /// Whether every node carries its signed balance factor.
  /// -> bool
  factors: false,
  /// Whether every non-root edge carries the height of the subtree below it.
  /// -> bool
  heights: false,
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
  factors,
  heights,
  node-style,
  edge-style,
  theme,
)
