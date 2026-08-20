/// = Starling
///
/// Animated data structures for teaching, on cetz.
///
/// Every data structure is a namespace — `bst`, `hashmap`, … — holding plain
/// functions that take the structure as their first argument:
///
/// ```typ
/// #import "@preview/starling:1.0.0" as starling
/// #import starling: bst, last
///
/// #let t = bst.new(8, 3, 10, 1, 6)
/// #last(bst.insert-display(t, 7))
/// ```
///
/// Alongside them sits a small flat layer: the presentation helpers that turn
/// frames into content, the op constructors for driving an animation yourself,
/// and the one theme.

// ===================================================================
// Data structures
// ===================================================================

#import "ds/bst.typ" as bst
#import "ds/hashmap.typ" as hashmap
#import "ds/rbt.typ" as rbt
#import "ds/avl.typ" as avl
#import "ds/b24.typ" as b24
#import "ds/trie.typ" as trie
#import "ds/graph.typ" as graph

// The semantic style vocabulary — `styles.attention(..)`, `styles.ghost(..)`
// and friends, each returning an op array that follows the active theme.
#import "styles.typ" as styles

// ===================================================================
// The core, flat
// ===================================================================

/// Snapshots — the sparse per-element style overlay for one frame.
#import "core/snapshot.typ": apply-snapshot, blank-snapshot

/// The op command stream. Each constructor returns an *array*, so streams
/// compose with `+`; `apply-ops` folds one into a renderer.
#import "core/ops.typ": (
  annotate, apply-ops, commit, set-alt, set-caption, set-step, style-edge,
  style-node,
)

/// Frames and renderers. `make-renderer(structure, draw, ..)` is the
/// documented extension point for a draw backend of your own.
#import "core/frame.typ": make-renderer, overlay, render, result

/// Theme references — a placeholder for `theme.<section>.<key>`, resolved when
/// the frame is drawn, so a style built ahead of time follows the live theme.
#import "core/style.typ": role, theme-ref

/// The one theme: one nested dict, one setter.
#import "core/theme.typ": default-theme, set-theme

/// The one anchor sanitizer: `anchor(key)` is the cetz element name every
/// backend draws under, so a callout can point at anything by its key.
#import "core/draw-util.typ": anchor

// ===================================================================
// Presentation
// ===================================================================

#import "slides.typ": canvas, figures, last, stacked

/// One frame's auxiliary bookkeeping — a BFS queue, Kruskal's disjoint sets,
/// Dijkstra's priority queue — as placeable content beside the canvas. The
/// whole `aux` module (with `aux-view-title`) is namespaced too.
#import "aux.typ" as aux
#import "aux.typ": aux-strip

// ===================================================================
// Draw backends
// ===================================================================
//
// Call these inside your own `cetz.canvas` when you want to compose a
// structure with annotations of your own; they need no `context`.

#import "draw/tree.typ": draw-tree
#import "draw/graph.typ": draw-graph
#import "draw/hashmap.typ": draw-hashmap

// ===================================================================
// TRANSITIONAL — the pre-1.0 surface for the not-yet-migrated structures
// ===================================================================
//
// Sort, Skiplist and the git DSL still ride the old typsy stack.
// Their exports below are unchanged and keep working; each block disappears
// as its structure moves into `ds/` (Phases 5-6). Nothing here is part of
// the 1.0 surface.

#import "./sort.typ": (
  Sort,
  sort,
  default-sort-theme,
  set-sort-theme,
  SortTheme,
  _sort-theme-state,
)
#import "./array-draw.typ": (
  draw-array,
  array-cell-anchor,
  array-entry-anchor,
  array-cell-key,
  array-entry-key,
  make-array-renderer,
)
#import "./skiplist.typ": (
  Skiplist,
  skiplist,
  default-skiplist-theme,
  set-skiplist-theme,
  SkiplistTheme,
  _skiplist-theme-state,
)
#import "./skiplist-draw.typ": (
  draw-skiplist,
  sl-box-anchor,
  sl-forward-anchor,
  sl-data-anchor,
  sl-box-key,
  sl-forward-key,
  sl-data-key,
  make-skiplist-renderer,
)
// The git DSL's verbs use generic names (`commit`, `branch`, `merge`, `tag`,
// `checkout`), so they stay behind a namespace rather than going flat.
#import "./git-graph.typ" as git
#import "./git-graph.typ": (
  default-git-theme,
  set-git-theme,
  GitTheme,
  _git-theme-state,
)
// The two pre-1.0 theme states the old structures read.
#import "./op-theme.typ": default-op-theme, set-op-theme, OpTheme, _op-theme-state
#import "./anim-core.typ": (
  default-render-theme,
  set-render-theme,
  RenderTheme,
  _render-theme-state,
)

/// TRANSITIONAL. Drop captions and step metadata, returning just the canvases,
/// for a hand-built layout. Superseded by @@canvas() (and, from Phase 6, by
/// `subslides`), which is what the migrated structures use.
///
/// -> array
#let canvases-only(
  /// The frame array from a `*-display`.
  /// -> array
  frames,
) = frames.map(f => canvas(f))

// ===================================================================
// Layout
// ===================================================================

// `auto-layout` carries its `diagraph-layout` import inside its own body (see
// graph-layout.typ), so re-exporting it here does NOT make `import starling`
// pull that dependency — it resolves only when the function is called. This is
// the only way external users can reach it, since Typst has no subpath package
// import.
#import "./graph-layout.typ": auto-layout
