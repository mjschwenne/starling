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

#let _node-style-keys = (
  "fill",
  "stroke",
  "text-fill",
  "note",
  "note-fill",
  "hide",
  "shape",
  "tag",
  "label",
  "materialize",
)
#let _edge-style-keys = (
  "stroke",
  "note",
  "note-fill",
  "mark",
  "hide",
  "parent-anchor",
  "child-anchor",
  "force-show",
)

/// Typsy refinement: a dictionary of node-style overrides. Recognised
/// keys are #raw("fill"), #raw("stroke"), #raw("text-fill"),
/// #raw("note"), #raw("note-fill"), #raw("hide"), #raw("shape"),
/// #raw("tag"), #raw("label"), and #raw("materialize"). #raw("shape")
/// accepts the string #raw("\"circle\"") (default),
/// #raw("\"triangle\"") (apex up; useful as a subtree-summary marker),
/// or #raw("\"rectangle\""). The triangle and rectangle share a 1.4×1.2
/// bounding box; the circle keeps its 1.2×1.2 footprint. Named cetz
/// anchors on the node's group (#raw("north"), #raw("south"),
/// #raw("east"), #raw("west")) follow each shape's bounding box.
/// #raw("tag") is a small piece of content drawn just outside the west
/// of the node — useful for compact per-node annotations that don't
/// compete with the label or the operation #raw("note") slot (e.g. the
/// RBT black-height bits enabled by #raw("display(bits: true)")).
/// #raw("label") replaces the node's rendered label (otherwise derived
/// from the tree node's #raw("label") field, or #raw("str(value)") when
/// that's #raw("auto")). #raw("materialize: true") draws an otherwise-
/// phantom slot as a real node — useful for one-off pedagogical
/// animations that need to expose a nil child (e.g. rendering ∅ at a
/// just-deleted leaf's position). Phantoms only exist at paths the tree
/// either naturally generates as layout-balance siblings or where an
/// edge style sets #raw("force-show: true"); materializing without one
/// of those has no node to attach to.
#let NodeStyle = Refine(
  Dictionary(..Any),
  d => d.keys().all(k => _node-style-keys.contains(k)),
)

/// Typsy refinement: a dictionary of edge-style overrides. Recognised
/// keys are #raw("stroke"), #raw("note"), #raw("note-fill"),
/// #raw("mark"), #raw("hide"), #raw("parent-anchor"),
/// #raw("child-anchor"), and #raw("force-show"). The two
/// #raw("*-anchor") keys accept a cetz anchor name (e.g.
/// #raw("\"north\"")) and override the default fractional-distance
/// endpoint on the parent or child side respectively; useful for
/// connecting edges to non-circular shapes (e.g. #raw("child-anchor:
/// \"north\"") to land on a triangle's apex). #raw("force-show: true")
/// renders an edge even when one endpoint is a phantom — used by the
/// RBT delete animation to draw a stub edge into a now-nil position
/// when marking double-black.
#let EdgeStyle = Refine(
  Dictionary(..Any),
  d => d.keys().all(k => _edge-style-keys.contains(k)),
)

// ===================================================================
// Render theme — structural defaults for the unstyled tree
// ===================================================================
//
// The render theme is the lowest layer in the style chain: it supplies
// the literal whites/blacks/etc. that `draw-tree` falls back on when a
// snapshot doesn't override a property. Above this layer sit (in
// merge order, lowest precedence first):
//
//   1. `default-render-theme` (this dict)
//   2. user overrides set via `set-render-theme(...)` or passed as
//      `theme: (...)` to `make-renderer`
//   3. `default-node-style` / `default-edge-style` on `make-renderer`
//   4. per-snapshot per-path overrides
//
// Users who want operation-specific colors (search/insert/delete
// highlights, rotation pivots, etc.) should look at `default-op-theme`
// in `op-theme.typ` instead — that's the semantic layer shared across
// data structures.

/// Default render theme. The structural defaults the renderer falls
/// back on when neither a snapshot nor `default-node-style`/
/// `default-edge-style` specifies otherwise.
#let default-render-theme = (
  node-fill: white,
  node-stroke: black,
  node-text-fill: black,
  edge-stroke: black,
  note-fill: rgb("#d4a017"),
)

#let _render-theme-keys = (
  "node-fill",
  "node-stroke",
  "node-text-fill",
  "edge-stroke",
  "note-fill",
)

/// Typsy refinement: a dictionary whose keys are a subset of the
/// render-theme keys (#raw("node-fill"), #raw("node-stroke"),
/// #raw("node-text-fill"), #raw("edge-stroke"), #raw("note-fill")).
#let RenderTheme = Refine(
  Dictionary(..Any),
  d => d.keys().all(k => _render-theme-keys.contains(k)),
)

// Internal Typst state holding the active render theme. Read inside
// `context { }` blocks at render time so a `set-render-theme(..)` in
// the document body propagates to canvases placed after it.
#let _render-theme-state = state(
  "starling:render-theme",
  default-render-theme,
)

/// Override one or more render-theme keys for the rest of the
/// document (state-based, scoped by Typst's normal layout flow). Pass
/// a partial dictionary — only the keys you list are changed; the rest
/// stay at their current values. Unknown keys panic.
#let set-render-theme(theme) = {
  for k in theme.keys() {
    if not _render-theme-keys.contains(k) {
      panic(
        "set-render-theme: unknown key '"
          + k
          + "'. Valid keys: "
          + _render-theme-keys.join(", ")
          + ".",
      )
    }
  }
  _render-theme-state.update(prev => {
    let next = prev
    for (k, v) in theme.pairs() { next.insert(k, v) }
    next
  })
}

// Merge a partial render-theme override into `default-render-theme`,
// panicking on unknown keys. Used by `make-renderer`'s explicit
// `theme:` argument (the non-state path).
#let _merge-render-theme(override) = {
  for k in override.keys() {
    if not _render-theme-keys.contains(k) {
      panic(
        "render-theme: unknown key '"
          + k
          + "'. Valid keys: "
          + _render-theme-keys.join(", ")
          + ".",
      )
    }
  }
  let next = default-render-theme
  for (k, v) in override.pairs() { next.insert(k, v) }
  next
}

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

/// Typsy class representing one frame in an animation. Fields and
/// methods:
///
/// - #raw("render(op-theme, render-theme)") — method that, given
///   resolved theme dicts, produces the cetz canvas for this frame.
///   Theming-aware deferral lives here: by carrying a builder rather
///   than pre-baked content, the lib.typ helpers (#raw("last"),
///   #raw("stacked"), #raw("figures")) can resolve theme state once
///   per call instead of once per frame, which is meaningfully faster
///   in many-tree documents. Per-data-structure themes (e.g. the RBT
///   palette) are read inside each frame's builder rather than passed
///   in — the helpers only carry the two universal layers.
/// - #raw("caption") — optional textual track for the step (possibly
///   #raw("none")).
/// - #raw("step") — optional free-form per-method metadata (possibly
///   #raw("none")).
/// - #raw("alt") — optional accessible text describing the frame
///   (possibly #raw("none")). Carried verbatim into the #raw("alt:")
///   argument on the Typst #raw("figure") wrapping the canvas. The
///   first frame of each operation includes the full tree structure
///   (via the BST #raw("describe") method) so screen-reader users have
///   a baseline; subsequent frames describe only the per-step change.
///
/// Direct rendering pattern for custom layouts:
/// ```typc
/// context {
///   let op = _op-theme-state.get()
///   let rt = _render-theme-state.get()
///   ... (frame.render)(op, rt) ...
/// }
/// ```
/// Or simply pass the frame array to one of the lib.typ helpers, which
/// handle the state wrap for you.
///
/// The internal #raw("_builder") field carries the actual rendering
/// closure wrapped in a singleton dict so typsy's auto-self-injection
/// doesn't fire on it; treat it as private and call #raw("render")
/// instead.
#let Frame = class(
  name: "Frame",
  fields: (
    // Singleton dict `(fn: ..)` rather than a bare function so typsy's
    // class-field accessor doesn't auto-wrap it with a self-injecting
    // shim (any function-typed field gets that treatment, which would
    // turn `(frame._builder)(bt, rt)` into a 3-arg call). Read through
    // the `render` method below.
    _builder: Dictionary(..Any),
    // Caption is `Any` (not `Content`) because Typst auto-coerces strings
    // to content; users should be able to pass `[6 < 7]` or `"6 < 7"`.
    caption: Union(None, Any),
    step: Union(None, Dictionary(..Any)),
    alt: Union(None, Any),
  ),
  methods: (
    render: (self, bt, rt) => (self._builder.fn)(bt, rt),
  ),
)

// ===================================================================
// TreeRenderer
// ===================================================================

#let _phantom(path) = (((value: none, label: auto, path: path, phantom: true),),)

#let _build-cetz-tree(node, path, forced-phantoms: ()) = {
  // BST-shaped accessor. Generalize here for n-ary trees.
  //
  // When a node has exactly one child, we inject a phantom sibling on the
  // opposite side so cetz's tree layout doesn't put the lone child directly
  // under its parent — single children should visibly hang off to one side.
  // Phantoms are detected in draw-{node,edge} via `content.phantom` and
  // skipped at draw time, but they still occupy layout space.
  //
  // `forced-phantoms` lists paths that must materialize as phantoms even
  // when the natural single-child rule wouldn't add them — used by the
  // double-black dot rendering, so the stub edge has a node to anchor to
  // when both children are nil.
  let has-left = node.left != none
  let has-right = node.right != none
  let force-left = forced-phantoms.contains(path + "L")
  let force-right = forced-phantoms.contains(path + "R")
  // Pair-up rule: at a leaf, a single forced phantom would be laid out
  // directly below the parent. Inject the opposite-side phantom too so
  // the forced one hangs off to its side, matching how a single real
  // child gets a phantom sibling.
  let leaf-force = (
    not has-left and not has-right and (force-left or force-right)
  )
  let children = ()
  if has-left {
    children.push(_build-cetz-tree(
      node.left,
      path + "L",
      forced-phantoms: forced-phantoms,
    ))
  } else if has-right or force-left or leaf-force {
    children.push(.._phantom(path + "L"))
  }
  if has-right {
    children.push(_build-cetz-tree(
      node.right,
      path + "R",
      forced-phantoms: forced-phantoms,
    ))
  } else if has-left or force-right or leaf-force {
    children.push(.._phantom(path + "R"))
  }
  ((value: node.value, label: node.label, path: path), ..children)
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
  /// The tree to render — any value with #raw("value"), #raw("label"),
  /// #raw("left"), and #raw("right") fields (e.g. a #raw("BST") instance).
  /// #raw("label") of #raw("auto") falls back to #raw("str(value)");
  /// any other value (string, image, content) is rendered as the node's
  /// drawn label.
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
  /// Structural defaults — the lowest layer of the style chain.
  /// Defaults to #raw("default-render-theme"); pass an already-merged
  /// dict (e.g. read from #raw("set-render-theme")'s state inside a
  /// #raw("context") block) to apply user overrides.
  /// -> dictionary
  render-theme: default-render-theme,
  /// Outer group name for the whole tree. Must match the #raw("tree-name")
  /// argument to @@path-anchor() for anchors to resolve.
  /// -> str
  name: "tree",
  /// Prefix attached to each node's cetz-tree internal name. Must match
  /// the #raw("prefix") argument to @@path-anchor().
  /// -> str
  node-prefix: "node-",
  /// Depth-direction layout factor passed to cetz-tree. Values below
  /// #raw("1") shorten edges between levels; values above #raw("1")
  /// stretch them. Node sizes are unaffected.
  /// -> float
  grow: 1,
  /// Sibling-direction layout factor passed to cetz-tree. Values below
  /// #raw("1") pull siblings together; values above #raw("1") push them
  /// apart. Node sizes are unaffected.
  /// -> float
  spread: 1,
) = {
  import cetz.draw
  import cetz.tree as cetz-tree
  // Any edge styled with `force-show: true` for a path that wouldn't
  // naturally exist (both children nil) needs a phantom anchor so the
  // stub edge has somewhere to land — used by the double-black dot.
  let forced-phantoms = snapshot.edges.pairs()
    .filter(p => p.at(1).at("force-show", default: false))
    .map(p => p.at(0))
  cetz-tree.tree(
    _build-cetz-tree(tree, "", forced-phantoms: forced-phantoms),
    name: name,
    group-name-prefix: node-prefix,
    grow: grow,
    spread: spread,
    draw-node: (node, ..) => {
        let path = node.content.path
        let s = _merge-into(
          default-node-style,
          snapshot.nodes.at(path, default: (:)),
        )
        let is-phantom = node.content.at("phantom", default: false)
        if is-phantom and not s.at("materialize", default: false) {
          // Reserve a slightly-wider-than-a-node layout footprint, but
          // render nothing. `bounds: true` keeps the bounding box for
          // cetz's tree layout while hiding the drawable. Width > node
          // diameter so the lone real sibling visibly hangs off-center
          // rather than sitting almost-under its parent.
          draw.hide(draw.rect((-0.9, -0.6), (0.9, 0.6)), bounds: true)
          return
        }
        if s.at("hide", default: false) { return }
        let value = node.content.value
        let raw-label = node.content.label
        let default-label = if raw-label == auto {
          if value == none { "" } else { str(value) }
        } else { raw-label }
        let label = s.at("label", default: default-label)
        // Shape dispatch. New shapes go here; keep bounding boxes
        // sensible so the named cetz anchors (north/south/east/west on
        // the node group) land where users expect, since the edge
        // anchor overrides reference them. `label-pos` shifts the
        // label off the geometric origin for shapes that taper — a
        // triangle's apex narrows to nothing at the top, so its
        // label sits at the centroid (y = -0.2) where the shape is
        // wide enough to host larger fonts without clipping the
        // sloped sides.
        let shape = s.at("shape", default: "circle")
        let fill-c = s.at("fill", default: render-theme.node-fill)
        let stroke-c = s.at("stroke", default: render-theme.node-stroke)
        let label-pos = (0, 0)
        if shape == "circle" {
          draw.circle((), radius: 0.6, fill: fill-c, stroke: stroke-c)
        } else if shape == "triangle" {
          draw.line(
            (0, 0.6),
            (-0.7, -0.6),
            (0.7, -0.6),
            close: true,
            fill: fill-c,
            stroke: stroke-c,
          )
          label-pos = (0, -0.2)
        } else if shape == "rectangle" {
          draw.rect(
            (-0.7, -0.6),
            (0.7, 0.6),
            fill: fill-c,
            stroke: stroke-c,
          )
        } else {
          panic(
            "draw-tree: unknown node shape "
              + repr(shape)
              + "; supported: \"circle\", \"triangle\", \"rectangle\".",
          )
        }
        let tf = s.at("text-fill", default: render-theme.node-text-fill)
        // Bold the label via `weight:` rather than `*..*` markup so a
        // user `show strong: set text(fill: ..)` rule in the document
        // can't override our computed `tf` — the contrast-aware fill
        // in `_text-fill-for` exists precisely so labels stay readable
        // against gradient-filled traversal nodes, and we don't want it
        // silently undone by ambient styling.
        // Anchor explicitly at `label-pos` (set by the shape branch
        // above) rather than `()` (the previous cetz coordinate).
        // After `draw.line(..)` or `draw.rect(..)`, the previous
        // coordinate is the last vertex/corner, not the centre.
        draw.content(label-pos, text(weight: "bold", fill: tf, label))
        let n = s.at("note", default: none)
        if n != none {
          let nf = s.at("note-fill", default: render-theme.note-fill)
          draw.content(
            (0.75, 0),
            anchor: "west",
            text(fill: nf, size: 0.8em, n),
          )
        }
        // Tag — small annotation pinned just outside the west of the
        // node. Used by RBT `display(bits: true)` to show per-node
        // black-height bits. Drawn in the render theme's edge-stroke
        // color so it reads as a marginal annotation rather than node
        // content. West of equator avoids overlap with the incoming
        // parent edge (NE / NW) and outgoing child edges (SW / SE).
        let tag = s.at("tag", default: none)
        if tag != none {
          draw.content(
            (-0.65, 0),
            anchor: "east",
            text(fill: render-theme.edge-stroke, size: 0.7em, tag),
          )
        }
      },
      draw-edge: (from, to, ..) => {
        let child-path = to.content.path
        let s = _merge-into(
          default-edge-style,
          snapshot.edges.at(child-path, default: (:)),
        )
        // Phantom edges are skipped by default. `force-show: true` lets
        // a stub edge render to (or from) a phantom — used to visualise
        // double-black on a now-nil tree slot.
        let force = s.at("force-show", default: false)
        if not force and to.content.at("phantom", default: false) { return }
        if not force and from.content.at("phantom", default: false) { return }
        if s.at("hide", default: false) { return }
        let mark = s.at("mark", default: none)
        // Endpoint resolution. Default is the empirical 0.4-fractional
        // trick (lands cleanly in the gap between two circle nodes); a
        // `parent-anchor` / `child-anchor` override swaps that side
        // for a named cetz anchor on the node group, which is how
        // non-circular shapes (triangle apex, etc.) get clean
        // connections.
        let parent-coord = if "parent-anchor" in s {
          from.group-name + "." + s.at("parent-anchor")
        } else {
          (from.group-name, 0.4, to.group-name)
        }
        let child-coord = if "child-anchor" in s {
          to.group-name + "." + s.at("child-anchor")
        } else {
          (to.group-name, 0.4, from.group-name)
        }
        draw.line(
          parent-coord,
          child-coord,
          stroke: s.at("stroke", default: render-theme.edge-stroke),
          ..if mark != none { (mark: mark) },
        )
        let n = s.at("note", default: none)
        if n != none {
          let nf = s.at("note-fill", default: render-theme.note-fill)
          draw.content(
            (from.group-name, 0.5, to.group-name),
            text(fill: nf, size: 0.8em, n),
          )
        }
      },
  )
}

// Convenience wrapper: `draw-tree` inside a `cetz.canvas`.
#let _render-canvas(
  tree,
  snapshot,
  default-node-style,
  default-edge-style,
  render-theme,
) = {
  cetz.canvas(
    draw-tree(
      tree,
      snapshot,
      default-node-style: default-node-style,
      default-edge-style: default-edge-style,
      render-theme: render-theme,
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

// Four parallel arrays. `snapshots[i]` is the style snapshot for the
// i-th frame; `captions[i]`, `steps[i]`, and `alts[i]` are the optional
// caption, metadata, and accessible-text track for that frame. All four
// are kept in lockstep — `push-frame` appends to each,
// `patch` / `with-caption` / `with-step` / `with-alt` modify the tail.
// `render` zips them into `Frame` records.
/// Typsy class accumulating an animation. Holds the tree, parallel
/// arrays of snapshots / captions / steps / alts (one entry per frame),
/// and default node/edge styles. Methods include
/// #raw("push-frame()"), #raw("patch(fn)"),
/// #raw("push-with-node(path, ..style)"),
/// #raw("push-with-edge(path, ..style)"),
/// #raw("push-note-node(path, txt)"), #raw("push-note-edge(path, txt)"),
/// #raw("with-caption(c)"), #raw("with-step(s)"), #raw("with-alt(a)"),
/// and #raw("render()"). Build one via @@make-renderer().
#let TreeRenderer = class(
  name: "TreeRenderer",
  fields: (
    tree: Any,
    snapshots: Array(..Any),
    captions: Array(..Any),
    steps: Array(..Any),
    alts: Array(..Any),
    default-node-style: NodeStyle,
    default-edge-style: EdgeStyle,
    sticky: Bool,
    // `auto` => read render-theme from state at render time.
    // dict   => baked-in merged render-theme (no state lookup).
    theme: Any,
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
        alts: self.alts + (none,),
        default-node-style: self.default-node-style,
        default-edge-style: self.default-edge-style,
        sticky: self.sticky,
        theme: self.theme,
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
        alts: self.alts,
        default-node-style: self.default-node-style,
        default-edge-style: self.default-edge-style,
        sticky: self.sticky,
        theme: self.theme,
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
        alts: self.alts,
        default-node-style: self.default-node-style,
        default-edge-style: self.default-edge-style,
        sticky: self.sticky,
        theme: self.theme,
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
        alts: self.alts,
        default-node-style: self.default-node-style,
        default-edge-style: self.default-edge-style,
        sticky: self.sticky,
        theme: self.theme,
      )
    },
    with-alt: (self, a) => {
      let cls = self.meta.cls
      assert(
        self.alts.len() > 0,
        message: "with-alt: no frames yet — call push-frame first.",
      )
      let next = self.alts
      next.at(next.len() - 1) = a
      (cls.new)(
        tree: self.tree,
        snapshots: self.snapshots,
        captions: self.captions,
        steps: self.steps,
        alts: next,
        default-node-style: self.default-node-style,
        default-edge-style: self.default-edge-style,
        sticky: self.sticky,
        theme: self.theme,
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
      // build a custom layout from `frame.render` / `frame.caption` /
      // `frame.step` / `frame.alt`.
      //
      // Each frame's `render` field is a function
      // `(op-theme, render-theme) => content`. The lib.typ helpers
      // resolve theme state once per call and feed the result to every
      // frame's builder; for direct use, see the `Frame` docstring.
      //
      // When `self.theme` is a dict (explicit override via
      // `make-renderer(theme: ..)`), the supplied render-theme argument
      // is ignored in favour of the baked-in dict.
      let theme = self.theme
      let tree = self.tree
      let dns = self.default-node-style
      let des = self.default-edge-style
      self.snapshots
        .enumerate()
        .map(((i, snap)) => {
          let render-fn = (_bt, rt) => {
            let effective-rt = if theme == auto { rt } else { theme }
            _render-canvas(tree, snap, dns, des, effective-rt)
          }
          (Frame.new)(
            _builder: (fn: render-fn),
            caption: self.captions.at(i),
            step: self.steps.at(i),
            alt: self.alts.at(i),
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
/// With #raw("theme: auto") (the default), each rendered canvas reads
/// the active render theme from state at layout time, so a
/// #raw("set-render-theme(..)") earlier in the document propagates.
/// Pass an explicit dictionary to bake a theme in and skip the state
/// lookup.
///
/// -> TreeRenderer
#let make-renderer(
  /// The tree to render — any value with #raw("value"), #raw("label"),
  /// #raw("left"), and #raw("right") fields. See @@draw-tree() for how
  /// #raw("label") is rendered.
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
  /// Render-theme override for this renderer. #raw("auto") reads the
  /// active render-theme from state at layout time. A dict is merged
  /// into #raw("default-render-theme") once and baked in.
  /// -> auto | dictionary
  theme: auto,
) = {
  let resolved-theme = if theme == auto {
    auto
  } else {
    _merge-render-theme(theme)
  }
  (TreeRenderer.new)(
    tree: tree,
    snapshots: (blank-snapshot(),),
    captions: (none,),
    steps: (none,),
    alts: (none,),
    default-node-style: default-node-style,
    default-edge-style: default-edge-style,
    sticky: sticky,
    theme: resolved-theme,
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
// frame (attaching its alt text) and opens a fresh one. Fold a sequence
// of Ops into a renderer with `apply-ops`.
//
// Variants:
//   Highlight(path, color)     — set node stroke to `color + 2pt`
//   Annotate(path, text)       — attach a note to a node (drawn in-canvas)
//   StyleNode(path, style)     — arbitrary node-style overrides
//   StyleEdge(path, style)     — arbitrary edge-style overrides
//   Commit(alt)                — finalize the current frame with alt text
//                                and open a new blank one
//   Alt(text)                  — set alt text on the in-progress frame
//                                without committing (use for the trailing
//                                frame, which has no following Commit)
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
//     (Op.Commit.new)(alt: "Comparing 7 against the root 14."),
//     (Op.Highlight.new)(path: "L", color: blue),
//     (Op.Alt.new)(text: "Descended into the left subtree."),
//   )
//   let r = apply-ops(make-renderer(t), ops)
//   let frames = (r.render)()
//
// The trailing in-progress frame is kept — no explicit `Commit` is needed
// after the last batch of edits, but its alt text must be attached via
// `Op.Alt` (or `r.with-alt(...)` after the fold).

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
/// - #raw("Op.Commit(alt)") — finalise the current frame, attach
///   #raw("alt") text to it, and open a fresh blank frame.
///   #raw("alt") is required so every frame the command stream
///   produces carries accessible text.
/// - #raw("Op.Alt(text)") — set alt text on the in-progress frame
///   without committing. Primary use is the trailing frame, which has
///   no following #raw("Op.Commit") to carry its alt; can also be
///   used to set alt earlier in a frame's lifecycle if convenient.
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
  Commit: class(name: "Op.Commit", fields: (alt: Any)),
  Alt: class(name: "Op.Alt", fields: (text: Any)),
  ClearNotes: class(name: "Op.ClearNotes", fields: (:)),
)

#let _apply-op(r, op) = match(
  op,
  case(Op.Highlight, () => (r.patch)(f => (f.style-node)(op.path, stroke: op.color + 2pt))),
  case(Op.Annotate, () => (r.patch)(f => (f.note-node)(op.path, op.text))),
  case(Op.StyleNode, () => (r.patch)(f => (f.style-node)(op.path, ..op.style))),
  case(Op.StyleEdge, () => (r.patch)(f => (f.style-edge)(op.path, ..op.style))),
  case(Op.Commit, () => {
    let r2 = (r.with-alt)(op.alt)
    (r2.push-frame)()
  }),
  case(Op.Alt, () => (r.with-alt)(op.text)),
  case(Op.ClearNotes, () => (r.patch)(f => (f.clear-notes)())),
)

/// Fold a sequence of @@Op values into a renderer, returning the
/// updated renderer. The trailing in-progress frame is kept — no
/// explicit #raw("Op.Commit") is needed after the last batch of edits,
/// but attach alt text to that trailing frame via #raw("Op.Alt") (or
/// #raw("r.with-alt(...)") on the returned renderer) so it has
/// accessible text like the committed frames do.
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
