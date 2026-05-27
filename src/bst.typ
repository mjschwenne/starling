#import "@preview/typsy:0.2.2": Any, Int, None, Union, class
#import "./tree-anim.typ" as tree-anim
#import "./op-theme.typ": _resolve-op-theme-arg

// BST has no intrinsic per-node styling, so it has no DS-specific
// theme of its own — every `*-display` method below reads operation
// strokes / fills / palettes from the shared `op-theme`
// (`src/op-theme.typ`), and structural defaults from `render-theme`
// (`src/tree-anim.typ`). See those files for the key inventories.

// Resolve a `render-theme:` argument that may be `auto` (read state) or
// a partial dict (merge into default). Returns either `auto`
// (signalling "read state inside the context block") or a fully merged
// dict ready to use directly. The auto-passthrough lets us defer state
// reads to inside the canvas's context block.
#let _resolve-render-theme-arg(theme) = if theme == auto {
  auto
} else { tree-anim._merge-render-theme(theme) }

// Build an array of `Frame` records for one phase of a display:
//
//   tree             — the BST being rendered (one tree per phase)
//   build-snapshots  — closure (op-theme, render-theme) => Array(Snapshot);
//                      one closure per phase, shared across all its frames
//                      so Typst's call cache amortizes the snapshot build
//   captions/steps/alts — parallel arrays of theme-independent metadata
//   theme/render-theme — pre-resolved (`auto` or merged dict)
//
// Each frame's `render` field is a builder
// `(op-theme, render-theme) => content` — the lib.typ helpers resolve
// state once per call and feed the resolved themes into every frame's
// builder. With Typst's function-result cache, repeated `build-snapshots`
// calls inside one helper invocation share results, so an n-frame
// animation pays O(n) snapshot work for one state read total.
//
// `theme` and `render-theme` arguments here are the per-call overrides
// (or `auto` to defer to the caller's resolved theme): a non-auto
// argument shadows whatever the helper passes in.
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
    _builder: (fn: (op-arg, rt-arg) => {
      let op = if theme == auto { op-arg } else { theme }
      let rt = if render-theme == auto { rt-arg } else { render-theme }
      let snaps = build-snapshots(op, rt)
      tree-anim._render-canvas(tree, snaps.at(i), (:), (:), rt)
    }),
    caption: captions.at(i),
    step: steps-meta.at(i),
    alt: alts.at(i),
  ))
}

// Pick a readable text fill for a given background color by inspecting the
// oklab L component. Used by the traversal-display methods so the value
// inside a gradient-filled node stays legible across the palette.
#let _text-fill-for(bg) = {
  let l = bg.oklab().components().first()
  if l < 60% { white } else { black }
}

// Concise per-visit animation shared by the four `*-order-display` methods.
// `paths` is the precomputed visit order; `name` appears in the initial
// alt text. One frame per visit: highlighted node gets a gradient fill
// sampled from the active op-theme's `traversal-palette` and a badge
// note showing its 1-indexed position; the caption accumulates the
// output sequence (monospace list).
//
// step.kind values: "init" (initial frame), "visit" (per node, with path,
// index, value).
#let _render-traversal(self, paths, name, theme, render-theme) = {
  let n = paths.len()

  let captions = (none,)
  let steps-meta = ((kind: "init"),)
  let alts = (
    "Binary search tree: "
      + (self.describe)()
      + ". About to traverse "
      + name
      + ".",
  )

  let output = ()
  for (i, p) in paths.enumerate() {
    let value = (self.resolve)(p).value
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
    let r = tree-anim.make-renderer(self, sticky: true)
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

// The BST class. The `*-display` methods return `Array(Frame)` —
// one Frame per animation step, each carrying the rendered cetz canvas,
// an optional textual caption, and free-form `step` metadata documenting
// what that frame represents. Pass the result to a render helper in
// `lib.typ` (`last`, `stacked`, `figures`) or compose your own layout
// from the frame fields.
//
// `value` is the integer key used for ordering. `label` is what gets
// drawn inside the node — `auto` falls back to `str(value)`; any other
// value is rendered as-is (strings auto-coerce to content, so images,
// `[]`, or arbitrary content all work). Captions and step metadata stay
// keyed on `value`. The field is named `label` rather than `display` to
// avoid colliding with the `display()` method below.
//
// `*-display` methods accept optional `theme:` and `render-theme:`
// arguments. `auto` (the default) reads the active theme from state at
// layout time, so `set-op-theme(..)` / `set-render-theme(..)` earlier
// in the document propagate. Passing a partial dict bakes that override
// in for this one call and skips state entirely.
#let BST = class(
  name: "BST",
  fields: (
    value: Int,
    label: Any,
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
    insert: (self, v, label: auto) => {
      let cls = self.meta.cls
      if v <= self.value {
        let new-left = if self.left == none {
          (cls.new)(value: v, label: label, left: none, right: none)
        } else {
          (self.left.insert)(v, label: label)
        }
        (cls.new)(
          value: self.value,
          label: self.label,
          left: new-left,
          right: self.right,
        )
      } else {
        let new-right = if self.right == none {
          (cls.new)(value: v, label: label, left: none, right: none)
        } else {
          (self.right.insert)(v, label: label)
        }
        (cls.new)(
          value: self.value,
          label: self.label,
          left: self.left,
          right: new-right,
        )
      }
    },
    // `insert-many` is for the common int-only case. For custom labels,
    // chain `.insert(v, label: ...)` calls directly.
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
          (cls.new)(
            value: self.value,
            label: self.label,
            left: new-left,
            right: self.right,
          )
        }
      } else if v > self.value {
        if self.right == none { self } else {
          let new-right = (self.right.delete)(v)
          (cls.new)(
            value: self.value,
            label: self.label,
            left: self.left,
            right: new-right,
          )
        }
      } else if self.left == none and self.right == none {
        none
      } else if self.left == none {
        self.right
      } else if self.right == none {
        self.left
      } else {
        // Two children — replace with in-order predecessor's value AND
        // label, then recursively delete the predecessor from the left
        // subtree.
        let find-max(n) = if n.right == none { n } else { find-max(n.right) }
        let pred = find-max(self.left)
        let new-left = (self.left.delete)(pred.value)
        (cls.new)(
          value: pred.value,
          label: pred.label,
          left: new-left,
          right: self.right,
        )
      }
    },
    rotate: (self, child) => {
      // Rotate around `child` — anywhere in the tree, not just at
      // the root. `child` is located via BST search on `child.value`;
      // its parent and the direction (left/right) are inferred.
      let cls = self.meta.cls
      let child-path = (self.by-value)(child.value)
      if child-path == "" {
        panic("rotate: cannot rotate the root with itself")
      }
      let parent-path = child-path.slice(0, child-path.len() - 1)
      let parent = (self.resolve)(parent-path)
      let is-right = child-path.last() == "L"
      let rotated = if is-right {
        // child is left child of parent -> right rotation
        (cls.new)(
          value: child.value,
          label: child.label,
          left: child.left,
          right: (cls.new)(
            value: parent.value,
            label: parent.label,
            left: child.right,
            right: parent.right,
          ),
        )
      } else {
        // child is right child of parent -> left rotation
        (cls.new)(
          value: child.value,
          label: child.label,
          left: (cls.new)(
            value: parent.value,
            label: parent.label,
            left: parent.left,
            right: child.left,
          ),
          right: child.right,
        )
      }
      // Splice the rotated subtree back into the full tree.
      let replace-at(tree, path, new-subtree) = if path == "" {
        new-subtree
      } else if path.first() == "L" {
        (cls.new)(
          value: tree.value,
          label: tree.label,
          left: replace-at(tree.left, path.slice(1), new-subtree),
          right: tree.right,
        )
      } else {
        (cls.new)(
          value: tree.value,
          label: tree.label,
          left: tree.left,
          right: replace-at(tree.right, path.slice(1), new-subtree),
        )
      }
      replace-at(self, parent-path, rotated)
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
    // Traversal-order helpers. Each returns an array of L/R path strings
    // in the order the corresponding traversal would visit them.
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
    // One frame per visit. The visited node gets a gradient fill sampled
    // from `palette` and a badge note showing its 1-indexed visit position;
    // the running output sequence accumulates in the caption. The final
    // frame wears the traversal's full color signature — stacking four
    // `last`-rendered displays gives the "compare four traversals" view.
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
    display: (self, theme: auto, render-theme: auto) => {
      // Returns a one-element Frame array — the static tree. `step` is none.
      let captions = (none,)
      let steps-meta = (none,)
      let alts = ("Binary search tree: " + (self.describe)() + ".",)
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
      // Returns one frame per comparison made along the search path.
      // The first frame is the unmodified tree (kind: "init"). Each
      // subsequent frame highlights the visited node, draws the
      // comparison string as an inline note next to it, and sets the
      // same string as the frame caption. `step` is:
      //   (kind: "init")                                    — initial frame
      //   (kind: "compare", path, cmp, found: bool)         — each comparison
      let walk(node, path) = {
        let cmp = if v == node.value {
          str(v) + " = " + str(node.value)
        } else if v < node.value {
          str(v) + " < " + str(node.value)
        } else {
          str(v) + " > " + str(node.value)
        }
        let step = (path: path, cmp: cmp, found: v == node.value)
        if v == node.value or node.left == none and node.right == none {
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
        "Binary search tree: "
          + (self.describe)()
          + ". About to search for "
          + str(v)
          + ".",
      )
      for (i, s) in steps.enumerate() {
        captions.push(s.cmp)
        steps-meta.push((kind: "compare", path: s.path, cmp: s.cmp, found: s.found))
        let node-value = str((self.resolve)(s.path).value)
        let is-last = i == steps.len() - 1
        let alt = if s.found {
          "Match found at node " + node-value + "."
        } else if is-last {
          (
            "Comparing "
              + s.cmp
              + " at node "
              + node-value
              + "; search ends here, "
              + str(v)
              + " is not in the tree."
          )
        } else {
          "Comparing " + s.cmp + " at node " + node-value + "; continuing search."
        }
        alts.push(alt)
      }

      let build-snapshots = (op, _rt) => {
        let r = tree-anim.make-renderer(self, sticky: true)
        for s in steps {
          r = (r.push-with-node)(s.path, stroke: op.search-stroke)
          r = (r.patch)(f => (f.note-node)(s.path, s.cmp))
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
    rotate-display: (self, child, theme: auto, render-theme: auto) => {
      // Animates a rotation around `child` — anywhere in the tree,
      // not just at the root. `child` is the BST node that should
      // become the new subtree root; its BST parent and the rotation
      // direction (left/right) are inferred from the search path.
      //
      // Six-frame sequence (step.kind):
      //   1. "init"        — before-tree, no styling
      //   2. "pivots"      — pivot nodes highlighted
      //   3. "break"       — edges that will rotate are hidden
      //   4. "restructure" — switch to after-tree, new edges still hidden
      //   5. "connect"     — new edges appear in success-stroke
      //   6. "settle"      — highlights cleared, final settled tree
      let child-value = child.value
      let child-path = (self.by-value)(child-value)
      if child-path == "" {
        panic(
          "rotate-display: cannot rotate around root node "
            + str(child-value)
            + "; child must have a parent.",
        )
      }
      let parent-path = child-path.slice(0, child-path.len() - 1)
      let parent-subtree = (self.resolve)(parent-path)
      let is-right = child-path.last() == "L"
      let after = (self.rotate)(child)

      // For non-root rotations the grandparent-to-subtree edge
      // (whose path-id is `parent-path` itself) must also break and
      // reconnect — otherwise the new subtree root visibly "snaps"
      // onto the grandparent without animation.
      let has-grandparent = parent-path != ""

      // BEFORE path-ids (absolute, relative to the full tree).
      // Middle child of `child` that moves to the parent after rotation.
      let middle-path = parent-path + (if is-right { "LR" } else { "RL" })
      let has-middle = (self.resolve)(middle-path) != none
      let broken-paths = (
        (if has-grandparent { (parent-path,) } else { () })
          + (child-path,)
          + (if has-middle { (middle-path,) } else { () })
      )

      // AFTER path-ids
      let new-parent-path = parent-path + (if is-right { "R" } else { "L" })
      let new-middle-path = parent-path + (if is-right { "RL" } else { "LR" })
      let has-new-middle = (after.resolve)(new-middle-path) != none
      let new-edge-paths = (
        (if has-grandparent { (parent-path,) } else { () })
          + (new-parent-path,)
          + (if has-new-middle { (new-middle-path,) } else { () })
      )

      let direction = if is-right { "right" } else { "left" }
      let parent-value = str(parent-subtree.value)
      let child-value-str = str(child-value)

      let resolved-theme = _resolve-op-theme-arg(theme)
      let resolved-render-theme = _resolve-render-theme-arg(render-theme)

      // Phase A metadata
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
        "Binary search tree: "
          + (self.describe)()
          + ". About to "
          + direction
          + "-rotate around node "
          + child-value-str
          + ".",
        "Rotation pivots identified: parent "
          + parent-value
          + " and child "
          + child-value-str
          + ".",
        "Breaking the edges that will rotate.",
      )

      let build-snapshots-a = (op, _rt) => {
        let r = tree-anim.make-renderer(self, sticky: true)
        // Frame 2: pivots
        r = (r.push-with-node)(parent-path, stroke: op.attention-stroke)
        r = (r.patch)(f => (f.style-node)(child-path, stroke: op.attention-stroke))
        // Frame 3: break
        r = (r.push-with-edge)(child-path, hide: true)
        if has-middle {
          r = (r.patch)(f => (f.style-edge)(middle-path, hide: true))
        }
        if has-grandparent {
          r = (r.patch)(f => (f.style-edge)(parent-path, hide: true))
        }
        r.snapshots
      }

      // Phase B metadata
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
        // Frame 4 (initial): "restructure" — new shape, pivots still
        // highlighted, rotated edges hidden.
        r = (r.patch)(f => (f.style-node)(parent-path, stroke: op.attention-stroke))
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
        // Frame 5: connect — new edges appear in success-stroke.
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
        // Frame 6: settle — reset highlights to the theme's reset
        // stroke (which should look like an unstyled stroke).
        r = (r.push-with-node)(parent-path, stroke: op.reset-stroke)
        r = (r.patch)(f => (f.style-node)(new-parent-path, stroke: op.reset-stroke))
        r = (r.patch)(f => (f.style-edge)(new-parent-path, stroke: op.reset-stroke))
        if has-new-middle {
          r = (r.patch)(f => (f.style-edge)(new-middle-path, stroke: op.reset-stroke))
        }
        if has-grandparent {
          r = (r.patch)(f => (f.style-edge)(parent-path, stroke: op.reset-stroke))
        }
        r.snapshots
      }

      let frames-a = _make-frames(
        self,
        build-snapshots-a,
        captions-a,
        steps-meta-a,
        alts-a,
        resolved-theme,
        resolved-render-theme,
      )
      let frames-b = _make-frames(
        after,
        build-snapshots-b,
        captions-b,
        steps-meta-b,
        alts-b,
        resolved-theme,
        resolved-render-theme,
      )
      frames-a + frames-b
    },
    delete-display: (self, v, search: false, theme: auto, render-theme: auto) => {
      // Animates a deletion. Dispatches on the target's children:
      //   leaf       → highlight, dash edge, then settle (r2's after-tree)
      //   one child  → highlight, dash both edges, hide, child reattaches success
      //   two child  → highlight target + descend to predecessor, annotate value
      //                transfer, settle with success at target slot
      //
      // With `search: true`, the deletion is preceded by a
      // search-display-style walk: one "compare" frame per node visited
      // along the path to the target. The comparison notes are cleared
      // on the first deletion frame so they don't compete with the
      // deletion-specific highlights.
      //
      // step.kind values: "init", "compare" (only with search: true),
      // "highlight", "break", "descend", "transfer", "settle".
      let target-path = (self.by-value)(v)
      let target = (self.resolve)(target-path)
      let after = (self.delete)(v)

      let resolved-theme = _resolve-op-theme-arg(theme)
      let resolved-render-theme = _resolve-render-theme-arg(render-theme)

      // Eager: precompute the search-prefix steps (if requested) and the
      // branch-specific frame counts so the metadata arrays can be built
      // without re-running per-theme work.
      let search-steps = if search {
        // `by-value` has already confirmed v is in the tree, so this
        // walk always terminates at a match.
        let walk(node, path) = {
          let cmp = if v == node.value {
            str(v) + " = " + str(node.value)
          } else if v < node.value {
            str(v) + " < " + str(node.value)
          } else {
            str(v) + " > " + str(node.value)
          }
          let step = (path: path, cmp: cmp, found: v == node.value)
          if v == node.value {
            (step,)
          } else if v < node.value {
            (step,) + walk(node.left, path + "L")
          } else {
            (step,) + walk(node.right, path + "R")
          }
        }
        walk(self, "")
      } else { () }

      let is-leaf = target.left == none and target.right == none
      let is-one-child = (
        (not is-leaf) and (target.left == none or target.right == none)
      )

      // Phase A metadata + the per-branch eager fixtures used by phase B.
      let captions-a = (none,)
      let steps-meta-a = ((kind: "init"),)
      let alts-a = (
        "Binary search tree: "
          + (self.describe)()
          + ". About to delete "
          + str(v)
          + ".",
      )
      for s in search-steps {
        captions-a.push(s.cmp)
        steps-meta-a.push((kind: "compare", path: s.path, cmp: s.cmp, found: s.found))
        let node-value = str((self.resolve)(s.path).value)
        let alt = if s.found {
          "Found target node " + node-value + "; ready to delete."
        } else {
          "Comparing " + s.cmp + " at node " + node-value + "; descending."
        }
        alts-a.push(alt)
      }

      let captions-b = ()
      let steps-meta-b = ()
      let alts-b = ()

      if is-leaf {
        captions-a += ([Delete #v], [Remove edge])
        steps-meta-a += (
          (kind: "highlight", path: target-path),
          (kind: "break", path: target-path),
        )
        alts-a += (
          "Marked leaf node " + str(v) + " for deletion.",
          "Removing the edge to node " + str(v) + ".",
        )
        captions-b.push([Done])
        steps-meta-b.push((kind: "settle"))
        alts-b.push("Deletion of " + str(v) + " complete.")
      } else if is-one-child {
        let has-left = target.left != none
        let child-path = target-path + (if has-left { "L" } else { "R" })
        let child-value = str((self.resolve)(child-path).value)

        captions-a += ([Delete #v], [Mark edges to remove], [Remove])
        steps-meta-a += (
          (kind: "highlight", path: target-path, child: child-path),
          (kind: "break", paths: (target-path, child-path)),
          (kind: "break", paths: (target-path, child-path), hidden: true),
        )
        alts-a += (
          "Marked node "
            + str(v)
            + " for deletion; its single child "
            + child-value
            + " will be promoted.",
          "Marking edges around node " + str(v) + " for removal.",
          "Removed node " + str(v) + " and its edges.",
        )
        captions-b.push([Reattach])
        steps-meta-b.push((kind: "settle", path: target-path))
        alts-b.push(
          "Child "
            + child-value
            + " reattached in place of "
            + str(v)
            + "; deletion complete.",
        )
      } else {
        // Two children — predecessor is rightmost in target's left subtree.
        let walk-max(p) = {
          let n = (self.resolve)(p)
          if n.right == none { (p,) } else { (p,) + walk-max(p + "R") }
        }
        let predecessor-paths = walk-max(target-path + "L")
        let predecessor-path = predecessor-paths.last()
        let predecessor-value = (self.resolve)(predecessor-path).value

        captions-a.push([Delete #v])
        steps-meta-a.push((kind: "highlight", path: target-path))
        alts-a.push(
          "Marked node "
            + str(v)
            + " for deletion; it has two children, so an in-order predecessor will replace it.",
        )
        for p in predecessor-paths {
          captions-a.push([Find predecessor])
          steps-meta-a.push((kind: "descend", path: p))
          let pv = str((self.resolve)(p).value)
          alts-a.push("Descending into the left subtree at node " + pv + ".")
        }
        captions-a.push([Transfer #predecessor-value])
        steps-meta-a.push((
          kind: "transfer",
          from: predecessor-path,
          to: target-path,
          value: predecessor-value,
        ))
        alts-a.push(
          "Replacing "
            + str(v)
            + " with predecessor value "
            + str(predecessor-value)
            + ".",
        )
        captions-b.push([Done])
        steps-meta-b.push((kind: "settle", path: target-path))
        alts-b.push(
          "Deletion of "
            + str(v)
            + " complete; node now holds "
            + str(predecessor-value)
            + ".",
        )
      }

      // Theme-dependent snapshot construction. Mirrors the eager
      // structure above, replacing literal colors/strokes with theme
      // reads. Each closure is shared across all its phase's frames so
      // Typst's call cache amortizes the snapshot build.
      let build-snapshots-a = (op, _rt) => {
        let r = tree-anim.make-renderer(self, sticky: true)
        for s in search-steps {
          r = (r.push-with-node)(s.path, stroke: op.search-stroke)
          r = (r.patch)(f => (f.note-node)(s.path, s.cmp))
        }
        if is-leaf {
          r = (r.push-with-node)(target-path, stroke: op.attention-stroke)
          if search { r = (r.patch)(f => (f.clear-notes)()) }
          r = (r.push-with-edge)(target-path, stroke: op.danger-stroke)
        } else if is-one-child {
          let has-left = target.left != none
          let child-path = target-path + (if has-left { "L" } else { "R" })
          r = (r.push-with-node)(target-path, stroke: op.attention-stroke)
          if search { r = (r.patch)(f => (f.clear-notes)()) }
          r = (r.patch)(f => (f.style-node)(child-path, stroke: op.search-stroke))
          r = (r.push-with-edge)(target-path, stroke: op.danger-stroke)
          r = (r.patch)(f => (f.style-edge)(child-path, stroke: op.danger-stroke))
          r = (r.push-with-edge)(target-path, hide: true)
          r = (r.patch)(f => (f.style-edge)(child-path, hide: true))
          r = (r.patch)(f => (f.style-node)(target-path, hide: true))
        } else {
          let walk-max(p) = {
            let n = (self.resolve)(p)
            if n.right == none { (p,) } else { (p,) + walk-max(p + "R") }
          }
          let predecessor-paths = walk-max(target-path + "L")
          let predecessor-value = (self.resolve)(predecessor-paths.last()).value
          r = (r.push-with-node)(target-path, stroke: op.attention-stroke)
          if search { r = (r.patch)(f => (f.clear-notes)()) }
          for p in predecessor-paths {
            r = (r.push-with-node)(p, stroke: op.search-stroke)
          }
          r = (r.push-frame)()
          r = (r.patch)(f => (f.note-node)(
            target-path,
            "← " + str(predecessor-value),
          ))
        }
        r.snapshots
      }

      let build-snapshots-b = (op, _rt) => {
        let r = tree-anim.make-renderer(after, sticky: true)
        if is-leaf {
          // Single settle frame, no styling.
        } else if is-one-child {
          r = (r.patch)(f => (f.style-node)(target-path, stroke: op.search-stroke))
          r = (r.patch)(f => (f.style-edge)(target-path, stroke: op.success-stroke))
        } else {
          r = (r.patch)(f => (f.style-node)(
            target-path,
            stroke: op.settled-stroke,
            fill: op.success-fill,
          ))
        }
        r.snapshots
      }

      let frames-a = _make-frames(
        self,
        build-snapshots-a,
        captions-a,
        steps-meta-a,
        alts-a,
        resolved-theme,
        resolved-render-theme,
      )
      let frames-b = _make-frames(
        after,
        build-snapshots-b,
        captions-b,
        steps-meta-b,
        alts-b,
        resolved-theme,
        resolved-render-theme,
      )
      frames-a + frames-b
    },
    insert-display: (self, v, theme: auto, render-theme: auto) => {
      // Walks the insertion search path, then transitions to the after-tree
      // to show the new node appearing.
      //
      // step.kind values: "init", "compare" (per comparison along the
      // search path), "inserted" (final frame on the after-tree).
      let walk(node, path) = {
        let cmp = if v < node.value {
          str(v) + " < " + str(node.value)
        } else if v > node.value {
          str(v) + " > " + str(node.value)
        } else {
          str(v) + " = " + str(node.value)
        }
        let step = (path: path, cmp: cmp)
        if v <= node.value and node.left != none {
          (step,) + walk(node.left, path + "L")
        } else if v > node.value and node.right != none {
          (step,) + walk(node.right, path + "R")
        } else {
          (step,)
        }
      }
      let steps = walk(self, "")
      let search-paths = steps.map(s => s.path)
      let after = (self.insert)(v)
      let new-path = (after.by-value)(v)

      let resolved-theme = _resolve-op-theme-arg(theme)
      let resolved-render-theme = _resolve-render-theme-arg(render-theme)

      // Phase A metadata.
      let captions-a = (none,)
      let steps-meta-a = ((kind: "init"),)
      let alts-a = (
        "Binary search tree: "
          + (self.describe)()
          + ". About to insert "
          + str(v)
          + ".",
      )
      for (i, s) in steps.enumerate() {
        captions-a.push(s.cmp)
        steps-meta-a.push((kind: "compare", path: s.path, cmp: s.cmp))
        let node-value = str((self.resolve)(s.path).value)
        let is-last = i == steps.len() - 1
        let alt = if is-last {
          (
            "Comparing "
              + s.cmp
              + " at node "
              + node-value
              + "; insertion point found below this node."
          )
        } else {
          "Comparing " + s.cmp + " at node " + node-value + "; descending."
        }
        alts-a.push(alt)
      }

      let build-snapshots-a = (op, _rt) => {
        let r = tree-anim.make-renderer(self, sticky: true)
        for s in steps {
          r = (r.push-with-node)(s.path, stroke: op.search-stroke)
          r = (r.patch)(f => (f.note-node)(s.path, s.cmp))
        }
        r.snapshots
      }

      // Phase B: single after-tree frame — search-path highlights carry
      // forward (without notes) and the new node appears at the same
      // time. The extra "just-appeared but not yet styled" intermediate
      // frame added no information, so it's elided.
      let captions-b = ([Inserted #v],)
      let steps-meta-b = ((kind: "inserted", path: new-path),)
      let alts-b = ("Inserted " + str(v) + " as a new leaf.",)

      let build-snapshots-b = (op, _rt) => {
        let r = tree-anim.make-renderer(after, sticky: true)
        for p in search-paths {
          r = (r.patch)(f => (f.style-node)(p, stroke: op.search-stroke))
        }
        r = (r.patch)(f => (f.style-node)(
          new-path,
          stroke: op.settled-stroke,
          fill: op.success-fill,
        ))
        r = (r.patch)(f => (f.style-edge)(new-path, stroke: op.success-stroke))
        r.snapshots
      }

      let frames-a = _make-frames(
        self,
        build-snapshots-a,
        captions-a,
        steps-meta-a,
        alts-a,
        resolved-theme,
        resolved-render-theme,
      )
      let frames-b = _make-frames(
        after,
        build-snapshots-b,
        captions-b,
        steps-meta-b,
        alts-b,
        resolved-theme,
        resolved-render-theme,
      )
      frames-a + frames-b
    },
  ),
)
