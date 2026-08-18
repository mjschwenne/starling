// Tree drawing backend.
//
// Turns a tree structure plus one snapshot into cetz commands. It knows
// nothing about tree *algorithms* — those live in `ds/`; this module only
// draws what it is handed, which is why BST, RBT, AVL, B24, and the trie
// all share it.
//
// Element identity
// ----------------
// A node is identified by its position in the tree, encoded as a string
// path. Binary trees (BST / RBT / AVL) use the alphabet "L"/"R": the root
// is "", "R" is the right child, "RL" the left child of the right child.
// N-ary trees (B24) use digit characters "0".."9", each indexing into the
// parent's `children` array: "" is the root, "0" the leftmost child, "012"
// leftmost -> middle -> right-of-middle. A trie's path is simply the prefix
// it spells ("", "c", "ca", "cat"). An edge is keyed by the path of its
// CHILD node.
//
// A path may carry a "#<int>" suffix addressing one compartment of a
// multi-key node — "01#1" is the middle key of the leftmost grandchild.
// The suffix is meaningful only to `anchor` (which turns it into a cetz
// sub-anchor); edge keys must not carry one.
//
// FUTURE — generalizing to arities > 10: replace the single digit
// characters with slash-separated indices ("0/1/2"). Paths are opaque
// everywhere else; the places that interpret their segments are the two
// builders below and the `path-to` / `by-value` walks in `ds/`.

#import "@preview/cetz:0.5.2"
#import "../core/draw-util.typ": anchor
#import "../core/style.typ": merge-into
#import "../core/theme.typ": default-theme

// ===================================================================
// Anchor aliasing
// ===================================================================
//
// cetz-tree names each node's group positionally — "0" for the root,
// "0-1" for its second child — because it lays the tree out before it
// knows anything about our paths. We want the shared `el-<key>` names
// instead, so after the tree is drawn we republish each node group's
// anchors under its path-derived name.
//
// This is the same manoeuvre cetz's own `draw.copy-anchors` performs
// (insert into `ctx.nodes` an entry whose `anchors` closure delegates to
// the source element's), with a rename and with the new name also pushed
// onto the enclosing group so it survives one level of nesting. It is the
// one place in starling that reaches into a cetz context; it is pinned to
// cetz 0.5.2 along with the rest of the drawing code.

// Republish anchors of `element`'s children under new names. `mapping` is
// an array of `(from, to)` pairs, `from` naming a child of `element`.
#let _alias-anchors(element, mapping) = {
  let el = (
  ctx => {
    let calc = ctx.nodes.at(element).anchors
    for (from, to) in mapping {
      ctx.nodes.insert(
        to,
        (
          anchors: name => {
            if name == "default" {
              calc(from)
            } else if name == () {
              ("default",)
            } else {
              calc((from,) + name)
            }
          },
        ),
      )
      if ctx.groups.len() > 0 { ctx.groups.last().push(to) }
    }
    (ctx: ctx, drawables: ())
  })
  (el,)
}

// The internal name of the cetz-tree group. Never public: every anchor a
// caller sees is aliased out of it by `_alias-anchors`.
#let _TREE = "starling-tree"
#let _NODE = "node-"

// Walk a built cetz-tree, pairing each node's positional cetz name with
// its starling path. Phantoms are included — a materialized phantom is a
// real, addressable node.
#let _anchor-map(node, name) = {
  let out = ((name, node.first().path),)
  for (i, child) in node.slice(1).enumerate() {
    out += _anchor-map(child, name + "-" + str(i))
  }
  out
}

// ===================================================================
// cetz-tree builders
// ===================================================================

#let _phantom(path) = (((value: none, label: auto, path: path, phantom: true),),)

// Binary shape: a node with `left` / `right`.
//
// When a node has exactly one child, a phantom sibling is injected on the
// opposite side so cetz's tree layout doesn't put the lone child directly
// under its parent — a single child should visibly hang off to one side.
// Phantoms are detected in draw-{node,edge} via `content.phantom` and
// skipped at draw time, but they still occupy layout space.
//
// `forced-phantoms` lists paths that must materialize as phantoms even
// where the single-child rule wouldn't add them — the RBT double-black
// dot needs one so its stub edge has a node to land on when both children
// are nil.
#let _build-cetz-tree(node, path, forced-phantoms: ()) = {
  let has-left = node.left != none
  let has-right = node.right != none
  let force-left = forced-phantoms.contains(path + "L")
  let force-right = forced-phantoms.contains(path + "R")
  // Pair-up rule: at a leaf, a single forced phantom would be laid out
  // directly below the parent. Inject the opposite-side phantom too so
  // the forced one hangs off to its side, matching how a single real
  // child gets a phantom sibling.
  let leaf-force = (
    not has-left and not has-right and (force-left or force-right)
  )
  let children = ()
  if has-left {
    children.push(_build-cetz-tree(
      node.left,
      path + "L",
      forced-phantoms: forced-phantoms,
    ))
  } else if has-right or force-left or leaf-force {
    children.push(.._phantom(path + "L"))
  }
  if has-right {
    children.push(_build-cetz-tree(
      node.right,
      path + "R",
      forced-phantoms: forced-phantoms,
    ))
  } else if has-left or force-right or leaf-force {
    children.push(.._phantom(path + "R"))
  }
  ((value: node.value, label: node.label, path: path), ..children)
}

// N-ary shape: a node with a `children` array (B24, and anything else
// exposing the same shape). Phantom logic doesn't apply — 2-3-4
// invariants require internal nodes to have a full child complement. Each
// child's path extends the parent's by one digit character.
#let _build-cetz-tree-nary(node, path) = {
  let children-rendered = ()
  let cs = node.at("children", default: ())
  for (i, c) in cs.enumerate() {
    children-rendered.push(_build-cetz-tree-nary(c, path + str(i)))
  }
  (
    (
      keys: node.keys,
      labels: node.at("labels", default: ()),
      path: path,
    ),
    ..children-rendered,
  )
}

// Trie shape: a node with `char` (the letter on its incoming edge, `none`
// at the root), `terminal` (a stored word ends here), and `children`
// (kept sorted by `char`). Each child's path extends the parent's by the
// child's `char`, so a node's path is exactly the prefix it spells. The
// drawn label is the terminal bit — "1" for a word end, "0" otherwise —
// and the letters live on the edges (set as edge `tag`s by the trie's
// painter). `child-index` / `n-siblings` record the node's position among
// its siblings so `draw-edge` can place each letter tag on the correct
// side of a fork (see `want-x-sign`). No phantom siblings: a lone child
// hanging straight down is the desired trie look (a prefix chain), unlike
// the binary builder.
#let _build-cetz-tree-trie(node, path, child-index: 0, n-siblings: 1) = {
  let children-rendered = ()
  let cs = node.at("children", default: ())
  for (i, c) in cs.enumerate() {
    children-rendered.push(_build-cetz-tree-trie(
      c,
      path + c.char,
      child-index: i,
      n-siblings: cs.len(),
    ))
  }
  (
    (
      value: none,
      label: if node.terminal { "1" } else { "0" },
      path: path,
      child-index: child-index,
      n-siblings: n-siblings,
    ),
    ..children-rendered,
  )
}

// ===================================================================
// draw-tree
// ===================================================================

/// Emit the cetz draw commands for one styled snapshot of `tree`,
/// _without_ wrapping them in a `cetz.canvas` — the caller owns the
/// canvas, which is what lets you add your own annotations alongside the
/// tree and anchor them with `anchor(<path>)`.
///
/// Shape dispatch is on the node: a `terminal` field means a trie, a
/// `children` field means an n-ary tree, otherwise `left` / `right` means
/// a binary tree.
///
/// -> content
#let draw-tree(
  /// The tree to render. Three accepted shapes:
  ///
  /// - Binary: `value`, `label`, `left`, `right`. A `label` of `auto`
  ///   falls back to `str(value)`; any other value (string, image,
  ///   content) is drawn as the node's label.
  /// - N-ary: `keys` (array of key values), optional `labels` (parallel
  ///   array of overrides), and `children` (empty for leaves). Pair it
  ///   with `shape: "btree-node"` in `node-style` for the canonical
  ///   subdivided rectangle.
  /// - Trie: `char`, `terminal`, `children`.
  /// -> dictionary
  tree,
  /// Style overlay for this snapshot; `blank-snapshot()` draws it
  /// unstyled.
  /// -> dictionary
  snapshot,
  /// Base node styling, applied beneath the snapshot's per-node styles.
  /// -> dictionary
  node-style: (:),
  /// Base edge styling, applied beneath the snapshot's per-edge styles.
  /// -> dictionary
  edge-style: (:),
  /// The full resolved theme. The backend reads `theme.render`.
  /// -> dictionary
  theme: default-theme,
  /// Wrap the whole tree in a cetz group of this name, qualifying every
  /// element anchor under it — `anchor(path, canvas: name)`. `none`
  /// draws into the enclosing canvas directly.
  /// -> none | str
  name: none,
  /// Depth-direction layout factor passed to cetz-tree. Below `1`
  /// shortens the edges between levels, above `1` stretches them. Node
  /// sizes are unaffected.
  /// -> float
  grow: 1,
  /// Sibling-direction layout factor passed to cetz-tree. Below `1`
  /// pulls siblings together, above `1` pushes them apart. Node sizes
  /// are unaffected.
  /// -> float
  spread: 1,
) = {
  import cetz.draw
  import cetz.tree as cetz-tree
  let rt = theme.render

  // Shape dispatch. A trie carries `terminal` (and `children`); an n-ary
  // node carries `keys` (and `children`); a binary node carries `left` /
  // `right`. Check `terminal` first so a trie doesn't fall into the
  // generic n-ary path.
  let is-trie = "terminal" in tree
  let is-nary = (not is-trie) and "children" in tree
  // An edge styled `force-show: true` for a path that wouldn't naturally
  // exist (both children nil) needs a phantom to land on — the
  // double-black dot. N-ary trees never use this; their invariants forbid
  // missing children at internal nodes.
  let forced-phantoms = snapshot
    .edges
    .pairs()
    .filter(p => p.at(1).at("force-show", default: false))
    .map(p => p.at(0))
  let root = if is-trie {
    _build-cetz-tree-trie(tree, "")
  } else if is-nary {
    _build-cetz-tree-nary(tree, "")
  } else {
    _build-cetz-tree(tree, "", forced-phantoms: forced-phantoms)
  }

  let body = {
    cetz-tree.tree(
      root,
      name: _TREE,
      group-name-prefix: _NODE,
      grow: grow,
      spread: spread,
      draw-node: (node, ..) => {
        let path = node.content.path
        let s = merge-into(node-style, snapshot.nodes.at(path, default: (:)))
        let is-phantom = node.content.at("phantom", default: false)
        if is-phantom and not s.at("materialize", default: false) {
          // Reserve a slightly-wider-than-a-node layout footprint and
          // render nothing. `bounds: true` keeps the box for cetz's tree
          // layout while hiding the drawable. Width > node diameter so
          // the lone real sibling visibly hangs off-center rather than
          // sitting almost under its parent.
          draw.hide(draw.rect((-0.9, -0.6), (0.9, 0.6)), bounds: true)
        } else if s.at("hide", default: false) {
          ()
        } else {
          let shape = s.at("shape", default: "circle")
          let fill-c = s.at("fill", default: rt.node-fill)
          let stroke-c = s.at("stroke", default: rt.node-stroke)
          let body = if shape == "btree-node" {
            // N-ary node — a subdivided rectangle whose width scales with
            // the number of keys. Per-compartment styling comes from
            // `s.key-styles`; key labels from the node content's `labels`
            // array (an `auto` entry falls back to `str(key)`).
            let keys = node.content.keys
            let labels = node.content.at("labels", default: ())
            let n = keys.len()
            let half-w = 0.6 * n
            let key-styles = s.at("key-styles", default: ())
            let ks-at = i => if i < key-styles.len() { key-styles.at(i) } else {
              (:)
            }
            // Outer rect first — default fill + stroke over the whole node.
            draw.rect(
              (-half-w, -0.6),
              (half-w, 0.6),
              fill: fill-c,
              stroke: stroke-c,
            )
            // Per-compartment fills, over the outer rect but before the
            // dividers so the dividers stay visible on top.
            for i in range(n) {
              let ks = ks-at(i)
              if "fill" in ks {
                let cx = -half-w + 0.6 + 1.2 * i
                draw.rect(
                  (cx - 0.6, -0.6),
                  (cx + 0.6, 0.6),
                  fill: ks.fill,
                  stroke: none,
                )
              }
            }
            // Internal dividers between compartments.
            for i in range(1, n) {
              let x = -half-w + 1.2 * i
              draw.line((x, -0.6), (x, 0.6), stroke: stroke-c)
            }
            // Per-compartment strokes last, so a highlighted
            // compartment's border overlays the dividers and the outer
            // stroke cleanly.
            for i in range(n) {
              let ks = ks-at(i)
              if "stroke" in ks {
                let cx = -half-w + 0.6 + 1.2 * i
                draw.rect(
                  (cx - 0.6, -0.6),
                  (cx + 0.6, 0.6),
                  fill: none,
                  stroke: ks.stroke,
                )
              }
            }
            // Compartment labels and per-compartment anchors.
            let default-text = s.at("text-fill", default: rt.node-text-fill)
            for (i, key) in keys.enumerate() {
              let ks = ks-at(i)
              let kt = ks.at("text-fill", default: default-text)
              let raw-label = if i < labels.len() { labels.at(i) } else { auto }
              let label-content = if raw-label == auto { str(key) } else {
                raw-label
              }
              let cx = -half-w + 0.6 + 1.2 * i
              draw.content(
                (cx, 0),
                text(weight: "bold", fill: kt, label-content),
              )
              draw.anchor("key-" + str(i), (cx, 0))
            }
            // Gap anchors — child-edge attachment points on the south
            // face, one per child position. `gap-0` is leftmost,
            // `gap-<n>` rightmost.
            for i in range(n + 1) {
              let x = -half-w + 1.2 * i
              draw.anchor("gap-" + str(i), (x, -0.6))
            }
            // Top-center anchor — where the incoming parent edge lands.
            // Explicit rather than the group's computed `north` so the
            // note drawn east of the node can't drag the bounding-box
            // center (and hence the edge endpoint) off the box. Most
            // visible on a 1-key node, where the note is wide relative to
            // the box's 1.2 width; the south-side `gap-<i>` anchors give
            // the outgoing child edges the same note-independence.
            draw.anchor("top", (0, 0.6))
            // Note slot — east of the entire node.
            let n-note = s.at("note", default: none)
            if n-note != none {
              let nf = s.at("note-fill", default: rt.note-fill)
              draw.content(
                (half-w + 0.15, 0),
                anchor: "west",
                text(fill: nf, size: 0.8em, n-note),
              )
            }
            // Tag slot — west of the entire node.
            let tag = s.at("tag", default: none)
            if tag != none {
              draw.content(
                (-half-w - 0.05, 0),
                anchor: "east",
                text(fill: rt.edge-stroke, size: 0.7em, tag),
              )
            }
          } else {
            // Binary shapes — `value` / `label` are required.
            let value = node.content.at("value", default: none)
            let raw-label = node.content.at("label", default: auto)
            let default-label = if raw-label == auto {
              if value == none { "" } else { str(value) }
            } else { raw-label }
            let label = s.at("label", default: default-label)
            // Shape dispatch. New shapes go here; keep the bounding boxes
            // sensible so the named cetz anchors (north/south/east/west on
            // the node group) land where users expect, since the edge
            // anchor overrides reference them. `label-pos` shifts the
            // label off the geometric origin for shapes that taper — a
            // triangle's apex narrows to nothing at the top, so its label
            // sits at the centroid (y = -0.2) where the shape is wide
            // enough to host larger fonts without clipping the sloped
            // sides.
            let label-pos = (0, 0)
            if shape == "circle" {
              draw.circle((), radius: 0.6, fill: fill-c, stroke: stroke-c)
            } else if shape == "triangle" {
              draw.line(
                (0, 0.6),
                (-0.7, -0.6),
                (0.7, -0.6),
                close: true,
                fill: fill-c,
                stroke: stroke-c,
              )
              label-pos = (0, -0.2)
            } else if shape == "rectangle" {
              draw.rect(
                (-0.7, -0.6),
                (0.7, 0.6),
                fill: fill-c,
                stroke: stroke-c,
              )
            } else {
              panic(
                "draw-tree: unknown node shape "
                  + repr(shape)
                  + "; supported: \"circle\", \"triangle\", \"rectangle\", \"btree-node\".",
              )
            }
            let tf = s.at("text-fill", default: rt.node-text-fill)
            // Bold the label via `weight:` rather than `*..*` markup so a
            // user `show strong: set text(fill: ..)` rule can't override
            // the computed `tf` — the contrast-aware fill exists precisely
            // so labels stay readable against gradient-filled traversal
            // nodes, and we don't want it silently undone by ambient
            // styling.
            //
            // Anchor explicitly at `label-pos` (set by the shape branch
            // above) rather than `()` (the previous cetz coordinate):
            // after `draw.line(..)` or `draw.rect(..)` the previous
            // coordinate is the last vertex/corner, not the centre.
            draw.content(label-pos, text(weight: "bold", fill: tf, label))
            let n = s.at("note", default: none)
            if n != none {
              let nf = s.at("note-fill", default: rt.note-fill)
              draw.content(
                (0.75, 0),
                anchor: "west",
                text(fill: nf, size: 0.8em, n),
              )
            }
            // Tag — a small annotation pinned just outside the west of
            // the node. RBT `display(bits: true)` uses it for per-node
            // black-height bits. Drawn in the render theme's edge-stroke
            // colour so it reads as a marginal annotation rather than
            // node content. West of the equator avoids the incoming
            // parent edge (NE / NW) and the outgoing child edges
            // (SW / SE).
            let tag = s.at("tag", default: none)
            if tag != none {
              draw.content(
                (-0.65, 0),
                anchor: "east",
                text(fill: rt.edge-stroke, size: 0.7em, tag),
              )
            }
          }
          // `ghost` keeps the node's exact footprint and its anchors but
          // paints nothing — the progressive-reveal slot.
          if s.at("ghost", default: false) {
            draw.hide(body, bounds: true)
          } else { body }
        }
      },
      draw-edge: (from, to, ..) => {
        let child-path = to.content.path
        let s = merge-into(edge-style, snapshot.edges.at(child-path, default: (:)))
        // Phantom edges are skipped by default. `force-show: true` lets a
        // stub edge render to (or from) a phantom — used to visualise
        // double-black on a now-nil tree slot.
        let force = s.at("force-show", default: false)
        if not force and to.content.at("phantom", default: false) { return }
        if not force and from.content.at("phantom", default: false) { return }
        if s.at("hide", default: false) { return }
        let mark = s.at("mark", default: none)
        // Endpoint resolution. The default is the empirical 0.4
        // fractional trick (it lands cleanly in the gap between two
        // circle nodes); a `parent-anchor` / `child-anchor` override
        // swaps that side for a named cetz anchor on the node group,
        // which is how non-circular shapes (a triangle's apex, say) get
        // clean connections.
        //
        // For n-ary parents (detected by `keys` in `from.content`) the
        // default parent anchor is the `gap-<i>` anchor on the south
        // face, `i` being the child's index — the last digit of the child
        // path. N-ary children likewise default to their group's explicit
        // `top` anchor: the box's true top-center, unlike the computed
        // `north`, which the east-side note would drag off the box.
        // Explicit overrides still win.
        let parent-is-nary = "keys" in from.content
        let child-is-nary = "keys" in to.content
        let parent-coord = if "parent-anchor" in s {
          from.group-name + "." + s.at("parent-anchor")
        } else if parent-is-nary and child-path.len() > 0 {
          from.group-name + ".gap-" + child-path.at(child-path.len() - 1)
        } else {
          (from.group-name, 0.4, to.group-name)
        }
        let child-coord = if "child-anchor" in s {
          to.group-name + "." + s.at("child-anchor")
        } else if child-is-nary {
          // The `top` anchor is only drawn by the btree-node shape. If a
          // caller overrode this n-ary node's shape (a triangle standing
          // in for a subtree, say), fall back to the group's computed
          // `north`, which every shape provides and which lands on the
          // apex / top-center of the symmetric binary shapes.
          let child-shape = merge-into(
            node-style,
            snapshot.nodes.at(child-path, default: (:)),
          ).at("shape", default: "circle")
          if child-shape == "btree-node" {
            to.group-name + ".top"
          } else {
            to.group-name + ".north"
          }
        } else {
          (to.group-name, 0.4, from.group-name)
        }
        draw.line(
          parent-coord,
          child-coord,
          stroke: s.at("stroke", default: rt.edge-stroke),
          ..if mark != none { (mark: mark) },
        )
        // `note` sits on the edge line itself — the midpoint of the
        // parent's south anchor and the child's north anchor. Bare group
        // names happen to resolve near the parent's centroid rather than
        // midway between centroids, so name the anchors explicitly.
        let n = s.at("note", default: none)
        if n != none {
          let nf = s.at("note-fill", default: rt.note-fill)
          draw.content(
            (from.group-name + ".south", 0.5, to.group-name + ".north"),
            text(fill: nf, size: 0.8em, n),
          )
        }
        // `tag` sits *off* the edge line, at its midpoint offset
        // perpendicular to the edge direction. An earlier corner-anchor
        // interpolation broke down for wide subtrees: at shallow edge
        // slopes the parent's and child's outer corners lined up with the
        // edge line itself, putting the tag on top of the stroke. A
        // geometric perpendicular works at any slope.
        let tag = s.at("tag", default: none)
        if tag != none {
          // The sign of the perpendicular offset picks the "outside" of
          // the V (away from the sibling subtree):
          //   binary — L child -> negative-x, R child -> positive-x.
          //   n-ary  — child index left of center -> negative-x, else
          //            positive-x.
          let want-x-sign = if "keys" in from.content {
            let n-children = from.content.keys.len() + 1
            let idx = int(child-path.at(child-path.len() - 1))
            if idx * 2 < n-children - 1 { -1 } else { 1 }
          } else if "n-siblings" in to.content {
            // Trie edge — the child records its own index / sibling count.
            let idx = to.content.child-index
            let n = to.content.n-siblings
            if idx * 2 < n - 1 { -1 } else { 1 }
          } else if child-path.ends-with("L") { -1 } else { 1 }
          draw.get-ctx(ctx => {
            let (_, p, c) = cetz.coordinate.resolve(
              ctx,
              parent-coord,
              child-coord,
            )
            let dx = c.at(0) - p.at(0)
            let dy = c.at(1) - p.at(1)
            let len = calc.sqrt(dx * dx + dy * dy)
            // Rotate the edge vector 90 degrees for a perpendicular, then
            // flip it if its x-sign disagrees with the desired outside
            // direction. The degenerate case (len == 0) falls back to a
            // pure-x offset.
            let (px, py) = if len == 0 {
              (want-x-sign, 0)
            } else {
              let cx = -dy / len
              let cy = dx / len
              if (cx >= 0) == (want-x-sign > 0) { (cx, cy) } else { (-cx, -cy) }
            }
            let offset = 0.3
            draw.content(
              (
                (p.at(0) + c.at(0)) / 2 + px * offset,
                (p.at(1) + c.at(1)) / 2 + py * offset,
              ),
              text(fill: rt.edge-tag-fill, size: 0.7em, tag),
            )
          })
        }
      },
    )
    // Republish every node group under its path-derived `el-` name.
    _alias-anchors(
      _TREE,
      _anchor-map(root, "0").map(((n, p)) => (_NODE + n, anchor(p))),
    )
  }

  if name == none { body } else { draw.group(body, name: name) }
}
