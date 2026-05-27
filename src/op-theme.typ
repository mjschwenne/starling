#import "@preview/typsy:0.2.2": Any, Refine, Dictionary

// ===================================================================
// Op theme — operation-semantic styling, shared across data structures
// ===================================================================
//
// Each key names a "role" that one or more `*-display` methods read at
// render time. These describe *operations* (searching, modifying,
// succeeding/failing, traversing) and apply across any data structure
// that exposes those operations — they're not BST-specific or
// RBT-specific.
//
//   search-stroke    — search/insert walk; descend in delete
//   attention-stroke — generic "look here": rotation pivots, deletion
//                      target, RBT red-red violation
//   success-stroke   — newly-connected edges
//   settled-stroke   — final new-node ring (insert, two-child delete)
//   success-fill     — final new-node fill (insert, two-child delete)
//   danger-stroke    — broken/removed edges (dashed by default)
//   reset-stroke     — used by rotate-display to clear pivot highlights;
//                      should look like an unstyled node/edge stroke
//   traversal-palette — gradient palette for *-order-display methods
//
// Strokes are full stroke dicts (`(paint:, thickness:, dash:)`) so users
// can change any aspect — color, width, dash — without us adding more
// keys.
//
// Structural defaults (unstyled node/edge appearance) live in
// `render-theme` (in `tree-anim.typ`). Per-data-structure styling
// (e.g. RBT's red/black palette) lives in each DS's own theme — see
// `rbt-theme` in `rbt.typ`. The merge order is render-theme (lowest
// precedence) → op-theme → per-DS theme → per-snapshot overrides.

/// Default operation theme. Pass a partial dict to
/// #raw("set-op-theme(..)") to override individual roles.
#let default-op-theme = (
  search-stroke: (paint: blue, thickness: 2pt),
  attention-stroke: (paint: rgb("#0891b2"), thickness: 2pt),
  success-stroke: (paint: green, thickness: 2pt),
  settled-stroke: (paint: green, thickness: 3pt),
  success-fill: green.lighten(70%),
  danger-stroke: (paint: red, thickness: 2pt, dash: "dashed"),
  reset-stroke: (paint: black, thickness: 1pt),
  traversal-palette: color.map.magma,
)

#let _op-theme-keys = (
  "search-stroke",
  "attention-stroke",
  "success-stroke",
  "settled-stroke",
  "success-fill",
  "danger-stroke",
  "reset-stroke",
  "traversal-palette",
)

/// Typsy refinement: a dictionary whose keys are a subset of the
/// op-theme keys. Used by #raw("set-op-theme") and the per-call
/// #raw("theme:") arguments to give early errors on typos.
#let OpTheme = Refine(
  Dictionary(..Any),
  d => d.keys().all(k => _op-theme-keys.contains(k)),
)

#let _op-theme-state = state("starling:op-theme", default-op-theme)

/// Override one or more op-theme keys for the rest of the document
/// (state-based, scoped by Typst's normal layout flow). Pass a partial
/// dictionary — only the keys you list are changed; the rest stay at
/// their current values. Unknown keys panic.
#let set-op-theme(theme) = {
  for k in theme.keys() {
    if not _op-theme-keys.contains(k) {
      panic(
        "set-op-theme: unknown key '"
          + k
          + "'. Valid keys: "
          + _op-theme-keys.join(", ")
          + ".",
      )
    }
  }
  _op-theme-state.update(prev => {
    let next = prev
    for (k, v) in theme.pairs() { next.insert(k, v) }
    next
  })
}

// Merge a partial op-theme override into `default-op-theme`, panicking
// on unknown keys. Used by per-call `theme:` arguments (the non-state
// path).
#let _merge-op-theme(override) = {
  for k in override.keys() {
    if not _op-theme-keys.contains(k) {
      panic(
        "op-theme: unknown key '"
          + k
          + "'. Valid keys: "
          + _op-theme-keys.join(", ")
          + ".",
      )
    }
  }
  let next = default-op-theme
  for (k, v) in override.pairs() { next.insert(k, v) }
  next
}

// Resolve a `theme:` argument that may be `auto` (read state) or a
// partial dict (merge into default). Returns either `auto` (signalling
// "read state inside the context block") or a fully merged dict ready
// to use directly.
#let _resolve-op-theme-arg(theme) = if theme == auto {
  auto
} else { _merge-op-theme(theme) }
