// Theme — one nested dict, one state, one setter, one resolution rule.
//
// The theme has one section per concern:
//
//   render    structural defaults for the unstyled structure (the literal
//             whites and blacks a backend falls back on)
//   op        operation-semantic roles shared across data structures
//             (searching, succeeding, failing, traversing)
//   rbt/trie/hashmap/sort/skiplist
//             styling intrinsic to one data structure
//
// Resolution order, lowest precedence first:
//
//   default-theme  <-  set-theme(..) state  <-  per-call `theme:` override
//   <-  the renderer's node-style/edge-style layers  <-  per-frame snapshot
//
// The state stores *partial* overrides only, so a document that never calls
// `set-theme` pays nothing but an empty-dict read. Only the presentation
// helpers in `slides.typ` read the state (once per call, inside their single
// `context`); display methods and draw backends never do — which is what
// makes a hand-composed `cetz.canvas({ draw-tree(..) })` work outside a
// `context` block.

// ===================================================================
// The defaults
// ===================================================================

/// The full default theme. Every section is complete; per-call overrides and
/// `set-theme` take partial dicts merged over this.
#let default-theme = (
  // ---------------------------------------------------------------
  // Structural defaults for an unstyled structure.
  // ---------------------------------------------------------------
  render: (
    node-fill: white,
    node-stroke: black,
    node-text-fill: black,
    edge-stroke: black,
    // Fill of the transient operation `note` slot.
    note-fill: rgb("#d4a017"),
    // Fill of the persistent edge `tag` slot (AVL heights, trie letters,
    // graph edge weights).
    edge-tag-fill: rgb("#2b6cb0"),
    // Drawn behind in-canvas annotations so they stay legible over edges.
    // Set this to the page color on a non-white background.
    note-bg: white,
    // An elided subtree (`styles.subtree`): drawn as a gray triangle so it
    // does not read as a real node.
    elided-fill: gray,
    elided-stroke: gray,
  ),
  // ---------------------------------------------------------------
  // Operation-semantic roles. Each names a role that `*-display` methods
  // read at render time; they describe *operations*, not structures, so
  // BST search and hash-map probing share `search-stroke`.
  //
  // Strokes are full stroke dicts so a user can change color, width, or
  // dash without us adding more keys.
  // ---------------------------------------------------------------
  op: (
    // Search / insert walk; the descent phase of a delete.
    search-stroke: (paint: blue, thickness: 2pt),
    // Generic "look here": rotation pivots, deletion target, RBT red-red
    // violation, the polled priority-queue entry.
    attention-stroke: (paint: rgb("#ffcd00"), thickness: 2pt),
    // Newly-connected edges.
    success-stroke: (paint: rgb("#7c3aed"), thickness: 2pt),
    // Final ring on a settled node (insert, two-child delete).
    settled-stroke: (paint: rgb("#7c3aed"), thickness: 3pt),
    // Final fill on a settled node.
    success-fill: rgb("#7c3aed").lighten(70%),
    // Broken / removed / rejected edges.
    danger-stroke: (paint: red, thickness: 2pt, dash: "dashed"),
    // Clears an earlier highlight; should look like an unstyled stroke.
    reset-stroke: (paint: black, thickness: 1pt),
    // Gradient sampled by the `*-order-display` traversals.
    traversal-palette: color.map.magma,
  ),
  // ---------------------------------------------------------------
  // Per-data-structure palettes.
  // ---------------------------------------------------------------
  rbt: (
    red-fill: rgb("#E42313"),
    red-stroke: rgb("#E42313"),
    red-text-fill: white,
    black-fill: black,
    black-stroke: black,
    black-text-fill: white,
  ),
  trie: (
    // A node where a stored word ends.
    terminal-fill: rgb("#2f855a"),
    terminal-stroke: rgb("#22543d"),
    terminal-text-fill: white,
  ),
  hashmap: (
    empty-fill: rgb("#f2f2f2"),
    index-fill: rgb("#888888"),
    hash-box-fill: white,
    hash-box-stroke: black,
    tombstone-fill: rgb("#e0e0e0"),
    tombstone-stroke: rgb("#999999"),
    chain-stroke: black,
    chain-fill: white,
  ),
  sort: (
    empty-fill: rgb("#f2f2f2"),
    index-fill: rgb("#888888"),
    row-label-fill: black,
    // Histogram- and bucket-cell tint.
    count-fill: rgb("#eef4fb"),
    // The radix active-digit subscript.
    active-digit-fill: rgb("#2b6cb0"),
    // Connectors for the "buckets" variant's chains / head pointers.
    chain-stroke: rgb("#8a8f98"),
  ),
  skiplist: (
    header-fill: rgb("#eef4fb"),
    header-stroke: black,
    header-text-fill: black,
    nil-fill: rgb("#f2f2f2"),
    nil-stroke: black,
    nil-text-fill: rgb("#666666"),
    index-fill: rgb("#888888"),
    pointer-stroke: black,
    // A box at a level where its node is NOT linked into the list (spliced
    // out, or not yet spliced in) is drawn muted, with the pointers running
    // over it — so it reads as skipped-past rather than a live stop.
    unlinked-fill: rgb("#e6e6e6"),
    unlinked-stroke: rgb("#a8a8a8"),
    unlinked-text-fill: rgb("#9a9a9a"),
  ),
  // NOTE: there is deliberately no `git:` section yet — the git-graph
  // palette carries decorator functions that still live in `git-graph.typ`.
  // See the deferral note in REFACTOR.md §4.4; Phase 6 adds it.
)

// ===================================================================
// Validation and merging
// ===================================================================

#let _section-names = default-theme.keys()

// Panic unless `override` is a well-formed partial theme: known sections,
// each holding a dict of known keys. `who` names the caller.
#let _assert-theme(override, who) = {
  if type(override) != dictionary {
    panic(who + ": expected a dictionary of theme sections, got " + repr(override) + ".")
  }
  for (section, values) in override.pairs() {
    if not _section-names.contains(section) {
      panic(
        who
          + ": unknown theme section '"
          + section
          + "'. Valid sections: "
          + _section-names.join(", ")
          + ".",
      )
    }
    if type(values) != dictionary {
      panic(
        who + ": theme section '" + section + "' must be a dictionary, got " + repr(values) + ".",
      )
    }
    let valid = default-theme.at(section).keys()
    for k in values.keys() {
      if not valid.contains(k) {
        panic(
          who
            + ": unknown key '"
            + k
            + "' in theme section '"
            + section
            + "'. Valid keys: "
            + valid.join(", ")
            + ".",
        )
      }
    }
  }
}

/// Merge a partial theme `override` over `base`, one section at a time. The
/// merge is two levels deep and no deeper: overriding a key replaces its
/// value wholesale, so a sub-style dict (e.g. a stroke) must be given
/// complete. Unknown sections or keys panic.
#let merge-theme(base, override) = {
  _assert-theme(override, "theme")
  let out = base
  for (section, values) in override.pairs() {
    let merged = out.at(section, default: (:))
    for (k, v) in values.pairs() { merged.insert(k, v) }
    out.insert(section, merged)
  }
  out
}

// ===================================================================
// The one state
// ===================================================================

// Holds *partial* overrides, not a resolved theme — so `resolve-theme` can
// layer default < state < per-call without the state having to be complete.
#let _theme-state = state("starling:theme", (:))

/// Override theme keys for the rest of the document. Pass a partial nested
/// dict — only the sections and keys you list change:
///
/// ```typ
/// #set-theme((op: (search-stroke: (paint: teal, thickness: 3pt)),
///             render: (note-bg: rgb("#fdf6e3"))))
/// ```
///
/// Unknown section names or keys panic. Note that reading and writing a
/// Typst state in one document forces a second layout pass; a per-call
/// `theme:` argument on a display avoids that cost.
#let set-theme(overrides) = {
  _assert-theme(overrides, "set-theme")
  _theme-state.update(prev => merge-theme(prev, overrides))
}

/// The active theme: `default-theme`, with the document's `set-theme`
/// overrides merged over it, with `override` merged over that. Pass `(:)`
/// for no override. Reads state, so it must be called inside a `context`
/// block — the `slides.typ` helpers open exactly one `context` per call and
/// pass the result into every frame's builder.
#let resolve-theme(override) = {
  merge-theme(merge-theme(default-theme, _theme-state.get()), override)
}
