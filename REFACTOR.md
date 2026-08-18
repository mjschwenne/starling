# Starling 1.0.0 Refactor Plan

**Status:** approved by mjs, ready to implement. **Written:** 2026-08-12, by
Claude (Fable 5) after a full audit of `src/` and a survey of one semester of
real usage (`~/Documents/classes/cs400/lectures/`). **Audience:** the
implementing agent (Claude Opus). This document is the authority for the
*target* design. `CLAUDE.md` accurately describes the *current* (pre-refactor)
architecture — use it to understand existing code, but where it conflicts with
this plan, this plan wins. `CLAUDE.md` gets rewritten in Phase 8, not before.

---

## 0. How to Work This Plan

- Create a branch `refactor/v1` off `main` before touching anything. Commit at
  least once per phase, with the phase number in the commit message.
- Work **one phase at a time, in order**. Each phase ends with `just test`
  green. Do not start a phase until the previous one's "Done when" criteria all
  hold.
- **The visual-regression suite is the contract.** Unless a task explicitly says
  "refs change", every migrated test must produce pixel-identical output. When a
  ref unexpectedly differs, STOP and diagnose — do not run `just update` to make
  the problem go away. When a task says refs change, inspect the diff PNGs
  (`tests/<name>/diff/`) before `just update <name>`.
- `just doc` (the manual) will be broken from Phase 3 until Phase 8. That is
  expected. The gate during migration is `just test` only. Do not "fix" the
  manual piecemeal mid-migration.
- New visual tests must be created with `tt new <name>` — never by hand-creating
  the directory (tytanic registers a ref-less directory as compile-only and
  `just update` then refuses).
- Run everything from the repo root (the Justfile exports `TYPST_ROOT`; tests
  use absolute imports like `#import "/src/lib.typ"`).
- Functions should stay under ~100 lines; module-private helpers get a leading
  `_`. **Every** non-public top-level binding — including import aliases — must
  be `_`-prefixed, because Typst modules have no visibility control and lib.typ
  re-exports whole modules (this is how `starling.git.d` accidentally became
  public API in 0.3.x).

### Decisions Already Made — Do Not Relitigate

1. **typsy is removed entirely.** Structures become plain dictionaries; methods
   become module-level functions. No typsy import remains anywhere in `src/`
   when this is done.
2. **No backwards compatibility.** No shims, no deprecation aliases. Old names
   die.
3. **Version is `1.0.0`.**
4. **git-graph stays in this package**, namespaced as `starling.git`, ported
   onto the unified theme dict but otherwise architecturally unchanged (it
   remains a stateful imperative cetz builder, deliberately off the
   Frame/Renderer stack).
5. **The public API is namespaced per data structure**
   (`starling.bst.insert(t, 5)`), with a small flat convenience layer (frames
   helpers, op constructors, theme). Nobody uses `import starling: *` (verified
   across all tests and a full semester of lectures), so collision-avoidance
   prefixes like `array-cell-anchor` / `sl-box-anchor` are abolished.

---

## 1. Why (Context for the Implementer)

Findings from the audit that this refactor exists to fix. Keep them in mind;
they justify specific choices below.

**In `src/` (19,692 lines):**

- 13 near-identical `_make-frames*` functions (363 lines), 8 copies of the
  ~90-line theme scaffolding block, 9 copies of `_resolve-render-theme-arg`, 5
  byte-identical `_draw-*-backend` wrappers, 4 copies of `_stroke-paint`, 3 of
  `_haloed`, 4 of `_text-fill-for`, 4 near-identical tree factories, 3 copies of
  the binary-tree traversals and `_render-traversal`. ≈2,000 lines are
  mechanical duplication.
- `theme:` on display methods means **op-theme** for BST/AVL/B24/Graph but
  **per-DS palette** for RBT/Trie/HashMap/Sort/Skiplist; the latter five have no
  per-call op-theme override.
- Five incompatible anchor-naming schemes (`node-`, `cell-`, `acell-`, `slbox-`,
  tree paths).
- typsy taxes: the `(fn: ..)` singleton-dict wrapper (6 places), mutator methods
  re-listing all 11 `Renderer` fields, `self.meta.cls` threading forcing "1,900
  lines of helpers, class at the bottom" file layout, `(t.method)(args)` syntax
  that the author's autoformatter mangles.
- Dead exports: `concat-frames`, `GraphNodeId`, `array-arrow-key` (an identity
  function); accidental exports through `starling.git.*` and the bare
  `tree-anim` module re-export.
- `hashmap-draw._resolve-dims` lacks the `measure-cells` superset that
  sort/skiplist use for frame-stable "fit" sizing — a real divergence, not just
  style.
- Docs reference an op-theme key `pivot-stroke` that does not exist in the code
  (`attention-stroke` is the real key).

**In the lectures (what users actually need):**

- ~200 lines of hand-written Op-style helpers (`disp_red`, `subtree`, `null`,
  `force_show`, `double_black`, …) duplicated across decks in three incompatible
  shapes. `Op.StyleNode` called 146×, `Op.StyleEdge` 69× — almost always
  expressing ~10 recurring semantic intents.
- Three hand-rolled tree-literal constructor sets (`bleaf/rleaf/bnode/rnode`,
  `avll/avln` with a reimplemented height recursion, `n2/l2/n3/…` reimplementing
  b24's private `parse`).
- A `grid + canvases-only + aux-strip + f.caption` sandwich repeated 10×;
  `scale(x: N%, reflow: true)` wrappers hand-tuned 35×.
- 28 sites write every operation twice: `(t.insert-display)(x)` for frames, then
  `#(t = (t.insert)(x))` to advance state.
- 9 sites reach into `renderer.snapshots.at(0)` to redraw inside a canvas just
  to add a callout; `draw-graph` lacks `name:` (there's a commented-out attempt
  in lecture 13).
- All eight `set-*-theme` state setters: **zero uses in an entire semester.**
  Explicit theme dicts were passed instead, to avoid needing `context` inside
  `cetz.canvas` bodies.
- `canvases-only` drops the alt-text figure wrapper — on decks compiled
  `--pdf-standard ua-1`.
- `starling.last((((m.search-display)(7)).at(3),))` — the 1-tuple re-wrap to
  show one frame.

---

## 2. Target File Tree

```text
src/
  lib.typ                 public surface (explicit export list, §10)
  core/
    style.typ             node/edge style key allowlists, validation, merge, theme-ref markers
    snapshot.typ          snapshot dict, blank-snapshot, apply-snapshot
    ops.typ               op constructors + apply-ops
    theme.typ             default-theme, set-theme, merge/resolve
    frame.typ             Frame + Renderer dicts, make-renderer, render, make-frames,
                          overlay, result
    text.typ              alt-label, alt-key-label, alt-intro, display-value helpers
    draw-util.typ         stroke-paint, haloed, resolve-dims, anchor sanitizer, shared
                          geometry helpers for the table backends
  draw/
    tree.typ              from tree-anim.typ (drawing half)
    graph.typ             from graph-draw.typ
    hashmap.typ           from hashmap-draw.typ
    array.typ             from array-draw.typ
    skiplist.typ          from skiplist-draw.typ
  ds/
    tree-common.typ       shared binary-tree ops, traversal walks, factory parsing,
                          render-traversal
    bst.typ  rbt.typ  avl.typ  b24.typ  trie.typ
    graph.typ  hashmap.typ  sort.typ  skiplist.typ
  styles.typ              the generic semantic style vocabulary (§8)
  aux.typ                 aux-strip + aux-view-title, lifted out of graph
  slides.typ              last, stacked, figures, subslides, canvas, fit machinery
  graph-layout.typ        unchanged location; auto-layout keeps its LAZY in-body
                          `#import "@preview/diagraph-layout:…"` — never move that import
                          to module scope
  git-graph.typ           kept; internals renamed to `_`-prefixed (§9)
```

Files that must not exist when the refactor is done: `anim-core.typ`,
`tree-anim.typ`, `op-theme.typ`, `graph-draw.typ`, `hashmap-draw.typ`,
`array-draw.typ`, `skiplist-draw.typ`, and the nine old top-level DS files
(`bst.typ` … `skiplist.typ` at `src/` root).

Import discipline (checked at the end of every phase):

- `core/*` imports only cetz and other `core/*` files. No typsy anywhere.
- `draw/*` imports cetz + `core/*`. Never a `ds/*` file.
- `ds/*` imports its backend(s) + `core/*` (+ `graph-layout.typ` for ds/graph
  only).
- `styles.typ`, `aux.typ`, `slides.typ` import `core/*` only.
- `git-graph.typ` imports cetz + `core/theme.typ` only.

---

## 3. Data Shapes (Plain Dicts Replace Every Typsy Class)

There is no typsy, so there is no self-injection:
**function-valued dict fields are fine and need no `(fn: ..)` wrapper**. Delete
that pattern everywhere; do not cargo-cult it from old code. Calling convention
for a function stored in a dict: `(frame.builder)(theme)`.

### 3.1 Structures

Every structure dict carries `kind: "<ds>"` (`"bst"`, `"rbt"`, `"avl"`, `"b24"`,
`"trie"`, `"graph"`, `"hashmap"`, `"sort"`, `"skiplist"`) on the root
**and on every tree node** (nodes are recursively full structures, as today).
Field sets are otherwise carried over from the typsy classes verbatim:

```typ
// bst node        (kind: "bst", value: 5, label: auto, left: none, right: none)
// rbt node        (kind: "rbt", value: 5, label: auto, red: false, left: …, right: …)
// avl node        (kind: "avl", value: 5, label: auto, height: 2, left: …, right: …)
// b24 node        (kind: "b24", keys: (5, 9), labels: (auto, auto), children: (…))
// trie node       (kind: "trie", char: none|"c", terminal: false, children: (…))
// graph           (kind: "graph", nodes: (:), edges: (), directed: false, positions: (:))
// hashmap         (kind: "hashmap", slots: (), capacity: 7, strategy: "linear",
//                  hash: <fn>, hash-repr: "k mod m", hash2: <fn>, hash2-repr: …)
// sort            (kind: "sort", values: (), labels: ())
// skiplist        (kind: "skiplist", nodes: (), max-level: 4, seed: …, rng-state: …,
//                  p: 0.5, nil: true)
```

Note `hashmap.hash` is now a **bare function** field (the `(fn:)` wrapper dies
here too).

Validation: constructors (`new`, `node`, `leaf`, …) assert their inputs with
clear messages
(`assert(v >= 0, message: "skiplist: keys must be non-negative, got " + repr(v))`).
Internal functions trust their inputs. Two tiny helpers in `core/style.typ`
serve everyone:

```typ
#let assert-keys(dict, allowed, who)   // panics naming the offending key and `who`
#let assert-any-of(value, options, who)
```

### 3.2 Snapshot

```typ
(nodes: (: "<key>": style-dict ), edges: (: "<key>": style-dict ))
```

`blank-snapshot()` returns `(nodes: (:), edges: (:))`. Keys are the same opaque
strings as today (tree paths, graph ids/edge-keys, `"c3:1"`, `"count:5"`,
`"b2:0"`, …) — **key formats do not change** in this refactor; only cetz
*anchor* names unify (§6).

### 3.3 Ops

Plain tagged dicts, built by constructor functions that each return an **array**
of ops (so they compose with `+`). Dispatch in `apply-ops` is on the `op` string
field.

```typ
(op: "style-node", key: "LR", style: (fill: …))
(op: "style-edge", key: "R",  style: (hide: true))
(op: "annotate",   key: "L",  note: [h = 2])
(op: "alt",        text: "…")
(op: "commit",     caption: none|content, step: none|dict, alt: none|str)
```

Port the fold semantics of `apply-ops` from `anim-core.typ` verbatim (pending
snapshot, sticky mode, commit pushes a frame).

**Settled in Phase 1** (was: grep and decide):

- `Op.Highlight` — dropped, no replacement. Its only uses were old tests and
  the manual; `style-node(key, stroke: blue + 2pt)` says the same thing. When
  migrating `bst-op-stream`, `bst-cetz-anchors`, `hashmap-anchors`, and
  `graph-anchors`, rewrite it that way.
- `Op.ClearNotes` — dropped from the op vocabulary, but `bst.delete-display`
  (`search: true`) genuinely needs it, so the capability survives as
  `snapshot.clear-notes(snap)`. Call that from a spec's `build` closure; do
  not re-add an op for it, and do not export it from lib.typ.
  **Phase 3 footnote:** a *user-driven* op stream can't reach that helper, and
  a sticky frame does sometimes need to drop a note it inherited. The answer
  there is `style-node(key, note: none)` — the backends only draw a note when
  it is non-`none`, so an explicit `none` clears one slot. `bst-op-stream`
  demonstrates it. Still no op.
- **Added in Phase 3: `set-caption(c)` and `set-step(s)`**, siblings of
  `set-alt`. The trailing in-progress frame has no closing `commit`, which is
  exactly why `set-alt` exists — and the argument applies verbatim to the other
  two pieces of frame metadata. Without `set-caption` a hand-driven stream
  cannot caption its last frame, and without `set-step` it cannot stamp the
  `step.result` that `result(frames)` reads. Both are one line each in
  `core/ops.typ` and one dispatch arm in `apply-ops`.
- `commit(caption:, step:, alt:)` assigns only the arguments that are not
  `none`, so an earlier `set-alt` is not wiped by a bare `commit()`.

### 3.4 Frame

```typ
(
  make:    (theme, extra) => content,   // the real builder (see below)
  builder: (theme) => content,   // theme = the FULL resolved nested theme dict (§7)
  caption: none | content,       // always content, never str (normalize sort/trie)
  step:    dict,                 // step.kind per §5; final frame carries step.result
  alt:     str,                  // always a str, always set explicitly
  extra:   (),                   // array of cetz command blocks appended inside the canvas
)
```

**`make` was added in Phase 1** and is not optional. `overlay` appends to
`extra` *after* the frame exists, but a one-argument builder has already
captured the extras it was constructed with — the first cut of this silently
dropped every overlay. So the frame keeps the two-argument `make`, and
`builder` is just `make` partially applied to the frame's current `extra`;
`overlay` rebuilds `builder` from `make` when it appends. Callers still use
`(frame.builder)(theme)` and never touch `make`. Build frames through
`frame.typ`'s `frame(make, caption:, step:, alt:, extra:)` constructor rather
than writing the dict by hand, and this stays consistent.

### 3.5 Renderer

```typ
(
  structure: <any>, draw: <fn>, snapshots: (), captions: (), steps: (), alts: (),
  node-style: (:), edge-style: (:), sticky: false, theme: (:),
)
```

`draw` is a bare function
`(structure, snapshot, node-style: .., edge-style: .., theme: ..) => cetz cmds`.
The five old `_draw-*-backend` wrapper constants are deleted; pass the draw
function directly. The old `default-node-style:`/`default-edge-style:` parameter
names shrink to `node-style:`/`edge-style:` everywhere (renderers, displays,
draw backends).

⚠️ **Amended in Phase 2:** `make-canvas` passes the two structural arguments
positionally and the three style arguments **by name**, which is what lets a
backend carry the defaults §6.1 gives it (`node-style: (:)`, `edge-style: (:)`,
`theme: default-theme`) and still be callable by hand inside a plain
`cetz.canvas`. Phase 1 wrote the call as five positionals, which no function
with named parameters can accept; `core/frame.typ` and the `core-ops` stub
backends were updated. A custom backend must therefore declare
`(structure, snapshot, node-style: (:), edge-style: (:), theme: ..)`.

⚠️ **`sticky` now defaults to `false`** (it was `true` in `anim-core.typ`). It
governs only the `make-renderer` + `apply-ops` path, and accumulation is the
idiom that path exists for, so **the four op-stream tests must pass
`sticky: true` explicitly when they migrate** — `bst-op-stream`,
`bst-cetz-anchors` (Phase 3), `hashmap-anchors` (Phase 3), `graph-anchors`
(Phase 5). Their refs are pixel-identical with that one argument added; without
it the highlights stop accumulating and the refs change. Same for any DS
`renderer()` whose animation expects accumulation.

`core/frame.typ` also exports the renderer mutators `push-frame`, `patch`,
`with-caption`, `with-step`, `with-alt` (unprefixed, because `core/ops.typ`
folds through them). They are deliberately **absent from lib.typ's export
list** — the public way to drive a renderer is the op stream.

---

## 4. The Core Modules (Phase 1 Deliverables)

### 4.1 `core/style.typ`

- `node-style-keys` / `edge-style-keys`: the allowlists from
  `anim-core.typ:29-65`, plus one new node key `ghost` (bool, §6.3). Keep the
  graph-only keys with a comment saying which backends honor which.
- `merge-style(base, override)`, `merge-into(base, override)` — port from
  anim-core.
- **Theme references** (this replaces hard-coded colors in the style
  vocabulary):

  ```typ
  #let theme-ref(section, key) = (starling-theme-ref: (section, key))
  #let role(key) = theme-ref("op", key)          // shorthand for the common case
  #let resolve-refs(style-dict, theme)           // replace every theme-ref value by
                                                 // theme.at(section).at(key)
  ```

  `resolve-refs` is applied to every node/edge style by the frame machinery
  right before the draw backend runs (single choke point: inside `make-canvas`,
  see 4.5). This is what lets `styles.attention("L")` react to the active theme
  even though the op was built earlier.

### 4.2 `core/snapshot.typ`

`blank-snapshot()`, `apply-snapshot(snap, ops)` (style/annotate ops only — panic
on commit/alt), and the internal merge used by apply-ops. Style dicts validated
against the allowlists on entry.

### 4.3 `core/ops.typ`

```typ
#let style-node(..args)  // positional args = keys; named args = the style. One op per key.
#let style-edge(..args)  // same shape
#let annotate(key, note)
#let set-alt(text)
#let set-caption(caption)          // added in Phase 3, see §3.3
#let set-step(step)                // added in Phase 3, see §3.3
#let commit(caption: none, step: none, alt: none)
#let apply-ops(renderer, ops)   // accepts nested arrays; flatten first
```

`style-node("L", "RR", fill: red)` → two ops. This variadic-keys shape is
exactly what every lecture helper hand-built (`disp_red(..paths)` etc.); it is
the load-bearing UX decision.

### 4.4 `core/theme.typ`

One nested dict, one state, one setter, one resolution rule.

```typ
#let default-theme = (
  render:   (…),   // values copied VERBATIM from default-render-theme (anim-core.typ)
  op:       (…),   // from default-op-theme (op-theme.typ) — note the real key is
                   // attention-stroke; `pivot-stroke` exists only in stale docs
  rbt:      (…),   // from default-rbt-theme (rbt.typ)
  trie:     (…), hashmap: (…), sort: (…), skiplist: (…),
  // git: DEFERRED TO PHASE 6 — see the note below.
)
#let _theme-state = state("starling-theme", (:))   // stores PARTIAL overrides only
#let set-theme(overrides)        // validates section names + keys, deep-merges one level
#let merge-theme(base, override) // per-section dict merge (two levels deep, no deeper)
#let resolve-theme(override)     // default-theme <- state <- override; NEEDS context
                                 // (only the slides.typ helpers call this)
```

> **Deferred (decided during Phase 1, mjs):** the `git:` section is NOT
> written in Phase 1. Its default values include the branch color palette and
> three decorator *functions* (`default-colors`, `color-boxed`,
> `_default-branch-pointer-decorator`, `_default-head-pointer-decorator`) that
> live in `git-graph.typ`, and `core/*` may not import `git-graph.typ`. **Phase 6
> must**: (a) move those four bindings into `core/theme.typ` (they are plain
> `box`/`text` content builders — no cetz needed), (b) add the `git:` section to
> `default-theme` with the values from `default-git-theme` verbatim, (c) delete
> `default-git-theme` / `set-git-theme` / `GitTheme` / `_git-theme-state` from
> `git-graph.typ`, and (d) point `git-graph`'s deferred `d.set-ctx` theme read at
> the one theme state. Until then `set-theme((git: …))` panics with an
> unknown-section error, which is correct — there is nothing to theme yet.

Rules:

- Display methods take `theme: (:)` — a partial nested dict. They never read
  state themselves; the override is captured in the frame builders and merged
  over the ambient theme the builder receives (see 4.5).

  ⚠️ **This is a behaviour change, confirmed in Phase 3.** A pre-1.0 per-call
  `theme:` *replaced* the palette — it merged the override onto the DEFAULTS
  and skipped `set-*-theme` state entirely (a deliberate escape hatch from the
  state-convergence cost). Under the rule above, a per-call override now layers
  on TOP of the state, so naming two keys changes those two and leaves the rest
  of the document's theme alone. It is the only intended ref change in Phase 3:
  `hashmap-theming`'s second panel now keeps the state's blue index labels and
  pink tombstone while overriding `empty-fill` and `hash-box-stroke`. The test
  was rewritten to assert that precedence rather than just exercise the
  argument.
- The `slides.typ` consumers (`last`, `figures`, `subslides`, …) open **one**
  `context`, read the **one** state once, and pass the resolved theme into every
  builder. Eight states collapse to one; the state-convergence 2× layout cost is
  paid at most once, and only if someone actually calls `set-theme`.
- `draw-*` backends take `theme: default-theme` as a plain default — they
  **never** read state, so hand-composed `cetz.canvas({ draw-tree(..) })` works
  without `context`. (This was the single biggest theming pain in the lectures.)

### 4.5 `core/frame.typ`

```typ
#let make-renderer(structure, draw, node-style: (:), edge-style: (:), sticky: false,
                   theme: (:))                       // -> Renderer dict
#let render(renderer)                                // -> array of Frame
#let make-frames(specs, draw, theme: (:), node-style: (:), edge-style: (:))
     // THE one frame builder. spec: (structure:, build: (theme) => snapshot,
     //                               caption:, step:, alt:, node-style: auto,
     //                               edge-style: auto, extra: ())
     // Every spec key except `structure` and `build` is optional and defaults as
     // shown (`caption: none`, `step: (:)`, `alt: ""`).
     // Replaces all 13 old _make-frames* variants.
#let make-canvas(structure, snapshot, node-style, edge-style, theme, draw, extra: ())
     // resolves theme-refs in the snapshot (style.resolve-refs), calls draw, appends
     // `extra` cetz commands INSIDE the same canvas (so el-* anchors are in scope), wraps
     // in cetz.canvas
#let overlay(frames, at: -1, draw: <cetz cmds | (theme) => cmds>)
     // returns frames with frame.at(i).extra += (draw,). `at` accepts negative indices.
#let result(frames)
     // frames.last().step.result, with a clear assert if absent
```

Builder closure created by `make-frames`, per spec:

```typ
(ambient) => {
  let th = merge-theme(ambient, theme)        // per-call override wins
  let snap = (spec.build)(th)
  make-canvas(spec.structure, snap, dns, des, th, draw, extra: frame-extra)
}
```

Perf rule preserved from the old code: all per-spec computation (event traces,
walks, the spec list itself) happens
**once, at display-call time, outside the builder closures**. The builder does
only merge + build-snapshot + draw. Do not move trace computation inside
builders.

### 4.6 `core/text.typ`

- `alt-label`, `alt-key-label` — moved from `tree-anim.typ:62,72` (they are
  string helpers, not drawing code; they were in the wrong module).
- `display-value(elem, value-key: "value")` — the "label if str, else
  str(value)" rule, currently reimplemented a fourth time as `sort.typ:_disp`.
  One copy now. The `value-key:` parameter is how the one copy serves both
  families: the trees pass the default, **sort and skiplist pass
  `value-key: "key"`** (their element dicts are `(key:, label:)`).
  `alt-label(node)` is the binary-tree case with the default applied.
- `alt-intro(ds-name, describe-text, action)` →
  `"<ds-name>: <describe>. About to <action>."` Every display's first-frame alt
  goes through this (fixes `hashmap.typ:1112` and `sort.typ:1022`, which
  silently drop the DS-name prefix today). Its sibling
  `alt-describe(ds-name, describe-text)` → `"<ds-name>: <describe>."` is the
  static-`display()` form (added in Phase 1; every `display()` uses it, so
  don't hand-build that string either).

### 4.7 `core/draw-util.typ`

- `stroke-paint(stroke)` (4 copies today), `haloed(draw, pos, body, theme,
  anchor: "center")` (3 copies), `text-fill-for(…)` (4 copies) — one copy each,
  byte-identical behavior. Note `haloed` takes the **full nested theme** and
  reads `theme.render.note-bg` itself; backends pass their `theme` straight
  through.
- `resolve-dims(cells, body-fn, cell-width, floor-w:, floor-h:, pad-x:, pad-y:,
  measure-cells:)` → `(w, h)` — ONE implementation serving hashmap/array/skiplist
  "fit" sizing, parameterized on the body-builder and floor constants,
  **always** accepting a `measure-cells` superset. Each backend renames `(w, h)`
  to its own field names (`cw/ch`, `bw/bh`) and derives its extras (the array's
  `row-gap`, the skiplist's pitches) itself. The hash map has **two** box
  families with different floors: call `resolve-dims` for the array cells, and
  the companion `measure-max(cells, body-fn, measure-cells:)` for the chain
  entries, whose `ehw`/`ehh` are *half*-extents (`max(_EHW, w / 2 + PAD-X)`) —
  padding is applied after halving, so they cannot go through `resolve-dims`
  directly. `PAD-X`/`PAD-Y` (0.22 / 0.15, identical in all three backends
  today) are the shared defaults. This closes the hashmap gap (§1). The
  `hashmap-frame-stability` test is the acceptance check; if hashmap cell sizes
  legitimately change, that test's refs (and other `hashmap-*` refs) may change
  — inspect diffs, confirm the new sizing is *correct* (stable across an
  animation's frames), then `just update`.

  **Split across Phases 2 and 3** (decided in Phase 2). `draw/hashmap.typ` now
  sizes through `resolve-dims` + `measure-max` and *accepts* a `measure-cells`
  key on the table dict, defaulting to `()` — so Phase 2 changed no refs at all.
  Phase 3's `ds/hashmap.typ` supplies the superset, and that is when the sizing
  (and possibly the refs) actually moves. One thing to carry over: the hash map's
  two box families are never populated at once — open addressing labels the array
  cells and has no chain entries, chaining labels the entries and leaves the array
  cells as keyless bucket headers — so the backend routes `measure-cells` to
  whichever family the strategy actually uses. Feeding it to both would inflate
  chaining's array pitch to the entry labels' width for no reason.

  ✅ **Landed in Phase 3, with no ref change after all.** `ds/hashmap.typ` now
  computes the superset and `draw/hashmap.typ` consumes it. None of the
  `hashmap-*` refs moved: every one either shows a single static table (where
  the superset is the table itself) or uses numeric labels, which measure below
  the `_CW` / `_EHW` floors, so the fit never engaged. The gap was real all the
  same — inserting a wide label into a table of short ones took the canvas from
  198.43pt to 481.08pt on the final frame before, and holds 481.08pt throughout
  now.
- `anchor(key, canvas: none)` — the ONE anchor sanitizer (§6.2).

---

## 5. The Step Vocabulary

Canonical `step.kind` values, enforced during each DS port:

- **Universal:** `static` (every single-frame `display()`), `init`, `settled`
  (terminal success of a mutation), `found` / `not-found` (lookup outcomes).
- **Renames** (pure synonyms → canonical): `settle` → `settled` (bst, avl);
  graph algorithm terminal `done` → `settled`; trie `miss` → `not-found`;
  hashmap's four miss kinds (`not-found`/`absent`/`empty`/`exhausted`) →
  `not-found` with the detail preserved as
  `step.reason: "empty" | "exhausted" | "chain-end"`.

  Three more settled in Phase 3, all "pure synonym" cases the list above did
  not spell out. BST's search terminal was `compare` with a `found:` flag; it
  is now `found` / `not-found`, matching the universal vocabulary (the flag
  stays). The hash map's open-addressing insert-onto-an-existing-key was
  `insert` with `updated: true` while chaining already called it `update`; both
  are `update` now. And the resize terminal `done` is `settled`, for the same
  reason the graph terminals are — it is the terminal success of a mutation.
- **DS-specific kinds stay** where the semantics genuinely differ (`descend`,
  `probe`, `advance`, `visit`, `compare`, `split-done`, `splice`, `rehash`, …) —
  list each module's set in a comment block at the top of the module.
- Row/column/aux-view kinds (`"buckets"`, `"count"`, `"header"`, `"dist-map"`,
  …) are a different namespace from step kinds; they stay on table/view dicts
  and must never appear as a `step.kind`.
- **Every** display's final frame `step` carries
  `result: <the post-operation structure>` (for searches/traversals: the
  unchanged input). This feeds `result(frames)` and kills the write-it-twice
  pattern (28 lecture sites).

Captions are always content (fix sort's 13 string captions and trie's 2). Alt is
always an explicitly-set str (never derived from caption — delete the old
`_resolve-alt` str-caption fallback; it behaved differently per DS).

---

## 6. Draw Backends (`draw/*.typ`)

### 6.1 Porting Rule

The drawing logic moves **verbatim** — geometry, colors, occlusion order, halos,
B24 key-styles merging, the skiplist layering story, everything. The only
changes per backend:

1. Signature:
   `draw-X(structure, snapshot, node-style: (:), edge-style: (:), theme: default-theme, name: none)`.
   - `theme` is the full nested dict; the backend reads `theme.render` plus its
     DS section (e.g. `draw-hashmap` reads `theme.hashmap`). The old "merge the
     palette into render-theme before calling" dance (`_combined-render-theme`)
     is deleted.
   - `name:` wraps the whole output in a named cetz `group` —
     **including `draw-graph`, which lacks it today** (lecture 13 has a
     commented-out attempt at it).
2. Anchors: emitted through the shared sanitizer (§6.2).
3. The `ghost` node-style key (§6.3).
4. All shared helpers come from `core/draw-util.typ`.

### 6.2 One Anchor Scheme

`core/draw-util.typ`:

```typ
#let anchor(key, canvas: none) = {
  // 1. B24 compartment suffix: "01#1" -> base key "01", sub ".key-1"
  // 2. base = "el-" + key with every char outside [a-zA-Z0-9_-] replaced by "-"
  //    special case: key == "" (tree root) -> "el-root"
  // 3. prepend canvas + "." when canvas != none
}
```

Examples: tree `"LR"` → `"el-LR"`, root → `"el-root"`, graph node `"A"` →
`"el-A"`, edge `"u->v"` → `"el-u--v"`, hashmap `"c3:1"` → `"el-c3-1"`, array
`"count:5"` → `"el-count-5"`, skiplist `"b2:0"` → `"el-b2-0"`, b24 `"01#1"` →
`"el-01.key-1"`.

Backends create their cetz elements under these names. The old per-backend
helpers (`path-anchor`, `node-anchor`, `cell-anchor`, `entry-anchor`,
`array-cell-anchor`, `array-entry-anchor`, `sl-box-anchor`, `sl-forward-anchor`,
`sl-data-anchor`) are deleted; each DS module re-exports `anchor` plus its
**key constructors** under short names (§7.2). `array-arrow-key` (an exported
identity function) is deleted with no replacement — arrow ids are already the
keys.

✅ **Done in Phase 2.** One wrinkle worth knowing before touching `draw/tree.typ`
again: cetz-tree names each node's group *positionally* ("0", "0-1", …), because
it lays the tree out long before it knows our paths, and there is no hook to
change that. `draw/tree.typ` therefore draws the tree inside a private group and
then republishes each node group's anchors under its `el-<path>` name, with a
local `_alias-anchors` element built the same way cetz's own
`draw.copy-anchors` is (insert into `ctx.nodes` an entry whose `anchors` closure
delegates to the source element's). It is the one place in starling that reaches
into a cetz context; it is pinned to cetz 0.5.2 along with the rest of the
drawing code, and it preserves point *and* compass sub-anchor resolution
(`anchor("LR") + ".north"`), qualified or not. The other four backends name
their elements directly and need none of this.

`draw-graph` now names its **edges** too (it named only nodes before), so
`anchor(edge-key(u, v))` resolves — the missing half of §6.2's edge examples.

✅ **Verified in Phase 1** (was: "verify early in Phase 2"). The `core-ops`
test's rendered page draws a callout between two sanitized names, one of them
via a compass sub-anchor (`anchor("a")` → `"el-a"`, `anchor("c->d") + ".north"`
→ `"el-c--d.north"`). cetz accepts the names and resolves the sub-anchor, so
the sanitizer needs no adjustment. Since only names change (not positions),
all existing refs must stay pixel-identical — anchor renames are invisible to
the renderer; only tests that *reference* anchors need their source updated.

### 6.3 `ghost: true` (New Node-Style Key, All Backends)

"Invisible but space-reserving": the element contributes its exact normal
footprint to layout/bounds and emits its anchors, but draws no fill, stroke, or
label.

- tree: cetz-tree still lays out the node (same extents); nothing painted. This
  replaces the lecture hack of `fill: none, stroke: none` on nodes +
  `hide: true` on edges for progressive reveals.
- graph/hashmap/array/skiplist: same idea; hashmap/skiplist already have
  internal ghost/state mechanisms (`hash-box.ghost`, skiplist column
  `state: "ghost"`) — those stay as-is internally, but the *snapshot-level*
  `ghost` key must also work so users can ghost any element from the Op stream.
- Edges: `hide: true` already exists and is the edge-side story;
  `styles.ghost(..keys)` (§8) emits node-ghost + edge-hide for the same keys.

✅ **Done in Phase 2**, uniformly: every backend draws the element normally and
wraps the result in `draw.hide(.., bounds: true)`. cetz's `hidden` tag skips
painting but still contributes bounds (only its `no-bounds` tag suppresses
them), so the footprint is exact by construction rather than by re-deriving each
backend's geometry, and the element's `name:` still registers — ghosted elements
keep their anchors. A tree node's ghost also survives cetz-tree's
measure-the-node pass, so the *layout* is unchanged too: measured on a 3-node
tree, ghosting a whole subtree left the canvas at 255.12pt against 255.12pt
undisturbed and 153.07pt with the subtree genuinely absent.

### 6.4 Draw Modules Also Export

`make-X-renderer` wrappers die. Instead each **ds** module exports
`renderer(structure, …)` (§7.2) and the generic
`make-renderer(structure, draw, …)` in core covers custom backends — which
becomes a *documented public extension point* (it never was reachable before).

---

## 7. DS Modules (`ds/*.typ`)

### 7.1 the Uniform Contract

Every DS module exports (names exact; a conformance test enforces this — §11.3):

```text
new(..)                       construction from values (today's factory semantics)
insert / delete / contains / describe / check-invariants     (+ DS-specific pure ops)
display(structure, ..)                          -> array(Frame)
<op>-display / <algorithm>-display(structure, ..)  -> array(Frame)
renderer(structure, node-style: (:), edge-style: (:), sticky: false, theme: (:))
                              -> Renderer, pre-painted with the DS's structural styling
anchor                        re-export of draw-util.anchor
key helpers                   short names, per backend (§7.2)
style vocabulary              DS-specific op-array helpers (§8)
```

Signature rules, uniform across all modules:

- Structure is always the **first positional** argument:
  `bst.insert(t, 5, label: auto)`.
- Every display takes `theme: (:)` (partial nested override) as its **only**
  theme argument. The old `render-theme:` parameter is gone (it's
  `theme: (render: (…))` now).
- `node-style:` / `edge-style:` (never `default-node-style:`).
- `insert-display` takes `label: auto` wherever `insert` does (fixes BST/RBT/AVL
  which today lack it). `delete-display` takes `search: true|false` wherever a
  search phase makes sense (BST/RBT/AVL have it today; add to
  B24/Trie/HashMap/Skiplist for uniformity, default matching current behavior).
- DS-specific flags keep their current names where semantics differ: `bits:`
  (rbt), `factors:`/`heights:` (avl), `strategy:` (b24, hashmap),
  `variant:`/`separate-counts:` (sort), `tombstone:`/`rehash:` (hashmap),
  graph's `positions:`/`scale:`/`layout:`/
  `layout-unit:`/`node-style:`/`target:`/`sort-frontier:`/`spanning-tree:`/
  `node-distances:`/`reconstruct:`.

`renderer()` absorbs the painters: `rbt.renderer(t, bits: false)` does what
`paint-rbt(make-renderer(t), t, bits: …)` did; `trie.renderer(t)` absorbs
`paint-trie`. The `paint-*` functions become module-private `_paint`.

### 7.2 per-Module Specifics

**`ds/tree-common.typ`** (used by bst/rbt/avl; b24 and trie keep their own n-ary
path utilities): value/label tuple parsing (the 4× duplicated factory `parse`),
`by-value`, `path-to`, `resolve`, `resolve-at`, `insert-many` (a fold), the four
traversal walks, a parameterized `describe`, and
`render-traversal(structure, order, alt-prefix, node-tag-fn, …)` (merging the 3
copies; the `factors:`/`heights:` hooks become the `node-tag-fn`/edge-tag
parameters).

**bst / rbt / avl / b24 / trie** — literal builders (this ships what lectures
hand-rolled three times):

```typ
bst.node(v, ..children, label: auto)    // children sink: () = leaf, or (left, right);
bst.leaf(v, label: auto)                //   none is a valid child
rbt.red(v, ..children, label: auto)     // rbt.black(...) likewise
avl.node(v, ..children, label: auto)    // height COMPUTED from children — never a parameter
b24.node(keys, ..children, labels: auto)  // keys: int or array of ints; parses like new()
b24.leaf(..keys)
```

- `rbt` finally gets the displays it's missing: `search-display` and the four
  `*-order-display`s come nearly free from tree-common + `_paint`. (The stale
  "will land in a follow-up stage" comment dies.) `fixup-display` stays.
- `bst` gains `check-invariants` (the only DS missing it).
- Path alphabets, `PathId` semantics, and the `#<int>` compartment suffix are
  unchanged.

**graph** — algorithm displays rename: `mst-prim-display` → `prim-display`,
`mst-kruskal-display` → `kruskal-display` (bfs/dfs/dijkstra keep their names).
The aux-machinery (`aux-strip`, `_status-box`, `_aux-pq-content`,
`_aux-map-content`, `_edge-body-vertical`, `aux-view-title`) moves to
`src/aux.typ` (§7.3). ALL graph displays emit the `aux-views` list form — the
single-`aux`/`aux-kind` contract is deleted (BFS/DFS emit a one-element list).
`adjacency-matrix`/`adjacency-list` stay in ds/graph (they're graph-specific),
now reading the unified theme. `positioned`, `auto-layout` handshake, and the
lazy-layout rules are unchanged.

**hashmap** — `hash`/`hash2` become bare function fields. The `positioned()`
table dict gains `measure-cells` (computed exactly like sort/skiplist do) and
`draw/hashmap.typ` consumes it through the unified `resolve-dims`.

**sort** — display renames: `counting-sort-display` → `counting-display`,
`radix-sort-display` → `radix-display`; pure ops `counting-sort` → `counting`,
`radix-sort` → `radix`. String captions become content.

**skiplist** — key helpers export as `box-key(col, level)`,
`forward-key(col, level)`, `data-key(col)` (the `sl-` prefixes die; the
namespace disambiguates).

Key-helper short names per module: `graph.edge-key(u, v, directed:)`;
`hashmap.cell-key(i)`, `hashmap.entry-key(i, j)`; `sort.cell-key(row, col)`,
`sort.entry-key(row, i, j)` (re-exported from draw/array); skiplist as above.
Tree modules need no key constructors (paths are the keys).

### 7.3 `aux.typ`

`aux-strip(step, view: auto, labels: (:), title: auto, theme: (:))` — one
`context`, resolves the one theme state, renders `step.aux-views`.
`aux-view-title(kind)` moves here. Contract: `aux-views` only. Adding aux views
for hashmap/sort/skiplist is **out of scope** for 1.0 (future work), but the
module boundary now permits it.

---

## 8. `styles.typ` — the Semantic Style Vocabulary

Generic helpers, each variadic over keys, each returning an op array (composable
with `+`), each using `theme-ref` so they follow the active theme. Derived from
the exact helpers the lectures kept rewriting (`04-rbt-deletion.typ:28-230` is
the reference implementation to match):

```typ
#let attention(..keys)   // node stroke: role("attention-stroke")
#let search(..keys)      // node stroke: role("search-stroke")
#let success(..keys)     // fill: role("success-fill"), stroke: role("settled-stroke")
#let danger(..keys)      // node stroke: role("danger-stroke")
#let subtree(..keys)     // shape: "triangle", child-anchor: "north"  (elided-subtree idiom)
                         //   + tag: none and a gray fill/stroke from the new render-theme
                         //   keys `elided-fill`/`elided-stroke`, so an elided subtree does
                         //   not read as a real node (matches the lecture helper, but
                         //   themeable). [decided during Phase 1, mjs]
#let nullify(..keys)     // materialize: true, label: ∅  (null-sentinel idiom)
#let ghost(..keys)       // node ghost: true  +  edge hide: true, same keys
#let hidden(..keys)      // node hide: true   +  edge hide: true
#let revealed(..keys)    // node ghost/hide: false + edge hide: false (undo the two above)
#let force-show(..keys)  // edge force-show: true
```

DS-specific vocabulary lives in the DS module: `rbt.red(..keys)` /
`rbt.black(..keys)` (fill/stroke/text from `theme-ref("rbt", …)`, tag [0]/[1]
matching the lecture `disp_red`/ `disp_black`), `rbt.double-black(..keys)` (tag
[2] + edge mark "o", per the lecture helper), `avl.unbalanced(..keys)`.

Names deliberately avoid colliding with Typst/cetz builtins (`hidden` not `hide`
— the lecture helper named `hide` shadowed both `std.hide` and
`cetz.draw.hide`).

---

## 9. `git-graph.typ`

- Stays one file, re-exported as `#import "git-graph.typ" as git` in lib.typ.
- Rename every internal top-level binding to `_`-prefixed: the cetz-draw alias
  (`d` → `_d`), `offset`, `default-colors`, `color-boxed`, `graph-props`,
  `set-graph-props`, `branch-props`, and friends. Public surface after the
  rename: `git-graph`, `commit`, `branch`, `merge`, `tag`, `checkout`,
  `branch-pointer`, `head-pointer`, `detached-commit`, `git-highlight`,
  `background-lanes`.
- Theme: the git palette becomes the `git:` section of `default-theme` — which
  Phase 1 deliberately left out, so **this phase adds it**, moving
  `default-colors` / `color-boxed` / the two pointer decorators into
  `core/theme.typ` first (see the deferral note in §4.4);
  `set-git-theme` and its private state die. `git-graph(theme: auto)` reads the
  ONE theme state inside its deferred `d.set-ctx` closure (same mechanism as
  today — cetz supplies context there); `theme: (…)` per-call bypasses state
  exactly as today via the merge helper.
- Behavior/layout config (`direction`, `commit-spacing`, `lane-spacing`) and
  runtime state stay where they are (not theme). No drawing changes; the
  `git-graph` test's 4 panels must stay pixel-identical.
- FYI, not a task: lecture 07 uses a *pre-theme fork* of this file from
  `07-assets/`; the package version is strictly newer. Nothing to port from the
  fork — confirm with a quick diff if in doubt.

---

## 10. `lib.typ` and `slides.typ`

### 10.1 Lib.typ — the Complete Export List

Namespaced modules (via `#import "ds/bst.typ" as bst` etc. — same mechanism
`git` uses today): `bst`, `rbt`, `avl`, `b24`, `trie`, `graph`, `hashmap`,
`sort`, `skiplist`, `git`, `styles`, `aux`.

Flat (the convenience layer lectures actually destructure):

```text
blank-snapshot, style-node, style-edge, annotate, set-alt, set-caption,
set-step, commit, apply-ops,
apply-snapshot, make-renderer, render, overlay, result, theme-ref, role,
last, stacked, figures, subslides, canvas,
default-theme, set-theme,
draw-tree, draw-graph, draw-hashmap, draw-array, draw-skiplist, anchor,
auto-layout, aux-strip
```

Nothing else. No bare module re-exports (the old `#import "./tree-anim.typ"`
line dies), no private states, no typsy type names, no `concat-frames` (dead),
no `GraphNodeId` (dead), no `TreeRenderer` alias. Every export appears in
lib.typ explicitly with a doc comment.

### 10.2 Slides.typ

```typ
#let last(frames, caption: false, spacing: 0.5em, alt: auto)
     // ACCEPTS a single Frame OR an array (kills the 1-tuple re-wrap idiom)
#let stacked(frames, caption: true, spacing: 1em, caption-spacing: 0.5em, alt: auto)
#let figures(frames, caption: true, caption-spacing: 0.5em, alt: auto)  // -> array
#let canvas(frame, theme: (:))
     // one frame's bare canvas, alt-LESS by design; documented as "for hand layout;
     //  you own accessibility". Replaces canvases-only (which is deleted).
#let subslides(frames,
  caption: true,
  aux: none,            // none | "right" | "left" | "below"
  aux-view: auto,       // forwarded to aux-strip's view:
  aux-size: 0.8em,      // text size for the strip
  fit: none,            // none | ratio | (width, height)
  alt: auto,
) // -> array of composed content, ready for touying's alternatives(..)
```

`subslides` semantics:

- Per frame: canvas + (aux-strip of `frame.step` if `aux != none`) + caption,
  arranged in a grid (`(1fr, auto)` columns for left/right, a `stack` for
  below), horizon-aligned.
- **Alt-preserving:** the entire composition is wrapped in the alt figure (this
  fixes the `ua-1` accessibility hole that `canvases-only` + manual captions
  created).
- `fit:` — a ratio is a plain `scale(x: r, y: r, reflow: true)`; a
  `(width, height)` pair measures every frame's composition (one `context`),
  takes the max dimensions across ALL frames, and applies ONE common scale
  factor so subslides don't wobble frame-to-frame.
- Still zero touying dependency: it returns an array; the user splats it into
  `alternatives(..)`. Benchmark the defaults against the lecture 13/14
  graph-algorithm slides (the 10× grid sandwich this replaces) — they needed
  `column-gutter: -8em` and 0.7em fonts to fit, which good defaults here should
  make unnecessary.

All helpers open one `context`, resolve the one theme state once via
`resolve-theme`, and pass the result into each frame's builder.

---

## 11. Old → New Mapping (For Migrating Tests And, Later, the Manual)

### 11.1 API

| Old | New |
| --- | --- |
| `bst(16, 11, 29)` / `(BST.new)(value: …)` | `bst.new(16, 11, 29)` / `bst.node(…)` / `bst.leaf(…)` |
| `(t.insert)(5)` | `bst.insert(t, 5)` |
| `(t.insert-display)(5)` | `bst.insert-display(t, 5)` |
| `(t.insert-display)(5)` then `(t.insert)(5)` | `let f = bst.insert-display(t, 5); t = result(f)` |
| `(Op.StyleNode.new)(path: p, style: (fill: red))` | `style-node(p, fill: red)` |
| `(Op.Commit.new)(alt: a)` | `commit(alt: a)` |
| `(Op.Highlight.new)(path: p, color: c)` | `style-node(p, stroke: c + 2pt)` |
| `(Op.ClearNotes.new)()` | `snapshot.clear-notes(snap)` — internal only, no op, not exported |
| `starling.make-renderer(t)` (tree-bound; sticky by default) | `bst.renderer(t, sticky: true)` (etc. per DS) — `sticky` now defaults to `false`, see §3.5 |
| `starling.make-renderer(structure, draw: …)` (generic, was unreachable) | `make-renderer(structure, draw, …)` |
| `(r.render)()` | `render(r)` |
| `paint-rbt(make-renderer(t), t, bits: true, theme: …)` | `rbt.renderer(t, bits: true)` |
| `paint-trie(r, t, theme: …)` | `trie.renderer(t)` |
| `theme:` = op-theme (bst/avl/b24/graph) | `theme: (op: (…))` |
| `theme:` = palette (rbt/trie/hashmap/sort/skiplist) | `theme: (rbt: (…))` etc. |
| `render-theme: (…)` | `theme: (render: (…))` |
| `set-op-theme(…)` / `set-render-theme(…)` / `set-rbt-theme(…)` / … | `set-theme((op: …, render: …, rbt: …))` |
| `default-op-theme.attention-stroke` | `default-theme.op.attention-stroke` |
| `path-anchor(p, tree-name: "t")` | `anchor(p, canvas: "t")` |
| `node-anchor(id)` / `cell-anchor(i)` / `array-cell-anchor(r,c)` / `sl-box-anchor(c,l)` | `anchor(<the key>)` — via the module's key constructor |
| `cell-key(i)` / `entry-key(i,j)` | `hashmap.cell-key(i)` / `hashmap.entry-key(i,j)` |
| `array-cell-key(row,col)` / `array-entry-key(…)` | `sort.cell-key(…)` / `sort.entry-key(…)` |
| `array-arrow-key(id)` | (deleted — the id *is* the key) |
| `sl-box-key` / `sl-forward-key` / `sl-data-key` | `skiplist.box-key` / `.forward-key` / `.data-key` |
| `mst-prim-display` / `mst-kruskal-display` | `graph.prim-display` / `graph.kruskal-display` |
| `counting-sort-display` / `radix-sort-display` | `sort.counting-display` / `sort.radix-display` |
| `canvases-only(frames)` | `frames.map(f => canvas(f))` — or better, `subslides` |
| `concat-frames`, `GraphNodeId`, `TreeRenderer`, `Op.Highlight`, `Op.ClearNotes` | deleted |
| `(m.positioned)()` + `make-hashmap-renderer(tbl)` | `hashmap.positioned(m)` + `make-renderer(tbl, draw-hashmap)` |

### 11.2 Files

| Old | New |
| --- | --- |
| `anim-core.typ` | `core/{style,snapshot,ops,theme,frame}.typ` |
| `op-theme.typ` | `core/theme.typ` (the `op:` section) |
| `tree-anim.typ` | `draw/tree.typ` (+ `core/text.typ` for `_alt-label`/`_alt-key-label`) |
| `graph-draw.typ` / `hashmap-draw.typ` / `array-draw.typ` / `skiplist-draw.typ` | `draw/{graph,hashmap,array,skiplist}.typ` |
| `bst.typ` … `skiplist.typ` | `ds/*.typ` (+ `ds/tree-common.typ`) |
| `aux-strip` & helpers inside `graph.typ` | `aux.typ` |
| `last`/`stacked`/`figures`/`canvases-only` inside `lib.typ` | `slides.typ` |

### 11.3 the Conformance Test

New assertion-style test `tests/api-conformance/` (created with
`tt new api-conformance`). Typst can turn a module into a dict:
`#import "/src/ds/bst.typ"; #let m = dictionary(bst)`. Assert, for every DS
module: presence of `new`, `insert` (where applicable — graph has
`add-node`/`add-edge` instead; encode the per-DS expected verb list explicitly),
`display`, `renderer`, `describe`, `check-invariants`, `anchor`; that every
`*-display` name in the module ends in `-display`; and that `lib.typ`'s dict
contains exactly the §10.1 export list (no more, no less — this is the tripwire
against accidental exports).

---

## 12. Phases

### Phase 0 — Setup (Small) — ✅ DONE (commit `Phase 0: prefix the BST-era test directories`)

1. Branch `refactor/v1`.
2. Rename the 15 BST-era unprefixed test dirs (`insert`→`bst-insert`,
   `search`→`bst-search`, `rotate`→`bst-rotate`, `static`→`bst-static`,
   `themed`→`bst-themed`, `traversals`→`bst-traversals`,
   `delete-leaf`→`bst-delete-leaf`,
   `delete-leaf-search`→`bst-delete-leaf-search`,
   `delete-twokids`→`bst-delete-twokids`,
   `delete-twokids-search`→`bst-delete-twokids-search`,
   `display-custom`→`bst-display-custom`,
   `triangle-subtree`→`bst-triangle-subtree`, `cetz-anchors`→`bst-cetz-anchors`,
   `op-stream`→`bst-op-stream`, `show-rule-isolation`→`bst-show-rule-isolation`)
   with `git mv`; refs move with the directories.
3. `just test` — everything green, zero ref changes.

**Done when:** suite green on the branch; one commit.

### Phase 1 — the Core (New Code Only; Nothing Existing Changes) — ✅ DONE (commit `Phase 1: the animation core, on plain dicts`)

Decisions made while implementing it are folded into §§3-4, 6.2, 8, 11.1 and
14 above, each marked "Phase 1". The load-bearing ones for later phases:
`Frame.make` (§3.4), `sticky: false` (§3.5), the `Op.Highlight`/`ClearNotes`
resolution (§3.3), `display-value`'s `value-key:` (§4.6), the
`resolve-dims` / `measure-max` split (§4.7), and the deferred `git:` theme
section (§4.4 → Phase 6).

1. Write `core/style.typ`, `core/snapshot.typ`, `core/ops.typ`,
   `core/theme.typ`, `core/frame.typ`, `core/text.typ`, `core/draw-util.typ`,
   and `styles.typ` per §§3-4, 8. Port logic from `anim-core.typ`/`op-theme.typ`
   (apply-ops fold, style merging, canvas assembly) — translate typsy classes to
   plain dicts, delete the `(fn:)` wrappers, keep semantics identical. Copy
   theme default *values* verbatim from the old files.
2. New assertion test `core-ops` (`tt new core-ops`): exercises blank-snapshot,
   op constructors, apply-ops (incl. sticky + commit), apply-snapshot, theme
   merge/resolve precedence (default < state < per-call), theme-ref resolution,
   `make-frames` with a stub draw function, `overlay`, `result`.
3. Old code untouched; old tests untouched.

**Done when:** `just test` green (old suite + core-ops). No old file modified.

### Phase 2 — Draw Backends — ✅ DONE (commit `Phase 2: the five draw backends`)

Decisions made while implementing it are folded into §§3.5, 4.7, 6.2 and 6.3
above, each marked "Phase 2". The load-bearing ones for later phases: the
backend calling convention (§3.5 — two positionals, three named), the tree's
`_alias-anchors` workaround for cetz-tree's positional group names (§6.2), the
uniform `draw.hide(.., bounds: true)` implementation of `ghost` (§6.3), and the
hashmap `measure-cells` split that defers the only intended ref change to
Phase 3 (§4.7).

Each backend was checked against its predecessor by rendering the same
structures through both and comparing PNG hashes — 29 configurations across the
five, all byte-identical (trees: binary, force-show phantoms, B24, trie,
grow/spread; graphs: directed and undirected, self-loops, bends, label-offsets,
autosize, every node shape; hash maps: both orientations x chaining and open
addressing, tombstones, phantom cell, real/ghost/double hash boxes, all three
sizing modes; arrays: data/count/buckets rows, arrows, chains, all sizing modes;
skip lists: ghost columns, both link-range forms, all sizing modes). That is
what "verbatim drawing logic" was held to, and it is the cheapest way to keep
Phases 3-5 honest as the DS modules move over — do the same when porting them.

1. Port the five backends to `draw/` per §6 (verbatim drawing logic; new
   signature; `name:`; shared draw-util helpers; `el-` anchors; `ghost` key).
   `draw/tree.typ` takes only the drawing half of `tree-anim.typ` (`draw-tree`,
   the three cetz-tree builders, edge/anchor resolution, key-styles merging);
   the alt-string helpers go to `core/text.typ`.
2. Old backend files stay in place, still serving the old DS classes. Temporary
   duplication is expected and fine.
3. New visual test per backend (`tt new draw-<x>-smoke`, 5 tests): each draws a
   small structure via `make-renderer(structure, draw-X)` + a few ops through
   the new core, including one `ghost` element, one `name:` + `anchor()`
   callout, and one theme-ref style. These get NEW refs (that's what
   `just update draw-…` is for — they're new tests).
4. ~~Verify the anchor sanitizer against cetz early (§6.2 warning).~~ Done in
   Phase 1 — see §6.2.

**Done when:** suite green; 5 new smoke tests with refs; no old test's ref
changed.

### Phase 3 — Pilot: Bst + Hashmap (One Tree DS, One Table DS) — ✅ DONE (commit `Phase 3: BST and the hash map, on the new core`)

Decisions made while implementing it are folded into §§3.3, 4.4, 4.7, 5 and
10.1 above, each marked "Phase 3". The load-bearing ones for Phase 4: the two
new trailing-frame ops (§3.3), the per-call-over-state theme precedence (§4.4),
and the shared-closure snapshot pattern described below.

**The port was validated frame by frame, not just by refs.** Old and new were
rendered side by side and compared by PNG hash: 121 BST frames across 20
display calls (static, search hit and miss, insert, all three delete branches
with and without `search:`, three rotations, four traversals, both theme
override forms) and 115 hash-map frames across 25 (four strategies, both
orientations, hit/miss/phantom, tombstone and naive delete, correct and naive
resize, all three `cell-width` modes, theming). All byte-identical. Do the same
for each module in Phases 4-5 — it catches an accumulation off-by-one that a
whole-suite ref check would let through if no test happens to cover it.

**Keep the shared-closure pattern when porting an accumulating animation.** The
pre-1.0 code built a phase's snapshots in ONE closure and let every frame index
into the result, so Typst's call cache made an n-frame animation cost one
accumulation pass. `make-frames` takes a per-spec `build`, which invites
rebuilding from scratch per frame — O(n²). Write `let build-all = th => {..}`
once per phase and give each spec `build: th => build-all(th).at(i)`, exactly as
`ds/bst.typ` and `ds/tree-common.typ` do. Note also that a Typst closure cannot
mutate a captured variable, so the accumulation must be written as straight-line
`cur = ..; out.push(cur)` inside the closure body, not via a helper.

**Watch for `import cetz.draw: *`.** Now that the sanitizer is called `anchor`,
a glob import of cetz's draw module shadows it — cetz has its own `anchor(name,
position)`. Import selectively in tests and examples, and say so in the manual
(Phase 8).

1. Write `ds/tree-common.typ` and `ds/bst.typ` per §7. Port algorithms from
   `bst.typ` verbatim (the traces/specs logic is fine; only the class
   scaffolding, frame plumbing, and theme handling change). Add
   `check-invariants`, literal builders, `step.result` stamping, `label:` on
   insert-display.
2. Write `ds/hashmap.typ` + the `measure-cells` unification (§7.2). This is the
   one place refs may legitimately change — see §4.7; inspect before updating.
3. lib.typ: remove the old BST/HashMap exports; add `bst`, `hashmap`, `styles`
   namespaces and the flat core/slides names they need. Other DSs keep their old
   exports for now.
4. Write `slides.typ` with `last`/`stacked`/`figures`/`canvas` (subslides can
   wait for Phase 6) — the old lib.typ helpers keep serving the unmigrated DSs
   until Phase 6; the new ones serve migrated DSs. Name-collide? No: old helpers
   live in old lib.typ code paths — simplest is to have lib.typ's `last` etc.
   come from `slides.typ` and make slides.typ accept BOTH old typsy Frames and
   new dict Frames during the transition
   (`if type(f) == dictionary and "builder" in f { … } else { (f.render)(…) }`).
   Delete the compat arm in Phase 7.
5. Migrate all `bst-*` and `hashmap-*` tests (incl. `bst-ops`, `hashmap-ops`) to
   the new API using the §11.1 table. **Refs must be pixel-identical** except
   the hashmap sizing tests if §4.7 bites.
6. Add `api-conformance` (§11.3) covering the migrated modules; extend it each
   phase.
7. **Checkpoint: measure the per-DS scaffolding.** Count the non-algorithm lines
   in `ds/hashmap.typ` (theme plumbing + frame plumbing + exports). Target:
   under ~60 (was ~360). If it's much higher, fix the core before migrating
   seven more modules.

**Checkpoint result: 33 lines, of which 18 are a new capability.** Counting
non-blank non-comment lines of pure framework glue — the code that exists only
to plug the structure into the animation machinery — `hashmap.typ` had 118
(70 of theme scaffolding, 22 of `_rebuild`/`_rebuild-cap`, 26 of
`_hm-make-frames-multi` + `_styled`) and `ds/hashmap.typ` has 33: a 12-line
`make-frames` call, the 18-line `measure-cells` superset the old code did not
have at all, and 3 lines of signature and `_styled`. The theme block and the
structure-rebuild helpers are gone outright — one is the unified theme, the
other is `(..hm, slots: slots)`. The core is carrying its weight; proceed.

(Two caveats on the raw file size, which fell only 1270 → 1122. First, the new
file carries much fuller doc comments. Second, a naive count of everything
outside the algorithms — including `_table`, `_hash-box`, `positioned`,
`renderer`, and the five display signatures — comes to 144, but those are
DS-specific data shaping and public API, not framework tax, and they have no
pre-1.0 equivalent to shrink against.)

**Done when:** suite green; bst/hashmap tests pass on the new API; conformance
test passes; scaffolding measured and acceptable.
### Phase 4 — Remaining Trees: Rbt, Avl, B24, Trie

Per module, in this order (each is one commit): port to `ds/`, wire tree-common
(rbt/avl), literal builders, style vocabulary
(`rbt.red`/`rbt.black`/`rbt.double-black`, `avl.unbalanced`), step-kind renames
(§5), `result` stamping, lib.typ export swap, migrate that DS's tests. RBT
additionally gains `search-display` + the four `*-order-display`s via
tree-common (new tests: `tt new rbt-search`, `tt new rbt-traversals` — new
refs).

**Done when:** suite green after each module; all five tree DSs on the new API;
old `bst.typ`/`rbt.typ`/`avl.typ`/`b24.typ`/`trie.typ`/`tree-anim.typ` deleted
(nothing imports them — verify with grep before deleting).

### Phase 5 — Graph, Aux, Sort, Skiplist

1. `aux.typ` extracted; `ds/graph.typ` ported (aux-views-only contract, display
   renames, step-kind renames); migrate `graph-*` tests.
2. `ds/sort.typ` (renames, content captions) and `ds/skiplist.typ` (short key
   names); migrate their tests.
3. Delete `anim-core.typ`, `op-theme.typ`, `graph-draw.typ`, `hashmap-draw.typ`,
   `array-draw.typ`, `skiplist-draw.typ` (grep first).

**Done when:** suite green; `src/` contains only the target tree (§2) plus
`lib.typ`; `grep -r "typsy" src/` returns nothing.

### Phase 6 — Presentation Layer

1. `subslides` per §10.2, including `fit:` and the aux layouts. Visual test
   `tt new slides-subslides`: a graph traversal's frames through
   `subslides(aux: "right", fit: (20cm, 12cm))`, plus a `last`/single-Frame
   call, plus an `overlay` callout using an `el-` anchor. New refs.
2. Delete `canvases-only` and the old lib.typ helper implementations; drop the
   Phase-3 compat arm in slides.typ.
3. git-graph curation per §9 (rename internals, unified theme section).
   `git-graph` test refs must be pixel-identical.

**Done when:** suite green; `dictionary(lib)` matches §10.1 exactly (conformance
test).

### Phase 7 — Sweep

1. Grep-audit: no `_`-prefixed name is referenced across module boundaries
   except from `core/*` siblings (allowed) — DS and presentation modules use
   only public core names. Fix any stragglers by promoting (rename without `_`)
   or restructuring.
2. Every function > 100 lines that is NEW code gets split; ported-verbatim
   algorithm bodies (the CLRS/Okasaki/Kahrs traces, the draw backends) are
   exempt — do not risk behavior churn for line counts.
3. Full-suite timing sanity check: `time just test` before/after the branch;
   flag anything
   > 20% slower (suspect: theme resolution or lost closure caching — see §4.5
   > perf rule).

### Phase 8 — Docs & Packaging

1. `docs/manual.typ`: rewrite all example code via §11.1; add tidy
   `parse-module`/ `show-module` stanzas for **every** public module (the old
   manual covered 11 of 19 files and omitted `op-theme`, `bst`, `rbt`, `avl`,
   `b24`, `trie`, `sort`, `array-draw` entirely); document the theme system
   (§4.4), the DS module contract (§7.1), `subslides`, the style vocabulary, the
   extension story (`make-renderer` + custom draw fn), and a "1.0.0 migration"
   section that is essentially §11.1. `just doc` compiles again.
2. `typst.toml`: version `1.0.0`; description mentions all the data structures,
   not just "binary search trees, 2-3-4 trees, and weighted graphs".
3. `Justfile`: `install`/`uninstall` targets read the version from `typst.toml`
   (or at minimum update the hard-coded `0.1.0`). Add `just check` running only
   the assertion tests (`tt run` with the `*-ops` + `core-ops` +
   `api-conformance` names).
4. `CHANGELOG.md`: a real `## [1.0.0]` entry (breaking rewrite, summary of
   §11.1); fix the stale `[Unreleased]` filing of AVL/git-graph.
5. Rewrite `CLAUDE.md` for the new architecture (it is git-ignored local
   guidance; keep the same level of detail but describe the NEW layering, the DS
   contract, the theme dict, and the phase-free steady state).
6. `just ci` green. Tag nothing; leave merging to mjs.

---

## 13. Out of Scope for 1.0.0 (Future Work — Do Not Do These Now)

- Aux views for hashmap (probe sequence), sort (running count), skiplist
  (`update[]`), b24 (split stack), rbt (case trace).
- A first-class progressive-reveal display (`reveal-frames`); 1.0 ships the
  `ghost` style key + `styles.ghost/revealed`, which cover the lecture use cases
  manually.
- The trie "array-of-slots" implementation view (lecture 24 hand-built one).
- Publishing to `@preview` / typst universe.
- Any change to the lecture repo (porting decks to 1.0.0, deleting the dead
  `00-common-assets/tree-anim.typ` vendored copy, retiring the lecture-07
  git-graph fork).

## 14. Known Risks / Verify-at-Implementation-Time

1. ~~**cetz anchor charset** (§6.2)~~ — **RESOLVED in Phase 1.** cetz accepts
   the sanitized `el-` names and resolves their compass sub-anchors; the
   `core-ops` test's rendered page is the standing check. Phase 2 step 4 is
   already done.
2. ~~**hashmap "fit" sizing refs** (§4.7)~~ — **RESOLVED.** Phase 2 wired the
   backend with `measure-cells` defaulting to `()`; Phase 3 supplied the
   superset. No hashmap ref moved (see §4.7 for why). The one intentional ref
   change in Phase 3 turned out to be `hashmap-theming`, from the per-call /
   state precedence rule instead (§4.4).
3. **Theme resolution perf** — one state read per `last`/`figures`/`subslides`
   call is the design; if a deck with hundreds of calls regresses, memoize
   `resolve-theme((:))` via a module-level pre-merged constant for the
   no-override path.
4. **`dictionary(module)`** requires Typst ≥ 0.12 — the repo pins 0.14, fine;
   just don't drop the conformance test if it errors, fix the usage.
5. Old code carries comments referencing typsy tricks ("wrapped in a singleton
   dict so typsy doesn't self-inject") — delete these comments during ports;
   they must not survive into `src/` after Phase 5.
