#import "@preview/typsy:0.2.2": Any, Int, Bool, None, Union, class

// ===================================================================
// Red-black tree — core data structure (no animations yet)
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

// Insert helper: standard BST descent with a fresh red leaf, balance
// on the way back up. The root is blackened by the public method.
#let _ins(cls, node, v, lab) = if node == none {
  _node(cls, true, none, v, lab, none)
} else if v <= node.value {
  _balance(
    cls,
    node.red,
    _ins(cls, node.left, v, lab),
    node.value,
    node.label,
    node.right,
  )
} else {
  _balance(
    cls,
    node.red,
    node.left,
    node.value,
    node.label,
    _ins(cls, node.right, v, lab),
  )
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
      _blacken(cls, _ins(cls, self, v, label))
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
  ),
)
