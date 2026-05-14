# Starling

<div align="center">Version 0.1.0</div>

Animated renderings of data structures for teaching, built on
[cetz](https://typst.app/universe/package/cetz),
[typsy](https://typst.app/universe/package/typsy),
and (optionally) [touying](https://typst.app/universe/package/touying).

Starling is the animation toolkit for a programming course; it
currently ships a `BST` (binary search tree) and will grow to cover more
structures over time (heaps, hash tables, graphs, etc.).

## Quick start

```typ
#import "@preview/starling:0.1.0": BST

#let t = (BST.new)(value: 4, left: none, right: none)
#let t = (t.insert)(1)
#let t = (t.insert)(7)
#let t = (t.insert)(3)
#let t = (t.insert)(6)

#(t.display)()              // static render
#(t.search-display)(6)      // animated search
#(t.insert-display)(5)      // animated insertion
#(t.delete-display)(3)      // animated deletion
#(t.rotate-display)(1)      // animated rotation
```

By default, the `*-display` methods collapse the animation to its final
frame -- a static image that's appropriate for handouts or printed notes.

## Usage with touying

In a touying slide deck, configure Starling with touying's `alternatives`
so each animation frame becomes its own subslide:

```typ
#import "@preview/touying:0.7.3": *
#import "@preview/starling:0.1.0" as starling

#let (BST,) = (starling.configure)(wrap: alternatives)

#show: solaris-theme.with(aspect-ratio: "16-9")

== A Binary Search Tree

#let t = (BST.new)(value: 4, left: none, right: none)
#let t = (t.insert)(1)
// ...

== Searching

#(t.search-display)(6)      // each step is a subslide
```

`configure(wrap: ...)` returns a dictionary of data-structure factories
with the wrapper baked in. Destructure the ones you need (currently just
`BST`).

### Why closure capture, not state?

If you're tempted to thread the wrapper through `std.state` (or typsy's
`safe-state`) so it can be "set once and forgotten": don't. It doesn't
work with touying.

Touying's `alternatives` is a layout-time mark that touying scans for
during page layout. Reading state requires a surrounding
`#context { ... }` block, and touying explicitly rejects its marks
inside `context`:

> ``Unsupported mark `touying-fn-wrapper` ... You can't use it inside
> some functions like `context`.``

Closure capture at the `configure` call site sidesteps the issue: the
wrapper is captured by value into each method, no contextual read
required. The single-line cost at the top of a touying document is
intentional.

## What `wrap` receives

The `*-display` methods build a sequence of `figure`s, one per animation
frame, and call `wrap(..figs)`. Built-in wrappers worth knowing:

| Wrapper                                | Result                              |
|----------------------------------------|-------------------------------------|
| (default, non-touying)                 | `figs.pos().last()` -- final frame  |
| `alternatives` (from touying)          | one subslide per frame              |
| `(..figs) => stack(dir: ttb, ..figs.pos())` | all frames vertically stacked  |

You can pass anything that accepts variadic content. Roll your own if
you want side-by-side layouts, interactive HTML output, etc.

## Lower-level: building your own animations

The animation kernel lives in `src/tree-anim.typ` and is exposed for
custom uses:

- `make-renderer(tree, ...)` -- start with one blank frame.
- `r.push-with-node(path, ..style)`, `r.push-with-edge(path, ..style)`
  -- append a frame that styles a node/edge.
- `r.patch(f => f.style-node(...))` -- modify the topmost frame in place.
- `r.render()` -- produce an array of cetz canvases.
- `concat-frames(r1, r2, ...)` -- stitch across renderers (needed when
  the tree shape changes mid-animation).

Paths are `"L"`/`"R"` strings rooted at `""`. The header of
`src/tree-anim.typ` documents the data model and sketches a path to
n-ary trees.

## Installation

While Starling is unpublished, install locally:

```sh
just install        # installs to @local/starling/0.1.0
just uninstall      # removes it
```

Or use the underlying script directly:

```sh
./scripts/package @local
```

## Development

```sh
just doc            # build docs/manual.pdf and thumbnails
just test           # run tytanic test suite
just update         # update visual regression refs
just ci             # test + doc
```

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
