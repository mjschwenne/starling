// Animation core — the structure-agnostic kernel shared by every
// renderer (trees in `tree-anim.typ`, graphs in `graph-draw.typ`).
//
// The core data flow:
//
//   Snapshot   — sparse style overrides for one snapshot of a structure.
//   Renderer   — a structure plus an ordered list of snapshots plus
//                defaults plus a *draw backend*. The draw backend is the
//                only structure-specific piece: a function
//                `(structure, snapshot, default-node-style,
//                 default-edge-style, render-theme) -> cetz draw commands`.
//                Trees inject `draw-tree`; graphs inject `draw-graph`.
//   Frame      — public output record carrying a render closure, caption,
//                step metadata, and alt text. One per snapshot, produced
//                by `r.render()`.
//
// Everything here keys nodes and edges by *opaque strings*. The string
// alphabet is the backend's business: binary/n-ary tree paths
// (`PathId` in `tree-anim.typ`), graph node ids and edge keys
// (`graph-draw.typ`). The core never interprets them.

#import "@preview/typsy:0.2.2": *
#import "@preview/cetz:0.5.2"

// ===================================================================
// Style refinements
// ===================================================================

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
  "key-styles",
  // Graph node geometry (consumed by `draw-graph`; the tree backend
  // uses fixed bounding boxes and ignores these). `r` is the circle
  // radius; `rx`/`ry` are the ellipse/rectangle half-extents;
  // `autosize` fits the node to its label via `measure`; `pad-x`/
  // `pad-y` pad the autosize fit. All in cetz units.
  "r",
  "rx",
  "ry",
  "autosize",
  "pad-x",
  "pad-y",
)
#let _edge-style-keys = (
  "stroke",
  "note",
  "note-fill",
  "tag",
  "mark",
  "hide",
  "parent-anchor",
  "child-anchor",
  "force-show",
  "bend",
)

/// Typsy refinement: a dictionary of node-style overrides. Recognised
/// keys are #raw("fill"), #raw("stroke"), #raw("text-fill"),
/// #raw("note"), #raw("note-fill"), #raw("hide"), #raw("shape"),
/// #raw("tag"), #raw("label"), #raw("materialize"), and
/// #raw("key-styles"). #raw("shape") accepts the string
/// #raw("\"circle\"") (default), #raw("\"triangle\"") (apex up; useful
/// as a subtree-summary marker), #raw("\"rectangle\""), or
/// #raw("\"btree-node\"") (B24 subdivided rectangle; reads the node's
/// #raw("keys") array). The triangle and rectangle share a 1.4×1.2
/// bounding box; the circle keeps its 1.2×1.2 footprint; the
/// #raw("btree-node") width scales as #raw("1.2 × keys.len()"), height
/// stays 1.2. Named cetz anchors on the node's group (#raw("north"),
/// #raw("south"), #raw("east"), #raw("west")) follow each shape's
/// bounding box; #raw("btree-node") additionally exposes
/// #raw("key-<i>") anchors at each compartment center and
/// #raw("gap-<i>") anchors at each child-edge attachment point on the
/// south face.
/// #raw("tag") is a small piece of content drawn just outside the west
/// of the node — useful for compact per-node annotations that don't
/// compete with the label or the operation #raw("note") slot (e.g. the
/// RBT black-height bits enabled by #raw("display(bits: true)")).
/// #raw("label") replaces the node's rendered label (otherwise derived
/// from the structure node's #raw("label") field, or #raw("str(value)")
/// when that's #raw("auto")). For #raw("\"btree-node\""), the node has
/// multiple compartments — per-key labels come from the node's
/// #raw("labels") array (entry #raw("auto") falls back to
/// #raw("str(keys.at(i))")); per-compartment styling comes from
/// #raw("key-styles"), an array of dicts (one per compartment) with
/// #raw("fill")/#raw("stroke")/#raw("text-fill") overrides. Use
/// #raw("(:)") in a slot to leave a compartment unstyled.
/// #raw("key-styles") merges index-wise across sticky frames so
/// highlighting compartment 0 in one frame and compartment 1 in the
/// next keeps both annotations. #raw("materialize: true") draws an
/// otherwise-phantom slot as a real node — useful for one-off
/// pedagogical animations that need to expose a nil child (e.g.
/// rendering ∅ at a just-deleted leaf's position). Phantoms only exist
/// at paths the tree either naturally generates as layout-balance
/// siblings or where an edge style sets #raw("force-show: true");
/// materializing without one of those has no node to attach to.
#let NodeStyle = Refine(
  Dictionary(..Any),
  d => d.keys().all(k => _node-style-keys.contains(k)),
)

/// Typsy refinement: a dictionary of edge-style overrides. Recognised
/// keys are #raw("stroke"), #raw("note"), #raw("note-fill"),
/// #raw("tag"), #raw("mark"), #raw("hide"), #raw("parent-anchor"),
/// #raw("child-anchor"), #raw("force-show"), and #raw("bend"). The two
/// #raw("*-anchor") keys accept a cetz anchor name (e.g.
/// #raw("\"north\"")) and override the default fractional-distance
/// endpoint on the parent or child side respectively; useful for
/// connecting edges to non-circular shapes (e.g. #raw("child-anchor:
/// \"north\"") to land on a triangle's apex). #raw("force-show: true")
/// renders an edge even when one endpoint is a phantom — used by the
/// RBT delete animation to draw a stub edge into a now-nil position
/// when marking double-black. #raw("tag") is a small persistent
/// annotation drawn near the edge midpoint in the render theme's
/// #raw("edge-tag-fill") color — the edge counterpart to a node's
/// #raw("tag"), distinct from the gold operation-level #raw("note")
/// slot. Used by AVL #raw("display(heights: true)") to label each edge
/// with the height of the subtree it points to, and by graphs to label
/// each edge with its weight. #raw("bend") is a graph-only number
/// (cetz units): it curves the edge into an arc whose control point is
/// the straight midpoint pushed perpendicular by this amount (positive =
/// left of the u→v direction). Giving a mutual directed pair the same
/// bend fans the two arcs apart so they don't overlap into one line.
#let EdgeStyle = Refine(
  Dictionary(..Any),
  d => d.keys().all(k => _edge-style-keys.contains(k)),
)

// ===================================================================
// Render theme — structural defaults for the unstyled structure
// ===================================================================
//
// The render theme is the lowest layer in the style chain: it supplies
// the literal whites/blacks/etc. that the draw backend falls back on
// when a snapshot doesn't override a property. Above this layer sit (in
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
  edge-tag-fill: rgb("#2b6cb0"),
  note-bg: white,
)

#let _render-theme-keys = (
  "node-fill",
  "node-stroke",
  "node-text-fill",
  "edge-stroke",
  "note-fill",
  "edge-tag-fill",
  "note-bg",
)

/// Typsy refinement: a dictionary whose keys are a subset of the
/// render-theme keys (#raw("node-fill"), #raw("node-stroke"),
/// #raw("node-text-fill"), #raw("edge-stroke"), #raw("note-fill"),
/// #raw("edge-tag-fill"), #raw("note-bg")). #raw("note-bg") is the fill
/// drawn behind in-canvas node annotations (the #raw("note") and
/// #raw("tag") slots) so they stay legible over edges — defaults to
/// #raw("white"); set it to the page color on a non-white background.
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

// Index-wise merge of two `key-styles` arrays. Position i in the result
// is `_merge-into(old.at(i, default: (:)), new.at(i, default: (:)))`, so
// per-compartment overrides accumulate across sticky frames instead of
// the second call wiping out the first. Out-of-range positions on
// either side are treated as the empty dict.
#let _merge-key-styles(old, new) = {
  let m = calc.max(old.len(), new.len())
  range(m).map(i => {
    let o = if i < old.len() { old.at(i) } else { (:) }
    let nn = if i < new.len() { new.at(i) } else { (:) }
    _merge-into(o, nn)
  })
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
/// directly — they're managed by @@make-renderer() and the data
/// structures' #raw("*-display") methods.
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
      let override = style.named()
      // `key-styles` merges index-wise rather than wholesale replacing —
      // see `_merge-key-styles` above for the rationale.
      if "key-styles" in existing and "key-styles" in override {
        override.insert(
          "key-styles",
          _merge-key-styles(existing.key-styles, override.key-styles),
        )
      }
      let merged = _merge-into(existing, override)
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
/// Useful when you want to render a structure once with a draw backend
/// and no per-frame state.
///
/// -> Snapshot
#let blank-snapshot() = (Snapshot.new)(nodes: (:), edges: (:))

// ===================================================================
// Frame — public output record
// ===================================================================
//
// One Frame per animation step. The `render` method produces the cetz
// canvas (with no caption baked in). `caption` is an optional textual
// track for that step. `step` is free-form per-method metadata: each
// `*-display` method documents what it puts there so callers can drive
// custom layouts off it. `alt` is accessible text describing the frame.

/// Typsy class representing one frame in an animation. Fields and
/// methods:
///
/// - #raw("render(op-theme, render-theme)") — method that, given
///   resolved theme dicts, produces the cetz canvas for this frame.
///   Theming-aware deferral lives here: by carrying a builder rather
///   than pre-baked content, the lib.typ helpers (#raw("last"),
///   #raw("stacked"), #raw("figures")) can resolve theme state once
///   per call instead of once per frame, which is meaningfully faster
///   in many-structure documents. Per-data-structure themes (e.g. the
///   RBT palette) are read inside each frame's builder rather than
///   passed in — the helpers only carry the two universal layers.
/// - #raw("caption") — optional textual track for the step (possibly
///   #raw("none")).
/// - #raw("step") — optional free-form per-method metadata (possibly
///   #raw("none")).
/// - #raw("alt") — optional accessible text describing the frame
///   (possibly #raw("none")). Carried verbatim into the #raw("alt:")
///   argument on the Typst #raw("figure") wrapping the canvas. The
///   first frame of each operation includes the full structure
///   (via the #raw("describe") method) so screen-reader users have
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
// Renderer
// ===================================================================
//
// The renderer is structure-agnostic: it accumulates snapshots and
// produces frames, delegating the actual drawing to a *draw backend*
// stored in the `draw` field. The backend is a function
//   `(structure, snapshot, default-node-style, default-edge-style,
//     render-theme) -> cetz draw commands`
// wrapped in a singleton dict `(fn: ..)` (the same trick `Frame._builder`
// uses) so typsy doesn't self-inject on the function-typed field. The
// canvas wrap happens in `_make-canvas` / `render`, so backends stay
// canvas-free and reusable for callers wanting raw draw commands.

// Wrap a draw backend's commands in a cetz canvas for one snapshot.
#let _make-canvas(draw, structure, snapshot, dns, des, render-theme) = {
  cetz.canvas((draw.fn)(structure, snapshot, dns, des, render-theme))
}

// Four parallel arrays. `snapshots[i]` is the style snapshot for the
// i-th frame; `captions[i]`, `steps[i]`, and `alts[i]` are the optional
// caption, metadata, and accessible-text track for that frame. All four
// are kept in lockstep — `push-frame` appends to each,
// `patch` / `with-caption` / `with-step` / `with-alt` modify the tail.
// `render` zips them into `Frame` records.
/// Typsy class accumulating an animation. Holds the structure, a draw
/// backend, parallel arrays of snapshots / captions / steps / alts (one
/// entry per frame), and default node/edge styles. Methods include
/// #raw("push-frame()"), #raw("patch(fn)"),
/// #raw("push-with-node(path, ..style)"),
/// #raw("push-with-edge(path, ..style)"),
/// #raw("push-note-node(path, txt)"), #raw("push-note-edge(path, txt)"),
/// #raw("with-caption(c)"), #raw("with-step(s)"), #raw("with-alt(a)"),
/// and #raw("render()"). Build one via @@make-renderer().
#let Renderer = class(
  name: "Renderer",
  fields: (
    structure: Any,
    // Draw backend wrapped in a singleton dict `(fn: ..)`; see the
    // section comment above for why it isn't a bare function field.
    draw: Dictionary(..Any),
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
        structure: self.structure,
        draw: self.draw,
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
        structure: self.structure,
        draw: self.draw,
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
        structure: self.structure,
        draw: self.draw,
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
        structure: self.structure,
        draw: self.draw,
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
        structure: self.structure,
        draw: self.draw,
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
      let structure = self.structure
      let draw = self.draw
      let dns = self.default-node-style
      let des = self.default-edge-style
      self.snapshots
        .enumerate()
        .map(((i, snap)) => {
          let render-fn = (_bt, rt) => {
            let effective-rt = if theme == auto { rt } else { theme }
            _make-canvas(draw, structure, snap, dns, des, effective-rt)
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

/// Build a #raw("Renderer") seeded with one blank initial frame, bound
/// to a draw backend.
///
/// #raw("draw") is the structure-specific backend wrapped in a
/// singleton dict #raw("(fn: ..)") — see the #raw("Renderer") section
/// comment. Backend-binding wrappers live in each backend module
/// (#raw("make-renderer") in #raw("tree-anim.typ"),
/// #raw("make-graph-renderer") in #raw("graph-draw.typ")).
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
/// -> Renderer
#let make-renderer(
  /// The structure to render — interpreted only by the draw backend.
  /// -> any
  structure,
  /// Draw backend wrapped in a singleton dict #raw("(fn: ..)").
  /// -> dictionary
  draw,
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
  (Renderer.new)(
    structure: structure,
    draw: draw,
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

// Build an array of `Frame` records for one phase of a display:
//
//   structure        — the structure being rendered (one per phase)
//   draw             — the draw backend, singleton dict `(fn: ..)`
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
// `theme` and `render-theme` here are the per-call overrides (or `auto`
// to defer to the caller's resolved theme): a non-auto argument shadows
// whatever the helper passes in.
#let _make-frames(
  structure,
  draw,
  build-snapshots,
  captions,
  steps-meta,
  alts,
  theme,
  render-theme,
  // Base style layers applied beneath every per-frame snapshot at draw
  // time (the `dns`/`des` args of the draw backend). Graph displays use
  // `default-node-style` to set a doc-wide node shape/size; trees leave
  // them empty and style per-node via snapshots.
  default-node-style: (:),
  default-edge-style: (:),
) = {
  let n = captions.len()
  range(n).map(i => (Frame.new)(
    _builder: (
      fn: (op-arg, rt-arg) => {
        let op = if theme == auto { op-arg } else { theme }
        let rt = if render-theme == auto { rt-arg } else { render-theme }
        let snaps = build-snapshots(op, rt)
        _make-canvas(
          draw,
          structure,
          snaps.at(i),
          default-node-style,
          default-edge-style,
          rt,
        )
      },
    ),
    caption: captions.at(i),
    step: steps-meta.at(i),
    alt: alts.at(i),
  ))
}

/// Stitch frame arrays from multiple renderers (or pre-rendered arrays)
/// into one flat #raw("Array(Frame)"). Use this when an animation spans
/// a structure-shape change (rotation, deletion, insertion) and one
/// renderer can't hold all the frames — one renderer per shape, joined
/// at the boundary.
///
/// Accepts a mix of #raw("Renderer") instances and already-rendered
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
// Paths are opaque strings (typed `Str` rather than a path refinement
// so the same Op stream serves trees and graphs). Captions and step
// metadata are renderer-level (not snapshot-level), so they're set
// directly on the renderer between Op batches via `r.with-caption(...)`
// / `r.with-step(...)` rather than through an Op.

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
    fields: (path: Str, color: Any),
  ),
  Annotate: class(
    name: "Op.Annotate",
    fields: (path: Str, text: Content),
  ),
  StyleNode: class(
    name: "Op.StyleNode",
    fields: (path: Str, style: NodeStyle),
  ),
  StyleEdge: class(
    name: "Op.StyleEdge",
    fields: (path: Str, style: EdgeStyle),
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
/// -> Renderer
#let apply-ops(
  /// The renderer to apply ops to.
  /// -> Renderer
  renderer,
  /// Sequence of @@Op values to fold left-to-right.
  /// -> array
  ops,
) = ops.fold(renderer, _apply-op)
