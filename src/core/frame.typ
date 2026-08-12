// Frame and Renderer — the animation plumbing.
//
//   Frame     one step of an animation: a builder that turns a resolved
//             theme into a cetz canvas, plus the caption / step metadata /
//             alt text that travel with it.
//   Renderer  a structure, a draw backend, and parallel arrays of snapshots
//             and metadata — the accumulating form used by the `Op` command
//             stream. `render(r)` zips it into an array of frames.
//
// A draw backend is just a function
//
//   (structure, snapshot, node-style, edge-style, theme) -> cetz commands
//
// so this module never knows what it is drawing. Trees pass `draw-tree`,
// graphs `draw-graph`, and a user with their own backend passes their own —
// `make-renderer` is the documented extension point.
//
// PERF: everything a display computes (traces, walks, the spec list) must be
// computed once at display-call time, OUTSIDE the builder closures. A builder
// does only: merge the per-call theme over the ambient one, build its own
// snapshot, draw. Moving trace computation inside a builder turns an O(n)
// animation into O(n) redundant recomputation per frame.

#import "@preview/cetz:0.5.2"
#import "snapshot.typ" as _snap
#import "style.typ" as _style
#import "theme.typ": merge-theme

// ===================================================================
// Canvas assembly
// ===================================================================

/// Draw one snapshot of a structure and wrap it in a `cetz.canvas`.
///
/// This is the single choke point where theme references are resolved: the
/// base node/edge style layers and every per-element style in the snapshot
/// are run through `style.resolve-refs` against the resolved `theme` just
/// before the backend sees them. That is what lets a style built long before
/// render time (an op stream, a `styles.attention(..)` helper) follow the
/// theme that is actually active.
///
/// `extra` is an array of additional cetz commands appended *inside* the same
/// canvas, so the backend's element anchors are in scope for them (this is
/// how `overlay` adds a callout). Each entry is either cetz content or a
/// function `(theme) => cetz content`.
#let make-canvas(
  structure,
  snapshot,
  node-style,
  edge-style,
  theme,
  draw,
  extra: (),
) = {
  let ns = _style.resolve-refs(node-style, theme)
  let es = _style.resolve-refs(edge-style, theme)
  let snap = (
    nodes: _style.resolve-refs-map(snapshot.nodes, theme),
    edges: _style.resolve-refs-map(snapshot.edges, theme),
  )
  cetz.canvas({
    draw(structure, snap, ns, es, theme)
    for e in extra {
      if type(e) == function { e(theme) } else { e }
    }
  })
}

// ===================================================================
// Frame
// ===================================================================

/// Build one frame.
///
/// - `make` is `(theme, extra) => content`, where `theme` is the *full*
///   resolved nested theme dict and `extra` the overlay commands to draw
///   inside the canvas.
/// - `builder` is the field callers use: `(theme) => content`, `make`
///   partially applied to the frame's current `extra`. `overlay` rebuilds it
///   when it appends commands, which is why the frame keeps `make` around.
/// - `caption` is content (or `none`) — never a bare string.
/// - `step` is free-form metadata; each display documents its `step.kind`
///   vocabulary, and every display's final frame carries `step.result`.
/// - `alt` is accessible text, always an explicitly-set string.
#let frame(make, caption: none, step: (:), alt: "", extra: ()) = (
  make: make,
  builder: theme => make(theme, extra),
  caption: caption,
  step: step,
  alt: alt,
  extra: extra,
)

/// The post-operation structure a display's final frame carries in
/// `step.result`. This is what replaces writing every operation twice —
/// once for the frames and once to advance the variable:
///
/// ```typ
/// #let frames = bst.insert-display(t, 5)
/// #let t = result(frames)
/// ```
///
/// For a search or traversal the result is the unchanged input structure.
#let result(frames) = {
  assert(
    frames.len() > 0,
    message: "result: no frames — a display always returns at least one.",
  )
  let step = frames.last().step
  assert(
    type(step) == dictionary and "result" in step,
    message: "result: the final frame carries no `step.result`. Every "
      + "starling display stamps one; a hand-built frame array must do the same.",
  )
  step.result
}

/// Append cetz commands to one frame's canvas, returning the new frame
/// array. Use it for callouts that need the backend's element anchors:
///
/// ```typ
/// #let frames = overlay(bst.search-display(t, 7), at: -1, draw: theme => {
///   import cetz.draw: line, content
///   line(anchor("LR"), (rel: (1, 1)))
/// })
/// ```
///
/// `at` indexes the frame array and accepts negative indices (`-1` is the
/// last frame). `draw` is either cetz content or a function `(theme) => cetz
/// content`, so an overlay can follow the active theme.
#let overlay(frames, at: -1, draw: ()) = {
  let i = if at < 0 { frames.len() + at } else { at }
  assert(
    i >= 0 and i < frames.len(),
    message: "overlay: frame index " + str(at) + " is out of range for "
      + str(frames.len())
      + " frames.",
  )
  let out = frames
  let f = out.at(i)
  let extra = f.extra + (draw,)
  out.at(i) = (..f, extra: extra, builder: theme => (f.make)(theme, extra))
  out
}

// ===================================================================
// make-frames — the one frame builder
// ===================================================================

/// Build an array of frames from an array of *specs*.
///
/// Each spec describes one frame:
///
/// ```typ
/// (
///   structure: <the structure to draw for this frame>,
///   build: (theme) => <snapshot>,   // this frame's styling
///   caption: none | content,
///   step: (:),                      // metadata; final frame carries `result`
///   alt: "",
///   node-style: auto,               // `auto` = the make-frames default
///   edge-style: auto,
///   extra: (),                      // cetz commands inside the canvas
/// )
/// ```
///
/// Carrying the structure per spec is what lets one animation span a shape
/// change (a rotation, a split, a chain growing) without stitching several
/// renderers together. Carrying `build` per spec is what keeps the work
/// linear: each frame builds only its own snapshot.
///
/// `theme` is the display's per-call override, merged over the ambient theme
/// the builder is handed at render time.
#let make-frames(
  specs,
  draw,
  theme: (:),
  node-style: (:),
  edge-style: (:),
) = {
  specs.map(spec => {
    let structure = spec.structure
    let build = spec.build
    let ns = spec.at("node-style", default: auto)
    let es = spec.at("edge-style", default: auto)
    let dns = if ns == auto { node-style } else { ns }
    let des = if es == auto { edge-style } else { es }
    frame(
      (ambient, extra) => {
        let th = merge-theme(ambient, theme)
        make-canvas(structure, build(th), dns, des, th, draw, extra: extra)
      },
      caption: spec.at("caption", default: none),
      step: spec.at("step", default: (:)),
      alt: spec.at("alt", default: ""),
      extra: spec.at("extra", default: ()),
    )
  })
}

// ===================================================================
// Renderer
// ===================================================================

/// Build a renderer seeded with one blank frame, bound to a draw backend.
///
/// This is the low-level, accumulate-as-you-go path behind the `Op` command
/// stream — and the extension point for a custom draw backend. The data
/// structures' `renderer(..)` functions wrap it with their own backend and
/// structural painting.
///
/// With `sticky: true` each new frame starts from the previous frame's
/// styling, so highlights accumulate; with `sticky: false` (the default)
/// every frame starts blank.
///
/// `theme` is a partial nested override merged over the ambient theme at
/// render time.
#let make-renderer(
  structure,
  draw,
  node-style: (:),
  edge-style: (:),
  sticky: false,
  theme: (:),
) = (
  structure: structure,
  draw: draw,
  snapshots: (_snap.blank-snapshot(),),
  captions: (none,),
  steps: ((:),),
  alts: ("",),
  node-style: node-style,
  edge-style: edge-style,
  sticky: sticky,
  theme: theme,
)

/// Open a new frame. Its styling starts from the previous frame's when the
/// renderer is sticky, blank otherwise.
#let push-frame(r) = {
  let base = if r.sticky and r.snapshots.len() > 0 {
    r.snapshots.last()
  } else {
    _snap.blank-snapshot()
  }
  (
    ..r,
    snapshots: r.snapshots + (base,),
    captions: r.captions + (none,),
    steps: r.steps + ((:),),
    alts: r.alts + ("",),
  )
}

/// Replace the in-progress frame's snapshot with `fn(snapshot)`.
#let patch(r, fn) = {
  assert(
    r.snapshots.len() > 0,
    message: "patch: no frames yet — call push-frame first.",
  )
  let next = r.snapshots
  next.at(next.len() - 1) = fn(next.last())
  (..r, snapshots: next)
}

// Set one metadata track's tail entry.
#let _set-tail(r, field, value) = {
  let next = r.at(field)
  assert(
    next.len() > 0,
    message: "with-" + field + ": no frames yet — call push-frame first.",
  )
  next.at(next.len() - 1) = value
  let out = r
  out.insert(field, next)
  out
}

/// Set the in-progress frame's caption.
#let with-caption(r, c) = _set-tail(r, "captions", c)

/// Set the in-progress frame's step metadata.
#let with-step(r, s) = _set-tail(r, "steps", s)

/// Set the in-progress frame's alt text.
#let with-alt(r, a) = _set-tail(r, "alts", a)

/// Zip a renderer into an array of frames — one per accumulated snapshot.
#let render(r) = {
  let structure = r.structure
  let draw = r.draw
  let dns = r.node-style
  let des = r.edge-style
  let theme = r.theme
  r
    .snapshots
    .enumerate()
    .map(((i, snap)) => frame(
      (ambient, extra) => {
        let th = merge-theme(ambient, theme)
        make-canvas(structure, snap, dns, des, th, draw, extra: extra)
      },
      caption: r.captions.at(i),
      step: r.steps.at(i),
      alt: r.alts.at(i),
    ))
}
