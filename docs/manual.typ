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
#import starling: BST

#let t = (BST.new)(value: 4, label: auto, left: none, right: none)
#let t = (t.insert)(1)
#let t = (t.insert)(7)
#let t = (t.insert)(3)
#let t = (t.insert)(6)
```

#let t = (starling.BST.new)(value: 4, label: auto, left: none, right: none)
#let t = (t.insert)(1)
#let t = (t.insert)(7)
#let t = (t.insert)(3)
#let t = (t.insert)(6)

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
  [`src/tree-anim.typ`],
  [The animation kernel — defines `Snapshot`, `Frame`,
   `TreeRenderer`, `draw-tree`, `Op`, and `apply-ops`. Knows nothing
   about binary search trees specifically.],
  [`src/bst.typ`],
  [The BST class — implements pure operations (`insert`, `delete`,
   `rotate`) and the `*-display` methods that build animations using
   the kernel.],
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
   builder function `(bst-theme, render-theme) -> content` — not
   pre-baked content — so callers can resolve theme state at layout
   time and reuse the same animation across documents with different
   themes. `TreeRenderer.render` produces an array of these, one per
   snapshot. This is what `*-display` methods return.],
  [Theme dict],
  [Either a `render-theme` (structural defaults like node fill, edge
   stroke, note colour) or a `bst-theme` (semantic strokes/fills like
   `search-stroke`, `success-fill`). Frames are theme-agnostic until
   a render helper feeds resolved themes into each frame's `render`
   builder.],
)

The data flow, end to end:

#align(center)[
  `Snapshot` array #h(0.5em) → #h(0.5em) `TreeRenderer.render`\
  #h(0.5em) → #h(0.5em) `Array(Frame)` _(builders, theme-agnostic)_\
  #h(0.5em) → #h(0.5em) helper resolves theme state once\
  #h(0.5em) → #h(0.5em) helper calls each `(f.render)(bt, rt)`\
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

== Two theme layers, one per concern

Theming is split into two dicts that live in different files:

- *Render theme* (`default-render-theme`, in `tree-anim.typ`) holds
  structural defaults — node fill, node stroke, node text fill, edge
  stroke, note fill. Anything that a future data structure (heap,
  trie, B-tree) would also need.
- *BST theme* (`default-bst-theme`, in `bst.typ`) holds semantic
  strokes and fills tied to BST operations — `search-stroke`,
  `pivot-stroke`, `success-stroke`, `settled-stroke`, `success-fill`,
  `danger-stroke`, `reset-stroke`, `traversal-palette`.

The split lets each layer own its own concerns. When a new data
structure lands, it brings its own semantic theme dict
(`default-heap-theme`, say) and reuses the render-theme as-is. If
the structural defaults were tangled into the BST theme, every new
data structure would either duplicate them or grow a coupling to BST.

The render theme also has a clear "lowest in the chain" role:
`draw-tree` falls back to it when neither a snapshot override nor a
`make-renderer(default-node-style:, default-edge-style:)` argument
specifies a property. So the merge order, lowest precedence first, is:
`default-render-theme` → user render-theme override → renderer
defaults → per-snapshot per-path overrides. Each layer adds more
specificity.

Strokes throughout the BST theme are full stroke dictionaries
(`(paint:, thickness:, dash:)`), not bare colours. That lets users
change any aspect of a stroke (dash pattern, cap, width) without us
adding more theme keys for each possibility.

== Frames carry builders, not pre-rendered content

`Frame.render` is a function `(bst-theme, render-theme) -> content`,
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
function-typed field on a class. To keep `(frame.render)(bt, rt)`
from getting a spurious third argument, the actual closure is stored
as `_builder: (fn: ...)` — a singleton dict around the function — and
exposed through a `render` method that dereferences it. Users only
see `(frame.render)(bt, rt)`; the dict wrap is private.

== State for ergonomics, per-call for perf

Theme overrides come in two flavours:

#table(
  columns: (auto, 1fr),
  inset: 6pt,
  align: (left, left),
  table.header[*Form*][*Behaviour*],
  [`set-bst-theme((..))` / `set-render-theme((..))`],
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
`set-bst-theme(my-palette)` once, forget about it. Per-call is right
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
green edges", which is too much information at once.

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

We'll use the same sample tree throughout this section:

```typ
#let t = (BST.new)(value: 4, label: auto, left: none, right: none)
#let t = (t.insert-many)(1, 7, 3, 6, 8)
```

#let tour = (starling.BST.new)(value: 4, label: auto, left: none, right: none)
#let tour = (tour.insert-many)(1, 7, 3, 6, 8)

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
then transitions to the after-tree with the new node highlighted
green. `step.kind` is `"init"`, `"compare"` (per search step), and
finally `"inserted"`.

#align(center, starling.stacked((tour.insert-display)(5)))

== Delete

`(t.delete-display)(v)` has three internal cases — leaf, one-child,
and two-children — and dispatches on the target's children. `step.kind`
ranges over `"init"`, `"highlight"`, `"break"`, `"descend"`,
`"transfer"`, and `"settle"` depending on case.

The two-children deletion is the most complex: it highlights the
target, descends into the left subtree to find the in-order
predecessor, annotates the value transfer, then jumps to the after-tree
with the new root of the affected subtree highlighted green.

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
`set-bst-theme((traversal-palette: color.map.viridis))` or per-call
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

= Theming <theming>

Starling exposes two theme layers so document authors can match
starling's palette to their own document style:

- *Render theme* (#raw("default-render-theme")) — the structural
  defaults the renderer falls back on for the unstyled tree:
  `node-fill`, `node-stroke`, `node-text-fill`, `edge-stroke`,
  `note-fill`.
- *BST theme* (#raw("default-bst-theme")) — the semantic colors and
  strokes the BST `*-display` methods use to communicate operation
  state: `search-stroke`, `pivot-stroke`, `success-stroke`,
  `settled-stroke`, `success-fill`, `danger-stroke`, `reset-stroke`,
  `traversal-palette`. Strokes are full stroke dicts
  (`(paint:, thickness:, dash:)`) so any aspect — color, width, dash —
  is overridable without adding more keys.

== Setting a theme for the whole document

Call `set-bst-theme` and/or `set-render-theme` once near the top of
your document. The override is state-based and scoped by Typst's
normal layout flow, so it propagates to every subsequent
`*-display` call.

```typ
#import "@preview/starling:0.1.0": BST, set-bst-theme, set-render-theme

#set-bst-theme((
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

Typst's state machinery is what makes `set-bst-theme` / `set-render-theme`
work: a `state.update` later in the document can affect renders earlier
in document order, so Typst evaluates the document, propagates state,
and re-evaluates anything that observed it. In practice that means
*using either state setter roughly doubles the compile time of the
state-observed portion of the document* — a small fixed cost on top of
each tree, plus a full extra layout pass through everything that placed
a starling render helper or rendered a frame's `render` builder against
that state.

Concretely, a 50-tree synthetic benchmark goes from ~1.85s to ~3.1s
when `set-bst-theme` is added. The cost scales with document size, not
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

This is the usual perf/ergonomics tradeoff: `set-bst-theme` is one
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

== Driving layout from step metadata

`frame.step` is free-form per-method metadata. For example, a slide
that wants to colour-code its narration by step kind:

```typ
#let kind-colors = (compare: blue, inserted: green)

#let captioned-frames = frames.map(f => figure(context {
  let bt = starling._bst-theme-state.get()
  let rt = starling._render-theme-state.get()
  let color = kind-colors.at(f.step.kind, default: black)
  stack(dir: ttb, spacing: 0.5em,
    (f.render)(bt, rt), text(fill: color, f.caption))
}))

#alternatives(..captioned-frames)
```

#raw("frame.render") is a builder #raw("(bt, rt) => content") rather
than pre-baked content, so themes resolve at layout time. The
#raw("context") block above reads the active themes and feeds them
in; if you don't need state-driven theming, you can call
#raw("(f.render)(starling.default-bst-theme, starling.default-render-theme)")
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

#let anim-docs = tidy.parse-module(
  read("/src/tree-anim.typ"),
  name: "Animation kernel",
  label-prefix: "anim-",
  scope: (starling: starling, cetz: cetz),
)

== Render helpers

#tidy.show-module(lib-docs, style: tidy.styles.default, show-module-name: false)

== Animation kernel

#tidy.show-module(anim-docs, style: tidy.styles.default, show-module-name: false)
