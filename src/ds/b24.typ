// 2-3-4 tree (a B-tree of order 4).
//
// Every node holds 1, 2, or 3 keys — so 2, 3, or 4 children — and every leaf
// sits at the same depth. The invariants every public operation preserves:
//
//   1. 1 <= keys.len() <= 3. (Transient 4-key states live inside the split
//      helpers and never escape.)
//   2. Keys are strictly increasing.
//   3. Either children.len() == 0 (a leaf) or children.len() == keys.len() + 1.
//   4. All leaves are at the same depth.
//
// A node is `(kind: "b24", keys, labels, children)`: `keys` orders the tree,
// `labels` runs parallel to it (`auto` falls back to `str(key)`), and
// `children` is empty for a leaf.
//
// Two rebalancing algorithms, chosen with `strategy:`:
//
//   "top-down"  (default) preventive — split any 3-key node on the way down
//               for an insert, refill any 1-key node on the way down for a
//               delete. One pass. A top-down split promotes the middle key
//               (index 1) of the 3-key node, decided *before* the new key is
//               inserted.
//   "bottom-up" reactive — walk to the leaf first, allow a transient 4-key
//               node, then split back up. A bottom-up split promotes the
//               upper-middle key (index 2) of the 4-key overflow, so the key
//               just inserted is itself a candidate for promotion.
//
// Both produce valid trees holding the same keys, but the SHAPES may
// legitimately differ: they agree whenever the inserted key falls in the
// lower half of an about-to-be-split node and diverge when it falls in the
// upper half. Both displays honour the choice, so the two can be compared
// frame by frame — which is the reason both exist.
//
// Element identity: a key compartment is `"<node-path>#<key-idx>"`, so
// `"1#2"` is the third key of the root's second child. `node-path` uses the
// n-ary digit alphabet (`""` the root, `"0"` its leftmost child, `"012"`
// leftmost then middle then right-of-middle). Edges are keyed by their
// child's node-path, with no `#` suffix. That is what `anchor` and the
// `key-styles` node-style slot address.
//
// step.kind vocabulary
// --------------------
//   static                     the one frame of `display`
//   init                       the opening frame of every animation
//   compare                    one comparison along a descent
//   found / not-found          how a search ended
//   td-pre-split-attention     a full node, about to be split preventively
//   split-done                 the promoted key now sits in its parent
//   bu-overflow                a transient 4-key node, about to split
//   settled                    terminal success of a mutation
//   td-pre-fix-attention       an under-full descent target
//   td-borrow-left / td-borrow-right / td-merge
//                              the three ways to refill it
//   td-target                  the key to delete, found
//   td-pred-swap / td-succ-swap
//                              its value replaced by a neighbour's, which is
//                              then deleted from a leaf instead
//   td-remove                  the key is gone from the leaf
//   td-root-collapse           the root's last key was merged away
//   visit                      one key of a traversal
// The final frame of every display carries `step.result` — the tree the
// operation produced (the unchanged input, for a search or traversal).

#import "../core/draw-util.typ": anchor
#import "../core/frame.typ": make-frames, make-renderer
#import "../core/snapshot.typ": blank-snapshot, with-edge, with-node
#import "../core/text.typ": alt-describe, alt-intro, alt-key-label
#import "../draw/tree.typ": draw-tree

#let _DS = "2-4 tree"

// Every B24 renderer needs this so the tree backend picks the subdivided
// rectangle rather than a circle.
#let _NODE-STYLE = (shape: "btree-node")
// --- node-construction & shape helpers -----------------------------

#let _mk(keys, labels, children) = (
  kind: "b24",
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
#let _replace-at(node, path, new) = if path == "" {
  new
} else {
  let idx = int(path.first())
  let new-children = node.children
  new-children.at(idx) = _replace-at(node.children.at(idx), path.slice(1), new)
  _mk(node.keys, node.labels, new-children)
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
#let _split(node) = {
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
    left: _mk(left-keys, left-labels, left-children),
    mid-key: mid-key,
    mid-label: mid-label,
    right: _mk(right-keys, right-labels, right-children),
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
#let _merge(left, sep-key, sep-label, right) = _mk(
  left.keys + (sep-key,) + right.keys,
  left.labels + (sep-label,) + right.labels,
  left.children + right.children,
)

// --- insert: bottom-up ---------------------------------------------

// Recursive helper. Returns either ("ok", node) or
// ("split", left, mid-key, mid-label, right).
#let _bu-insert-rec(node, v, label) = {
  if _is-leaf(node) {
    let (new-keys, new-labels, _) = _insert-sorted(node.keys, node.labels, v, label)
    let tmp = _mk(new-keys, new-labels, ())
    if new-keys.len() <= 3 {
      (kind: "ok", node: tmp)
    } else {
      let s = _split(tmp)
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
    let res = _bu-insert-rec(node.children.at(i), v, label)
    if res.kind == "ok" {
      let nc = node.children
      nc.at(i) = res.node
      (kind: "ok", node: _mk(node.keys, node.labels, nc))
    } else {
      let (nk, nl) = _splice-key(node.keys, node.labels, i, res.mid-key, res.mid-label)
      let nc = _splice-children(node.children, i, res.left, res.right)
      let tmp = _mk(nk, nl, nc)
      if nk.len() <= 3 {
        (kind: "ok", node: tmp)
      } else {
        let s = _split(tmp)
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

#let _insert-bu(root, v, label) = {
  let res = _bu-insert-rec(root, v, label)
  if res.kind == "ok" {
    res.node
  } else {
    _mk((res.mid-key,), (res.mid-label,), (res.left, res.right))
  }
}

// --- insert: top-down ----------------------------------------------

#let _td-descend-insert(node, v, label) = {
  // Precondition: `node` has < 3 keys (i.e., it was not full when its
  // parent decided to descend into it).
  if _is-leaf(node) {
    let (nk, nl, _) = _insert-sorted(node.keys, node.labels, v, label)
    _mk(nk, nl, ())
  } else {
    let i = _scan(node.keys, v)
    let child = node.children.at(i)
    if child.keys.len() == 3 {
      // Preemptive split before descending.
      let s = _split(child)
      let (nk, nl) = _splice-key(node.keys, node.labels, i, s.mid-key, s.mid-label)
      let nc = _splice-children(node.children, i, s.left, s.right)
      let updated = _mk(nk, nl, nc)
      // Re-decide which side v belongs to after the split.
      let target = if v < s.mid-key { i } else if v > s.mid-key { i + 1 } else { i }
      let new-target = _td-descend-insert(updated.children.at(target), v, label)
      let final-children = updated.children
      final-children.at(target) = new-target
      _mk(updated.keys, updated.labels, final-children)
    } else {
      let new-child = _td-descend-insert(child, v, label)
      let nc = node.children
      nc.at(i) = new-child
      _mk(node.keys, node.labels, nc)
    }
  }
}

#let _insert-td(root, v, label) = {
  if root.keys.len() == 3 {
    // Pre-split root so descent invariants hold from frame one.
    let s = _split(root)
    let new-root = _mk(
      (s.mid-key,),
      (s.mid-label,),
      (s.left, s.right),
    )
    _td-descend-insert(new-root, v, label)
  } else {
    _td-descend-insert(root, v, label)
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
#let _rotate-from-left(node, i) = {
  let parent = node
  let target = parent.children.at(i)
  let left = parent.children.at(i - 1)
  let borrowed-key = left.keys.last()
  let borrowed-label = left.labels.last()
  let borrowed-child = if _is-leaf(left) { none } else { left.children.last() }
  let new-left = _mk(
    left.keys.slice(0, left.keys.len() - 1),
    left.labels.slice(0, left.labels.len() - 1),
    if _is-leaf(left) {
      ()
    } else { left.children.slice(0, left.children.len() - 1) },
  )
  let sep-key = parent.keys.at(i - 1)
  let sep-label = parent.labels.at(i - 1)
  let new-target = _mk(
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
  _mk(nk, nl, nc)
}

// Mirror of the above, rotating from the right sibling.
#let _rotate-from-right(node, i) = {
  let parent = node
  let target = parent.children.at(i)
  let right = parent.children.at(i + 1)
  let borrowed-key = right.keys.first()
  let borrowed-label = right.labels.first()
  let borrowed-child = if _is-leaf(right) { none } else { right.children.first() }
  let new-right = _mk(
    right.keys.slice(1),
    right.labels.slice(1),
    if _is-leaf(right) { () } else { right.children.slice(1) },
  )
  let sep-key = parent.keys.at(i)
  let sep-label = parent.labels.at(i)
  let new-target = _mk(
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
  _mk(nk, nl, nc)
}

// Merge children[i] and children[i+1] using parent.keys[i] as the
// separator. Returns the updated parent (which loses one key).
#let _merge-siblings(node, i) = {
  let merged = _merge(
    node.children.at(i),
    node.keys.at(i),
    node.labels.at(i),
    node.children.at(i + 1),
  )
  let nk = node.keys.slice(0, i) + node.keys.slice(i + 1)
  let nl = node.labels.slice(0, i) + node.labels.slice(i + 1)
  let nc = node.children.slice(0, i) + (merged,) + node.children.slice(i + 2)
  _mk(nk, nl, nc)
}

// --- delete: top-down ----------------------------------------------

// Ensure children[i] of `parent` has ≥ 2 keys, fixing it up by
// rotating from a sibling or merging if necessary. Returns
// (new-parent, new-child-index) since merging may shift the
// child's index by 1.
#let _td-ensure-rich(parent, i) = {
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
      (parent: _rotate-from-left(parent, i), i: i)
    } else if right-rich {
      (parent: _rotate-from-right(parent, i), i: i)
    } else if has-left {
      // Merge with left sibling.
      let new-parent = _merge-siblings(parent, i - 1)
      (parent: new-parent, i: i - 1)
    } else {
      // Merge with right sibling.
      let new-parent = _merge-siblings(parent, i)
      (parent: new-parent, i: i)
    }
  }
}

#let _td-delete-rec(node, v) = {
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
    _mk(
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
      let new-left = _td-delete-rec(left-c, pred.value)
      let nk = node.keys
      let nl = node.labels
      nk.at(key-idx) = pred.value
      nl.at(key-idx) = pred.label
      let nc = node.children
      nc.at(key-idx) = new-left
      _mk(nk, nl, nc)
    } else if right-c.keys.len() >= 2 {
      let succ = _min-entry(right-c)
      let new-right = _td-delete-rec(right-c, succ.value)
      let nk = node.keys
      let nl = node.labels
      nk.at(key-idx) = succ.value
      nl.at(key-idx) = succ.label
      let nc = node.children
      nc.at(key-idx + 1) = new-right
      _mk(nk, nl, nc)
    } else {
      // Both flanking children are 1-key. Merge them with v in the
      // middle, then descend into the merged child to remove v.
      let merged-parent = _merge-siblings(node, key-idx)
      let new-merged = _td-delete-rec(merged-parent.children.at(key-idx), v)
      let nc = merged-parent.children
      nc.at(key-idx) = new-merged
      _mk(merged-parent.keys, merged-parent.labels, nc)
    }
  } else {
    // v not in this node — descend into the appropriate child,
    // refilling it first if it's a 1-key node.
    let i = _scan(node.keys, v)
    let fix = _td-ensure-rich(node, i)
    let target = fix.parent.children.at(fix.i)
    let new-target = _td-delete-rec(target, v)
    let nc = fix.parent.children
    nc.at(fix.i) = new-target
    _mk(fix.parent.keys, fix.parent.labels, nc)
  }
}

#let _delete-td(root, v) = {
  // Root is allowed to have 1 key. If it does and both children are
  // 1-key nodes, merge them into a new root.
  let prepared = if (
    not _is-leaf(root) and root.keys.len() == 1
      and root.children.at(0).keys.len() == 1
      and root.children.at(1).keys.len() == 1
  ) {
    _merge(
      root.children.at(0),
      root.keys.at(0),
      root.labels.at(0),
      root.children.at(1),
    )
  } else { root }
  let after = _td-delete-rec(prepared, v)
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

// Fix an underflow at children[i] of `parent`. Returns
// (new-parent, underflow: bool). The returned parent may itself be
// underflowing (only if it now has 0 keys — i.e. the merge consumed
// its last separator), in which case the caller propagates.
#let _bu-fixup(parent, i) = {
  let n-children = parent.children.len()
  let has-left = i > 0
  let has-right = i < n-children - 1
  let left-rich = has-left and parent.children.at(i - 1).keys.len() >= 2
  let right-rich = has-right and parent.children.at(i + 1).keys.len() >= 2
  let new-parent = if left-rich {
    _rotate-from-left(parent, i)
  } else if right-rich {
    _rotate-from-right(parent, i)
  } else if has-left {
    _merge-siblings(parent, i - 1)
  } else {
    _merge-siblings(parent, i)
  }
  (node: new-parent, underflow: new-parent.keys.len() == 0)
}

// --- delete: bottom-up ---------------------------------------------

// Returns (node, underflow: bool). Underflow when the returned node
// has fewer keys than the per-node minimum (0 keys for a non-root).
#let _bu-delete-rec(node, v) = {
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
    let new-node = _mk(new-keys, new-labels, ())
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
      let res = _bu-delete-rec(left-c, pred.value)
      let nc = node.children
      nc.at(key-idx) = res.node
      let new-parent = _mk(nk, nl, nc)
      if res.underflow {
        _bu-fixup(new-parent, key-idx)
      } else {
        (node: new-parent, underflow: false)
      }
    } else {
      // Descend into the appropriate child.
      let i = _scan(node.keys, v)
      let res = _bu-delete-rec(node.children.at(i), v)
      let nc = node.children
      nc.at(i) = res.node
      let new-parent = _mk(node.keys, node.labels, nc)
      if res.underflow {
        _bu-fixup(new-parent, i)
      } else {
        (node: new-parent, underflow: false)
      }
    }
  }
}

#let _delete-bu(root, v) = {
  let res = _bu-delete-rec(root, v)
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
// Construction
// ===================================================================

// Parse one factory argument into a `(value, label)` pair.
#let _parse-value(x, who) = if type(x) == array {
  assert(
    x.len() == 2,
    message: who + ": expected a (key, label) 2-tuple, got " + repr(x) + ".",
  )
  (value: x.at(0), label: x.at(1))
} else {
  (value: x, label: auto)
}

/// A node holding `keys`, with either no children (a leaf) or exactly
/// `keys.len() + 1` of them.
///
/// `keys` is one key or an array of them; each entry is a bare key or a
/// `(key, label)` pair, so labels can be mixed in exactly as `new` allows.
///
/// ```typ
/// b24.node((10, 20), b24.leaf(3, 7), b24.leaf(15), b24.leaf(25, 30))
/// ```
///
/// -> dictionary
#let node(
  /// One key, or an array of keys / `(key, label)` pairs.
  /// -> int | array
  keys,
  /// Nothing (a leaf) or exactly `keys.len() + 1` children.
  /// -> dictionary
  ..children,
) = {
  let ks = if type(keys) == array { keys } else { (keys,) }
  let parsed = ks.map(k => _parse-value(k, "b24.node"))
  let cs = children.pos()
  assert(
    parsed.len() >= 1 and parsed.len() <= 3,
    message: "b24.node: a node holds 1 to 3 keys, got " + str(parsed.len()) + ".",
  )
  assert(
    cs.len() == 0 or cs.len() == parsed.len() + 1,
    message: "b24.node: expected no children or "
      + str(parsed.len() + 1)
      + " (one more than the "
      + str(parsed.len())
      + " keys), got "
      + str(cs.len())
      + ".",
  )
  _mk(parsed.map(p => p.value), parsed.map(p => p.label), cs)
}

/// A childless node — `node(keys)` with the intent spelled out. Keys are
/// variadic here, since a leaf has no children to disambiguate them from.
///
/// ```typ
/// b24.leaf(3, 7)
/// b24.leaf((3, [three]), 7)
/// ```
///
/// -> dictionary
#let leaf(
  /// The keys, each a bare key or a `(key, label)` pair.
  /// -> int | array
  ..keys,
) = node(keys.pos())

// ===================================================================
// Pure operations
// ===================================================================

/// The subtree at a node-path (no `#` suffix).
/// -> dictionary
#let resolve(
  /// The tree.
  /// -> dictionary
  tree,
  /// The digit path.
  /// -> str
  path,
) = _resolve-at(tree, path)

/// Whether `v` is in the tree.
/// -> bool
#let contains(
  /// The tree.
  /// -> dictionary
  tree,
  /// The key to look for.
  /// -> int
  v,
) = {
  let walk(n) = {
    let i = _scan(n.keys, v)
    if i < n.keys.len() and n.keys.at(i) == v {
      true
    } else if _is-leaf(n) { false } else { walk(n.children.at(i)) }
  }
  walk(tree)
}

/// The compartment path `"<node-path>#<key-idx>"` of the key holding `v`.
/// Panics when `v` is absent.
/// -> str
#let by-value(
  /// The tree.
  /// -> dictionary
  tree,
  /// The key to look for.
  /// -> int
  v,
) = {
  let walk(n, path) = {
    let i = _scan(n.keys, v)
    if i < n.keys.len() and n.keys.at(i) == v {
      path + "#" + str(i)
    } else if _is-leaf(n) {
      panic("b24.by-value: key not found in tree: " + repr(v) + ".")
    } else {
      walk(n.children.at(i), path + str(i))
    }
  }
  walk(tree, "")
}

/// Every comparison made searching for `v`, in order. Each record is
/// `(path, key-idx, key-value, key-label, cmp, found)`. Panics when `v` is
/// absent — @@search-display() is the form that narrates a miss.
/// -> array
#let path-to(
  /// The tree.
  /// -> dictionary
  tree,
  /// The key to look for.
  /// -> int
  v,
) = {
  let walk(n, path) = {
    let scan(i) = {
      if i == n.keys.len() {
        // v exceeds every key here; descend the rightmost child.
        if _is-leaf(n) {
          panic("b24.path-to: key not found in tree: " + repr(v) + ".")
        }
        walk(n.children.at(i), path + str(i))
      } else {
        let k = n.keys.at(i)
        let cmp = if v == k {
          str(v) + " = " + str(k)
        } else if v < k { str(v) + " < " + str(k) } else {
          str(v) + " > " + str(k)
        }
        let entry = (
          path: path,
          key-idx: i,
          key-value: k,
          key-label: alt-key-label(n, i),
          cmp: cmp,
          found: v == k,
        )
        if v == k {
          (entry,)
        } else if v < k {
          if _is-leaf(n) {
            panic("b24.path-to: key not found in tree: " + repr(v) + ".")
          }
          (entry,) + walk(n.children.at(i), path + str(i))
        } else {
          (entry,) + scan(i + 1)
        }
      }
    }
    scan(0)
  }
  walk(tree, "")
}

// The two strategies, and the error when neither is named.
#let _strategies = ("top-down", "bottom-up")
#let _assert-strategy(strategy, who) = assert(
  _strategies.contains(strategy),
  message: who
    + ": unknown strategy "
    + repr(strategy)
    + "; supported: \"top-down\", \"bottom-up\".",
)

/// Insert `v`, returning a new tree.
///
/// `strategy` picks between splitting full nodes preventively on the way
/// down (`"top-down"`) and splitting a transient overflow on the way back up
/// (`"bottom-up"`). Both are correct; the shapes may differ.
/// -> dictionary
#let insert(
  /// The tree.
  /// -> dictionary
  tree,
  /// The key to insert.
  /// -> int
  v,
  /// What to draw in the new compartment; `auto` draws `str(v)`.
  /// -> auto | any
  label: auto,
  /// `"top-down"` or `"bottom-up"`.
  /// -> str
  strategy: "top-down",
) = {
  _assert-strategy(strategy, "b24.insert")
  if strategy == "top-down" {
    _insert-td(tree, v, label)
  } else { _insert-bu(tree, v, label) }
}

/// Insert several keys in order, top-down. Each is a bare key or a
/// `(key, label)` pair.
/// -> dictionary
#let insert-many(
  /// The tree.
  /// -> dictionary
  tree,
  /// The keys to insert.
  /// -> any
  ..vals,
) = {
  let out = tree
  for x in vals.pos() {
    let p = _parse-value(x, "b24.insert-many")
    out = insert(out, p.value, label: p.label)
  }
  out
}

/// Build a tree from a list of keys: the first seeds the root, the rest are
/// inserted in order. Each is a bare key or a `(key, label)` pair.
///
/// ```typ
/// b24.new(4, 1, 7, 3, 6, 8)
/// b24.new((4, [FOUR]), 1, 7, (6, [SIX]))
/// ```
///
/// -> dictionary
#let new(
  /// The keys. At least one is required — it seeds the root.
  /// -> any
  ..vals,
) = {
  let xs = vals.pos()
  assert(xs.len() > 0, message: "b24.new: at least one key is required (the root).")
  let head = _parse-value(xs.first(), "b24.new")
  insert-many(_mk((head.value,), (head.label,), ()), ..xs.slice(1))
}

// An empty leaf at the root means the tree has been emptied. Surface that
// as `none`, the way every other structure's `delete` does — the internal
// algorithms find the empty leaf easier to carry than a `none`.
#let _empty-to-none(tree) = if (
  tree != none and tree.keys.len() == 0 and _is-leaf(tree)
) { none } else { tree }

/// Delete `v`, returning a new tree (or `none` if the last key went).
///
/// `strategy` picks between refilling an under-full node on the way down
/// (`"top-down"`) and merging on the way back up (`"bottom-up"`).
/// -> dictionary | none
#let delete(
  /// The tree.
  /// -> dictionary
  tree,
  /// The key to delete.
  /// -> int
  v,
  /// `"top-down"` or `"bottom-up"`.
  /// -> str
  strategy: "top-down",
) = {
  _assert-strategy(strategy, "b24.delete")
  let out = if strategy == "top-down" {
    _delete-td(tree, v)
  } else { _delete-bu(tree, v) }
  _empty-to-none(out)
}

/// A recursive textual rendering of the tree, used in alt text.
/// -> str
#let describe(
  /// The tree.
  /// -> dictionary
  tree,
) = {
  let key-str = range(tree.keys.len()).map(i => alt-key-label(tree, i)).join(", ")
  if _is-leaf(tree) {
    "[" + key-str + "]"
  } else {
    "[" + key-str + "] (children: " + tree.children.map(describe).join(", ") + ")"
  }
}

/// Check all four 2-3-4 invariants: 1 to 3 keys per node, strictly
/// increasing, `keys + 1` children at an internal node, and every leaf at
/// the same depth. Returns `true` or panics naming the first violation.
/// -> bool
#let check-invariants(
  /// The tree.
  /// -> dictionary
  tree,
) = {
  // Returns the subtree's leaf depth, panicking on the way up.
  let walk(n) = {
    let k = n.keys.len()
    assert(
      k >= 1 and k <= 3,
      message: "b24.check-invariants: node has " + str(k) + " keys (must be 1 to 3).",
    )
    for i in range(k - 1) {
      assert(
        n.keys.at(i) < n.keys.at(i + 1),
        message: "b24.check-invariants: keys are not strictly increasing: "
          + repr(n.keys)
          + ".",
      )
    }
    if _is-leaf(n) {
      1
    } else {
      assert(
        n.children.len() == k + 1,
        message: "b24.check-invariants: node "
          + repr(n.keys)
          + " has "
          + str(n.children.len())
          + " children, expected "
          + str(k + 1)
          + " (one more than its keys).",
      )
      let depths = n.children.map(walk)
      assert(
        depths.all(d => d == depths.first()),
        message: "b24.check-invariants: unequal leaf depths under node "
          + repr(n.keys)
          + ".",
      )
      depths.first() + 1
    }
  }
  let _ = walk(tree)
  true
}

/// The compartment paths of every key, in left-to-right sorted order — the
/// in-order walk threads each key between its flanking subtrees.
/// -> array
#let in-order(
  /// The tree.
  /// -> dictionary
  tree,
) = _traverse-in(tree, "")

/// The compartment paths of every key, node before children.
/// -> array
#let pre-order(
  /// The tree.
  /// -> dictionary
  tree,
) = _traverse-pre(tree, "")

/// The compartment paths of every key, children before node.
/// -> array
#let post-order(
  /// The tree.
  /// -> dictionary
  tree,
) = _traverse-post(tree, "")

/// The compartment paths of every key, breadth-first by node.
/// -> array
#let level-order(
  /// The tree.
  /// -> dictionary
  tree,
) = {
  let out = ()
  let queue = ("",)
  while queue.len() > 0 {
    let path = queue.first()
    queue = queue.slice(1)
    let n = _resolve-at(tree, path)
    for i in range(n.keys.len()) { out.push(path + "#" + str(i)) }
    if not _is-leaf(n) {
      for j in range(n.children.len()) { queue.push(path + str(j)) }
    }
  }
  out
}

// ===================================================================
// Rendering
// ===================================================================

// A readable text fill for a given background, from its oklab lightness —
// so a compartment label stays legible against any traversal colour.
#let _text-fill-for(bg) = {
  let l = bg.oklab().components().first()
  if l < 60% { white } else { black }
}

// A `key-styles` array of length `n` where only compartment `idx` carries
// the override. Compartment styling merges index-wise, so this is how one
// key of a node is highlighted without disturbing its neighbours.
#let _solo-key-style(n, idx, override) = range(n).map(i => if i == idx {
  override
} else { (:) })

/// A `Renderer` over this tree, bound to the tree backend and carrying the
/// subdivided-rectangle node shape — the entry point for driving an
/// animation yourself with the `Op` command stream. Pass `sticky: true` when
/// you want each frame's styling to accumulate.
/// -> dictionary
#let renderer(
  /// The tree.
  /// -> dictionary
  tree,
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
) = make-renderer(
  tree,
  draw-tree,
  node-style: (:.._NODE-STYLE, ..node-style),
  edge-style: edge-style,
  sticky: sticky,
  theme: theme,
)

// Every display shares this. The caller's `node-style:` layers over the
// btree-node shape rather than replacing it, so overriding a fill doesn't
// silently turn every node back into a circle.
#let _frames(specs, theme, node-style, edge-style) = make-frames(
  specs,
  draw-tree,
  theme: theme,
  node-style: (:.._NODE-STYLE, ..node-style),
  edge-style: edge-style,
)
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

// Re-apply the accumulated descent comparisons to a snapshot. Each entry
// rings its compartment in `search-stroke` and hangs the comparison text
// off its node; `key-styles` merges index-wise, so several highlighted
// compartments on one node stay distinct.
#let _replay-history(snap, tree, history, th) = {
  let cur = snap
  for h in history {
    let node = _resolve-at(tree, h.path)
    cur = with-node(
      cur,
      h.path,
      (
        key-styles: _solo-key-style(
          node.keys.len(),
          h.key-idx,
          (stroke: th.op.search-stroke),
        ),
        note: h.cmp,
      ),
    )
  }
  cur
}

#let _td-insert-events(root, v, label) = {
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
    let s = _split(current)
    current = _mk((s.mid-key,), (s.mid-label,), (s.left, s.right))
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
      let new-leaf = _mk(nk, nl, ())
      current = _replace-at(current, node-path, new-leaf)
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
      let s = _split(child)
      let parent = _resolve-at(current, node-path)
      let new-parent = _mk(
        parent.keys.slice(0, i) + (s.mid-key,) + parent.keys.slice(i),
        parent.labels.slice(0, i) + (s.mid-label,) + parent.labels.slice(i),
        parent.children.slice(0, i)
          + (s.left, s.right)
          + parent.children.slice(i + 1),
      )
      current = _replace-at(current, node-path, new-parent)
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

#let _bu-insert-events(root, v, label) = {
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
  let new-leaf = _mk(nk, nl, ())
  let current = _replace-at(root, leaf-path, new-leaf)
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
    let s = _split(new-leaf)
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
      let new-ancestor = _mk(
        ancestor.keys.slice(0, i) + (pending-key,) + ancestor.keys.slice(i),
        ancestor.labels.slice(0, i)
          + (pending-label,)
          + ancestor.labels.slice(i),
        ancestor.children.slice(0, i)
          + (pending-left, pending-right)
          + ancestor.children.slice(i + 1),
      )
      current = _replace-at(current, ancestor-path, new-ancestor)
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
      let s2 = _split(new-ancestor)
      pending-left = s2.left
      pending-right = s2.right
      pending-key = s2.mid-key
      pending-label = s2.mid-label
      current-leaf-path = ancestor-path
    }
    // Stack exhausted — split propagated through the root.
    let new-root = _mk((pending-key,), (pending-label,), (pending-left, pending-right))
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

#let _td-delete-events(root, v) = {
  let events = ((kind: "init", tree: root),)

  // Root prep: if the root has 1 key and both children are 1-key,
  // merge them so descent invariants hold from frame one.
  let current = if (
    not _is-leaf(root) and root.keys.len() == 1
      and root.children.at(0).keys.len() == 1
      and root.children.at(1).keys.len() == 1
  ) {
    let merged = _merge(
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
        let new-leaf = _mk(
          node.keys.slice(0, key-idx) + node.keys.slice(key-idx + 1),
          node.labels.slice(0, key-idx) + node.labels.slice(key-idx + 1),
          (),
        )
        current = _replace-at(current, path, new-leaf)
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
          let new-node = _mk(nk, nl, node.children)
          current = _replace-at(current, path, new-node)
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
          let new-node = _mk(nk, nl, node.children)
          current = _replace-at(current, path, new-node)
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
          let merged-parent = _merge-siblings(node, key-idx)
          current = _replace-at(current, path, merged-parent)
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
          let new-parent = _rotate-from-left(node, descend-i)
          current = _replace-at(current, path, new-parent)
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
          let new-parent = _rotate-from-right(node, descend-i)
          current = _replace-at(current, path, new-parent)
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
          let new-parent = _merge-siblings(node, descend-i - 1)
          current = _replace-at(current, path, new-parent)
          events.push((
            kind: "td-merge",
            tree: current,
            merge-path: path,
            merge-child-idx: descend-i - 1,
          ))
          history = ()
          path = path + str(descend-i - 1)
        } else {
          let new-parent = _merge-siblings(node, descend-i)
          current = _replace-at(current, path, new-parent)
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

#let _bu-delete-events(root, v) = {
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
    let new-v-node = _mk(nk, nl, v-node.children)
    current = _replace-at(current, path, new-v-node)
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
  let new-leaf = _mk(
    leaf.keys.slice(0, remove-idx) + leaf.keys.slice(remove-idx + 1),
    leaf.labels.slice(0, remove-idx) + leaf.labels.slice(remove-idx + 1),
    (),
  )
  current = _replace-at(current, target-leaf-path, new-leaf)
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
        fixed-parent = _rotate-from-left(parent, i)
        new-kind = "td-borrow-left"
      } else if right-rich {
        fixed-parent = _rotate-from-right(parent, i)
        new-kind = "td-borrow-right"
      } else if has-left {
        fixed-parent = _merge-siblings(parent, i - 1)
        new-kind = "td-merge"
      } else {
        fixed-parent = _merge-siblings(parent, i)
        new-kind = "td-merge"
      }
      current = _replace-at(current, parent-path, fixed-parent)
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
// `disp` is the human-readable name of the inserted key — its label
// when a string was supplied, else `str(v)` (see `_alt-key-label`).

// ===================================================================
// Events to frames
// ===================================================================

// One spec per insert event. `disp` names the inserted key the way it is
// drawn (its label when a string was supplied, else the key).
#let _insert-specs(events, v, disp) = events.map(ev => {
  let caption = none
  let alt = ""
  let step = (kind: ev.kind)

  if ev.kind == "init" {
    alt = alt-intro(_DS, describe(ev.tree), "insert " + disp)
  } else if ev.kind == "compare" {
    caption = ev.cmp-text
    alt = "Comparing " + ev.cmp-text + " at the current node."
    step.insert("path", ev.cmp-path)
    step.insert("key-idx", ev.cmp-key-idx)
  } else if ev.kind == "td-pre-split-attention" {
    caption = [Full node — split first]
    alt = ("The node at path "
      + ev.target-path
      + " is full (3 keys); splitting it before descending.")
    step.insert("target-path", ev.target-path)
  } else if ev.kind == "split-done" {
    caption = [Promoted key]
    alt = "Split complete; the promoted key now sits in its parent."
    step.insert("promoted-path", ev.promoted-path)
    step.insert("promoted-key-idx", ev.promoted-key-idx)
  } else if ev.kind == "bu-overflow" {
    caption = [Overflow]
    alt = "The leaf overflows with 4 keys — split before continuing."
    step.insert("overflow-path", ev.overflow-path)
  } else if ev.kind == "settled" {
    caption = [Inserted #v]
    alt = "Inserted " + disp + "."
    step.insert("leaf-path", ev.leaf-path)
    step.insert("new-key-idx", ev.new-key-idx)
  }

  let build = th => {
    let cur = blank-snapshot()
    if ev.kind == "compare" {
      cur = _replay-history(cur, ev.tree, ev.history, th)
    } else if ev.kind == "td-pre-split-attention" {
      cur = _replay-history(cur, ev.tree, ev.history, th)
      cur = with-node(cur, ev.target-path, (stroke: th.op.attention-stroke))
    } else if ev.kind == "split-done" {
      let n = _resolve-at(ev.tree, ev.promoted-path)
      cur = with-node(
        cur,
        ev.promoted-path,
        (
          key-styles: _solo-key-style(
            n.keys.len(),
            ev.promoted-key-idx,
            (stroke: th.op.success-stroke),
          ),
        ),
      )
      for p in ev.new-child-paths {
        cur = with-edge(cur, p, (stroke: th.op.success-stroke))
      }
    } else if ev.kind == "bu-overflow" {
      let n = _resolve-at(ev.tree, ev.overflow-path)
      cur = with-node(
        cur,
        ev.overflow-path,
        (
          key-styles: _solo-key-style(
            n.keys.len(),
            ev.overflow-key-idx,
            (stroke: th.op.danger-stroke, fill: th.op.success-fill),
          ),
          stroke: th.op.danger-stroke,
        ),
      )
    } else if ev.kind == "settled" {
      let n = _resolve-at(ev.tree, ev.leaf-path)
      cur = with-node(
        cur,
        ev.leaf-path,
        (
          key-styles: _solo-key-style(
            n.keys.len(),
            ev.new-key-idx,
            (fill: th.op.success-fill, stroke: th.op.settled-stroke),
          ),
        ),
      )
    }
    // "init" draws the tree unstyled.
    cur
  }

  (structure: ev.tree, build: build, caption: caption, step: step, alt: alt)
})

// One spec per delete event. `disp` names the deleted key the way it is
// drawn, resolved once up front because a predecessor swap relocates the
// key mid-descent.
#let _delete-specs(events, v, disp) = events.map(ev => {
  let caption = none
  let alt = ""
  let step = (kind: ev.kind)

  if ev.kind == "init" {
    alt = alt-intro(_DS, describe(ev.tree), "delete " + disp)
  } else if ev.kind == "compare" {
    caption = ev.cmp-text
    alt = "Comparing " + ev.cmp-text + " at the current node."
    step.insert("path", ev.cmp-path)
    step.insert("key-idx", ev.cmp-key-idx)
  } else if ev.kind == "td-pre-fix-attention" {
    caption = [Under-full — fix before descending]
    alt = ("The descent target has only 1 key; borrowing or merging before "
      + "descending into it.")
    step.insert("target-path", ev.target-path)
  } else if ev.kind == "td-borrow-left" {
    caption = [Borrow from left]
    alt = ("Borrow: the separator slides down into the target and the left "
      + "sibling's rightmost key slides up to replace it.")
    step.insert("target-path", ev.target-path)
  } else if ev.kind == "td-borrow-right" {
    caption = [Borrow from right]
    alt = ("Borrow: the separator slides down into the target and the right "
      + "sibling's leftmost key slides up to replace it.")
    step.insert("target-path", ev.target-path)
  } else if ev.kind == "td-merge" {
    caption = [Merge]
    alt = "Merged two children with their separator key."
    step.insert("merge-path", ev.merge-path)
  } else if ev.kind == "td-target" {
    caption = [Target found]
    alt = "Found the key to delete; it will swap with its predecessor."
    step.insert("target-path", ev.target-path)
    step.insert("target-key-idx", ev.target-key-idx)
  } else if ev.kind == "td-pred-swap" {
    caption = [Swap with predecessor]
    alt = ("Replaced the target's key with its predecessor; the predecessor "
      + "is now the one to delete, and it lives in a leaf.")
    step.insert("path", ev.path)
    step.insert("key-idx", ev.key-idx)
  } else if ev.kind == "td-succ-swap" {
    caption = [Swap with successor]
    alt = ("Replaced the target's key with its successor; the successor is "
      + "now the one to delete, and it lives in a leaf.")
    step.insert("path", ev.path)
    step.insert("key-idx", ev.key-idx)
  } else if ev.kind == "td-remove" {
    caption = [Removed #v]
    alt = "Removed " + disp + " from the leaf."
    step.insert("leaf-path", ev.leaf-path)
  } else if ev.kind == "td-root-collapse" {
    caption = [Root collapsed]
    alt = ("The root's only key was consumed by a merge; its single remaining "
      + "child becomes the new root.")
  }

  let build = th => {
    let cur = blank-snapshot()
    if ev.kind == "compare" {
      cur = _replay-history(cur, ev.tree, ev.history, th)
    } else if ev.kind == "td-pre-fix-attention" {
      cur = _replay-history(cur, ev.tree, ev.history, th)
      cur = with-node(cur, ev.target-path, (stroke: th.op.attention-stroke))
    } else if ev.kind == "td-borrow-left" or ev.kind == "td-borrow-right" {
      // The parent's affected key, plus the two edges the keys moved across.
      let parent = _resolve-at(ev.tree, ev.parent-path)
      cur = with-node(
        cur,
        ev.parent-path,
        (
          key-styles: _solo-key-style(
            parent.keys.len(),
            ev.parent-key-idx,
            (stroke: th.op.success-stroke),
          ),
        ),
      )
      cur = with-edge(cur, ev.target-path, (stroke: th.op.success-stroke))
      cur = with-edge(cur, ev.sibling-path, (stroke: th.op.success-stroke))
    } else if ev.kind == "td-merge" {
      // A root-prep merge has no child edge to highlight — outline the new
      // merged root instead.
      if ev.merge-child-idx == none {
        cur = with-node(cur, ev.merge-path, (stroke: th.op.success-stroke))
      } else {
        cur = with-edge(
          cur,
          ev.merge-path + str(ev.merge-child-idx),
          (stroke: th.op.success-stroke),
        )
      }
    } else if ev.kind == "td-target" {
      cur = _replay-history(cur, ev.tree, ev.history, th)
      let n = _resolve-at(ev.tree, ev.target-path)
      cur = with-node(
        cur,
        ev.target-path,
        (
          key-styles: _solo-key-style(
            n.keys.len(),
            ev.target-key-idx,
            (stroke: th.op.attention-stroke),
          ),
        ),
      )
    } else if ev.kind == "td-pred-swap" or ev.kind == "td-succ-swap" {
      let n = _resolve-at(ev.tree, ev.path)
      cur = with-node(
        cur,
        ev.path,
        (
          key-styles: _solo-key-style(
            n.keys.len(),
            ev.key-idx,
            (fill: th.op.success-fill, stroke: th.op.success-stroke),
          ),
        ),
      )
    } else if ev.kind == "td-remove" {
      // The compartment is gone, so there is nothing to highlight inside the
      // node; outline the whole node to signal completion.
      cur = with-node(cur, ev.leaf-path, (stroke: th.op.settled-stroke))
    } else if ev.kind == "td-root-collapse" {
      cur = with-node(cur, "", (stroke: th.op.settled-stroke))
    }
    cur
  }

  (structure: ev.tree, build: build, caption: caption, step: step, alt: alt)
})

// Stamp `step.result` onto the last spec — the tree the operation produced.
#let _stamp-result(specs, after) = {
  let out = specs
  let i = out.len() - 1
  let s = out.at(i)
  out.at(i) = (..s, step: (..s.step, result: after))
  out
}

// ===================================================================
// Displays
// ===================================================================

/// The tree as a single static frame.
/// -> array
#let display(
  /// The tree.
  /// -> dictionary
  tree,
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
      build: _ => blank-snapshot(),
      caption: none,
      step: (kind: "static", result: tree),
      alt: alt-describe(_DS, describe(tree)),
    ),
  ),
  theme,
  node-style,
  edge-style,
)

// Every comparison a search for `v` makes, ending at a match or at the last
// key checked before the search would descend off a leaf. Unlike `path-to`
// this narrates a miss instead of panicking.
#let _search-walk(tree, v) = {
  let walk(n, path) = {
    let scan(i) = {
      if i == n.keys.len() {
        if _is-leaf(n) {
          // The search would descend off the rightmost child of a leaf —
          // report the terminal "v > last key" comparison.
          let k = n.keys.last()
          ((
            path: path,
            key-idx: n.keys.len() - 1,
            key-value: k,
            key-label: alt-key-label(n, n.keys.len() - 1),
            cmp: str(v) + " > " + str(k),
            found: false,
          ),)
        } else { walk(n.children.at(i), path + str(i)) }
      } else {
        let k = n.keys.at(i)
        let cmp = if v == k {
          str(v) + " = " + str(k)
        } else if v < k { str(v) + " < " + str(k) } else {
          str(v) + " > " + str(k)
        }
        let entry = (
          path: path,
          key-idx: i,
          key-value: k,
          key-label: alt-key-label(n, i),
          cmp: cmp,
          found: v == k,
        )
        if v == k {
          (entry,)
        } else if v < k {
          if _is-leaf(n) { (entry,) } else {
            (entry,) + walk(n.children.at(i), path + str(i))
          }
        } else {
          (entry,) + scan(i + 1)
        }
      }
    }
    scan(0)
  }
  walk(tree, "")
}

/// Animate searching for `v`: one frame per comparison, each ringing the
/// compared compartment and hanging the comparison beside its node. A miss
/// is animated too — the walk ends on the last key checked before the search
/// would run off the tree.
/// -> array
#let search-display(
  /// The tree.
  /// -> dictionary
  tree,
  /// The key to search for.
  /// -> int
  v,
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
  let cmps = _search-walk(tree, v)
  let n = cmps.len()

  // One shared closure builds every snapshot, each frame indexing into the
  // result; Typst memoizes the call, so the accumulation runs once.
  let build-all = th => {
    let cur = blank-snapshot()
    let out = (cur,)
    for c in cmps {
      let node = _resolve-at(tree, c.path)
      cur = with-node(
        cur,
        c.path,
        (
          key-styles: _solo-key-style(
            node.keys.len(),
            c.key-idx,
            (stroke: th.op.search-stroke),
          ),
          note: c.cmp,
        ),
      )
      out.push(cur)
    }
    out
  }

  let specs = (
    (
      structure: tree,
      build: th => build-all(th).at(0),
      caption: none,
      step: (kind: "init"),
      alt: alt-intro(_DS, describe(tree), "search for " + str(v)),
    ),
  )
  for (i, c) in cmps.enumerate() {
    let at = i + 1
    specs.push((
      structure: tree,
      build: th => build-all(th).at(at),
      caption: c.cmp,
      step: (
        kind: if c.found { "found" } else if at == n { "not-found" } else {
          "compare"
        },
        path: c.path,
        key-idx: c.key-idx,
        cmp: c.cmp,
        found: c.found,
        ..if at == n { (result: tree) },
      ),
      alt: if c.found {
        "Match found at key " + c.key-label + "."
      } else if at == n {
        ("Comparing "
          + c.cmp
          + " at key "
          + c.key-label
          + "; search ends here, "
          + str(v)
          + " is not in the tree.")
      } else {
        ("Comparing " + c.cmp + " at key " + c.key-label + "; continuing search.")
      },
    ))
  }
  _frames(specs, theme, node-style, edge-style)
}

/// Animate inserting `v` under the chosen `strategy`.
///
/// Top-down splits every full node it passes on the way down, so the leaf it
/// reaches always has room; bottom-up walks straight to the leaf, lets it
/// overflow to 4 keys, and splits back up. The two can land the key in
/// different places — running both is the point.
/// -> array
#let insert-display(
  /// The tree.
  /// -> dictionary
  tree,
  /// The key to insert.
  /// -> int
  v,
  /// What to draw in the new compartment; `auto` draws `str(v)`.
  /// -> auto | any
  label: auto,
  /// `"top-down"` or `"bottom-up"`.
  /// -> str
  strategy: "top-down",
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
  _assert-strategy(strategy, "b24.insert-display")
  let events = if strategy == "top-down" {
    _td-insert-events(tree, v, label)
  } else { _bu-insert-events(tree, v, label) }
  // The inserted key displays its label when a string was given.
  let disp = if type(label) == str { label } else { str(v) }
  _frames(
    _stamp-result(_insert-specs(events, v, disp), events.last().tree),
    theme,
    node-style,
    edge-style,
  )
}

/// Animate deleting `v` under the chosen `strategy`.
///
/// Top-down refills every under-full node it passes on the way down — by
/// borrowing from a sibling or merging with one — so the leaf it reaches can
/// always afford to lose a key; bottom-up removes first and repairs on the
/// way back up.
///
/// With `search: false` the descent is dropped entirely — no comparison
/// frames, and no comparison highlights inherited by the frames that remain —
/// so the animation is only the structural work.
/// -> array
#let delete-display(
  /// The tree.
  /// -> dictionary
  tree,
  /// The key to delete.
  /// -> int
  v,
  /// Whether to show one frame per comparison on the way down.
  /// -> bool
  search: true,
  /// `"top-down"` or `"bottom-up"`.
  /// -> str
  strategy: "top-down",
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
  _assert-strategy(strategy, "b24.delete-display")
  let events = if strategy == "top-down" {
    _td-delete-events(tree, v)
  } else { _bu-delete-events(tree, v) }
  let after = _empty-to-none(events.last().tree)
  // Dropping the comparison frames also means dropping the trail they left:
  // the structural frames replay the descent's history, and half a search is
  // more confusing than none.
  let shown = if search { events } else {
    events
      .filter(e => e.kind != "compare")
      .map(e => if "history" in e { (..e, history: ()) } else { e })
  }
  // Name the deleted key the way it is drawn. `v` is known present here —
  // the event producers panic otherwise — so `by-value` cannot fail.
  let bp = by-value(tree, v).split("#")
  let disp = alt-key-label(_resolve-at(tree, bp.at(0)), int(bp.at(1)))
  _frames(
    _stamp-result(_delete-specs(shown, v, disp), after),
    theme,
    node-style,
    edge-style,
  )
}

// ===================================================================
// Traversals
// ===================================================================
//
// One frame per key visited: the visited compartment is filled from the
// theme's `traversal-palette` and the running output accumulates in the
// caption. `paths` is the per-compartment visit order, each entry
// `"<node-path>#<key-idx>"`.

#let _split-path(p) = {
  let parts = p.split("#")
  (parts.at(0), int(parts.at(1)))
}

#let _traversal(tree, paths, name, node-style, edge-style, theme) = {
  let n = paths.len()

  // One shared closure builds every snapshot; each frame then indexes into
  // the result. Typst memoizes the call, so an n-frame traversal costs one
  // accumulation pass rather than n of them.
  let build-all = th => {
    let g = gradient.linear(..th.op.traversal-palette)
    let cur = blank-snapshot()
    let out = (cur,)
    for (i, p) in paths.enumerate() {
      let (node-path, key-idx) = _split-path(p)
      let node = _resolve-at(tree, node-path)
      let t = if n <= 1 { 0% } else { (i / (n - 1)) * 100% }
      let fill = g.sample(t)
      cur = with-node(
        cur,
        node-path,
        (
          key-styles: _solo-key-style(
            node.keys.len(),
            key-idx,
            (fill: fill, text-fill: _text-fill-for(fill)),
          ),
        ),
      )
      out.push(cur)
    }
    out
  }

  let specs = (
    (
      structure: tree,
      build: th => build-all(th).at(0),
      caption: none,
      step: (kind: "init", ..if n == 0 { (result: tree) }),
      alt: alt-intro(_DS, describe(tree), "traverse " + name),
    ),
  )

  let output = ()
  for (i, p) in paths.enumerate() {
    let (node-path, key-idx) = _split-path(p)
    let node = _resolve-at(tree, node-path)
    let disp = alt-key-label(node, key-idx)
    output.push(disp)
    let at = i + 1
    specs.push((
      structure: tree,
      build: th => build-all(th).at(at),
      caption: [Output: #raw("[" + output.join(", ") + "]")],
      step: (
        kind: "visit",
        path: p,
        index: at,
        value: node.keys.at(key-idx),
        ..if at == n { (result: tree) },
      ),
      alt: "Visited "
        + disp
        + " (visit "
        + str(at)
        + " of "
        + str(n)
        + "); output so far: "
        + output.join(", ")
        + ".",
    ))
  }

  _frames(specs, theme, node-style, edge-style)
}

/// Animate an in-order traversal — the sorted walk, threading each key
/// between its flanking subtrees.
/// -> array
#let in-order-display(
  /// The tree.
  /// -> dictionary
  tree,
  /// Base node styling.
  /// -> dictionary
  node-style: (:),
  /// Base edge styling.
  /// -> dictionary
  edge-style: (:),
  /// Partial theme override for this call.
  /// -> dictionary
  theme: (:),
) = _traversal(tree, in-order(tree), "in-order", node-style, edge-style, theme)

/// Animate a pre-order traversal — a node's keys before its children.
/// -> array
#let pre-order-display(
  /// The tree.
  /// -> dictionary
  tree,
  /// Base node styling.
  /// -> dictionary
  node-style: (:),
  /// Base edge styling.
  /// -> dictionary
  edge-style: (:),
  /// Partial theme override for this call.
  /// -> dictionary
  theme: (:),
) = _traversal(tree, pre-order(tree), "pre-order", node-style, edge-style, theme)

/// Animate a post-order traversal — a node's keys after its children.
/// -> array
#let post-order-display(
  /// The tree.
  /// -> dictionary
  tree,
  /// Base node styling.
  /// -> dictionary
  node-style: (:),
  /// Base edge styling.
  /// -> dictionary
  edge-style: (:),
  /// Partial theme override for this call.
  /// -> dictionary
  theme: (:),
) = _traversal(tree, post-order(tree), "post-order", node-style, edge-style, theme)

/// Animate a level-order (breadth-first) traversal.
/// -> array
#let level-order-display(
  /// The tree.
  /// -> dictionary
  tree,
  /// Base node styling.
  /// -> dictionary
  node-style: (:),
  /// Base edge styling.
  /// -> dictionary
  edge-style: (:),
  /// Partial theme override for this call.
  /// -> dictionary
  theme: (:),
) = _traversal(tree, level-order(tree), "level-order", node-style, edge-style, theme)
