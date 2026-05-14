// Tree animation library — frame-based, styled rendering of trees built
// on top of cetz. Built using typsy classes for immutable, chainable
// construction.
//
// The core data flow:
//
//   Frame          — sparse style overrides for one snapshot of the tree.
//   TreeRenderer   — a tree plus an ordered list of frames plus defaults.
//   r.render()     — produces an array of cetz canvases (one per frame),
//                    ready to be spread into `alternatives(..)` for slides
//                    or used individually as static figures.
//
// Path identity
// -------------
// Nodes are identified by their position in the tree, encoded as a string
// of "L"/"R" characters from the root. The root is "". The right child of
// the root is "R", its left child is "RL", and so on. Edges are identified
// by the path of their CHILD node (each child has exactly one parent, so
// this is unambiguous).
//
// FUTURE — generalizing to B-trees and other n-ary trees: replace the L/R
// alphabet with slash-separated child indices (e.g. "0/1/2") or switch to
// `Array(..Int)` outright. The only places that interpret path segments
// are:
//   * `PathId` (the pattern below)
//   * `_build-cetz-tree` in this file (walks .left/.right)
//   * `by-value` / `path-to` on the BST class (also walk .left/.right)
// Everything else treats paths as opaque keys. To support B-trees you'd
// also need to extend the node renderer to draw multiple values per node
// and let edges fan out below each separator key; that is a render-side
// change, not a path-id change.

#import "@preview/typsy:0.2.2": *
#import "@preview/cetz:0.5.2"

// ===================================================================
// Types
// ===================================================================

#let PathId = Refine(
  Str,
  p => p.codepoints().all(c => c == "L" or c == "R"),
)

#let _node-style-keys = ("fill", "stroke", "text-fill", "note", "note-fill", "hide")
#let _edge-style-keys = ("stroke", "note", "note-fill", "mark", "hide")

#let NodeStyle = Refine(
  Dictionary(..Any),
  d => d.keys().all(k => _node-style-keys.contains(k)),
)
#let EdgeStyle = Refine(
  Dictionary(..Any),
  d => d.keys().all(k => _edge-style-keys.contains(k)),
)

// ===================================================================
// Frame — one styled snapshot
// ===================================================================

#let _merge-into(base, override) = {
  let out = base
  for (k, v) in override.pairs() { out.insert(k, v) }
  out
}

#let _strip-notes(d) = {
  let out = (:)
  for (k, v) in d.pairs() {
    let kept = (:)
    for (sk, sv) in v.pairs() {
      if sk != "note" and sk != "note-fill" { kept.insert(sk, sv) }
    }
    out.insert(k, kept)
  }
  out
}

#let Frame = class(
  name: "Frame",
  fields: (
    nodes: Dictionary(..NodeStyle),
    edges: Dictionary(..EdgeStyle),
    caption: Union(None, Content),
  ),
  methods: (
    style-node: (self, path, ..style) => {
      let cls = self.meta.cls
      let existing = self.nodes.at(path, default: (:))
      let merged = _merge-into(existing, style.named())
      let next = self.nodes
      next.insert(path, merged)
      (cls.new)(nodes: next, edges: self.edges, caption: self.caption)
    },
    style-edge: (self, path, ..style) => {
      let cls = self.meta.cls
      let existing = self.edges.at(path, default: (:))
      let merged = _merge-into(existing, style.named())
      let next = self.edges
      next.insert(path, merged)
      (cls.new)(nodes: self.nodes, edges: next, caption: self.caption)
    },
    note-node: (self, path, txt) => (self.style-node)(path, note: txt),
    note-edge: (self, path, txt) => (self.style-edge)(path, note: txt),
    with-caption: (self, c) => {
      let cls = self.meta.cls
      (cls.new)(nodes: self.nodes, edges: self.edges, caption: c)
    },
    clear-notes: (self) => {
      let cls = self.meta.cls
      (cls.new)(
        nodes: _strip-notes(self.nodes),
        edges: _strip-notes(self.edges),
        caption: self.caption,
      )
    },
  ),
)

#let blank-frame() = (Frame.new)(nodes: (:), edges: (:), caption: none)

// ===================================================================
// TreeRenderer
// ===================================================================

#let _phantom(path) = (((value: none, path: path, phantom: true),),)

#let _build-cetz-tree(node, path) = {
  // BST-shaped accessor. Generalize here for n-ary trees.
  //
  // When a node has exactly one child, we inject a phantom sibling on the
  // opposite side so cetz's tree layout doesn't put the lone child directly
  // under its parent — single children should visibly hang off to one side.
  // Phantoms are detected in draw-{node,edge} via `content.phantom` and
  // skipped at draw time, but they still occupy layout space.
  let has-left = node.left != none
  let has-right = node.right != none
  let children = ()
  if has-left {
    children.push(_build-cetz-tree(node.left, path + "L"))
  } else if has-right {
    children.push(.._phantom(path + "L"))
  }
  if has-right {
    children.push(_build-cetz-tree(node.right, path + "R"))
  } else if has-left {
    children.push(.._phantom(path + "R"))
  }
  ((value: node.value, path: path), ..children)
}

#let _render-canvas(tree, frame, default-node-style, default-edge-style) = {
  cetz.canvas({
    import cetz.draw
    import cetz.tree as cetz-tree
    cetz-tree.tree(
      _build-cetz-tree(tree, ""),
      draw-node: (node, ..) => {
        if node.content.at("phantom", default: false) {
          // Reserve a slightly-wider-than-a-node layout footprint, but
          // render nothing. `bounds: true` keeps the bounding box for
          // cetz's tree layout while hiding the drawable. Width > node
          // diameter so the lone real sibling visibly hangs off-center
          // rather than sitting almost-under its parent.
          draw.hide(draw.rect((-0.9, -0.6), (0.9, 0.6)), bounds: true)
          return
        }
        let path = node.content.path
        let value = node.content.value
        let s = _merge-into(
          default-node-style,
          frame.nodes.at(path, default: (:)),
        )
        if s.at("hide", default: false) { return }
        draw.circle(
          (),
          radius: 0.6,
          fill: s.at("fill", default: white),
          stroke: s.at("stroke", default: black),
        )
        let tf = s.at("text-fill", default: black)
        draw.content((), text(fill: tf)[*#value*])
        let n = s.at("note", default: none)
        if n != none {
          let nf = s.at("note-fill", default: rgb("#d4a017"))
          draw.content(
            (0.75, 0),
            anchor: "west",
            text(fill: nf, size: 0.8em, n),
          )
        }
      },
      draw-edge: (from, to, ..) => {
        if to.content.at("phantom", default: false) { return }
        if from.content.at("phantom", default: false) { return }
        let child-path = to.content.path
        let s = _merge-into(
          default-edge-style,
          frame.edges.at(child-path, default: (:)),
        )
        if s.at("hide", default: false) { return }
        let mark = s.at("mark", default: none)
        draw.line(
          (from.group-name, 0.4, to.group-name),
          (to.group-name, 0.4, from.group-name),
          stroke: s.at("stroke", default: black),
          ..if mark != none { (mark: mark) },
        )
        let n = s.at("note", default: none)
        if n != none {
          let nf = s.at("note-fill", default: rgb("#d4a017"))
          draw.content(
            (from.group-name, 0.5, to.group-name),
            text(fill: nf, size: 0.8em, n),
          )
        }
      },
    )
  })
}

#let TreeRenderer = class(
  name: "TreeRenderer",
  fields: (
    tree: Any,
    frames: Array(..Any),
    default-node-style: NodeStyle,
    default-edge-style: EdgeStyle,
    sticky: Bool,
  ),
  methods: (
    push-frame: (self) => {
      let cls = self.meta.cls
      let base = if self.sticky and self.frames.len() > 0 {
        self.frames.last()
      } else {
        blank-frame()
      }
      (cls.new)(
        tree: self.tree,
        frames: self.frames + (base,),
        default-node-style: self.default-node-style,
        default-edge-style: self.default-edge-style,
        sticky: self.sticky,
      )
    },
    patch: (self, fn) => {
      let cls = self.meta.cls
      assert(
        self.frames.len() > 0,
        message: "patch: no frames yet — call push-frame first.",
      )
      let next = self.frames
      next.at(next.len() - 1) = fn(next.last())
      (cls.new)(
        tree: self.tree,
        frames: next,
        default-node-style: self.default-node-style,
        default-edge-style: self.default-edge-style,
        sticky: self.sticky,
      )
    },
    push-with-node: (self, path, ..style) => {
      let r = (self.push-frame)()
      (r.patch)(f => (f.style-node)(path, ..style))
    },
    push-with-edge: (self, path, ..style) => {
      let r = (self.push-frame)()
      (r.patch)(f => (f.style-edge)(path, ..style))
    },
    push-note-node: (self, path, txt) => {
      let r = (self.push-frame)()
      (r.patch)(f => (f.note-node)(path, txt))
    },
    push-note-edge: (self, path, txt) => {
      let r = (self.push-frame)()
      (r.patch)(f => (f.note-edge)(path, txt))
    },
    render: (self) => {
      // Returns an array of content, one per frame. Spread into
      // `alternatives(..)` for animated subslides, or index into for
      // static figures.
      self.frames.map(f => {
        let canvas = _render-canvas(
          self.tree,
          f,
          self.default-node-style,
          self.default-edge-style,
        )
        if f.caption != none {
          stack(dir: ttb, spacing: 0.5em, canvas, f.caption)
        } else { canvas }
      })
    },
    static: (self, frame: -1) => {
      let idx = if frame < 0 { self.frames.len() + frame } else { frame }
      (self.render)().at(idx)
    },
  ),
)

#let make-renderer(
  tree,
  default-node-style: (:),
  default-edge-style: (:),
  sticky: true,
) = {
  (TreeRenderer.new)(
    tree: tree,
    frames: (blank-frame(),),
    default-node-style: default-node-style,
    default-edge-style: default-edge-style,
    sticky: sticky,
  )
}

// Stitch frames across multiple renderers (or pre-rendered arrays) into a
// single flat content array. Use this when an animation spans tree-shape
// changes (rotation, deletion, insertion) and one renderer can't hold all
// the frames.
#let concat-frames(..parts) = {
  let out = ()
  for p in parts.pos() {
    if type(p) == array { out += p } else { out += (p.render)() }
  }
  out
}

// ===================================================================
// Op command stream — FUTURE EXTENSION
// ===================================================================
//
// A higher-level command-stream layer on top of frames. Each Op describes
// one change; a sequence of Ops folds into a list of frames. Useful when
// the per-frame patching gets verbose. Not wired into TreeRenderer above
// — add a method like `apply: (self, ops) => ops.fold(self, _apply-op)`
// when this graduates from draft.
//
//   let ops = (
//     (Op.Highlight.new)(path: "", color: blue),
//     (Op.Annotate.new)(path: "", text: [7 < 14]),
//     (Op.Commit.new)(),                   // marks "end of this frame"
//     (Op.Highlight.new)(path: "L", color: blue),
//     ...
//   )
//   let r = apply(make-renderer(t), ops)

#let Op = enumeration(
  Highlight: class(
    name: "Op.Highlight",
    fields: (path: PathId, color: Any),
  ),
  Annotate: class(
    name: "Op.Annotate",
    fields: (path: PathId, text: Content),
  ),
  StyleEdge: class(
    name: "Op.StyleEdge",
    fields: (path: PathId, style: EdgeStyle),
  ),
  Caption: class(
    name: "Op.Caption",
    fields: (text: Content),
  ),
  Commit: class(name: "Op.Commit", fields: (:)),
  ClearNotes: class(name: "Op.ClearNotes", fields: (:)),
)

#let _apply-op(r, op) = match(
  op,
  case(Op.Highlight, () => (r.patch)(f => (f.style-node)(op.path, stroke: op.color + 2pt))),
  case(Op.Annotate, () => (r.patch)(f => (f.note-node)(op.path, op.text))),
  case(Op.StyleEdge, () => (r.patch)(f => (f.style-edge)(op.path, ..op.style))),
  case(Op.Caption, () => (r.patch)(f => (f.with-caption)(op.text))),
  case(Op.Commit, () => (r.push-frame)()),
  case(Op.ClearNotes, () => (r.patch)(f => (f.clear-notes)())),
)

#let apply-ops(renderer, ops) = ops.fold(renderer, _apply-op)
