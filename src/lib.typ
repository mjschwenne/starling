/// = Starling
///
/// Public surface: the default #raw("BST") class, render helpers for
/// turning #raw("Array(Frame)") into document content, and re-exports
/// of the lower-level animation kernel from #raw("tree-anim.typ").
///
/// Animation methods like #raw("(t.search-display)(v)") return arrays
/// of #raw("Frame") records (#raw("(canvas, caption, step)")); the
/// helpers below collapse those into a final image, a vertical stack,
/// or an array of figures suitable for touying's
/// #raw("alternatives(..)").

#import "./bst.typ": make-bst
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
)

/// The default BST class. Build a tree via #raw("(BST.new)(value:, left:, right:)")
/// and call its #raw("*-display") methods (see the BST API section of the
/// manual) to get animation frames; pass those frames through one of the
/// helpers below.
#let BST = make-bst()

// _with-caption is private — kept as a regular comment so tidy ignores it.
#let _with-caption(frame, spacing) = if frame.caption == none {
  frame.canvas
} else {
  stack(dir: ttb, spacing: spacing, frame.canvas, frame.caption)
}

/// Final frame as a single piece of content. Useful for static
/// renderings in print or for "just show me the end state" usage.
///
/// The inline node annotations (drawn next to nodes in the cetz canvas)
/// already label what the final step did, so the textual caption is
/// suppressed by default. Pass #raw("caption: true") to stack the
/// caption below the canvas.
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
) = {
  let f = frames.last()
  if caption { _with-caption(f, spacing) } else { f.canvas }
}

/// All frames stacked vertically as one block of content. Useful for
/// handouts that want to show the full animation in a single figure.
/// Captions are on by default since the stack is read as a sequence —
/// the caption text annotates which step each tree corresponds to.
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
) = {
  stack(
    dir: ttb,
    spacing: spacing,
    ..frames.map(f => if caption { _with-caption(f, caption-spacing) } else {
      f.canvas
    }),
  )
}

/// Build an array of #raw("figure") content, one per frame, suitable
/// for splatting into touying's #raw("alternatives(..)") so each frame
/// becomes its own subslide. Starling itself does not depend on
/// touying — the result is just an array of standard Typst figures.
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
  /// Alt-text strategy. #raw("auto") generates per-frame alt text
  /// (#raw("\"Animation frame N\"")); pass a string to override.
  /// -> auto | str
  alt: auto,
  /// Spacing between canvas and caption when #raw("caption: true").
  /// -> length
  caption-spacing: 0.5em,
) = {
  frames
    .enumerate()
    .map(((i, f)) => {
      let body = if caption { _with-caption(f, caption-spacing) } else {
        f.canvas
      }
      let a = if alt == auto { "Animation frame " + str(i) } else { alt }
      figure(body, alt: a)
    })
}

/// Drop captions and step metadata, returning just the array of
/// canvases. Useful when you want to lay out captions yourself —
/// e.g. alongside other slide content in a custom touying layout.
///
/// -> array
#let canvases-only(
  /// The frame array returned by any #raw("*-display") method.
  /// -> array
  frames,
) = frames.map(f => f.canvas)
