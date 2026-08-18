// The DS module contract, asserted rather than documented.
//
// Every data-structure module presents the same surface (REFACTOR.md §7.1), so
// a reader who knows one knows them all. This test is the tripwire that keeps
// that true as the remaining structures migrate: extend the `modules` table
// below with each one as it lands in `ds/`.
//
// It also watches `lib.typ`'s exports. Typst has no visibility control, so an
// accidental import at the top of lib.typ silently becomes public API — that is
// how `starling.git.d` escaped in 0.3.x.

#import "/src/lib.typ" as starling
#import "/src/ds/bst.typ"
#import "/src/ds/hashmap.typ"

// ===================================================================
// The per-module contract
// ===================================================================

// Names every DS module must export, whatever it stores.
#let universal = (
  "new",
  "display",
  "renderer",
  "describe",
  "check-invariants",
  "anchor",
)

// Plus the verbs specific to each. Listed explicitly rather than derived: a
// graph has `add-node` / `add-edge` where a tree has `insert`, and the point of
// the table is to say so out loud.
#let modules = (
  (
    name: "bst",
    module: bst,
    verbs: (
      "node",
      "leaf",
      "insert",
      "insert-many",
      "delete",
      "contains",
      "rotate",
      "by-value",
      "path-to",
      "resolve",
      "in-order",
      "pre-order",
      "post-order",
      "level-order",
    ),
    displays: (
      "search-display",
      "insert-display",
      "delete-display",
      "rotate-display",
      "in-order-display",
      "pre-order-display",
      "post-order-display",
      "level-order-display",
    ),
  ),
  (
    name: "hashmap",
    module: hashmap,
    verbs: (
      "insert",
      "delete",
      "contains",
      "get",
      "resize",
      "size",
      "load-factor",
      "hash-of",
      "probe-seq",
      "positioned",
      "cell-key",
      "entry-key",
    ),
    displays: (
      "insert-display",
      "search-display",
      "delete-display",
      "resize-display",
    ),
  ),
)

#for m in modules {
  let d = dictionary(m.module)
  for name in universal + m.verbs + m.displays {
    assert(
      name in d,
      message: m.name + " must export '" + name + "' (see REFACTOR.md §7.1).",
    )
  }
  // Every animation is named `<op>-display`, and nothing else wears the word.
  for name in d.keys() {
    if name.contains("display") {
      assert(
        name == "display" or name.ends-with("-display"),
        message: m.name + ": '" + name + "' should be named '<op>-display'.",
      )
    }
  }
  // The structure is always the first positional argument, so a display can be
  // called on the structure alone and still produce frames.
  let frames = (d.display)((d.new)(1))
  assert(
    type(frames) == array and frames.len() >= 1,
    message: m.name + ".display must return a non-empty array of frames.",
  )
  // And every display's last frame carries the result, which is what lets a
  // caller advance their variable without writing the operation twice.
  assert(
    "result" in frames.last().step,
    message: m.name + ": the final frame must carry `step.result`.",
  )
}

// ===================================================================
// lib.typ's exports
// ===================================================================

// The 1.0 surface (REFACTOR.md §10.1). `subslides` lands in Phase 6.
#let expected = (
  // Namespaced data structures and vocabularies.
  "bst",
  "hashmap",
  "styles",
  "git",
  // Snapshots and the op stream.
  "blank-snapshot",
  "apply-snapshot",
  "style-node",
  "style-edge",
  "annotate",
  "set-alt",
  "set-caption",
  "set-step",
  "commit",
  "apply-ops",
  // Frames and renderers.
  "make-renderer",
  "render",
  "overlay",
  "result",
  // Theme.
  "theme-ref",
  "role",
  "default-theme",
  "set-theme",
  // Presentation.
  "last",
  "stacked",
  "figures",
  "canvas",
  // Backends and anchors.
  "draw-tree",
  "draw-graph",
  "draw-hashmap",
  "draw-array",
  "draw-skiplist",
  "anchor",
  // Layout and aux.
  "auto-layout",
  "aux-strip",
)

#let exported = dictionary(starling)
#for name in expected {
  assert(name in exported, message: "lib.typ must export '" + name + "'.")
}

// TRANSITIONAL. lib.typ still carries the pre-1.0 surface for the structures
// that have not migrated yet, so the check above is a subset test. Phase 6
// tightens it to equality — that is the tripwire against accidental exports —
// once the last `#import "./<old>.typ"` block is gone. Until then, assert only
// that the names Phase 3 deliberately retired have in fact gone.
#let retired = (
  "BST",
  "bst-factory",
  "HashMap",
  "concat-frames",
  "GraphNodeId",
  "TreeRenderer",
  "Op",
  "path-anchor",
  "cell-anchor",
  "entry-anchor",
  "make-hashmap-renderer",
  "set-hashmap-theme",
  "default-hashmap-theme",
  "HashmapTheme",
)
#for name in retired {
  assert(
    name not in exported,
    message: "lib.typ still exports the retired name '" + name + "'.",
  )
}

// ===================================================================
// The presentation helpers
// ===================================================================

#let demo = bst.search-display(bst.new(4, 1, 7), 7)

// `figures` gives one piece of content per frame, for touying's
// `alternatives(..)`.
#assert.eq(starling.figures(demo).len(), demo.len())

// `last` accepts a lone frame as well as an array, so pulling one step out of
// an animation needs no re-wrapping.
#assert.eq(type(starling.last(demo.at(1))), content)
#assert.eq(type(starling.last(demo)), content)

// `canvas` is the bare, alt-less form for hand-built layouts.
#assert.eq(type(starling.canvas(demo.first())), content)

// Placeholder page (tytanic always compares a rendered page).
#set page(width: auto, height: auto, margin: 6pt)
API conformance assertions passed.
