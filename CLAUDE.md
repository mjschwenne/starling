# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Note:** This file is git-ignored in this repo (see `.gitignore`) — it is local-only guidance and
> is not committed or shared via version control. Edits here won't show up in `git status`.

## What this is

Starling is a Typst package (`src/lib.typ`, name `starling`, version `1.0.0`) that renders animated
data structures for teaching: binary search trees (`bst`, `rbt`, `avl`), 2-3-4 trees (`b24`), tries
(`trie`), weighted graphs (`graph` — MST, Dijkstra, BFS/DFS), hash maps (`hashmap`), linear sorts
(`sort` — counting / radix), skip lists (`skiplist`), and a git commit-graph DSL (`git`). It is
built on `cetz` (drawing) and, optionally, `diagraph-layout` (graphviz auto-layout, lazily
imported). Typst 0.14 is required. **There is no typsy dependency** — structures are plain
dictionaries.

`docs/manual.typ` is the user-facing documentation and is the best statement of intended usage;
`REFACTOR.md` is the (completed) plan of the 1.0.0 rewrite and records why the architecture is
shaped this way. Where this file and the manual disagree about behavior, check the source.

## Common commands

All workflows go through `just` (and tytanic for tests).

- `just test` — run the visual-regression suite via `tt run --no-fail-fast` (106 tests).
- `just test <pattern>` — run a subset (e.g. `just test bst-insert`); args pass through to `tt run`.
- `just check` — run only the assertion tests (`*-ops`, `core-ops`, `api-conformance`). Fast, and
  the right first gate for a pure-logic change.
- `just update` / `just update <pattern>` — regenerate reference PNGs after intentional visual
  changes.
- `just doc` — build `docs/manual.pdf` and refresh `thumbnail-{light,dark}.svg` (~25s).
- `just version` — print the name/version packaging will use (read from `typst.toml`).
- `just install` / `just install-preview` — package to `@local/starling/<version>` (or `@preview`).
- `just uninstall` / `just uninstall-preview` — remove the installed copy.
- `just ci` — `test` then `doc`; mirrors what CI runs.

The Justfile exports `TYPST_ROOT := <repo root>`, which is why tests use absolute imports like
`#import "/src/lib.typ"`. Run any direct `typst`/`tt` invocation from the repo root (or set
`TYPST_ROOT` yourself), and note that `typst compile` refuses source files outside the root — put
scratch `.typ` files inside the repo, not in `/tmp`.

`flake.nix` provides a dev shell with typst 0.14, tinymist, typstyle, utpm, tytanic, and just.

## Architecture

Four layers, strictly ordered. Each imports only downward.

```text
src/
  lib.typ                 the public surface: an explicit export list, nothing else
  core/                   structure-agnostic animation kernel (cetz + core/* only)
    style.typ             node/edge style allowlists, validation, merging, theme refs
    snapshot.typ          the sparse per-element style overlay
    ops.typ               op constructors + apply-ops
    theme.typ             default-theme, set-theme, merge/resolve
    frame.typ             Frame + Renderer dicts, make-renderer, make-frames, render, overlay
    text.typ              alt-text string builders, display-value
    draw-util.typ         anchor sanitizer, stroke-paint, haloed, muted, fit sizing
  draw/                   drawing backends (cetz + core/* only; never a ds/* file)
    tree.typ graph.typ hashmap.typ array.typ skiplist.typ
  ds/                     data structures (their backend + core/*; graph also graph-layout)
    tree-common.typ       shared binary-tree ops, walks, render-search/traversal/rotate
    bst.typ rbt.typ avl.typ b24.typ trie.typ
    graph.typ hashmap.typ sort.typ skiplist.typ
  styles.typ              the generic semantic style vocabulary (core/* only)
  aux.typ                 aux-strip + aux-view-title (core/* only)
  slides.typ              last, stacked, figures, canvas, subslides (core/* + aux.typ)
  graph-layout.typ        auto-layout; the LAZY in-body diagraph-layout import lives here
  git-graph.typ           the git DSL (cetz + core/theme.typ only)
```

**Import discipline is load-bearing.** Typst has no visibility control and `lib.typ` re-exports
whole modules, so *every* non-public top-level binding — including import aliases — must be
`_`-prefixed. `git-graph.typ` imports cetz as `_cetz` and `resolve-theme` as `_resolve-theme` for
exactly this reason (`starling.git.cetz` and `starling.git.d` were both live, accidental exports
pre-1.0). `tests/api-conformance` asserts `dictionary(lib)` and `dictionary(git)` equal their
expected surfaces exactly; that equality is the tripwire.

### The four data shapes

All plain dicts. Function-valued fields are ordinary fields (no `(fn: ..)` wrapper — that was a
typsy workaround and is gone).

- **Structure** — the data. Carries `kind: "<ds>"` on the root and on every tree node. Every
  operation returns a new one.
- **Snapshot** — `(nodes: (: key -> style), edges: (: key -> style))`, the sparse style overlay for
  one frame. `blank-snapshot()` seeds it. Style dicts are validated against the allowlists in
  `core/style.typ` on entry.
- **Renderer** — `(structure, draw, snapshots, captions, steps, alts, node-style, edge-style,
  sticky, theme)`. `draw` is a bare function; `sticky` defaults to **`false`**.
- **Frame** — `(make, builder, caption, step, alt, extra)`. `builder` is `theme => content`;
  `make` is the two-argument `(theme, extra) => content` that `overlay` re-partially-applies when
  it appends to `extra`. Build frames through `core/frame.typ`'s `frame(..)` constructor, never by
  hand.

### The uniform DS contract

Every `ds/*` module exports, with these exact names (asserted by `tests/api-conformance`):

```text
new(..)                        construction from values
pure ops                       insert / delete / contains / … — structure first, returns a new one
describe(s)                    one-line string, used as the alt-text opener
check-invariants(s)            true, or a panic naming the broken invariant
display(s, ..)                 -> array(Frame), one frame
<op>-display(s, ..)            -> array(Frame); nothing else contains the word "display"
renderer(s, ..)                a Renderer pre-painted with the DS's structural styling
anchor                         re-export of core/draw-util.anchor
key helpers                    that backend's key constructors, short-named
```

Signature rules: structure is always the first positional; `theme:` is always a *partial nested
theme* (never an op-theme or a palette); `node-style:` / `edge-style:` are the base style layers;
`insert-display` takes `label:` wherever `insert` does; `delete-display` takes `search:` wherever a
search phase makes sense. DS-specific flags keep their names: `bits:` (rbt), `factors:`/`heights:`
(avl), `strategy:` (b24, hashmap), `variant:`/`separate-counts:` (sort), `tombstone:`/`rehash:`
(hashmap), and the graph's layout/algorithm flags.

Every display's **final frame carries `step.result`** — the structure the operation produced (the
unchanged input for a search or traversal). That is what `result(frames)` reads, and it is why no
caller writes an operation twice. `tree-common.stamp-result(specs, after)` stamps it onto a spec
list so no display hand-writes it.

### Element keys and anchors

Keys are opaque strings; only backends assign meaning.

| structure | key | notes |
| --- | --- | --- |
| bst/rbt/avl | `""`, `"L"`, `"RL"` | path from the root; edges keyed by their child |
| b24 | `"01"`, `"01#1"` | child indices as digits; `#i` addresses a key compartment |
| trie | `""`, `"c"`, `"ca"` | the prefix spelled by the edges |
| graph | `"A"`, `edge-key(u, v)` | `"u--v"` undirected, `"u->v"` directed |
| hashmap | `cell-key(i)`, `entry-key(i, j)` | `"c3"`, `"c3:1"`; the entry key also keys its link |
| sort | `cell-key(row, col)`, `entry-key(row, i, j)` | `"count:5"`; arrows are keyed by their id |
| skiplist | `box-key(c, l)`, `forward-key(c, l)`, `data-key(c)` | `"b2:0"`, `"f2:0"`, `"d2"` |

`core/draw-util.anchor(key, canvas: none)` is the **one** sanitizer: `"LR"` → `el-LR`, root →
`el-root`, `"c3:1"` → `el-c3-1`, `"01#1"` → `el-01.key-1`. Every backend names its elements with
it, so a callout can point at anything by its key, compass sub-anchors included. `draw/tree.typ`
has to republish cetz-tree's positional group names under `el-<path>` (via a local
`_alias-anchors` element built the way `draw.copy-anchors` is) — the one place starling reaches
into a cetz context, pinned to cetz 0.5.2.

To generalize tree paths to arities > 10, replace digit characters with slash-separated indices;
the touchpoints are the cetz-tree builders in `draw/tree.typ` and the `by-value` / `path-to`
helpers in `ds/tree-common.typ` and `ds/b24.typ`. Everything else treats paths as opaque.

### Theming

**One nested dict, one state, one setter** (`core/theme.typ`). Sections: `render` (structural
defaults), `op` (operation-semantic roles shared by every DS), and a palette section per DS that
needs one (`rbt`, `trie`, `hashmap`, `sort`, `skiplist`, `git`). `bst`, `avl`, `b24`, `graph` have
none.

Resolution, lowest precedence first:

```text
default-theme  <-  set-theme(..) state  <-  per-call theme:  <-  renderer node-style/edge-style
               <-  per-frame snapshot
```

The state stores **partial** overrides only. Only `slides.typ`, `aux.typ`, and `ds/graph.typ`'s
adjacency tables read it (each inside one `context`); display methods and draw backends never do —
which is what makes a hand-composed `cetz.canvas({ draw-tree(..) })` work outside a `context`.
A per-call `theme:` **layers over** the state (a 1.0 behavior change from the pre-1.0 "replace the
palette" rule).

**Theme references** (`core/style.typ`): `role(key)` / `theme-ref(section, key)` store a marker
that `resolve-refs` swaps for the real value inside `make-canvas`, just before the backend runs.
That is what lets `styles.attention("L")` follow a `set-theme` made after the op was built.

**Perf:** reading and writing one Typst state in a document forces a second layout pass. There is
now exactly one state (there were eight), and a document that never calls `set-theme` pays nothing.
Per-call `theme:` is the escape hatch; `docs/manual.typ`'s `<theming-perf>` section is the
user-facing version.

### Step kinds

`step.kind` is the vocabulary of what a frame shows. Universal: `static` (the one frame of
`display`), `init`, `settled` (terminal success of a mutation), `found` / `not-found`. Each module
lists its complete set in a comment block at the top of its file — **read that block first when
touching a module's animations.** Row/column/aux-view kinds (`"buckets"`, `"count"`, `"dist-map"`,
…) are a different namespace and never appear as a `step.kind`; the one deliberate overlap is the
graph's terminal `spanning-tree` prune frame.

Captions are always content; alt is always an explicitly-set str (never derived from a caption).

### The style vocabulary

`styles.typ` holds the generic, theme-following op-array helpers — `attention`, `search`, `success`,
`danger`, `subtree`, `nullify`, `ghost`, `hidden`, `revealed`, `force-show` — each variadic over
keys and each returning an array, so they compose with `+`. DS-specific vocabulary lives in the DS
module: `rbt.paint-red` / `rbt.paint-black` / `rbt.double-black`, `avl.unbalanced`. Note the
deliberate split between `rbt.red` (a *constructor*: `rbt.red(5, l, r)`) and `rbt.paint-red` (a
*style helper*: `rbt.paint-red("L", "RR")`).

`ghost: true` is the progressive-reveal key: every backend draws the element normally and wraps it
in `draw.hide(.., bounds: true)`, so the footprint and the anchors survive but nothing is painted.
`hide: true` is the drop-it-entirely counterpart.

### Presentation

`slides.typ` — `last`, `stacked`, `figures`, `canvas`, `subslides`. `last`/`stacked`/`canvas` open
one `context` and resolve the theme once; `figures`/`subslides` cannot (touying lays each element
out independently), so each opens its own. Everything but `canvas` wraps each frame in an
alt-carrying `figure` — `canvas` is alt-less **by design**, documented as "you own the
accessibility".

`subslides` composes canvas + `aux-strip` + caption per frame. Its side-by-side layouts use `auto`
columns, not `1fr`: a fractional track collapses in the unbounded region `measure` lays content out
in, which would make `fit: (w, h)` scale off a bogus size. `fit: (w, h)` measures *every* frame
(through one shared `_compose-all` call, so Typst's call cache computes them once) and applies one
common factor.

`aux.typ` — `aux-strip(step, view:, labels:, title:, theme:)` renders a frame's auxiliary state.
Contract is `step.aux-views` (a list), for every graph algorithm; the pre-1.0 single-`aux` form is
gone. Kinds: `queue`/`stack` (BFS/DFS), `pq` (Prim), `edge-list` + `partition` (Kruskal),
`dist-pq` + `dist-map` + `prev-map` (Dijkstra).

### The git DSL

`git-graph.typ` is deliberately **off** the Frame/Renderer stack: a stateful, imperative cetz
builder whose verbs mutate `ctx.git-graph` as they draw, called inside a `git-graph({ .. })` block
placed directly in a `cetz.canvas`. Animation is touying-native. It reads the one theme's `git:`
section inside its deferred `_d.set-ctx` closure — the one place a cetz builder has the context a
state read needs. Behavior/layout config (`direction`, `commit-spacing`, `lane-spacing`) and
runtime state are `..style` arguments, **not** theme. Public verbs: `git-graph`, `commit`, `branch`,
`merge`, `tag`, `checkout`, `branch-pointer`, `head-pointer`, `detached-commit`, `git-highlight`,
`background-lanes`.

## Per-module notes

The module header comments carry the algorithm detail (invariants, cases, step vocabulary). What
follows is the map, plus the things that are easy to get wrong.

- **`ds/tree-common.typ`** — the shared half of bst/rbt/avl: factory parsing (`parse-value`),
  `by-value` / `path-to` / `resolve` / `contains`, the four traversal walks, `describe`,
  the descent walks, and the three shared animation bodies `render-search`, `render-traversal`,
  `render-rotate`, plus `stamp-result`. Each takes a `base:` hook — `theme => snapshot`, the DS's
  own structural painting laid under the highlights — which is how one body serves three DSs.
  `by-value, contains, in-order, level-order, path-to, post-order, pre-order, resolve` are
  re-exported from bst/rbt/avl, so `bst.contains` is really this module's.
- **`ds/bst.typ`** — the plainest tree; read it first. Ties go left.
- **`ds/rbt.typ`** — Okasaki insert, Kahrs delete, CLRS-shaped animations. `bits: true` tags each
  node with its black-height bit. `fixup-display(t, violation-path)` animates from a hand-built,
  deliberately unvalidated tree. `rotate` is structural and does *not* restore invariants.
- **`ds/avl.typ`** — heights are 1-indexed and maintained by every operation. `avl.node`'s
  `height: auto` computes it; an explicit `height:` is the escape hatch for a *stale* mid-operation
  spine, which is exactly what `fixup-display` exists to animate. `factors:` tags balance factors,
  `heights:` labels each non-root edge with its subtree height.
- **`ds/b24.typ`** — `strategy:` is `"top-down"` (default, preventive, single-pass) or
  `"bottom-up"` (reactive). Both are correct; the *shapes* can legitimately differ because they
  promote from different states. Per-compartment styling rides `NodeStyle.key-styles` (merged
  index-wise across sticky frames).
- **`ds/trie.typ`** — letters live on the *edges* (the `tag` slot, `edge-tag-fill`), a node's drawn
  value is its terminal bit, and word-end nodes are shaded from the `trie` palette. It rides the
  shared tree backend; the builder is dispatched on `"terminal" in tree`. Captions quote words, so
  they go through a one-line `_cap(s)` that *interpolates* the string into content — writing them
  as markup would turn straight quotes into smart ones and move every ref.
- **`ds/graph.typ`** — four algorithms, each walking the graph once into a list of *moments* that
  become frames. `positioned` is the handshake with the backend; `layout:` opts into `auto-layout`
  (and is the only thing that touches `graph-layout.typ`). `adjacency-matrix` / `adjacency-list`
  return placeable Typst tables, not frames, and resolve the theme themselves. Dijkstra models the
  priority queue explicitly (add-a-fresh-entry, never decrease-key, with `skip` frames for stale
  duplicates) because that is what students implement.
- **`ds/hashmap.typ`** — four strategies off one `_probe-seq`; `hash`/`hash2` are bare function
  fields. The teaching-critical semantics and the two deliberately-buggy modes are in the header.
  Frame-stability matters here: pre-mutation frames carry a *ghost* hash box so the table never
  jumps when the real box appears, and the terminal frames that drop the box ghost it too
  (`tests/hashmap-frame-stability` is the acceptance check).
- **`ds/sort.typ`** — one counting-sort engine keyed by an extractor; radix is that engine per
  digit place. Variants: `"prefix"` (stable, default), `"reconstruct"` (intro, unstable — it
  rebuilds from the histogram alone, so it can only show the first-seen label per key),
  `"buckets"` (the chaining-hash-table view). Elements are `(key, label)` pairs; only `.key` drives
  the histogram.
- **`ds/skiplist.typ`** — forward pointers are *derived*, not stored: at level L the list is the
  subsequence of nodes with `height > L`. Insert and delete are interleaved single passes (the
  surgery happens as the descent reaches each lane). Tower heights come from an explicit `height`
  or a deterministic seeded LCG coin flip. `search-walk` is public because all three animations and
  `contains` run it.
- **`draw/*.typ`** — signature is
  `draw-X(structure, snapshot, node-style: (:), edge-style: (:), theme: default-theme, name: none)`:
  two positionals, the rest named. They read `theme.render` plus their own palette section, never
  state. Shared helpers (`stroke-paint`, `haloed`, `text-fill-for`, `resolve-dims`/`measure-max`,
  `anchor`) come from `core/draw-util.typ` — do not grow a local copy.

## Tests

Tests live in `tests/<name>/test.typ` and are run by tytanic as visual regression: each test
compiles to one or more pages compared against `ref/*.png`. After an intentional visual change, run
`just update <name>` and commit the updated refs. **A ref that moves unexpectedly is a bug, not a
nuisance — diagnose it before updating.**

Assertion-style tests (`*-ops`, `core-ops`, `api-conformance`) don't depend on rendered output but
still emit a placeholder page, since tytanic always compares. `just check` runs exactly those.
`tests/api-conformance/test.typ` is the executable version of the DS contract and the export list;
extend it when a module gains a verb.

To add a visual test, run `tt new <name>` (persistent is the default). Do **not** create the
directory and `test.typ` by hand — tytanic registers a ref-less directory as compile-only and
`just update` then refuses. If that happens, `tt delete <name>` and start over with `tt new`.

CI (`.github/workflows/tests.yml`) runs on Typst 0.14 / tytanic 0.3 and uploads `out/`, `diff/`, and
`ref/` PNGs as artifacts on failure — the first place to look when CI fails but the suite passes
locally.

## Conventions

- **Private is `_`-prefixed**, including import aliases (see Import discipline above). No module
  reaches for another module's `_name`.
- **Functions stay under ~100 lines**, with one deliberate exemption: a function whose body *is*
  the algorithm's control flow (the CLRS/Okasaki/Kahrs traces, the b24 event traces,
  `graph._dijkstra-moments`, the five draw backends) is left whole — splitting it risks behavior
  churn and reads worse. Dispatch tables and multi-phase orchestrators do get split; the recurring
  shape is `_<op>-meta(event, ..)` (caption / step / alt) plus `_<op>-build(event, ..)` (the
  snapshot closure), zipped by `_<op>-specs`.
- **Perf idiom: module-level named helpers over closures built per call.** Typst's result cache
  memoizes a module-level function across call sites and repeat calls; a closure built inside a
  display body is a fresh value that shares nothing. Extracting spec builders to module scope
  measurably sped the suite up (−26% in the Phase 7 sweep).
- **Perf idiom: one shared accumulation closure per phase.** For an animation whose length scales
  with the data, write `let build-all = th => { .. }` once and give each spec
  `build: th => build-all(th).at(i)` — the cache then makes an n-frame animation cost one pass
  instead of n²/2. Adding even one *ignored* argument to `build-all` defeats it (a distinct memo key
  per call: measured 8× slower on a 255-node traversal). For a walk of *bounded* length (the hash
  map's probe/chain walks, bounded by a capacity chosen to fit on a slide) the straightforward
  per-frame rebuild is fine and sometimes faster.
- A Typst closure cannot mutate a captured variable — it is a compile error, not a slowdown — so an
  accumulation must be straight-line `cur = ..; out.push(cur)` inside the closure body.
- **Doc comments are `///` and are parsed by tidy** for the manual. Two traps: a ` -> ` with spaces
  *anywhere* in a docstring is read as the return-type marker and truncates the description (write
  `key`-to-style, or `u->v` unspaced), and a line starting with `=` becomes a markup heading in the
  rendered manual.
- **`import cetz.draw: *` shadows starling's `anchor`** (cetz has its own two-argument one). Import
  selectively in tests, examples, and the manual.
- Ported algorithm bodies are verbatim on purpose. When changing one, validate frame-by-frame (render
  old and new side by side and compare PNG hashes) rather than trusting the suite — a whole-suite ref
  check misses an accumulation off-by-one that no test happens to cover.

## Adding a data structure

1. Write the backend in `draw/`, if an existing one doesn't fit: a plain function
   `(structure, snapshot, node-style:, edge-style:, theme:, name:) => cetz commands`, naming every
   element `anchor(<its key>)` and honoring `ghost` / `hide`.
2. Write `ds/<name>.typ` to the contract above: `new`, pure ops, `describe`, `check-invariants`,
   `display`, the `*-display`s (built with `core/frame.make-frames`), `renderer`, `anchor`, key
   helpers. Put the step vocabulary in the header comment.
3. Add a `<name>:` theme section in `core/theme.typ` only if the structure has intrinsic styling;
   reuse `render` and `op` otherwise.
4. Export the namespace from `lib.typ` and add the module to `tests/api-conformance`.
5. Add tests: one assertion-style `<name>-ops`, plus visual tests per animation.
6. Add a tour chapter and a tidy reference stanza to `docs/manual.typ`.
