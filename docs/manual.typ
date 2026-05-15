#import "/src/lib.typ" as starling

#set page(paper: "us-letter", margin: 1in)
#set par(justify: true)
#show raw.where(block: true): set block(fill: luma(245), inset: 8pt, radius: 3pt, width: 100%)

#align(center)[
  #text(22pt, weight: "bold")[Starling]\
  #v(0.3em)
  #text(12pt)[v0.1.0 -- Animated renderings of data structures for teaching]
]

#v(1em)

= Quick start

The package exports a `BST` factory (Typsy class) and the `configure(wrap: ...)`
hook for touying integration.

```typ
#import "@preview/starling:0.1.0": BST

#let t = (BST.new)(value: 4, left: none, right: none)
#let t = (t.insert)(1)
#let t = (t.insert)(7)
#let t = (t.insert)(3)
#let t = (t.insert)(6)
```

#let t = (starling.BST.new)(value: 4, left: none, right: none)
#let t = (t.insert)(1)
#let t = (t.insert)(7)
#let t = (t.insert)(3)
#let t = (t.insert)(6)

A static rendering via `display`:

#align(center, (t.display)())

= Animations

Each `*-display` method produces a sequence of frames showing one operation.
What the package returns from each method is determined by the `wrap` function
passed to `configure(...)`. The default `wrap` collapses the sequence to its
final frame -- useful for static documents like this manual:

```typ
#(t.search-display)(6)   // final-frame-only by default
```

#align(center, (t.search-display)(6))

= Touying integration

In a touying slide deck, pass touying's `alternatives` as the wrap. Each frame
becomes a subslide:

```typ
#import "@preview/touying:0.7.3": *
#import "@preview/starling:0.1.0" as starling

#let (BST,) = (starling.configure)(wrap: alternatives)
```

After that, calls like `(t.insert-display)(5)` animate across subslides.

The configuration is closure-captured, not state-based. Typst's `state` (and
typsy's `safe-state`) would require `context { ... }` blocks to read the
wrap, and touying's `alternatives` is rejected inside `context`. Closure
capture at the `configure` call site avoids the problem.

= BST API summary

Construction: `(BST.new)(value:, left:, right:)`.

Pure operations (return new trees):
- `(t.insert)(v)`
- `(t.delete)(v)`
- `(t.contains)(v)` -- returns bool
- `(t.rotate)(child)` -- right or left rotation, direction inferred
- `(t.describe)()` -- string summary
- `(t.path-to)(v)`, `(t.by-value)(v)`, `(t.resolve)(path)` -- path utilities

Display methods (return content shaped by `wrap`):
- `(t.display)(alt: none)` -- static figure
- `(t.search-display)(v)` -- animated search
- `(t.insert-display)(v)` -- animated insertion
- `(t.delete-display)(v)` -- animated deletion (leaf / one-child / two-children)
- `(t.rotate-display)(child-value)` -- animated rotation

= Lower-level: `tree-anim`

The animation kernel is exposed for building your own animated trees. See
`src/tree-anim.typ` for `make-renderer`, `Frame`, `TreeRenderer`, and
`concat-frames`. Paths are `"L"`/`"R"` strings rooted at `""`.

== Op command stream

`Op` is a declarative layer over the per-frame patch API. Build a list of
`Op` values, fold them into a renderer with `apply-ops`, and render the
result. `Op.Commit` marks the boundary between frames; the trailing
in-progress frame is kept as the final frame, so no closing `Commit` is
needed.

The available variants:

- `Op.Highlight(path, color)` -- set a node's stroke to `color + 2pt`
- `Op.Annotate(path, text)` -- attach a note to a node
- `Op.StyleNode(path, style)` -- arbitrary node-style overrides
  (`fill`, `stroke`, `text-fill`, `note`, `note-fill`, `hide`)
- `Op.StyleEdge(path, style)` -- arbitrary edge-style overrides
  (`stroke`, `mark`, `note`, `note-fill`, `hide`)
- `Op.Caption(text)` -- set the current frame's caption
- `Op.Commit()` -- finalize the current frame and open a fresh one
- `Op.ClearNotes()` -- drop all notes from the current frame

A short walk-through of searching for `1` in the tree above (path `"L"`):

```typ
#import "@preview/starling:0.1.0": make-renderer, apply-ops, Op

#let ops = (
  (Op.Caption.new)(text: [start at root]),
  (Op.Highlight.new)(path: "", color: blue),
  (Op.Annotate.new)(path: "", text: [1 < 4]),
  (Op.Commit.new)(),
  (Op.ClearNotes.new)(),
  (Op.Caption.new)(text: [descend left]),
  (Op.Highlight.new)(path: "L", color: blue),
  (Op.StyleEdge.new)(path: "L", style: (stroke: blue + 2pt)),
  (Op.StyleNode.new)(path: "L", style: (fill: green.lighten(70%))),
  (Op.Annotate.new)(path: "L", text: [1 = 1]),
)

#let r = apply-ops(make-renderer(t, sticky: true), ops)
#(r.render)()   // an array of frames -- pass to `alternatives(..)` or pick one
```

#let op-ops = (
  (starling.Op.Caption.new)(text: [start at root]),
  (starling.Op.Highlight.new)(path: "", color: blue),
  (starling.Op.Annotate.new)(path: "", text: [1 < 4]),
  (starling.Op.Commit.new)(),
  (starling.Op.ClearNotes.new)(),
  (starling.Op.Caption.new)(text: [descend left]),
  (starling.Op.Highlight.new)(path: "L", color: blue),
  (starling.Op.StyleEdge.new)(path: "L", style: (stroke: blue + 2pt)),
  (starling.Op.StyleNode.new)(path: "L", style: (fill: green.lighten(70%))),
  (starling.Op.Annotate.new)(path: "L", text: [1 = 1]),
)
#let op-r = (starling.apply-ops)(starling.make-renderer(t, sticky: true), op-ops)

#align(center, grid(columns: 2, gutter: 2em, ..(op-r.render)()))
