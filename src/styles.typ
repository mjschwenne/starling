// The semantic style vocabulary.
//
// Every helper here is variadic over element keys and returns an op array,
// so they compose with `+` and drop straight into `apply-ops`:
//
//   apply-ops(r, styles.search("", "L") + styles.attention("LR")
//                  + commit(alt: "Descending left."))
//
// Each one styles by *intent* rather than by color, via theme references —
// so a `set-theme` or a per-call `theme:` override reaches styles that were
// built long before the frame was drawn.
//
// Data-structure-specific vocabulary (an RBT node's red/black, an AVL node's
// imbalance) lives in that structure's own module, not here.

#import "core/ops.typ": style-edge, style-node
#import "core/style.typ": role, theme-ref

// ===================================================================
// Operation roles
// ===================================================================

/// Ring an element in the "look here" color — a rotation pivot, a deletion
/// target, the entry being polled.
#let attention(..keys) = style-node(..keys.pos(), stroke: role("attention-stroke"))

/// Ring an element as part of a search or insert walk.
#let search(..keys) = style-node(..keys.pos(), stroke: role("search-stroke"))

/// Mark an element as settled: the success fill plus the terminal ring.
#let success(..keys) = style-node(
  ..keys.pos(),
  fill: role("success-fill"),
  stroke: role("settled-stroke"),
)

/// Ring an element as broken, removed, or rejected.
#let danger(..keys) = style-node(..keys.pos(), stroke: role("danger-stroke"))

// ===================================================================
// Structural idioms
// ===================================================================

/// Elide a subtree: draw the node as a gray triangle with its incoming edge
/// landing on the apex, standing in for "any subtree of the right height".
/// The gray comes from the render theme's `elided-fill` / `elided-stroke`,
/// so it stays distinguishable from a real node under any palette.
#let subtree(..keys) = (
  style-node(
    ..keys.pos(),
    shape: "triangle",
    tag: none,
    fill: theme-ref("render", "elided-fill"),
    stroke: theme-ref("render", "elided-stroke"),
  )
    + style-edge(..keys.pos(), child-anchor: "north")
)

/// Draw a nil child as a real ∅ node. Tree phantoms exist only where the
/// layout generates a balance sibling or an edge sets `force-show: true`;
/// materializing anywhere else has nothing to attach to.
#let nullify(..keys) = style-node(
  ..keys.pos(),
  materialize: true,
  label: sym.emptyset,
  tag: none,
  fill: theme-ref("render", "node-fill"),
  stroke: theme-ref("render", "node-stroke"),
  text-fill: theme-ref("render", "node-text-fill"),
)

// ===================================================================
// Reveal control
// ===================================================================

/// Make elements invisible but keep their space: the layout is identical to
/// the fully-drawn structure, so a progressive reveal doesn't shift what is
/// already on screen. This is the one to reach for on a slide.
#let ghost(..keys) = (
  style-node(..keys.pos(), ghost: true) + style-edge(..keys.pos(), hide: true)
)

/// Drop elements from the drawing entirely. Unlike `ghost`, this releases
/// their layout space, so everything around them moves.
#let hidden(..keys) = (
  style-node(..keys.pos(), hide: true) + style-edge(..keys.pos(), hide: true)
)

/// Undo `ghost` or `hidden` on a sticky frame.
#let revealed(..keys) = (
  style-node(..keys.pos(), ghost: false, hide: false)
    + style-edge(..keys.pos(), hide: false)
)

/// Draw an edge even though one of its endpoints is a phantom — the stub
/// edge into a nil position (the RBT double-black marker needs one).
#let force-show(..keys) = style-edge(..keys.pos(), force-show: true)
