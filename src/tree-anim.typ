// Tree animation library — frame-based, styled rendering of trees built
// on top of cetz. Built using typsy classes for immutable, chainable
// construction.
//
// The core data flow:
//
//   Snapshot       — sparse style overrides for one snapshot of the tree.
//   TreeRenderer   — a tree plus an ordered list of snapshots plus defaults.
//   Frame          — public output record: (canvas, caption, step). One per
//                    snapshot, produced by `r.render()`.
//   r.render()     — produces an array of `Frame` records, ready to be
//                    passed to a render helper (see `lib.typ`: `last`,
//                    `stacked`, `figures`) or composed into custom layouts.
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

/// Typsy refinement: a string built only from #raw("\"L\"") and
/// #raw("\"R\"") characters. The empty string is the root; #raw("\"L\"")
/// is the root's left child; #raw("\"LR\"") is the root's left child's
/// right child; and so on.
#let PathId = Refine(
  Str,
  p => p.codepoints().all(c => c == "L" or c == "R"),
)

#let _node-style-keys = ("fill", "stroke", "text-fill", "note", "note-fill", "hide")
#let _edge-style-keys = ("stroke", "note", "note-fill", "mark", "hide")

/// Typsy refinement: a dictionary of node-style overrides. Recognised
/// keys are #raw("fill"), #raw("stroke"), #raw("text-fill"),
/// #raw("note"), #raw("note-fill"), and #raw("hide").
#let NodeStyle = Refine(
  Dictionary(..Any),
  d => d.keys().all(k => _node-style-keys.contains(k)),
)

/// Typsy refinement: a dictionary of edge-style overrides. Recognised
/// keys are #raw("stroke"), #raw("note"), #raw("note-fill"),
/// #raw("mark"), and #raw("hide").
#let EdgeStyle = Refine(
  Dictionary(..Any),
  d => d.keys().all(k => _edge-style-keys.contains(k)),
)

// ===================================================================
// Snapshot — one styled snapshot
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

/// Typsy class representing one sparse style overlay — the
/// per-node and per-edge style overrides for a single frame. Build one
/// via @@blank-snapshot() and chain its #raw("style-node") /
/// #raw("style-edge") / #raw("note-node") / #raw("note-edge") /
/// #raw("clear-notes") methods. Snapshots are rarely constructed
/// directly — they're managed by @@make-renderer() and the BST's
/// #raw("*-display") methods.
#let Snapshot = class(
  name: "Snapshot",
  fields: (
    nodes: Dictionary(..NodeStyle),
    edges: Dictionary(..EdgeStyle),
  ),
  methods: (
    style-node: (self, path, ..style) => {
      let cls = self.meta.cls
      let existing = self.nodes.at(path, default: (:))
      let merged = _merge-into(existing, style.named())
      let next = self.nodes
      next.insert(path, merged)
      (cls.new)(nodes: next, edges: self.edges)
    },
    style-edge: (self, path, ..style) => {
      let cls = self.meta.cls
      let existing = self.edges.at(path, default: (:))
      let merged = _merge-into(existing, style.named())
      let next = self.edges
      next.insert(path, merged)
      (cls.new)(nodes: self.nodes, edges: next)
    },
    note-node: (self, path, txt) => (self.style-node)(path, note: txt),
    note-edge: (self, path, txt) => (self.style-edge)(path, note: txt),
    clear-notes: (self) => {
      let cls = self.meta.cls
      (cls.new)(
        nodes: _strip-notes(self.nodes),
        edges: _strip-notes(self.edges),
      )
    },
  ),
)

/// Build a fresh #raw("Snapshot") with no node or edge style overrides.
/// Useful when you want to render a tree once with #raw("draw-tree") and
/// no per-frame state.
///
/// -> Snapshot
#let blank-snapshot() = (Snapshot.new)(nodes: (:), edges: (:))

// ===================================================================
// Frame — public output record
// ===================================================================
//
// One Frame per animation step. `canvas` holds the rendered cetz canvas
// (with no caption baked in). `caption` is an optional textual track for
// that step — set by `r.with-caption(...)` and surfaced by the render
// helpers in `lib.typ`. `step` is free-form per-method metadata: each
// `*-display` BST method documents what it puts there so callers can
// drive custom layouts off it.

/// Typsy class representing one rendered animation frame. Fields:
/// #raw("canvas") (cetz content, no caption baked in),
/// #raw("caption") (optional textual track for the step, possibly
/// #raw("none")), and #raw("step") (optional free-form per-method
/// metadata, possibly #raw("none")). Produced by
/// #raw("TreeRenderer.render()"); the BST's #raw("*-display") methods
/// return arrays of these.
#let Frame = class(
  name: "Frame",
  fields: (
    canvas: Content,
    // Caption is `Any` (not `Content`) because Typst auto-coerces strings
    // to content; users should be able to pass `[6 < 7]` or `"6 < 7"`.
    caption: Union(None, Any),
    step: Union(None, Dictionary(..Any)),
  ),
  methods: (:),
)

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

/// Emit the cetz draw commands for one styled snapshot of #raw("tree"),
/// _without_ wrapping them in a #raw("cetz.canvas"). Caller is
/// responsible for the canvas wrap. Use this when you want to add your
/// own cetz annotations alongside the tree — for example, callouts
/// anchored at specific nodes.
///
/// The whole tree is wrapped in a named cetz group (#raw("name"),
/// default #raw("\"tree\"")); each non-phantom node has an inner-name
/// of #raw("<node-prefix><cetz-tree-name>") where the cetz-tree name is
/// #raw("\"0\"") for the root, #raw("\"0-0\"") for L, #raw("\"0-1\"")
/// for R, #raw("\"0-0-1\"") for LR, and so on. Fully qualified anchor
/// names therefore look like #raw("\"tree.node-0-0-1\"") — use
/// @@path-anchor() to compute them from an L/R path string.
///
/// -> content
#let draw-tree(
  /// The tree to render — any value with #raw("value"), #raw("left"),
  /// and #raw("right") fields (e.g. a #raw("BST") instance).
  /// -> dictionary
  tree,
  /// Style overlay for this snapshot. Use @@blank-snapshot() for an
  /// unstyled tree.
  /// -> Snapshot
  snapshot,
  /// Default node-style overrides applied before per-node overrides.
  /// -> dictionary
  default-node-style: (:),
  /// Default edge-style overrides applied before per-edge overrides.
  /// -> dictionary
  default-edge-style: (:),
  /// Outer group name for the whole tree. Must match the #raw("tree-name")
  /// argument to @@path-anchor() for anchors to resolve.
  /// -> str
  name: "tree",
  /// Prefix attached to each node's cetz-tree internal name. Must match
  /// the #raw("prefix") argument to @@path-anchor().
  /// -> str
  node-prefix: "node-",
) = {
  import cetz.draw
  import cetz.tree as cetz-tree
  cetz-tree.tree(
    _build-cetz-tree(tree, ""),
    name: name,
    group-name-prefix: node-prefix,
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
          snapshot.nodes.at(path, default: (:)),
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
          snapshot.edges.at(child-path, default: (:)),
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
}

// Convenience wrapper: `draw-tree` inside a `cetz.canvas`.
#let _render-canvas(tree, snapshot, default-node-style, default-edge-style) = {
  cetz.canvas(
    draw-tree(
      tree,
      snapshot,
      default-node-style: default-node-style,
      default-edge-style: default-edge-style,
    ),
  )
}

/// Translates a starling path-id (L/R string rooted at #raw("\"\"")) to
/// the fully-qualified cetz anchor name produced by @@draw-tree().
/// Path #raw("\"\"") maps to the root anchor; #raw("\"L\"")/#raw("\"R\"")
/// map to first-level children; and so on.
///
/// The #raw("tree-name") and #raw("prefix") arguments must match the
/// #raw("name") and #raw("node-prefix") passed to #raw("draw-tree").
///
/// -> str
#let path-anchor(
  /// L/R path string identifying a node (#raw("\"\"") = root,
  /// #raw("\"LR\"") = root's left child's right child, etc.).
  /// -> str
  path,
  /// Outer-group name; must match #raw("draw-tree")'s #raw("name").
  /// -> str
  tree-name: "tree",
  /// Per-node prefix; must match #raw("draw-tree")'s #raw("node-prefix").
  /// -> str
  prefix: "node-",
) = {
  let segments = ("0",)
  for c in path.codepoints() {
    segments.push(if c == "L" { "0" } else { "1" })
  }
  tree-name + "." + prefix + segments.join("-")
}

// Three parallel arrays. `snapshots[i]` is the style snapshot for the i-th
// frame; `captions[i]` and `steps[i]` are the optional caption and metadata
// for that frame. All three are kept in lockstep — `push-frame` appends to
// each, `patch` / `with-caption` / `with-step` modify the tail. `render`
// zips them into `Frame` records.
/// Typsy class accumulating an animation. Holds the tree, parallel
/// arrays of snapshots / captions / steps (one entry per frame), and
/// default node/edge styles. Methods include #raw("push-frame()"),
/// #raw("patch(fn)"), #raw("push-with-node(path, ..style)"),
/// #raw("push-with-edge(path, ..style)"),
/// #raw("push-note-node(path, txt)"), #raw("push-note-edge(path, txt)"),
/// #raw("with-caption(c)"), #raw("with-step(s)"), and
/// #raw("render()"). Build one via @@make-renderer().
#let TreeRenderer = class(
  name: "TreeRenderer",
  fields: (
    tree: Any,
    snapshots: Array(..Any),
    captions: Array(..Any),
    steps: Array(..Any),
    default-node-style: NodeStyle,
    default-edge-style: EdgeStyle,
    sticky: Bool,
  ),
  methods: (
    push-frame: (self) => {
      let cls = self.meta.cls
      let base = if self.sticky and self.snapshots.len() > 0 {
        self.snapshots.last()
      } else {
        blank-snapshot()
      }
      (cls.new)(
        tree: self.tree,
        snapshots: self.snapshots + (base,),
        captions: self.captions + (none,),
        steps: self.steps + (none,),
        default-node-style: self.default-node-style,
        default-edge-style: self.default-edge-style,
        sticky: self.sticky,
      )
    },
    patch: (self, fn) => {
      let cls = self.meta.cls
      assert(
        self.snapshots.len() > 0,
        message: "patch: no frames yet — call push-frame first.",
      )
      let next = self.snapshots
      next.at(next.len() - 1) = fn(next.last())
      (cls.new)(
        tree: self.tree,
        snapshots: next,
        captions: self.captions,
        steps: self.steps,
        default-node-style: self.default-node-style,
        default-edge-style: self.default-edge-style,
        sticky: self.sticky,
      )
    },
    with-caption: (self, c) => {
      let cls = self.meta.cls
      assert(
        self.captions.len() > 0,
        message: "with-caption: no frames yet — call push-frame first.",
      )
      let next = self.captions
      next.at(next.len() - 1) = c
      (cls.new)(
        tree: self.tree,
        snapshots: self.snapshots,
        captions: next,
        steps: self.steps,
        default-node-style: self.default-node-style,
        default-edge-style: self.default-edge-style,
        sticky: self.sticky,
      )
    },
    with-step: (self, s) => {
      let cls = self.meta.cls
      assert(
        self.steps.len() > 0,
        message: "with-step: no frames yet — call push-frame first.",
      )
      let next = self.steps
      next.at(next.len() - 1) = s
      (cls.new)(
        tree: self.tree,
        snapshots: self.snapshots,
        captions: self.captions,
        steps: next,
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
      // Returns an array of `Frame` records, one per snapshot. Pass to
      // a render helper in `lib.typ` (`last`, `stacked`, `figures`) or
      // build a custom layout from `frame.canvas` / `frame.caption` /
      // `frame.step`.
      self.snapshots
        .enumerate()
        .map(((i, snap)) => {
          let canvas = _render-canvas(
            self.tree,
            snap,
            self.default-node-style,
            self.default-edge-style,
          )
          (Frame.new)(
            canvas: canvas,
            caption: self.captions.at(i),
            step: self.steps.at(i),
          )
        })
    },
  ),
)

/// Build a #raw("TreeRenderer") seeded with one blank initial frame.
///
/// With #raw("sticky: true") (the default), each new frame pushed via
/// #raw("r.push-frame()") starts from the previous frame's style
/// snapshot — so highlights accumulate over the course of an animation.
/// Set #raw("sticky: false") to start each frame from a clean slate.
///
/// -> TreeRenderer
#let make-renderer(
  /// The tree to render — any value with #raw("value"), #raw("left"),
  /// and #raw("right") fields.
  /// -> dictionary
  tree,
  /// Default node-style overrides applied before per-snapshot overrides.
  /// -> dictionary
  default-node-style: (:),
  /// Default edge-style overrides applied before per-snapshot overrides.
  /// -> dictionary
  default-edge-style: (:),
  /// When #raw("true"), new frames inherit the previous frame's style.
  /// When #raw("false"), each new frame starts blank.
  /// -> bool
  sticky: true,
) = {
  (TreeRenderer.new)(
    tree: tree,
    snapshots: (blank-snapshot(),),
    captions: (none,),
    steps: (none,),
    default-node-style: default-node-style,
    default-edge-style: default-edge-style,
    sticky: sticky,
  )
}

/// Stitch frame arrays from multiple renderers (or pre-rendered arrays)
/// into one flat #raw("Array(Frame)"). Use this when an animation spans
/// a tree-shape change (rotation, deletion, insertion) and one
/// renderer can't hold all the frames — one renderer per shape, joined
/// at the boundary.
///
/// Accepts a mix of #raw("TreeRenderer") instances and already-rendered
/// arrays; the former are #raw("render")-ed in place.
///
/// -> array
#let concat-frames(
  /// Variadic mix of renderers and frame arrays.
  ..parts,
) = {
  let out = ()
  for p in parts.pos() {
    if type(p) == array { out += p } else { out += (p.render)() }
  }
  out
}

// ===================================================================
// Op command stream
// ===================================================================
//
// A declarative layer over the per-frame patch API. Each Op describes a
// single change to the in-progress frame; `Op.Commit` finalizes that
// frame and opens a fresh one. Fold a sequence of Ops into a renderer
// with `apply-ops`.
//
// Variants:
//   Highlight(path, color)     — set node stroke to `color + 2pt`
//   Annotate(path, text)       — attach a note to a node (drawn in-canvas)
//   StyleNode(path, style)     — arbitrary node-style overrides
//   StyleEdge(path, style)     — arbitrary edge-style overrides
//   Commit                     — finalize the current frame
//   ClearNotes                 — drop all notes on the current frame
//
// Captions and step metadata are renderer-level (not snapshot-level), so
// they're set directly on the renderer between Op batches via
// `r.with-caption(...)` / `r.with-step(...)` rather than through an Op.
//
// Example:
//
//   let ops = (
//     (Op.Highlight.new)(path: "", color: blue),
//     (Op.Annotate.new)(path: "", text: [7 < 14]),
//     (Op.Commit.new)(),
//     (Op.Highlight.new)(path: "L", color: blue),
//   )
//   let r = apply-ops(make-renderer(t), ops)
//   let frames = (r.render)()
//
// The trailing in-progress frame is kept — no explicit `Commit` is needed
// after the last batch of edits.

/// Typsy enumeration describing a declarative command stream for
/// building animations. Variants:
///
/// - #raw("Op.Highlight(path, color)") — set a node's stroke to
///   #raw("color + 2pt").
/// - #raw("Op.Annotate(path, text)") — attach an inline note to a
///   node (drawn in-canvas).
/// - #raw("Op.StyleNode(path, style)") — arbitrary node-style
///   overrides.
/// - #raw("Op.StyleEdge(path, style)") — arbitrary edge-style
///   overrides.
/// - #raw("Op.Commit()") — finalise the current frame and open a
///   fresh one.
/// - #raw("Op.ClearNotes()") — drop all notes from the current
///   frame's snapshot.
///
/// Captions and step metadata are renderer-level rather than
/// snapshot-level: set them between Op batches via
/// #raw("r.with-caption(...)") / #raw("r.with-step(...)"), not
/// through an Op. Fold a sequence of Ops into a renderer with
/// @@apply-ops().
#let Op = enumeration(
  Highlight: class(
    name: "Op.Highlight",
    fields: (path: PathId, color: Any),
  ),
  Annotate: class(
    name: "Op.Annotate",
    fields: (path: PathId, text: Content),
  ),
  StyleNode: class(
    name: "Op.StyleNode",
    fields: (path: PathId, style: NodeStyle),
  ),
  StyleEdge: class(
    name: "Op.StyleEdge",
    fields: (path: PathId, style: EdgeStyle),
  ),
  Commit: class(name: "Op.Commit", fields: (:)),
  ClearNotes: class(name: "Op.ClearNotes", fields: (:)),
)

#let _apply-op(r, op) = match(
  op,
  case(Op.Highlight, () => (r.patch)(f => (f.style-node)(op.path, stroke: op.color + 2pt))),
  case(Op.Annotate, () => (r.patch)(f => (f.note-node)(op.path, op.text))),
  case(Op.StyleNode, () => (r.patch)(f => (f.style-node)(op.path, ..op.style))),
  case(Op.StyleEdge, () => (r.patch)(f => (f.style-edge)(op.path, ..op.style))),
  case(Op.Commit, () => (r.push-frame)()),
  case(Op.ClearNotes, () => (r.patch)(f => (f.clear-notes)())),
)

/// Fold a sequence of @@Op values into a renderer, returning the
/// updated renderer. The trailing in-progress frame is kept — no
/// explicit #raw("Op.Commit") is needed after the last batch of edits.
///
/// -> TreeRenderer
#let apply-ops(
  /// The renderer to apply ops to.
  /// -> TreeRenderer
  renderer,
  /// Sequence of @@Op values to fold left-to-right.
  /// -> array
  ops,
) = ops.fold(renderer, _apply-op)
