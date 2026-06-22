#import "@preview/typsy:0.2.2": Any, Array, Int, Union, class
#import "./tree-anim.typ" as tree-anim
#import "./op-theme.typ": _resolve-op-theme-arg

// ===================================================================
// B24 — 2-3-4 tree (B-tree of order 4)
// ===================================================================
//
// A B-tree where every internal node holds 1, 2, or 3 keys (so 2, 3,
// or 4 children) and every leaf sits at the same depth. The four
// invariants enforced by every public operation:
//
//   1. 1 ≤ keys.len() ≤ 3 (root may have 1..3; transient 4-key states
//      live only inside split helpers, never escape).
//   2. keys are strictly increasing.
//   3. Either children.len() == 0 (leaf) or children.len() == keys.len() + 1.
//   4. All leaves are at the same depth.
//
// Two rebalancing algorithms are exposed via `strategy:` on
// `insert` / `delete`:
//
//   "top-down"  (default) — preventive: split any 3-key (full) node on
//               the way down for insert; refill any 1-key node on the
//               way down for delete. Single-pass recursion. Top-down
//               splits promote the middle key (index 1) of the 3-key
//               node *before* the new key is inserted.
//   "bottom-up" — reactive: walk to the leaf first; allow a transient
//               4-key (overflowed) leaf or internal node, then split
//               on the way back up. Bottom-up splits promote the
//               upper-middle key (index 2) of the 4-key overflow.
//
// Both produce valid 2-3-4 trees containing the same keys, but the
// SHAPES may differ. The two algorithms agree whenever the inserted
// key falls in the lower half of an about-to-be-split node; they
// diverge when it falls in the upper half (because the bottom-up
// split sees the inserted key as a candidate for promotion while the
// top-down split doesn't). The `*-display` methods honour the choice
// so the two algorithms can be compared frame-by-frame.
//
// Per-key addressability: a key compartment is identified by its
// node-path followed by `"#" + str(i)`, where `i` is the 0-indexed
// compartment within that node. So "1#2" is the third key of the
// second child of the root. Edges are keyed by their child's
// node-path (no `#` suffix). This drives `path-anchor` and the
// `key-styles` slot on `NodeStyle`.

// --- node-construction & shape helpers -----------------------------
//
// Every helper takes `cls` first so it can call `cls.new` without
// referring to `B24` (not yet in scope while helpers are defined).

#let _node(cls, keys, labels, children) = (cls.new)(
  keys: keys,
  labels: labels,
  children: children,
)

#let _is-leaf(node) = node.children.len() == 0

// Resolve a subtree by digit-only path. `path == ""` returns `node`
// itself. Caller must not walk off a missing child.
#let _resolve-at(node, path) = if path == "" {
  node
} else {
  let idx = int(path.first())
  _resolve-at(node.children.at(idx), path.slice(1))
}

// Replace the subtree at `path` with `new`, rebuilding the spine
// above. Spine nodes' keys/labels/other-children are preserved.
#let _replace-at(cls, node, path, new) = if path == "" {
  new
} else {
  let idx = int(path.first())
  let new-children = node.children
  new-children.at(idx) = _replace-at(cls, node.children.at(idx), path.slice(1), new)
  _node(cls, node.keys, node.labels, new-children)
}

// --- split / merge primitives --------------------------------------

// Index of the first key in `keys` that is ≥ v. Used both as a
// search-step (which child to descend into) and as an insert position.
#let _scan(keys, v) = {
  let i = 0
  while i < keys.len() and keys.at(i) < v { i += 1 }
  i
}

// Split index for a node about to be split. For a 3-key node
// (top-down preemptive), keys.len() == 3 → mid index 1, layout
// [k0] | k1 | [k2]. For a 4-key node (bottom-up post-overflow),
// keys.len() == 4 → mid index 2, layout [k0, k1] | k2 | [k3]. General
// rule: `keys.len() / 2` (integer division).
#let _split-mid(k) = int(k / 2)

// Split a node into a record (left, mid-key, mid-label, right). `node`
// may transiently have 3 or 4 keys. Children are partitioned to track
// the key partition — leaf nodes split cleanly with no child arrays.
#let _split(cls, node) = {
  let k = node.keys.len()
  let mid = _split-mid(k)
  let mid-key = node.keys.at(mid)
  let mid-label = node.labels.at(mid)
  let left-keys = node.keys.slice(0, mid)
  let left-labels = node.labels.slice(0, mid)
  let right-keys = node.keys.slice(mid + 1)
  let right-labels = node.labels.slice(mid + 1)
  let (left-children, right-children) = if _is-leaf(node) {
    ((), ())
  } else {
    (node.children.slice(0, mid + 1), node.children.slice(mid + 1))
  }
  (
    left: _node(cls, left-keys, left-labels, left-children),
    mid-key: mid-key,
    mid-label: mid-label,
    right: _node(cls, right-keys, right-labels, right-children),
  )
}

// Insert `(v, label)` sorted into a (keys, labels) pair. Returns the
// new pair plus the insert index.
#let _insert-sorted(keys, labels, v, label) = {
  let i = _scan(keys, v)
  (
    keys.slice(0, i) + (v,) + keys.slice(i),
    labels.slice(0, i) + (label,) + labels.slice(i),
    i,
  )
}

// Insert (mid-key, mid-label) at index `idx` of (keys, labels). The
// caller will replace children.at(idx) with `left` and insert `right`
// just after — see `_splice-children`.
#let _splice-key(keys, labels, idx, mid-key, mid-label) = (
  keys.slice(0, idx) + (mid-key,) + keys.slice(idx),
  labels.slice(0, idx) + (mid-label,) + labels.slice(idx),
)

// Replace child at `idx` with `left` and insert `right` immediately
// after.
#let _splice-children(children, idx, left, right) = (
  children.slice(0, idx) + (left, right) + children.slice(idx + 1)
)

// Merge two adjacent children with a separator key/label. The
// separator slides down from the parent and becomes the middle key
// of the merged node. Used by delete fixup.
#let _merge(cls, left, sep-key, sep-label, right) = _node(
  cls,
  left.keys + (sep-key,) + right.keys,
  left.labels + (sep-label,) + right.labels,
  left.children + right.children,
)

// --- insert: bottom-up ---------------------------------------------

// Recursive helper. Returns either ("ok", node) or
// ("split", left, mid-key, mid-label, right).
#let _bu-insert-rec(cls, node, v, label) = {
  if _is-leaf(node) {
    let (new-keys, new-labels, _) = _insert-sorted(node.keys, node.labels, v, label)
    let tmp = _node(cls, new-keys, new-labels, ())
    if new-keys.len() <= 3 {
      (kind: "ok", node: tmp)
    } else {
      let s = _split(cls, tmp)
      (
        kind: "split",
        left: s.left,
        mid-key: s.mid-key,
        mid-label: s.mid-label,
        right: s.right,
      )
    }
  } else {
    let i = _scan(node.keys, v)
    let res = _bu-insert-rec(cls, node.children.at(i), v, label)
    if res.kind == "ok" {
      let nc = node.children
      nc.at(i) = res.node
      (kind: "ok", node: _node(cls, node.keys, node.labels, nc))
    } else {
      let (nk, nl) = _splice-key(node.keys, node.labels, i, res.mid-key, res.mid-label)
      let nc = _splice-children(node.children, i, res.left, res.right)
      let tmp = _node(cls, nk, nl, nc)
      if nk.len() <= 3 {
        (kind: "ok", node: tmp)
      } else {
        let s = _split(cls, tmp)
        (
          kind: "split",
          left: s.left,
          mid-key: s.mid-key,
          mid-label: s.mid-label,
          right: s.right,
        )
      }
    }
  }
}

#let _insert-bu(cls, root, v, label) = {
  let res = _bu-insert-rec(cls, root, v, label)
  if res.kind == "ok" {
    res.node
  } else {
    _node(cls, (res.mid-key,), (res.mid-label,), (res.left, res.right))
  }
}

// --- insert: top-down ----------------------------------------------

#let _td-descend-insert(cls, node, v, label) = {
  // Precondition: `node` has < 3 keys (i.e., it was not full when its
  // parent decided to descend into it).
  if _is-leaf(node) {
    let (nk, nl, _) = _insert-sorted(node.keys, node.labels, v, label)
    _node(cls, nk, nl, ())
  } else {
    let i = _scan(node.keys, v)
    let child = node.children.at(i)
    if child.keys.len() == 3 {
      // Preemptive split before descending.
      let s = _split(cls, child)
      let (nk, nl) = _splice-key(node.keys, node.labels, i, s.mid-key, s.mid-label)
      let nc = _splice-children(node.children, i, s.left, s.right)
      let updated = _node(cls, nk, nl, nc)
      // Re-decide which side v belongs to after the split.
      let target = if v < s.mid-key { i } else if v > s.mid-key { i + 1 } else { i }
      let new-target = _td-descend-insert(cls, updated.children.at(target), v, label)
      let final-children = updated.children
      final-children.at(target) = new-target
      _node(cls, updated.keys, updated.labels, final-children)
    } else {
      let new-child = _td-descend-insert(cls, child, v, label)
      let nc = node.children
      nc.at(i) = new-child
      _node(cls, node.keys, node.labels, nc)
    }
  }
}

#let _insert-td(cls, root, v, label) = {
  if root.keys.len() == 3 {
    // Pre-split root so descent invariants hold from frame one.
    let s = _split(cls, root)
    let new-root = _node(
      cls,
      (s.mid-key,),
      (s.mid-label,),
      (s.left, s.right),
    )
    _td-descend-insert(cls, new-root, v, label)
  } else {
    _td-descend-insert(cls, root, v, label)
  }
}

// --- delete helpers -------------------------------------------------

// Walk to the right-most (rightmost-key-of-rightmost-leaf) of `node`.
// Returns (value, label).
#let _max-entry(node) = {
  let n = node
  while not _is-leaf(n) { n = n.children.last() }
  (value: n.keys.last(), label: n.labels.last())
}

// Walk to the left-most. Used by delete-bu's predecessor handling
// (top-down delete uses _max-entry instead).
#let _min-entry(node) = {
  let n = node
  while not _is-leaf(n) { n = n.children.first() }
  (value: n.keys.first(), label: n.labels.first())
}

// Rotate a key from the left sibling of children[i] into children[i].
// Used by top-down delete when the descent target is a 1-key node and
// its left sibling has ≥ 2 keys. Returns the updated parent node.
#let _rotate-from-left(cls, node, i) = {
  let parent = node
  let target = parent.children.at(i)
  let left = parent.children.at(i - 1)
  let borrowed-key = left.keys.last()
  let borrowed-label = left.labels.last()
  let borrowed-child = if _is-leaf(left) { none } else { left.children.last() }
  let new-left = _node(
    cls,
    left.keys.slice(0, left.keys.len() - 1),
    left.labels.slice(0, left.labels.len() - 1),
    if _is-leaf(left) {
      ()
    } else { left.children.slice(0, left.children.len() - 1) },
  )
  let sep-key = parent.keys.at(i - 1)
  let sep-label = parent.labels.at(i - 1)
  let new-target = _node(
    cls,
    (sep-key,) + target.keys,
    (sep-label,) + target.labels,
    if _is-leaf(target) { () } else { (borrowed-child,) + target.children },
  )
  let nk = parent.keys
  let nl = parent.labels
  nk.at(i - 1) = borrowed-key
  nl.at(i - 1) = borrowed-label
  let nc = parent.children
  nc.at(i - 1) = new-left
  nc.at(i) = new-target
  _node(cls, nk, nl, nc)
}

// Mirror of the above, rotating from the right sibling.
#let _rotate-from-right(cls, node, i) = {
  let parent = node
  let target = parent.children.at(i)
  let right = parent.children.at(i + 1)
  let borrowed-key = right.keys.first()
  let borrowed-label = right.labels.first()
  let borrowed-child = if _is-leaf(right) { none } else { right.children.first() }
  let new-right = _node(
    cls,
    right.keys.slice(1),
    right.labels.slice(1),
    if _is-leaf(right) { () } else { right.children.slice(1) },
  )
  let sep-key = parent.keys.at(i)
  let sep-label = parent.labels.at(i)
  let new-target = _node(
    cls,
    target.keys + (sep-key,),
    target.labels + (sep-label,),
    if _is-leaf(target) { () } else { target.children + (borrowed-child,) },
  )
  let nk = parent.keys
  let nl = parent.labels
  nk.at(i) = borrowed-key
  nl.at(i) = borrowed-label
  let nc = parent.children
  nc.at(i) = new-target
  nc.at(i + 1) = new-right
  _node(cls, nk, nl, nc)
}

// Merge children[i] and children[i+1] using parent.keys[i] as the
// separator. Returns the updated parent (which loses one key).
#let _merge-siblings(cls, node, i) = {
  let merged = _merge(
    cls,
    node.children.at(i),
    node.keys.at(i),
    node.labels.at(i),
    node.children.at(i + 1),
  )
  let nk = node.keys.slice(0, i) + node.keys.slice(i + 1)
  let nl = node.labels.slice(0, i) + node.labels.slice(i + 1)
  let nc = node.children.slice(0, i) + (merged,) + node.children.slice(i + 2)
  _node(cls, nk, nl, nc)
}

// --- delete: top-down ----------------------------------------------

// Ensure children[i] of `parent` has ≥ 2 keys, fixing it up by
// rotating from a sibling or merging if necessary. Returns
// (new-parent, new-child-index) since merging may shift the
// child's index by 1.
#let _td-ensure-rich(cls, parent, i) = {
  let child = parent.children.at(i)
  if child.keys.len() >= 2 {
    (parent: parent, i: i)
  } else {
    let n-children = parent.children.len()
    let has-left = i > 0
    let has-right = i < n-children - 1
    let left-rich = has-left and parent.children.at(i - 1).keys.len() >= 2
    let right-rich = has-right and parent.children.at(i + 1).keys.len() >= 2
    if left-rich {
      (parent: _rotate-from-left(cls, parent, i), i: i)
    } else if right-rich {
      (parent: _rotate-from-right(cls, parent, i), i: i)
    } else if has-left {
      // Merge with left sibling.
      let new-parent = _merge-siblings(cls, parent, i - 1)
      (parent: new-parent, i: i - 1)
    } else {
      // Merge with right sibling.
      let new-parent = _merge-siblings(cls, parent, i)
      (parent: new-parent, i: i)
    }
  }
}

#let _td-delete-rec(cls, node, v) = {
  // Precondition: `node` has ≥ 2 keys (or is the root from
  // `_delete-td`, which handles the root specially).
  let key-idx = {
    let i = 0
    while i < node.keys.len() and node.keys.at(i) < v { i += 1 }
    if i < node.keys.len() and node.keys.at(i) == v { i } else { -1 }
  }
  if _is-leaf(node) {
    if key-idx == -1 {
      panic("B24.delete: value not found: " + repr(v))
    }
    _node(
      cls,
      node.keys.slice(0, key-idx) + node.keys.slice(key-idx + 1),
      node.labels.slice(0, key-idx) + node.labels.slice(key-idx + 1),
      (),
    )
  } else if key-idx != -1 {
    // v lives in this internal node. Replace with predecessor or
    // successor, then recurse into the corresponding subtree to
    // remove the duplicate.
    let left-c = node.children.at(key-idx)
    let right-c = node.children.at(key-idx + 1)
    if left-c.keys.len() >= 2 {
      let pred = _max-entry(left-c)
      let new-left = _td-delete-rec(cls, left-c, pred.value)
      let nk = node.keys
      let nl = node.labels
      nk.at(key-idx) = pred.value
      nl.at(key-idx) = pred.label
      let nc = node.children
      nc.at(key-idx) = new-left
      _node(cls, nk, nl, nc)
    } else if right-c.keys.len() >= 2 {
      let succ = _min-entry(right-c)
      let new-right = _td-delete-rec(cls, right-c, succ.value)
      let nk = node.keys
      let nl = node.labels
      nk.at(key-idx) = succ.value
      nl.at(key-idx) = succ.label
      let nc = node.children
      nc.at(key-idx + 1) = new-right
      _node(cls, nk, nl, nc)
    } else {
      // Both flanking children are 1-key. Merge them with v in the
      // middle, then descend into the merged child to remove v.
      let merged-parent = _merge-siblings(cls, node, key-idx)
      let new-merged = _td-delete-rec(cls, merged-parent.children.at(key-idx), v)
      let nc = merged-parent.children
      nc.at(key-idx) = new-merged
      _node(cls, merged-parent.keys, merged-parent.labels, nc)
    }
  } else {
    // v not in this node — descend into the appropriate child,
    // refilling it first if it's a 1-key node.
    let i = _scan(node.keys, v)
    let fix = _td-ensure-rich(cls, node, i)
    let target = fix.parent.children.at(fix.i)
    let new-target = _td-delete-rec(cls, target, v)
    let nc = fix.parent.children
    nc.at(fix.i) = new-target
    _node(cls, fix.parent.keys, fix.parent.labels, nc)
  }
}

#let _delete-td(cls, root, v) = {
  // Root is allowed to have 1 key. If it does and both children are
  // 1-key nodes, merge them into a new root.
  let prepared = if (
    not _is-leaf(root) and root.keys.len() == 1
      and root.children.at(0).keys.len() == 1
      and root.children.at(1).keys.len() == 1
  ) {
    _merge(
      cls,
      root.children.at(0),
      root.keys.at(0),
      root.labels.at(0),
      root.children.at(1),
    )
  } else { root }
  let after = _td-delete-rec(cls, prepared, v)
  // If the root ended up empty (only possible if `prepared` was a
  // freshly merged 3-key node that subsequently merged again — rare
  // but possible), pull up the sole remaining child.
  if after.keys.len() == 0 and after.children.len() == 1 {
    after.children.at(0)
  } else if after.keys.len() == 0 and _is-leaf(after) {
    // Empty leaf — entire tree erased. Caller handles `none` at the
    // public API; we return the empty leaf and let the public
    // `delete` translate it.
    after
  } else { after }
}

// --- delete: bottom-up ---------------------------------------------

// Returns (node, underflow: bool). Underflow when the returned node
// has fewer keys than the per-node minimum (0 keys for a non-root).
#let _bu-delete-rec(cls, node, v) = {
  if _is-leaf(node) {
    let idx = {
      let i = 0
      while i < node.keys.len() and node.keys.at(i) != v { i += 1 }
      if i < node.keys.len() { i } else { -1 }
    }
    if idx == -1 {
      panic("B24.delete: value not found: " + repr(v))
    }
    let new-keys = node.keys.slice(0, idx) + node.keys.slice(idx + 1)
    let new-labels = node.labels.slice(0, idx) + node.labels.slice(idx + 1)
    let new-node = _node(cls, new-keys, new-labels, ())
    (node: new-node, underflow: new-keys.len() == 0)
  } else {
    let key-idx = {
      let i = 0
      while i < node.keys.len() and node.keys.at(i) < v { i += 1 }
      if i < node.keys.len() and node.keys.at(i) == v { i } else { -1 }
    }
    if key-idx != -1 {
      // v is in this internal node. Swap with the rightmost key of
      // the left subtree (predecessor), then bottom-up delete that
      // predecessor from the left subtree.
      let left-c = node.children.at(key-idx)
      let pred = _max-entry(left-c)
      let nk = node.keys
      let nl = node.labels
      nk.at(key-idx) = pred.value
      nl.at(key-idx) = pred.label
      let res = _bu-delete-rec(cls, left-c, pred.value)
      let nc = node.children
      nc.at(key-idx) = res.node
      let new-parent = _node(cls, nk, nl, nc)
      if res.underflow {
        _bu-fixup(cls, new-parent, key-idx)
      } else {
        (node: new-parent, underflow: false)
      }
    } else {
      // Descend into the appropriate child.
      let i = _scan(node.keys, v)
      let res = _bu-delete-rec(cls, node.children.at(i), v)
      let nc = node.children
      nc.at(i) = res.node
      let new-parent = _node(cls, node.keys, node.labels, nc)
      if res.underflow {
        _bu-fixup(cls, new-parent, i)
      } else {
        (node: new-parent, underflow: false)
      }
    }
  }
}

// Fix an underflow at children[i] of `parent`. Returns
// (new-parent, underflow: bool). The returned parent may itself be
// underflowing (only if it now has 0 keys — i.e. the merge consumed
// its last separator), in which case the caller propagates.
#let _bu-fixup(cls, parent, i) = {
  let n-children = parent.children.len()
  let has-left = i > 0
  let has-right = i < n-children - 1
  let left-rich = has-left and parent.children.at(i - 1).keys.len() >= 2
  let right-rich = has-right and parent.children.at(i + 1).keys.len() >= 2
  let new-parent = if left-rich {
    _rotate-from-left(cls, parent, i)
  } else if right-rich {
    _rotate-from-right(cls, parent, i)
  } else if has-left {
    _merge-siblings(cls, parent, i - 1)
  } else {
    _merge-siblings(cls, parent, i)
  }
  (node: new-parent, underflow: new-parent.keys.len() == 0)
}

#let _delete-bu(cls, root, v) = {
  let res = _bu-delete-rec(cls, root, v)
  // If the root ended up empty but has a single child, that child
  // becomes the new root (the tree's height decreased by one).
  if res.node.keys.len() == 0 {
    if _is-leaf(res.node) {
      res.node
    } else {
      res.node.children.at(0)
    }
  } else { res.node }
}

// ===================================================================
// Traversal helpers (per-compartment paths)
// ===================================================================
//
// Each traversal returns an array of `path + "#" + str(i)` strings,
// one per key visited. The in-order traversal threads keys with
// their flanking subtrees: child[0], key[0], child[1], key[1], …,
// child[k]. Pre- and post-order group all of a node's keys at the
// node-visit point (before or after its children, respectively).
// Level-order is BFS over nodes, emitting each node's keys in
// left-to-right order before queuing children.

#let _traverse-in(node, path) = {
  if _is-leaf(node) {
    range(node.keys.len()).map(i => path + "#" + str(i))
  } else {
    let result = ()
    for i in range(node.keys.len()) {
      result += _traverse-in(node.children.at(i), path + str(i))
      result.push(path + "#" + str(i))
    }
    result + _traverse-in(node.children.last(), path + str(node.keys.len()))
  }
}

#let _traverse-pre(node, path) = {
  let result = range(node.keys.len()).map(i => path + "#" + str(i))
  if not _is-leaf(node) {
    for (i, c) in node.children.enumerate() {
      result += _traverse-pre(c, path + str(i))
    }
  }
  result
}

#let _traverse-post(node, path) = {
  let result = ()
  if not _is-leaf(node) {
    for (i, c) in node.children.enumerate() {
      result += _traverse-post(c, path + str(i))
    }
  }
  result + range(node.keys.len()).map(i => path + "#" + str(i))
}

// ===================================================================
// Frame-building helpers (display-side)
// ===================================================================

#let _resolve-render-theme-arg(theme) = if theme == auto {
  auto
} else { tree-anim._merge-render-theme(theme) }

// All B24 renderers share `shape: "btree-node"` as the default node
// style so `draw-tree` picks the subdivided-rectangle renderer.
#let _b24-default-node-style = (shape: "btree-node")

// Pick a readable text fill for a given background color by inspecting
// the oklab L component. Same heuristic as BST traversals — keeps
// per-compartment labels legible against gradient fills.
#let _text-fill-for(bg) = {
  let l = bg.oklab().components().first()
  if l < 60% { white } else { black }
}

// Build an array of `Frame` records for one phase of an animation
// (single tree, N snapshots). Mirrors `_make-frames` in bst.typ but
// passes `_b24-default-node-style` so unstyled compartments still
// pick up the btree-node shape.
#let _make-frames(
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
        tree-anim._render-canvas(
          tree,
          snaps.at(i),
          _b24-default-node-style,
          (:),
          rt,
        )
      },
    ),
    caption: captions.at(i),
    step: steps-meta.at(i),
    alt: alts.at(i),
  ))
}

// Build a `key-styles` array of length `n` where only compartment
// `idx` carries the override dict. Used by search and traversal
// displays to highlight one compartment at a time.
#let _solo-key-style(n, idx, override) = {
  range(n).map(i => if i == idx { override } else { (:) })
}

// Multi-tree frame builder. Each spec carries its own `tree` and its
// own `build(op, rt) -> Snapshot` closure, so phases that span tree-
// shape changes (splits, merges) compose by concatenation. Mirrors
// `_make-frames-rbt-multi` in rbt.typ.
#let _make-frames-multi(specs, theme, render-theme) = {
  specs.map(s => (tree-anim.Frame.new)(
    _builder: (
      fn: (op-arg, rt-arg) => {
        let op = if theme == auto { op-arg } else { theme }
        let rt = if render-theme == auto { rt-arg } else { render-theme }
        let snap = (s.build)(op, rt)
        tree-anim._render-canvas(
          s.tree,
          snap,
          _b24-default-node-style,
          (:),
          rt,
        )
      },
    ),
    caption: s.caption,
    step: s.step,
    alt: s.alt,
  ))
}

// Shared per-visit traversal animation. `paths` is the precomputed
// per-compartment visit order (each path is "<node-path>#<key-idx>");
// `name` appears in the initial alt text. One frame per visit: the
// visited compartment gets a gradient fill sampled from the active
// op-theme's `traversal-palette`, the caption accumulates the output
// sequence, and the alt text logs the visit.
//
// step.kind values: "init" (initial frame), "visit" (per compartment).
#let _render-traversal(self, paths, name, theme, render-theme) = {
  let n = paths.len()

  let captions = (none,)
  let steps-meta = ((kind: "init"),)
  let alts = (
    "2-4 tree: "
      + (self.describe)()
      + ". About to traverse "
      + name
      + ".",
  )

  let output = ()
  let split-path(p) = {
    let parts = p.split("#")
    (parts.at(0), int(parts.at(1)))
  }

  for (i, p) in paths.enumerate() {
    let (node-path, key-idx) = split-path(p)
    let value = (self.resolve)(node-path).keys.at(key-idx)
    output.push(str(value))
    captions.push([Output: #raw("[" + output.join(", ") + "]")])
    steps-meta.push((
      kind: "visit",
      path: p,
      index: i + 1,
      value: value,
    ))
    alts.push(
      "Visited "
        + str(value)
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
    let r = tree-anim.make-renderer(
      self,
      sticky: true,
      default-node-style: _b24-default-node-style,
    )
    for (i, p) in paths.enumerate() {
      let (node-path, key-idx) = split-path(p)
      let node = (self.resolve)(node-path)
      let t = if n <= 1 { 0% } else { (i / (n - 1)) * 100% }
      let fill = g.sample(t)
      let txt-fill = _text-fill-for(fill)
      r = (r.push-with-node)(
        node-path,
        key-styles: _solo-key-style(
          node.keys.len(),
          key-idx,
          (fill: fill, text-fill: txt-fill),
        ),
      )
    }
    r.snapshots
  }

  _make-frames(
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
// Insert-display event production
// ===================================================================
//
// Each strategy emits an array of `event` records. An event carries
// the tree state at that moment plus the styling-relevant payload for
// the frame (`kind`, paths, key indices, accumulated comparison
// history, etc.). The `_insert-events-to-specs` helper renders each
// event into a `(tree, build, caption, step, alt)` spec consumable by
// `_make-frames-multi`.
//
// Event kinds (shared vocabulary):
//   "init"                      — initial tree, no highlights.
//   "compare"                   — descent comparison highlight at a
//                                 specific compartment + inline note;
//                                 carries `history` so prior
//                                 comparisons on the same tree stay
//                                 visible.
//   "td-pre-split-attention"    — top-down only: outline a node about
//                                 to be preventively split.
//   "split-done"                — post-split tree: promoted key
//                                 compartment + the two new child
//                                 edges highlighted with success-stroke.
//   "bu-overflow"               — bottom-up only: a 4-key transient
//                                 state with the leaf outlined in
//                                 danger-stroke.
//   "settled"                   — final tree: new key compartment in
//                                 success-fill + settled-stroke.

// Locate a value in the tree, returning its (node-path, key-idx) pair
// or none. Used by `_bu-insert-events` after cascading splits to find
// where the inserted value actually landed — its position depends on
// how the cascade resolved, which is hard to track imperatively
// during the split loop. Scanning the resulting tree is cheap (B24
// trees are shallow) and unambiguous.
#let _find-value(tree, v) = {
  let walk(node, path) = {
    let i = 0
    while i < node.keys.len() {
      if node.keys.at(i) == v {
        return (path: path, key-idx: i)
      }
      i += 1
    }
    if _is-leaf(node) {
      return none
    }
    let j = 0
    while j < node.children.len() {
      let r = walk(node.children.at(j), path + str(j))
      if r != none { return r }
      j += 1
    }
    none
  }
  walk(tree, "")
}

// Builds an updated "history" array reflecting that path `p` had its
// key `i` compared at value `k` against `v` with the given comparison
// text. The result is captured by value into the next event record.
#let _push-cmp(history, path, i, cmp) = (
  history + (
    (path: path, key-idx: i, cmp: cmp),
  )
)

// Re-apply accumulated descent-comparison highlights to the renderer.
// Each entry contributes a search-stroke on its compartment and an
// inline note on its node; index-wise merging keeps multiple
// compartment highlights at the same node distinct.
#let _replay-history(r, tree, history, op) = {
  let acc = r
  for h in history {
    let node = _resolve-at(tree, h.path)
    let ks = _solo-key-style(
      node.keys.len(),
      h.key-idx,
      (stroke: op.search-stroke),
    )
    acc = (acc.patch)(f => (f.style-node)(
      h.path,
      key-styles: ks,
      note: h.cmp,
    ))
  }
  acc
}

#let _td-insert-events(cls, root, v, label) = {
  let events = ((kind: "init", tree: root),)
  let current = root
  let history = ()

  // Root pre-split.
  if current.keys.len() == 3 {
    events.push((
      kind: "td-pre-split-attention",
      tree: current,
      target-path: "",
      history: history,
    ))
    let s = _split(cls, current)
    current = _node(cls, (s.mid-key,), (s.mid-label,), (s.left, s.right))
    history = ()
    events.push((
      kind: "split-done",
      tree: current,
      promoted-path: "",
      promoted-key-idx: 0,
      new-child-paths: ("0", "1"),
    ))
  }

  let node-path = ""
  while true {
    let node = _resolve-at(current, node-path)
    if _is-leaf(node) {
      let (nk, nl, idx) = _insert-sorted(node.keys, node.labels, v, label)
      let new-leaf = _node(cls, nk, nl, ())
      current = _replace-at(cls, current, node-path, new-leaf)
      events.push((
        kind: "settled",
        tree: current,
        leaf-path: node-path,
        new-key-idx: idx,
      ))
      break
    }

    let i = _scan(node.keys, v)
    let max-j = calc.min(i, node.keys.len() - 1)
    for j in range(max-j + 1) {
      let k = node.keys.at(j)
      let cmp = if v < k {
        str(v) + " < " + str(k)
      } else if v > k {
        str(v) + " > " + str(k)
      } else { str(v) + " = " + str(k) }
      history = _push-cmp(history, node-path, j, cmp)
      events.push((
        kind: "compare",
        tree: current,
        cmp-path: node-path,
        cmp-key-idx: j,
        cmp-text: cmp,
        history: history,
      ))
    }

    let child-path = node-path + str(i)
    let child = _resolve-at(current, child-path)
    if child.keys.len() == 3 {
      events.push((
        kind: "td-pre-split-attention",
        tree: current,
        target-path: child-path,
        history: history,
      ))
      let s = _split(cls, child)
      let parent = _resolve-at(current, node-path)
      let new-parent = _node(
        cls,
        parent.keys.slice(0, i) + (s.mid-key,) + parent.keys.slice(i),
        parent.labels.slice(0, i) + (s.mid-label,) + parent.labels.slice(i),
        parent.children.slice(0, i)
          + (s.left, s.right)
          + parent.children.slice(i + 1),
      )
      current = _replace-at(cls, current, node-path, new-parent)
      // Tree shape changed — the accumulated search highlights at the
      // parent reference different compartments now. Clear history.
      history = ()
      events.push((
        kind: "split-done",
        tree: current,
        promoted-path: node-path,
        promoted-key-idx: i,
        new-child-paths: (node-path + str(i), node-path + str(i + 1)),
      ))
      child-path = if v > s.mid-key {
        node-path + str(i + 1)
      } else { node-path + str(i) }
    }
    node-path = child-path
  }

  events
}

#let _bu-insert-events(cls, root, v, label) = {
  // Bottom-up: descend without splitting, insert at leaf, propagate
  // overflow by emitting overflow + split-done event pairs.
  let events = ((kind: "init", tree: root),)
  let history = ()

  // Descent: emit a "compare" event per key compared at each node.
  let node-path = ""
  let descend-stack = (node-path,)
  let node = root
  while not _is-leaf(node) {
    let i = _scan(node.keys, v)
    let max-j = calc.min(i, node.keys.len() - 1)
    for j in range(max-j + 1) {
      let k = node.keys.at(j)
      let cmp = if v < k {
        str(v) + " < " + str(k)
      } else if v > k {
        str(v) + " > " + str(k)
      } else { str(v) + " = " + str(k) }
      history = _push-cmp(history, node-path, j, cmp)
      events.push((
        kind: "compare",
        tree: root,
        cmp-path: node-path,
        cmp-key-idx: j,
        cmp-text: cmp,
        history: history,
      ))
    }
    node-path = node-path + str(i)
    descend-stack.push(node-path)
    node = node.children.at(i)
  }

  // At leaf: scan once for comparisons (so the user sees the leaf
  // comparisons before insertion).
  let leaf-path = node-path
  let leaf = node
  let i-in-leaf = _scan(leaf.keys, v)
  let max-j = calc.min(i-in-leaf, leaf.keys.len() - 1)
  for j in range(max-j + 1) {
    let k = leaf.keys.at(j)
    let cmp = if v < k {
      str(v) + " < " + str(k)
    } else if v > k {
      str(v) + " > " + str(k)
    } else { str(v) + " = " + str(k) }
    history = _push-cmp(history, leaf-path, j, cmp)
    events.push((
      kind: "compare",
      tree: root,
      cmp-path: leaf-path,
      cmp-key-idx: j,
      cmp-text: cmp,
      history: history,
    ))
  }

  // Insert v into the leaf. Tree shape changes here.
  let (nk, nl, idx) = _insert-sorted(leaf.keys, leaf.labels, v, label)
  let new-leaf = _node(cls, nk, nl, ())
  let current = _replace-at(cls, root, leaf-path, new-leaf)
  // Clear the descent history — the leaf's key positions just shifted.
  history = ()

  if nk.len() <= 3 {
    // No overflow. Final settled state.
    events.push((
      kind: "settled",
      tree: current,
      leaf-path: leaf-path,
      new-key-idx: idx,
    ))
  } else {
    // Overflow at the leaf. Emit overflow + split-done; propagate up.
    events.push((
      kind: "bu-overflow",
      tree: current,
      overflow-path: leaf-path,
      overflow-key-idx: idx,
    ))
    let s = _split(cls, new-leaf)
    let promoted-key = s.mid-key
    let promoted-label = s.mid-label
    let split-left = s.left
    let split-right = s.right

    // Propagate up the descent stack. `stack` excludes the leaf path.
    let propagate-stack = descend-stack.slice(0, descend-stack.len() - 1)
    // We'll work bottom-up: at each ancestor, insert promoted key.
    // If that causes an ancestor overflow, the loop continues.
    let current-leaf-path = leaf-path
    let pending-left = split-left
    let pending-right = split-right
    let pending-key = promoted-key
    let pending-label = promoted-label

    // Loop: pop ancestor from stack, replace child[i] with pending-left,
    // insert pending-right after, insert pending-key into ancestor's
    // keys. If overflow, set new pending-* and continue.
    let split-key-of-this-frame = current-leaf-path

    while propagate-stack.len() > 0 {
      let ancestor-path = propagate-stack.last()
      propagate-stack = propagate-stack.slice(0, propagate-stack.len() - 1)
      let ancestor = _resolve-at(current, ancestor-path)
      // Find the child index that was the previously-processed node.
      let last-digit = current-leaf-path.at(current-leaf-path.len() - 1)
      let i = int(last-digit)
      // Build new ancestor with promoted key inserted.
      let new-ancestor = _node(
        cls,
        ancestor.keys.slice(0, i) + (pending-key,) + ancestor.keys.slice(i),
        ancestor.labels.slice(0, i)
          + (pending-label,)
          + ancestor.labels.slice(i),
        ancestor.children.slice(0, i)
          + (pending-left, pending-right)
          + ancestor.children.slice(i + 1),
      )
      current = _replace-at(cls, current, ancestor-path, new-ancestor)
      // Emit split-done at the ancestor — shows promoted key arriving.
      events.push((
        kind: "split-done",
        tree: current,
        promoted-path: ancestor-path,
        promoted-key-idx: i,
        new-child-paths: (ancestor-path + str(i), ancestor-path + str(i + 1)),
      ))
      // Does the ancestor itself overflow?
      if new-ancestor.keys.len() <= 3 {
        // Done — emit a final settled event at v's actual position
        // (cascading splits may have moved it off the original leaf).
        let pos = _find-value(current, v)
        events.push((
          kind: "settled",
          tree: current,
          leaf-path: pos.path,
          new-key-idx: pos.key-idx,
        ))
        return events
      }
      // Overflow at ancestor — emit overflow + split + propagate.
      events.push((
        kind: "bu-overflow",
        tree: current,
        overflow-path: ancestor-path,
        overflow-key-idx: i,
      ))
      let s2 = _split(cls, new-ancestor)
      pending-left = s2.left
      pending-right = s2.right
      pending-key = s2.mid-key
      pending-label = s2.mid-label
      current-leaf-path = ancestor-path
    }
    // Stack exhausted — split propagated through the root.
    let new-root = _node(cls, (pending-key,), (pending-label,), (pending-left, pending-right))
    current = new-root
    events.push((
      kind: "split-done",
      tree: current,
      promoted-path: "",
      promoted-key-idx: 0,
      new-child-paths: ("0", "1"),
    ))
    let pos = _find-value(current, v)
    events.push((
      kind: "settled",
      tree: current,
      leaf-path: pos.path,
      new-key-idx: pos.key-idx,
    ))
  }

  events
}

// ===================================================================
// Delete-display event production
// ===================================================================
//
// Event vocabulary (in addition to "init", "compare", "settled" from
// the insert side):
//   "td-pre-fix-attention" — about to fix a 1-key descent target
//                            (top-down only); highlight the node.
//   "td-borrow-left"       — borrow from left sibling: separator
//                            slides down, sibling's rightmost key
//                            slides up.
//   "td-borrow-right"      — mirror of the above.
//   "td-merge"             — merge two adjacent children with their
//                            separator key.
//   "td-target"            — internal-key deletion target highlight.
//   "td-pred-swap"         — predecessor's value moves into v's slot.
//   "td-succ-swap"         — successor's value moves into v's slot.
//   "td-remove"            — v is removed from its leaf.
//   "td-root-collapse"     — root's only key was consumed; the
//                            single remaining child becomes the new
//                            root.

#let _td-delete-events(cls, root, v) = {
  let events = ((kind: "init", tree: root),)

  // Root prep: if the root has 1 key and both children are 1-key,
  // merge them so descent invariants hold from frame one.
  let current = if (
    not _is-leaf(root) and root.keys.len() == 1
      and root.children.at(0).keys.len() == 1
      and root.children.at(1).keys.len() == 1
  ) {
    let merged = _merge(
      cls,
      root.children.at(0),
      root.keys.at(0),
      root.labels.at(0),
      root.children.at(1),
    )
    events.push((
      kind: "td-merge",
      tree: merged,
      merge-path: "",
      merge-child-idx: none,
    ))
    merged
  } else { root }

  let path = ""
  let history = ()
  let target = v
  let done = false

  while not done {
    let node = _resolve-at(current, path)
    let key-idx = -1

    // Scan and emit compare events until we either find v or
    // determine which child to descend into.
    let i = 0
    while i < node.keys.len() and node.keys.at(i) < target {
      let k = node.keys.at(i)
      let cmp = str(target) + " > " + str(k)
      history = _push-cmp(history, path, i, cmp)
      events.push((
        kind: "compare",
        tree: current,
        cmp-path: path,
        cmp-key-idx: i,
        cmp-text: cmp,
        history: history,
      ))
      i += 1
    }
    if i < node.keys.len() {
      let k = node.keys.at(i)
      let cmp = if target == k {
        str(target) + " = " + str(k)
      } else { str(target) + " < " + str(k) }
      history = _push-cmp(history, path, i, cmp)
      events.push((
        kind: "compare",
        tree: current,
        cmp-path: path,
        cmp-key-idx: i,
        cmp-text: cmp,
        history: history,
      ))
      if target == k { key-idx = i }
    }

    if key-idx != -1 {
      // Found v at this node.
      if _is-leaf(node) {
        let new-leaf = _node(
          cls,
          node.keys.slice(0, key-idx) + node.keys.slice(key-idx + 1),
          node.labels.slice(0, key-idx) + node.labels.slice(key-idx + 1),
          (),
        )
        current = _replace-at(cls, current, path, new-leaf)
        events.push((
          kind: "td-remove",
          tree: current,
          leaf-path: path,
          removed-value: target,
        ))
        done = true
      } else {
        // Internal: predecessor swap / successor swap / merge.
        let left-c = node.children.at(key-idx)
        let right-c = node.children.at(key-idx + 1)
        if left-c.keys.len() >= 2 {
          let pred = _max-entry(left-c)
          events.push((
            kind: "td-target",
            tree: current,
            target-path: path,
            target-key-idx: key-idx,
            history: history,
          ))
          let nk = node.keys
          let nl = node.labels
          nk.at(key-idx) = pred.value
          nl.at(key-idx) = pred.label
          let new-node = _node(cls, nk, nl, node.children)
          current = _replace-at(cls, current, path, new-node)
          history = ()
          events.push((
            kind: "td-pred-swap",
            tree: current,
            path: path,
            key-idx: key-idx,
            new-key: pred.value,
          ))
          target = pred.value
          path = path + str(key-idx)
        } else if right-c.keys.len() >= 2 {
          let succ = _min-entry(right-c)
          events.push((
            kind: "td-target",
            tree: current,
            target-path: path,
            target-key-idx: key-idx,
            history: history,
          ))
          let nk = node.keys
          let nl = node.labels
          nk.at(key-idx) = succ.value
          nl.at(key-idx) = succ.label
          let new-node = _node(cls, nk, nl, node.children)
          current = _replace-at(cls, current, path, new-node)
          history = ()
          events.push((
            kind: "td-succ-swap",
            tree: current,
            path: path,
            key-idx: key-idx,
            new-key: succ.value,
          ))
          target = succ.value
          path = path + str(key-idx + 1)
        } else {
          // Both flanks 1-key. Merge them with v as separator and
          // descend into the merged child.
          let merged-parent = _merge-siblings(cls, node, key-idx)
          current = _replace-at(cls, current, path, merged-parent)
          history = ()
          events.push((
            kind: "td-merge",
            tree: current,
            merge-path: path,
            merge-child-idx: key-idx,
          ))
          path = path + str(key-idx)
        }
      }
    } else {
      // Descend into child[i]. Pre-fix if child is 1-key.
      let descend-i = _scan(node.keys, target)
      let child-path = path + str(descend-i)
      let child = node.children.at(descend-i)
      if child.keys.len() < 2 {
        let n-children = node.children.len()
        let has-left = descend-i > 0
        let has-right = descend-i < n-children - 1
        let left-rich = (
          has-left and node.children.at(descend-i - 1).keys.len() >= 2
        )
        let right-rich = (
          has-right and node.children.at(descend-i + 1).keys.len() >= 2
        )
        events.push((
          kind: "td-pre-fix-attention",
          tree: current,
          target-path: child-path,
          history: history,
        ))
        if left-rich {
          let new-parent = _rotate-from-left(cls, node, descend-i)
          current = _replace-at(cls, current, path, new-parent)
          events.push((
            kind: "td-borrow-left",
            tree: current,
            target-path: child-path,
            sibling-path: path + str(descend-i - 1),
            parent-path: path,
            parent-key-idx: descend-i - 1,
          ))
          history = ()
          path = child-path
        } else if right-rich {
          let new-parent = _rotate-from-right(cls, node, descend-i)
          current = _replace-at(cls, current, path, new-parent)
          events.push((
            kind: "td-borrow-right",
            tree: current,
            target-path: child-path,
            sibling-path: path + str(descend-i + 1),
            parent-path: path,
            parent-key-idx: descend-i,
          ))
          history = ()
          path = child-path
        } else if has-left {
          let new-parent = _merge-siblings(cls, node, descend-i - 1)
          current = _replace-at(cls, current, path, new-parent)
          events.push((
            kind: "td-merge",
            tree: current,
            merge-path: path,
            merge-child-idx: descend-i - 1,
          ))
          history = ()
          path = path + str(descend-i - 1)
        } else {
          let new-parent = _merge-siblings(cls, node, descend-i)
          current = _replace-at(cls, current, path, new-parent)
          events.push((
            kind: "td-merge",
            tree: current,
            merge-path: path,
            merge-child-idx: descend-i,
          ))
          history = ()
          path = path + str(descend-i)
        }
      } else {
        path = child-path
      }
    }
  }

  // Post-delete root collapse.
  if current.keys.len() == 0 and (
    not _is-leaf(current) and current.children.len() == 1
  ) {
    current = current.children.at(0)
    events.push((kind: "td-root-collapse", tree: current))
  }

  events
}

#let _bu-delete-events(cls, root, v) = {
  // Bottom-up: descend to v's location, swap with predecessor if v
  // is internal, then remove from the leaf. Propagate underflow up.
  let events = ((kind: "init", tree: root),)
  let history = ()
  let current = root

  // Descend, recording compare events. Build the descent stack so
  // underflow propagation can walk back up.
  let path = ""
  let descend-stack = (path,)
  let key-idx = -1
  while true {
    let node = _resolve-at(current, path)
    let i = 0
    while i < node.keys.len() and node.keys.at(i) < v {
      let k = node.keys.at(i)
      let cmp = str(v) + " > " + str(k)
      history = _push-cmp(history, path, i, cmp)
      events.push((
        kind: "compare",
        tree: current,
        cmp-path: path,
        cmp-key-idx: i,
        cmp-text: cmp,
        history: history,
      ))
      i += 1
    }
    if i < node.keys.len() {
      let k = node.keys.at(i)
      let cmp = if v == k {
        str(v) + " = " + str(k)
      } else { str(v) + " < " + str(k) }
      history = _push-cmp(history, path, i, cmp)
      events.push((
        kind: "compare",
        tree: current,
        cmp-path: path,
        cmp-key-idx: i,
        cmp-text: cmp,
        history: history,
      ))
      if v == k {
        key-idx = i
        break
      }
    }
    if _is-leaf(node) {
      panic("B24.delete-display: value not found: " + repr(v))
    }
    path = path + str(i)
    descend-stack.push(path)
  }

  // At this point, `path` is v's node and `key-idx` is its position.
  // If internal, swap with predecessor (rightmost-of-left-subtree).
  let target-leaf-path = path
  if not _is-leaf(_resolve-at(current, path)) {
    let v-node = _resolve-at(current, path)
    events.push((
      kind: "td-target",
      tree: current,
      target-path: path,
      target-key-idx: key-idx,
      history: history,
    ))
    // Walk to rightmost leaf of left child.
    let walk-path = path + str(key-idx)
    while not _is-leaf(_resolve-at(current, walk-path)) {
      let n = _resolve-at(current, walk-path)
      walk-path = walk-path + str(n.keys.len())
    }
    let pred-leaf = _resolve-at(current, walk-path)
    let pred-value = pred-leaf.keys.last()
    let pred-label = pred-leaf.labels.last()
    // Swap value into v's slot.
    let nk = v-node.keys
    let nl = v-node.labels
    nk.at(key-idx) = pred-value
    nl.at(key-idx) = pred-label
    let new-v-node = _node(cls, nk, nl, v-node.children)
    current = _replace-at(cls, current, path, new-v-node)
    history = ()
    events.push((
      kind: "td-pred-swap",
      tree: current,
      path: path,
      key-idx: key-idx,
      new-key: pred-value,
    ))
    target-leaf-path = walk-path
    // Update descend-stack to point all the way down to the leaf.
    let p = path
    let n = _resolve-at(current, p)
    p = p + str(key-idx)
    descend-stack.push(p)
    while p != walk-path {
      let nn = _resolve-at(current, p)
      p = p + str(nn.keys.len())
      descend-stack.push(p)
    }
  }

  // Remove v (or predecessor value) from the leaf.
  let leaf = _resolve-at(current, target-leaf-path)
  // Find the key in the leaf to remove. If we did pred swap, it's
  // the leaf's rightmost key (which we read above). If v was already
  // in the leaf, it's at the recorded key-idx.
  let remove-idx = leaf.keys.len() - 1  // rightmost for pred case
  if target-leaf-path == path {
    // v was directly in the leaf — use the original key-idx.
    remove-idx = key-idx
  }
  let new-leaf = _node(
    cls,
    leaf.keys.slice(0, remove-idx) + leaf.keys.slice(remove-idx + 1),
    leaf.labels.slice(0, remove-idx) + leaf.labels.slice(remove-idx + 1),
    (),
  )
  current = _replace-at(cls, current, target-leaf-path, new-leaf)
  events.push((
    kind: "td-remove",
    tree: current,
    leaf-path: target-leaf-path,
    removed-value: v,
  ))

  // If the leaf is now empty AND it's the root, the tree is empty.
  if target-leaf-path == "" and new-leaf.keys.len() == 0 {
    return events
  }

  // Propagate underflow upward.
  if new-leaf.keys.len() == 0 {
    let underflow-path = target-leaf-path
    let stack = descend-stack.slice(0, descend-stack.len() - 1)
    while stack.len() > 0 {
      let parent-path = stack.last()
      stack = stack.slice(0, stack.len() - 1)
      let parent = _resolve-at(current, parent-path)
      let i = int(underflow-path.at(underflow-path.len() - 1))
      let n-children = parent.children.len()
      let has-left = i > 0
      let has-right = i < n-children - 1
      let left-rich = (
        has-left and parent.children.at(i - 1).keys.len() >= 2
      )
      let right-rich = (
        has-right and parent.children.at(i + 1).keys.len() >= 2
      )
      events.push((
        kind: "td-pre-fix-attention",
        tree: current,
        target-path: underflow-path,
        history: history,
      ))
      let fixed-parent = none
      let new-kind = ""
      if left-rich {
        fixed-parent = _rotate-from-left(cls, parent, i)
        new-kind = "td-borrow-left"
      } else if right-rich {
        fixed-parent = _rotate-from-right(cls, parent, i)
        new-kind = "td-borrow-right"
      } else if has-left {
        fixed-parent = _merge-siblings(cls, parent, i - 1)
        new-kind = "td-merge"
      } else {
        fixed-parent = _merge-siblings(cls, parent, i)
        new-kind = "td-merge"
      }
      current = _replace-at(cls, current, parent-path, fixed-parent)
      if new-kind == "td-merge" {
        let merge-i = if has-left and not left-rich and not right-rich {
          i - 1
        } else { i }
        events.push((
          kind: "td-merge",
          tree: current,
          merge-path: parent-path,
          merge-child-idx: merge-i,
        ))
      } else {
        events.push((
          kind: new-kind,
          tree: current,
          target-path: underflow-path,
          sibling-path: parent-path + (
            if new-kind == "td-borrow-left" { str(i - 1) } else { str(i + 1) }
          ),
          parent-path: parent-path,
          parent-key-idx: (
            if new-kind == "td-borrow-left" { i - 1 } else { i }
          ),
        ))
      }
      // If we rotated (borrow), the underflow is resolved.
      if left-rich or right-rich { break }
      // We merged. Check whether the parent now underflows.
      if fixed-parent.keys.len() == 0 {
        // Parent itself underflows; propagate.
        underflow-path = parent-path
        continue
      } else {
        // Parent still has keys; underflow resolved.
        break
      }
    }
    // Root collapse if root ended up with 0 keys + 1 child.
    if current.keys.len() == 0 and (
      not _is-leaf(current) and current.children.len() == 1
    ) {
      current = current.children.at(0)
      events.push((kind: "td-root-collapse", tree: current))
    }
  }

  events
}

// Convert events to specs. The `build` closure dispatches on event
// kind to apply the right styling. Captured event payloads are copied
// at closure-creation time (Typst value semantics), so each frame
// renders the snapshot for its own event regardless of later events.
#let _insert-events-to-specs(events, v) = events.map(ev => {
  let caption = none
  let alt = ""
  let step = (kind: ev.kind)

  if ev.kind == "init" {
    caption = none
    alt = (
      "2-4 tree: "
        + (ev.tree.describe)()
        + ". About to insert "
        + str(v)
        + "."
    )
  } else if ev.kind == "compare" {
    caption = ev.cmp-text
    alt = "Comparing " + ev.cmp-text + " at the current node."
    step.insert("path", ev.cmp-path)
    step.insert("key-idx", ev.cmp-key-idx)
  } else if ev.kind == "td-pre-split-attention" {
    caption = [Full node — split first]
    alt = "Node at path " + ev.target-path + " is full (3 keys); pre-split before descending."
    step.insert("target-path", ev.target-path)
  } else if ev.kind == "split-done" {
    caption = [Promoted key]
    alt = "Split complete; the promoted key now sits in its parent."
    step.insert("promoted-path", ev.promoted-path)
    step.insert("promoted-key-idx", ev.promoted-key-idx)
  } else if ev.kind == "bu-overflow" {
    caption = [Overflow]
    alt = "Leaf overflows with 4 keys — split before continuing."
    step.insert("overflow-path", ev.overflow-path)
  } else if ev.kind == "settled" {
    caption = [Inserted #v]
    alt = "Inserted " + str(v) + "."
    step.insert("leaf-path", ev.leaf-path)
    step.insert("new-key-idx", ev.new-key-idx)
  }

  let build = (op, _rt) => {
    let r = tree-anim.make-renderer(
      ev.tree,
      sticky: false,
      default-node-style: _b24-default-node-style,
    )
    if ev.kind == "init" {
      // No styling.
    } else if ev.kind == "compare" {
      r = _replay-history(r, ev.tree, ev.history, op)
    } else if ev.kind == "td-pre-split-attention" {
      r = _replay-history(r, ev.tree, ev.history, op)
      r = (r.patch)(f => (f.style-node)(
        ev.target-path,
        stroke: op.attention-stroke,
      ))
    } else if ev.kind == "split-done" {
      let n = _resolve-at(ev.tree, ev.promoted-path)
      let ks = _solo-key-style(
        n.keys.len(),
        ev.promoted-key-idx,
        (stroke: op.success-stroke),
      )
      r = (r.patch)(f => (f.style-node)(ev.promoted-path, key-styles: ks))
      for p in ev.new-child-paths {
        r = (r.patch)(f => (f.style-edge)(p, stroke: op.success-stroke))
      }
    } else if ev.kind == "bu-overflow" {
      let n = _resolve-at(ev.tree, ev.overflow-path)
      let ks = _solo-key-style(
        n.keys.len(),
        ev.overflow-key-idx,
        (stroke: op.danger-stroke, fill: op.success-fill),
      )
      r = (r.patch)(f => (f.style-node)(
        ev.overflow-path,
        key-styles: ks,
        stroke: op.danger-stroke,
      ))
    } else if ev.kind == "settled" {
      let n = _resolve-at(ev.tree, ev.leaf-path)
      let ks = _solo-key-style(
        n.keys.len(),
        ev.new-key-idx,
        (fill: op.success-fill, stroke: op.settled-stroke),
      )
      r = (r.patch)(f => (f.style-node)(ev.leaf-path, key-styles: ks))
    }
    r.snapshots.first()
  }

  (tree: ev.tree, build: build, caption: caption, step: step, alt: alt)
})

#let _delete-events-to-specs(events, v) = events.map(ev => {
  let caption = none
  let alt = ""
  let step = (kind: ev.kind)

  if ev.kind == "init" {
    alt = (
      "2-4 tree: "
        + (ev.tree.describe)()
        + ". About to delete "
        + str(v)
        + "."
    )
  } else if ev.kind == "compare" {
    caption = ev.cmp-text
    alt = "Comparing " + ev.cmp-text + " at the current node."
    step.insert("path", ev.cmp-path)
    step.insert("key-idx", ev.cmp-key-idx)
  } else if ev.kind == "td-pre-fix-attention" {
    caption = [Under-full — fix before descending]
    alt = "Descent target has only 1 key; borrow or merge before descending."
    step.insert("target-path", ev.target-path)
  } else if ev.kind == "td-borrow-left" {
    caption = [Borrow from left]
    alt = (
      "Borrow: separator slides down into the target, left sibling's rightmost key slides up."
    )
    step.insert("target-path", ev.target-path)
  } else if ev.kind == "td-borrow-right" {
    caption = [Borrow from right]
    alt = (
      "Borrow: separator slides down into the target, right sibling's leftmost key slides up."
    )
    step.insert("target-path", ev.target-path)
  } else if ev.kind == "td-merge" {
    caption = [Merge]
    alt = "Merge two children with their separator key."
    step.insert("merge-path", ev.merge-path)
  } else if ev.kind == "td-target" {
    caption = [Target found]
    alt = "Found the value to delete; will swap with predecessor."
    step.insert("target-path", ev.target-path)
    step.insert("target-key-idx", ev.target-key-idx)
  } else if ev.kind == "td-pred-swap" {
    caption = [Swap with predecessor]
    alt = "Replaced the target's value with its predecessor; will now delete the predecessor from the leaf."
    step.insert("path", ev.path)
    step.insert("key-idx", ev.key-idx)
  } else if ev.kind == "td-succ-swap" {
    caption = [Swap with successor]
    alt = "Replaced the target's value with its successor; will now delete the successor from the leaf."
    step.insert("path", ev.path)
    step.insert("key-idx", ev.key-idx)
  } else if ev.kind == "td-remove" {
    caption = [Removed #v]
    alt = "Removed " + str(v) + " from the leaf."
    step.insert("leaf-path", ev.leaf-path)
  } else if ev.kind == "td-root-collapse" {
    caption = [Root collapsed]
    alt = "Root's only key was consumed by merging; the single remaining child becomes the new root."
  }

  let build = (op, _rt) => {
    let r = tree-anim.make-renderer(
      ev.tree,
      sticky: false,
      default-node-style: _b24-default-node-style,
    )
    if ev.kind == "init" {
      // No styling.
    } else if ev.kind == "compare" {
      r = _replay-history(r, ev.tree, ev.history, op)
    } else if ev.kind == "td-pre-fix-attention" {
      r = _replay-history(r, ev.tree, ev.history, op)
      r = (r.patch)(f => (f.style-node)(
        ev.target-path,
        stroke: op.attention-stroke,
      ))
    } else if ev.kind == "td-borrow-left" or ev.kind == "td-borrow-right" {
      // Highlight the parent's affected key + the target node's
      // new boundary key.
      let parent = _resolve-at(ev.tree, ev.parent-path)
      let pks = _solo-key-style(
        parent.keys.len(),
        ev.parent-key-idx,
        (stroke: op.success-stroke),
      )
      r = (r.patch)(f => (f.style-node)(
        ev.parent-path,
        key-styles: pks,
      ))
      r = (r.patch)(f => (f.style-edge)(
        ev.target-path,
        stroke: op.success-stroke,
      ))
      r = (r.patch)(f => (f.style-edge)(
        ev.sibling-path,
        stroke: op.success-stroke,
      ))
    } else if ev.kind == "td-merge" {
      // Root-prep merge has no specific child edge to highlight;
      // outline the new merged root instead.
      if ev.merge-child-idx == none {
        r = (r.patch)(f => (f.style-node)(
          ev.merge-path,
          stroke: op.success-stroke,
        ))
      } else {
        r = (r.patch)(f => (f.style-edge)(
          ev.merge-path + str(ev.merge-child-idx),
          stroke: op.success-stroke,
        ))
      }
    } else if ev.kind == "td-target" {
      r = _replay-history(r, ev.tree, ev.history, op)
      let n = _resolve-at(ev.tree, ev.target-path)
      let ks = _solo-key-style(
        n.keys.len(),
        ev.target-key-idx,
        (stroke: op.attention-stroke),
      )
      r = (r.patch)(f => (f.style-node)(ev.target-path, key-styles: ks))
    } else if ev.kind == "td-pred-swap" or ev.kind == "td-succ-swap" {
      let n = _resolve-at(ev.tree, ev.path)
      let ks = _solo-key-style(
        n.keys.len(),
        ev.key-idx,
        (fill: op.success-fill, stroke: op.success-stroke),
      )
      r = (r.patch)(f => (f.style-node)(ev.path, key-styles: ks))
    } else if ev.kind == "td-remove" {
      // No specific compartment to highlight (it's gone). Outline
      // the resulting node with success-stroke to signal completion.
      r = (r.patch)(f => (f.style-node)(
        ev.leaf-path,
        stroke: op.settled-stroke,
      ))
    } else if ev.kind == "td-root-collapse" {
      r = (r.patch)(f => (f.style-node)("", stroke: op.settled-stroke))
    }
    r.snapshots.first()
  }

  (tree: ev.tree, build: build, caption: caption, step: step, alt: alt)
})

// ===================================================================
// Class definition
// ===================================================================

#let B24 = class(
  name: "B24",
  fields: (
    keys: Array(..Int),
    labels: Array(..Any),
    children: Array(..Any),
  ),
  methods: (
    resolve: (self, path) => _resolve-at(self, path),

    contains: (self, v) => {
      let walk(node) = {
        let i = _scan(node.keys, v)
        if i < node.keys.len() and node.keys.at(i) == v {
          true
        } else if _is-leaf(node) {
          false
        } else {
          walk(node.children.at(i))
        }
      }
      walk(self)
    },

    by-value: (self, v) => {
      // Returns the per-compartment path "<node-path>#<key-idx>" or
      // panics if v isn't in the tree.
      let walk(node, path) = {
        let i = _scan(node.keys, v)
        if i < node.keys.len() and node.keys.at(i) == v {
          path + "#" + str(i)
        } else if _is-leaf(node) {
          panic("B24.by-value: value not found: " + repr(v))
        } else {
          walk(node.children.at(i), path + str(i))
        }
      }
      walk(self, "")
    },

    path-to: (self, v) => {
      // Returns the sequence of comparison records made along the
      // search path. Each record:
      //   (path, key-idx, key-value, cmp, found)
      // where `path` is the node-path being examined, `key-idx` is
      // the compartment compared, `key-value` is the key at that
      // compartment, `cmp` is the comparison string, and `found` is
      // true if v == key-value.
      let walk(node, path) = {
        let scan(i) = {
          if i == node.keys.len() {
            // v exceeds all keys at this node; descend rightmost.
            if _is-leaf(node) {
              panic("B24.path-to: value not found: " + repr(v))
            }
            walk(node.children.at(i), path + str(i))
          } else {
            let k = node.keys.at(i)
            let cmp = if v == k {
              str(v) + " = " + str(k)
            } else if v < k {
              str(v) + " < " + str(k)
            } else {
              str(v) + " > " + str(k)
            }
            let entry = (
              path: path,
              key-idx: i,
              key-value: k,
              cmp: cmp,
              found: v == k,
            )
            if v == k {
              (entry,)
            } else if v < k {
              if _is-leaf(node) {
                panic("B24.path-to: value not found: " + repr(v))
              }
              (entry,) + walk(node.children.at(i), path + str(i))
            } else {
              (entry,) + scan(i + 1)
            }
          }
        }
        scan(0)
      }
      walk(self, "")
    },

    insert: (self, v, label: auto, strategy: "top-down") => {
      let cls = self.meta.cls
      if strategy == "top-down" {
        _insert-td(cls, self, v, label)
      } else if strategy == "bottom-up" {
        _insert-bu(cls, self, v, label)
      } else {
        panic(
          "B24.insert: unknown strategy "
            + repr(strategy)
            + "; supported: \"top-down\", \"bottom-up\".",
        )
      }
    },

    // Plain `insert(..)` overload-free helper for the common int-only
    // case. Iterates with the default strategy.
    insert-many: (self, ..vals) => {
      let tree = self
      for v in vals.pos() {
        tree = (tree.insert)(v)
      }
      tree
    },

    delete: (self, v, strategy: "top-down") => {
      let cls = self.meta.cls
      let result = if strategy == "top-down" {
        _delete-td(cls, self, v)
      } else if strategy == "bottom-up" {
        _delete-bu(cls, self, v)
      } else {
        panic(
          "B24.delete: unknown strategy "
            + repr(strategy)
            + "; supported: \"top-down\", \"bottom-up\".",
        )
      }
      // Empty leaf at the root means the entire tree has been emptied.
      // For consistency with BST.delete (which can return `none` from
      // a 1-node tree), we surface that as `none` at the public API.
      if result.keys.len() == 0 and _is-leaf(result) {
        none
      } else { result }
    },

    describe: self => {
      let key-str = self.keys.map(str).join(", ")
      if _is-leaf(self) {
        "[" + key-str + "]"
      } else {
        let cs = self.children.map(c => (c.describe)()).join(", ")
        "[" + key-str + "] (children: " + cs + ")"
      }
    },

    // Returns `none` if all invariants hold, otherwise an explanatory
    // string. Used in tests; safe to call on user-built trees too.
    check-invariants: self => {
      let walk(node, is-root) = {
        let k = node.keys.len()
        if k < 1 or k > 3 {
          return (
            err: "node has "
              + str(k)
              + " keys (must be 1..3)",
            depth: none,
          )
        }
        for i in range(k - 1) {
          if node.keys.at(i) >= node.keys.at(i + 1) {
            return (
              err: "keys not strictly increasing: "
                + repr(node.keys),
              depth: none,
            )
          }
        }
        if _is-leaf(node) {
          return (err: none, depth: 1)
        }
        if node.children.len() != k + 1 {
          return (
            err: "child count "
              + str(node.children.len())
              + " ≠ keys + 1 ("
              + str(k + 1)
              + ")",
            depth: none,
          )
        }
        let leaf-depth = none
        for c in node.children {
          let r = walk(c, false)
          if r.err != none { return r }
          if leaf-depth == none {
            leaf-depth = r.depth
          } else if r.depth != leaf-depth {
            return (
              err: "unequal leaf depths under node "
                + repr(node.keys),
              depth: none,
            )
          }
        }
        (err: none, depth: leaf-depth + 1)
      }
      walk(self, true).err
    },

    in-order: self => _traverse-in(self, ""),
    pre-order: self => _traverse-pre(self, ""),
    post-order: self => _traverse-post(self, ""),
    level-order: self => {
      let result = ()
      let queue = ("",)
      while queue.len() > 0 {
        let path = queue.first()
        queue = queue.slice(1)
        let n = _resolve-at(self, path)
        for i in range(n.keys.len()) {
          result.push(path + "#" + str(i))
        }
        if not _is-leaf(n) {
          for j in range(n.children.len()) {
            queue.push(path + str(j))
          }
        }
      }
      result
    },

    // --- display methods ---------------------------------------------

    display: (self, theme: auto, render-theme: auto) => {
      // One-frame Frame array — the static tree. `step` is none.
      let captions = (none,)
      let steps-meta = (none,)
      let alts = ("2-4 tree: " + (self.describe)() + ".",)
      let build-snapshots = (_op, _rt) => (tree-anim.blank-snapshot(),)
      _make-frames(
        self,
        build-snapshots,
        captions,
        steps-meta,
        alts,
        _resolve-op-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
      )
    },

    search-display: (self, v, theme: auto, render-theme: auto) => {
      // One frame per comparison made along the search path. The
      // first frame is the unmodified tree (kind: "init"). Each
      // subsequent frame highlights the compared compartment with
      // `op.search-stroke` (key-styles) and attaches the comparison
      // string as an inline note. `step` is:
      //   (kind: "init")
      //   (kind: "compare", path, key-idx, cmp, found: bool)
      //
      // Search misses are rendered as well — the final comparison is
      // the last key checked at the leaf before the search would
      // descend off the tree. `found` stays false; the alt text and
      // caption explain the miss.
      let walk(node, path) = {
        let scan(i) = {
          if i == node.keys.len() {
            if _is-leaf(node) {
              // Search would descend off the rightmost child of a
              // leaf — emit a terminal "v > kₙ₋₁" comparison.
              let k = node.keys.last()
              ((
                path: path,
                key-idx: node.keys.len() - 1,
                key-value: k,
                cmp: str(v) + " > " + str(k),
                found: false,
              ),)
            } else { walk(node.children.at(i), path + str(i)) }
          } else {
            let k = node.keys.at(i)
            let cmp = if v == k {
              str(v) + " = " + str(k)
            } else if v < k {
              str(v) + " < " + str(k)
            } else {
              str(v) + " > " + str(k)
            }
            let entry = (
              path: path,
              key-idx: i,
              key-value: k,
              cmp: cmp,
              found: v == k,
            )
            if v == k {
              (entry,)
            } else if v < k {
              if _is-leaf(node) {
                (entry,)
              } else { (entry,) + walk(node.children.at(i), path + str(i)) }
            } else {
              (entry,) + scan(i + 1)
            }
          }
        }
        scan(0)
      }
      let cmps = walk(self, "")
      let captions = (none,)
      let steps-meta = ((kind: "init"),)
      let alts = (
        "2-4 tree: "
          + (self.describe)()
          + ". About to search for "
          + str(v)
          + ".",
      )
      for (i, c) in cmps.enumerate() {
        captions.push(c.cmp)
        steps-meta.push((
          kind: "compare",
          path: c.path,
          key-idx: c.key-idx,
          cmp: c.cmp,
          found: c.found,
        ))
        let is-last = i == cmps.len() - 1
        let alt = if c.found {
          "Match found at key " + str(c.key-value) + "."
        } else if is-last {
          (
            "Comparing "
              + c.cmp
              + " at key "
              + str(c.key-value)
              + "; search ends here, "
              + str(v)
              + " is not in the tree."
          )
        } else {
          (
            "Comparing "
              + c.cmp
              + " at key "
              + str(c.key-value)
              + "; continuing search."
          )
        }
        alts.push(alt)
      }

      let build-snapshots = (op, _rt) => {
        let r = tree-anim.make-renderer(
          self,
          sticky: true,
          default-node-style: _b24-default-node-style,
        )
        for c in cmps {
          let node = (self.resolve)(c.path)
          r = (r.push-with-node)(
            c.path,
            key-styles: _solo-key-style(
              node.keys.len(),
              c.key-idx,
              (stroke: op.search-stroke),
            ),
            note: c.cmp,
          )
        }
        r.snapshots
      }

      _make-frames(
        self,
        build-snapshots,
        captions,
        steps-meta,
        alts,
        _resolve-op-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
      )
    },

    delete-display: (
      self,
      v,
      strategy: "top-down",
      theme: auto,
      render-theme: auto,
    ) => {
      let cls = self.meta.cls
      let events = if strategy == "top-down" {
        _td-delete-events(cls, self, v)
      } else if strategy == "bottom-up" {
        _bu-delete-events(cls, self, v)
      } else {
        panic(
          "B24.delete-display: unknown strategy "
            + repr(strategy)
            + "; supported: \"top-down\", \"bottom-up\".",
        )
      }
      let specs = _delete-events-to-specs(events, v)
      _make-frames-multi(
        specs,
        _resolve-op-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
      )
    },

    insert-display: (
      self,
      v,
      label: auto,
      strategy: "top-down",
      theme: auto,
      render-theme: auto,
    ) => {
      let cls = self.meta.cls
      let events = if strategy == "top-down" {
        _td-insert-events(cls, self, v, label)
      } else if strategy == "bottom-up" {
        _bu-insert-events(cls, self, v, label)
      } else {
        panic(
          "B24.insert-display: unknown strategy "
            + repr(strategy)
            + "; supported: \"top-down\", \"bottom-up\".",
        )
      }
      let specs = _insert-events-to-specs(events, v)
      _make-frames-multi(
        specs,
        _resolve-op-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
      )
    },

    in-order-display: (self, theme: auto, render-theme: auto) => _render-traversal(
      self,
      (self.in-order)(),
      "in-order",
      _resolve-op-theme-arg(theme),
      _resolve-render-theme-arg(render-theme),
    ),
    pre-order-display: (self, theme: auto, render-theme: auto) => _render-traversal(
      self,
      (self.pre-order)(),
      "pre-order",
      _resolve-op-theme-arg(theme),
      _resolve-render-theme-arg(render-theme),
    ),
    post-order-display: (self, theme: auto, render-theme: auto) => _render-traversal(
      self,
      (self.post-order)(),
      "post-order",
      _resolve-op-theme-arg(theme),
      _resolve-render-theme-arg(render-theme),
    ),
    level-order-display: (self, theme: auto, render-theme: auto) => _render-traversal(
      self,
      (self.level-order)(),
      "level-order",
      _resolve-op-theme-arg(theme),
      _resolve-render-theme-arg(render-theme),
    ),
  ),
)

// ===================================================================
// Convenience constructor
// ===================================================================

/// Build a 2-3-4 tree from a list of values. The first value seeds
/// the root; subsequent values are inserted left-to-right using the
/// default (#raw("\"top-down\"")) strategy. Each positional value may
/// be either a bare integer or a #raw("(value, label)") 2-tuple.
///
/// ```typc
/// // root 4, then insert 1, 7, 3, 6, 8
/// let t = b24(4, 1, 7, 3, 6, 8)
///
/// // mixed labels
/// let t = b24((4, [FOUR]), 1, 7, (6, [SIX]))
/// ```
///
/// -> dictionary
#let b24(
  /// Positional values. Each is either a bare value or a
  /// #raw("(value, label)") 2-tuple. At least one is required (the
  /// root).
  ..vals,
) = {
  let xs = vals.pos()
  assert(
    xs.len() > 0,
    message: "b24: at least one value required (the root)",
  )
  let parse(x) = if type(x) == array {
    assert(
      x.len() == 2,
      message: "b24: expected (value, label) 2-tuple, got " + repr(x),
    )
    (value: x.at(0), label: x.at(1))
  } else {
    (value: x, label: auto)
  }
  let head = parse(xs.first())
  let tree = (B24.new)(
    keys: (head.value,),
    labels: (head.label,),
    children: (),
  )
  for x in xs.slice(1) {
    let p = parse(x)
    tree = (tree.insert)(p.value, label: p.label)
  }
  tree
}
