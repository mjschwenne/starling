#import "/src/lib.typ" as starling
#import "@preview/cetz:0.5.2"
#import "@preview/tidy:0.4.3"

#import starling: (
  anchor, annotate, apply-ops, aux-strip, avl, b24, blank-snapshot, bst,
  canvas, commit, default-theme, figures, git, graph, hashmap, last,
  make-renderer, overlay, rbt, render, result, role, set-alt, set-caption,
  set-step, set-theme, skiplist, sort, stacked, style-edge, style-node, styles,
  subslides, theme-ref, trie,
)

#set page(paper: "us-letter", margin: 1in)
#set par(justify: true)
#set heading(numbering: "1.")
#show raw.where(block: true): set block(fill: luma(245), inset: 8pt, radius: 3pt, width: 100%)
#show link: set text(fill: rgb("#2b6cb0"))

#align(center)[
  #text(28pt, weight: "bold")[Starling]\
  #v(0.4em)
  #text(13pt, style: "italic")[Animated renderings of data structures for teaching]\
  #v(0.3em)
  #text(11pt)[Manual for v1.0.0]
]

#v(2em)

#outline(depth: 2, indent: auto)

#pagebreak()

= Introduction

Starling draws data structures, one step at a time, so a lecture can show
_how_ an algorithm works rather than only what it produced. It ships nine
structures — binary search trees, red-black trees, AVL trees, 2-3-4 trees,
tries, weighted graphs, hash maps, the linear (distribution) sorts, and skip
lists — plus a DSL for git commit graphs, and it is built on
#link("https://typst.app/universe/package/cetz")[cetz]. Slide decks are a
first-class target, but starling has no dependency on
#link("https://typst.app/universe/package/touying")[touying]: every animation
is a plain array of values you place however your document needs.

Every animation in starling is the same thing: an ordered array of *frames*.
A frame carries a builder that draws one moment of the structure, a caption,
step metadata, and alt text. Helpers collapse that array into a final image,
a vertical stack, a per-subslide sequence, or whatever you assemble yourself.

#block(
  fill: rgb("#eef4fb"),
  inset: 10pt,
  radius: 3pt,
  width: 100%,
)[
  *Coming from 0.3.x?* Version 1.0.0 is a rewrite of the public API: plain
  dictionaries instead of classes, one namespace per data structure, and one
  theme. Nothing from 0.3 keeps working. The
  #link(label("migration"))[migration chapter] maps every old name to its
  replacement.
]

== Installation

```typ
#import "@preview/starling:1.0.0" as starling
```

Typst 0.14 or later is required. The graphviz auto-layout helper pulls
`@preview/diagraph-layout` — but only if you call it (@auto-layout), so
projects that place their graphs by hand never fetch it.

== Quick start

```typ
#import "@preview/starling:1.0.0" as starling
#import starling: bst, last, stacked

#let t = bst.new(4, 1, 7, 3, 6)
```

The first value becomes the root; the rest are inserted in order. Every
data structure lives in a namespace of plain functions, and the structure is
always the first argument.

#let t = bst.new(4, 1, 7, 3, 6)

A static rendering — `display` returns a one-frame array, and `last` takes
the final frame of any array:

#align(center, last(bst.display(t)))

A search animation, stacked vertically with per-step captions:

#align(center, stacked(bst.search-display(t, 6)))

And on a slide, one subslide per step:

```typ
#alternatives(..subslides(bst.search-display(t, 6)))
```

== The shape of the API

Starling exports two kinds of name. *Namespaces* hold everything specific to
one structure or vocabulary; the *flat layer* holds what is common to all of
them.

#table(
  columns: (auto, 1fr),
  inset: 6pt,
  align: (left, left),
  table.header[*Namespace*][*Holds*],
  [`bst` `rbt` `avl` `b24` `trie`], [Tree structures: pure operations, literal
    builders, and the `*-display` animations.],
  [`graph` `hashmap` `sort` `skiplist`], [The non-tree structures, same
    contract.],
  [`styles`], [The semantic style vocabulary — `attention`, `success`,
    `ghost`, … (@styles).],
  [`aux`], [Auxiliary-state strips: `aux-strip`, `aux-view-title` (@aux).],
  [`git`], [The git commit-graph DSL (@git-graph). Its verbs (`commit`,
    `branch`, `merge`) are too generic to go flat.],
)

The flat layer, grouped by what it is for:

#table(
  columns: (auto, 1fr),
  inset: 6pt,
  align: (left, left),
  table.header[*Group*][*Names*],
  [Frames on the page],
  [`last`, `stacked`, `figures`, `subslides`, `canvas`, `aux-strip`],

  [The op stream],
  [`style-node`, `style-edge`, `annotate`, `set-alt`, `set-caption`,
    `set-step`, `commit`, `apply-ops`, `blank-snapshot`, `apply-snapshot`],

  [Frames and renderers],
  [`make-renderer`, `render`, `overlay`, `result`],

  [Theme],
  [`default-theme`, `set-theme`, `theme-ref`, `role`],

  [Drawing],
  [`draw-tree`, `draw-graph`, `draw-hashmap`, `draw-array`, `draw-skiplist`,
    `anchor`, `auto-layout`],
)

That is the whole surface; a conformance test asserts the list exactly, so
nothing leaks into it by accident.

== One contract, nine structures <ds-contract>

Every data-structure module presents the same names, so knowing one means
knowing them all:

#table(
  columns: (auto, 1fr),
  inset: 6pt,
  align: (left, left),
  table.header[*Name*][*Role*],
  [`new(..)`], [Build a structure from values. `bst.new(4, 1, 7)`,
    `trie.new("cat", "car")`, `hashmap.new(7, strategy: "linear")`.],
  [pure operations], [`insert`, `delete`, `contains`, … — each takes the
    structure first and returns a *new* structure or a value. Nothing
    mutates.],
  [`describe(s)`], [A one-line string describing the structure. It is what
    the animations' alt text opens with.],
  [`check-invariants(s)`], [Returns `true`, or panics naming the broken
    invariant.],
  [`display(s, ..)`], [The structure as a single frame.],
  [`<op>-display(s, ..)`], [One animation per operation, each returning an
    array of frames.],
  [`renderer(s, ..)`], [A renderer pre-painted with the structure's own
    styling, for driving by hand with the op stream (@op-stream).],
  [`anchor`, key helpers], [The cetz anchor sanitizer, plus the constructors
    for that structure's element keys (@element-keys).],
)

Signature rules hold across all of them: the structure is the first
positional argument; `theme:` is always a partial nested theme override
(@theming); `node-style:` and `edge-style:` are the base style layers; and
every animation is named `<op>-display` and nothing else is.

== Calling `insert` inside a function <insert-trap>

One name needs care. Typst reads `x.insert(..)` as a call to *its own*
mutating `insert` method, and a variable captured from an enclosing scope
cannot be mutated — so inside any function or closure body, the natural
spelling fails:

```typ
#let f = x => bst.insert(t, x)
// error: variables from outside the function are read-only
//        and cannot be modified
```

The caret points at `bst`, and the message never mentions `insert`, so the
diagnostic gives no route to the fix. At the top level of a document the same
line is fine, which is what makes this easy to miss until a helper is
extracted.

Parenthesize the function reference, and it is an ordinary call again:

```typ
#let f = x => (bst.insert)(t, x)
```

Importing the verb out of the namespace also works, if you would rather not
carry the parentheses:

```typ
#import starling.bst: insert
#let f = x => insert(t, x)
```

This affects only the bare name `insert` — which `bst`, `rbt`, `avl`, `b24`,
`trie`, `hashmap`, and `skiplist` all export. `insert-many` and every other
verb (`delete`, `contains`, `display`, …) are unaffected, since Typst has no
method by those names.

= The animation model

Four shapes do all the work, and all four are plain dictionaries you can
inspect, slice, and rebuild.

#table(
  columns: (auto, 1fr),
  inset: 6pt,
  align: (left, left),
  table.header[*Shape*][*Role*],
  [Structure],
  [The data — a tree node, a graph, a table. Carries a `kind` field and
    nothing else that is starling's business. Every operation returns a new
    one.],

  [`Snapshot`],
  [A _sparse style overlay_ for one moment: which elements are filled what
    colour, which edges are dashed or hidden, which notes hang off which
    nodes. `(nodes: (:), edges: (:))`, keyed by element key. Pure data — no
    theme, no content.],

  [`Renderer`],
  [A structure, a draw backend, and an ordered list of snapshots, plus the
    caption / step / alt metadata for each. What you build up when driving
    an animation by hand.],

  [`Frame`],
  [The *output* record: `(builder, caption, step, alt, ..)`. `builder` is a
    function `theme => content` — not baked content — so one frame array can
    render against different themes without recomputing the animation. This
    is what every `*-display` returns.],
)

The data flow, end to end:

#align(center)[
  structure + snapshots #h(0.4em) → #h(0.4em) `render(renderer)` or a
  `*-display`\
  #h(0.4em) → #h(0.4em) `array(Frame)` _(builders; theme-agnostic)_\
  #h(0.4em) → #h(0.4em) a helper resolves the theme once\
  #h(0.4em) → #h(0.4em) each `(frame.builder)(theme)`\
  #h(0.4em) → #h(0.4em) document content
]

The shape is load-bearing: because frames are data until the last step, you
can pull one out, read its `step`, swap its caption, thread it into a custom
layout, or overlay cetz commands on it, all without rendering anything.

== What a frame carries

#table(
  columns: (auto, 1fr),
  inset: 6pt,
  align: (left, left),
  table.header[*Field*][*Meaning*],
  [`builder`], [`theme => content`. The helpers call it; you rarely do
    directly.],
  [`caption`], [`none` or content — the textual narration of this step.],
  [`step`], [Free-form metadata about the step; always has `kind`
    (@step-kinds).],
  [`alt`], [Alt text for this step, always an explicitly-set string. The
    helpers wrap each canvas in an alt-carrying `figure`, so a deck compiled
    to PDF/UA keeps its narration.],
  [`extra`], [cetz commands appended inside the frame's canvas — what
    `overlay` (@cetz) appends to.],
)

Captions run on a second channel from the drawing on purpose. A search frame
labels the compared node _in the canvas_ with the comparison it just made,
and _also_ carries "6 \> 4" as its caption. The inline note makes a single
frame readable on its own; the caption is a parallel textual track for
layouts that want narration somewhere else on the slide. It is also why
`last` hides captions by default while `stacked` and `figures` show them.

== Step kinds and the result <step-kinds>

`step.kind` says what a frame is showing. A few kinds are universal —
`static` (a one-frame `display`), `init`, `settled` (the terminal success of
a mutation), and `found` / `not-found` (lookup outcomes) — and each structure
adds its own where the semantics genuinely differ (`descend`, `probe`,
`splice`, `rehash`, `visit`, …). Each module lists its full set in a comment
at the top of its source.

Every animation's *final* frame also carries `step.result`: the structure the
operation produced. That is what `result(frames)` reads, and it is how an
animation and the state it leaves behind stay in sync:

```typ
#let frames = bst.insert-display(t, 5)
#stacked(frames)
#let t = result(frames)     // t now has the 5 in it
```

For searches and traversals — which change nothing — `step.result` is the
input structure, so the pattern is uniform.

== Element keys <element-keys>

Every element a backend draws has a *key*: an opaque string that snapshots,
op streams, and anchors all use to name it. The alphabet is the structure's
business.

#table(
  columns: (auto, auto, 1fr),
  inset: 6pt,
  align: (left, left, left),
  table.header[*Structure*][*Key*][*Meaning*],
  [`bst` `rbt` `avl`], [`""`, `"L"`, `"RL"`], [The path from the root in
    `L`/`R` characters. The root is the empty string.],
  [`b24`], [`"01"`, `"01#1"`], [Child indices as digits; an optional `#i`
    suffix addresses one key compartment of that node.],
  [`trie`], [`""`, `"c"`, `"ca"`], [The prefix spelled by the edges down to
    the node.],
  [`graph`], [`"A"`, `graph.edge-key("A", "B")`], [The node id; edges are
    `"u--v"` (undirected) or `"u->v"` (directed).],
  [`hashmap`], [`hashmap.cell-key(3)`, `hashmap.entry-key(3, 1)`], [Slot 3;
    entry 1 of bucket 3's chain (which also keys the link into it).],
  [`sort`], [`sort.cell-key("count", 5)`], [Row and column of the cell;
    `sort.entry-key(row, i, j)` for a bucket-chain entry.],
  [`skiplist`], [`skiplist.box-key(2, 1)`], [Column 2's lane box at level 1;
    also `data-key(col)` and `forward-key(col, level)`.],
)

An *edge* is keyed by its child in a tree (each child has exactly one
parent, so this is unambiguous) and by `edge-key` in a graph.

Because keys are opaque, an animation written against one structure works on
any structure of the same shape: styling is independent of the values in the
nodes. And because both the snapshot layer and the anchor layer use the same
key, calling out a node in your own cetz code is `anchor(<the key>)` — see
@cetz.

= Putting frames on the page

An animation is an array; these five helpers turn it into content. All of
them except `canvas` wrap each canvas in a `figure` carrying that frame's
alt text, which changes nothing visible but keeps the animation narrated for
screen readers.

#table(
  columns: (auto, 1fr),
  inset: 6pt,
  align: (left, left),
  table.header[*Helper*][*Gives you*],
  [`last(frames)`], [The final frame alone — the static, print form. Takes a
    lone frame too, so `last(frames.at(3))` needs no re-wrapping.],
  [`stacked(frames)`], [Every frame stacked down the page with its caption —
    the handout form.],
  [`figures(frames)`], [An array of `figure`s, one per frame. Splat it into
    touying's `alternatives(..)`.],
  [`subslides(frames, ..)`], [An array of *compositions* — canvas, auxiliary
    strip, and caption laid out together, one per step (@subslides).],
  [`canvas(frame)`], [One frame's bare canvas, with no caption and *no alt
    text*, for hand-built layouts where you own the accessibility.],
)

`last`, `stacked`, and `canvas` open one `context` and resolve the theme
once for the whole call. `figures` and `subslides` cannot: touying lays each
returned element out independently, so each opens its own.

== Slides with `subslides` <subslides>

`subslides` is the one to reach for in a deck. It composes each step's
canvas with the algorithm's auxiliary state and the step's caption, so a
slide is one call:

```typ
#alternatives(..subslides(graph.bfs-display(g, "A"), aux: "right"))
```

#let g-demo = graph.new(
  (("A", 0, 0), ("B", -1.4, -1.4), ("C", 1.4, -1.4), ("D", 0, -2.8)),
  edges: (("A", "B"), ("A", "C"), ("B", "D"), ("C", "D")),
)

#align(center, subslides(
  graph.bfs-display(g-demo, "A", sort-frontier: true),
  aux: "right",
  fit: 90%,
).at(2))

Its arguments: `aux:` places the strip (`none`, `"right"`, `"left"`, or
`"below"`), `aux-view:` picks one view when a step carries several,
`aux-size:` sets the strip's text size, `caption:` toggles the narration,
and `fit:` scales the composition. `fit: 60%` is a plain scale; `fit: (20cm,
12cm)` measures *every* frame in the animation and applies one common factor
so the drawing keeps a constant size from subslide to subslide instead of
resizing under each step.

Composing that sandwich by hand — a `grid` of `canvas`, `aux-strip`, and
`f.caption`, each in its own `alternatives` — is what decks used to do, and
it both drops the alt text and lets the three columns drift apart between
subslides. If you do want the pieces separately, they still step in lockstep
because each `alternatives` gets the same number of children:

```typ
#let frames = graph.bfs-display(g, "A")
#grid(
  columns: (2fr, 1fr), column-gutter: 2em, align: horizon,
  alternatives(..figures(frames, caption: false)),
  stack(dir: ttb, spacing: 1.2em,
    alternatives(..frames.map(f => aux-strip(f.step))),
    alternatives(..frames.map(f => f.caption)),
  ),
)
```

== Auxiliary state <aux>

The graph algorithms carry their bookkeeping — BFS's queue, DFS's stack,
Prim's frontier, Kruskal's sorted edge list and disjoint sets, Dijkstra's
priority queue and its `dist` / `prev` maps — in each frame's `step`.
`aux-strip(frame.step)` renders it as placeable content beside the canvas:

#let bfs-demo = graph.bfs-display(g-demo, "A", sort-frontier: true)
#align(center, grid(
  columns: (auto, auto),
  column-gutter: 1.5em,
  align: horizon,
  canvas(bfs-demo.at(2)),
  aux-strip(bfs-demo.at(2).step),
))

It is deliberately decoupled from the canvas, so a slide can put the graph
on one side and the strip on the other. A frame that carries several views
(Kruskal two, Dijkstra three) stacks them all under their headings by
default; `view:` selects one, `title:` overrides whether the heading shows,
and `labels:` supplies custom display labels per node id. The heading string
itself is `aux.aux-view-title(kind)`, for rolling your own.

== Reading step metadata

`frame.step` is ordinary data, so a layout can dispatch on it — colouring
the narration by what kind of step it is, for instance:

```typ
#let kind-colors = (compare: blue, inserted: green)
#let narrated = frames.map(f => stack(dir: ttb, spacing: 0.5em,
  canvas(f),
  text(fill: kind-colors.at(f.step.kind, default: black), f.caption),
))
#alternatives(..narrated)
```

= Theming <theming>

Starling has one theme: a nested dictionary with one section per concern.

#table(
  columns: (auto, 1fr),
  inset: 6pt,
  align: (left, left),
  table.header[*Section*][*Holds*],
  [`render`], [Structural defaults for an unstyled structure: `node-fill`,
    `node-stroke`, `node-text-fill`, `edge-stroke`, `note-fill`,
    `edge-tag-fill` (persistent edge labels — AVL heights, trie letters,
    graph weights), `note-bg` (drawn behind in-canvas annotations so they
    stay legible over edges; set it to your page colour on a tinted
    background), and `elided-fill` / `elided-stroke` for an elided
    subtree.],

  [`op`], [Operation-semantic roles shared by every structure:
    `search-stroke`, `attention-stroke`, `success-stroke`, `settled-stroke`,
    `success-fill`, `danger-stroke`, `reset-stroke`, and
    `traversal-palette`. BST search and hash-map probing read the same
    `search-stroke` — the roles describe *operations*, not structures.],

  [`rbt` `trie` `hashmap` `sort` `skiplist` `git`], [Styling intrinsic to one
    structure: the red/black palette, the trie's word-end shading, the hash
    map's tombstones and chains, the sort's count tint, the skip list's
    sentinels and muted lanes, and the git DSL's branch colours. `bst`,
    `avl`, `b24` and `graph` need none.],
)

Strokes throughout are full stroke dictionaries — `(paint:, thickness:,
dash:)` — so any aspect can change without the theme growing another key.
`default-theme` is the whole thing; read a value out of it with
`default-theme.op.attention-stroke`.

== The two override paths

Both take a *partial* nested dict: only the sections and keys you name
change, and an unknown section or key panics so a typo surfaces at once.

```typ
// Document-wide, from here on:
#set-theme((
  op: (search-stroke: (paint: teal, thickness: 2.5pt)),
  render: (node-fill: yellow.lighten(85%)),
))

// Or for one call only:
#stacked(bst.search-display(t, 6, theme: (op: (search-stroke: (paint: olive, thickness: 2pt)))))
```

#align(center, stacked(
  bst.search-display(t, 6, theme: (
    op: (search-stroke: (paint: olive, thickness: 2pt)),
    render: (node-fill: olive.lighten(88%)),
  )).slice(0, 2),
))

Precedence runs `default-theme` #sym.arrow.l `set-theme` state
#sym.arrow.l a per-call `theme:` #sym.arrow.l the renderer's `node-style:` /
`edge-style:` layers #sym.arrow.l the per-frame snapshot. A per-call
override *layers on* the document's theme rather than replacing it, so
naming two keys changes those two and leaves the rest of your palette alone.

== Performance: state costs a layout pass <theming-perf>

Typst's state machinery is what makes `set-theme` work: an update later in
the document can affect renders earlier in document order, so Typst
evaluates, propagates, and re-evaluates everything that observed the state.
In practice, *using `set-theme` roughly doubles the compile time of the
state-observed part of the document.* The cost is one extra layout pass, not
one per read — a thousand reads cost the same as one.

Starling pays that price at most once (there is a single state, where 0.3.x
had eight), and only if you call `set-theme` at all. When compile speed
matters more than the convenience, hoist a palette into a `let` and pass it
per call:

```typ
#let palette = (op: (search-stroke: (paint: teal, thickness: 2.5pt)))
#stacked(bst.search-display(t, 6, theme: palette))
#stacked(bst.insert-display(t, 5, theme: palette))
```

== Theme references

A style built ahead of time cannot know the theme that will be active when
it is drawn — so it stores a *reference* instead of a colour. `role(key)` is
a reference into the `op` section and `theme-ref(section, key)` into any
section; the frame machinery resolves them just before the backend runs.

```typ
#style-node("LR", stroke: role("attention-stroke"))
#style-node("LR", fill: theme-ref("rbt", "red-fill"))
```

This is what makes the style vocabulary below theme-aware, and it is
available to your own op streams for the same reason.

= The style vocabulary <styles>

`styles.*` names *intents* rather than colours. Each helper is variadic over
element keys and returns an op array, so they compose with `+` and drop
straight into `apply-ops`:

#table(
  columns: (auto, 1fr),
  inset: 6pt,
  align: (left, left),
  table.header[*Helper*][*Effect*],
  [`styles.attention(..keys)`], ["Look here" — a rotation pivot, a deletion
    target, the entry being polled.],
  [`styles.search(..keys)`], [Part of a search or insert walk.],
  [`styles.success(..keys)`], [Settled: the success fill plus the terminal
    ring.],
  [`styles.danger(..keys)`], [Broken, removed, or rejected.],
  [`styles.subtree(..keys)`], [Elide a subtree: a grey triangle with the
    incoming edge landing on its apex.],
  [`styles.nullify(..keys)`], [Draw a nil child as a real #sym.emptyset
    node.],
  [`styles.ghost(..keys)`], [Invisible but space-reserving — the layout is
    identical to the fully-drawn structure.],
  [`styles.hidden(..keys)`], [Gone entirely, layout space released.],
  [`styles.revealed(..keys)`], [Undo either of those on a sticky frame.],
  [`styles.force-show(..keys)`], [Draw an edge into a phantom (nil)
    position.],
)

`ghost` versus `hidden` is the progressive-reveal decision. Ghosting keeps
every element's exact footprint, so revealing a subtree one node at a time
never shifts what is already on the slide; hiding releases the space, so the
drawing re-flows around the gap. On a slide you almost always want `ghost`.

#let reveal-tree = bst.insert-many(bst.leaf(5), 2, 8, 1, 3, 7, 9)
#let reveal-panel(name, ops) = stack(
  dir: ttb,
  spacing: 0.6em,
  align(center, strong(name)),
  scale(62%, reflow: true, last(render(apply-ops(
    bst.renderer(reveal-tree, sticky: true),
    ops + set-alt("A tree with its right subtree " + name + "."),
  )))),
)

#align(center, grid(
  columns: (1fr, 1fr, 1fr),
  column-gutter: 1em,
  align: center + top,
  reveal-panel("full", ()),
  reveal-panel("ghosted", styles.ghost("R", "RL", "RR")),
  reveal-panel("hidden", styles.hidden("R", "RL", "RR")),
))

Structure-specific vocabulary lives in that structure's namespace, where it
can name things only that structure has: `rbt.paint-red(..keys)` /
`rbt.paint-black(..keys)` recolour nodes from the red-black palette,
`rbt.double-black(..keys)` marks the missing-black bookkeeping of a
deletion, and `avl.unbalanced(..keys, case: "LL")` rings an imbalanced node
with its case.

An elided subtree, a nullified child, and a double-black marker, all on one
tree:

#let vocab-tree = rbt.new(8, 4, 12, 2, 6)
#align(center, last(render(apply-ops(
  rbt.renderer(vocab-tree, sticky: true),
  styles.subtree("LL")
    + styles.nullify("LRL")
    + styles.force-show("LRL")
    + rbt.double-black("R")
    + styles.attention("")
    + set-alt("An elided subtree, a nil sentinel, and a double-black node."),
))))

= The op command stream <op-stream>

When an animation doesn't fit any built-in `*-display` — a probe sequence
you want narrated your way, a hand-built teaching fixture, a progressive
reveal — build the frames yourself. The op stream is a small declarative
language for that: each constructor returns an *array* of ops, so streams
compose with `+`, and `apply-ops` folds one into a renderer.

#table(
  columns: (auto, 1fr),
  inset: 6pt,
  align: (left, left),
  table.header[*Op*][*Does*],
  [`style-node(..keys, ..style)`], [Style one or more nodes. Positional
    arguments are element keys, named arguments the style —
    `style-node("L", "RR", fill: red)` is two ops.],
  [`style-edge(..keys, ..style)`], [The same for edges.],
  [`annotate(key, note)`], [Attach a transient note beside a node.],
  [`commit(caption:, step:, alt:)`], [Close the in-progress frame, attaching
    metadata, and open a fresh one.],
  [`set-caption(c)` `set-step(s)` `set-alt(a)`], [Set one piece of metadata
    without committing — for the trailing frame, which has no `commit` after
    it.],
)

The three pieces: a renderer from the structure's own namespace (so it comes
pre-painted with that structure's styling), a stream, and `render`.

The three painting namespaces — `rbt`, `avl`, `trie` — always apply their
palette. When you want the *structure* but none of its colouring, because
every fill is coming from your own ops, go through the extension point
directly: `make-renderer(t, draw-tree)` gives an unpainted renderer over the
same tree. Reaching for `bst.renderer` instead would work, but it would
misname what you are drawing.

```typ
#let r = bst.renderer(t, sticky: true)
#let frames = render(apply-ops(r,
  style-node("", stroke: role("search-stroke"))
    + annotate("", [6 > 4])
    + commit(caption: [start at the root], alt: "Comparing 6 against 4."),
  ))
```

`sticky: true` is what makes each frame start from the previous one's
styling — the accumulate-as-you-go behaviour a walk wants. It is *off* by
default, so an animation whose frames each stand alone needs no
un-sticking. Captions, steps, and alt text never accumulate; each frame's
are its own.

#let op-tree = bst.new(4, 1, 7, 3, 6, 8)
#let walk-frames = render(apply-ops(
  bst.renderer(op-tree, sticky: true),
  style-node("", stroke: role("search-stroke"))
    + annotate("", [6 > 4])
    + commit(caption: [start at the root], alt: "Comparing 6 against 4.")
    + style-node("R", stroke: role("search-stroke"))
    + annotate("R", [6 < 7])
    + commit(caption: [go right], alt: "Comparing 6 against 7.")
    + styles.success("RL")
    + set-caption([found it])
    + set-alt("Found 6."),
))

#align(center, stacked(walk-frames))

Notice the third batch: `styles.success("RL")` is the vocabulary from
@styles, which is nothing more than a pre-built op array, and the trailing
frame closes with `set-caption` / `set-alt` rather than a `commit`.

A note is transient by design even under `sticky: true` — pass `note: none`
in a later batch to clear one that was inherited. There is no
"clear everything" op; styling one key at a time is the whole model.

== On a graph and on a hash map

The same stream drives every backend; only the keys change. Each namespace
exports the constructors for its own keys, so nothing is spelled by hand.

```typ
#let r = graph.renderer(g, sticky: true)
#let frames = render(apply-ops(r,
  styles.attention("A")
    + style-edge(graph.edge-key("A", "C"), stroke: role("success-stroke"))
    + commit(caption: [A #sym.arrow C (+4)], alt: "Relaxing A to C."),
  ))
```

#let g-op = graph.new(
  (("A", 0, 0), ("B", 3, 0.4), ("C", 1.5, 2.4), ("D", 4.5, 2.2)),
  edges: (
    ("A", "B", 7), ("B", "C", 2), ("A", "C", 4), ("C", "D", 5), ("B", "D", 1),
  ),
)

#let hm-op = hashmap.new(7, strategy: "linear", entries: (14, 21))

#align(center, grid(
  columns: (auto, auto),
  column-gutter: 2em,
  align: horizon,
  last(render(apply-ops(
    graph.renderer(g-op, sticky: true),
    styles.success("A")
      + styles.attention("C")
      + style-edge(graph.edge-key("A", "C"), stroke: role("success-stroke"))
      + set-alt("Edge A to C committed."),
  ))),
  last(render(apply-ops(
    hashmap.renderer(hm-op, sticky: true),
    style-node(hashmap.cell-key(0), stroke: role("search-stroke"))
      + style-node(hashmap.cell-key(1), stroke: role("search-stroke"))
      + styles.success(hashmap.cell-key(2))
      + set-alt("Probed slots 0 and 1, landed on 2."),
  ))),
))

The graph renderer takes the same `positions:` / `scale:` / `layout:`
arguments its displays do; the hash-map renderer takes `orientation:` and an
optional `hash-box:`.

= Composing with cetz <cetz>

Two escape hatches lead from a starling drawing back to raw cetz: drawing a
structure inside your own canvas, and appending commands to a frame's
canvas. Both find elements through `anchor(<element key>)`.

== `anchor` and the draw backends

Each `draw-*` backend emits cetz drawables *without* wrapping them in a
`cetz.canvas`, so you can compose them with your own commands. They read a
plain `theme:` default rather than state, so no `context` is needed.

```typ
#import "@preview/cetz:0.5.2"

#cetz.canvas({
  starling.draw-tree(t, blank-snapshot())
  // Selective import: cetz.draw has an `anchor` of its own, and a glob
  // import would shadow starling's.
  import cetz.draw: circle
  circle(anchor("LR"), radius: 0.85, stroke: red + 2pt)
})
```

#align(center, cetz.canvas({
  starling.draw-tree(op-tree, blank-snapshot())
  import cetz.draw: circle
  circle(anchor("LR"), radius: 0.85, stroke: red + 2pt)
  circle(anchor(""), radius: 0.85, stroke: blue + 2pt)
}))

`anchor(key)` is the one sanitizer for every backend: it turns an element
key into the cetz element name that backend drew under (`"LR"` #sym.arrow
`el-LR`, the root #sym.arrow `el-root`, `"c3:1"` #sym.arrow `el-c3-1`).
Compass sub-anchors work as usual — `anchor("LR") + ".north"` — and
`anchor(key, canvas: "t")` qualifies the name when the drawing sits inside a
named group. Pass `name:` to any backend to create that group.

The snapshot need not be blank. A structure's `renderer()` gives you its
structural painting — a trie's terminal shading, a red-black tree's colours —
and `apply-ops` layers the style vocabulary on top; either snapshot drops
straight into a backend:

```typ
#cetz.canvas({
  let t = trie.new("car", "cat")
  starling.draw-tree(t, trie.renderer(t).snapshots.last())
})
```

#align(center, cetz.canvas({
  let t = trie.new("car", "cat")
  starling.draw-tree(t, trie.renderer(t).snapshots.last())
}))

Where a backend has key helpers, each has a matching anchor helper that saves
the wrapping call — `skiplist.box-anchor(c, l)` is `anchor(skiplist.box-key(c,
l))`, and likewise `forward-anchor` / `data-anchor`, `hashmap.cell-anchor` /
`entry-anchor`, `sort.cell-anchor` / `entry-anchor`, and
`graph.edge-anchor(g, u, v)`. Each takes the same `canvas:` argument. A graph
node's key is its id, so its anchor is just `anchor(id)`.

The non-tree backends take the structure's *positioned* form, which is what
turns a graph or a table into coordinates:

```typ
#let h = hashmap.new(5, strategy: "chaining", entries: (5, 10, 7, 3))
#context cetz.canvas({
  starling.draw-hashmap(hashmap.positioned(h), blank-snapshot())
  import cetz.draw: circle, content
  circle(anchor(hashmap.cell-key(2)), radius: 0.8, stroke: red + 2pt)
  content(anchor(hashmap.entry-key(0, 1)) + ".east", anchor: "west", [ #sym.arrow.l tail])
})
```

#let hm-anchor = hashmap.new(5, strategy: "chaining", entries: (5, 10, 7, 3))
#align(center, context cetz.canvas({
  starling.draw-hashmap(hashmap.positioned(hm-anchor), blank-snapshot())
  import cetz.draw: circle, content
  circle(anchor(hashmap.cell-key(2)), radius: 0.8, stroke: red + 2pt)
  content(
    anchor(hashmap.entry-key(0, 1)) + ".east",
    anchor: "west",
    [ #sym.arrow.l tail],
  )
}))

== Overlaying a callout on a frame

Reaching into an animation to annotate one step used to mean rebuilding its
canvas by hand. `overlay(frames, at:, draw:)` appends cetz commands *inside*
an existing frame's canvas — so the backend's anchors are in scope — and
gives back the frame array:

```typ
#let frames = overlay(bst.search-display(t, 6), at: -1, draw: theme => {
  import cetz.draw: content, line
  line((rel: (-1.6, -1), to: anchor("RL")), anchor("RL") + ".south-west",
       stroke: theme.op.attention-stroke, mark: (end: ">"))
  content((rel: (-1.7, -1.1), to: anchor("RL")), [the hit], anchor: "north-east")
})
```

#align(center, last(overlay(
  bst.search-display(op-tree, 6),
  at: -1,
  draw: theme => {
    import cetz.draw: content, line
    line(
      (rel: (-1.6, -1), to: anchor("RL")),
      anchor("RL") + ".south-west",
      stroke: theme.op.attention-stroke,
      mark: (end: ">"),
    )
    content(
      (rel: (-1.7, -1.1), to: anchor("RL")),
      [the hit],
      anchor: "north-east",
    )
  },
)))

`draw:` is either raw cetz commands or a function of the resolved theme, so
a callout can wear the same colours the animation does. `at:` accepts
negative indices; `-1` is the last frame.

= Extending starling <extending>

A draw backend is a plain function

```typ
(structure, snapshot, node-style: (:), edge-style: (:), theme: default-theme)
  => cetz commands
```

and `make-renderer(structure, draw, ..)` is the documented way to plug one
in. Everything else in the package — the five bundled backends included —
goes through the same door: nothing about frames, snapshots, ops, themes, or
the presentation helpers knows what a tree is.

```typ
#let draw-blobs(structure, snapshot, node-style: (:), edge-style: (:), theme: default-theme) = {
  import cetz.draw: circle, content
  for (i, item) in structure.items.enumerate() {
    let style = node-style + snapshot.nodes.at(str(i), default: (:))
    circle((i * 1.4, 0),
      radius: 0.5,
      fill: style.at("fill", default: theme.render.node-fill),
      stroke: style.at("stroke", default: theme.render.node-stroke),
      name: anchor(str(i)))
    content((i * 1.4, 0), item)
  }
}

#let r = make-renderer((items: ("a", "b", "c")), draw-blobs, sticky: true)
#last(render(apply-ops(r, styles.success("1") + set-alt("The middle blob."))))
```

#let draw-blobs(
  structure,
  snapshot,
  node-style: (:),
  edge-style: (:),
  theme: default-theme,
) = {
  import cetz.draw: circle, content
  for (i, item) in structure.items.enumerate() {
    let style = node-style + snapshot.nodes.at(str(i), default: (:))
    circle(
      (i * 1.4, 0),
      radius: 0.5,
      fill: style.at("fill", default: theme.render.node-fill),
      stroke: style.at("stroke", default: theme.render.node-stroke),
      name: anchor(str(i)),
    )
    content((i * 1.4, 0), item)
  }
}

#align(center, last(render(apply-ops(
  make-renderer((items: ("a", "b", "c")), draw-blobs, sticky: true),
  styles.success("1") + set-alt("The middle blob."),
))))

Two conventions make a custom backend behave like a bundled one. Resolve
each element's style as `node-style` #sym.arrow.l the snapshot's entry for
that key, falling back to `theme.render` — the frame machinery has already
resolved any theme references by the time it calls you. And name each
element `anchor(<its key>)`, so callouts and `overlay` can find it.

For a whole animation rather than a hand-driven renderer, `make-frames`
takes a list of specs — each a structure, a `build: theme => snapshot`
closure, and the frame's metadata — and is what every `*-display` in the
package is built on.

= Binary search trees

`bst` is the plainest structure in the package and the one to read first:
the others differ from it only where their algorithms do.

Build one from values with `new` (first value is the root, the rest are
inserted in order), or write a tree literal with `node` / `leaf` when the
*shape* is the point — a fixture for a specific fix-up case, say:

```typ
#let t = bst.new(4, 1, 7, 3, 6, 8)
#let fixture = bst.node(4, bst.node(1, none, bst.leaf(3)), bst.leaf(7))
```

Values may carry a display label: pass `(value, label)` in place of a bare
value, or `label:` on `insert` / `node`. The label is drawn; the value still
orders the tree.

#let tour = bst.new(4, 1, 7, 3, 6, 8)

Pure operations — `insert`, `insert-many`, `delete`, `rotate`, `contains`,
`by-value`, `path-to`, `resolve`, the four traversals, `describe`, and
`check-invariants` — return new trees or plain values, and are what the
animations are built on.

== Static display

#align(center, last(bst.display(tour)))

== Search

`search-display(t, v)` walks the search path, highlighting each node it
visits and labelling it with the comparison it made. The terminal frame is
`found` or `not-found`.

#align(center, stacked(bst.search-display(tour, 6)))

== Insert

`insert-display(t, v, label: auto)` walks the same path, then shows the new
node spliced in and settled.

#align(center, stacked(bst.insert-display(tour, 5)))

== Delete

`delete-display(t, v)` dispatches on the target's children — leaf, one
child, or two. The two-child case is the interesting one: it marks the
target, descends to the in-order predecessor, transfers the value, and then
excises the emptied node.

Pass `search: true` to precede the deletion with a search-style walk to the
target (its comparison notes are cleared on the first deletion frame, so they
do not compete with the deletion highlights). The default opens straight on
the deletion, which is what you want when that, not the lookup, is the
lesson. In `rbt` and `avl` the same flag means one frame per comparison
instead of a single frame lighting the whole path.

#align(center, stacked(bst.delete-display(tour, 4)))

== Rotate

`rotate-display(t, child)` rotates `child` up into its parent's place —
anywhere in the tree, not only at the root — inferring the direction from
where `child` sits. Six frames, each answering exactly one question:

#table(
  columns: (auto, 1fr),
  inset: 6pt,
  align: (left, left),
  table.header[*`step.kind`*][*Question answered*],
  [`init`], [What is the starting tree?],
  [`pivots`], [Which two nodes are rotating?],
  [`break`], [Which edges are about to disappear?],
  [`restructure`], [What is the new shape, edges aside?],
  [`connect`], [Where do the new edges go?],
  [`settled`], [What does the finished tree look like?],
)

`restructure` is the load-bearing frame: it shows the new positions forming
while the moved edges are still hidden, so the shape change lands separately
from the reconnection.

#align(center, stacked(bst.rotate-display(tour, bst.resolve(tour, "L"))))

== Traversals

The four `*-order-display` animations emit one frame per visit. The visited
node takes the next colour from the op theme's `traversal-palette` and a
numbered badge, and the caption accumulates the output sequence. The final
frame therefore carries the algorithm's whole colour signature, which makes
the four worth showing side by side:

#let traversal-panel(name, frames) = block(breakable: false, stack(
  dir: ttb,
  spacing: 0.4em,
  align(center, strong(name)),
  last(frames, caption: true),
))

#align(center, grid(
  columns: 2,
  gutter: 1.5em,
  traversal-panel([In-order], bst.in-order-display(tour)),
  traversal-panel([Pre-order], bst.pre-order-display(tour)),
  traversal-panel([Post-order], bst.post-order-display(tour)),
  traversal-panel([Level-order], bst.level-order-display(tour)),
))

The pure `bst.in-order(t)` and friends return the visit order as an array of
paths, for driving a layout of your own.

= Red-black trees

`rbt` adds a colour bit per node and the invariants that make it balanced.
Its palette is the theme's `rbt` section, so every frame's nodes wear their
semantic colour automatically and the operation highlights compose on top.

Literals here are `rbt.red(v, ..children)` and `rbt.black(v, ..children)` —
which is exactly how the textbook fixtures read:

```typ
#let t = rbt.new(8, 4, 12, 2, 6, 10, 14, 1)
#let violation = rbt.black(8, rbt.red(4, rbt.red(2), none), rbt.black(12))
```

#let rbt-tour = rbt.new(8, 4, 12, 2, 6, 10, 14, 1)

Every display takes `bits: true`, which tags each node with its black-height
bit (`0` red, `1` black) so a reader can count black height down any path:

#align(center, grid(
  columns: 2,
  gutter: 1.5em,
  align: center + horizon,
  last(rbt.display(rbt-tour)),
  last(rbt.display(rbt-tour, bits: true)),
))

== Insert

`insert-display(t, v)` traces the CLRS insertion: a search descent, the new
value spliced in as a red leaf, then the fix-up loop — Case 1 (red uncle:
recolour and continue at the grandparent), Case 2 (zigzag: rotate the parent
to straighten the red-red pair), Case 3 (straight line: rotate the
grandparent and swap colours) — and a final blackening of the root if it
ended up red.

#align(center, stacked(rbt.insert-display(rbt-tour, 0)))

== Delete

`delete-display(t, v)` traces the search, the predecessor walk when the
target has two children, the transfer, the excise, and the four-case
rebalancing loop. Cases 1, 3, and 4 each emit the rotation and the recolour
as separate frames, so the structural pivot lands apart from the colour
swap; Case 2 is a pure recolour and emits one.

Excising a black node leaves its subtree one black short of the rest of the
tree, and the animation marks that with the textbook filled circle at the
child end of the affected edge. It persists across every fix-up step that
does not resolve it, and disappears when a Case 4 rotation drains it or a
red ancestor absorbs it.

#align(center, stacked(rbt.delete-display(rbt-tour, 6)))

== Fix-ups from a hand-built tree

`fixup-display(t, violation-path)` runs the red-red fix-up on a tree you
built yourself, with `violation-path` naming the *lower* of the two reds.
The tree is deliberately not validated: the whole point is to show
configurations a single `insert` cannot produce — a red-red in the middle of
a tree, or a multi-level Case 1 propagation that ends by blackening the
root.

#align(center, stacked(rbt.fixup-display(
  rbt.black(10, rbt.red(5, rbt.red(3), none), rbt.black(15)),
  "LL",
)))

`rbt` also has `search-display` and the four traversals, which behave
exactly as the BST's do while keeping the red-black colouring underneath.

= AVL trees

`avl` is a height-balanced BST: every node carries its `height`, and after
any operation no node's two subtrees differ in height by more than one.
Imbalances are repaired by the four textbook cases — LL, RR, LR, RL.

`avl.node(v, ..children, height: auto)` computes the height for you, which
is the recursion nobody should be writing by hand. Pass `height:` explicitly
only to build a *deliberately stale* tree — a spine caught mid-operation, so
that `fixup-display` has something to fix.

#let avl-tour = avl.new(5, 3, 7, 2, 4, 6, 8, 1, 9)

Two display flags make the balance visible. `factors: true` tags every node
with its signed balance factor; `heights: true` labels each non-root edge
with the height of the subtree below it (the root has no incoming edge, and
its children's labels make its own factor readable anyway).

#align(center, grid(
  columns: 3,
  gutter: 1.2em,
  align: center + horizon,
  last(avl.display(avl-tour)),
  last(avl.display(avl-tour, factors: true)),
  last(avl.display(avl-tour, heights: true)),
))

== Insert

The descent and the splice are the BST's; what follows is AVL's. The climb
back to the root recomputes each ancestor's height in turn, and at the first
node whose balance factor reaches #sym.plus.minus 2 the animation names the
case, applies the child rotation if it is a zigzag (LR or RL), and finishes
with the rotation at the imbalanced node. One insertion restores the
subtree's original height, so the climb stops there.

#align(center, stacked(avl.insert-display(avl-tour, 0, factors: true)))

== Delete

Delete runs the same climb, but a deletion can shorten a subtree — so
several ancestors may need rotating, and the loop runs all the way to the
root.

#align(center, stacked(avl.delete-display(avl-tour, 3, factors: true)))

== Rotate and fix-up

`rotate-display(t, child)` is the same six-frame structural rotation the BST
has, with heights refreshed afterwards. It is *not* what `insert` and
`delete` use internally — those narrate recompute-then-rotate case by case.

`fixup-display(t, violation-path)` runs the climb on a hand-built tree,
walking every proper prefix of `violation-path` deepest-first. With
`avl.node`'s `height:` escape hatch you can write down the stale spine a
mid-operation tree really has:

#let avl-stale = avl.node(
  5,
  avl.node(3, avl.node(2, avl.leaf(1), none, height: 2), none, height: 3),
  avl.leaf(7),
  height: 4,
)

#align(center, stacked(avl.fixup-display(avl-stale, "LLL", factors: true)))

Search and the four traversals come from the same shared implementation the
BST uses, and take `factors:` / `heights:` like everything else here.

= 2-3-4 trees

`b24` is a B-tree of order 4: every node holds one, two, or three keys (so
two, three, or four children) and every leaf sits at the same depth. Nodes
draw as subdivided rectangles that widen with their key count, and an
individual compartment is addressed by suffixing its node's path with
`#<i>` — `"01#1"` is the middle key of the leftmost grandchild.

```typ
#let t = b24.new(10, 5, 15, 1, 7, 12, 20, 25, 30, 17, 19)
#let fixture = b24.node((10, 20), b24.leaf(1, 5), b24.leaf(12), b24.leaf(25, 30))
```

#let b24-tour = b24.new(10, 5, 15, 1, 7, 12, 20, 25, 30, 17, 19)

#align(center, last(b24.display(b24-tour)))

== Two strategies

`insert` and `delete` (and their displays) take `strategy:`:

- *`"top-down"`* (the default) is preventive and single-pass: split any
  3-key node on the way down when inserting; refill any 1-key node on the
  way down when deleting.
- *`"bottom-up"`* is reactive: walk to the leaf first, then propagate splits
  or merges back up the descent path.

Both produce valid 2-3-4 trees with the same keys, but the *shapes* can
legitimately differ — bottom-up promotes from the post-overflow 4-key state,
so the freshly inserted key may itself be promoted, while top-down promotes
the middle of the pre-insert 3-key state.

#align(center, stacked(b24.insert-display(b24-tour, 13)))

The same insertion, bottom-up:

#align(center, stacked(b24.insert-display(b24-tour, 13, strategy: "bottom-up")))

== Search and delete

Search highlights one compartment per comparison and leaves the descent lit
behind it. Delete narrates the preventive fix (borrow left, borrow right, or
merge) before each step down, and an internal-key deletion swaps with its
predecessor and keeps descending to remove that key from its leaf.

#align(center, stacked(b24.search-display(b24-tour, 19)))

#align(center, stacked(b24.delete-display(b24-tour, 15)))

The four traversals sample the traversal palette across the *compartment*
visit order — in-order threads each key between its flanking subtrees, while
pre- and post-order group a node's keys at the node visit.

#align(center, last(b24.in-order-display(b24-tour)))

= Tries

`trie` stores a *set of strings*. A node has no key of its own: its identity
is the prefix spelled by the edges from the root down to it, which gives the
drawing its two teaching conventions.

- *Letters live on the edges*, drawn in the render theme's `edge-tag-fill` —
  the same persistent-label slot AVL heights and graph weights use. Reading
  the edges spells the prefix.
- *Nodes show their word-end bit* — `1` when a stored word ends there, `0`
  for an interior prefix — and word-end nodes are shaded from the theme's
  `trie` section.

#let trie-tour = trie.new("cat", "car", "card", "dog", "do")

#align(center, last(trie.display(trie-tour)))

Note that `"do"` is both a stored word and an interior node on the way to
`"dog"`: a word end need not be a leaf.

== Search

`search-display(t, word)` walks one character at a time and ends in one of
three ways: at a word end (*found*), at an interior node (*a prefix only*),
or at a character with no matching edge (*a miss*, ringing the last node it
did match).

#align(center, stacked(trie.search-display(trie-tour, "card")))

#align(center, stacked(trie.search-display(trie-tour, "ca")))

== Insert and delete

Insert walks the longest existing prefix, then grows the remaining suffix
one node per frame before flipping the endpoint's bit. Delete unmarks the
word end and then prunes the dead branch one node per frame, stopping at the
first ancestor that is itself a word end or has another child.

#align(center, stacked(trie.insert-display(trie-tour, "bat")))

#align(center, stacked(trie.delete-display(trie-tour, "dog")))

Both take the shapes that change nothing gracefully: inserting an existing
prefix only flips a bit, and deleting a word that other words extend only
unmarks it.

= Graphs

`graph` is an undirected-or-directed weighted graph with animations for
Prim's and Kruskal's minimum spanning trees, Dijkstra's shortest paths, and
breadth- and depth-first traversal. It has no root, so nodes are named by
plain string ids and edges by `graph.edge-key(u, v)`.

== Construction and layout

Layout is decoupled from drawing: the graph carries node positions in cetz
units and the backend draws nodes there.

```typ
#let g = graph.new(
  (("A", 0, 0), ("B", 3, 0.4), ("C", 1.5, 2.4), ("D", 4.5, 2.2)),
  edges: (("A", "B", 7), ("B", "C", 2), ("A", "C", 4),
          ("C", "D", 5), ("B", "D", 1)),
)
```

A node spec is a bare id, an `(id, label)` pair (label but no position —
pair it with auto-layout), an `(id, x, y)` triple, or `(id, x, y, label)`.
An edge's third slot dispatches on type: a *number* is the weight, a *string
or content* is a label drawn in its place, and the four-slot form
`(u, v, weight, label)` sets both — so an algorithm can run on the numeric
weight while the drawing shows `4 ms`.

#let g-tour = graph.new(
  (("A", 0, 0), ("B", 3, 0.4), ("C", 1.5, 2.4), ("D", 4.5, 2.2)),
  edges: (
    ("A", "B", 7), ("B", "C", 2), ("A", "C", 4), ("C", "D", 5), ("B", "D", 1),
  ),
)

#align(center, last(graph.display(g-tour)))

Hand placement is the first-class path — small teaching graphs read best
when you control the layout — and every display takes `scale:` (default `1`)
to multiply the coordinates while the drawn node size stays fixed. Reach for
it when a hand-placed graph is too cramped for a wide slide; to resize
everything together, wrap the result in Typst's own `scale` instead.

== Adjacency tables

`adjacency-matrix(g)` and `adjacency-list(g)` return placeable Typst tables
rather than frames — no cetz, no animation. They show 1/0 presence and bare
neighbour ids by default; `weights: true` shows each edge's display label
instead, marking non-edges with `none-marker` and empty rows with
`empty-marker`. A directed graph reads row = source, column = target.

#align(center, grid(
  columns: (auto, auto),
  column-gutter: 2em,
  align: horizon,
  graph.adjacency-matrix(g-tour, weights: true),
  graph.adjacency-list(g-tour, weights: true),
))

// One row per frame: the canvas beside its auxiliary strip.
#let aux-rows(frames) = stack(
  dir: ttb,
  spacing: 0.8em,
  ..frames.map(f => grid(
    columns: (auto, auto),
    column-gutter: 1.5em,
    align: horizon,
    canvas(f),
    aux-strip(f.step),
  )),
)

== Prim's minimum spanning tree

`prim-display(g, start)` grows the tree from `start`. Each round shows the
frontier — the crossing edges — with the lightest picked out, commits it,
and settles the newly reached node, while the caption tracks the running
weight. A terminal *prune* frame then hides every non-tree edge, so the
animation ends on the spanning tree alone.

#align(center, stacked(graph.prim-display(g-tour, "A")))

Prim's bookkeeping is a priority queue of crossing edges, and `aux-strip`
renders it beside the canvas — min on top, the chosen edge ringed:

#align(center, aux-rows(graph.prim-display(g-tour, "A").slice(1, 3)))

== Kruskal's minimum spanning tree

`kruskal-display(g)` considers edges in weight order, adding each unless it
would close a cycle. The union-find forest shows as *node colour*: same
colour means same set, and colours merge as components do.

#align(center, stacked(graph.kruskal-display(g-tour)))

Kruskal carries two auxiliary views, and `aux-strip` stacks both: the sorted
edge list with a cursor under the edge being considered and each edge tagged
added / rejected / pending, and the disjoint-set partition. Pass
`view: "partition"` to place one alone.

#let kruskal-frames = graph.kruskal-display(g-tour)
#align(center, aux-rows((kruskal-frames.at(2), kruskal-frames.at(8))))

== Dijkstra's shortest paths

`dijkstra-display(g, source, target: none)` models the priority queue the
way students implement it: the queue starts with `source` alone, and each
improving relaxation *adds a fresh `(node, dist)` entry* rather than
decreasing a key — so a node can sit in the queue several times. Each round
polls the minimum, marks it visited, and relaxes its unvisited neighbours.
Polling a stale duplicate for an already-visited node produces a *skip*
frame, which is the reason the `if u is not visited` guard exists. Ties
break alphabetically.

#let dg-tour = graph.new(
  (("S", 0, 0), ("A", 2.5, 1.2), ("B", 2.5, -1.2), ("T", 5, 0)),
  edges: (
    ("S", "A", 1), ("S", "B", 4), ("A", "B", 1), ("A", "T", 5), ("B", "T", 1),
  ),
  directed: true,
)

#align(center, stacked(graph.dijkstra-display(dg-tour, "S", target: "T")))

Three auxiliary views ride along — the queue, the `dist` map, and the `prev`
map — selectable with `view: "dist-pq"` / `"dist-map"` / `"prev-map"`:

#align(center, aux-rows(graph.dijkstra-display(dg-tour, "S").slice(2, 4)))

Two flags tailor the canvas. `node-distances: false` drops the tentative
distances from the nodes, for when the `dist` view already carries them.
`reconstruct: true` (which needs a `target`) appends the path-reconstruction
phase: instead of lighting the whole path at once, it walks `prev` backwards
from the target, prepending one node per frame while the `prev` view traces
the chain it reads.

#align(center, aux-rows(
  graph
    .dijkstra-display(
      dg-tour,
      "S",
      target: "T",
      node-distances: false,
      reconstruct: true,
    )
    .slice(-3),
))

== Traversals

`bfs-display(g, start)` and `dfs-display(g, start)` sample the traversal
palette across the visit order, badge each node with its 1-indexed position,
and accumulate the sequence in the caption — the same vocabulary as the tree
traversals.

#align(center, grid(
  columns: (1fr, 1fr),
  align: center,
  last(graph.bfs-display(g-tour, "A")),
  last(graph.dfs-display(g-tour, "A")),
))

Three flags:

- `target:` turns the traversal into a *search* that stops the moment the
  target is visited, ending on `Found <t>` — or, if it is unreachable, on
  `<t> not found` after the whole component.
- `sort-frontier: true` enqueues each node's unseen neighbours in ascending
  id order instead of edge-declaration order, for a deterministic walk.
  (The sort is lexicographic, so `"10"` precedes `"2"`.)
- `spanning-tree: true` renders the *traversal tree* instead of the palette
  walk: each node joins with a uniform commit style and its discovery edge
  lights up, accumulating into the BFS or DFS spanning tree, and a final
  frame prunes the cross edges away. It covers the whole component, so it
  takes no `target:`.

#align(center, grid(
  columns: (1fr, 1fr),
  align: center,
  last(graph.bfs-display(g-tour, "A", spanning-tree: true)),
  last(graph.dfs-display(g-tour, "A", spanning-tree: true)),
))

Every frame carries the queue or stack in its `step`, and the DFS stack is
faithful to the iterative algorithm — the same id can appear twice, because
a node may be pushed again before an earlier copy is popped:

#align(center, aux-rows(graph.dfs-display(g-tour, "A").slice(2, 4)))

== Node shapes and sizing

The default circle is sized for short ids. Pass `node-style:` to any display
to restyle every node at once — it sits beneath the per-frame algorithm
styling, so shape and size persist while fills and strokes animate on top.
`shape` takes `"circle"`, `"ellipse"`, or `"rectangle"`; `autosize: true`
fits each node to its own label; `r` or `rx` / `ry` pin a size instead.
Edges trim to whatever boundary the shape defines, so arrowheads stay flush.

#let g-people = graph.new(
  (
    ("A", 0, 0, [Alice]), ("B", 3, 0, [Bob]),
    ("C", 1.5, 2.4, [Charlie]), ("D", 4.5, 2.4, [Dan]),
  ),
  edges: (
    ("A", "B", 1), ("A", "C", 1), ("B", "C", 1), ("B", "D", 1), ("C", "D", 1),
  ),
)

#align(center, last(graph.display(
  g-people,
  node-style: (shape: "ellipse", autosize: true),
)))

== Optional auto-layout with graphviz <auto-layout>

For graphs too large to place by hand, `auto-layout(g, engine:, unit:,
sizes:)` computes positions with graphviz through the `diagraph-layout`
package — a WASM build, so no external binary is involved. Feed its result
to any display's `positions:`, or skip the intermediate map by passing
`layout:` and letting the display call it:

```typ
#let g = graph.new(("A", "B", "C"), edges: (("A", "B", 7), ("B", "C", 2)))

#last(graph.prim-display(g, "A", positions: auto-layout(g)))
#last(graph.display(g, layout: "neato", node-style: (shape: "ellipse", autosize: true)))
```

The `layout:` form feeds graphviz a per-node size estimate so wide labels
get spread apart. That estimate is a cheap label-length heuristic computed
without `measure`, whereas the drawn node is measured exactly — the two only
approximate each other, and graphviz's margins absorb the slack. Tune the
result with the display's `scale:` or with `layout-unit:`.

`diagraph-layout` stays an *optional* dependency even though the entrypoint
re-exports `auto-layout`: the import sits inside the function's body, which
Typst resolves only when the function is actually called. Projects that hand
place their graphs never fetch it.

= Hash maps

A `hashmap` is a fixed array of `capacity` slots, a *pluggable* hash
function, and one of four collision strategies:

- `"chaining"` — each slot holds a list of entries.
- `"linear"` — open addressing, probing `(h + i) mod m`.
- `"quadratic"` — open addressing, probing `(h + i*i) mod m`.
- `"double"` — open addressing, probing `(h1 + i * h2) mod m`, with the step
  from a second hash.

There is no layout to supply — the geometry follows from the capacity — so
the displays take an `orientation:` (`"horizontal"`, the default, or
`"vertical"`) instead of positions.

```typ
#let h = hashmap.new(5, strategy: "chaining", entries: (5, 10, 7, 3, 8, 13))
```

`entries:` seeds the table by inserting each item in order (a bare key, or a
`(key, value)` pair). `hash:` is any `(k, m) => index` and `hash-repr:` its
on-screen form, with `k` and `m` substituted as whole words — so write them
standalone (`"(k * 3) mod m"`), since `"3k"` will not substitute. Double
hashing takes a second pair, `hash2:` / `hash2-repr:`, defaulting to
`1 + (k mod (m - 1))`: nonzero, and coprime to a prime `m`, so the probe
visits every slot.

#let hm-chain = hashmap.new(5, strategy: "chaining", entries: (5, 10, 7, 3, 8, 13))
#align(center, last(hashmap.display(hm-chain)))

Empty slots are muted, a bucket's chain hangs below it, and a deleted
open-addressing slot shows a tombstone. Entries carry a key and an optional
value, drawn as a smaller second line.

By default the displays *fit* each cell to the widest label in the whole
animation — in both width and height, so entries stay legible at slide font
sizes, and so the table never resizes mid-animation as a label grows. That
is `cell-width: "fit"`; a number pins an exact width in cetz units, and
`auto` keeps a fixed footprint without measuring (which is what
`positioned` defaults to, since that path can run outside a layout
context).

#{
  let h = hashmap.new(5, strategy: "linear")
  let h = hashmap.insert(h, 3, value: "v1", label: "(k1, v1)")
  let h = hashmap.insert(h, 8, value: "v2", label: "(k2, v2)")
  align(center, last(hashmap.display(h)))
}

== The hash box

Every `insert` / `search` / `delete` opens by computing the hash, and the
animation draws a *hash box* — `h(<key>) = <formula> = <index>` — above the
target slot with an arrow into it, so the key #sym.arrow bucket mapping is
explicit before any probing starts.

The opening frame invisibly reserves that box's exact footprint, and the
terminal frames that drop it reserve it again, so every frame of the walk
renders at the same canvas size and the table does not jump when the box
appears or disappears on the next subslide. Top-align the canvas in your
deck and the whole animation stays pinned.

== Insertion, by strategy

Chaining hashes to a bucket, walks the chain comparing keys — so a repeated
key updates in place — and appends at the tail:

#align(center, stacked(hashmap.insert-display(
  hashmap.new(5, strategy: "chaining", entries: (5, 10, 7)),
  20,
)))

Linear probing steps to the next slot until it finds a free one:

#align(center, stacked(hashmap.insert-display(
  hashmap.new(7, strategy: "linear", entries: (14, 21, 7)),
  28,
)))

Quadratic probing spreads the probes out, which reduces the primary
clustering linear probing suffers. The trade-off is that its sequence visits
only a subset of the slots: it can report the table *full* while empty slots
remain — a genuine teaching point, and a terminal frame of its own.

#align(center, stacked(hashmap.insert-display(
  hashmap.new(7, strategy: "quadratic", entries: (0, 7, 14)),
  21,
)))

Double hashing takes the *step size* from a second hash, so two keys that
collide at the same home slot generally walk different slots afterwards. The
hash box shows both.

#align(center, stacked(hashmap.insert-display(
  hashmap.new(7, strategy: "double", entries: (14, 21, 7)),
  28,
)))

== Search

Open-addressing search *stops at the first empty slot* but *steps over
tombstones*, so a lookup for a key sitting past a deleted entry still finds
it:

#align(center, stacked(hashmap.search-display(
  hashmap.delete(hashmap.new(7, strategy: "linear", entries: (14, 21, 7)), 21),
  7,
)))

A chaining miss walks to the end of the bucket and rings a *phantom* null
cell hung one past the last entry — the slot the search fell off the chain
into — rather than the keyless bucket header, which would read as if the
bucket itself were the miss.

#align(center, stacked(hashmap.search-display(
  hashmap.new(5, strategy: "chaining", entries: (5, 10, 7, 3, 8)),
  15,
)))

== Deletion, tombstones, and a deliberate bug

Chaining unlinks the entry and re-links the chain. Open addressing cannot
blank the slot — that would truncate every probe sequence running through it
— so it writes a *tombstone* that search skips and insert may reuse.

#align(center, stacked(hashmap.delete-display(
  hashmap.new(7, strategy: "linear", entries: (14, 21, 7)),
  21,
)))

To show *why*, `delete` and `delete-display` take `tombstone: false`: the
naive deletion that clears the slot instead. Here 14, 21 and 7 all hash to
slot 0, so clearing 21 severs the probe chain and a later search for 7 stops
at the hole and wrongly reports a miss — even though 7 is still in slot 2.

#let naive-hm = hashmap.new(7, strategy: "linear", entries: (14, 21, 7))
#align(center, last(hashmap.delete-display(naive-hm, 21, tombstone: false)))
#align(center, stacked(hashmap.search-display(
  hashmap.delete(naive-hm, 21, tombstone: false),
  7,
)))

== Resizing and rehashing

`resize-display(h, new-cap)` allocates a larger array and replays every live
entry through the hash under the new capacity, one entry per frame, so the
load factor drops and old collisions scatter:

#align(center, stacked(hashmap.resize-display(
  hashmap.new(7, strategy: "linear", entries: (14, 21, 7, 3)),
  11,
)))

The matching teaching bug is `rehash: false`: grow the array but copy each
entry to its *old* index. 14, 21 and 7 land back in slots 0, 1, 2, but
`h(7) = 7 mod 11 = 7` now — so a later search probes slot 7, finds it empty,
and misses a key that is still in the table. (It needs `new-cap >=
capacity`, so the old indices still fit.)

#let stale-hm = hashmap.resize(
  hashmap.new(7, strategy: "linear", entries: (14, 21, 7)),
  11,
  rehash: false,
)
#align(center, last(hashmap.resize-display(
  hashmap.new(7, strategy: "linear", entries: (14, 21, 7)),
  11,
  rehash: false,
)))
#align(center, stacked(hashmap.search-display(stale-hm, 7)))

== Palette

The `hashmap` theme section holds `empty-fill`, `index-fill`,
`hash-box-fill` / `-stroke`, `tombstone-fill` / `-stroke`, and `chain-stroke`
/ `chain-fill`:

#align(center, last(hashmap.display(
  hashmap.new(5, strategy: "chaining", entries: (5, 10, 7, 3)),
  theme: (hashmap: (empty-fill: rgb("#eef3ff"), index-fill: rgb("#3355aa"))),
)))

= Linear sorts

`sort` animates the two *distribution* sorts — counting sort and LSD radix
sort. They don't compare and swap; they read a value, compute an index, and
write a cell, which is exactly the rows-of-boxes-with-arrows vocabulary the
array backend draws.

```typ
#let s = sort.new(3, 1, 4, 1, 5)     // or sort.new((3, 1, 4, 1, 5))
```

Keys must be non-negative integers, because the value *is* an index into the
count array. To sort an enumeration you would rather show by name, give an
element as `(value: <int>, label: <content>)`: the integer orders it, the
label is drawn, and the two may be mixed freely with bare integers. The pure
`sort.counting(s, k: auto)` and `sort.radix(s, base: 10)` return the sorted
keys (`sort.sorted(s)` is the built-in-sort oracle); the labels are a
display concern.

#align(center, last(sort.display(sort.new(3, 1, 4, 1, 5, 9, 2, 6))))

== Counting sort

`counting-display(s)` animates the stable, prefix-sum counting sort: sweep
the input to fill the *count* row (indexed *by value*, so a read arrow lands
on the bucket the element names), turn the counts into cumulative end
positions, then walk the input *right to left* — the stability radix sort
depends on — placing each value at `output[count[value] - 1]` and
decrementing.

#align(center, stacked(sort.counting-display(sort.new(1, 0, 2, 1))))

The count array is sized `max + 1` by default; pass `k:` to reserve a larger
range. Three arguments change the telling:

`variant: "reconstruct"` animates the intro version instead — build the
histogram, then sweep the buckets and emit each value `count[v]` times. It
sorts, but it uses neither the prefix sums nor a right-to-left pass, so it
does not demonstrate stability. (It also rebuilds from the histogram alone,
which is why it can only show the first-seen label per key: discarding
element identity is precisely what makes it unstable.)

#align(center, stacked(sort.counting-display(
  sort.new(2, 0, 1, 2),
  variant: "reconstruct",
)))

`separate-counts: true` keeps the raw histogram in the `count` row all pass
and builds the cumulative sums in their own row below it, instead of
overwriting the histogram in place. It costs a row and buys the clearer
telling of *why* the prefix sum gives each value its slot.

#align(center, stacked(sort.counting-display(
  sort.new(1, 0, 2, 1, 3),
  separate-counts: true,
)))

`variant: "buckets"` draws the count array as a *chaining hash table* with
the identity hash. Each element is copied into the tail of its value's
chain, then the buckets are read left to right, each chain head to tail, into
the output. It is deliberately space-inefficient — the whole element lives in
the bucket — but it makes the mechanism concrete: sorting *is* distributing
into value-indexed buckets and concatenating them. Tail-append plus head-first
read means it is stable, and labels ride their chains faithfully.

#align(center, stacked(sort.counting-display(
  sort.new(
    (value: 2, label: [Tue]), (value: 0, label: [Sun]),
    (value: 2, label: [Tue]), (value: 1, label: [Mon]),
  ),
  variant: "buckets",
)))

== Radix sort

`radix-display(s, base: 10)` is LSD radix sort as *one stable counting-sort
pass per digit place*, keyed on the extracted digit — so the count row has
`base` buckets and each input cell wears its digit for the active pass as a
subscript. Because each pass is the counting sort above, radix is a thin
wrapper over the same engine.

#align(center, stacked(sort.radix-display(sort.new(23, 4, 8))))

Labels travel with their keys through every pass, so an enumeration comes
out reordered by name:

#align(center, stacked(sort.radix-display(sort.new(
  (value: 23, label: [23kg]), (value: 4, label: [4kg]), (value: 8, label: [8kg]),
))))

The `sort` theme section holds `empty-fill`, `index-fill`, `row-label-fill`,
`count-fill` (the histogram and bucket tint), `active-digit-fill` (the radix
subscript), and `chain-stroke`.

= Skip lists

A `skiplist` is a sorted set of non-negative integer keys stored as a
probabilistic multi-level linked list: every key sits at level 0 and each
also rises through a tower of express lanes that let a search skip ahead. It
draws as a sparse grid — a header sentinel, one column per key, an optional
`NIL` tail — with forward pointers at each level skipping the columns whose
towers don't reach that high.

```typ
#let s = skiplist.new(3, 1, 4, 7, 5, seed: 7)        // coin-flipped towers
#let s = skiplist.new(                                // pinned towers
  (value: 2, height: 1), (value: 5, height: 3),
  (value: 8, height: 1), (value: 12, height: 2),
)
```

Tower heights come from an explicit `height` or from a *deterministic*
seeded coin flip (grown with probability `p`, default one half, capped at
`max-level`), so a document renders the same every time. Forward pointers
are not stored: at level #sym.ell the list is exactly the subsequence of
nodes whose towers reach that high, so the backend derives them.

#let sl = skiplist.new(
  (value: 2, height: 1), (value: 5, height: 3), (value: 8, height: 1),
  (value: 12, height: 2), (value: 17, height: 1), (value: 20, height: 2),
)

#align(center, last(skiplist.display(sl)))

A node's tower is one flush column of *pointer cells*, one per level it
reaches, sitting above a separate *data box* that holds the key. Because no
forward pointer attaches to the data box, a link never crosses a key.

== Search

`search-display(s, key)` animates the top-left descent: move right while the
next key is below the target, drop a level the moment it would overshoot.
The whole descent stays lit — every box stepped on and pointer followed
accumulates into a trail, while the current comparison is picked out — so
the finished animation reads as one continuous path.

#align(center, stacked(skiplist.search-display(sl, 17)))

== Insert and delete

Both are *interleaved single passes*: the pointer surgery happens as the
descent reaches each lane, because the descent lands on the target's
predecessor on every lane it occupies. There is no separate splice phase and
no backtracking.

On insert the new node stays a *ghost* — its column reserved, so the grid
never shifts — until the descent first reaches its top lane, where it
materializes; each lower lane is then woven in as the descent lands on it. A
lane the node isn't linked on yet is drawn muted with the list's pointer
running *over* it, so it is clear the list still skips past it there.

#align(center, stacked(skiplist.insert-display(sl, 9, height: 3)))

Delete is the mirror image: each lane is unlinked as the descent reaches it,
the predecessor bypassing the target from the top down, and the node is left
detached in place so it reads as removed rather than vanishing.

#align(center, stacked(skiplist.delete-display(sl, 5)))

`delete-display(s, key, search: false)` drops the pure navigation frames and
keeps the surgery — "the pointer work without the walk that found it".

The `skiplist` theme section holds the header and `NIL` palettes,
`index-fill` (the `head` caption), `pointer-stroke`, and the `unlinked-*`
trio that mutes a lane the node isn't linked on.

#align(center, last(skiplist.display(sl, theme: (skiplist: (
  header-fill: rgb("#e8f7ee"),
  header-stroke: rgb("#2f855a"),
  pointer-stroke: rgb("#3355aa"),
)))))

= Git commit graphs <git-graph>

The `git` namespace draws git histories — commits, branches, merges, tags,
and HEAD/branch pointers. It is the one part of starling that does *not*
ride the frame stack: rather than an immutable structure animated step by
step, it is a *stateful, imperative cetz builder*. You call `commit` /
`branch` / `merge` inside a `git-graph({ .. })` block and the verbs mutate
cetz's canvas context as they draw, so the presentation helpers do not apply
— you place the block directly inside a `cetz.canvas`.

Its verbs have names too generic to sit in the flat layer, so they stay
behind the namespace:

```typ
#import "@preview/cetz:0.5.2"
#import "@preview/starling:1.0.0" as starling
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

#align(center, cetz.canvas(git.git-graph({
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
})))

Create the initial branch before the first commit. `merge(branch)` takes the
*branch name* to merge in; `commit`, `branch`, and `merge` accept a `name:`
so later annotations survive reordering; `detached-commit(from, msg, name)`
draws an orphan dot for `head-pointer(target: name)` to hang off; and
`background-lanes()` rules each branch's lane.

Animation is touying-native: put `pause` or `alternatives(..)` markers
inside the canvas body, or redraw a dot with `git-highlight`. Pass
`direction: "left-to-right"` to lay commits out rightward instead of upward;
the label angles and anchors switch with it.

#align(center, cetz.canvas(git.git-graph(
  direction: "left-to-right",
  {
    git.branch("main")
    git.commit("a")
    git.branch("topic")
    git.commit("b")
    git.checkout("main")
    git.commit("c")
    git.background-lanes()
  },
)))

Styling comes from the theme's `git` section — the branch `colors` palette
plus the `lane-style` / `graph-style` / `commit-style` / `tag-style` /
`pointer-style` sub-dicts — and a per-call `theme:` layers over the document
theme exactly like any display's:

```typ
#cetz.canvas(git.git-graph(theme: (git: (colors: (teal, maroon, olive))), history))
```

Because those sub-styles are dicts, overriding one replaces it whole: pass a
complete dict for the role you change. Behavioural arguments —
`direction:`, `commit-spacing:`, `lane-spacing:` — are *not* theme; they
stay arguments of `git-graph`.

= Migrating from 0.3.x <migration>

Version 1.0.0 replaced typsy classes with plain dictionaries and namespaced
the API per structure. There are no shims: old names are gone, and the
compiler will tell you so. The mapping is mechanical.

#table(
  columns: (1fr, 1fr),
  inset: 6pt,
  align: (left, left),
  table.header[*0.3.x*][*1.0.0*],
  [`bst(16, 11, 29)`], [`bst.new(16, 11, 29)` — plus `bst.node` / `bst.leaf`
    for literals],
  [`trie("cat")`, `graph(nodes, edges: ..)`, `hashmap(7, ..)`, `sort(..)`,
    `skiplist(..)`],
  [`trie.new(..)` and so on — every factory became its namespace's `new`],

  [`(s.style-node)(p, fill: red)` on a snapshot],
  [`with-node(s, p, (fill: red))` — or `apply-snapshot(s, style-node(p, fill:
    red))` to fold in a whole stream],
  [`(t.insert)(5)`], [`bst.insert(t, 5)`],
  [`(t.insert-display)(5)`], [`bst.insert-display(t, 5)`],
  [`(t.insert-display)(5)` then `(t = (t.insert)(5))`],
  [`let f = bst.insert-display(t, 5)` then `t = result(f)`],

  [`(Op.StyleNode.new)(path: p, style: (fill: red))`],
  [`style-node(p, fill: red)`],

  [`(Op.Commit.new)(alt: a)`], [`commit(alt: a)`],
  [`(Op.Highlight.new)(path: p, color: c)`], [`style-node(p, stroke: c + 2pt)`],
  [`Op.ClearNotes`], [`style-node(key, note: none)` on the keys to clear],
  [`starling.make-renderer(t)`], [`bst.renderer(t, sticky: true)` — `sticky`
    now defaults to `false`],
  [`(r.render)()`], [`render(r)`],
  [`paint-rbt(make-renderer(t), t, bits: true)`], [`rbt.renderer(t, bits: true)`],
  [`paint-trie(r, t)`], [`trie.renderer(t)`],
  [`make-graph-renderer(g.positioned())`], [`graph.renderer(g)` — it takes the
    *graph* and positions internally, so drop the `positioned` call.
    `graph.positioned` stays, for a hand-composed `draw-graph` canvas],
  [`theme:` (op-theme, on bst/avl/b24/graph)], [`theme: (op: (..))`],
  [`theme:` (palette, on rbt/trie/hashmap/sort/skiplist)], [`theme: (rbt: (..))`
    and so on],
  [`render-theme: (..)`], [`theme: (render: (..))` — on a `draw-*` call too;
    a partial theme layers over the default there as well],
  [`set-op-theme(..)`, `set-render-theme(..)`, `set-rbt-theme(..)`, …],
  [`set-theme((op: .., render: .., rbt: ..))` — one state, one setter],

  [`default-op-theme.attention-stroke`], [`default-theme.op.attention-stroke`],
  [`path-anchor(p, tree-name: "t")`], [`anchor(p, canvas: "t")`],
  [`node-anchor(id)`, `cell-anchor(i)`, `array-cell-anchor(r, c)`,
    `sl-box-anchor(c, l)`],
  [`anchor(id)`, `hashmap.cell-anchor(i)`, `sort.cell-anchor(r, c)`,
    `skiplist.box-anchor(c, l)` — one `<x>-anchor` per `<x>-key`],

  [`cell-key(i)` / `entry-key(i, j)`], [`hashmap.cell-key(i)` /
    `hashmap.entry-key(i, j)`],
  [`array-cell-key(row, col)`], [`sort.cell-key(row, col)`],
  [`array-arrow-key(id)`], [deleted — the id *is* the key],
  [`sl-box-key` / `sl-forward-key` / `sl-data-key`], [`skiplist.box-key` /
    `.forward-key` / `.data-key`],
  [`mst-prim-display` / `mst-kruskal-display`], [`graph.prim-display` /
    `graph.kruskal-display`],
  [`counting-sort-display` / `radix-sort-display`], [`sort.counting-display` /
    `sort.radix-display`; the pure ops are `sort.counting` / `sort.radix`],
  [`canvases-only(frames)`], [`frames.map(f => canvas(f))` — or better,
    `subslides(frames)`],
  [`concat-frames`, `GraphNodeId`, `TreeRenderer`, `Op.Highlight`,
    `Op.ClearNotes`],
  [deleted],
)

Four behaviour changes are worth knowing before you convert a deck.

*Renderers no longer accumulate by default.* `sticky` was `true` in the old
tree-bound `make-renderer`; it is `false` now, so an op stream that expects
each frame to build on the last must say `sticky: true`.

*A per-call `theme:` layers over the document theme* rather than replacing
it. Before, passing `theme:` reset the palette to the defaults and skipped
`set-*-theme` entirely; now naming two keys changes those two and leaves the
rest of your theme alone.

*Every animation's last frame carries `step.result`.* The old pattern of
writing each operation twice — once for the frames, once to advance the
variable — is what `result(frames)` replaces.

*Alt text is always set explicitly*, and captions are always content (the
sort and trie captions that used to be strings are not any more). Nothing
derives alt from a caption.

*Hash-map cells are measured once per animation, not once per frame.* The
width fits the widest entry the whole animation will hold, so a frame whose
entries are a subset of that no longer shrinks. Decks that relied on the old
per-frame sizing will see those frames stay wide — that is the fix, not a
regression.

Four smaller notes, all of them things a real port tripped over.

`import cetz.draw: *` inside a canvas now shadows starling's `anchor`, since
cetz has an `anchor` of its own — import selectively.

`bst.insert(t, v)` and its siblings do not compile *inside a function body* —
Typst reads the call as its own mutating `insert` on a captured variable.
Write `(bst.insert)(t, v)`, or import the verb. See @insert-trap; this one bit
hardest in the port, because the error names the namespace and never mentions
`insert`.

There is no `Op` enum: the constructors are top-level functions, each
returning an *array*, so streams compose with `+`. The old constructors
returned a single op, so a deck that accumulates with `ops.push(..)` now
pushes an array into an array. `apply-ops` flattens, so it happens to work,
but write `ops += ..` (and `.flatten()` after a `.map`) and mean it.

Every namespace name — `bst`, `rbt`, `sort`, `graph`, `trie`, `skiplist` — is
an ordinary identifier, so a deck-local `#let sort = ..` or a parameter named
`rbt` now shadows the module. The flat exports are just as stealable: `commit`
in particular collides with the helper decks tend to write around it, and a
local definition wins at module scope, so the helper's own body has to call
`starling.commit(..)` rather than recursing into itself. This is the most
common way a port breaks somewhere unrelated to the edit that caused it.

Backends name their elements through `anchor(<key>)` now, where 0.3.x let each
one choose (the array backend used `acell-<row>-<col>`, the tree backend used
cetz-tree's positional `node-0-0-1`). If a deck builds an element name by
string concatenation rather than calling the helper, the prefix has to change
to `el-`.

// tidy emits a heading per function and per parameter, so the reference
// would otherwise number five levels deep. Keep numbers on the sections a
// reader navigates by and drop them below that.
#set heading(numbering: (..n) => if n.pos().len() <= 3 {
  numbering("1.", ..n.pos())
})

= API reference

The rest of this manual is generated by
#link("https://typst.app/universe/package/tidy")[tidy] from the doc comments
in the source. Names starting with `_` are private and do not appear.

The nine data-structure namespaces come first, then the shared machinery
they are built on, then the drawing layer. Where a module's names are
reachable under a namespace, the heading says which — `bst.insert`,
`styles.ghost`, `git.commit`.

#let api(path, name) = tidy.show-module(
  tidy.parse-module(
    read(path),
    name: name,
    label-prefix: name + "-",
    scope: (starling: starling, cetz: cetz),
  ),
  style: tidy.styles.default,
  show-module-name: false,
)

== `bst` — binary search trees

#api("/src/ds/bst.typ", "bst")

== `rbt` — red-black trees

#api("/src/ds/rbt.typ", "rbt")

== `avl` — AVL trees

#api("/src/ds/avl.typ", "avl")

== `b24` — 2-3-4 trees

#api("/src/ds/b24.typ", "b24")

== `trie` — tries

#api("/src/ds/trie.typ", "trie")

== Shared binary-tree operations

These live in `ds/tree-common.typ` and are re-exported by `bst`, `rbt`, and
`avl` — `bst.contains`, `avl.in-order`, and so on. The `render-*` helpers
are the shared animation bodies those modules build their displays from.

#api("/src/ds/tree-common.typ", "tree-common")

== `graph` — weighted graphs

#api("/src/ds/graph.typ", "graph")

== `hashmap` — hash maps

#api("/src/ds/hashmap.typ", "hashmap")

== `sort` — linear sorts

#api("/src/ds/sort.typ", "sort")

== `skiplist` — skip lists

#api("/src/ds/skiplist.typ", "skiplist")

== `styles` — the semantic style vocabulary

#api("/src/styles.typ", "styles")

== Presentation helpers

Exported flat: `last`, `stacked`, `figures`, `subslides`, `canvas`.

#api("/src/slides.typ", "slides")

== `aux` — auxiliary state strips

`aux-strip` is also exported flat.

#api("/src/aux.typ", "aux")

== The op command stream

Exported flat: `style-node`, `style-edge`, `annotate`, `commit`, `set-alt`,
`set-caption`, `set-step`, `apply-ops`.

#api("/src/core/ops.typ", "ops")

== Frames and renderers

Exported flat: `make-renderer`, `render`, `overlay`, `result`. The rest is
what a custom draw backend or a hand-built display talks to.

#api("/src/core/frame.typ", "frame")

== Snapshots

Exported flat: `blank-snapshot`, `apply-snapshot`.

#api("/src/core/snapshot.typ", "snapshot")

== Styles and style keys

Exported flat: `theme-ref`, `role`. The node- and edge-style key allowlists
below are the complete vocabulary a snapshot may use.

#api("/src/core/style.typ", "style")

== Theme

Exported flat: `default-theme`, `set-theme`.

#api("/src/core/theme.typ", "theme")

== Drawing utilities

Exported flat: `anchor`. The rest is shared geometry and measurement the
backends use, and what a custom backend should reuse.

#api("/src/core/draw-util.typ", "draw-util")

== Alt-text helpers

The string builders every display's alt text goes through, so the narration
reads the same across structures.

#api("/src/core/text.typ", "text")

== Draw backends

Each of these is exported flat (`draw-tree`, `draw-graph`, …) and can be
called inside a `cetz.canvas` of your own, with no `context` needed.

=== `draw-tree`

#api("/src/draw/tree.typ", "draw-tree")

=== `draw-graph`

#api("/src/draw/graph.typ", "draw-graph")

=== `draw-hashmap`

#api("/src/draw/hashmap.typ", "draw-hashmap")

=== `draw-array`

The backend behind `sort`; `sort.cell-key` and `sort.entry-key` are
re-exported from here.

#api("/src/draw/array.typ", "draw-array")

=== `draw-skiplist`

#api("/src/draw/skiplist.typ", "draw-skiplist")

== Graph auto-layout

Exported flat: `auto-layout`.

#api("/src/graph-layout.typ", "graph-layout")

== `git` — the commit-graph DSL

#api("/src/git-graph.typ", "git")
