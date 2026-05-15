#import "@preview/typsy:0.2.2": Any, Int, None, Union, class
#import "./tree-anim.typ" as tree-anim

// Builds a BST class with `wrap` baked into the *-display methods via
// closure capture. `wrap` is called as `wrap(..figs)` where `figs` is a
// sequence of `figure` content — one per animation frame. See `src/lib.typ`
// for the public `configure(wrap: ...)` entrypoint that wires this up.
#let make-bst(wrap) = class(
  name: "BST",
  fields: (
    value: Int,
    left: Union(None, Any),
    right: Union(None, Any),
  ),
  methods: (
    by-value: (self, v) => {
      // Returns the L/R path-id string for the node holding v, or panics.
      let walk(node, path) = {
        if node == none {
          panic("by-value: value not found in tree: " + repr(v))
        } else if v == node.value {
          path
        } else if v < node.value {
          walk(node.left, path + "L")
        } else {
          walk(node.right, path + "R")
        }
      }
      walk(self, "")
    },
    path-to: (self, v) => {
      // Returns the sequence of path-ids visited when searching for v,
      // ending at the node that holds v (or panicking if not present).
      let walk(node, path) = {
        if node == none {
          panic("path-to: value not found in tree: " + repr(v))
        } else if v == node.value {
          (path,)
        } else if v < node.value {
          (path,) + walk(node.left, path + "L")
        } else {
          (path,) + walk(node.right, path + "R")
        }
      }
      walk(self, "")
    },
    resolve: (self, path) => {
      // Returns the subtree at the given L/R path string, or none if the
      // path runs off a missing child.
      let walk(node, cps) = {
        if node == none or cps.len() == 0 { node } else if cps.first() == "L" {
          walk(node.left, cps.slice(1))
        } else { walk(node.right, cps.slice(1)) }
      }
      walk(self, path.codepoints())
    },
    insert: (self, v) => {
      let cls = self.meta.cls
      if v < self.value {
        let new-left = if self.left == none {
          (cls.new)(value: v, left: none, right: none)
        } else {
          (self.left.insert)(v)
        }
        (cls.new)(value: self.value, left: new-left, right: self.right)
      } else {
        let new-right = if self.right == none {
          (cls.new)(value: v, left: none, right: none)
        } else {
          (self.right.insert)(v)
        }
        (cls.new)(value: self.value, left: self.left, right: new-right)
      }
    },
    insert-many: (self, ..vals) => {
      let tree = self
      for v in vals.pos() {
        tree = (tree.insert)(v)
      }
      tree
    },
    contains: (self, v) => {
      if v == self.value { true } else if v < self.value {
        self.left != none and (self.left.contains)(v)
      } else { self.right != none and (self.right.contains)(v) }
    },
    delete: (self, v) => {
      let cls = self.meta.cls
      if v < self.value {
        if self.left == none { self } else {
          let new-left = (self.left.delete)(v)
          (cls.new)(value: self.value, left: new-left, right: self.right)
        }
      } else if v > self.value {
        if self.right == none { self } else {
          let new-right = (self.right.delete)(v)
          (cls.new)(value: self.value, left: self.left, right: new-right)
        }
      } else if self.left == none and self.right == none {
        none
      } else if self.left == none {
        self.right
      } else if self.right == none {
        self.left
      } else {
        // Two children — replace value with in-order successor, then
        // recursively delete the successor from the right subtree.
        let find-min(n) = if n.left == none { n.value } else {
          find-min(n.left)
        }
        let sv = find-min(self.right)
        let new-right = (self.right.delete)(sv)
        (cls.new)(value: sv, left: self.left, right: new-right)
      }
    },
    rotate: (self, child) => {
      let cls = self.meta.cls
      if self.left != none and self.left.value == child.value {
        // child is left child of self -> right rotation
        (cls.new)(
          value: child.value,
          left: child.left,
          right: (cls.new)(
            value: self.value,
            left: child.right,
            right: self.right,
          ),
        )
      } else if self.right != none and self.right.value == child.value {
        // child is right child of self -> left rotation
        (cls.new)(
          value: child.value,
          left: (cls.new)(
            value: self.value,
            left: self.left,
            right: child.left,
          ),
          right: child.right,
        )
      } else {
        panic("child must be a direct child of parent")
      }
    },
    describe: self => {
      if self.left == none and self.right == none {
        str(self.value)
      } else {
        let l = if self.left == none { "empty" } else { (self.left.describe)() }
        let r = if self.right == none { "empty" } else {
          (self.right.describe)()
        }
        str(self.value) + " (left: " + l + ", right: " + r + ")"
      }
    },
    display: (self, alt: none) => {
      let alt-text = if alt != none { alt } else {
        "Binary search tree: " + (self.describe)()
      }
      let r = tree-anim.make-renderer(self)
      figure((r.static)(), alt: alt-text)
    },
    search-display: (self, v) => {
      let walk(node, path) = {
        let cmp = if v == node.value {
          str(v) + " = " + str(node.value)
        } else if v < node.value {
          str(v) + " < " + str(node.value)
        } else {
          str(v) + " > " + str(node.value)
        }
        let step = (path: path, cmp: cmp)
        if v == node.value or node.left == none and node.right == none {
          (step,)
        } else if v < node.value and node.left != none {
          (step,) + walk(node.left, path + "L")
        } else if v > node.value and node.right != none {
          (step,) + walk(node.right, path + "R")
        } else { (step,) }
      }
      let steps = walk(self, "")

      let r = tree-anim.make-renderer(self, sticky: true)
      for step in steps {
        r = (r.push-with-node)(step.path, stroke: color.blue + 2pt)
        r = (r.patch)(f => (f.note-node)(step.path, step.cmp))
      }
      let canvases = (r.render)()
      let figs = canvases
        .enumerate()
        .map(((i, c)) => figure(
          c,
          alt: "BST search for " + str(v) + ", step " + str(i),
        ))
      wrap(..figs)
    },
    rotate-display: (self, child-value) => {
      // Animates a rotation at the root of `self`. `child-value` must
      // match a direct child of self; the direction (left/right) is
      // inferred.
      //
      // Visual story:
      //   1. Highlight the two pivot nodes orange.
      //   2. The edges that will break go red+dashed.
      //   3. Those edges hide entirely (truly broken).
      //   4. Switch to the rotated tree; new edges show green.
      let is-right = self.left != none and self.left.value == child-value
      let is-left = self.right != none and self.right.value == child-value
      if not (is-right or is-left) {
        panic(
          "rotate-display: "
            + str(child-value)
            + " is not a direct child of "
            + str(self.value),
        )
      }
      let child = if is-right { self.left } else { self.right }
      let after = (self.rotate)(child)

      // BEFORE path-ids
      let parent-path = ""
      let child-path = if is-right { "L" } else { "R" }
      // Middle child of `child` that moves to the parent after rotation.
      let middle-path = if is-right { "LR" } else { "RL" }
      let has-middle = (self.resolve)(middle-path) != none

      // AFTER path-ids
      let new-parent-path = if is-right { "R" } else { "L" }
      let new-middle-path = if is-right { "RL" } else { "LR" }
      let has-new-middle = (after.resolve)(new-middle-path) != none

      let dashed-red = (paint: color.red, thickness: 2pt, dash: "dashed")

      // Phase A: before-tree
      let r1 = tree-anim.make-renderer(self, sticky: true)
      // Frame: highlight pivots
      r1 = (r1.push-with-node)(parent-path, stroke: color.orange + 2pt)
      r1 = (r1.patch)(f => (f.style-node)(
        child-path,
        stroke: color.orange + 2pt,
      ))
      // Frame: edges to break go dashed red
      r1 = (r1.push-with-edge)(child-path, stroke: dashed-red)
      if has-middle {
        r1 = (r1.patch)(f => (f.style-edge)(middle-path, stroke: dashed-red))
      }
      // Frame: hide the broken edges
      r1 = (r1.push-with-edge)(child-path, hide: true)
      if has-middle {
        r1 = (r1.patch)(f => (f.style-edge)(middle-path, hide: true))
      }

      // Phase B: after-tree with new edges highlighted green
      let r2 = tree-anim.make-renderer(after, sticky: true)
      r2 = (r2.patch)(f => (f.style-node)(
        parent-path,
        stroke: color.orange + 2pt,
      ))
      r2 = (r2.patch)(f => (f.style-node)(
        new-parent-path,
        stroke: color.orange + 2pt,
      ))
      r2 = (r2.patch)(f => (f.style-edge)(
        new-parent-path,
        stroke: color.green + 2pt,
      ))
      if has-new-middle {
        r2 = (r2.patch)(f => (f.style-edge)(
          new-middle-path,
          stroke: color.green + 2pt,
        ))
      }

      let canvases = tree-anim.concat-frames(r1, r2)
      let figs = canvases
        .enumerate()
        .map(((i, c)) => figure(
          c,
          alt: "BST rotation around " + str(child-value) + ", step " + str(i),
        ))
      wrap(..figs)
    },
    delete-display: (self, v) => {
      // Animates a deletion. Dispatches on the target's children:
      //   leaf       → highlight, dash edge, hide, settle
      //   one child  → highlight, dash both edges, hide, child reattaches green
      //   two child  → highlight target + successor, annotate value
      //                transfer, cut to after-tree with green at target slot
      let target-path = (self.by-value)(v)
      let target = (self.resolve)(target-path)
      let after = (self.delete)(v)
      let dashed-red = (paint: color.red, thickness: 2pt, dash: "dashed")

      let r1 = tree-anim.make-renderer(self, sticky: true)
      let r2 = tree-anim.make-renderer(after, sticky: true)

      let is-leaf = target.left == none and target.right == none
      let is-one-child = (
        (not is-leaf) and (target.left == none or target.right == none)
      )

      if is-leaf {
        // Leaf case: no rewiring happens, so "broken" and "settled" would
        // render nearly identically. Drop the hide frame and let r2's
        // after-tree serve as the final state.
        r1 = (r1.push-with-node)(target-path, stroke: color.orange + 2pt)
        r1 = (r1.push-with-edge)(target-path, stroke: dashed-red)
      } else if is-one-child {
        let has-left = target.left != none
        let child-path = target-path + (if has-left { "L" } else { "R" })
        r1 = (r1.push-with-node)(target-path, stroke: color.orange + 2pt)
        r1 = (r1.patch)(f => (f.style-node)(
          child-path,
          stroke: color.blue + 2pt,
        ))
        r1 = (r1.push-with-edge)(target-path, stroke: dashed-red)
        r1 = (r1.patch)(f => (f.style-edge)(child-path, stroke: dashed-red))
        r1 = (r1.push-with-edge)(target-path, hide: true)
        r1 = (r1.patch)(f => (f.style-edge)(child-path, hide: true))
        r1 = (r1.patch)(f => (f.style-node)(target-path, hide: true))
        // After tree: the surviving child is now at target-path
        r2 = (r2.patch)(f => (f.style-node)(
          target-path,
          stroke: color.blue + 2pt,
        ))
        r2 = (r2.patch)(f => (f.style-edge)(
          target-path,
          stroke: color.green + 2pt,
        ))
      } else {
        // Two children — successor is leftmost in target's right subtree.
        // Visually walk down from target.right, highlighting each step.
        let walk-min(p) = {
          let n = (self.resolve)(p)
          if n.left == none { (p,) } else { (p,) + walk-min(p + "L") }
        }
        let successor-paths = walk-min(target-path + "R")
        let successor-path = successor-paths.last()
        let successor-value = (self.resolve)(successor-path).value
        // Frame: target orange.
        r1 = (r1.push-with-node)(target-path, stroke: color.orange + 2pt)
        // Frames: descend into the right subtree to find the successor.
        for p in successor-paths {
          r1 = (r1.push-with-node)(p, stroke: color.blue + 2pt)
        }
        // Frame: annotate the value transfer.
        r1 = (r1.push-frame)()
        r1 = (r1.patch)(f => (f.note-node)(
          target-path,
          "← " + str(successor-value),
        ))
        // After tree: target-path now holds the successor's value.
        r2 = (r2.patch)(f => (f.style-node)(
          target-path,
          stroke: color.green + 3pt,
          fill: color.green.lighten(70%),
        ))
      }

      let canvases = tree-anim.concat-frames(r1, r2)
      let figs = canvases
        .enumerate()
        .map(((i, c)) => figure(
          c,
          alt: "BST delete " + str(v) + ", step " + str(i),
        ))
      wrap(..figs)
    },
    insert-display: (self, v) => {
      // Walks the insertion search path, then transitions to the after-tree
      // to show the new node appearing.
      let walk(node, path) = {
        let cmp = if v < node.value {
          str(v) + " < " + str(node.value)
        } else if v > node.value {
          str(v) + " > " + str(node.value)
        } else {
          str(v) + " = " + str(node.value)
        }
        let step = (path: path, cmp: cmp)
        if v < node.value and node.left != none {
          (step,) + walk(node.left, path + "L")
        } else if v >= node.value and node.right != none {
          (step,) + walk(node.right, path + "R")
        } else {
          (step,)
        }
      }
      let steps = walk(self, "")
      let search-paths = steps.map(s => s.path)
      let after = (self.insert)(v)
      let new-path = (after.by-value)(v)

      // Phase A: search on the before-tree, with running comparisons.
      let r1 = tree-anim.make-renderer(self, sticky: true)
      for step in steps {
        r1 = (r1.push-with-node)(step.path, stroke: color.blue + 2pt)
        r1 = (r1.patch)(f => (f.note-node)(step.path, step.cmp))
      }

      // Phase B: after-tree. Carry the search-path highlights forward
      // (without notes) so the eye tracks across the topology change, then
      // make the new node appear in green.
      let r2 = tree-anim.make-renderer(after, sticky: true)
      for p in search-paths {
        r2 = (r2.patch)(f => (f.style-node)(p, stroke: color.blue + 2pt))
      }
      r2 = (r2.push-with-node)(
        new-path,
        stroke: color.green + 3pt,
        fill: color.green.lighten(70%),
      )
      r2 = (r2.patch)(f => (f.style-edge)(new-path, stroke: color.green + 2pt))

      let canvases = tree-anim.concat-frames(r1, r2)
      let figs = canvases
        .enumerate()
        .map(((i, c)) => figure(
          c,
          alt: "BST insert " + str(v) + ", step " + str(i),
        ))
      wrap(..figs)
    },
  ),
)
