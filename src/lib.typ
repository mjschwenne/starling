/// = Starling
///
/// Public surface: the default #raw("BST") class, render helpers for
/// turning #raw("Array(Frame)") into document content, and re-exports
/// of the lower-level animation kernel from #raw("tree-anim.typ").
///
/// Animation methods like #raw("(t.search-display)(v)") return arrays
/// of #raw("Frame") records (#raw("(canvas, caption, step, alt)"));
/// the helpers below collapse those into a final image, a vertical
/// stack, or an array of figures suitable for touying's
/// #raw("alternatives(..)"). All three helpers wrap canvases in
/// #raw("figure") with the frame's #raw("alt") text attached so
/// screen-reader users get a per-step narration; the wrappers
/// suppress numbering and supplements so they don't change the
/// visible layout.

#import "./bst.typ": (
  BST,
  default-bst-theme,
  set-bst-theme,
  BstTheme,
  _bst-theme-state,
)
#import "./rbt.typ": (
  RBT,
  default-rbt-theme,
  set-rbt-theme,
  RbtTheme,
  _rbt-theme-state,
)
#import "./tree-anim.typ"
#import "./tree-anim.typ": (
  PathId,
  NodeStyle,
  EdgeStyle,
  Snapshot,
  Frame,
  TreeRenderer,
  make-renderer,
  concat-frames,
  blank-snapshot,
  Op,
  apply-ops,
  draw-tree,
  path-anchor,
  default-render-theme,
  set-render-theme,
  RenderTheme,
  _render-theme-state,
)

// Private helpers — kept as regular comments so tidy ignores them.
//
// Each #raw("frame.render") is a builder #raw("(bt, rt) => content")
// rather than pre-baked content; the helpers below resolve the active
// theme state *once* per call and feed those resolved themes into every
// frame's builder. That collapses N per-frame `state.get()` calls down
// to two per helper invocation — a meaningful perf win in many-tree
// documents (`set-bst-theme` / `set-render-theme` participate in
// Typst's state-convergence machinery, so each per-frame state read
// costs a few ms in extra layout work).
//
// `_with-caption(frame, spacing, bt, rt)` stacks the caption below the
// rendered canvas when present, otherwise returns the bare canvas.
//
// `_resolve-alt(frame, override, index)` picks the alt-text string for
// one frame: an explicit override wins; otherwise the frame's own
// `alt` field is used; otherwise the caption (when it's a plain
// string) is used as a last-resort fallback; otherwise a generic
// "Animation frame N" placeholder.
//
// `_alt-figure(body, alt)` wraps content in a `figure` carrying the
// alt text without any visible numbering or supplement, so the helpers
// can attach alt to a canvas without changing the visible layout.
#let _with-caption(frame, spacing, bt, rt) = {
  let canvas = (frame.render)(bt, rt)
  if frame.caption == none {
    canvas
  } else {
    stack(dir: ttb, spacing: spacing, canvas, frame.caption)
  }
}
#let _resolve-alt(frame, override, index) = {
  if override != auto { override } else if frame.alt != none { frame.alt } else if (
    frame.caption != none and type(frame.caption) == str
  ) { frame.caption } else { "Animation frame " + str(index) }
}
#let _alt-figure(body, alt) = figure(
  body,
  kind: image,
  numbering: none,
  supplement: none,
  alt: alt,
)

/// Final frame as a single piece of content. Useful for static
/// renderings in print or for "just show me the end state" usage.
///
/// The inline node annotations (drawn next to nodes in the cetz canvas)
/// already label what the final step did, so the textual caption is
/// suppressed by default. Pass #raw("caption: true") to stack the
/// caption below the canvas.
///
/// The returned content is wrapped in an alt-tagged figure for
/// accessibility. The alt text comes from the frame's #raw("alt")
/// field; pass an explicit string to #raw("alt") to override.
///
/// -> content
#let last(
  /// The frame array returned by any #raw("*-display") method.
  /// -> array
  frames,
  /// Whether to render the step's caption below the canvas.
  /// -> bool
  caption: false,
  /// Vertical spacing between canvas and caption when #raw("caption: true").
  /// -> length
  spacing: 0.5em,
  /// Alt-text override. #raw("auto") uses the frame's #raw("alt") field.
  /// -> auto | str
  alt: auto,
) = context {
  let bt = _bst-theme-state.get()
  let rt = _render-theme-state.get()
  let f = frames.last()
  let body = if caption {
    _with-caption(f, spacing, bt, rt)
  } else { (f.render)(bt, rt) }
  _alt-figure(body, _resolve-alt(f, alt, frames.len() - 1))
}

/// All frames stacked vertically as one block of content. Useful for
/// handouts that want to show the full animation in a single figure.
/// Captions are on by default since the stack is read as a sequence —
/// the caption text annotates which step each tree corresponds to.
///
/// Each frame is wrapped individually in an alt-tagged figure so
/// screen-reader users hear the per-step narration. Pass a string to
/// #raw("alt") to set the same override on every frame.
///
/// -> content
#let stacked(
  /// The frame array returned by any #raw("*-display") method.
  /// -> array
  frames,
  /// Whether to include each frame's caption below its canvas.
  /// -> bool
  caption: true,
  /// Vertical spacing between frames.
  /// -> length
  spacing: 1em,
  /// Spacing between each canvas and its caption.
  /// -> length
  caption-spacing: 0.5em,
  /// Alt-text override applied to every frame. #raw("auto") uses each
  /// frame's #raw("alt") field.
  /// -> auto | str
  alt: auto,
) = context {
  let bt = _bst-theme-state.get()
  let rt = _render-theme-state.get()
  stack(
    dir: ttb,
    spacing: spacing,
    ..frames
      .enumerate()
      .map(((i, f)) => {
        let body = if caption {
          _with-caption(f, caption-spacing, bt, rt)
        } else { (f.render)(bt, rt) }
        _alt-figure(body, _resolve-alt(f, alt, i))
      }),
  )
}

/// Build an array of #raw("figure") content, one per frame, suitable
/// for splatting into touying's #raw("alternatives(..)") so each frame
/// becomes its own subslide. Starling itself does not depend on
/// touying — the result is just an array of standard Typst figures.
///
/// Unlike @@last() / @@stacked(), this helper can't collapse theme
/// state reads to one — each figure is an independent piece of
/// content laid out separately (touying splits them into subslides),
/// so each figure's body resolves theme state in its own
/// #raw("context") block. In many-tree documents that rely on
/// #raw("set-bst-theme") / #raw("set-render-theme"), prefer per-call
/// #raw("theme:") arguments on the #raw("*-display") method to skip
/// state altogether when you're using #raw("figures").
///
/// -> array
#let figures(
  /// The frame array returned by any #raw("*-display") method.
  /// -> array
  frames,
  /// Whether to stack each frame's caption below its canvas inside
  /// the figure body.
  /// -> bool
  caption: true,
  /// Alt-text override applied to every frame. #raw("auto") uses each
  /// frame's #raw("alt") field, falling back to the caption (if it's
  /// a plain string) and then to a generic
  /// #raw("\"Animation frame N\"") placeholder.
  /// -> auto | str
  alt: auto,
  /// Spacing between canvas and caption when #raw("caption: true").
  /// -> length
  caption-spacing: 0.5em,
) = {
  frames
    .enumerate()
    .map(((i, f)) => figure(
      context {
        let bt = _bst-theme-state.get()
        let rt = _render-theme-state.get()
        if caption {
          _with-caption(f, caption-spacing, bt, rt)
        } else { (f.render)(bt, rt) }
      },
      alt: _resolve-alt(f, alt, i),
    ))
}

/// Drop captions and step metadata, returning just the array of
/// canvases. Useful when you want to lay out captions yourself —
/// e.g. alongside other slide content in a custom touying layout.
///
/// Like @@figures(), this returns one piece of content per frame and
/// therefore can't amortize theme state reads — each canvas resolves
/// state independently. If you're calling this on hot paths under a
/// state-set theme, prefer per-call #raw("theme:") arguments on
/// the #raw("*-display") method.
///
/// -> array
#let canvases-only(
  /// The frame array returned by any #raw("*-display") method.
  /// -> array
  frames,
) = frames.map(f => context {
  let bt = _bst-theme-state.get()
  let rt = _render-theme-state.get()
  (f.render)(bt, rt)
})
