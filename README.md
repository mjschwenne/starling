# Starling

<div align="center">Version 1.0.0</div>

Animated renderings of data structures for teaching, built on
[cetz](https://typst.app/universe/package/cetz). It composes with
[touying](https://typst.app/universe/package/touying) without depending
on it, and reaches for
[diagraph-layout](https://typst.app/universe/package/diagraph-layout)
only if you ask for graphviz layout.

Starling is the animation toolkit for a programming course. It ships
binary search trees, red-black trees, AVL trees, 2-3-4 trees, tries,
weighted graphs (Prim, Kruskal, Dijkstra, BFS/DFS), hash maps, the
linear sorts, skip lists, and a DSL for git commit graphs.

## Quick start

```typ
#import "@preview/starling:1.0.0" as starling
#import starling: bst, last, stacked, result

#let t = bst.new(4, 1, 7, 3, 6)

#last(bst.display(t))                     // the tree, statically
#last(bst.search-display(t, 6))           // a search, final frame only
#stacked(bst.insert-display(t, 5))        // an insert, every frame down the page
#stacked(bst.in-order-display(t))         // a traversal (also pre-/post-/level-order)
```

Every data structure is a namespace of plain functions, and the
structure is always the first argument — `bst.insert(t, 5)`,
`hashmap.search-display(h, 21)`, `graph.prim-display(g, "A")`. Nothing
mutates: an operation returns a new structure.

## Frames

Every `*-display` returns an array of *frames*. A frame is a plain
dictionary carrying a builder (`theme => content`), a caption, step
metadata, and alt text — data until you render it.

| Helper                          | Result                                                  |
|---------------------------------|---------------------------------------------------------|
| `last(frames)`                  | the final frame, for print                              |
| `stacked(frames)`               | every frame down the page, captioned — the handout form |
| `figures(frames)`               | one figure per frame, to splat into `alternatives(..)`  |
| `subslides(frames, aux: "right")` | canvas + auxiliary strip + caption, composed per step |
| `canvas(frame)`                 | one bare canvas, for hand-built layouts                 |

The final frame carries `step.result`, so an animation and the state it
leaves behind stay in sync without writing the operation twice:

```typ
#let frames = bst.insert-display(t, 5)
#stacked(frames)
#let t = result(frames)
```

## Usage with touying

Starling has no touying dependency — it returns plain arrays.

```typ
#import "@preview/touying:0.7.3": *
#import "@preview/starling:1.0.0" as starling
#import starling: bst, graph, subslides

== Searching
#alternatives(..subslides(bst.search-display(t, 6)))

== Breadth-first search
#alternatives(..subslides(graph.bfs-display(g, "A"), aux: "right"))
```

`subslides` composes each step's canvas with the algorithm's auxiliary
state (a BFS queue, Dijkstra's priority queue, Kruskal's disjoint sets)
and the step's caption, keeping the whole thing one alt-tagged figure.

## Annotating with cetz

Each backend emits cetz drawables *without* a surrounding canvas, and
`anchor(<element key>)` names any element it drew:

```typ
#import "@preview/cetz:0.5.2"
#import starling: anchor, blank-snapshot, draw-tree

#cetz.canvas({
  draw-tree(t, blank-snapshot())
  import cetz.draw: circle       // selectively: cetz has an `anchor` of its own
  circle(anchor("LR"), radius: 0.85, stroke: red + 2pt)
})
```

To annotate a step of an existing animation instead, `overlay(frames,
at: -1, draw: ..)` appends commands inside that frame's own canvas.

## Building your own animations

Drive a renderer with the op stream when no built-in animation fits:

```typ
#import starling: apply-ops, commit, render, set-alt, style-node, styles

#let r = bst.renderer(t, sticky: true)
#stacked(render(apply-ops(r,
  styles.search("") + commit(caption: [start at the root], alt: "At the root.")
    + styles.search("R") + commit(caption: [go right], alt: "Descending right.")
    + styles.success("RL") + set-alt("Found it."),
)))
```

`make-renderer(structure, draw, ..)` takes a draw backend of your own —
a plain function of a structure and a snapshot — so the frame,
snapshot, theme, and presentation machinery works for structures
starling doesn't ship.

## Theming

One nested dictionary, one setter. Sections: `render` (structural
defaults), `op` (operation-semantic roles shared by every structure),
and a palette per structure that needs one.

```typ
#starling.set-theme((op: (search-stroke: (paint: teal, thickness: 2.5pt))))
#bst.search-display(t, 6, theme: (render: (node-fill: yellow.lighten(85%))))
```

A per-call `theme:` layers over the document's rather than replacing
it. Calling `set-theme` at all costs an extra layout pass (Typst state
convergence), so a document where compile speed matters can skip it and
pass a palette per call instead.

## Documentation

[`docs/manual.pdf`](docs/manual.pdf) has a tour of every structure, the
theme and style vocabularies, the extension story, an API reference for
every module, and a chapter on migrating from 0.3.x.

## Installation

While Starling is unpublished, install locally:

```sh
just install        # installs to @local/starling/1.0.0
just uninstall      # removes it
```

Or use the underlying script directly:

```sh
./scripts/package @local
```

## Development

```sh
just test           # run the tytanic visual-regression suite
just check          # the assertion tests only
just update         # update visual regression refs
just doc            # build docs/manual.pdf and the thumbnails
just ci             # test + doc
```

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
