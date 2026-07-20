// Tree animation backend — the tree-specific layer on top of the
// structure-agnostic kernel in `anim-core.typ`. Holds the cetz tree
// drawing (`draw-tree`), the cetz-tree builders, path identity
// (`PathId`, `path-anchor`), and tree-bound wrappers that inject
// `draw-tree` into the generic `Renderer` / canvas helpers.
//
// This module re-exports the core kernel (`#import "./anim-core.typ":
// *`), so existing consumers that read `tree-anim.Frame`,
// `tree-anim.blank-snapshot`, `tree-anim._merge-render-theme`, etc.
// keep working unchanged.
//
// Path identity
// -------------
// Nodes are identified by their position in the tree, encoded as a
// string. For binary trees (BST / RBT / AVL) the alphabet is "L"/"R":
// root is "", "R" is the right child, "RL" is the left of the right,
// and so on. For n-ary trees (B24) the alphabet is digit characters
// "0".."9" with each digit indexing into the parent's children array:
// root is "", "0" is the leftmost child, "012" is leftmost → middle →
// right-of-middle. Edges are identified by the path of their CHILD node.
//
// Optionally, a path may carry a "#<int>" suffix addressing one of a
// node's internal keys for per-compartment styling on n-ary nodes —
// e.g. "01#1" is the middle key of the leftmost grandchild. The suffix
// is only meaningful for `path-anchor` (which resolves it to a
// `key-<i>` sub-anchor) and the tree classes' own helpers; it is
// rejected on paths passed to edge styling.
//
// FUTURE — generalizing to arities > 10: replace single digit characters
// with slash-separated indices (e.g. "0/1/2"). Paths are otherwise
// treated as opaque keys downstream. The places that interpret path
// segments are:
//   * `PathId` (the pattern below)
//   * `_build-cetz-tree` / `_build-cetz-tree-nary` in this file
//   * `by-value` / `path-to` on the BST / B24 classes (walk the structure)

#import "@preview/typsy:0.2.2": *
#import "@preview/cetz:0.5.2"
#import "./anim-core.typ": *
#import "./anim-core.typ" as core

// ===================================================================
// Alt-text / caption node labels
// ===================================================================

// Human-readable reference to a node for captions and alt text. A node
// visually displays its `label` whenever that is set to a string (see
// `draw-tree.draw-node`, which falls back to `str(value)` only for
// `auto`), so text that refers to the node should read the same way.
// We use the label only when it is a plain string — `auto` or arbitrary
// content can't be spliced into an alt-text string — otherwise falling
// back to the ordering `value`. Binary trees (BST/AVL/RBT) carry the
// `value`/`label` pair.
#let _alt-label(node) = if type(node.label) == str {
  node.label
} else {
  str(node.value)
}

// N-ary (B24) analog: a node carries parallel `keys`/`labels` arrays, so
// a reference names one compartment `i`. Same string-only rule.
#let _alt-key-label(node, i) = {
  let l = node.labels.at(i, default: auto)
  if type(l) == str { l } else { str(node.keys.at(i)) }
}

// ===================================================================
// Path identity
// ===================================================================

/// Typsy refinement: a path-id string. Binary trees use #raw("\"L\"") /
/// #raw("\"R\"") characters (empty string = root, #raw("\"L\"") = the
/// root's left child, #raw("\"LR\"") = the root's left child's right
/// child, and so on). N-ary trees use digit characters #raw("\"0\"") to
/// #raw("\"9\"") with each digit indexing into the parent's children
/// array. An optional #raw("\"#<int>\"") suffix addresses an internal
/// key compartment of an n-ary node — used by @@path-anchor(), e.g.
/// #raw("\"01#1\"") is the middle-key compartment of the leftmost
/// grandchild. The binary and n-ary alphabets are not mixed within a
/// single path.
#let PathId = Refine(Str, p => {
  let parts = p.split("#")
  let valid = c => c == "L" or c == "R" or "0123456789".contains(c)
  let digit = c => "0123456789".contains(c)
  parts.len() <= 2 and (
    parts.at(0).codepoints().all(valid) and (
      parts.len() == 1 or parts.at(1).codepoints().all(digit)
    )
  )
})

// ===================================================================
// cetz-tree builders
// ===================================================================

#let _phantom(path) = (((value: none, label: auto, path: path, phantom: true),),)

#let _build-cetz-tree(node, path, forced-phantoms: ()) = {
  // BST-shaped accessor. Generalize here for n-ary trees.
  //
  // When a node has exactly one child, we inject a phantom sibling on the
  // opposite side so cetz's tree layout doesn't put the lone child directly
  // under its parent — single children should visibly hang off to one side.
  // Phantoms are detected in draw-{node,edge} via `content.phantom` and
  // skipped at draw time, but they still occupy layout space.
  //
  // `forced-phantoms` lists paths that must materialize as phantoms even
  // when the natural single-child rule wouldn't add them — used by the
  // double-black dot rendering, so the stub edge has a node to anchor to
  // when both children are nil.
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

// n-ary variant — for B24 and any future tree exposing a `children`
// array instead of `.left` / `.right`. Phantom logic doesn't apply
// (B24 invariants require internal nodes to have a full child
// complement). Each child's path extends the parent's by a single
// digit character.
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

// Trie variant — for the `Trie` class. A trie node carries `char` (the
// letter on its incoming edge; `none` at the root), `terminal` (whether
// a stored word ends here), and `children` (array of child nodes kept
// sorted by `char`). Each child's path extends the parent's by the
// child's `char`, so a node's path is exactly the prefix it spells. The
// node's drawn label is its terminal bit — "1" when a word ends here,
// "0" otherwise — and the letters live on the edges (set as edge `tag`s
// by the trie's paint helper). `child-index` / `n-siblings` record the
// node's position among its siblings so `draw-edge` can place each
// edge's letter tag on the correct side of a fork (see `want-x-sign`).
// No phantom siblings: a lone child hanging straight down is the desired
// trie look (a prefix chain), unlike the binary builder.
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

/// Emit the cetz draw commands for one styled snapshot of #raw("tree"),
/// _without_ wrapping them in a #raw("cetz.canvas"). Caller is
/// responsible for the canvas wrap. Use this when you want to add your
/// own cetz annotations alongside the tree — for example, callouts
/// anchored at specific nodes.
///
/// The whole tree is wrapped in a named cetz group (#raw("name"),
/// default #raw("\"tree\"")); each non-phantom node has an inner-name
/// of #raw("<node-prefix><cetz-tree-name>") where the cetz-tree name is
/// #raw("\"0\"") for the root, #raw("\"0-0\"") for L (or child 0),
/// #raw("\"0-1\"") for R (or child 1), and so on. Fully qualified anchor
/// names therefore look like #raw("\"tree.node-0-0-1\"") — use
/// @@path-anchor() to compute them from a path string.
///
/// Tree-shape dispatch: if #raw("tree") exposes a #raw("children")
/// field, the n-ary builder is used (no phantom-sibling layout, each
/// child path-segment is a digit indexing into #raw("children")).
/// Otherwise, the binary #raw(".left") / #raw(".right") builder runs.
///
/// -> content
#let draw-tree(
  /// The tree to render. Two accepted shapes:
  ///
  /// - Binary: any value with #raw("value"), #raw("label"),
  ///   #raw("left"), and #raw("right") fields (e.g. a #raw("BST")
  ///   instance). #raw("label") of #raw("auto") falls back to
  ///   #raw("str(value)"); any other value (string, image, content)
  ///   is rendered as the node's drawn label.
  /// - N-ary: any value with #raw("keys") (array of key values),
  ///   optional #raw("labels") (parallel array of label overrides),
  ///   and #raw("children") (array of child subtrees; empty for
  ///   leaves). Used with #raw("shape: \"btree-node\"") in the
  ///   default node-style to render the canonical subdivided
  ///   rectangle.
  /// -> dictionary
  tree,
  /// Style overlay for this snapshot. Use #raw("blank-snapshot()")
  /// (from the animation core) for an unstyled tree.
  /// -> Snapshot
  snapshot,
  /// Default node-style overrides applied before per-node overrides.
  /// -> dictionary
  default-node-style: (:),
  /// Default edge-style overrides applied before per-edge overrides.
  /// -> dictionary
  default-edge-style: (:),
  /// Structural defaults — the lowest layer of the style chain.
  /// Defaults to #raw("default-render-theme"); pass an already-merged
  /// dict (e.g. read from #raw("set-render-theme")'s state inside a
  /// #raw("context") block) to apply user overrides.
  /// -> dictionary
  render-theme: default-render-theme,
  /// Outer group name for the whole tree. Must match the #raw("tree-name")
  /// argument to @@path-anchor() for anchors to resolve.
  /// -> str
  name: "tree",
  /// Prefix attached to each node's cetz-tree internal name. Must match
  /// the #raw("prefix") argument to @@path-anchor().
  /// -> str
  node-prefix: "node-",
  /// Depth-direction layout factor passed to cetz-tree. Values below
  /// #raw("1") shorten edges between levels; values above #raw("1")
  /// stretch them. Node sizes are unaffected.
  /// -> float
  grow: 1,
  /// Sibling-direction layout factor passed to cetz-tree. Values below
  /// #raw("1") pull siblings together; values above #raw("1") push them
  /// apart. Node sizes are unaffected.
  /// -> float
  spread: 1,
) = {
  import cetz.draw
  import cetz.tree as cetz-tree
  // Any edge styled with `force-show: true` for a path that wouldn't
  // naturally exist (both children nil) needs a phantom anchor so the
  // stub edge has somewhere to land — used by the double-black dot.
  // N-ary trees never use this — their invariants forbid missing
  // children at internal nodes.
  // Shape dispatch. A trie carries `terminal` (and `children`); a B24
  // n-ary node carries `keys` (and `children`); a binary node carries
  // `left`/`right`. Check `terminal` first so a trie doesn't fall into
  // the generic n-ary path.
  let is-trie = "terminal" in tree
  let is-nary = (not is-trie) and "children" in tree
  let forced-phantoms = snapshot.edges.pairs()
    .filter(p => p.at(1).at("force-show", default: false))
    .map(p => p.at(0))
  let cetz-tree-root = if is-trie {
    _build-cetz-tree-trie(tree, "")
  } else if is-nary {
    _build-cetz-tree-nary(tree, "")
  } else {
    _build-cetz-tree(tree, "", forced-phantoms: forced-phantoms)
  }
  cetz-tree.tree(
    cetz-tree-root,
    name: name,
    group-name-prefix: node-prefix,
    grow: grow,
    spread: spread,
    draw-node: (node, ..) => {
        let path = node.content.path
        let s = _merge-into(
          default-node-style,
          snapshot.nodes.at(path, default: (:)),
        )
        let is-phantom = node.content.at("phantom", default: false)
        if is-phantom and not s.at("materialize", default: false) {
          // Reserve a slightly-wider-than-a-node layout footprint, but
          // render nothing. `bounds: true` keeps the bounding box for
          // cetz's tree layout while hiding the drawable. Width > node
          // diameter so the lone real sibling visibly hangs off-center
          // rather than sitting almost-under its parent.
          draw.hide(draw.rect((-0.9, -0.6), (0.9, 0.6)), bounds: true)
          return
        }
        if s.at("hide", default: false) { return }
        let shape = s.at("shape", default: "circle")
        let fill-c = s.at("fill", default: render-theme.node-fill)
        let stroke-c = s.at("stroke", default: render-theme.node-stroke)

        // n-ary B24 node — subdivided rectangle, width scales with the
        // number of keys. Per-compartment styling comes from
        // `s.key-styles`; key labels come from the node content's
        // `labels` array (entry `auto` falls back to `str(key)`).
        if shape == "btree-node" {
          let keys = node.content.keys
          let labels = node.content.at("labels", default: ())
          let n = keys.len()
          let half-w = 0.6 * n
          let key-styles = s.at("key-styles", default: ())
          let ks-at = i => if i < key-styles.len() { key-styles.at(i) } else { (:) }
          // Outer rect first — default fill + stroke fills the whole node.
          draw.rect(
            (-half-w, -0.6),
            (half-w, 0.6),
            fill: fill-c,
            stroke: stroke-c,
          )
          // Per-compartment fills, drawn over the outer rect before the
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
          // Per-compartment strokes — drawn last so a highlighted
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
          let default-text = s.at(
            "text-fill",
            default: render-theme.node-text-fill,
          )
          for (i, key) in keys.enumerate() {
            let ks = ks-at(i)
            let kt = ks.at("text-fill", default: default-text)
            let raw-label = if i < labels.len() { labels.at(i) } else { auto }
            let label-content = if raw-label == auto {
              str(key)
            } else { raw-label }
            let cx = -half-w + 0.6 + 1.2 * i
            draw.content(
              (cx, 0),
              text(weight: "bold", fill: kt, label-content),
            )
            draw.anchor("key-" + str(i), (cx, 0))
          }
          // Gap anchors — child-edge attachment points on the south
          // face, one per child position. `gap-0` is leftmost,
          // `gap-<n>` is rightmost.
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
          // Note slot — anchored east of the entire node.
          let n-note = s.at("note", default: none)
          if n-note != none {
            let nf = s.at("note-fill", default: render-theme.note-fill)
            draw.content(
              (half-w + 0.15, 0),
              anchor: "west",
              text(fill: nf, size: 0.8em, n-note),
            )
          }
          // Tag slot — anchored west of the entire node.
          let tag = s.at("tag", default: none)
          if tag != none {
            draw.content(
              (-half-w - 0.05, 0),
              anchor: "east",
              text(fill: render-theme.edge-stroke, size: 0.7em, tag),
            )
          }
          return
        }

        // Binary shapes — `value` / `label` are required.
        let value = node.content.at("value", default: none)
        let raw-label = node.content.at("label", default: auto)
        let default-label = if raw-label == auto {
          if value == none { "" } else { str(value) }
        } else { raw-label }
        let label = s.at("label", default: default-label)
        // Shape dispatch. New shapes go here; keep bounding boxes
        // sensible so the named cetz anchors (north/south/east/west on
        // the node group) land where users expect, since the edge
        // anchor overrides reference them. `label-pos` shifts the
        // label off the geometric origin for shapes that taper — a
        // triangle's apex narrows to nothing at the top, so its
        // label sits at the centroid (y = -0.2) where the shape is
        // wide enough to host larger fonts without clipping the
        // sloped sides.
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
        let tf = s.at("text-fill", default: render-theme.node-text-fill)
        // Bold the label via `weight:` rather than `*..*` markup so a
        // user `show strong: set text(fill: ..)` rule in the document
        // can't override our computed `tf` — the contrast-aware fill
        // in `_text-fill-for` exists precisely so labels stay readable
        // against gradient-filled traversal nodes, and we don't want it
        // silently undone by ambient styling.
        // Anchor explicitly at `label-pos` (set by the shape branch
        // above) rather than `()` (the previous cetz coordinate).
        // After `draw.line(..)` or `draw.rect(..)`, the previous
        // coordinate is the last vertex/corner, not the centre.
        draw.content(label-pos, text(weight: "bold", fill: tf, label))
        let n = s.at("note", default: none)
        if n != none {
          let nf = s.at("note-fill", default: render-theme.note-fill)
          draw.content(
            (0.75, 0),
            anchor: "west",
            text(fill: nf, size: 0.8em, n),
          )
        }
        // Tag — small annotation pinned just outside the west of the
        // node. Used by RBT `display(bits: true)` to show per-node
        // black-height bits. Drawn in the render theme's edge-stroke
        // color so it reads as a marginal annotation rather than node
        // content. West of equator avoids overlap with the incoming
        // parent edge (NE / NW) and outgoing child edges (SW / SE).
        let tag = s.at("tag", default: none)
        if tag != none {
          draw.content(
            (-0.65, 0),
            anchor: "east",
            text(fill: render-theme.edge-stroke, size: 0.7em, tag),
          )
        }
      },
      draw-edge: (from, to, ..) => {
        let child-path = to.content.path
        let s = _merge-into(
          default-edge-style,
          snapshot.edges.at(child-path, default: (:)),
        )
        // Phantom edges are skipped by default. `force-show: true` lets
        // a stub edge render to (or from) a phantom — used to visualise
        // double-black on a now-nil tree slot.
        let force = s.at("force-show", default: false)
        if not force and to.content.at("phantom", default: false) { return }
        if not force and from.content.at("phantom", default: false) { return }
        if s.at("hide", default: false) { return }
        let mark = s.at("mark", default: none)
        // Endpoint resolution. Default is the empirical 0.4-fractional
        // trick (lands cleanly in the gap between two circle nodes); a
        // `parent-anchor` / `child-anchor` override swaps that side
        // for a named cetz anchor on the node group, which is how
        // non-circular shapes (triangle apex, etc.) get clean
        // connections.
        //
        // For n-ary parents (detected by `keys` in `from.content`), the
        // default parent anchor is the `gap-<i>` anchor on the south
        // face, where `i` is the child's index — i.e. the last digit
        // of the child path. Likewise n-ary children default to
        // landing at their group's explicit `top` anchor — the box's
        // true top-center, unlike the computed `north`, which the
        // east-side note would drag off the box. Explicit
        // `parent-anchor` / `child-anchor` overrides still win.
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
          // caller overrode this n-ary node's shape (e.g. a triangle
          // standing in for a subtree), fall back to the group's
          // computed `north`, which every shape provides and which lands
          // on the apex / top-center of the symmetric binary shapes.
          let child-shape = _merge-into(
            default-node-style,
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
          stroke: s.at("stroke", default: render-theme.edge-stroke),
          ..if mark != none { (mark: mark) },
        )
        // `note` sits on the edge line itself — midpoint of the
        // parent's south anchor and the child's north anchor. Bare
        // group names happen to resolve near the parent's centroid
        // rather than midway between centroids, so we use named
        // anchors explicitly.
        let n = s.at("note", default: none)
        if n != none {
          let nf = s.at("note-fill", default: render-theme.note-fill)
          draw.content(
            (from.group-name + ".south", 0.5, to.group-name + ".north"),
            text(fill: nf, size: 0.8em, n),
          )
        }
        // `tag` sits *off* the edge line, at its midpoint offset
        // perpendicular to the edge direction. The earlier SW/NW vs
        // SE/NE corner-anchor interpolation broke down for wide
        // subtrees — at shallow edge slopes, the parent's and child's
        // outer corners lined up with the edge line itself, putting
        // the tag on top of the stroke. A geometric perpendicular
        // works at any slope.
        let tag = s.at("tag", default: none)
        if tag != none {
          // Sign of the perpendicular offset picks the "outside" of
          // the V (away from the sibling subtree):
          //   binary — L child → negative-x, R child → positive-x.
          //   n-ary  — child index left of center → negative-x, else
          //           positive-x.
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
              ctx, parent-coord, child-coord,
            )
            let dx = c.at(0) - p.at(0)
            let dy = c.at(1) - p.at(1)
            let len = calc.sqrt(dx * dx + dy * dy)
            // Rotate the edge vector 90° to get a perpendicular, then
            // flip if its x-sign disagrees with the desired outside
            // direction. Degenerate case (len == 0) falls back to a
            // pure-x offset.
            let (px, py) = if len == 0 {
              (want-x-sign, 0)
            } else {
              let cx = -dy / len
              let cy = dx / len
              if (cx >= 0) == (want-x-sign > 0) {
                (cx, cy)
              } else {
                (-cx, -cy)
              }
            }
            let offset = 0.3
            draw.content(
              (
                (p.at(0) + c.at(0)) / 2 + px * offset,
                (p.at(1) + c.at(1)) / 2 + py * offset,
              ),
              text(fill: render-theme.edge-tag-fill, size: 0.7em, tag),
            )
          })
        }
      },
  )
}

// ===================================================================
// Tree-bound wrappers over the generic kernel
// ===================================================================

// The draw backend the tree renderer injects into the generic
// `Renderer`. Wrapped in a singleton dict `(fn: ..)` so typsy doesn't
// self-inject on the function-typed `draw` field (see `anim-core.typ`).
#let _draw-tree-backend = (
  fn: (structure, snapshot, dns, des, rt) => draw-tree(
    structure,
    snapshot,
    default-node-style: dns,
    default-edge-style: des,
    render-theme: rt,
  ),
)

// Convenience wrapper: `draw-tree` inside a `cetz.canvas`. Preserved
// signature for the per-DS `_make-frames` helpers that call it.
#let _render-canvas(
  tree,
  snapshot,
  default-node-style,
  default-edge-style,
  render-theme,
) = core._make-canvas(
  _draw-tree-backend,
  tree,
  snapshot,
  default-node-style,
  default-edge-style,
  render-theme,
)

/// Translates a starling path-id to the fully-qualified cetz anchor
/// name produced by @@draw-tree(). Path #raw("\"\"") maps to the root
/// anchor; binary paths use #raw("\"L\"") / #raw("\"R\"") (mapping to
/// child indices 0 and 1); n-ary paths use digit characters
/// #raw("\"0\"") to #raw("\"9\"") that pass through verbatim.
///
/// An optional #raw("\"#<int>\"") suffix on the path (n-ary only)
/// resolves to a per-compartment sub-anchor #raw("key-<int>") on the
/// btree-node — e.g. #raw("path-anchor(\"01#1\")") returns the anchor
/// of the middle key compartment of the leftmost grandchild.
///
/// The #raw("tree-name") and #raw("prefix") arguments must match the
/// #raw("name") and #raw("node-prefix") passed to #raw("draw-tree").
///
/// -> str
#let path-anchor(
  /// Path-id string identifying a node (optionally followed by
  /// #raw("\"#<int>\"") for a btree-node compartment).
  /// -> str
  path,
  /// Outer-group name; must match #raw("draw-tree")'s #raw("name").
  /// -> str
  tree-name: "tree",
  /// Per-node prefix; must match #raw("draw-tree")'s #raw("node-prefix").
  /// -> str
  prefix: "node-",
) = {
  let parts = path.split("#")
  let node-path = parts.at(0)
  let key-suffix = if parts.len() > 1 { ".key-" + parts.at(1) } else { "" }
  let segments = ("0",)
  for c in node-path.codepoints() {
    if c == "L" { segments.push("0") } else if c == "R" {
      segments.push("1")
    } else { segments.push(c) }
  }
  tree-name + "." + prefix + segments.join("-") + key-suffix
}

/// Build a tree #raw("Renderer") seeded with one blank initial frame,
/// bound to the @@draw-tree() backend. Thin wrapper over the generic
/// #raw("make-renderer") in #raw("anim-core.typ") that injects the tree
/// draw backend, preserving the historical #raw("make-renderer(tree,
/// ..)") signature.
///
/// -> Renderer
#let make-renderer(
  /// The tree to render — any value with #raw("value"), #raw("label"),
  /// #raw("left"), and #raw("right") fields (binary) or #raw("keys") /
  /// #raw("children") (n-ary). See @@draw-tree().
  /// -> dictionary
  tree,
  /// Default node-style overrides applied before per-snapshot overrides.
  /// -> dictionary
  default-node-style: (:),
  /// Default edge-style overrides applied before per-snapshot overrides.
  /// -> dictionary
  default-edge-style: (:),
  /// When #raw("true"), new frames inherit the previous frame's style.
  /// When #raw("false"), each new frame starts blank.
  /// -> bool
  sticky: true,
  /// Render-theme override for this renderer. #raw("auto") reads the
  /// active render-theme from state at layout time. A dict is merged
  /// into #raw("default-render-theme") once and baked in.
  /// -> auto | dictionary
  theme: auto,
) = core.make-renderer(
  tree,
  _draw-tree-backend,
  default-node-style: default-node-style,
  default-edge-style: default-edge-style,
  sticky: sticky,
  theme: theme,
)

// Backwards-compatible alias: the renderer class is now the generic
// `Renderer` in `anim-core.typ`, re-exported here under its historical
// name.
#let TreeRenderer = Renderer
