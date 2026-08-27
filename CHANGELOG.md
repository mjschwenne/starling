# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0]

A rewrite of the public API. Typsy classes are gone — every structure is a
plain dictionary and every method a module-level function taking the structure
as its first argument — and each data structure now lives in its own namespace
behind a small flat convenience layer. Nothing from 0.3.x keeps working; there
are no shims or deprecation aliases.

This entry also covers the eight data structures, the git DSL, and the
presentation and theming work that landed after 0.2.0 without a changelog entry
of their own. The 0.3.0 version number was set during that development but
never released, so its work is folded in here.

<details>
<summary>Migration guide from v0.2.x / v0.3.x</summary>

Full details, including a name-by-name table, are in the manual's *Migrating
from 0.3.x* chapter.

**Construction and operations** — namespaced functions, structure first:

```typ
// before
#let t = bst(16, 11, 29)
#let t = (t.insert)(5)
#(t.insert-display)(5)

// after
#import starling: bst, result
#let t = bst.new(16, 11, 29)
#let t = bst.insert(t, 5)
#bst.insert-display(t, 5)
```

**Advancing state** — every animation's last frame carries `step.result`, so an
operation is no longer written twice:

```typ
// before
#stacked((t.insert-display)(5))
#let t = (t.insert)(5)

// after
#let frames = bst.insert-display(t, 5)
#stacked(frames)
#let t = result(frames)
```

**The op stream** — the `Op` enum is gone; each constructor is a top-level
function returning an array, so streams compose with `+`:

```typ
// before
#let r = starling.make-renderer(t, sticky: true)
#let r = starling.apply-ops(r, (
  (starling.Op.StyleNode.new)(path: "L", style: (fill: red)),
  (starling.Op.Commit.new)(alt: "Left child."),
))
#(r.render)()

// after
#let r = bst.renderer(t, sticky: true)
#render(apply-ops(r, style-node("L", fill: red) + commit(alt: "Left child.")))
```

Note `sticky` now defaults to `false`; an accumulating stream must ask for it.

**Theming** — one nested dict, one state, one setter:

```typ
// before
#set-op-theme((search-stroke: (paint: teal, thickness: 2pt)))
#set-render-theme((node-fill: yellow))
#(t.search-display)(6, theme: (search-stroke: ..), render-theme: (..))

// after
#set-theme((op: (search-stroke: (paint: teal, thickness: 2pt)),
            render: (node-fill: yellow)))
#bst.search-display(t, 6, theme: (op: (search-stroke: ..), render: (..)))
```

A per-call `theme:` now *layers over* the document's theme instead of replacing
it with the defaults.

**Anchors** — one sanitizer for every backend, keyed by the same element key
the snapshots use: `path-anchor(p)` / `node-anchor(id)` / `cell-anchor(i)` /
`array-cell-anchor(r, c)` / `sl-box-anchor(c, l)` all become
`anchor(<the key>)`. Import `cetz.draw` selectively inside a canvas — a glob
import shadows `anchor` with cetz's own.

</details>

### Added

- Data structures, each in its own namespace with the same contract (`new`,
  pure operations, `describe`, `check-invariants`, `display`, `<op>-display`,
  `renderer`, `anchor`, key helpers): `bst`, `rbt` (red-black), `avl`, `b24`
  (2-3-4), `trie`, `graph`, `hashmap`, `sort` (counting and radix), and
  `skiplist`.
- Literal builders, so a fixture with a specific shape needs no hand-rolled
  constructors: `bst.node` / `bst.leaf`, `rbt.red` / `rbt.black`, `avl.node`
  (height computed by default, or pinned for a deliberately stale spine),
  `b24.node` / `b24.leaf`.
- `styles` — a semantic style vocabulary (`attention`, `search`, `success`,
  `danger`, `subtree`, `nullify`, `ghost`, `hidden`, `revealed`, `force-show`),
  each variadic over element keys and each following the active theme through
  theme references. Structure-specific vocabulary lives with its structure:
  `rbt.paint-red` / `rbt.paint-black` / `rbt.double-black`, `avl.unbalanced`.
- `ghost` node style — invisible but space-reserving, so a progressive reveal
  never shifts what is already on the slide.
- `subslides` — one composed piece of content per frame (canvas, auxiliary
  strip, caption), with `aux:` placement, `aux-view:` selection, and a `fit:`
  that measures the whole animation and applies one common scale factor so the
  drawing does not resize between subslides.
- `aux-strip` — the auxiliary state of the graph algorithms (BFS queue, DFS
  stack, Prim's frontier, Kruskal's sorted edges and disjoint sets, Dijkstra's
  priority queue and its `dist` / `prev` maps) as placeable content.
- `overlay(frames, at:, draw:)` — append cetz commands inside an existing
  frame's canvas, with the backend's anchors in scope and the resolved theme
  available to the callout.
- `result(frames)` — the structure an animation's final frame produced.
- `make-renderer(structure, draw, ..)` as a documented extension point: a draw
  backend is a plain function, and the bundled five go through the same door.
- An anchor helper per key helper, so naming an element in your own cetz code
  is one call rather than two: `hashmap.cell-anchor` / `entry-anchor`,
  `sort.cell-anchor` / `entry-anchor`, `skiplist.box-anchor` / `forward-anchor`
  / `data-anchor`, and `graph.edge-anchor(g, u, v)`. Each takes the same
  `canvas:` argument as `anchor`. A graph node's key is its id and a tree's key
  is its path, so those stay `anchor(key)`.
- `with-node` / `with-edge` on the public surface, so a snapshot can be built
  by hand — the progressive-reveal idiom — without routing every element
  through the op stream just to fold it straight back in.
- A partial `theme:` on the `draw-*` backends, matching every DS-level entry
  point: naming one key layers it over the default rather than requiring a
  whole resolved theme. The full theme the animation path passes merges to
  itself, so nothing there changes.
- `resolve-refs(style, theme)` on the public surface, for a draw backend of
  your own. The bundled backends now call it themselves, so a snapshot carrying
  theme references — anything from a structure's `renderer()` or from
  `styles.*` — can be handed straight to `draw-tree` and friends inside your
  own `cetz.canvas`. Previously only `make-canvas` resolved, so that path
  panicked deep inside cetz with `expected color, found dictionary`, and
  `resolve-refs` being private left no way to work around it.
- `set-theme` / `default-theme` — one nested theme with a section per concern
  (`render`, `op`, and a palette per structure that needs one), replacing eight
  separate states and setters.
- Graph algorithm animations: Prim, Kruskal, Dijkstra (with an explicit
  priority queue that adds rather than decreases keys, `skip` frames for stale
  entries, and optional path reconstruction), and BFS / DFS with `target:`,
  `sort-frontier:`, and `spanning-tree:` modes.
- `graph.adjacency-matrix` / `graph.adjacency-list` — static tabular renderings
  that are placeable content rather than frames.
- `auto-layout` — optional graphviz layout through `diagraph-layout`, imported
  lazily inside the function body so it stays an optional dependency.
- Deliberately buggy teaching modes: `hashmap.delete(.., tombstone: false)`
  (clear the slot instead of tombstoning, so a later search misses) and
  `hashmap.resize(.., rehash: false)` (copy entries to their old indices).
- `git` — the commit-graph DSL (`git-graph`, `commit`, `branch`, `merge`,
  `tag`, `checkout`, `branch-pointer`, `head-pointer`, `detached-commit`,
  `git-highlight`, `background-lanes`), now themed from the one theme's `git`
  section.
- `just check`, running only the assertion tests.

### Changed

- Structures are plain dictionaries; operations are namespaced functions taking
  the structure first (`bst.insert(t, 5)`).
- `sticky` defaults to `false` on renderers.
- A per-call `theme:` layers over the `set-theme` state instead of replacing
  the palette with the defaults.
- `theme:` means the same thing everywhere — a partial nested theme. It used to
  mean the op theme on some structures and a per-structure palette on others.
- One anchor scheme (`anchor(key)`) across all five backends, and every backend
  takes `name:` to wrap its drawing in a named cetz group.
- `last` accepts a lone frame as well as an array.
- Every animation's final frame carries `step.result`; step kinds were
  regularised (`settle` → `settled`, terminal `done` → `settled`, `miss` →
  `not-found`, the hash map's four miss kinds → `not-found` with a
  `step.reason`).
- Captions are always content and alt text is always set explicitly — nothing
  derives alt from a caption any more.
- `mst-prim-display` / `mst-kruskal-display` → `graph.prim-display` /
  `graph.kruskal-display`; `counting-sort-display` / `radix-sort-display` →
  `sort.counting-display` / `sort.radix-display` (pure: `sort.counting` /
  `sort.radix`).
- `insert-display` takes `label:` wherever `insert` does, and `delete-display`
  takes `search:` wherever a search phase makes sense.
- `b24.check-invariants` and `trie.check-invariants` return `true` or panic,
  like every other structure's.
- The manual documents every public module, the theme, the module contract, the
  style vocabulary, and the extension story, and carries the migration table.

### Removed

- typsy: no classes, no refinements, no `(fn: ..)` field wrappers.
- The `Op` enum, including `Op.Highlight` (use `style-node(key, stroke: ..)`)
  and `Op.ClearNotes` (use `style-node(key, note: none)`).
- The eight theme states and their setters (`set-op-theme`, `set-render-theme`,
  `set-rbt-theme`, `set-trie-theme`, `set-hashmap-theme`, `set-sort-theme`,
  `set-skiplist-theme`, `set-git-theme`) and the `default-*-theme` constants,
  all folded into `set-theme` / `default-theme`.
- The `render-theme:` argument (now `theme: (render: (..))`).
- `canvases-only` (use `canvas` per frame, or `subslides`), `concat-frames`,
  `GraphNodeId`, `TreeRenderer`, and the `paint-rbt` / `paint-trie` painters
  (absorbed into each structure's `renderer`).
- The per-backend anchor helpers (`path-anchor`, `node-anchor`, `cell-anchor`,
  `entry-anchor`, `array-cell-anchor`, `array-entry-anchor`, `sl-box-anchor`,
  `sl-forward-anchor`, `sl-data-anchor`) and the `make-*-renderer` wrappers.
- `array-arrow-key` — an identity function; the arrow id is the key.
- The collision-avoidance prefixes on key helpers: `array-cell-key` →
  `sort.cell-key`, `sl-box-key` → `skiplist.box-key`, and so on.

## [0.2.0]

<details>
<summary>Migration guide from v0.1.X</summary>

The `*-display` methods now return `Array(Frame)` instead of pre-wrapped
content. Each `Frame` is a record `(canvas, caption, step)`. The
`configure(wrap: ...)` entrypoint and the closure-captured `wrap`
parameter are gone — wrap the frames yourself with one of the new
helpers (`last`, `stacked`, `figures`, `canvases-only`).

**Static use:**

```typ
// before
#(t.insert-display)(5)

// after
#starling.last((t.insert-display)(5))
```

**Touying:**

```typ
// before
#let (BST,) = (starling.configure)(wrap: alternatives)
#(t.search-display)(6)

// after
#import starling: BST
#alternatives(..starling.figures((t.search-display)(6)))
```

**Custom slide layouts:**

```typ
#let frames = (t.search-display)(6)
#grid(columns: 2,
  alternatives(..starling.figures(frames, caption: false)),
  alternatives(..frames.map(f => f.caption)),
)
```

`Op.Caption` was removed from the `Op` enum. Captions are renderer-level
now, set directly via `r.with-caption(...)` between Op batches.

The internal `Frame` typsy class (a sparse style overlay) was renamed
`Snapshot`. `blank-frame` is now `blank-snapshot`. The public `Frame`
name now refers to the output record described above.

The rotation animation gained a "restructure" frame between breaking
the old edges and connecting the new ones, plus a final settled frame
with highlights cleared. The dashed-red "edge about to break"
intermediate frame was dropped.

</details>

### Changed

- `*-display` methods return `Array(Frame)`; wrap with `starling.last`,
  `starling.stacked`, or `starling.figures` (the latter splats into
  touying's `alternatives(..)`).
- The internal style snapshot class `Frame` was renamed `Snapshot`;
  `blank-frame` → `blank-snapshot`. The public `Frame` name is now the
  output record (`canvas`, `caption`, `step`).
- Rotation animation reordered: init → pivots → break → restructure →
  connect → settle. The intermediate dashed-red break frame was dropped.

### Added

- `Frame` record class with `canvas`, `caption`, `step` fields. Each
  `*-display` method documents the `step.kind` values it emits.
- Render helpers: `last`, `stacked`, `figures`, `canvases-only`.
- `TreeRenderer.with-caption(c)` and `TreeRenderer.with-step(s)` for
  setting renderer-level frame metadata.
- `draw-tree(tree, snapshot, ...)` — cetz draw commands for one
  snapshot, *without* the surrounding `cetz.canvas`, so callers can
  compose with their own annotations.
- `path-anchor(path)` — translates an L/R path to the cetz anchor name
  of the corresponding node circle, for annotating specific nodes from
  user-provided cetz code.

### Removed

- `configure(wrap: ...)`. Callers wrap frame arrays with the new helpers
  (or any other strategy) themselves.
- `Op.Caption` variant. Use `r.with-caption(...)` between Op batches.
- `Snapshot.with-caption` (caption moved off the snapshot).
- `Snapshot.caption` field.
- `TreeRenderer.static(...)` (replaced by `starling.last(frames)`).

## [0.1.0] - 2025-01-01

Initial release.

[1.0.0]: https://github.com/mjschwenne/starling/compare/v0.2.0...v1.0.0
[0.2.0]: https://github.com/mjschwenne/starling/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/mjschwenne/starling/releases/tag/v0.1.0
