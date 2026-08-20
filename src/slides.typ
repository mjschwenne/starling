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
// `last`, `stacked`, `figures`, and `subslides` wrap each canvas in a `figure`
// carrying the frame's `alt` text, so screen-reader users get a per-step
// narration; the wrapper suppresses numbering and supplements, so it changes
// nothing visible. `canvas` deliberately does not — see its docs.

#import "aux.typ": aux-strip
#import "core/theme.typ": resolve-theme

// Whether `frames` is a single frame rather than an array of them.
#let _is-frame(x) = type(x) == dictionary and "builder" in x

// Render one frame against an already-resolved theme.
#let _render-frame(frame, theme) = (frame.builder)(theme)

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
#let _as-array(frames) = if _is-frame(frames) or type(frames) != array {
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

// ===================================================================
// subslides — the composed, one-per-subslide form
// ===================================================================

// Spacing inside a composition. Fixed rather than exposed: the point of
// `subslides` is that a deck should not have to hand-tune the sandwich of
// canvas, strip, and caption it replaces.
#let _AUX-GUTTER = 1.2em
#let _AUX-SPACING = 0.8em
#let _CAPTION-SPACING = 0.6em

// A one-column grid sizes to its widest row and centers the rest inside it —
// what a `stack` cannot do, and what keeps a narrow strip or caption under
// the middle of a wide canvas.
#let _centered-column(spacing, ..rows) = grid(
  columns: 1,
  row-gutter: spacing,
  align: center + horizon,
  ..rows,
)

// One frame as canvas + optional aux strip + optional caption, arranged per
// `aux`. The strip gets the already-resolved theme (a complete theme is a
// valid override of itself), so the whole composition draws from one read.
#let _composed(frame, theme, aux, aux-view, aux-size, caption) = {
  let body = _render-frame(frame, theme)
  let composed = if aux == none {
    body
  } else {
    assert(
      type(frame.step) == dictionary and "aux-views" in frame.step,
      message: "subslides: aux: \"" + aux + "\" needs frames that carry "
        + "auxiliary state, and this one does not — the graph algorithm "
        + "displays are the ones that stamp `step.aux-views`.",
    )
    let strip = text(
      size: aux-size,
      aux-strip(frame.step, view: aux-view, theme: theme),
    )
    // Both columns are `auto`, not `1fr`: a fractional track collapses in
    // the unbounded region `measure` lays content out in, which would make
    // `fit:` scale off a bogus size. Sizing the pair to its content and
    // letting the caller place the block keeps the two features compatible.
    let side(..cells) = grid(
      columns: (auto, auto),
      column-gutter: _AUX-GUTTER,
      align: center + horizon,
      ..cells,
    )
    if aux == "below" {
      _centered-column(_AUX-SPACING, body, strip)
    } else if aux == "right" {
      side(body, strip)
    } else {
      side(strip, body)
    }
  }
  if caption and frame.caption != none {
    _centered-column(_CAPTION-SPACING, composed, frame.caption)
  } else { composed }
}

// Every frame's composition, in order. A separate function so that each
// subslide calls it with identical arguments and Typst's call cache builds
// the array once for the whole animation.
#let _compose-all(frames, theme, aux, aux-view, aux-size, caption) = frames.map(f => _composed(
  f,
  theme,
  aux,
  aux-view,
  aux-size,
  caption,
))

// The largest scale factor that fits every composition in `bodies` inside a
// `width` by `height` box. One factor for the whole animation, so subslides
// don't wobble as the drawing grows. Needs `context` (it measures).
#let _fit-scale(bodies, width, height) = {
  let w = 0pt
  let h = 0pt
  for b in bodies {
    let size = measure(b)
    w = calc.max(w, size.width)
    h = calc.max(h, size.height)
  }
  if w <= 0pt or h <= 0pt { 100% } else { calc.min(width / w, height / h) * 100% }
}

// Scale a composition, or leave it alone when `fit` is `none`.
#let _scaled(body, factor) = if factor == none {
  body
} else {
  scale(x: factor, y: factor, reflow: true, body)
}

/// One piece of composed content per frame — canvas, the algorithm's
/// auxiliary state, and the step's caption, laid out together and ready to
/// splat into touying's `alternatives(..)`:
///
/// ```typ
/// #alternatives(..subslides(graph.bfs-display(g, "A"), aux: "right"))
/// ```
///
/// This is the whole point of the frame model on a slide: the same drawing
/// re-rendered per step, with the queue or the priority queue beside it and
/// the narration beneath. Composing it by hand (a `grid` of `canvas` +
/// `aux-strip` + `f.caption`, each wrapped in its own `alternatives`) both
/// loses the alt text and lets the pieces drift apart from subslide to
/// subslide; this keeps one composition per step and wraps all of it in the
/// frame's alt figure.
///
/// Starling still has no touying dependency — the return value is a plain
/// array of content.
///
/// -> array
#let subslides(
  /// The frame array from a `*-display`, or a single frame.
  /// -> array | dictionary
  frames,
  /// Whether to place each frame's caption below the composition.
  /// -> bool
  caption: true,
  /// Where to put the auxiliary strip, if anywhere: `none`, `"right"`,
  /// `"left"`, or `"below"`. Only the graph algorithm displays carry the
  /// state a strip needs.
  /// -> none | str
  aux: none,
  /// Which auxiliary view to show when a frame carries several (Kruskal
  /// carries two, Dijkstra three). `auto` stacks them all, exactly as
  /// `aux-strip` does on its own.
  /// -> auto | str
  aux-view: auto,
  /// Text size for the auxiliary strip. Strips carry a lot of small cells,
  /// so they read better a little below body size.
  /// -> length
  aux-size: 0.8em,
  /// Scale the compositions down (or up) to fit: a ratio scales by exactly
  /// that much, and a `(width, height)` pair measures every frame and picks
  /// the one factor that fits the largest of them in that box — so the
  /// drawing keeps a constant size across the subslides instead of resizing
  /// under each step.
  /// -> none | ratio | array
  fit: none,
  /// Alt-text override applied to every frame. `auto` uses each frame's own.
  /// -> auto | str
  alt: auto,
) = {
  assert(
    aux == none or ("left", "right", "below").contains(aux),
    message: "subslides: aux must be none, \"left\", \"right\", or "
      + "\"below\"; got "
      + repr(aux)
      + ".",
  )
  assert(
    fit == none
      or type(fit) == ratio
      or (type(fit) == array and fit.len() == 2 and fit.all(v => type(v) == length)),
    message: "subslides: fit must be none, a ratio, or a (width, height) "
      + "pair of lengths; got "
      + repr(fit)
      + ".",
  )
  let fs = _as-array(frames)
  fs
    .enumerate()
    .map(((i, f)) => _alt-figure(
      // Each subslide is laid out on its own, so — like `figures` — each
      // opens its own `context`. The composition work behind `fit` is shared
      // between them by the call cache, not by a shared context.
      context {
        let theme = resolve-theme((:))
        if type(fit) == array {
          // Compose every frame — this one included — so the whole animation
          // shares one measurement and one factor.
          let bodies = _compose-all(fs, theme, aux, aux-view, aux-size, caption)
          _scaled(bodies.at(i), _fit-scale(bodies, fit.first(), fit.last()))
        } else {
          _scaled(_composed(f, theme, aux, aux-view, aux-size, caption), fit)
        }
      },
      _alt-of(f, alt, i),
    ))
}
