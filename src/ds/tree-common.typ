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

#import "../core/frame.typ": make-frames
#import "../core/snapshot.typ": blank-snapshot, with-node
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

// A readable text fill for a given background, from its oklab lightness —
// so a value stays legible against any point of the traversal gradient.
#let _text-fill-for(bg) = {
  let l = bg.oklab().components().first()
  if l < 60% { white } else { black }
}

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
        (fill: fill, text-fill: _text-fill-for(fill), note: str(i + 1)),
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
