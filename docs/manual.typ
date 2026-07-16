#import "/src/lib.typ" as starling
#import "@preview/cetz:0.5.2"
#import "@preview/tidy:0.4.3"

#set page(paper: "us-letter", margin: 1in)
#set par(justify: true)
#set heading(numbering: "1.")
#show raw.where(block: true): set block(fill: luma(245), inset: 8pt, radius: 3pt, width: 100%)

#align(center)[
  #text(28pt, weight: "bold")[Starling]\
  #v(0.4em)
  #text(13pt, style: "italic")[Animated renderings of data structures for teaching]\
  #v(0.3em)
  #text(11pt)[Manual for v0.2.0]
]

#v(2em)

#outline(depth: 2, indent: auto)

#pagebreak()

= Introduction

Starling renders animated data structures in Typst, built on top of
#link("https://typst.app/universe/package/cetz")[cetz],
#link("https://typst.app/universe/package/typsy")[typsy], and
(optionally) #link("https://typst.app/universe/package/touying")[touying].
The package is designed for a programming course: it ships a binary
search tree today and is structured to grow to heaps, hash tables, and
graphs without rewriting the animation kernel.

Every animation in starling is built from the same primitive — an
ordered array of `Frame` records. Each `Frame` carries a rendered cetz
canvas, an optional textual caption, and free-form step metadata. The
package supplies a few helpers to collapse the array into a final
image, a vertical stack, or an array of subslide figures, but you are
free to ignore them and lay frames out however your document needs.

== Quick start

```typ
#import "@preview/starling:0.2.0" as starling
#import starling: bst

#let t = bst(4, 1, 7, 3, 6)
```

#let t = starling.bst(4, 1, 7, 3, 6)

The first argument becomes the root; the rest are inserted in order.
For custom node labels, pass a #raw("(value, label)") 2-tuple in place
of a bare value — e.g. #raw("bst((4, [FOUR]), 1, (7, [SEVEN]))").
The lower-level constructor #raw("(BST.new)(value:, label:, left:,
right:)") and the #raw("(t.insert-many)(..vals)") method are still
available for finer control.

A static render of the tree, taking the final frame from `(t.display)()`:

#align(center, starling.last((t.display)()))

A full search animation, stacked vertically with per-step captions:

#align(center, starling.stacked((t.search-display)(6)))

= Architecture

Starling is layered into three source files, each with a single
responsibility:

#table(
  columns: (auto, 1fr),
  inset: 6pt,
  align: (left, left),
  table.header[*File*][*Role*],
  [`src/anim-core.typ`],
  [The structure-agnostic animation core — defines `Snapshot`,
   `Frame`, the `Renderer` (with a pluggable draw backend),
   `make-renderer`, `Op`, and `apply-ops`. Knows nothing about any
   particular structure.],
  [`src/tree-anim.typ`],
  [The tree backend on the core — `draw-tree`, the cetz-tree
   builders, `PathId`, `path-anchor`, and the tree-bound
   `make-renderer` wrapper. Re-exports the core.],
  [`src/bst.typ`],
  [The BST class — implements pure operations (`insert`, `delete`,
   `rotate`) and the `*-display` methods that build animations using
   the kernel.],
  [`src/graph-draw.typ`],
  [The graph renderer on the core — `draw-graph`, `edge-key`,
   `node-anchor`, and the graph-bound `make-graph-renderer` wrapper.
   The graph analog of `tree-anim.typ`; knows drawing, not algorithms.],
  [`src/graph.typ`],
  [The Graph class — data plus the MST / Dijkstra / BFS / DFS
   `*-display` algorithms. Split from its renderer, like `bst.typ` is
   from `draw-tree`.],
  [`src/graph-layout.typ`],
  [Optional graphviz auto-layout (`auto-layout`) via `diagraph-layout`.
   The only file referencing that dependency, and it does so with a
   lazy import inside `auto-layout`'s body — so the dependency stays
   optional even though `lib.typ` re-exports the function.],
  [`src/git-graph.typ`],
  [The git-graph DSL — a *stateful* cetz builder (`commit`, `branch`,
   `merge`, `tag`, `branch-pointer`, `head-pointer`, `detached-commit`)
   for drawing git commit graphs. Deliberately off the `Frame` stack;
   surfaced under the `starling.git.*` namespace. Carries its own per-DS
   theme (`default-git-theme` / `set-git-theme`).],
  [`src/lib.typ`],
  [The public surface — re-exports everything users need, plus the
   render helpers (`last`, `stacked`, `figures`, `canvases-only`).],
)

This split lets us add a new data structure (e.g. a heap) by writing
just a new file at the `bst.typ` layer; the kernel does not need to
change. Conversely, a power user who wants to assemble custom
animations can talk to the kernel directly without touching the BST
class at all.

== Snapshots, frames, and the renderer

Four types do most of the work. Their roles are intentionally
distinct:

#table(
  columns: (auto, 1fr),
  inset: 6pt,
  align: (left, left),
  table.header[*Type*][*Role*],
  [`Snapshot`],
  [A _sparse style overlay_ for one moment in time — which nodes are
   filled what colour, which edges are dashed or hidden, which notes
   are attached to which nodes. Built up by chaining
   `style-node` / `style-edge` / `note-node` calls. Pure data; no
   theme awareness, no content.],
  [`TreeRenderer`],
  [A tree plus an ordered list of snapshots plus optional caption /
   step-metadata for each snapshot. The thing you build up while
   describing an animation.],
  [`Frame`],
  [The _output_ record: `(render, caption, step, alt)`. `render` is a
   builder function `(op-theme, render-theme) -> content` — not
   pre-baked content — so callers can resolve theme state at layout
   time and reuse the same animation across documents with different
   themes. `TreeRenderer.render` produces an array of these, one per
   snapshot. This is what `*-display` methods return.],
  [Theme dict],
  [One of three layers, in merge order: `render-theme` (structural
   defaults like node fill, edge stroke, note colour), `op-theme`
   (operation strokes/fills shared across data structures, like
   `search-stroke`, `success-fill`, `traversal-palette`), and an
   optional per-DS theme (e.g. `rbt-theme`'s red/black palette).
   Frames are theme-agnostic until a render helper feeds resolved
   themes into each frame's `render` builder.],
)

The data flow, end to end:

#align(center)[
  `Snapshot` array #h(0.5em) → #h(0.5em) `TreeRenderer.render`\
  #h(0.5em) → #h(0.5em) `Array(Frame)` _(builders, theme-agnostic)_\
  #h(0.5em) → #h(0.5em) helper resolves theme state once\
  #h(0.5em) → #h(0.5em) helper calls each `(f.render)(op, rt)`\
  #h(0.5em) → #h(0.5em) document content
]

The shape matters: snapshots and frames are both pure data until the
final step. That makes them inspectable, slicable, and composable —
you can pull a frame out, look at its `step` metadata, swap its
caption, or thread it into a custom layout without rendering. The
theming-aware materialisation is concentrated at the helper boundary.

== Path identity

Every node is identified by its position in the tree, encoded as a
string of `"L"` and `"R"` characters from the root. The root is `""`,
the right child of the root is `"R"`, the left child of `"R"` is
`"RL"`, and so on. Edges are identified by the path of their _child_
node — each child has exactly one parent, so this is unambiguous.

Path identity is the linchpin that keeps node and edge styling
independent of the tree's value or layout. It also means a
node-highlighting animation built for one tree can be reused on a tree
of the same shape with different values just by passing a different
`tree` to `make-renderer`.

The only places that interpret path characters are `PathId` (the
refined string type), `_build-cetz-tree` (which walks `.left` and
`.right`), and the BST's own `by-value` / `path-to` / `resolve`
methods. Everywhere else treats paths as opaque keys, which leaves
room to generalise — n-ary trees would use slash-separated child
indices like `"0/1/2"` or arrays of ints, and only those four places
need to change.

== Sticky animation accumulation

`make-renderer(tree, sticky: true)` is the common case: each new frame
pushed via `r.push-frame()` starts from the previous frame's snapshot.
That means a sequence like

```typ
#let r = starling.make-renderer(t, sticky: true)
#let r = (r.push-with-node)("",  stroke: blue + 2pt)   // frame 1
#let r = (r.push-with-node)("L", stroke: blue + 2pt)   // frame 2
#let r = (r.push-with-node)("LR", stroke: blue + 2pt)  // frame 3
```

produces three frames where each highlights one more node than the
last — frame 3 has all three highlights, not just `LR`. This matches
the natural mental model for teaching ("we visited these nodes in
order"). Set `sticky: false` if you want each frame to start fresh.

Captions and `step` metadata do _not_ sticky-accumulate; each frame's
caption is whatever was last set on that frame, with no carry-over.

== The cetz integration

The animation kernel renders each snapshot via `draw-tree`, which
emits cetz draw commands using `cetz.tree.tree(...)` for layout. The
key choice here is _not_ to wrap `draw-tree`'s output in `cetz.canvas`
inside the kernel — that wrap happens one layer up, in
`_render-canvas`. The two functions are split so a power user can
write their own `cetz.canvas` block, call `draw-tree` inside it, and
add their own cetz annotations alongside the tree (see
@composing-with-cetz-annotations).

Anchors for individual nodes are exposed by `path-anchor`, which
translates an L/R path string into the cetz anchor name produced by
`draw-tree`. The fact that this needs a translation function at all
is a quirk worth flagging — see @path-based-anchors-and-the-cetz-tree-quirk.

= Design decisions

This section explains the major calls that shape the API. None of
them are obvious from reading the code, but each was a conscious
choice and the reasoning is load-bearing for anyone considering a
refactor.

== Why frames, not a wrap callback

The original (v0.1) API let users configure `starling.configure(wrap:
alternatives)` to bake touying's `alternatives` into the BST class via
closure capture. Each `*-display` method internally called
`wrap(..figs)` on the array of figures it generated.

That approach was rigid in two ways. First, the rendering decision
was made _inside_ the animation method, so the same animation could
not appear as a static figure in handouts and as a subslide sequence
in slides — you'd configure differently per context. Second, and
worse, the animation was always one opaque blob: there was no way to
weave the caption "6 \> 4" alongside other slide content while keeping
the visual animation synchronised, because everything lived inside a
single `alternatives` mark.

The current API solves both: `*-display` returns the raw frame array,
and the helpers (`last`, `stacked`, `figures`) collapse it however
the caller wants. Wanting to lay captions in a sidebar while the
animation plays? Pull them out yourself:

```typ
#let frames = (t.search-display)(6)
#grid(columns: 2,
  alternatives(..starling.figures(frames, caption: false)),
  alternatives(..frames.map(f => f.caption)),
)
```

A historical note worth preserving: closure-captured `wrap` was
itself chosen over a state-based approach (`std.state`, typsy's
`safe-state`) because touying's `alternatives` is a layout-time
"mark" that touying rejects inside `context { ... }` blocks. With
frames as plain data, that constraint no longer applies to the
animation API — and state did become viable later for the theming
layer (see _State for ergonomics, per-call for perf_ below).

== Three theme layers, one per concern

Theming is split into three dicts that each own a different concern:

- *Render theme* (`default-render-theme`, in `anim-core.typ`) holds
  structural defaults — node fill, node stroke, node text fill, edge
  stroke, note fill, edge-tag fill (persistent edge labels like AVL
  heights and graph weights), and note-bg (the fill drawn behind a
  node's in-canvas annotations so they stay legible over edges;
  defaults to `white`, set it to the page color on a dark background).
  Anything any data structure would need to render at all.
- *Op theme* (`default-op-theme`, in `op-theme.typ`) holds operation-
  semantic strokes/fills/palettes that apply to _any_ data structure
  with those operations — `search-stroke`, `attention-stroke`,
  `success-stroke`, `settled-stroke`, `success-fill`, `danger-stroke`,
  `reset-stroke`, `traversal-palette`. BST search and a hypothetical
  hash-table search share the same `search-stroke` from this layer.
- *Per-DS theme* (e.g. `default-rbt-theme`, in `rbt.typ`) holds
  styling intrinsic to one data structure — the red/black palette for
  RBTs is the canonical example. BST itself has no per-DS theme,
  because BST nodes have no intrinsic differentiation.

The split lets each layer own its own concerns. A new data
structure (heap, trie, B-tree) brings its own per-DS theme dict if
needed and reuses the render theme and op theme as-is. If operation
strokes lived in a BST theme, every new data structure would either
duplicate them or grow a coupling to BST.

The render theme also has a clear "lowest in the chain" role:
`draw-tree` falls back to it when neither a snapshot override nor a
`make-renderer(default-node-style:, default-edge-style:)` argument
specifies a property. So the merge order, lowest precedence first, is:
`default-render-theme` → user render-theme override → op-theme /
per-DS-theme overlays applied per snapshot → renderer defaults →
per-snapshot per-path overrides. Each layer adds more specificity.

Strokes throughout the op theme are full stroke dictionaries
(`(paint:, thickness:, dash:)`), not bare colours. That lets users
change any aspect of a stroke (dash pattern, cap, width) without us
adding more theme keys for each possibility.

== Frames carry builders, not pre-rendered content

`Frame.render` is a function `(op-theme, render-theme) -> content`,
not a piece of pre-baked content. This is so render helpers (`last`,
`stacked`, `figures`) can resolve theme state _once per call_ and
feed those resolved themes into every frame's builder, rather than
each frame independently resolving theme inside its own context
block.

The frame-as-builder shape also has a non-perf benefit: an
`Array(Frame)` is now a portable, theme-agnostic description of an
animation. The same frames can render against different themes in
different contexts without re-running the `*-display` method. That's
a cleaner separation than the older `(canvas, caption, step)` shape,
where `canvas` baked in whatever theme was active at construction
time.

A typsy quirk worth noting: typsy auto-injects `self` into any
function-typed field on a class. To keep `(frame.render)(op, rt)`
from getting a spurious third argument, the actual closure is stored
as `_builder: (fn: ...)` — a singleton dict around the function — and
exposed through a `render` method that dereferences it. Users only
see `(frame.render)(op, rt)`; the dict wrap is private.

RBT and any future per-DS theme are read inside the frame's builder
itself, not by the lib.typ helpers. The helpers only resolve the two
universal layers — op-theme and render-theme — and pass them in;
per-DS themes are state-read on demand. That keeps the helper
signature stable as more data structures land.

== State for ergonomics, per-call for perf

Theme overrides come in two flavours:

#table(
  columns: (auto, 1fr),
  inset: 6pt,
  align: (left, left),
  table.header[*Form*][*Behaviour*],
  [`set-op-theme((..))` / `set-render-theme((..))` / `set-rbt-theme((..))`],
  [State-based. One declaration at the top of the document propagates
   through every subsequent `*-display` call. Ergonomic and intent-
   matching, but participates in Typst's state-convergence machinery
   — see @theming-perf.],
  [`(t.search-display)(v, theme: (..))`],
  [Per-call. Overrides the theme for one call; ignores state for that
   call. Verbose if you have many calls, but skips the state-cost
   path entirely. Run at the no-state baseline.],
)

Both paths exist because there's no single answer. State is right
for a document that uses one theme throughout — write
`set-op-theme(my-palette)` once, forget about it. Per-call is right
when compile speed dominates and the user is happy threading a `let
palette = (..)` value through their calls. The library does not pick
a winner.

The cost being structural to Typst — not something starling can
optimise away — meant choosing whether to expose state at all was a
real call. Skipping state would have removed the perf footgun but
also removed the ergonomic win. Exposing both, with the cost
documented up-front, lets users decide.

== Two-channel captions

For `search-display` and `insert-display`, the comparison string
("6 \> 4") appears in _two_ places:

- *Inline*, as a small note drawn beside the highlighted node in the
  cetz canvas. This labels which comparison happened at which node
  spatially.
- *Caption*, as a textual track on the `Frame` record. This is what
  `stacked` and `figures` render below the canvas, and what callers
  pulling captions out for custom layouts read.

The redundancy is deliberate. The inline note is part of the visual:
when looking at a single frame, you should be able to see at a glance
what the algorithm just did. The caption is a parallel _textual_
track for layouts that want narration apart from the animation.

This is why `last(frames)` defaults to `caption: false` — the inline
note already labels the node, so adding a caption block below the
static figure would be redundant. `stacked` and `figures` default to
`caption: true` because animated rendering invites the textual
narrative.

== The six-frame rotation <the-six-frame-rotation>

`rotate-display` walks through rotation as six discrete frames:
`init`, `pivots`, `break`, `restructure`, `connect`, `settle`. The
sequence is calibrated for teaching: each frame answers exactly one
question.

#table(
  columns: (auto, 1fr),
  inset: 6pt,
  align: (left, left),
  table.header[*`step.kind`*][*Question answered*],
  [`init`],     [What's the starting tree?],
  [`pivots`],   [Which two nodes are rotating?],
  [`break`],    [Which edges are about to disappear?],
  [`restructure`], [What does the new shape look like, edges aside?],
  [`connect`],  [Where do the new edges go?],
  [`settle`],   [What does the final, clean tree look like?],
)

An earlier draft had a "dashed red" intermediate between
`pivots` and `break` (edges going dashed before disappearing). That
was dropped because the orange pivot highlight already cues the eye
to those edges — the extra frame added length without information.

The `restructure` frame is the load-bearing one: it shows the new
tree shape with the rotated edges still hidden, so the student can
see the new positions form _before_ the edges connect. Without it,
the rotation would collapse into one cut from "broken" to "rotated +
highlighted edges", which is too much information at once.

== Path-based anchors and the cetz tree quirk <path-based-anchors-and-the-cetz-tree-quirk>

`cetz.tree.tree` numbers its nodes internally as `0`, `0-0`, `0-1`,
`0-0-1`, ... — sibling indices joined by hyphens, with the root being
`0`. Starling configures cetz-tree's `group-name-prefix` to `"node-"`,
so the resulting anchor names look like `node-0-0-1`. The whole tree
also sits inside an outer named group (`"tree"` by default), so the
fully qualified anchor for path `"LR"` is `tree.node-0-0-1`.

Two things made me reach for `path-anchor` rather than letting users
type that out:

1. The user thinks in `"LR"`, not `"0-0-1"`. The translation is
   mechanical (`L → 0`, `R → 1`, prepend the root `0`) but it's
   error-prone to do by hand.
2. The naming scheme is a cetz-tree implementation detail. Wrapping
   it in `path-anchor(path, tree-name:, prefix:)` lets us swap to a
   different naming scheme later (e.g. if we drop cetz-tree for a
   custom layout) without churn at every annotation call site.

Phantom siblings (used to off-centre lone children — see
`_build-cetz-tree`) also get cetz-tree-internal anchor names like
`node-0-0-0`, but they are hidden at draw time and you generally
should not annotate them.

= BST animations tour

The BST class provides five `*-display` methods. Each returns
`Array(Frame)`; the examples below pass the result to `starling.stacked`
to render every frame vertically with its caption.

We'll use the same sample tree throughout this section, seeded via
the #raw("bst(..vals)") factory (first arg = root, rest are
inserted):

```typ
#let t = bst(4, 1, 7, 3, 6, 8)
```

#let tour = starling.bst(4, 1, 7, 3, 6, 8)

== Static display

`(t.display)()` returns a one-element frame array — the unmodified
tree, with no step metadata.

#align(center, starling.last((tour.display)()))

== Search

`(t.search-display)(v)` walks the search path, highlighting each
node visited and labelling it with the comparison made. `step.kind`
is `"init"` for the initial frame and `"compare"` for each step;
`step.found` records whether the value was reached.

#align(center, starling.stacked((tour.search-display)(6)))

== Insert

`(t.insert-display)(v)` walks the search path as for `search-display`,
then transitions to the after-tree with the new node highlighted via
`success-stroke` / `success-fill`. `step.kind` is `"init"`, `"compare"`
(per search step), and finally `"inserted"`.

#align(center, starling.stacked((tour.insert-display)(5)))

== Delete

`(t.delete-display)(v)` has three internal cases — leaf, one-child,
and two-children — and dispatches on the target's children. `step.kind`
ranges over `"init"`, `"highlight"`, `"break"`, `"descend"`,
`"transfer"`, and `"settle"` depending on case.

The two-children deletion is the most complex: it highlights the
target, descends into the left subtree to find the in-order
predecessor, annotates the value transfer, then jumps to the after-tree
with the new root of the affected subtree highlighted via `success-stroke`.

#align(center, starling.stacked((tour.delete-display)(4)))

== Rotate

`(t.rotate-display)(c)` rotates around node `c` — any node in the
tree with a parent, not just a direct child of the root. The
direction (left/right) is inferred from `c`'s position in the BST.
The six-frame sequence is described in @the-six-frame-rotation.

#align(center, starling.stacked((tour.rotate-display)((tour.resolve)("L"))))

== Traversals

`(t.in-order-display)()`, `(t.pre-order-display)()`,
`(t.post-order-display)()`, and `(t.level-order-display)()` animate
the four standard traversals. Each returns one frame per visit (plus
the initial frame): the visited node is filled with the next color in
a perceptually-uniform palette (magma by default) and tagged with a
numbered badge marking its visit order, and the caption accumulates
the running output sequence. `step.kind` is `"init"` for the initial
frame and `"visit"` thereafter, with `step.value` and `step.index`
(1-indexed) recording each visit. Switch palettes via the theme
system (see #link(label("theming"))[Theming]) — either doc-wide with
`set-op-theme((traversal-palette: color.map.viridis))` or per-call
with `(t.in-order-display)(theme: (traversal-palette: ...))`.

Pure-data variants `(t.in-order)()`, `(t.pre-order)()`,
`(t.post-order)()`, and `(t.level-order)()` return the visit sequence
as an array of path strings without producing any animation, in case
you want to drive a custom layout.

#align(center, starling.stacked((tour.in-order-display)()))

The final frame of each traversal carries the algorithm's full color
signature. Laying all four out side-by-side gives a fast visual
comparison — especially useful as a recall cue in review material
where students already understand the algorithms and the gradient
pattern reads as "oh right, post-order goes leaves-cool to
root-warm":

#let traversal-panel(label, frames) = block(breakable: false, stack(
  dir: ttb,
  spacing: 0.4em,
  align(center, strong(label)),
  starling.last(frames, caption: true),
))

#align(center, grid(
  columns: 2,
  gutter: 1.5em,
  traversal-panel([In-order], (tour.in-order-display)()),
  traversal-panel([Pre-order], (tour.pre-order-display)()),
  traversal-panel([Post-order], (tour.post-order-display)()),
  traversal-panel([Level-order], (tour.level-order-display)()),
))

= RBT animations tour

The `RBT` class ships three `*-display` methods today: `display`,
`insert-display`, and `delete-display`. Each returns `Array(Frame)`
in the same shape as the BST methods, so the render helpers
(`last`, `stacked`, `figures`) and the caption / `step` /
`alt` conventions carry over unchanged. The rbt-theme palette (red
and black fill, stroke, and text-fill) is layered on top of the
render theme so every frame's nodes wear their semantic colors
automatically; operation-specific highlights from the op-theme
(search-stroke on descent, attention-stroke on fix-up pivots,
settled / success strokes on resolution) compose on top.

The sample tree throughout this section is seeded via the
#raw("rbt(..vals)") factory — first arg becomes the (black) root,
the rest are inserted in order so the CLRS fix-ups produce a clean
balanced shape with a mix of red and black nodes:

```typ
#let t = rbt(8, 4, 12, 2, 6, 10, 14, 1)
```

#let rbt-tour = starling.rbt(8, 4, 12, 2, 6, 10, 14, 1)

For finer control, the lower-level
#raw("(RBT.new)(value:, label:, red:, left:, right:)") constructor
plus #raw("(t.insert-many)(..vals)") method are still available —
the root takes a #raw("red:") argument because a single-node tree
also carries a colour (it must be black after every public
operation).

== Static display

`(t.display)()` returns a one-element frame array — the unmodified
tree, with every node coloured by its `red` field from the active
rbt-theme palette.

#align(center, starling.last((rbt-tour.display)()))

== Insert

`(t.insert-display)(v)` traces the CLRS insertion algorithm: a BST
descent records each visited node, the new value splices in as a
red leaf, then a fix-up loop walks back up the tree applying Case 1
(uncle red — recolour parent and uncle black, grandparent red,
continue at the grandparent), Case 2 (zigzag — rotate around the
parent to straighten the red-red pair), and Case 3 (straight line
— rotate around the grandparent and swap its colour with the new
subtree root). The root is blackened at the end if it ended up
red. `step.kind` ranges over `"init"`, `"descend"`, `"insert"`,
`"check"`, `"recolor"`, `"rotate-zigzag"`, `"rotate-recolor"`, and
`"blacken-root"`.

Inserting 0 walks down to the red leaf 1, splices a red 0 beneath
it, then resolves the red-red pair via a straight-line Case 3
(rotate around the grandparent 2, swap its colour with the new
subtree root 1):

#align(center, starling.stacked((rbt-tour.insert-display)(0)))

== Delete

`(t.delete-display)(v)` traces a BST search for the target, the
in-order predecessor walk if the target has two children, the
value transfer, the structural excise, and the four-case
rebalancing loop. `step.kind` covers `"init"`, `"descend"` (a
single frame highlighting the full search path; pass
`search: true` for one `"compare"` frame per step instead),
`"not-found"`, `"mark-target"`, `"find-predecessor"`, `"transfer"`,
`"excise"`, `"paint-black-promoted"`, `"paint-black-db"`, and the
fix-up cases. Cases 1, 3, and 4 each emit two frames — a
rotation-only intermediate (`"case-1-rotate"`, `"case-3-rotate"`,
`"case-4-rotate"`) followed by the recolor (`"case-1"`, `"case-3"`,
`"case-4"`) — so the structural pivot lands separately from the
color swap. Case 2 is a pure recolor and emits a single `"case-2"`
frame.

Excising a black node leaves the subtree one black short of the
rest of the tree. The animation marks that imbalance with a small
filled circle at the child end of the affected edge — the textbook
convention. The circle stays in place across each fix-up step that
doesn't resolve the missing black; it disappears once a Case 4
rotation drains it or a red ancestor absorbs it. Deleting the black
leaf 6 takes the Case 4 branch directly (sibling 2 is black, far
nephew 1 is red):

#align(center, starling.stacked((rbt-tour.delete-display)(6)))

== Theming the red/black palette

The rbt-theme palette lives in its own state, separate from the
render theme and op theme, with `default-rbt-theme` as the seed and
`set-rbt-theme` / a per-call `theme:` argument as the two override
paths. Recognised keys are `red-fill`, `red-stroke`,
`red-text-fill`, `black-fill`, `black-stroke`, and
`black-text-fill`; unknown keys panic so typos surface immediately.

Set the palette document-wide via `set-rbt-theme` (state-based,
participates in the layout-pass cost — see @theming-perf):

```typ
#import "@preview/starling:0.2.0": RBT, set-rbt-theme

#set-rbt-theme((
  red-fill: orange,
  red-stroke: orange.darken(20%),
  black-fill: navy,
  black-stroke: navy,
))
```

Or per-call to skip state and run at the no-state baseline:

```typ
(t.display)(theme: (red-fill: red.darken(20%)))
```

= AVL animations tour

The `AVL` class is a height-balanced BST. Each node carries an extra
`height` field; after every public operation the height is up-to-date
and #raw("|h(left) - h(right)|") (the *balance factor*) is at most 1.
Imbalances are repaired with single or double rotations, dispatched on
four cases (LL, RR, LR, RL) — the same ones every textbook walks
through.

`AVL` ships the standard suite of `*-display` methods (`display`,
`search-display`, `insert-display`, `delete-display`,
`rotate-display`, `fixup-display`, and the four `*-order-display`
traversals), all returning `Array(Frame)` so the render helpers and
caption / `step` / `alt` conventions carry across unchanged. AVL has
no per-DS theme — animation strokes come from the op-theme, structural
defaults from the render theme.

The sample tree throughout this section is seeded via the
#raw("avl(..vals)") factory — first arg becomes the root, the rest
are inserted in order so the AVL rebalancing produces a clean balanced
shape:

```typ
#let t = avl(5, 3, 7, 2, 4, 6, 8, 1, 9)
```

#let avl-tour = starling.avl(5, 3, 7, 2, 4, 6, 8, 1, 9)

For finer control, the lower-level
#raw("(AVL.new)(value:, label:, height:, left:, right:)") constructor
plus #raw("(t.insert-many)(..vals)") method are still available — the
root takes a #raw("height:") argument because a single-node tree
already has height 1.

== Static display

`(t.display)()` returns a one-element frame array — the unmodified
tree. Pass `factors: true` to tag every node with its signed balance
factor (e.g. #raw("\"+1\""), #raw("\"0\""), #raw("\"-1\"")), drawn
just west of the node so it doesn't compete with the label or the
operation `note` slot. The tag layer is reused by every `*-display`
method as a base layer (off by default; opt in per call).

#grid(
  columns: 2,
  gutter: 1.5em,
  align: center,
  starling.last((avl-tour.display)()),
  starling.last((avl-tour.display)(factors: true)),
)

== Insert

`(t.insert-display)(v)` traces the AVL insertion algorithm. A BST
descent records each visited node, the new leaf appears with height 1,
then the climb back to the root recomputes each ancestor's height
in turn. On the first ancestor whose balance factor reaches ±2, the
animation labels the imbalance case (LL/LR/RR/RL), applies a child
rotation if the case is a zigzag (LR or RL), and finishes with the
single rotation at the imbalanced node. After a single insertion the
subtree's height returns to its pre-insert value, so the climb stops
there. `step.kind` ranges over #raw("\"init\""), #raw("\"descend\""),
#raw("\"insert\""), #raw("\"recompute\""), #raw("\"check\""),
#raw("\"rotate-zigzag\""), and #raw("\"rotate-finish\"").

Inserting 0 into the sample tree triggers an LL fix-up at node 2
(after the climb sees node 1's height grow). The fix-up is a single
right rotation:

#align(center, starling.stacked((avl-tour.insert-display)(0, factors: true)))

The zigzag cases (LR/RL) emit an extra `rotate-zigzag` frame between
`check` and `rotate-finish` for the child rotation that straightens the
configuration before the final rotation at the imbalanced node.

== Delete

`(t.delete-display)(v)` traces a BST search for the target, the
in-order predecessor walk if the target has two children, the value
transfer, the structural excise, and then a climb that recomputes
heights and rotates at every imbalanced ancestor. Unlike insert, a
single deletion can trigger several rotations on the way up — the
loop runs to the root. `step.kind` covers #raw("\"init\""),
#raw("\"descend\"") (single frame; pass `search: true` for one
#raw("\"compare\"") per step instead), #raw("\"not-found\""),
#raw("\"mark-target\""), #raw("\"find-predecessor\""),
#raw("\"transfer\""), #raw("\"excise\""), and the same
#raw("\"recompute\"") / #raw("\"check\"") /
#raw("\"rotate-zigzag\"") / #raw("\"rotate-finish\"") events insert
emits.

Deleting 3 from the sample tree takes the two-child branch
(predecessor transfer from 2) and stays balanced — the climb
recomputes heights without triggering any rotation:

#align(center, starling.stacked((avl-tour.delete-display)(3, factors: true)))

== Rotate

`(t.rotate-display)(c)` is the same six-frame structural rotation
animation BST exposes, with heights refreshed in the after-tree. AVL
rebalancing in `insert` / `delete` does *not* go through this method —
the case-dispatch rotations are applied directly so the animation can
narrate the recompute-then-rotate logic.

== Fix-up

`(t.fixup-display)(violation-path)` runs the AVL fix-up climb from a
hand-constructed (possibly invalid) tree. The tree is *not* validated:
this is intended for teaching configurations that can't arise from a
single insert or delete — for example, multiple imbalances on one
spine where the inner rotation propagates the imbalance up. The climb
walks every proper prefix of `violation-path` deepest-first, emitting
the same `recompute` / `check` / `rotate-zigzag` / `rotate-finish`
events that insert and delete use.

== Traversals

`(t.in-order-display)()`, `(t.pre-order-display)()`,
`(t.post-order-display)()`, and `(t.level-order-display)()` work
exactly like their BST counterparts — one frame per visit, gradient
fill from the op-theme's `traversal-palette`, running output sequence
in the caption. Pass `factors: true` on any traversal to layer the
balance-factor tags under the per-visit highlights.

= B24 animations tour

The `B24` class is a 2-3-4 tree (a B-tree of order 4) — every internal
node holds 1, 2, or 3 keys (so 2, 3, or 4 children) and every leaf
sits at the same depth. The node renderer for this data structure is
the subdivided rectangle shape `"btree-node"`, which scales its width
with the number of keys; per-key compartments are individually
addressable via the `"<path>#<i>"` path syntax and the `key-styles`
slot on `NodeStyle`.

`B24` exposes the standard suite of `*-display` methods (`display`,
`search-display`, `insert-display`, `delete-display`, and the four
`*-order-display` traversals). Insert and delete accept a
#raw("strategy:") argument that switches between two textbook
algorithms:

- *Top-down* (the default): preventive — split any 3-key node on the
  way down for insert; refill any 1-key node on the way down for
  delete. Single-pass recursion.
- *Bottom-up*: reactive — walk to the leaf first, then propagate
  splits or merges back up through the descent path.

Both produce valid 2-3-4 trees containing the same keys but they can
produce structurally different *shapes* — bottom-up promotes a key
from the *post-overflow* 4-key state (so the freshly inserted key may
itself be promoted), while top-down promotes the middle of the
*pre-insert* 3-key state. There is no per-DS theme — animation strokes
come from the op-theme; structural defaults from the render theme.

The sample tree throughout this section is seeded via the
#raw("b24(..vals)") factory:

```typ
#let t = b24(10, 5, 15, 1, 7, 12, 20, 25, 30, 17, 19)
```

#let b24-tour = starling.b24(10, 5, 15, 1, 7, 12, 20, 25, 30, 17, 19)

For finer control, the lower-level
#raw("(B24.new)(keys:, labels:, children:)") constructor lets you
hand-build a tree with any compartment count at every depth — useful
for fixtures that demonstrate a specific fix-up case.

== Static display

`(t.display)()` returns a one-frame array — the unmodified tree.
Compartment widths scale with key count, and edges fan out from the
gap anchors (`gap-0` through `gap-k`) on the parent's south face.

#align(center, starling.last((b24-tour.display)()))

== Search

`(t.search-display)(v)` highlights one key compartment per comparison.
The descent path stays visible as the search progresses (sticky search
strokes); the inline note at each visited node carries the comparison
text. Misses end at the leaf without panicking — the final frame
reports that the value isn't in the tree.

#align(center, starling.stacked((b24-tour.search-display)(19)))

== Insert

`(t.insert-display)(v, strategy: ..)` traces the full insertion
algorithm. Top-down splits trigger a `td-pre-split-attention` frame
that outlines a full node about to be split, then a `split-done`
frame showing the promoted key with its two new child edges. The
final `settled` frame highlights the inserted compartment.

#align(center, starling.stacked((b24-tour.insert-display)(13)))

The bottom-up variant runs the descent first, then animates the leaf
insertion plus any cascading splits:

#align(center, starling.stacked((b24-tour.insert-display)(13, strategy: "bottom-up")))

== Delete

`(t.delete-display)(v, strategy: ..)` traces the deletion algorithm.
Top-down's preventive `td-pre-fix-attention` frame outlines a 1-key
descent target before the fix; subsequent `td-borrow-left` /
`td-borrow-right` / `td-merge` frames carry out the rotation or merge.
Internal-key deletions visit a `td-target` highlight, swap with the
predecessor (`td-pred-swap`), then continue the descent to remove the
predecessor's old value from its leaf.

#align(center, starling.stacked((b24-tour.delete-display)(15)))

== Traversals

The four traversal animations sample the op-theme's
`traversal-palette` across the per-compartment visit order — each
visited compartment gets a fill from the gradient and the caption
accumulates the output sequence. In-order on a 2-3-4 tree threads
keys with their flanking subtrees (child[0], key[0], child[1], key[1],
…, child[k]); pre- and post-order group all of a node's keys at the
node-visit point.

#align(center, starling.last((b24-tour.in-order-display)()))

= Graph animations tour

The `Graph` class is the first non-tree structure in starling: an
undirected-or-directed weighted graph for teaching minimum spanning
trees (Prim and Kruskal), Dijkstra's shortest paths, and breadth- and
depth-first traversals. It rides the same `Frame` / op-theme /
render-theme stack as the trees, so every render helper, theming knob,
and touying composition works unchanged. There is no per-DS theme —
animation strokes come from the op-theme, structural defaults from the
render theme.

Unlike trees, graphs have no root and no path-from-root, so node
identity is a plain string id and edges are keyed by
#raw("edge-key(u, v, directed:)") (sorted `"u--v"` when undirected,
`"u->v"` when directed). The renderer (`graph-draw.typ`, the
`draw-graph` backend) is split from the `Graph` class (`graph.typ`,
data plus algorithms) exactly as `draw-tree` is split from the tree
classes — both inject their backend into the shared `Renderer` in
`anim-core.typ`.

== Construction and layout

Layout is decoupled from rendering: the `Graph` carries node positions
(in cetz units) and the renderer simply draws nodes there. The
#raw("graph(..)") factory takes placed nodes and weighted edges:

```typ
#let g = graph(
  (("A", 0, 0), ("B", 3, 0.4), ("C", 1.5, 2.4), ("D", 4.5, 2.2)),
  edges: (("A", "B", 7), ("B", "C", 2), ("A", "C", 4),
          ("C", "D", 5), ("B", "D", 1)),
)
```

Both nodes and edges accept optional custom *labels* — text drawn in
place of the id (for a node) or the weight (for an edge). A node spec
is a bare id, an #raw("(id, label)") 2-tuple (label, no manual
position — pairs with `auto-layout`), an #raw("(id, x, y)") tuple, or
an #raw("(id, x, y, label)") tuple. An edge's third slot dispatches by
type: a *number* is the weight, a *string or content* is a label drawn
in its place; an #raw("(u, v, weight, label)") 4-tuple sets both — the
numeric weight still drives Dijkstra and the MSTs while the label is
what's shown.

```typ
#let g = graph(
  ("A", ("B", [Server]), ("C", 1.5, 2.4)),  // B is auto-laid-out
  edges: (
    ("A", "B", 7),          // weight 7
    ("B", "C", [TLS]),       // label "TLS", no weight shown
    ("A", "C", 4, [4 ms]),   // weight 4 for algorithms, shown as "4 ms"
  ),
)
```

#let g-tour = starling.graph(
  (("A", 0, 0), ("B", 3, 0.4), ("C", 1.5, 2.4), ("D", 4.5, 2.2)),
  edges: (
    ("A", "B", 7),
    ("B", "C", 2),
    ("A", "C", 4),
    ("C", "D", 5),
    ("B", "D", 1),
  ),
)

Hand-placement is the first-class path — small teaching graphs read
best when you control the layout. For larger graphs, the optional
`auto-layout` helper (below) computes positions with graphviz.

Every display method takes a `scale:` factor (default `1`) that
multiplies all node coordinates about the origin, spreading the nodes
apart while their drawn size — circles, labels, edge weights — stays
fixed. It's the manual-layout analog of `auto-layout`'s `unit:`: reach
for it when a hand-placed graph is too cramped (e.g. on a wide slide)
without wanting to rescale the whole figure or edit every coordinate.

```typ
#last((g.display)(scale: 1.6))           // 1.6× the gaps, same node size
#last((g.dijkstra-display)("A", scale: 1.4))
```

To instead resize the *whole* figure — nodes, spacing, and text
together — wrap the result in Typst's `scale`:
#raw("#scale(140%, reflow: true, last((g.display)()))").

== Static display

`(g.display)()` returns a one-frame array. Edge weights are drawn at
each edge midpoint; a directed graph gets arrowheads.

#align(center, starling.last((g-tour.display)()))

== Tabular representations

Besides the drawn graph, `(g.adjacency-matrix)()` and
`(g.adjacency-list)()` render the structure as plain Typst tables — no
cetz, no animation. Unlike the `*-display` methods they return
*placeable content directly* (not an `Array(Frame)`), so drop them
straight into the document; wrap them in a `figure` yourself if you want
a caption or alt text. Both still honor the render theme — header cells
take the node fill and a bold node-text-fill, the rules the node stroke.

By default the matrix shows 1/0 *presence* and the list shows bare
neighbor ids. Pass `weights: true` to show each edge's display label
instead (its label if set, else its numeric weight); the matrix then
marks non-edges with `none-marker` (`·`) and the list appends the weight
in parentheses:

#grid(
  columns: (1fr, 1fr),
  align: horizon + center,
  (g-tour.adjacency-matrix)(weights: true),
  (g-tour.adjacency-list)(weights: true),
)

For a *directed* graph the matrix is asymmetric — row = source, column =
target — and the list gives each node's out-neighbors (a sink shows the
`empty-marker`, `—`). An undirected graph gives a symmetric matrix and
lists every incident neighbor. A self-loop lands on the matrix diagonal
and appears once in the list. Absent matrix cells (the `0`s or
`none-marker`) and empty rows are drawn muted so the populated entries
read first.

// Lay each frame out as its canvas beside its aux strip, one row per
// frame stacked down the page (so a long MST animation doesn't overflow
// horizontally the way the BFS `aux-row` would).
#let aux-rows(frames) = stack(
  dir: ttb,
  spacing: 0.8em,
  ..frames.map(f => grid(
    columns: (auto, auto),
    column-gutter: 1.5em,
    align: horizon,
    starling.canvases-only((f,)).first(),
    starling.aux-strip(f.step),
  )),
)

== Prim's minimum spanning tree

`(g.mst-prim-display)(start)` grows the tree from `start`. Each
selection shows the frontier (crossing edges in the search stroke) with
the lightest edge picked out in the attention stroke, then commits it
to the tree (success stroke) and settles the newly reached node. The
caption tracks the running tree weight. A terminal *prune* frame then
hides every non-tree edge, so the animation ends on the spanning tree
alone (the same close as BFS/DFS `spanning-tree` mode).

#align(center, starling.stacked((g-tour.mst-prim-display)("A")))

Prim's bookkeeping is a *priority queue* of the crossing edges, and
`aux-strip(frame.step)` renders it beside the canvas — the candidate
edges stacked vertically (a queue's natural orientation, and it stays
narrow when the frontier is wide), sorted by weight with the `min` on
top and the chosen edge ringed in the attention stroke, so the pop is
legible step by step. Here are the two selection rounds where the
frontier reorders:

#align(center, aux-rows((g-tour.mst-prim-display)("A").slice(1, 4)))

== Kruskal's minimum spanning tree

`(g.mst-kruskal-display)()` considers edges in weight order, adding
each unless it would join two nodes already in the same component (a
cycle, drawn in the danger stroke). The union-find forest is shown by
*node color*: same color means same set, and colors merge as the
components do — no extra dependency, and robust to any layout. As with
Prim, a terminal *prune* frame hides the non-tree edges to finish on the
spanning tree.

#align(center, starling.stacked((g-tour.mst-kruskal-display)()))

Kruskal carries *two* auxiliary structures, and `aux-strip(frame.step)`
stacks both: the sorted edge list — every edge in weight order, a cursor
(▲) under the one being considered, each tagged added / rejected /
pending — and the disjoint-set partition (one bordered group per
component, merging as edges are added). The edge labels are stacked
vertically (endpoints over the weight) so the list stays compact even
with many edges. A committed edge (three components remain) and a later
cycle-rejected edge (all merged):

#let kruskal-frames = (g-tour.mst-kruskal-display)()
#align(center, aux-rows((kruskal-frames.at(2), kruskal-frames.at(8))))

Pass `view:` to render just one of them for separate placement — e.g.
`aux-strip(frame.step, view: "partition")` for the components alone.

== Dijkstra's shortest paths

`(g.dijkstra-display)(source, target: ..)` carries each node's
tentative distance in its note slot (∞ until reached). Each round
finalizes the nearest unvisited node (attention stroke, then settled),
relaxes its outgoing edges (search stroke, updating distances), and
grows the shortest-path tree in the success stroke. With a `target`
the search stops early and the path is highlighted. It works on
directed graphs:

#let dg-tour = starling.graph(
  (("S", 0, 0), ("A", 2.5, 1.2), ("B", 2.5, -1.2), ("T", 5, 0)),
  edges: (
    ("S", "A", 1),
    ("S", "B", 4),
    ("A", "B", 1),
    ("A", "T", 5),
    ("B", "T", 1),
  ),
  directed: true,
)

#align(center, starling.stacked((dg-tour.dijkstra-display)("S", target: "T")))

== Traversals

`(g.bfs-display)(start)` and `(g.dfs-display)(start)` sample the
op-theme's `traversal-palette` across the visit order — each visited
node gets a fill from the gradient and a 1-indexed badge, and the
caption accumulates the visit sequence (the same pattern as the tree
`*-order-display` methods). The final frame wears the full visit
signature:

#grid(
  columns: (1fr, 1fr),
  align: center,
  starling.last((g-tour.bfs-display)("A")),
  starling.last((g-tour.dfs-display)("A")),
)

Pass a `target:` node id to either method to turn the traversal into a
*search* that stops the moment the target is visited (mirroring
`dijkstra-display`'s `target:`). The visit gradient builds up only over
the nodes examined before the target, and a terminal frame states the
outcome: on success the target gains a `settled-stroke` ring and a
`Found <t>` caption; if the target is unreachable the search visits the
whole reachable component and ends with a `<t> not found` frame.

#align(center, starling.stacked((g-tour.bfs-display)("A", target: "D")))

By default each node's neighbours enter the queue / stack in
edge-declaration order. Pass `sort-frontier: true` to instead visit them
in ascending node-id order — a lexicographic string sort, so `"A"`
before `"B"` and `"0"` before `"1"` — giving a deterministic traversal
that doesn't depend on the order edges were added. (Being lexicographic,
`"10"` sorts before `"2"`; single-character ids sort as expected.)

=== Spanning trees

Pass `spanning-tree: true` to either method to render the *traversal
tree* rather than the palette walk. Instead of shading nodes across the
`traversal-palette`, each node joins the tree with a uniform commit style
(`success-fill` + `settled-stroke`) and its *discovery edge* — the edge
from the node that first reached it — lights up in `success-stroke`. The
highlighted edges accumulate into the BFS / DFS spanning tree of the
reachable component (the same visual vocabulary as `mst-prim-display`,
just committing edges in traversal order rather than by weight). Combine
with `sort-frontier: true` to pin the tree's shape deterministically. The
mode spans the whole reachable component, so it doesn't take a `target:`.
A final frame then prunes every non-tree edge — hiding the cross edges
and their weights — so the animation ends on the spanning tree by itself
(that terminal frame is what `last` shows below).

#grid(
  columns: (1fr, 1fr),
  align: center,
  starling.last((g-tour.bfs-display)("A", spanning-tree: true)),
  starling.last((g-tour.dfs-display)("A", spanning-tree: true)),
)

=== Tracking the queue / stack

BFS and DFS are driven by a helper structure — a FIFO queue and a LIFO
stack respectively — and a common sticking point for students is
tracking its contents step by step. Every `bfs-display` / `dfs-display`
frame records that structure's state in its `step` metadata, and
`aux-strip(frame.step)` renders it as a placeable strip of boxes (the
front and rear ends marked on a queue, the `top` push/pop end on a
stack). The same `aux-strip` helper also serves the MST displays (the
Prim frontier and the two Kruskal views, above); it dispatches on the
kind of auxiliary state each `step` carries. It returns
ordinary content, not a `Frame`, so you lay it out wherever you want —
this is deliberately decoupled from the graph canvas so a touying slide
can put the graph on one side and the strip on the other:

```typ
#let frames = (g.bfs-display)("A")
#grid(
  columns: (2fr, 1fr),
  alternatives(..starling.canvases-only(frames)),
  alternatives(..frames.map(f => aux-strip(f.step))),
)
```

Statically, pairing each canvas with its strip shows the queue draining
and refilling across the traversal:

#let aux-row(frames) = grid(
  columns: frames.len(),
  column-gutter: 1em,
  align: center + top,
  ..frames.map(f => stack(
    dir: ttb,
    spacing: 0.5em,
    starling.canvases-only((f,)).first(),
    starling.aux-strip(f.step),
  )),
)

#align(center, aux-row((g-tour.bfs-display)("A")))

The DFS stack is shown *faithfully*: because the iterative algorithm can
push a node before an earlier copy is popped, the same id may appear
twice in the strip — exactly the state a hand-trace would produce. Pass
a `labels:` `(id -> content)` map to `aux-strip` when your nodes carry
custom display labels.

== Node shapes and sizing

The default circular node is sized for short ids. Longer labels — names,
words, multi-character keys — overflow it. Pass a `node-style:` dict to
any display to restyle *every* node at once; it sits beneath the
per-frame algorithm styling, so shape and size persist while fills and
strokes animate on top.

- `shape` accepts `"circle"` (default), `"ellipse"`, or
  `"rectangle"`/`"square"`.
- `autosize: true` fits the node to its own label (measured at render
  time), so each node is exactly as wide as it needs to be.
- For a fixed size, set `rx`/`ry` (ellipse / rectangle half-extents) or
  `r` (circle radius) in cetz units instead, plus `pad-x`/`pad-y` to
  loosen or tighten an autosize fit.

Edges trim to whatever boundary the shape defines, so arrowheads and
edge ends stay flush against a wide ellipse just as they do a circle.

#let g-people = starling.graph(
  (
    ("A", 0, 0, [Alice]),
    ("B", 3, 0, [Bob]),
    ("C", 1.5, 2.4, [Charlie]),
    ("D", 4.5, 2.4, [Dan]),
  ),
  edges: (("A", "B", 1), ("A", "C", 1), ("B", "C", 1), ("B", "D", 1), ("C", "D", 1)),
)

#align(center, starling.last((g-people.display)(
  node-style: (shape: "ellipse", autosize: true),
)))

== Optional auto-layout with graphviz

For graphs too large to place by hand, `auto-layout` computes positions
with graphviz via the `diagraph-layout` package — a WASM build, so no
external binary is needed. It is re-exported from the package entrypoint
alongside everything else, so import it the same way and feed its result
to any display via the `positions:` argument:

```typ
#import "@preview/starling:0.3.0": graph, auto-layout, last

// Position-less graph — bare ids, no coordinates.
#let g = graph(("A", "B", "C"), edges: (("A", "B", 7), ("B", "C", 2)))
#last((g.mst-prim-display)("A", positions: auto-layout(g)))
```

Or skip the intermediate map entirely: pass `layout: <engine>` to any
display and it runs `auto-layout` for you, internally. Because the
display knows the node labels, it feeds graphviz a per-node size
estimate so wide labels get spread apart (and sets `overlap=false` so
the force-directed engines honor those sizes rather than stacking
nodes). This keeps the graph inline at the call site and removes the
chance of pairing a positions map with the wrong graph:

```typ
#last((g.display)(
  node-style: (shape: "ellipse", autosize: true),
  layout: "neato",          // the display calls auto-layout itself
))
```

That size estimate is a cheap label-length heuristic computed *without*
`measure`, whereas the drawn node is measured exactly — so the two only
approximate each other. Graphviz's node margins absorb most of the
slack; if spacing still looks off, spread the graph with the display's
`scale:` or tighten/loosen it with `layout-unit:` (the per-unit point
scale, mirroring `auto-layout`'s `unit:`). `layout:` defaults to `none`,
in which case the display uses `positions:` and `diagraph-layout` is
never touched.

Despite being on the `import starling` path, `diagraph-layout` stays an
*optional* dependency: `auto-layout` carries its `diagraph-layout`
import inside its own body, which Typst resolves lazily — only when the
function is actually called (whether directly or through a display's
`layout:` argument). Projects that only hand-place graphs never pull it
in. (Typst has no subpath package import, so re-exporting from the
entrypoint is the only way to reach `auto-layout`; the older
`@preview/starling:<ver>/src/graph-layout.typ` form never worked.)

= Hash map animations tour

A `HashMap` is a fixed-length array of `capacity` slots. Keys are placed
by a *pluggable hash function* `(key, m) => index`, and collisions are
resolved by one of four strategies chosen at construction:

- `"chaining"` — separate chaining; each slot holds a linked list of
  entries.
- `"linear"` — open addressing; on a collision probe `(h + i) mod m`.
- `"quadratic"` — open addressing; on a collision probe `(h + i*i) mod m`.
- `"double"` — open addressing; on a collision probe
  `(h1 + i * h2) mod m`, taking the step size from a *second* hash `h2`.

Unlike the trees and graphs, a hash table has no per-node layout to
supply — the array geometry is fixed — so the display methods take only
an `orientation:` (`"horizontal"`, the default, or `"vertical"`) and a
`scale:`, alongside the usual `theme:` / `render-theme:`.

== Construction

Build one with the `hashmap(..)` factory. `entries:` seeds the table by
inserting each item in order (a bare key, or a `(key, value)` pair):

```typ
#let h = hashmap(5, strategy: "chaining", entries: (5, 10, 7, 3, 8, 13))
```

The hash function and the formula shown on screen are both configurable.
`hash:` is any `(key, m) => index`; `hash-repr:` is its display form,
with `k` (the key) and `m` (the capacity) substituted as whole words —
so write them as standalone tokens (`"k mod m"`, `"(k * 31) mod m"`),
not glued to a coefficient (`"3k"` would not substitute the `k`). The
default is the division method `k mod m`. Double hashing takes a second
pair, `hash2:` / `hash2-repr:`, for the probe step (default
`1 + (k mod (m - 1))`, which stays nonzero and — when `m` is prime —
coprime to `m`, so the probe visits every slot).

```typ
#let h = hashmap(
  8,
  strategy: "linear",
  hash: (k, m) => calc.rem(k * 3, m),
  hash-repr: "(k * 3) mod m",
)
```

== Static display

`display()` renders the current table as a single frame. Empty slots are
muted; a bucket's chain hangs below it; a deleted open-addressing slot
shows a tombstone (`×`).

#align(center, starling.last(
  (starling.hashmap(5, strategy: "chaining", entries: (5, 10, 7, 3, 8, 13)).display)(),
))

The same table in `orientation: "vertical"` runs the array top-to-bottom
(a memory-diagram look) with chains extending rightward.

Entries carry both a key and an optional value: an inserted `(key, value)`
pair (or `insert(key, value: ..)`) renders the value as a smaller second
line under the key. By default the display methods *fit* each cell (and,
for chaining, each entry box) to the widest label, so a wide label such as
`(k1, v1)` — here set explicitly on each entry — is never clipped:

#{
  let h = starling.hashmap(5, strategy: "linear")
  let h = (h.insert)(3, value: "v1", label: "(k1, v1)")
  let h = (h.insert)(8, value: "v2", label: "(k2, v2)")
  align(center, starling.last((h.display)()))
}

The sizing is controlled by each display method's `cell-width:` argument:
`"fit"` (the default) measures the labels and grows the cells to fit — in
*both* width and height, so chaining entries stay legible at the larger
font sizes of a slide deck (floored at the historical size, so numeric
tables at the default font are unchanged); a number pins an exact cell
width in cetz units; and `auto` keeps the fixed historical footprint
without measuring — useful when you know the labels are short and want to
skip the measurement pass. On the `positioned(..)`
entry point (for hand-composed cetz canvases) `cell-width:` defaults to
`auto`, since that path may render outside a layout context where `"fit"`
cannot `measure`.

== Hash functions and the hash box

Every `insert` / `search` / `delete` opens by computing the hash. The
animation draws a *hash box* — `h(<key>) = <formula> = <index>` — above
the target slot with an arrow pointing at it, so the mapping from key to
bucket is explicit before any probing begins.

The opening frame (before the hash box appears) invisibly reserves the
box's footprint, so all of the walk frames render at the same canvas size
and the table doesn't jump when the box appears on the next subslide. Give
the canvas a `top` alignment in your deck and the whole animation stays
pinned in place.

== Separate chaining

Insertion hashes to a bucket, walks the existing chain comparing keys
(so a repeated key updates in place), and appends a new entry at the
tail:

#align(center, starling.stacked(
  (starling.hashmap(5, strategy: "chaining", entries: (5, 10, 7)).insert-display)(20),
))

== Linear probing

Open addressing keeps every entry in the array itself. On a collision,
linear probing steps to the next slot, `(h + i) mod m`, until it finds a
free one:

#align(center, starling.stacked(
  (starling.hashmap(7, strategy: "linear", entries: (14, 21, 7)).insert-display)(28),
))

== Quadratic probing

Quadratic probing spreads the probes out as `(h + i*i) mod m`, which
reduces the primary clustering linear probing suffers. The trade-off is
that the probe sequence visits only a subset of the slots: with these
parameters it can report the table "full" for a key even while empty
slots remain — a genuine teaching point, surfaced as a terminal *table
full* frame.

#align(center, starling.stacked(
  (starling.hashmap(7, strategy: "quadratic", entries: (0, 7, 14)).insert-display)(21),
))

== Double hashing

Double hashing keeps the entries in the array like the other open
schemes, but the *step size* between probes comes from a second hash
`h2(key)` rather than a fixed pattern — so two keys that collide at the
same home slot generally walk different slots afterwards, avoiding the
clustering of linear probing. The hash box shows both hashes: `h₁` (the
home slot) and `h₂` (the step).

#align(center, starling.stacked(
  (starling.hashmap(7, strategy: "double", entries: (14, 21, 7)).insert-display)(28),
))

== Search

`search-display` walks the same probe/chain sequence and ends on a hit
(a settled ring) or a miss. Crucially, open-addressing search *stops at
the first empty slot* but *steps over tombstones* — a lookup for a key
whose slot sits past a deleted entry still finds it:

#align(center, starling.stacked(
  ((starling.hashmap(7, strategy: "linear", entries: (14, 21, 7)).delete)(21).search-display)(7),
))

A chaining miss walks to the end of the bucket and rings a *phantom*
"null" cell hung one past the last entry — the slot the search fell off
the chain into — rather than the (keyless) bucket header:

#align(center, starling.stacked(
  (starling.hashmap(5, strategy: "chaining", entries: (5, 10, 7, 3, 8)).search-display)(15),
))

== Deletion and tombstones

Deletion is where the two collision families diverge. Chaining simply
unlinks the entry and re-links the chain. Open addressing cannot blank
the slot — that would truncate probe sequences that run through it — so
it writes a *tombstone* (`×`) that search skips and insert may reuse:

#align(center, starling.stacked(
  (starling.hashmap(7, strategy: "linear", entries: (14, 21, 7)).delete-display)(21),
))

To *demonstrate why* that matters, `delete` and `delete-display` take
`tombstone: false` — the naive open-addressing deletion that clears the
slot to empty instead of tombstoning it. It's deliberately buggy: here
14, 21 and 7 all hash to slot 0, so clearing 21 (slot 1) severs the
probe chain, and a later search for 7 stops at the now-empty slot and
wrongly reports a miss — even though 7 is still in slot 2. Keep the
default (`tombstone: true`) in real code; the flag is a no-op for
chaining, which has no tombstones.

#align(center, starling.stacked(
  (starling.hashmap(7, strategy: "linear", entries: (14, 21, 7)).delete-display)(21, tombstone: false),
))

#let broken = (starling.hashmap(7, strategy: "linear", entries: (14, 21, 7)).delete)(21, tombstone: false)
#align(center, starling.stacked((broken.search-display)(7)))

== Resizing and rehashing

`resize-display(new-cap)` allocates a larger array and replays every
live entry through the hash under the new capacity, one entry per frame
— so the load factor drops and old collisions frequently scatter apart:

#align(center, starling.stacked(
  (starling.hashmap(7, strategy: "linear", entries: (14, 21, 7, 3)).resize-display)(11),
))

To *demonstrate why* the rehash matters, `resize` and `resize-display`
take `rehash: false` — the naive resize that grows the array but copies
each entry into its *old* index instead of hashing it again (no hash box
is shown, because nothing is hashed). It's deliberately buggy: 14, 21 and
7 land back in slots 0, 1, 2, but the array is now length 11, so
`h(7) = 7 mod 11 = 7` — a later search for 7 probes the empty slot 7 and
wrongly reports a miss even though 7 is still sitting in slot 2. Keep the
default (`rehash: true`) in real code. (`rehash: false` requires
`new-cap >= capacity` so the old indices still fit.)

#align(center, starling.stacked(
  (starling.hashmap(7, strategy: "linear", entries: (14, 21, 7)).resize-display)(11, rehash: false),
))

#let stale = (starling.hashmap(7, strategy: "linear", entries: (14, 21, 7)).resize)(11, rehash: false)
#align(center, starling.stacked((stale.search-display)(7)))

== Theming

The hash map reuses the render theme (structural colours) and the op
theme (probe/landing/miss strokes) unchanged, and adds its own palette,
`default-hashmap-theme`, for what's intrinsic to a table: `empty-fill`,
`index-fill`, `hash-box-fill`, `hash-box-stroke`, `tombstone-fill`,
`tombstone-stroke`, `chain-stroke`, and `chain-fill`. Override it
document-wide with `set-hashmap-theme(..)` or per call with the
`theme:` argument (the per-call form skips the state read — see
@theming-perf).

A per-call override (shown here, scoped so it doesn't leak into the rest
of the manual) recolours a single display:

#align(center, starling.last(
  (starling.hashmap(5, strategy: "chaining", entries: (5, 10, 7, 3)).display)(
    theme: (empty-fill: rgb("#eef3ff"), index-fill: rgb("#3355aa")),
  ),
))

= Git graph

The `git-graph` DSL draws git commit graphs — commits, branches, merges,
tags, and HEAD/branch pointers. It is the one part of starling that does
*not* ride the `Frame` / `Renderer` / `*-display` stack: rather than an
immutable structure animated step by step, it is a *stateful, imperative
cetz builder*. You call `commit` / `branch` / `merge` inside a
`git-graph({ .. })` block and the commands mutate cetz's canvas context
as they draw. Consequently the frame helpers (`last`, `stacked`,
`figures`) do not apply here — you place a `git-graph` block directly
inside a `cetz.canvas(..)`. Animation is touying-native instead: put
`pause` / `alternatives(..)` markers inside the canvas body, or redraw a
commit dot with `git-highlight`.

Because its verbs use generic names (`commit`, `branch`, `merge`, `tag`,
`checkout`), they live behind a `git` namespace rather than being
re-exported flat, so `import starling: *` never collides with them:

```typ
#import "@preview/cetz:0.5.2"
#import "@preview/starling:0.3.0" as starling
#import starling: git

#cetz.canvas(git.git-graph({
  git.branch("main")
  git.commit("init")
  git.commit("work")
  git.branch("dev")
  git.commit("feature")
  git.checkout("main")
  git.commit("main work")
  git.merge("dev", message: "merge dev")
  git.branch-pointer("main")
  git.head-pointer()
  git.tag("v1.0")
}))
```

#align(center, cetz.canvas(starling.git.git-graph({
  starling.git.branch("main")
  starling.git.commit("init")
  starling.git.commit("work")
  starling.git.branch("dev")
  starling.git.commit("feature")
  starling.git.checkout("main")
  starling.git.commit("main work")
  starling.git.merge("dev", message: "merge dev")
  starling.git.branch-pointer("main")
  starling.git.head-pointer()
  starling.git.tag("v1.0")
})))

You must create the initial branch (`branch("main")`) before the first
`commit`. `merge(branch)` takes the *branch name* to merge in; `commit`,
`branch`, and `merge` accept a `name:` so later annotations survive
reordering. `detached-commit(from, msg, name)` draws an orphan dot and
`head-pointer(target: name)` hangs a detached HEAD off it.

Pass `direction: "left-to-right"` to `git-graph` to lay commits out
rightward (lanes spread downward) instead of the default upward stacking;
sensible label angles/anchors switch automatically.

== Theming the git graph

git-graph carries its own per-DS theme, `default-git-theme`, exactly like
the RBT palette (see @theming). Its keys are the branch `colors` palette
and the `lane-style` / `graph-style` / `commit-style` / `tag-style` /
`pointer-style` sub-dicts. Override document-wide with `set-git-theme(..)`
or per-call with `git-graph(theme: (..))`:

```typ
// Document-wide (state — persists for the rest of the document):
#starling.set-git-theme((graph-style: (stroke: (thickness: 0.4em), radius: 0.15)))

// Per-call (bypasses state entirely — the perf escape hatch):
#cetz.canvas(git.git-graph(
  theme: (colors: (teal, maroon, olive)),
  { git.branch("main"); git.commit("a"); .. },
))
```

Merging is *shallow* at the top level: overriding `commit-style` replaces
the whole sub-dict, so pass a complete style dict for the role you change.
As elsewhere in starling, the state path costs an extra layout pass (see
@theming-perf) — prefer the per-call `theme:` argument on hot paths.

= Theming <theming>

Starling exposes three theme layers so document authors can match
starling's palette to their own document style:

- *Render theme* (#raw("default-render-theme")) — the structural
  defaults the renderer falls back on for the unstyled tree:
  `node-fill`, `node-stroke`, `node-text-fill`, `edge-stroke`,
  `note-fill`.
- *Op theme* (#raw("default-op-theme")) — the operation-semantic
  colors and strokes that any data structure's `*-display` methods use
  to communicate operation state: `search-stroke`, `attention-stroke`,
  `success-stroke`, `settled-stroke`, `success-fill`, `danger-stroke`,
  `reset-stroke`, `traversal-palette`. Shared across data structures —
  BST search, RBT search, and a future heap delete all read the same
  `search-stroke`. Strokes are full stroke dicts
  (`(paint:, thickness:, dash:)`) so any aspect — color, width, dash —
  is overridable without adding more keys.
- *Per-DS theme* — styling intrinsic to one data structure. RBT has
  #raw("default-rbt-theme") with `red-fill`, `red-stroke`,
  `red-text-fill`, `black-fill`, `black-stroke`, `black-text-fill` for
  the red/black palette. BST has no per-DS theme of its own because
  BST nodes carry no intrinsic styling.

== Setting a theme for the whole document

Call any combination of `set-render-theme`, `set-op-theme`, and the
per-DS setters (e.g. `set-rbt-theme`) once near the top of your
document. Each override is state-based and scoped by Typst's normal
layout flow, so it propagates to every subsequent `*-display` call.

```typ
#import "@preview/starling:0.1.0": BST, set-op-theme, set-render-theme

#set-op-theme((
  search-stroke: (paint: teal, thickness: 2.5pt),
  success-stroke: (paint: olive, thickness: 2.5pt),
  settled-stroke: (paint: olive, thickness: 3.5pt),
  success-fill: olive.lighten(75%),
))
#set-render-theme((node-fill: yellow.lighten(85%)))
```

Pass a partial dictionary — only the keys you list are changed.
Unknown keys panic so typos surface immediately rather than silently
falling back to defaults.

== Per-call overrides

For one-off variations, every `*-display` method accepts `theme:`
and `render-theme:` arguments. A partial dict is merged into the
defaults and used in place of the state value for that call only.

```typ
(t.search-display)(6, theme: (search-stroke: (paint: olive, thickness: 2pt)))
```

== Performance: state-based theming costs a layout pass <theming-perf>

Typst's state machinery is what makes `set-op-theme` / `set-render-theme`
work: a `state.update` later in the document can affect renders earlier
in document order, so Typst evaluates the document, propagates state,
and re-evaluates anything that observed it. In practice that means
*using either state setter roughly doubles the compile time of the
state-observed portion of the document* — a small fixed cost on top of
each tree, plus a full extra layout pass through everything that placed
a starling render helper or rendered a frame's `render` builder against
that state.

Concretely, a 50-tree synthetic benchmark goes from ~1.85s to ~3.1s
when `set-op-theme` is added. The cost scales with document size, not
with the number of state reads (one read or a thousand is the same),
because the price is "Typst does a second layout pass", not "the read
is slow".

This is a structural property of Typst's state model, not something
starling can work around without giving up state. If compile speed
matters more than the ergonomic win, hoist your theme dict into a
plain `let` and pass it to each `*-display` call via the per-call
`theme:` argument — that path skips state entirely and runs at the
no-state baseline:

```typ
#let palette = (
  search-stroke: (paint: teal, thickness: 2.5pt),
  success-stroke: (paint: olive, thickness: 2.5pt),
  // ...
)

#starling.stacked((t.search-display)(6, theme: palette))
#starling.stacked((t.insert-display)(5, theme: palette))
// ...
```

This is the usual perf/ergonomics tradeoff: `set-op-theme` is one
declaration at the top of the document and "just works"; per-call
`theme:` is more typing but avoids the extra pass.

= Touying composition examples

Starling is layout-agnostic. In a touying deck, the simplest use
splats `figures` into `alternatives`:

```typ
#import "@preview/touying:0.7.3": *
#import "@preview/starling:0.2.0" as starling
#import starling: BST

== Searching
#alternatives(..starling.figures((t.search-display)(6)))
```

Each frame becomes a subslide; touying handles the rest.

== Captions in a sidebar

When the visual animation should sit alongside synchronised text
elsewhere on the slide, pull the captions out separately:

```typ
== Searching for 6
#let frames = (t.search-display)(6)
#grid(columns: 2, column-gutter: 2em,
  alternatives(..starling.figures(frames, caption: false)),
  alternatives(..frames.map(f => f.caption)),
)
```

Both `alternatives` calls produce the same number of subslides, so
they step in lockstep.

== A live queue / stack beside the graph

For BFS and DFS, `aux-strip` turns each frame's helper structure into a
strip you can place anywhere on the slide. Drive three `alternatives`
off the same frame array — the graph canvas, the queue strip, and the
caption — and they share one subslide count, so the whole slide advances
together as you step through it:

```typ
== Breadth-first search
#let frames = (g.bfs-display)("A")
#grid(columns: (2fr, 1fr), column-gutter: 2em, align: horizon,
  alternatives(..starling.canvases-only(frames)),
  stack(dir: ttb, spacing: 1.2em,
    alternatives(..frames.map(f => starling.aux-strip(f.step))),
    alternatives(..frames.map(f => f.caption)),
  ),
)
```

Each `alternatives` child here is independent content (the strip and the
canvas resolve their own theme state), which is exactly what touying
wants — the layout-time `alternatives` mark sits *outside* every
`context` block, never inside one. Swap `bfs-display` for `dfs-display`
to watch the stack instead; the duplicate entries it shows are faithful
to the iterative algorithm.

== Driving layout from step metadata

`frame.step` is free-form per-method metadata. For example, a slide
that wants to colour-code its narration by step kind:

```typ
#let kind-colors = (compare: blue, inserted: green)

#let captioned-frames = frames.map(f => figure(context {
  let op = starling._op-theme-state.get()
  let rt = starling._render-theme-state.get()
  let color = kind-colors.at(f.step.kind, default: black)
  stack(dir: ttb, spacing: 0.5em,
    (f.render)(op, rt), text(fill: color, f.caption))
}))

#alternatives(..captioned-frames)
```

#raw("frame.render") is a builder #raw("(op, rt) => content") rather
than pre-baked content, so themes resolve at layout time. The
#raw("context") block above reads the active themes and feeds them
in; if you don't need state-driven theming, you can call
#raw("(f.render)(starling.default-op-theme, starling.default-render-theme)")
without the wrapper.

= Composing with cetz annotations <composing-with-cetz-annotations>

For callouts or overlays that need to track specific nodes, drop down
to the cetz layer. `draw-tree(tree, snapshot, ...)` emits the tree's
cetz drawables without wrapping them in `cetz.canvas`, so you can
compose them with your own draw commands in a shared canvas.
`path-anchor(path)` translates an L/R path string to the cetz anchor
name of the corresponding node.

```typ
#import "@preview/cetz:0.5.2"

#cetz.canvas({
  starling.draw-tree(t, starling.blank-snapshot())
  import cetz.draw: *
  circle(starling.path-anchor("LR"), radius: 0.85, stroke: red + 2pt)
})
```

#align(center, cetz.canvas({
  starling.draw-tree(tour, starling.blank-snapshot())
  import cetz.draw: *
  circle(starling.path-anchor("LR"), radius: 0.85, stroke: red + 2pt)
}))

The same trick combines with frame canvases: each frame's `canvas` is
itself a `cetz.canvas` block, so for static "annotate the final
frame" use you can either render once via `draw-tree` (as above) or
extract the cetz block from a frame and add to it externally.

Graphs and hash maps expose the same escape hatch. `draw-graph` /
`draw-hashmap` emit drawables without a canvas, and each structure has
its own anchor helper: `node-anchor(id)` for a graph node,
`cell-anchor(i)` for a hash-map slot, and `entry-anchor(i, j)` for a
chaining entry (depth `j` of bucket `i`). Feed the renderer the
structure's positioned form — `(g.positioned)()` for a graph,
`(h.positioned)()` for a hash map (which also takes `orientation:` and
an optional `hash-box:`). Compass sub-anchors (`.north`, `.south`,
`.east`, `.west`) follow each shape's bounding box, so a callout can
track any face:

```typ
#let h = hashmap(5, strategy: "chaining", entries: (5, 10, 7, 3))
#cetz.canvas({
  starling.draw-hashmap((h.positioned)(), starling.blank-snapshot())
  import cetz.draw: *
  circle(starling.cell-anchor(2), radius: 0.8, stroke: red + 2pt)
  content(starling.entry-anchor(0, 1) + ".east", anchor: "west", [ ← tail])
})
```

#align(center, cetz.canvas({
  starling.draw-hashmap(
    (starling.hashmap(5, strategy: "chaining", entries: (5, 10, 7, 3)).positioned)(),
    starling.blank-snapshot(),
  )
  import cetz.draw: *
  circle(starling.cell-anchor(2), radius: 0.8, stroke: red + 2pt)
  content(starling.entry-anchor(0, 1) + ".east", anchor: "west", [ ← tail])
}))

= The Op command stream

For animations that don't fit the BST's built-in methods — say, a
custom hash-table probe sequence or a graph traversal — drop down to
the `Op` command stream. Build a sequence of declarative ops and fold
them into a renderer with `apply-ops`:

```typ
#let r = starling.make-renderer(t, sticky: true)
#let r = (r.with-caption)([start at root])
#let r = starling.apply-ops(r, (
  (starling.Op.Highlight.new)(path: "", color: blue),
  (starling.Op.Annotate.new)(path: "", text: [1 < 4]),
  (starling.Op.Commit.new)(
    alt: "Comparing the target 1 against the root 4.",
  ),
))
#let r = (r.with-caption)([descend left])
#let r = starling.apply-ops(r, (
  (starling.Op.ClearNotes.new)(),
  (starling.Op.Highlight.new)(path: "L", color: blue),
  (starling.Op.StyleEdge.new)(path: "L", style: (stroke: blue + 2pt)),
  (starling.Op.StyleNode.new)(path: "L", style: (fill: green.lighten(70%))),
  (starling.Op.Annotate.new)(path: "L", text: [1 = 1]),
  (starling.Op.Alt.new)(
    text: "Descended into the left subtree; 1 matches the left child.",
  ),
))
#starling.stacked((r.render)())
```

#let op-r = (starling.make-renderer)(tour, sticky: true)
#let op-r = (op-r.with-caption)([start at root])
#let op-r = (starling.apply-ops)(op-r, (
  (starling.Op.Highlight.new)(path: "", color: blue),
  (starling.Op.Annotate.new)(path: "", text: [1 < 4]),
  (starling.Op.Commit.new)(
    alt: "Comparing the target 1 against the root 4.",
  ),
))
#let op-r = (op-r.with-caption)([descend left])
#let op-r = (starling.apply-ops)(op-r, (
  (starling.Op.ClearNotes.new)(),
  (starling.Op.Highlight.new)(path: "L", color: blue),
  (starling.Op.StyleEdge.new)(path: "L", style: (stroke: blue + 2pt)),
  (starling.Op.StyleNode.new)(path: "L", style: (fill: green.lighten(70%))),
  (starling.Op.Annotate.new)(path: "L", text: [1 = 1]),
  (starling.Op.Alt.new)(
    text: "Descended into the left subtree; 1 matches the left child.",
  ),
))

#align(center, starling.stacked((op-r.render)()))

`Op.Commit` closes the current frame, attaches the supplied `alt` text
to it, and opens a fresh blank frame. The `alt` argument is required
so every frame the command stream produces carries accessible text.
The trailing in-progress frame is kept implicitly — no final
`Op.Commit` is needed — but use `Op.Alt(text)` (or `r.with-alt(...)`
on the returned renderer) to give that last frame its alt text too.

`Op.Caption` does _not_ exist; captions and step metadata are
renderer-level, set via `r.with-caption(...)` / `r.with-step(...)`
directly between Op batches. The split keeps each Op's responsibility
narrow (modifying the current snapshot) and matches how the
`*-display` methods are written internally.

== On a graph

The Op stream is structure-agnostic: an op's `path` is an opaque
string, so the same machinery drives a graph. Address nodes by their
id and edges by `edge-key(u, v)` (the canonical key the renderer uses
— sorted `"u--v"` when undirected, `"u->v"` when directed), and build
the renderer with `make-graph-renderer` over a positioned graph
instead of `make-renderer`. Everything else — `Op.Highlight`,
`Op.StyleEdge`, `Op.Annotate`, `Op.Commit` — is identical.

This is the escape hatch for animations the built-in MST / Dijkstra /
traversal displays don't cover. Here we trace a custom walk
A → C → D, coloring each node and edge and carrying the running cost
in the gold note slot (reusing the `g` from the graph tour above):

```typ
#let r = starling.make-graph-renderer((g.positioned)(), sticky: true)
#let r = (r.with-caption)([start at A])
#let r = starling.apply-ops(r, (
  (starling.Op.Highlight.new)(path: "A", color: blue),
  (starling.Op.Commit.new)(alt: "Start the walk at A."),
))
#let r = (r.with-caption)([A → C  (+4)])
#let r = starling.apply-ops(r, (
  (starling.Op.StyleEdge.new)(
    path: starling.edge-key("A", "C"), style: (stroke: blue + 2pt),
  ),
  (starling.Op.Highlight.new)(path: "C", color: blue),
  (starling.Op.Annotate.new)(path: "C", text: [4]),
  (starling.Op.Commit.new)(alt: "Follow edge A–C (weight 4); cost so far 4."),
))
#let r = (r.with-caption)([C → D  (+5)])
#let r = starling.apply-ops(r, (
  (starling.Op.StyleEdge.new)(
    path: starling.edge-key("C", "D"), style: (stroke: blue + 2pt),
  ),
  (starling.Op.Highlight.new)(path: "D", color: blue),
  (starling.Op.Annotate.new)(path: "D", text: [9]),
  (starling.Op.Alt.new)(text: "Follow edge C–D (weight 5); total cost 9."),
))
#starling.stacked((r.render)())
```

#let gop-r = starling.make-graph-renderer((g-tour.positioned)(), sticky: true)
#let gop-r = (gop-r.with-caption)([start at A])
#let gop-r = (starling.apply-ops)(gop-r, (
  (starling.Op.Highlight.new)(path: "A", color: blue),
  (starling.Op.Commit.new)(alt: "Start the walk at A."),
))
#let gop-r = (gop-r.with-caption)([A → C  (+4)])
#let gop-r = (starling.apply-ops)(gop-r, (
  (starling.Op.StyleEdge.new)(
    path: starling.edge-key("A", "C"), style: (stroke: blue + 2pt),
  ),
  (starling.Op.Highlight.new)(path: "C", color: blue),
  (starling.Op.Annotate.new)(path: "C", text: [4]),
  (starling.Op.Commit.new)(alt: "Follow edge A–C (weight 4); cost so far 4."),
))
#let gop-r = (gop-r.with-caption)([C → D  (+5)])
#let gop-r = (starling.apply-ops)(gop-r, (
  (starling.Op.StyleEdge.new)(
    path: starling.edge-key("C", "D"), style: (stroke: blue + 2pt),
  ),
  (starling.Op.Highlight.new)(path: "D", color: blue),
  (starling.Op.Annotate.new)(path: "D", text: [9]),
  (starling.Op.Alt.new)(text: "Follow edge C–D (weight 5); total cost 9."),
))

#align(center, starling.stacked((gop-r.render)()))

`edge-key` is exported from the package so user code can compute the
same key the renderer stores; for a directed graph pass
`directed: true` to match. Node and edge ids never collide because
they live in separate snapshot dictionaries, so `"A"` (a node) and
`"A--C"` (an edge) address different things.

`make-graph-renderer` takes a *positioned* graph, and `(g.positioned)()`
defaults to the graph's own stored coordinates. To drive a manual op
stream over a graphviz layout instead of hand-placed nodes, compute the
positions with `auto-layout` first and thread them through
`positioned`'s `positions:` argument before building the renderer — the
same seam the displays' `layout:` argument uses internally, done by
hand:

```typ
#let pos = starling.auto-layout(g, engine: "neato", sizes: auto)
#let r = starling.make-graph-renderer(
  (g.positioned)(positions: pos), sticky: true,
)
// ...then apply-ops exactly as above.
```

Pass `sizes: auto` so graphviz reserves room per node (it also sets
`overlap=false`) when the nodes are `autosize`d; tune absolute spacing
with `auto-layout`'s `unit:` or `positioned`'s `scale:`. Keeping this
`auto-layout` call explicit is what preserves its laziness — the manual
op-stream path never pulls `diagraph-layout` unless you make the call.

== On a hash map

The same escape hatch drives a hash map — reach for it to stage a probe
sequence the built-in `insert-display` / `search-display` don't cover
(a custom hash, a deliberately pathological collision run, a
side-by-side comparison). Build the renderer with `make-hashmap-renderer`
over `(h.positioned)()`, and address the structure with the *snapshot*
keys (distinct from the cetz anchors above): `cell-key(i)` for slot `i`,
and `entry-key(i, j)` for the chaining entry at depth `j` of bucket `i`.
`entry-key(i, j)` also keys the chain *link* into that entry, so
`Op.StyleEdge` recolors links. Everything else — `Op.Highlight`,
`Op.StyleNode`, `Op.Annotate`, `Op.Commit` — is identical.

Here we trace a linear-probing insert of 7 by hand, lighting each probed
slot and landing the key:

```typ
#let h = hashmap(7, strategy: "linear", entries: (14, 21))
#let r = starling.make-hashmap-renderer((h.positioned)(), sticky: true)
#let r = (r.with-caption)([h(7) = 0])
#let r = starling.apply-ops(r, (
  (starling.Op.Highlight.new)(path: starling.cell-key(0), color: blue),
  (starling.Op.Commit.new)(alt: "Probe slot 0; occupied by 14."),
))
#let r = (r.with-caption)([probe → slot 2])
#let r = starling.apply-ops(r, (
  (starling.Op.Highlight.new)(path: starling.cell-key(1), color: blue),
  (starling.Op.Highlight.new)(path: starling.cell-key(2), color: blue),
  (starling.Op.StyleNode.new)(
    path: starling.cell-key(2), style: (fill: green.lighten(60%)),
  ),
  (starling.Op.Alt.new)(text: "Slots 1 (occupied) then 2 (free): land at 2."),
))
#starling.stacked((r.render)())
```

#let hop-h = starling.hashmap(7, strategy: "linear", entries: (14, 21))
#let hop-r = starling.make-hashmap-renderer((hop-h.positioned)(), sticky: true)
#let hop-r = (hop-r.with-caption)([h(7) = 0])
#let hop-r = (starling.apply-ops)(hop-r, (
  (starling.Op.Highlight.new)(path: starling.cell-key(0), color: blue),
  (starling.Op.Commit.new)(alt: "Probe slot 0; occupied by 14."),
))
#let hop-r = (hop-r.with-caption)([probe → slot 2])
#let hop-r = (starling.apply-ops)(hop-r, (
  (starling.Op.Highlight.new)(path: starling.cell-key(1), color: blue),
  (starling.Op.Highlight.new)(path: starling.cell-key(2), color: blue),
  (starling.Op.StyleNode.new)(
    path: starling.cell-key(2), style: (fill: green.lighten(60%)),
  ),
  (starling.Op.Alt.new)(text: "Slots 1 (occupied) then 2 (free): land at 2."),
))
#align(center, starling.stacked((hop-r.render)()))

== Custom shapes and edge anchors

Two node-style and edge-style keys let you swap the default circular
node for a triangle or rectangle and steer where the incoming or
outgoing edge connects:

- `shape` (node style) accepts `"circle"` (default), `"triangle"`
  (apex up), or `"rectangle"`. The triangle and rectangle share a
  1.4×1.2 bounding box; the circle keeps its 1.2×1.2 footprint.
- `parent-anchor` / `child-anchor` (edge style) accept a cetz anchor
  name like `"north"` or `"south"` and override the edge endpoint on
  the parent or child side respectively. The default for both stays
  the empirical fractional-distance trick that looks clean between
  two circles.

The canonical use case is using a triangle to stand in for an entire
subtree — a common pattern when only the top-level shape matters and
the details would clutter the slide. Because the triangle's apex sits
at the `north` anchor of its bounding box, an incoming edge with
`child-anchor: "north"` lands cleanly on the tip:

```typ
#let t = (starling.BST.new)(value: 5, label: auto, left: none, right: none)
#let t = (t.insert-many)(2, 8, 1, 3)

#let ops = (
  (starling.Op.StyleNode.new)(path: "L", style: (shape: "triangle", fill: aqua.lighten(60%))),
  (starling.Op.StyleEdge.new)(path: "L", style: (child-anchor: "north")),
  (starling.Op.StyleNode.new)(path: "LL", style: (hide: true)),
  (starling.Op.StyleNode.new)(path: "LR", style: (hide: true)),
  (starling.Op.StyleEdge.new)(path: "LL", style: (hide: true)),
  (starling.Op.StyleEdge.new)(path: "LR", style: (hide: true)),
  (starling.Op.Alt.new)(text: "Left subtree summarised as a triangle."),
)
#let r = starling.apply-ops(starling.make-renderer(t, sticky: true), ops)
#starling.last((r.render)())
```

#let subtree-tree = (starling.BST.new)(value: 5, label: auto, left: none, right: none)
#let subtree-tree = (subtree-tree.insert-many)(2, 8, 1, 3)
#let subtree-ops = (
  (starling.Op.StyleNode.new)(
    path: "L",
    style: (shape: "triangle", fill: aqua.lighten(60%)),
  ),
  (starling.Op.StyleEdge.new)(path: "L", style: (child-anchor: "north")),
  (starling.Op.StyleNode.new)(path: "LL", style: (hide: true)),
  (starling.Op.StyleNode.new)(path: "LR", style: (hide: true)),
  (starling.Op.StyleEdge.new)(path: "LL", style: (hide: true)),
  (starling.Op.StyleEdge.new)(path: "LR", style: (hide: true)),
  (starling.Op.Alt.new)(text: "Left subtree summarised as a triangle."),
)
#let subtree-r = (starling.apply-ops)(
  starling.make-renderer(subtree-tree, sticky: true),
  subtree-ops,
)

#align(center, starling.last((subtree-r.render)()))

Shape and anchor are deliberately independent — the library doesn't
auto-set `child-anchor: "north"` when you switch a node to a triangle,
because there are legitimate uses for the default endpoint behavior
even on non-circular shapes (e.g. a labelled rectangle whose edges you
want pulled toward its center rather than flush against its top).
When you want flush meeting points, set the anchors yourself.

= API reference

The remainder of this manual is an auto-generated reference, produced
by the `tidy` package from doc-comments in the source.

#let lib-docs = tidy.parse-module(
  read("/src/lib.typ"),
  name: "Render helpers",
  label-prefix: "lib-",
  scope: (starling: starling, cetz: cetz),
)

#let core-docs = tidy.parse-module(
  read("/src/anim-core.typ"),
  name: "Animation core",
  label-prefix: "core-",
  scope: (starling: starling, cetz: cetz),
)

#let anim-docs = tidy.parse-module(
  read("/src/tree-anim.typ"),
  name: "Tree backend",
  label-prefix: "anim-",
  scope: (starling: starling, cetz: cetz),
)

#let graph-docs = tidy.parse-module(
  read("/src/graph.typ"),
  name: "Graph",
  label-prefix: "graph-",
  scope: (starling: starling, cetz: cetz),
)

#let gdraw-docs = tidy.parse-module(
  read("/src/graph-draw.typ"),
  name: "Graph renderer",
  label-prefix: "gdraw-",
  scope: (starling: starling, cetz: cetz),
)

#let glayout-docs = tidy.parse-module(
  read("/src/graph-layout.typ"),
  name: "Graph auto-layout",
  label-prefix: "glayout-",
  scope: (starling: starling, cetz: cetz),
)

#let git-docs = tidy.parse-module(
  read("/src/git-graph.typ"),
  name: "Git graph",
  label-prefix: "git-",
  scope: (starling: starling, cetz: cetz),
)

#let hashmap-docs = tidy.parse-module(
  read("/src/hashmap.typ"),
  name: "Hash map",
  label-prefix: "hashmap-",
  scope: (starling: starling, cetz: cetz),
)

#let hdraw-docs = tidy.parse-module(
  read("/src/hashmap-draw.typ"),
  name: "Hash map renderer",
  label-prefix: "hdraw-",
  scope: (starling: starling, cetz: cetz),
)

== Render helpers

#tidy.show-module(lib-docs, style: tidy.styles.default, show-module-name: false)

== Animation core

#tidy.show-module(core-docs, style: tidy.styles.default, show-module-name: false)

== Tree backend

#tidy.show-module(anim-docs, style: tidy.styles.default, show-module-name: false)

== Graph

#tidy.show-module(graph-docs, style: tidy.styles.default, show-module-name: false)

== Graph renderer

#tidy.show-module(gdraw-docs, style: tidy.styles.default, show-module-name: false)

== Graph auto-layout

#tidy.show-module(glayout-docs, style: tidy.styles.default, show-module-name: false)

== Git graph

#tidy.show-module(git-docs, style: tidy.styles.default, show-module-name: false)

== Hash map

#tidy.show-module(hashmap-docs, style: tidy.styles.default, show-module-name: false)

== Hash map renderer

#tidy.show-module(hdraw-docs, style: tidy.styles.default, show-module-name: false)
