# Starling

<div align="center">Version 0.2.0</div>

Animated renderings of data structures for teaching, built on
[cetz](https://typst.app/universe/package/cetz),
[typsy](https://typst.app/universe/package/typsy),
and (optionally) [touying](https://typst.app/universe/package/touying).

Starling is the animation toolkit for a programming course; it
currently ships a `BST` (binary search tree) and will grow to cover more
structures over time (heaps, hash tables, graphs, etc.).

## Quick start

```typ
#import "@preview/starling:0.2.0" as starling
#import starling: BST

#let t = (BST.new)(value: 4, left: none, right: none)
#let t = (t.insert)(1)
#let t = (t.insert)(7)
#let t = (t.insert)(3)
#let t = (t.insert)(6)

#starling.last((t.display)())              // static tree
#starling.last((t.search-display)(6))      // search, final frame
#starling.stacked((t.insert-display)(5))   // insert, all frames vertically
#starling.stacked((t.delete-display)(3))   // delete, all frames vertically
#starling.stacked((t.rotate-display)(1))   // rotation, all frames vertically
```

## Frames and helpers

Every `*-display` method returns `Array(Frame)`. A `Frame` is a record:

```
(canvas: Content, caption: Union(None, Content), step: Union(None, Dictionary))
```

`canvas` is a cetz canvas, `caption` is an optional textual track for the
step, and `step` is per-method metadata (e.g. `(kind: "compare", path,
cmp, found)` for search frames). The package ships these helpers:

| Helper                                  | Result                                  |
|-----------------------------------------|-----------------------------------------|
| `last(frames, caption: false)`          | final frame's canvas (+ caption opt-in) |
| `stacked(frames, caption: true)`        | all frames stacked vertically           |
| `figures(frames, caption: true)`        | `Array(figure)` for touying             |
| `canvases-only(frames)`                 | strip captions, return canvas array     |

If those don't fit your layout, pull the records apart yourself:
`frames.last().canvas`, `frames.map(f => f.caption)`, etc.

## Usage with touying

Starling does not depend on touying. Splat `figures` into `alternatives`
so each frame becomes its own subslide:

```typ
#import "@preview/touying:0.7.3": *
#import "@preview/starling:0.2.0" as starling
#import starling: BST

#show: solaris-theme.with(aspect-ratio: "16-9")

== A Binary Search Tree

#let t = (BST.new)(value: 4, left: none, right: none)
#let t = (t.insert)(1)
// ...

== Searching

#alternatives(..starling.figures((t.search-display)(6)))
```

Because Starling returns plain data, you can also weave frame fields
into custom slide layouts — for instance, side-by-side animation and
prose that step together:

```typ
== Searching for 6
#let frames = (t.search-display)(6)
#grid(columns: 2,
  alternatives(..starling.figures(frames, caption: false)),
  alternatives(..frames.map(f => f.caption)),
)
```

## Adding cetz annotations alongside a tree

For callouts or overlays that need to track specific nodes, drop down
to the cetz layer. `draw-tree` emits the tree's draw commands *without*
wrapping them in `cetz.canvas`, so you can compose them with your own
annotations in a shared canvas. `path-anchor("LR")` translates a starling
L/R path to the cetz anchor name of the corresponding node circle:

```typ
#import "@preview/cetz:0.5.2"
#import "@preview/starling:0.2.0" as starling

#cetz.canvas({
  starling.draw-tree(t, starling.blank-snapshot())
  import cetz.draw: *
  // Ring around the node at path "LR" (root → L → R).
  circle(starling.path-anchor("LR"), radius: 0.85, stroke: red + 2pt)
})
```

`draw-tree` accepts a `name:` (default `"tree"`) and `node-prefix:`
(default `"node-"`); `path-anchor` takes matching `tree-name:` and
`prefix:` if you've customised those.

## Lower-level: building your own animations

The animation kernel lives in `src/tree-anim.typ` and is exposed for
custom uses:

- `make-renderer(tree, sticky: true)` — start with one blank frame.
- `r.push-with-node(path, ..style)`, `r.push-with-edge(path, ..style)`
  — append a frame that styles a node/edge.
- `r.patch(f => f.style-node(...))` — modify the topmost frame's
  style snapshot in place.
- `r.with-caption(c)`, `r.with-step(s)` — set the current frame's
  caption / metadata.
- `r.render()` — produce `Array(Frame)`.
- `concat-frames(r1, r2, ...)` — stitch frames across renderers
  (needed when the tree shape changes mid-animation).

Paths are `"L"`/`"R"` strings rooted at `""`. The header of
`src/tree-anim.typ` documents the data model and sketches a path to
n-ary trees.

## Installation

While Starling is unpublished, install locally:

```sh
just install        # installs to @local/starling/0.2.0
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
