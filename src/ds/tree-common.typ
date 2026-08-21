// Shared binary-tree machinery.
//
// BST, RBT, and AVL are the same tree with different invariants: the same
// L/R paths, the same descent, the same traversals, the same prose. Everything
// that doesn't depend on which of the three it is lives here, so each module
// is left holding only its own algorithm.
//
// Every function takes the node as its first positional argument and returns a
// value — there is no state and no self. A "node" is any dict with `value`,
// `label`, `left`, and `right`; `none` stands in for a missing child. The
// per-DS extras (`red` on an RBT node, `height` on an AVL one) are carried
// along untouched by the walks here, which never construct nodes.
//
// B24 and the trie are n-ary and keep their own path utilities.

#import "../core/draw-util.typ": text-fill-for
#import "../core/frame.typ": make-frames
#import "../core/snapshot.typ": blank-snapshot, note-node, with-edge, with-node
#import "../core/text.typ": alt-intro, alt-label
#import "../draw/tree.typ": draw-tree

// ===================================================================
// Construction input
// ===================================================================

/// Parse one factory argument into a `(value, label)` pair: either a bare
/// ordering value (label `auto`, so the backend draws `str(value)`) or an
/// explicit `(value, label)` 2-tuple. `who` names the caller in errors.
///
/// -> dictionary
#let parse-value(x, who) = if type(x) == array {
  assert(
    x.len() == 2,
    message: who + ": expected a (value, label) 2-tuple, got " + repr(x) + ".",
  )
  (value: x.at(0), label: x.at(1))
} else {
  (value: x, label: auto)
}

/// Fold `insert` over a list of factory arguments (bare values or
/// `(value, label)` pairs), returning the grown tree.
///
/// -> dictionary
#let insert-many(tree, insert, vals, who: "insert-many") = {
  let out = tree
  for x in vals {
    let p = parse-value(x, who)
    out = insert(out, p.value, label: p.label)
  }
  out
}

// ===================================================================
// Paths
// ===================================================================

/// The L/R path of the node holding `v`. Panics when `v` is absent.
///
/// -> str
#let by-value(tree, v) = {
  let walk(node, path) = {
    if node == none {
      panic("by-value: value not found in tree: " + repr(v) + ".")
    } else if v == node.value {
      path
    } else if v < node.value {
      walk(node.left, path + "L")
    } else {
      walk(node.right, path + "R")
    }
  }
  walk(tree, "")
}

/// Every path visited while searching for `v`, ending at the node holding it.
/// Panics when `v` is absent.
///
/// -> array
#let path-to(tree, v) = {
  let walk(node, path) = {
    if node == none {
      panic("path-to: value not found in tree: " + repr(v) + ".")
    } else if v == node.value {
      (path,)
    } else if v < node.value {
      (path,) + walk(node.left, path + "L")
    } else {
      (path,) + walk(node.right, path + "R")
    }
  }
  walk(tree, "")
}

/// The subtree at an L/R path, or `none` when the path runs off a missing
/// child.
///
/// -> dictionary | none
#let resolve(tree, path) = {
  let walk(node, cps) = {
    if node == none or cps.len() == 0 {
      node
    } else if cps.first() == "L" {
      walk(node.left, cps.slice(1))
    } else {
      walk(node.right, cps.slice(1))
    }
  }
  walk(tree, path.codepoints())
}

/// Whether `v` is in the tree.
///
/// -> bool
#let contains(tree, v) = {
  if tree == none {
    false
  } else if v == tree.value {
    true
  } else if v < tree.value {
    contains(tree.left, v)
  } else {
    contains(tree.right, v)
  }
}

// ===================================================================
// Traversals
// ===================================================================

/// The paths of every node, in left-root-right order.
/// -> array
#let in-order(tree) = {
  let walk(node, path) = if node == none { () } else {
    walk(node.left, path + "L") + (path,) + walk(node.right, path + "R")
  }
  walk(tree, "")
}

/// The paths of every node, in root-left-right order.
/// -> array
#let pre-order(tree) = {
  let walk(node, path) = if node == none { () } else {
    (path,) + walk(node.left, path + "L") + walk(node.right, path + "R")
  }
  walk(tree, "")
}

/// The paths of every node, in left-right-root order.
/// -> array
#let post-order(tree) = {
  let walk(node, path) = if node == none { () } else {
    walk(node.left, path + "L") + walk(node.right, path + "R") + (path,)
  }
  walk(tree, "")
}

/// The paths of every node, breadth-first.
/// -> array
#let level-order(tree) = {
  let out = ()
  let queue = ("",)
  while queue.len() > 0 {
    let path = queue.first()
    queue = queue.slice(1)
    if resolve(tree, path) != none {
      out.push(path)
      queue.push(path + "L")
      queue.push(path + "R")
    }
  }
  out
}

// ===================================================================
// Prose
// ===================================================================

/// A recursive textual rendering of the tree, for alt text.
///
/// `head` builds one node's own description; the recursion and the
/// `(left: .., right: ..)` framing are shared. RBT passes a `head` that
/// appends the colour, AVL one that appends the height.
///
/// -> str
#let describe(tree, head: alt-label) = {
  let walk(node) = {
    let h = head(node)
    if node.left == none and node.right == none {
      h
    } else {
      let l = if node.left == none { "empty" } else { walk(node.left) }
      let r = if node.right == none { "empty" } else { walk(node.right) }
      h + " (left: " + l + ", right: " + r + ")"
    }
  }
  walk(tree)
}

/// The comparison shown beside a node during a walk: `"7 < 8"`, `"7 = 7"`.
/// -> str
#let cmp-string(v, node-value) = {
  let op = if v == node-value { " = " } else if v < node-value { " < " } else {
    " > "
  }
  str(v) + op + str(node-value)
}

// ===================================================================
// Descent walks
// ===================================================================
//
// Three walks, one per operation, each returning an array of
// `(path, cmp, ..)` steps. They differ in where they stop, which is the
// whole point: a search stops when the tree runs out, an insert stops at the
// slot it will fill, and a delete's search prefix knows the target is there.

/// The comparisons a *search* for `v` makes: descend while the matching child
/// exists, stopping at a match or where the search runs off the tree.
///
/// -> array
#let search-walk(tree, v) = {
  let walk(node, path) = {
    let step = (
      path: path,
      cmp: cmp-string(v, node.value),
      found: v == node.value,
    )
    if v == node.value or (node.left == none and node.right == none) {
      (step,)
    } else if v < node.value and node.left != none {
      (step,) + walk(node.left, path + "L")
    } else if v > node.value and node.right != none {
      (step,) + walk(node.right, path + "R")
    } else { (step,) }
  }
  walk(tree, "")
}

/// The comparisons an *insert* of `v` makes. Ties go left (matching
/// `insert`), and the walk ends on the node that will get the new child.
///
/// -> array
#let insert-walk(tree, v) = {
  let walk(node, path) = {
    let step = (path: path, cmp: cmp-string(v, node.value))
    if v <= node.value and node.left != none {
      (step,) + walk(node.left, path + "L")
    } else if v > node.value and node.right != none {
      (step,) + walk(node.right, path + "R")
    } else { (step,) }
  }
  walk(tree, "")
}

/// The comparisons made descending to a value already known to be present —
/// the search prefix of a delete.
///
/// -> array
#let descend-walk(tree, v) = {
  let walk(node, path) = {
    let step = (
      path: path,
      cmp: cmp-string(v, node.value),
      found: v == node.value,
    )
    if v == node.value {
      (step,)
    } else if v < node.value {
      (step,) + walk(node.left, path + "L")
    } else {
      (step,) + walk(node.right, path + "R")
    }
  }
  walk(tree, "")
}

// ===================================================================
// Traversal animation
// ===================================================================

/// Animate a traversal: one frame per visit, the visited node filled from the
/// theme's `traversal-palette` and badged with its 1-indexed position, the
/// running output accumulating in the caption. The final frame wears the whole
/// traversal's colour signature, so `last`-rendering four of these gives the
/// compare-the-traversals view.
///
/// `step.kind` is `"init"` on the opening frame and `"visit"` thereafter; the
/// final frame carries `step.result` (the unchanged tree).
///
/// `base` is the DS's structural painting — `(theme) => snapshot` — laid down
/// before the traversal highlights. AVL passes the balance-factor and height
/// tags through it; BST has none.
///
/// -> array
#let render-traversal(
  tree,
  paths,
  name,
  ds-name,
  describe-text,
  base: none,
  node-style: (:),
  edge-style: (:),
  theme: (:),
) = {
  let n = paths.len()
  let specs = (
    (
      structure: tree,
      build: th => if base == none { blank-snapshot() } else { base(th) },
      caption: none,
      step: (kind: "init", ..if n == 0 { (result: tree) }),
      alt: alt-intro(ds-name, describe-text, "traverse " + name),
    ),
  )

  // One shared closure builds every snapshot; each frame then indexes into
  // the result. Typst memoizes the call, so an n-frame traversal costs one
  // accumulation pass rather than n of them.
  let build-all = th => {
    let g = gradient.linear(..th.op.traversal-palette)
    let cur = if base == none { blank-snapshot() } else { base(th) }
    let out = (cur,)
    for (i, p) in paths.enumerate() {
      let t = if n <= 1 { 0% } else { (i / (n - 1)) * 100% }
      let fill = g.sample(t)
      cur = with-node(
        cur,
        p,
        (fill: fill, text-fill: text-fill-for(fill), note: str(i + 1)),
      )
      out.push(cur)
    }
    out
  }

  let output = ()
  for (i, p) in paths.enumerate() {
    let node = resolve(tree, p)
    let disp = alt-label(node)
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
        value: node.value,
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

  make-frames(
    specs,
    draw-tree,
    theme: theme,
    node-style: node-style,
    edge-style: edge-style,
  )
}

// ===================================================================
// Search animation
// ===================================================================

/// Animate a search for `v`: one frame per comparison along the search path,
/// each ringing the visited node in the theme's `search-stroke` and drawing
/// the comparison beside it. The walk ends at a match, or where the search
/// runs off the tree.
///
/// `base` is the DS's structural painting — `(theme) => snapshot` — laid down
/// beneath the search highlights (the RBT palette, AVL's factor and height
/// tags); `none` leaves the tree unpainted, which is the BST case.
///
/// `step.kind` is `"init"` on the opening frame, `"compare"` along the way,
/// and `"found"` / `"not-found"` on the last one; that frame also carries
/// `step.result` (the unchanged tree).
///
/// -> array
#let render-search(
  tree,
  v,
  ds-name,
  describe-text,
  base: none,
  node-style: (:),
  edge-style: (:),
  theme: (:),
) = {
  let steps = search-walk(tree, v)
  let n = steps.len()

  // One shared closure builds every snapshot, each frame indexing into the
  // result; Typst memoizes the call, so the accumulation runs once.
  let build-all = th => {
    let cur = if base == none { blank-snapshot() } else { base(th) }
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
      build: th => build-all(th).at(0),
      caption: none,
      step: (kind: "init"),
      alt: alt-intro(ds-name, describe-text, "search for " + str(v)),
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

  make-frames(
    specs,
    draw-tree,
    theme: theme,
    node-style: node-style,
    edge-style: edge-style,
  )
}

// ===================================================================
// Rotation animation
// ===================================================================

// The paths a rotation touches, on the tree before and the tree after.
// `child-path`'s last character says which way the subtree leans: an `L`
// child becomes the new root by rotating right.
#let _rotate-paths(tree, after, child-path) = {
  let parent = child-path.slice(0, child-path.len() - 1)
  let is-right = child-path.last() == "L"

  // For a non-root rotation the grandparent-to-subtree edge (whose path is
  // `parent` itself) must break and reconnect too — otherwise the new
  // subtree root visibly snaps onto the grandparent without animating.
  let has-grandparent = parent != ""

  // BEFORE: the middle child of `child`, which moves to the parent.
  let middle = parent + (if is-right { "LR" } else { "RL" })
  let has-middle = resolve(tree, middle) != none

  // AFTER.
  let new-parent = parent + (if is-right { "R" } else { "L" })
  let new-middle = parent + (if is-right { "RL" } else { "LR" })
  let has-new-middle = resolve(after, new-middle) != none

  let grandparent = if has-grandparent { (parent,) } else { () }
  (
    parent: parent,
    child: child-path,
    is-right: is-right,
    has-grandparent: has-grandparent,
    middle: middle,
    has-middle: has-middle,
    new-parent: new-parent,
    new-middle: new-middle,
    has-new-middle: has-new-middle,
    broken: (
      grandparent + (child-path,) + (if has-middle { (middle,) } else { () })
    ),
    reconnected: (
      grandparent
        + (new-parent,)
        + (if has-new-middle { (new-middle,) } else { () })
    ),
  )
}

// Phase A — on the tree as it stands: the pivots light up, then the edges
// that will move go dark.
#let _rotate-build-before(p, base) = th => {
  let cur = if base == none { blank-snapshot() } else { base(th) }
  let out = (cur,)
  cur = with-node(cur, p.parent, (stroke: th.op.attention-stroke))
  cur = with-node(cur, p.child, (stroke: th.op.attention-stroke))
  out.push(cur)
  cur = with-edge(cur, p.child, (hide: true))
  if p.has-middle { cur = with-edge(cur, p.middle, (hide: true)) }
  if p.has-grandparent { cur = with-edge(cur, p.parent, (hide: true)) }
  out.push(cur)
  out
}

// Phase B — on the rotated tree. Its first snapshot is already styled (the
// pivots stay lit and the moved edges stay hidden), so the restructure reads
// as one continuous motion; then the edges reconnect and the highlights
// clear.
#let _rotate-build-after(p, base) = th => {
  let cur = if base == none { blank-snapshot() } else { base(th) }
  cur = with-node(cur, p.parent, (stroke: th.op.attention-stroke))
  cur = with-node(cur, p.new-parent, (stroke: th.op.attention-stroke))
  cur = with-edge(cur, p.new-parent, (hide: true))
  if p.has-new-middle { cur = with-edge(cur, p.new-middle, (hide: true)) }
  if p.has-grandparent { cur = with-edge(cur, p.parent, (hide: true)) }
  let out = (cur,)

  let connect = (s, path) => with-edge(
    s,
    path,
    (stroke: th.op.success-stroke, hide: false),
  )
  cur = connect(cur, p.new-parent)
  if p.has-new-middle { cur = connect(cur, p.new-middle) }
  if p.has-grandparent { cur = connect(cur, p.parent) }
  out.push(cur)

  // Reset to the theme's reset stroke, which should read as unstyled.
  cur = with-node(cur, p.parent, (stroke: th.op.reset-stroke))
  cur = with-node(cur, p.new-parent, (stroke: th.op.reset-stroke))
  cur = with-edge(cur, p.new-parent, (stroke: th.op.reset-stroke))
  if p.has-new-middle {
    cur = with-edge(cur, p.new-middle, (stroke: th.op.reset-stroke))
  }
  if p.has-grandparent {
    cur = with-edge(cur, p.parent, (stroke: th.op.reset-stroke))
  }
  out.push(cur)
  out
}

/// Animate a rotation around `child` — anywhere in the tree, not only at the
/// root. `child` is the node that should become the new subtree root; its
/// parent and the direction are inferred from the search path. `after` is the
/// rotated tree, which the caller produces with its own `rotate` (AVL's
/// recomputes heights, BST's does not).
///
/// Six frames: the pivots are marked, the edges that will move are broken,
/// the tree restructures with those edges still hidden, they reconnect, and
/// the highlights clear. `step.kind` runs `"init"`, `"pivots"`, `"break"`,
/// `"restructure"`, `"connect"`, `"settled"`; the last carries `step.result`.
///
/// `base` is the DS's structural painting — `(theme) => snapshot` — laid down
/// beneath the rotation highlights, the same hook `render-search` takes.
/// `after-base` is the same for the rotated tree, which a DS whose painting
/// depends on the shape needs (AVL's heights move with the pivot); `auto`
/// reuses `base`.
///
/// -> array
#let render-rotate(
  tree,
  after,
  child,
  ds-name,
  describe-text,
  who: "rotate-display",
  base: none,
  after-base: auto,
  node-style: (:),
  edge-style: (:),
  theme: (:),
) = {
  let child-path = by-value(tree, child.value)
  if child-path == "" {
    panic(
      who
        + ": cannot rotate around root node "
        + str(child.value)
        + "; the child must have a parent.",
    )
  }
  let p = _rotate-paths(tree, after, child-path)
  let before = _rotate-build-before(p, base)
  let rotated = _rotate-build-after(
    p,
    if after-base == auto { base } else { after-base },
  )

  let direction = if p.is-right { "right" } else { "left" }
  let parent-value = alt-label(resolve(tree, p.parent))
  let child-value = alt-label(child)

  make-frames(
    (
      (
        structure: tree,
        build: th => before(th).at(0),
        caption: none,
        step: (kind: "init"),
        alt: alt-intro(
          ds-name,
          describe-text,
          direction + "-rotate around node " + child-value,
        ),
      ),
      (
        structure: tree,
        build: th => before(th).at(1),
        caption: [Rotate around #child.value],
        step: (kind: "pivots", paths: (p.parent, p.child)),
        alt: ("Rotation pivots identified: parent "
          + parent-value
          + " and child "
          + child-value
          + "."),
      ),
      (
        structure: tree,
        build: th => before(th).at(2),
        caption: [Break edges],
        step: (kind: "break", paths: p.broken),
        alt: "Breaking the edges that will rotate.",
      ),
      (
        structure: after,
        build: th => rotated(th).at(0),
        caption: [Restructure tree],
        step: (kind: "restructure"),
        alt: ("Tree restructured: "
          + child-value
          + " is now the parent of "
          + parent-value
          + "; the rotated edges are still hidden."),
      ),
      (
        structure: after,
        build: th => rotated(th).at(1),
        caption: [Reconnect edges],
        step: (kind: "connect", paths: p.reconnected),
        alt: "Reconnecting rotated edges.",
      ),
      (
        structure: after,
        build: th => rotated(th).at(2),
        caption: none,
        step: (kind: "settled", result: after),
        alt: "Rotation complete.",
      ),
    ),
    draw-tree,
    theme: theme,
    node-style: node-style,
    edge-style: edge-style,
  )
}

// ===================================================================
// Result stamping
// ===================================================================

/// Stamp `step.result` onto the last spec in `specs` — the post-operation
/// structure a display's final frame carries, so a caller can advance their
/// variable from the frames instead of writing the operation twice.
///
/// -> array
#let stamp-result(specs, after) = {
  assert(
    specs.len() > 0,
    message: "stamp-result: a display always produces at least one frame.",
  )
  let out = specs
  let i = out.len() - 1
  let s = out.at(i)
  out.at(i) = (..s, step: (..s.at("step", default: (:)), result: after))
  out
}
