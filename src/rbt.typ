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

// Okasaki's balance — under a black parent, fix one of the four
// red-red violations by promoting the middle key to a red parent
// whose two children are recolored black. Any other shape is returned
// unchanged.
#let _balance(cls, red, l, v, lab, r) = if not red and _is-red(l) and _is-red(l.left) {
  _node(
    cls,
    true,
    _node(cls, false, l.left.left, l.left.value, l.left.label, l.left.right),
    l.value,
    l.label,
    _node(cls, false, l.right, v, lab, r),
  )
} else if not red and _is-red(l) and _is-red(l.right) {
  _node(
    cls,
    true,
    _node(cls, false, l.left, l.value, l.label, l.right.left),
    l.right.value,
    l.right.label,
    _node(cls, false, l.right.right, v, lab, r),
  )
} else if not red and _is-red(r) and _is-red(r.left) {
  _node(
    cls,
    true,
    _node(cls, false, l, v, lab, r.left.left),
    r.left.value,
    r.left.label,
    _node(cls, false, r.left.right, r.value, r.label, r.right),
  )
} else if not red and _is-red(r) and _is-red(r.right) {
  _node(
    cls,
    true,
    _node(cls, false, l, v, lab, r.left),
    r.value,
    r.label,
    _node(
      cls,
      false,
      r.right.left,
      r.right.value,
      r.right.label,
      r.right.right,
    ),
  )
} else {
  _node(cls, red, l, v, lab, r)
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

// balleft — fix-up after the left subtree's black-height was shortened
// by one. Three cases:
//   l red                — recolor l black, wrap with a red root
//   l black, r black     — redden r and balance
//   l black, r red       — r.left is black by RB invariants; restructure
#let _balleft(cls, l, v, lab, r) = if _is-red(l) {
  _node(
    cls,
    true,
    _node(cls, false, l.left, l.value, l.label, l.right),
    v,
    lab,
    r,
  )
} else if _is-black(r) {
  _balance(cls, false, l, v, lab, _redden(cls, r))
} else if _is-red(r) {
  _node(
    cls,
    true,
    _node(cls, false, l, v, lab, r.left.left),
    r.left.value,
    r.left.label,
    _balance(cls, false, r.left.right, r.value, r.label, _redden(cls, r.right)),
  )
} else {
  panic("balleft: unexpected case (r is none)")
}

// Symmetric: right subtree shortened.
#let _balright(cls, l, v, lab, r) = if _is-red(r) {
  _node(
    cls,
    true,
    l,
    v,
    lab,
    _node(cls, false, r.left, r.value, r.label, r.right),
  )
} else if _is-black(l) {
  _balance(cls, false, _redden(cls, l), v, lab, r)
} else if _is-red(l) {
  _node(
    cls,
    true,
    _balance(cls, false, _redden(cls, l.left), l.value, l.label, l.right.left),
    l.right.value,
    l.right.label,
    _node(cls, false, l.right.right, v, lab, r),
  )
} else {
  panic("balright: unexpected case (l is none)")
}

// "Glue" the left and right subtrees of a deleted internal node into
// a single subtree with the same black height as the original pair.
#let _app(cls, a, b) = if a == none {
  b
} else if b == none {
  a
} else if a.red and b.red {
  let bc = _app(cls, a.right, b.left)
  if _is-red(bc) {
    _node(
      cls,
      true,
      _node(cls, true, a.left, a.value, a.label, bc.left),
      bc.value,
      bc.label,
      _node(cls, true, bc.right, b.value, b.label, b.right),
    )
  } else {
    _node(
      cls,
      true,
      a.left,
      a.value,
      a.label,
      _node(cls, true, bc, b.value, b.label, b.right),
    )
  }
} else if not a.red and not b.red {
  let bc = _app(cls, a.right, b.left)
  if _is-red(bc) {
    _node(
      cls,
      true,
      _node(cls, false, a.left, a.value, a.label, bc.left),
      bc.value,
      bc.label,
      _node(cls, false, bc.right, b.value, b.label, b.right),
    )
  } else {
    _balleft(
      cls,
      a.left,
      a.value,
      a.label,
      _node(cls, false, bc, b.value, b.label, b.right),
    )
  }
} else if not a.red and b.red {
  // a black, b red — descend into b's left.
  _node(cls, true, _app(cls, a, b.left), b.value, b.label, b.right)
} else {
  // a red, b black — descend into a's right.
  _node(cls, true, a.left, a.value, a.label, _app(cls, a.right, b))
}

// Recursive delete. Caller must guarantee v lives in node's subtree;
// the public `delete` method enforces this with a `contains` precheck.
#let _del(cls, node, v) = if node == none {
  none
} else if v < node.value {
  let new-l = _del(cls, node.left, v)
  if _is-black(node.left) {
    _balleft(cls, new-l, node.value, node.label, node.right)
  } else {
    _node(cls, true, new-l, node.value, node.label, node.right)
  }
} else if v > node.value {
  let new-r = _del(cls, node.right, v)
  if _is-black(node.right) {
    _balright(cls, node.left, node.value, node.label, new-r)
  } else {
    _node(cls, true, node.left, node.value, node.label, new-r)
  }
} else {
  _app(cls, node.left, node.right)
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
// snapshot before layering operation-specific highlights on top.
#let _paint-palette(r, tree, rbt) = {
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
    result = (result.patch)(f => (f.style-node)(
      p,
      fill: fill,
      stroke: stroke,
      text-fill: text-fill,
    ))
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
    delete: (self, v) => if not (self.contains)(v) {
      self
    } else {
      let cls = self.meta.cls
      _blacken(cls, _del(cls, self, v))
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
    display: (self, theme: auto, render-theme: auto) => {
      // Returns a one-element Frame array — the static tree, with each
      // node colored from the active RBT palette by its `red` field.
      // `step` is none.
      let captions = (none,)
      let steps-meta = (none,)
      let alts = ("Red-black tree: " + (self.describe)() + ".",)
      let build-snapshots = (rbt, _op, _rt) => {
        let r = tree-anim.make-renderer(self)
        r = _paint-palette(r, self, rbt)
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
    insert-display: (self, v, theme: auto, render-theme: auto) => {
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
          r = _paint-palette(r, event.tree, rbt)
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
  ),
)
