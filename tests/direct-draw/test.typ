// The public direct-call path: a `draw-*` backend invoked inside the caller's
// own `cetz.canvas`, fed a snapshot that carries *theme references*.
//
// This is the documented extension point ("call these inside your own
// cetz.canvas"), and it is the one path that does not go through
// `frame.make-canvas`, which is what made it the one path where theme
// references were never resolved: every DS `renderer()` paints with refs (the
// rbt/trie palettes, avl's balance colours) and every `styles.*` helper builds
// them, so the backend received a raw `(starling-theme-ref: ..)` dict where it
// wanted a colour and panicked deep inside cetz.
//
// Each canvas below pairs a ref-bearing snapshot with its backend. The
// reference render is the proof the refs resolved to real palette colours
// rather than merely failing to crash.

#import "@preview/cetz:0.5.2"
#import "/src/lib.typ" as starling
#import starling: (
  apply-ops, avl, blank-snapshot, bst, draw-array, draw-graph, draw-hashmap,
  draw-skiplist, draw-tree, graph, hashmap, rbt, skiplist, sort, styles, trie,
  with-edge, with-node,
)

#set page(width: auto, height: auto, margin: 6pt)

#let row(..bodies) = stack(dir: ltr, spacing: 10pt, ..bodies.pos())

// --- Tree backend: the three tree DSs that paint with refs ---------
#let t-trie = trie.new("car", "cat")
#let t-rbt = rbt.new(5, 3, 8, 1)
#let t-avl = avl.new(5, 3, 8, 1, 2)

#row(
  cetz.canvas(draw-tree(t-trie, trie.renderer(t-trie).snapshots.last())),
  cetz.canvas(draw-tree(t-rbt, rbt.renderer(t-rbt, bits: true).snapshots.last())),
  cetz.canvas(draw-tree(t-avl, avl.renderer(t-avl).snapshots.last())),
)

// --- styles.* helpers produce refs too ----------------------------
#let t-bst = bst.new(5, 3, 8)
#let r-bst = apply-ops(
  bst.renderer(t-bst),
  styles.attention("L") + styles.search("") + styles.danger("R"),
)

// --- Graph / hashmap / skiplist / array backends -------------------
#let g = graph.new(
  (("A", 0, 0), ("B", 2, 0), ("C", 1, -1.5)),
  edges: (("A", "B", 3), ("B", "C", 1)),
)
// No `styles.*` helper builds an *edge* ref, so the edge half of
// `resolve-inputs` gets an explicit one — the pattern a user reaches for when
// an edge style should follow the theme.
#let r-g = apply-ops(
  graph.renderer(g),
  styles.attention("A")
    + starling.style-edge(
      graph.ek(g, "A", "B"),
      stroke: starling.role("success-fill"),
    ),
)

#let hm = hashmap.insert(hashmap.insert(hashmap.new(5), 3), 8)
#let r-hm = apply-ops(
  hashmap.renderer(hm),
  styles.search(hashmap.cell-key(3)) + styles.attention(hashmap.entry-key(3, 0)),
)

#let sl = skiplist.new(1, 4, 7)
#let r-sl = apply-ops(
  skiplist.renderer(sl),
  styles.attention(skiplist.box-key(1, 0)),
)

#row(
  cetz.canvas(draw-tree(t-bst, r-bst.snapshots.last())),
  cetz.canvas(draw-graph(graph.positioned(g), r-g.snapshots.last())),
)

#row(
  cetz.canvas(draw-hashmap(hashmap.positioned(hm), r-hm.snapshots.last())),
  cetz.canvas(draw-skiplist(skiplist.positioned(sl), r-sl.snapshots.last())),
)

// The array backend, driven straight off a sort table.
#let s = sort.new(3, 1, 2)
#let r-s = apply-ops(
  sort.renderer(s),
  styles.attention(sort.cell-key("a", 0)),
)
#cetz.canvas(draw-array(sort.positioned(s), r-s.snapshots.last()))

// --- A partial theme layers over the default on a direct call ------
// Every DS entry point takes a partial `theme:`; the backends do too, so the
// migration table's `render-theme: (..)` -> `theme: (render: (..))` row holds
// on this path as well. Naming one key must not require spelling the rest.
#row(
  cetz.canvas(draw-tree(
    t-bst,
    blank-snapshot(),
    theme: (render: (node-stroke: blue + 1.5pt)),
  )),
  cetz.canvas(draw-skiplist(
    skiplist.positioned(sl),
    blank-snapshot(),
    theme: (skiplist: (header-fill: yellow)),
  )),
)

// --- Hand-built snapshots, without going through the op stream -----
#let by-hand = with-edge(
  with-node(blank-snapshot(), "L", (fill: blue.lighten(60%))),
  "R",
  (stroke: green + 1.5pt),
)
#cetz.canvas(draw-tree(t-bst, by-hand))

// --- The anchor conveniences name the same elements as the keys ----
#assert.eq(skiplist.box-anchor(2, 1), starling.anchor(skiplist.box-key(2, 1)))
#assert.eq(
  skiplist.forward-anchor(2, 1),
  starling.anchor(skiplist.forward-key(2, 1)),
)
#assert.eq(skiplist.data-anchor(2), starling.anchor(skiplist.data-key(2)))
#assert.eq(hashmap.cell-anchor(3), starling.anchor(hashmap.cell-key(3)))
#assert.eq(hashmap.entry-anchor(3, 1), starling.anchor(hashmap.entry-key(3, 1)))
#assert.eq(sort.cell-anchor("count", 2), starling.anchor(sort.cell-key("count", 2)))
#assert.eq(
  sort.entry-anchor("count", 2, 0),
  starling.anchor(sort.entry-key("count", 2, 0)),
)
#assert.eq(graph.edge-anchor(g, "A", "B"), starling.anchor(graph.ek(g, "A", "B")))

// `canvas:` qualifies the name with the enclosing canvas, exactly as
// `anchor(.., canvas:)` does.
#assert.eq(skiplist.box-anchor(0, 0, canvas: "sl"), "sl.el-b0-0")
#assert.eq(hashmap.cell-anchor(1, canvas: "hm"), "hm.el-c1")

// --- resolve-refs is reachable from the public surface -------------
// A backend of your own needs it, and its absence from the public surface is
// what left the direct path with no user-side workaround.
#assert.eq(
  starling.resolve-refs(
    (stroke: starling.role("attention-stroke")),
    starling.default-theme,
  ),
  (stroke: starling.default-theme.op.attention-stroke),
)
