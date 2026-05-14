#import "./bst.typ": make-bst
#import "./tree-anim.typ"
#import "./tree-anim.typ": (
  PathId,
  NodeStyle,
  EdgeStyle,
  Frame,
  TreeRenderer,
  make-renderer,
  concat-frames,
  blank-frame,
  Op,
  apply-ops,
)

// Default wrap for non-touying contexts: collapse the animation to its
// final frame, giving a static image of the end state. Touying users
// override this via `configure(wrap: alternatives)`.
#let _default-wrap(..figs) = figs.pos().last()

// `configure(wrap: ...)` returns a dict of data-structure factories with
// `wrap` baked in by closure capture. Use it once at the top of a touying
// document:
//
//   #import "@preview/starling:0.1.0" as starling
//   #let (BST,) = (starling.configure)(wrap: alternatives)
//
// `wrap` is invoked as `wrap(..figs)` where `figs` is a sequence of
// `figure` content, one per animation frame. The touying `alternatives`
// function fits this signature directly and renders each figure as a
// separate subslide.
//
// State-based configuration (`std.state`, typsy's `safe-state`) cannot be
// used here: touying's `alternatives` is a layout-time "mark" that touying
// rejects inside `context { ... }` blocks, and `state.get()` requires a
// surrounding context. Closure capture sidesteps the issue entirely.
#let configure(wrap: _default-wrap) = (
  BST: make-bst(wrap),
)

// Default-configured BST for non-touying use. Override by calling
// `configure(wrap: ...)` and destructuring its result.
#let BST = make-bst(_default-wrap)
