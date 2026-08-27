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
#import "/src/ds/rbt.typ"
#import "/src/ds/avl.typ"
#import "/src/ds/b24.typ"
#import "/src/ds/trie.typ"
#import "/src/ds/graph.typ"
#import "/src/ds/sort.typ"
#import "/src/ds/skiplist.typ"

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
    name: "rbt",
    module: rbt,
    verbs: (
      "node",
      "red",
      "black",
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
      "paint-red",
      "paint-black",
      "double-black",
    ),
    displays: (
      "search-display",
      "insert-display",
      "delete-display",
      "fixup-display",
      "in-order-display",
      "pre-order-display",
      "post-order-display",
      "level-order-display",
    ),
  ),
  (
    name: "avl",
    module: avl,
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
      "imbalance-case",
      "balance-factor",
      "unbalanced",
    ),
    displays: (
      "search-display",
      "insert-display",
      "delete-display",
      "rotate-display",
      "fixup-display",
      "in-order-display",
      "pre-order-display",
      "post-order-display",
      "level-order-display",
    ),
  ),
  (
    name: "b24",
    module: b24,
    verbs: (
      "node",
      "leaf",
      "insert",
      "insert-many",
      "delete",
      "contains",
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
      "in-order-display",
      "pre-order-display",
      "post-order-display",
      "level-order-display",
    ),
  ),
  (
    name: "trie",
    seed: "cat",
    module: trie,
    verbs: (
      "insert",
      "insert-many",
      "delete",
      "contains",
      "has-prefix",
      "path-to",
      "resolve",
      "words",
    ),
    displays: ("search-display", "insert-display", "delete-display"),
  ),
  (
    // A graph is built up rather than inserted into, so its verbs differ the
    // most from the trees'. `new` takes a node list; one placed node is
    // enough for `display` to draw.
    name: "graph",
    seed: (("A", 0, 0),),
    module: graph,
    verbs: (
      "add-node",
      "add-edge",
      "with-position",
      "neighbors",
      "weight",
      "contains-node",
      "contains-edge",
      "ek",
      "edge-key",
      "edge-anchor",
      "positioned",
      "adjacency-matrix",
      "adjacency-list",
    ),
    displays: (
      "prim-display",
      "kruskal-display",
      "dijkstra-display",
      "bfs-display",
      "dfs-display",
    ),
  ),
  (
    // A sort is an array of keys, so it has no insert/delete either; its
    // verbs are the two algorithms plus the oracle they are checked against.
    name: "sort",
    module: sort,
    verbs: (
      "counting",
      "radix",
      "sorted",
      "len",
      "positioned",
      "cell-key",
      "entry-key",
      "cell-anchor",
      "entry-anchor",
    ),
    displays: ("counting-display", "radix-display"),
  ),
  (
    // A skip list is a sorted set, so it has the tree verbs without the tree
    // shape; `search-walk` is the descent its animations and its `contains`
    // both run.
    name: "skiplist",
    module: skiplist,
    verbs: (
      "insert",
      "delete",
      "contains",
      "get",
      "keys",
      "levels",
      "len",
      "search-walk",
      "positioned",
      "box-key",
      "forward-key",
      "data-key",
      "box-anchor",
      "forward-anchor",
      "data-anchor",
    ),
    displays: ("search-display", "insert-display", "delete-display"),
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
      "cell-anchor",
      "entry-anchor",
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
  // Private helpers (`_`-prefixed, the convention for "not API" in a language
  // with no visibility control) are exempt.
  for name in d.keys() {
    if name.contains("display") and not name.starts-with("_") {
      assert(
        name == "display" or name.ends-with("-display"),
        message: m.name + ": '" + name + "' should be named '<op>-display'.",
      )
    }
  }
  // The structure is always the first positional argument, so a display can be
  // called on the structure alone and still produce frames. `new` takes
  // whatever that structure is built from — integers for most, words for a
  // trie — so the table names one sample argument per module.
  let frames = (d.display)((d.new)(m.at("seed", default: 1)))
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

// The 1.0 surface (REFACTOR.md §10.1).
#let expected = (
  // Namespaced data structures and vocabularies.
  "bst",
  "rbt",
  "avl",
  "b24",
  "trie",
  "graph",
  "hashmap",
  "sort",
  "skiplist",
  "styles",
  "aux",
  "git",
  // Snapshots and the op stream.
  "blank-snapshot",
  "apply-snapshot",
  "with-node",
  "with-edge",
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
  "resolve-refs",
  "default-theme",
  "set-theme",
  // Presentation.
  "last",
  "stacked",
  "figures",
  "subslides",
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

// And nothing else. Typst has no visibility control, so this equality is the
// only thing standing between a stray import at the top of lib.typ and a name
// users can reach — which is exactly how `starling.git.d` escaped in 0.3.x.
#let extra = exported.keys().filter(n => not expected.contains(n))
#assert.eq(
  extra,
  (),
  message: "lib.typ exports names outside the 1.0 surface: "
    + extra.join(", ")
    + " (see REFACTOR.md §10.1).",
)

// And the names the migration deliberately retired are gone for good.
#let retired = (
  "BST",
  "RBT",
  "AVL",
  "B24",
  "Trie",
  "paint-trie",
  "set-trie-theme",
  "default-trie-theme",
  "TrieTheme",
  "paint-rbt",
  "set-rbt-theme",
  "default-rbt-theme",
  "RbtTheme",
  "bst-factory",
  "HashMap",
  "Graph",
  "node-anchor",
  "edge-key",
  "make-graph-renderer",
  "aux-view-title",
  "Sort",
  "set-sort-theme",
  "default-sort-theme",
  "SortTheme",
  "array-cell-key",
  "array-entry-key",
  "array-cell-anchor",
  "array-entry-anchor",
  "make-array-renderer",
  "Skiplist",
  "set-skiplist-theme",
  "default-skiplist-theme",
  "SkiplistTheme",
  "sl-box-key",
  "sl-forward-key",
  "sl-data-key",
  "sl-box-anchor",
  "make-skiplist-renderer",
  // The two pre-1.0 theme states, and the frame-array shim that served the
  // old typsy frames until the last structure migrated.
  "default-op-theme",
  "set-op-theme",
  "OpTheme",
  "default-render-theme",
  "set-render-theme",
  "RenderTheme",
  "canvases-only",
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
  // The git palette's own state and refinement, folded into the one theme.
  "default-git-theme",
  "set-git-theme",
  "GitTheme",
  "_git-theme-state",
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

// `subslides` composes one piece of content per frame. It takes a lone frame
// too, and its `aux:` / `fit:` arguments are checked up front rather than
// deep inside a layout pass.
#assert.eq(starling.subslides(demo).len(), demo.len())
#assert.eq(starling.subslides(demo.at(1)).len(), 1)
#assert.eq(starling.subslides(demo, fit: 60%).len(), demo.len())

// ===================================================================
// The git DSL's surface
// ===================================================================

// git-graph is a namespace of DSL verbs, not a DS module, so it has its own
// expected surface (REFACTOR.md §9). Everything else in the file is
// `_`-prefixed — this is the module where an accidental export (the cetz
// draw alias, once exported as `starling.git.d`) did real damage.
#let git-verbs = (
  "git-graph",
  "commit",
  "branch",
  "merge",
  "tag",
  "checkout",
  "branch-pointer",
  "head-pointer",
  "detached-commit",
  "git-highlight",
  "background-lanes",
)
#let git-exported = dictionary(starling.git).keys().filter(n => (
  not n.starts-with("_")
))
#assert.eq(
  git-exported.sorted(),
  git-verbs.sorted(),
  message: "starling.git's public surface drifted from REFACTOR.md §9: "
    + git-exported.filter(n => not git-verbs.contains(n)).join(", "),
)

// ===================================================================
// The `insert` call trap
// ===================================================================
//
// Typst parses `x.insert(..)` as a call to its own *mutating* dict/array
// method, and a variable captured from an enclosing scope is read-only — so
// `bst.insert(t, v)` does not compile inside a function body, though the same
// line is fine at top level. Seven of the nine namespaces export `insert`, so
// this is the one verb every user trips over; the manual documents it at
// <insert-trap>.
//
// These assertions pin the two documented workarounds. If a future Typst
// makes the bare form work, the parenthesized one still will — this test
// keeps the escape hatch honest, it does not assert the trap persists.
#let _t = bst.new(5, 3, 8)

// Workaround 1: parenthesize the function reference.
#let _via-parens = v => (bst.insert)(_t, v)
#assert.eq(bst.contains(_via-parens(7), 7), true)

// Workaround 2: import the verb out of the namespace.
#import "/src/ds/bst.typ": insert as _bst-insert
#let _via-import = v => _bst-insert(_t, v)
#assert.eq(bst.contains(_via-import(7), 7), true)

// Hyphenated siblings are unaffected — Typst has no `insert-many` method, so
// the bare form is safe there and needs no workaround.
#let _via-plain = vs => bst.insert-many(_t, ..vs)
#assert.eq(bst.contains(_via-plain((7, 9)), 9), true)

// Placeholder page (tytanic always compares a rendered page).
#set page(width: auto, height: auto, margin: 6pt)
API conformance assertions passed.
