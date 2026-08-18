// Binary search tree.
//
// The plainest of the tree structures: no colours, no heights, no rebalancing
// — which is what makes it the one to teach the shape of a tree with. It
// carries no per-DS theme; every animation styles by operation role alone.
//
// A node is `(kind: "bst", value, label, left, right)`. `value` is the
// ordering key; `label` is what gets drawn (`auto` falls back to
// `str(value)`, anything else is drawn as-is, so images and arbitrary content
// work). Captions and step metadata stay keyed on `value`. `none` stands in
// for a missing child.
//
// Ties go LEFT: `insert(t, v)` with `v == node.value` descends left, so equal
// values are legal and land in the left subtree.
//
// step.kind vocabulary
// --------------------
//   static                     the one frame of `display`
//   init                       the opening frame of every animation
//   compare                    one comparison along a descent
//   found / not-found          how a search ended
//   inserted                   the new leaf has appeared
//   highlight / break          the deletion target, then its severed edges
//   descend / transfer         the walk to the in-order predecessor, and the
//                              value moving into the target's slot
//   pivots / restructure / connect     the three shape-changing rotation steps
//   visit                      one node of a traversal
//   settled                    terminal success of a mutation
// The final frame of every display carries `step.result` — the tree the
// operation produced (the unchanged input, for a search or traversal).

#import "../core/draw-util.typ": anchor
#import "../core/frame.typ": make-frames, make-renderer
#import "../core/snapshot.typ": (
  blank-snapshot, clear-notes, note-node, with-edge, with-node,
)
#import "../core/text.typ": alt-describe, alt-intro, alt-label
#import "../draw/tree.typ": draw-tree
#import "tree-common.typ" as tc
#import "tree-common.typ": (
  by-value, contains, in-order, level-order, path-to, post-order, pre-order,
  resolve,
)

#let _DS = "Binary search tree"

// ===================================================================
// Construction
// ===================================================================

/// A node holding `value`, with either no children (a leaf) or both — pass
/// `none` for a missing one.
///
/// ```typ
/// bst.node(8, bst.leaf(3), bst.node(10, none, bst.leaf(14)))
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
  /// What to draw in the node; `auto` draws `str(value)`.
  /// -> auto | any
  label: auto,
) = {
  let cs = children.pos()
  assert(
    cs.len() == 0 or cs.len() == 2,
    message: "bst.node: expected no children or exactly two (left, right), got "
      + str(cs.len())
      + ".",
  )
  (
    kind: "bst",
    value: value,
    label: label,
    left: cs.at(0, default: none),
    right: cs.at(1, default: none),
  )
}

/// A childless node — `node(value)` with the intent spelled out.
/// -> dictionary
#let leaf(
  /// The ordering key.
  /// -> int
  value,
  /// What to draw in the node; `auto` draws `str(value)`.
  /// -> auto | any
  label: auto,
) = node(value, label: label)

/// Insert `v`, returning a new tree. Ties descend left.
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
) = {
  if v <= tree.value {
    (
      ..tree,
      left: if tree.left == none {
        node(v, label: label)
      } else { insert(tree.left, v, label: label) },
    )
  } else {
    (
      ..tree,
      right: if tree.right == none {
        node(v, label: label)
      } else { insert(tree.right, v, label: label) },
    )
  }
}

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
) = tc.insert-many(tree, insert, vals.pos(), who: "bst.insert-many")

/// Build a tree from a list of values: the first becomes the root, the rest
/// are inserted in order. Each is a bare key or a `(value, label)` pair.
///
/// ```typ
/// bst.new(4, 1, 7, 3, 6, 8)
/// bst.new((4, [FOUR]), 1, 7, (6, [SIX]))
/// ```
///
/// -> dictionary
#let new(
  /// The values. At least one is required — it becomes the root.
  /// -> any
  ..vals,
) = {
  let xs = vals.pos()
  assert(xs.len() > 0, message: "bst.new: at least one value is required (the root).")
  let head = tc.parse-value(xs.first(), "bst.new")
  tc.insert-many(
    node(head.value, label: head.label),
    insert,
    xs.slice(1),
    who: "bst.new",
  )
}

// ===================================================================
// Pure operations
// ===================================================================

/// Delete `v`, returning a new tree (or `none` if the last node went). A node
/// with two children is replaced by its in-order predecessor — value *and*
/// label — which is then deleted from the left subtree.
/// -> dictionary | none
#let delete(
  /// The tree.
  /// -> dictionary
  tree,
  /// The ordering key to delete.
  /// -> int
  v,
) = {
  if v < tree.value {
    if tree.left == none { tree } else { (..tree, left: delete(tree.left, v)) }
  } else if v > tree.value {
    if tree.right == none { tree } else {
      (..tree, right: delete(tree.right, v))
    }
  } else if tree.left == none and tree.right == none {
    none
  } else if tree.left == none {
    tree.right
  } else if tree.right == none {
    tree.left
  } else {
    let find-max(n) = if n.right == none { n } else { find-max(n.right) }
    let pred = find-max(tree.left)
    (
      ..tree,
      value: pred.value,
      label: pred.label,
      left: delete(tree.left, pred.value),
    )
  }
}

// The path of every node on the walk to the in-order predecessor of the node
// at `target-path`: down into its left subtree, then right as far as it goes.
#let _predecessor-paths(tree, target-path) = {
  let walk(p) = {
    let n = resolve(tree, p)
    if n.right == none { (p,) } else { (p,) + walk(p + "R") }
  }
  walk(target-path + "L")
}

/// Rotate around `child` — anywhere in the tree, not only at the root.
/// `child` is located by searching for its value, so its parent and the
/// direction (left or right) are inferred.
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
    panic("bst.rotate: cannot rotate the root with itself.")
  }
  let parent-path = child-path.slice(0, child-path.len() - 1)
  let parent = resolve(tree, parent-path)
  let is-right = child-path.last() == "L"
  let rotated = if is-right {
    // child is the left child of parent -> right rotation
    (..child, right: (..parent, left: child.right))
  } else {
    // child is the right child of parent -> left rotation
    (..child, left: (..parent, right: child.left))
  }
  // Splice the rotated subtree back into the full tree.
  let replace-at(t, path, sub) = if path == "" {
    sub
  } else if path.first() == "L" {
    (..t, left: replace-at(t.left, path.slice(1), sub))
  } else {
    (..t, right: replace-at(t.right, path.slice(1), sub))
  }
  replace-at(tree, parent-path, rotated)
}

/// A recursive textual rendering of the tree, used in alt text.
/// -> str
#let describe(
  /// The tree.
  /// -> dictionary
  tree,
) = tc.describe(tree)

/// Check the search-tree ordering: an in-order walk must be non-decreasing
/// (ties descend left, so equal values are legal). Returns `true` or panics
/// naming the first violation.
/// -> bool
#let check-invariants(
  /// The tree.
  /// -> dictionary
  tree,
) = {
  let values = in-order(tree).map(p => resolve(tree, p).value)
  for i in range(1, values.len()) {
    assert(
      values.at(i - 1) <= values.at(i),
      message: "bst.check-invariants: in-order walk is not sorted — "
        + str(values.at(i - 1))
        + " precedes "
        + str(values.at(i))
        + ".",
    )
  }
  true
}

// ===================================================================
// Rendering
// ===================================================================

/// A `Renderer` over this tree, bound to the tree backend — the entry point
/// for driving an animation yourself with the `Op` command stream. Pass
/// `sticky: true` when you want each frame's styling to accumulate.
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
  node-style: node-style,
  edge-style: edge-style,
  sticky: sticky,
  theme: theme,
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

/// Animate searching for `v`: one frame per comparison along the search path,
/// each highlighting the visited node and drawing the comparison beside it.
/// The walk ends at a match, or where the search runs off the tree.
/// -> array
#let search-display(
  /// The tree.
  /// -> dictionary
  tree,
  /// The ordering key to search for.
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
  let steps = tc.search-walk(tree, v)
  let n = steps.len()

  // One shared closure builds every snapshot, each frame indexing into the
  // result; Typst memoizes the call, so the accumulation runs once.
  let build-all = th => {
    let cur = blank-snapshot()
    let out = (cur,)
    for s in steps {
      cur = with-node(cur, s.path, (stroke: th.op.search-stroke))
      cur = note-node(cur, s.path, s.cmp)
      out.push(cur)
    }
    out
  }

  let specs = (
    (
      structure: tree,
      build: _ => blank-snapshot(),
      caption: none,
      step: (kind: "init"),
      alt: alt-intro(_DS, describe(tree), "search for " + str(v)),
    ),
  )
  for (i, s) in steps.enumerate() {
    let at = i + 1
    let node-value = alt-label(resolve(tree, s.path))
    specs.push((
      structure: tree,
      build: th => build-all(th).at(at),
      caption: s.cmp,
      step: (
        kind: if s.found { "found" } else if at == n { "not-found" } else {
          "compare"
        },
        path: s.path,
        cmp: s.cmp,
        found: s.found,
        ..if at == n { (result: tree) },
      ),
      alt: if s.found {
        "Match found at node " + node-value + "."
      } else if at == n {
        ("Comparing "
          + s.cmp
          + " at node "
          + node-value
          + "; search ends here, "
          + str(v)
          + " is not in the tree.")
      } else {
        "Comparing " + s.cmp + " at node " + node-value + "; continuing search."
      },
    ))
  }
  _frames(specs, theme, node-style, edge-style)
}

/// Animate inserting `v`: the descent to the insertion point, then the new
/// leaf appearing on the grown tree.
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
  let steps = tc.insert-walk(tree, v)
  let after = insert(tree, v, label: label)
  let new-path = by-value(after, v)

  let build-a = th => {
    let cur = blank-snapshot()
    let out = (cur,)
    for s in steps {
      cur = with-node(cur, s.path, (stroke: th.op.search-stroke))
      cur = note-node(cur, s.path, s.cmp)
      out.push(cur)
    }
    out
  }

  let specs = (
    (
      structure: tree,
      build: _ => blank-snapshot(),
      caption: none,
      step: (kind: "init"),
      alt: alt-intro(_DS, describe(tree), "insert " + str(v)),
    ),
  )
  for (i, s) in steps.enumerate() {
    let at = i + 1
    let node-value = alt-label(resolve(tree, s.path))
    specs.push((
      structure: tree,
      build: th => build-a(th).at(at),
      caption: s.cmp,
      step: (kind: "compare", path: s.path, cmp: s.cmp),
      alt: if at == steps.len() {
        (
          "Comparing "
            + s.cmp
            + " at node "
            + node-value
            + "; insertion point found below this node."
        )
      } else {
        "Comparing " + s.cmp + " at node " + node-value + "; descending."
      },
    ))
  }

  // The search-path highlights carry onto the grown tree (without their
  // notes) at the same moment the new node appears — an intermediate
  // "appeared but not yet styled" frame added nothing.
  specs.push((
    structure: after,
    build: th => {
      let cur = blank-snapshot()
      for s in steps {
        cur = with-node(cur, s.path, (stroke: th.op.search-stroke))
      }
      cur = with-node(
        cur,
        new-path,
        (stroke: th.op.settled-stroke, fill: th.op.success-fill),
      )
      with-edge(cur, new-path, (stroke: th.op.success-stroke))
    },
    caption: [Inserted #v],
    step: (kind: "inserted", path: new-path, result: after),
    alt: "Inserted " + str(v) + " as a new leaf.",
  ))
  _frames(specs, theme, node-style, edge-style)
}

/// Animate deleting `v`, dispatching on the target's children:
///
/// - a leaf is highlighted, its edge dashed, then it is gone;
/// - a one-child node dashes both edges, vanishes, and its child reattaches;
/// - a two-child node descends to its in-order predecessor, transfers that
///   value into the target's slot, and settles.
///
/// With `search: true` the deletion is preceded by a search-style walk to the
/// target; those comparison notes are cleared on the first deletion frame so
/// they don't compete with the deletion highlights.
/// -> array
#let delete-display(
  /// The tree.
  /// -> dictionary
  tree,
  /// The ordering key to delete.
  /// -> int
  v,
  /// Whether to precede the deletion with the walk to the target.
  /// -> bool
  search: false,
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
  let target-path = by-value(tree, v)
  let target = resolve(tree, target-path)
  let target-label = alt-label(target)
  let after = delete(tree, v)

  // `by-value` has already confirmed `v` is present, so this walk always
  // terminates at the match.
  let search-steps = if search { tc.descend-walk(tree, v) } else { () }
  let is-leaf = target.left == none and target.right == none
  let is-one-child = (
    (not is-leaf) and (target.left == none or target.right == none)
  )

  let specs = (
    (
      structure: tree,
      build: _ => blank-snapshot(),
      caption: none,
      step: (kind: "init"),
      alt: alt-intro(_DS, describe(tree), "delete " + target-label),
    ),
  )

  // Phase A — everything drawn on the *original* tree. `build-a` accumulates
  // the whole phase's snapshots once; each frame indexes into it. Each step
  // starts from the previous snapshot, so the styling is cumulative.
  let build-a = th => {
    let cur = blank-snapshot()
    let out = (cur,)
    for s in search-steps {
      cur = note-node(
        with-node(cur, s.path, (stroke: th.op.search-stroke)),
        s.path,
        s.cmp,
      )
      out.push(cur)
    }
    if is-leaf {
      cur = with-node(cur, target-path, (stroke: th.op.attention-stroke))
      // The comparison notes have done their job; clear them so they don't
      // compete with the deletion highlights.
      if search { cur = clear-notes(cur) }
      out.push(cur)
      cur = with-edge(cur, target-path, (stroke: th.op.danger-stroke))
      out.push(cur)
    } else if is-one-child {
      let child-path = target-path + (if target.left != none { "L" } else { "R" })
      cur = with-node(cur, target-path, (stroke: th.op.attention-stroke))
      if search { cur = clear-notes(cur) }
      cur = with-node(cur, child-path, (stroke: th.op.search-stroke))
      out.push(cur)
      cur = with-edge(cur, target-path, (stroke: th.op.danger-stroke))
      cur = with-edge(cur, child-path, (stroke: th.op.danger-stroke))
      out.push(cur)
      cur = with-edge(cur, target-path, (hide: true))
      cur = with-edge(cur, child-path, (hide: true))
      cur = with-node(cur, target-path, (hide: true))
      out.push(cur)
    } else {
      cur = with-node(cur, target-path, (stroke: th.op.attention-stroke))
      if search { cur = clear-notes(cur) }
      out.push(cur)
      for p in _predecessor-paths(tree, target-path) {
        cur = with-node(cur, p, (stroke: th.op.search-stroke))
        out.push(cur)
      }
      cur = note-node(
        cur,
        target-path,
        "← " + str(resolve(tree, _predecessor-paths(tree, target-path).last()).value),
      )
      out.push(cur)
    }
    out
  }

  // Phase A metadata, in the same order `build-a` pushes.
  let meta-a = ()
  for s in search-steps {
    let node-value = alt-label(resolve(tree, s.path))
    meta-a.push((
      caption: s.cmp,
      step: (kind: "compare", path: s.path, cmp: s.cmp, found: s.found),
      alt: if s.found {
        "Found target node " + node-value + "; ready to delete."
      } else {
        "Comparing " + s.cmp + " at node " + node-value + "; descending."
      },
    ))
  }
  if is-leaf {
    meta-a.push((
      caption: [Delete #v],
      step: (kind: "highlight", path: target-path),
      alt: "Marked leaf node " + target-label + " for deletion.",
    ))
    meta-a.push((
      caption: [Remove edge],
      step: (kind: "break", path: target-path),
      alt: "Removing the edge to node " + target-label + ".",
    ))
  } else if is-one-child {
    let child-path = target-path + (if target.left != none { "L" } else { "R" })
    let child-value = alt-label(resolve(tree, child-path))
    meta-a.push((
      caption: [Delete #v],
      step: (kind: "highlight", path: target-path, child: child-path),
      alt: "Marked node "
        + target-label
        + " for deletion; its single child "
        + child-value
        + " will be promoted.",
    ))
    meta-a.push((
      caption: [Mark edges to remove],
      step: (kind: "break", paths: (target-path, child-path)),
      alt: "Marking edges around node " + target-label + " for removal.",
    ))
    meta-a.push((
      caption: [Remove],
      step: (kind: "break", paths: (target-path, child-path), hidden: true),
      alt: "Removed node " + target-label + " and its edges.",
    ))
  } else {
    let predecessor-paths = _predecessor-paths(tree, target-path)
    let predecessor-node = resolve(tree, predecessor-paths.last())
    meta-a.push((
      caption: [Delete #v],
      step: (kind: "highlight", path: target-path),
      alt: "Marked node "
        + target-label
        + " for deletion; it has two children, so an in-order predecessor "
        + "will replace it.",
    ))
    for p in predecessor-paths {
      meta-a.push((
        caption: [Find predecessor],
        step: (kind: "descend", path: p),
        alt: "Descending into the left subtree at node "
          + alt-label(resolve(tree, p))
          + ".",
      ))
    }
    meta-a.push((
      caption: [Transfer #predecessor-node.value],
      step: (
        kind: "transfer",
        from: predecessor-paths.last(),
        to: target-path,
        value: predecessor-node.value,
      ),
      alt: "Replacing "
        + target-label
        + " with predecessor value "
        + alt-label(predecessor-node)
        + ".",
    ))
  }
  for (i, m) in meta-a.enumerate() {
    let at = i + 1
    specs.push((
      structure: tree,
      build: th => build-a(th).at(at),
      caption: m.caption,
      step: m.step,
      alt: m.alt,
    ))
  }

  // Phase B — one settle frame on the tree the deletion produced.
  let settle = if is-leaf {
    (
      build: _ => blank-snapshot(),
      caption: [Done],
      step: (kind: "settled", result: after),
      alt: "Deletion of " + target-label + " complete.",
    )
  } else if is-one-child {
    (
      build: th => with-edge(
        with-node(blank-snapshot(), target-path, (stroke: th.op.search-stroke)),
        target-path,
        (stroke: th.op.success-stroke),
      ),
      caption: [Reattach],
      step: (kind: "settled", path: target-path, result: after),
      alt: "Child reattached in place of " + target-label + "; deletion complete.",
    )
  } else {
    (
      build: th => with-node(
        blank-snapshot(),
        target-path,
        (stroke: th.op.settled-stroke, fill: th.op.success-fill),
      ),
      caption: [Done],
      step: (kind: "settled", path: target-path, result: after),
      alt: "Deletion of "
        + target-label
        + " complete; node now holds "
        + alt-label(resolve(after, target-path))
        + ".",
    )
  }
  specs.push((structure: after, ..settle))
  _frames(specs, theme, node-style, edge-style)
}

/// Animate a rotation around `child` — anywhere in the tree, not only at the
/// root. `child` is the node that should become the new subtree root; its
/// parent and the direction are inferred from the search path.
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
  let child-path = by-value(tree, child.value)
  if child-path == "" {
    panic(
      "bst.rotate-display: cannot rotate around root node "
        + str(child.value)
        + "; the child must have a parent.",
    )
  }
  let parent-path = child-path.slice(0, child-path.len() - 1)
  let parent-subtree = resolve(tree, parent-path)
  let is-right = child-path.last() == "L"
  let after = rotate(tree, child)

  // For a non-root rotation the grandparent-to-subtree edge (whose path is
  // `parent-path` itself) must break and reconnect too — otherwise the new
  // subtree root visibly snaps onto the grandparent without animating.
  let has-grandparent = parent-path != ""

  // BEFORE paths: the middle child of `child`, which moves to the parent.
  let middle-path = parent-path + (if is-right { "LR" } else { "RL" })
  let has-middle = resolve(tree, middle-path) != none
  let broken-paths = (
    (if has-grandparent { (parent-path,) } else { () })
      + (child-path,)
      + (if has-middle { (middle-path,) } else { () })
  )

  // AFTER paths.
  let new-parent-path = parent-path + (if is-right { "R" } else { "L" })
  let new-middle-path = parent-path + (if is-right { "RL" } else { "LR" })
  let has-new-middle = resolve(after, new-middle-path) != none
  let new-edge-paths = (
    (if has-grandparent { (parent-path,) } else { () })
      + (new-parent-path,)
      + (if has-new-middle { (new-middle-path,) } else { () })
  )

  let direction = if is-right { "right" } else { "left" }
  let parent-value = alt-label(parent-subtree)
  let child-value = alt-label(child)

  // Phase A — on the tree as it stands.
  let build-a = th => {
    let cur = blank-snapshot()
    let out = (cur,)
    cur = with-node(cur, parent-path, (stroke: th.op.attention-stroke))
    cur = with-node(cur, child-path, (stroke: th.op.attention-stroke))
    out.push(cur)
    cur = with-edge(cur, child-path, (hide: true))
    if has-middle { cur = with-edge(cur, middle-path, (hide: true)) }
    if has-grandparent { cur = with-edge(cur, parent-path, (hide: true)) }
    out.push(cur)
    out
  }

  // Phase B — on the rotated tree. Its first frame is already styled (the
  // pivots stay lit and the moved edges stay hidden), so the restructure
  // reads as one continuous motion.
  let build-b = th => {
    let cur = blank-snapshot()
    cur = with-node(cur, parent-path, (stroke: th.op.attention-stroke))
    cur = with-node(cur, new-parent-path, (stroke: th.op.attention-stroke))
    cur = with-edge(cur, new-parent-path, (hide: true))
    if has-new-middle { cur = with-edge(cur, new-middle-path, (hide: true)) }
    if has-grandparent { cur = with-edge(cur, parent-path, (hide: true)) }
    let out = (cur,)
    cur = with-edge(
      cur,
      new-parent-path,
      (stroke: th.op.success-stroke, hide: false),
    )
    if has-new-middle {
      cur = with-edge(
        cur,
        new-middle-path,
        (stroke: th.op.success-stroke, hide: false),
      )
    }
    if has-grandparent {
      cur = with-edge(
        cur,
        parent-path,
        (stroke: th.op.success-stroke, hide: false),
      )
    }
    out.push(cur)
    // Reset to the theme's reset stroke, which should read as unstyled.
    cur = with-node(cur, parent-path, (stroke: th.op.reset-stroke))
    cur = with-node(cur, new-parent-path, (stroke: th.op.reset-stroke))
    cur = with-edge(cur, new-parent-path, (stroke: th.op.reset-stroke))
    if has-new-middle {
      cur = with-edge(cur, new-middle-path, (stroke: th.op.reset-stroke))
    }
    if has-grandparent {
      cur = with-edge(cur, parent-path, (stroke: th.op.reset-stroke))
    }
    out.push(cur)
    out
  }

  let specs = (
    (
      structure: tree,
      build: _ => blank-snapshot(),
      caption: none,
      step: (kind: "init"),
      alt: alt-intro(
        _DS,
        describe(tree),
        direction + "-rotate around node " + child-value,
      ),
    ),
    (
      structure: tree,
      build: th => build-a(th).at(1),
      caption: [Rotate around #child.value],
      step: (kind: "pivots", paths: (parent-path, child-path)),
      alt: "Rotation pivots identified: parent "
        + parent-value
        + " and child "
        + child-value
        + ".",
    ),
    (
      structure: tree,
      build: th => build-a(th).at(2),
      caption: [Break edges],
      step: (kind: "break", paths: broken-paths),
      alt: "Breaking the edges that will rotate.",
    ),
    (
      structure: after,
      build: th => build-b(th).at(0),
      caption: [Restructure tree],
      step: (kind: "restructure"),
      alt: "Tree restructured: "
        + child-value
        + " is now the parent of "
        + parent-value
        + "; the rotated edges are still hidden.",
    ),
    (
      structure: after,
      build: th => build-b(th).at(1),
      caption: [Reconnect edges],
      step: (kind: "connect", paths: new-edge-paths),
      alt: "Reconnecting rotated edges.",
    ),
    (
      structure: after,
      build: th => build-b(th).at(2),
      caption: none,
      step: (kind: "settled", result: after),
      alt: "Rotation complete.",
    ),
  )
  _frames(specs, theme, node-style, edge-style)
}

// ===================================================================
// Traversals
// ===================================================================
//
// One frame per visit: the visited node is filled from the theme's
// `traversal-palette` and badged with its position, and the running output
// accumulates in the caption. The final frame wears the whole traversal's
// colour signature, so `last`-rendering all four gives the compare-the-
// traversals view.

#let _traversal(tree, paths, name, node-style, edge-style, theme) = tc.render-traversal(
  tree,
  paths,
  name,
  _DS,
  describe(tree),
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

/// Animate a pre-order (root, left, right) traversal.
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

/// Animate a post-order (left, right, root) traversal.
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
