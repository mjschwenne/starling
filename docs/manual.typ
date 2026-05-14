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
`src/tree-anim.typ` for `make-renderer`, `Frame`, `TreeRenderer`,
`concat-frames`, and the experimental `Op` command stream. Paths are
`"L"`/`"R"` strings rooted at `""`.
