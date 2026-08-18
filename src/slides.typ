// Presentation helpers — turning an array of frames into document content.
//
// Every `*-display` returns an `Array(Frame)`; these collapse it into a final
// image, a vertical stack, or an array of figures ready for touying's
// `alternatives(..)`. Starling itself never depends on touying: these return
// plain Typst content.
//
// Each frame carries a *builder* `(theme) => content` rather than pre-baked
// content, so the helpers resolve the active theme once per call — inside a
// single `context` — and feed that one resolved theme into every frame. A
// document that never calls `set-theme` pays nothing; one that does pays the
// state-convergence cost once, not once per frame.
//
// `last`, `stacked`, and `figures` wrap each canvas in a `figure` carrying the
// frame's `alt` text, so screen-reader users get a per-step narration; the
// wrapper suppresses numbering and supplements, so it changes nothing visible.
// `canvas` deliberately does not — see its docs.

#import "core/theme.typ": resolve-theme

// TRANSITIONAL (Phase 3 → 6). Frames come in two shapes while the data
// structures migrate: the new plain dicts carrying a `builder`, and the old
// typsy `Frame` class carrying a `render` method plus the two old theme
// states. These imports and `_render-frame`'s second arm exist only to serve
// the not-yet-migrated structures and are deleted with the last of them.
#import "anim-core.typ": _render-theme-state
#import "op-theme.typ": _op-theme-state

#let _is-new(frame) = type(frame) == dictionary and "builder" in frame

// Render one frame against an already-resolved theme. Old-style frames read
// the two legacy states themselves — lazily, so a document with no old frames
// never touches them (and never pays their convergence cost).
#let _render-frame(frame, theme) = if _is-new(frame) {
  (frame.builder)(theme)
} else {
  (frame.render)(_op-theme-state.get(), _render-theme-state.get())
}

// A frame's canvas with its caption stacked below, when it has one.
#let _with-caption(frame, spacing, theme) = {
  let body = _render-frame(frame, theme)
  if frame.caption == none {
    body
  } else {
    stack(dir: ttb, spacing: spacing, body, frame.caption)
  }
}

// The alt text for one frame: an explicit override wins, then the frame's own
// `alt`, then a generic placeholder. Unlike the pre-1.0 helper there is no
// caption fallback — every display sets `alt` explicitly, and the fallback
// behaved differently per data structure.
#let _alt-of(frame, override, index) = {
  if override != auto {
    override
  } else if frame.alt != none and frame.alt != "" {
    frame.alt
  } else { "Animation frame " + str(index) }
}

// Wrap content in a figure carrying alt text, with nothing visible added.
#let _alt-figure(body, alt) = figure(
  body,
  kind: image,
  numbering: none,
  supplement: none,
  alt: alt,
)

// Accept a lone frame anywhere an array is expected.
#let _as-array(frames) = if _is-new(frames) or type(frames) != array {
  (frames,)
} else { frames }

/// The final frame as one piece of content — a static rendering for print, or
/// "just show me the end state".
///
/// Accepts either the frame array a `*-display` returns or a single frame, so
/// picking one step out of an animation needs no re-wrapping:
///
/// ```typ
/// #last(bst.search-display(t, 7).at(3))
/// ```
///
/// The in-canvas annotations already say what the final step did, so the
/// textual caption is suppressed by default.
///
/// -> content
#let last(
  /// The frame array from a `*-display`, or a single frame.
  /// -> array | dictionary
  frames,
  /// Whether to stack the step's caption below the canvas.
  /// -> bool
  caption: false,
  /// Vertical spacing between canvas and caption when `caption: true`.
  /// -> length
  spacing: 0.5em,
  /// Alt-text override. `auto` uses the frame's own `alt`.
  /// -> auto | str
  alt: auto,
) = context {
  let fs = _as-array(frames)
  let theme = resolve-theme((:))
  let f = fs.last()
  let body = if caption {
    _with-caption(f, spacing, theme)
  } else { _render-frame(f, theme) }
  _alt-figure(body, _alt-of(f, alt, fs.len() - 1))
}

/// Every frame stacked vertically as one block — the handout form, showing a
/// whole animation in one figure. Captions are on by default, since a stack
/// reads as a sequence and the caption says which step each image is.
///
/// Each frame is wrapped in its own alt-tagged figure, so the narration stays
/// per-step.
///
/// -> content
#let stacked(
  /// The frame array from a `*-display`, or a single frame.
  /// -> array | dictionary
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
  /// Alt-text override applied to every frame. `auto` uses each frame's own.
  /// -> auto | str
  alt: auto,
) = context {
  let fs = _as-array(frames)
  let theme = resolve-theme((:))
  stack(
    dir: ttb,
    spacing: spacing,
    ..fs
      .enumerate()
      .map(((i, f)) => {
        let body = if caption {
          _with-caption(f, caption-spacing, theme)
        } else { _render-frame(f, theme) }
        _alt-figure(body, _alt-of(f, alt, i))
      }),
  )
}

/// An array of `figure` content, one per frame — splat it into touying's
/// `alternatives(..)` to give each frame its own subslide.
///
/// Unlike @@last() and @@stacked() this cannot collapse the theme read to
/// one: each figure is laid out independently (touying splits them across
/// subslides), so each resolves the theme in its own `context`. In a deck that
/// relies on `set-theme`, prefer a per-call `theme:` argument on the display
/// to skip state entirely.
///
/// -> array
#let figures(
  /// The frame array from a `*-display`, or a single frame.
  /// -> array | dictionary
  frames,
  /// Whether to stack each frame's caption below its canvas in the figure.
  /// -> bool
  caption: true,
  /// Spacing between canvas and caption when `caption: true`.
  /// -> length
  caption-spacing: 0.5em,
  /// Alt-text override applied to every frame. `auto` uses each frame's own.
  /// -> auto | str
  alt: auto,
) = {
  _as-array(frames)
    .enumerate()
    .map(((i, f)) => figure(
      context {
        let theme = resolve-theme((:))
        if caption {
          _with-caption(f, caption-spacing, theme)
        } else { _render-frame(f, theme) }
      },
      alt: _alt-of(f, alt, i),
    ))
}

/// One frame's bare canvas, with no caption and *no alt text* — for hand-built
/// layouts where you place the canvas yourself and own the accessibility.
/// Reach for @@last() or @@figures() unless you are doing exactly that.
///
/// -> content
#let canvas(
  /// A single frame.
  /// -> dictionary
  frame,
  /// Partial theme override for this render, merged over the ambient theme.
  /// -> dictionary
  theme: (:),
) = context _render-frame(frame, resolve-theme(theme))
