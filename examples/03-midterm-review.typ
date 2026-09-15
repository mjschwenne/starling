#import "@preview/touying:0.7.3": *
#import "@local/touying-solaris:0.2.0": *

#import "@preview/theorion:0.6.0": *
#import cosmos.clouds: *
#show: show-theorion

#import "@preview/booktabs:0.0.4": *
#show: booktabs-default-table-style

#import "@preview/cetz:0.5.2"
#import "@preview/fletcher:0.5.8" as fletcher: diagram, edge, node
#import fletcher.shapes: chevron, circle, triangle
#let cetz-canvas = touying-reducer.with(
  reduce: cetz.canvas,
  cover: cetz.draw.hide.with(bounds: true),
)
#let fletcher-diagram = touying-reducer.with(
  reduce: fletcher.diagram,
  cover: fletcher.hide,
)

#import "../src/lib.typ" as starling: (
  apply-ops, apply-snapshot, avl, b24, bst, rbt, style-edge, style-node,
)

#let handout = sys.inputs.at("handout", default: "false") == "true"

#show: solaris-theme.with(
  aspect-ratio: "16-9",
  config-info(
    title: [Midterm Review],
    subtitle: [_CS 400 -- Programming III_],
    author: [Matt Schwennesen],
    date: datetime(year: 2026, month: 07, day: 9).display(
      "[month repr:long] [day], [year repr:full]",
    ),
    logo: image("./00-common-assets/uw-logo.svg"),
  ),
  config-common(
    handout: handout,
  ),
)

#title-slide(
  logo: image(
    "00-common-assets/uw-logo-horizontal-color-reverse-web-digital.svg",
    height: 1in,
    alt: "University of Wisconsin-Madison logo.",
  ),
)

#outline-slide()

#focus-slide(
  theme: "lemon",
  icon: nf-icon("file_pen"),
  [Midterm Logistics],
)

#let fmt = "[weekday], [month repr:long] [day], [year] at [hour repr:12]:[minute]:[second] [period] Central Time"

== Midterm Logistics

#item-by-item[
  - Midterm released #datetime(
      year: 2026,
      month: 07,
      day: 09,
      hour: 0,
      minute: 0,
      second: 0,
    ).display(fmt)
  - Midterm due #datetime(
      year: 2026,
      month: 07,
      day: 10,
      hour: 23,
      minute: 59,
      second: 59,
    ).display(fmt)
  - Two hour time limit.
  - 30 questions, no written code questions.
  - Scratch paper allowed and recommended.
  - Honorlock required.
    - Google chrome based browser with Honorlock extension
]

== Midterm Topics

#columns(2)[
  - Binary Search Tree Rotations
  - Red-Black Trees
    - Insertion
    - Deletion
    - Properties
  - AVL trees
  - B-Trees
  - Graphs
  - CSV files
  - Make
  - Testing & JUnit
  - Bash Commands
  - Version Control
  - Anonymous Classes
  - Lambda Expressions
]

#focus-slide(
  theme: "ocean",
  icon: nf-icon("file_pen"),
  [Midterm Review],
)

== BST Right Rotation Pattern


== BST Right Rotation Pattern

#let rr = bst.leaf(1, label: "GP")
#let rr = bst.insert(rr, 5, label: "P")
#let rr = bst.insert(rr, 3, label: "C")
#let rr = bst.insert(rr, 2, label: "X")
#let rr = bst.insert(rr, 4, label: "Y")
#let rr = bst.insert(rr, 6, label: "Z")

#let rr_snap = apply-snapshot(
  starling.blank-snapshot(),
  style-node("RLL", shape: "triangle")
    + style-edge("RLL", child-anchor: "north")
    + style-node(
      "RLR",
      shape: "triangle",
      stroke: color.blue,
      text-fill: color.blue,
    )
    + style-edge(
      "RLR",
      child-anchor: "north",
      stroke: color.blue,
    )
    + style-node("RR", shape: "triangle")
    + style-edge("RR", child-anchor: "north"),
)

#let rrr = bst.leaf(1, label: "GP")
#let rrr = bst.insert(rrr, 3, label: "C")
#let rrr = bst.insert(rrr, 2, label: "X")
#let rrr = bst.insert(rrr, 5, label: "P")
#let rrr = bst.insert(rrr, 4, label: "Y")
#let rrr = bst.insert(rrr, 6, label: "Z")

#let rrr_snap = apply-snapshot(
  starling.blank-snapshot(),
  style-node(
    "RRL",
    shape: "triangle",
    stroke: color.blue,
    text-fill: color.blue,
  )
    + style-edge(
      "RRL",
      child-anchor: "north",
      stroke: color.blue,
    )
    + style-node("RRR", shape: "triangle")
    + style-edge("RRR", child-anchor: "north")
    + style-node("RL", shape: "triangle")
    + style-edge("RL", child-anchor: "north"),
)

#align(center, cetz-canvas({
  import cetz.draw: *

  starling.draw-tree(rr, rr_snap, name: "pre")
  (pause,)
  content(
    (4, 0),
    (9, -2),
    box(
      par(justify: false)[Could be on either side],
      stroke: 1pt + color.orange,
      fill: color.orange,
      width: 100%,
      height: 100%,
      inset: 1.5mm,
    ),
  )
  line(
    (5, -1),
    (rel: (0.6, 0), to: starling.anchor("", canvas: "pre")),
    stroke: 2pt + color.orange,
    mark: (end: ")>"),
    fill: color.orange,
  )
  set-origin((12, 0))

  (pause,)
  mark(
    (0, -5),
    (1, -5),
    symbol: ">",
    scale: 10,
    stroke: color.red,
    fill: color.red,
  )

  content(
    (-7, -5.5),
    (-1, -4.5),
    box(
      par(justify: false)[Rotate C & P],
      fill: color.red,
      inset: 2mm,
    ),
  )
  starling.draw-tree(rrr, rrr_snap, name: "post")
}))

== BST Left Rotation Pattern

#let left_pre = bst.leaf(1, label: "GP")
#let left_pre = bst.insert(left_pre, 3, label: "P")
#let left_pre = bst.insert(left_pre, 5, label: "C")
#let left_pre = bst.insert(left_pre, 2, label: "X")
#let left_pre = bst.insert(left_pre, 4, label: "Y")
#let left_pre = bst.insert(left_pre, 6, label: "Z")

#let pre_snap = apply-snapshot(
  starling.blank-snapshot(),
  style-node("RL", shape: "triangle")
    + style-edge("RL", child-anchor: "north")
    + style-node(
      "RRL",
      shape: "triangle",
      stroke: color.blue,
      text-fill: color.blue,
    )
    + style-edge(
      "RRL",
      child-anchor: "north",
      stroke: color.blue,
    )
    + style-node("RRR", shape: "triangle")
    + style-edge("RRR", child-anchor: "north"),
)

#let left_post = bst.leaf(1, label: "GP")
#let left_post = bst.insert(left_post, 5, label: "C")
#let left_post = bst.insert(left_post, 3, label: "P")
#let left_post = bst.insert(left_post, 2, label: "X")
#let left_post = bst.insert(left_post, 4, label: "Y")
#let left_post = bst.insert(left_post, 6, label: "Z")

#let post_snap = apply-snapshot(
  starling.blank-snapshot(),
  style-node(
    "RLR",
    shape: "triangle",
    stroke: color.blue,
    text-fill: color.blue,
  )
    + style-edge(
      "RLR",
      child-anchor: "north",
      stroke: color.blue,
    )
    + style-node("RLL", shape: "triangle")
    + style-edge("RLL", child-anchor: "north")
    + style-node("RR", shape: "triangle")
    + style-edge("RR", child-anchor: "north"),
)

#align(center, cetz-canvas({
  import cetz.draw: *

  starling.draw-tree(left_pre, pre_snap, name: "pre")
  (pause,)
  content(
    (4, 0),
    (9, -2),
    box(
      par(justify: false)[Could be on either side],
      stroke: 1pt + color.orange,
      fill: color.orange,
      width: 100%,
      height: 100%,
      inset: 1.5mm,
    ),
  )
  line(
    (5, -1),
    (rel: (0.6, 0), to: starling.anchor("", canvas: "pre")),
    stroke: 2pt + color.orange,
    mark: (end: ")>"),
    fill: color.orange,
  )
  set-origin((12, 0))

  (pause,)
  mark(
    (0, -5),
    (1, -5),
    symbol: ">",
    scale: 10,
    stroke: color.red,
    fill: color.red,
  )

  content(
    (-7, -5.5),
    (-1, -4.5),
    box(
      par(justify: false)[Rotate P & C],
      fill: color.red,
      inset: 2mm,
    ),
  )
  starling.draw-tree(left_post, post_snap, name: "post")
}))

== Red Black Tree Properties

#slide(repeat: 5, self => {
  let reveal(n, body) = if self.subslide >= n { body } else { hide(body) }
  definition-box[Red Black Tree][
    A binary search tree with four extra properties:
    + #reveal(2)[Color Property]
    + #reveal(3)[Red-Child Property]
    + #reveal(4)[Root Property]
    + #reveal(5)[Black-Height Property]
  ]
})

== Red Black Tree Insertions

#item-by-item[
  + Start with a *valid* red black tree.
  + Perform *naive BST insertion* algorithm, ignoring colors.
  + Set the new node to be #highlight(fill: red.B)[red].
  + *Fix* any new red black property violation.
]

== Case 1: Red Aunt

#let n_1 = highlight(fill: black, text(fill: white)[+1])
#let red_n = highlight(fill: red.B)[red]
#let black_n = highlight(fill: black, text(fill: white)[black])
If the aunt of the child is #red_n:
+ Make the parent and aunt #black_n
+ Make the grandparent #red_n
+ Check for red-child violations *higher up the tree*.

#let style_black = (fill: color.black, text-fill: color.white)
#let subtree(path) = (
  style-node(
    path,
    stroke: color.gray,
    shape: "triangle",
    fill: color.gray,
  ),
  style-edge(path, child-anchor: "north"),
)
#let disp_red(path) = style-node(
  path,
  fill: red.B,
  stroke: red.B,
  text-fill: color.white,
)
#let disp_black(path) = style-node(
  path,
  fill: color.black,
  stroke: color.black,
  text-fill: color.white,
)
#let c1_t = rbt.new(
  (4, [G]),
  (2, [A]),
  (6, [P]),
  (1, []),
  (3, []),
  (5, [C]),
  (7, []),
)
#align(center, stack(
  dir: ltr,
  spacing: 1cm,
  context {
    let r = rbt.renderer(c1_t, sticky: true)
    r = starling.apply-ops(r, (
      ..subtree("LL"),
      ..subtree("LR"),
      ..subtree("RR"),
      disp_red("L"),
      disp_red("R"),
      starling.set-alt(
        "Red black tree with a red-child property violation
    before repair.",
      ),
    ))
    starling.last(starling.render(r))
  },
  cetz-canvas({
    import cetz.draw: *
    line((0, 0), (3, 0), stroke: white)
    line(
      (0, -3),
      (3, -3),
      mark: (end: ">", scale: 4, fill: blue.B),
      stroke: blue.B + 5pt,
    )
    content((0, -4), (3, -4), text(fill: blue.B)[Recolor])
  }),
  context {
    let r = rbt.renderer(c1_t, sticky: true)
    r = starling.apply-ops(r, (
      ..subtree("LL"),
      ..subtree("LR"),
      ..subtree("RR"),
      disp_red(""),
      starling.set-alt(
        "Red black tree after red-child property as been
      fixed. Parent and Aunt are black while the grandparent is red.",
      ),
    ))
    starling.last(starling.render(r))
  },
))

== Case 2: Black Aunt Same Side

If the aunt of the child is #black_n *and* the parent and child are on the *same
side* (i.e. both left or both right children):
+ *Rotate* the parent and grandparent
+ Swap the colors of the parent and grandparent
#let c2_t1 = rbt.new(
  (4, [G]),
  (2, [A]),
  (6, [P]),
  (1, []),
  (3, []),
  (5, []),
  (7, [C]),
)
#let c2_t2 = rbt.rotate(c2_t1, c2_t1.right)
#align(center, stack(
  dir: ltr,
  spacing: 1cm,
  context {
    let r = rbt.renderer(c2_t1, sticky: true)
    r = starling.apply-ops(r, (
      ..subtree("LL"),
      ..subtree("LR"),
      ..subtree("RL"),
      disp_red("R"),
      starling.set-alt(
        "Red black tree with a red-child property violation
    before repair.",
      ),
    ))
    starling.last(starling.render(r))
  },
  cetz-canvas({
    import cetz.draw: *
    line((0, 0), (4, 0), stroke: white)
    line(
      (0, -2),
      (4, -2),
      mark: (end: ">", scale: 4, fill: blue.B),
      stroke: blue.B + 5pt,
    )
    content((0, -3), (5, -3), text(fill: blue.B)[Rotate & Color Swap])
  }),
  context {
    let r = rbt.renderer(c2_t2, sticky: true)
    r = starling.apply-ops(r, (
      ..subtree("LLL"),
      ..subtree("LLR"),
      ..subtree("LR"),
      disp_red("L"),
      starling.set-alt(
        "Red black tree after red-child property as been
      fixed. Parent and Aunt are black while the grandparent is red.",
      ),
    ))
    scale(x: 82%, y: 82%, reflow: true, starling.last(starling.render(r)))
  },
))

== Case 3: Black Aunt Zig-Zag

#let bleaf(v, label: auto) = rbt.black(v, label: label)
#let rleaf(v, label: auto) = rbt.red(v, label: label)
#let bnode(v, l, r, label: auto) = rbt.black(v, l, r, label: label)
#let rnode(v, l, r, label: auto) = rbt.red(v, l, r, label: label)

If the aunt of the child is #black_n *and* and parent and child are *on
different sides* (not both left or both right children):
+ *Rotate* the parent and child
+ Handle the result using *Case 2*

#let c3_t1 = bnode(
  2,
  bleaf(1, label: [A]),
  rnode(4, rleaf(3, label: [C]), none, label: [P]),
  label: [G],
)
#let c3_t2 = rbt.rotate(c3_t1, c3_t1.right.left)

#align(center, stack(
  dir: ltr,
  spacing: 1cm,
  starling.last(rbt.display(c3_t1)),
  cetz-canvas({
    import cetz.draw: *
    line((0, 0), (3, 0), stroke: white)
    line(
      (0, -3),
      (3, -3),
      mark: (end: ">", scale: 4, fill: blue.B),
      stroke: blue.B + 5pt,
    )
    content((0, -4), (3, -4), text(fill: blue.B)[Rotate])
  }),
  starling.last(rbt.display(c3_t2)),
))

== Case 4: Null Aunt

Use either *Case 2* or *Case 3* treating the null as if it was #black_n.

#let c4_t1 = bnode(
  4,
  rnode(1, none, rleaf(3, label: [C]), label: [P]),
  bleaf(6, label: math.equation(
    $emptyset$,
    alt: "null",
  )),
  label: [G],
)
#let c4_t2 = rbt.rotate(c4_t1, c4_t1.left.right)
#let c4_t3 = rbt.rotate(c4_t2, c4_t2.left)

#align(center, stack(
  dir: ltr,
  spacing: 1cm,
  starling.last(rbt.display(c4_t1)),
  cetz-canvas({
    import cetz.draw: *
    line((0, 0), (3, 0), stroke: white)
    line(
      (0, -3),
      (3, -3),
      mark: (end: ">", scale: 4, fill: blue.B),
      stroke: blue.B + 5pt,
    )
    content((0, -4), (3, -4), text(fill: blue.B)[Rotate])
  }),
  starling.last(rbt.display(c4_t2)),
  cetz-canvas({
    import cetz.draw: *
    line((0, 0), (3, 0), stroke: white)
    line(
      (0, -3),
      (5, -3),
      mark: (end: ">", scale: 4, fill: blue.B),
      stroke: blue.B + 5pt,
    )
    content((0, -4), (5, -4), text(fill: blue.B)[Rotate & Color Swap])
  }),
  context {
    let r = rbt.renderer(c4_t3, sticky: true)
    r = starling.apply-ops(r, (disp_black(""), disp_red("R")))
    starling.last(starling.render(r))
  },
))

== Red Black Tree Insertion Summary

#v(-1cm)
#align(center, image(
  "01-rbt-insert.svg",
  height: 4.6in,
  alt: "Summary of all red black tree insertion
cases. This handout will be provided for exams.",
))

== Red Black Tree Deletions

+ Start with a *valid* red black tree.
+ Perform *naïve BST deletion* algorithm, ignoring colors.
+ *Fix* any new red black tree property violation.

#let mkRBT-renderer(t) = rbt.renderer(t, bits: true, sticky: true)

#let commit(alt) = starling.commit(alt: alt)

#let force_show(..paths) = (
  paths.pos().map(p => style-edge(p, force-show: true))
)

#let hide(..paths) = {
  let ops = ()
  for p in paths.pos() {
    ops.push(style-node(
      p,
      tag: [],
      stroke: white,
      text-fill: white,
      fill: white,
    ))
    ops.push(style-edge(p, stroke: white))
  }
  ops
}

#let disp_red(..paths) = {
  paths
    .pos()
    .map(p => style-node(
      p,
      fill: red.B,
      stroke: red.B,
      tag: [0],
    ))
}

#let disp_black(..paths) = {
  paths
    .pos()
    .map(p => style-node(
      p,
      fill: black,
      stroke: black,
      tag: [1],
    ))
}

#let double_black(..paths) = {
  let ops = ()
  for p in paths.pos() {
    ops.push(style-node(p, tag: [2]))
    ops.push(style-edge(
      p,
      mark: (end: "o", fill: black, scale: 2, offset: 0.2),
    ))
  }
  ops
}

#let rm_double_black(..paths) = {
  paths.pos().map(p => style-edge(p, mark: none))
}

#let null(..paths) = (
  paths
    .pos()
    .map(p => style-node(
      p,
      materialize: true,
      label: sym.emptyset,
      fill: white,
      text-fill: black,
      tag: [],
    ))
)

#let subtree(..paths) = {
  let ops = ()
  for p in paths.pos() {
    ops.push(style-node(
      p,
      shape: "triangle",
      tag: none,
      fill: gray,
      stroke: gray,
    ))
    ops.push(style-edge(
      p,
      child-anchor: "north",
    ))
  }
  ops
}

#let attention(..paths) = {
  let ops = ()
  paths
    .pos()
    .map(p => style-node(
      p,
      stroke: starling.default-theme.op.attention-stroke,
    ))
}

#let double_black_subtree(..paths) = {
  let ops = ()
  for p in paths.pos() {
    ops.push(style-node(
      p,
      shape: "triangle",
      tag: none,
      fill: gray,
      stroke: gray,
    ))
    ops.push(
      style-edge(
        p,
        mark: (end: "o", fill: black, scale: 2),
        child-anchor: "north",
      ),
    )
  }
  ops
}

#let any_a(..paths) = (
  paths.pos().map(p => style-node(p, tag: [X], fill: blue.B, stroke: blue.B))
)

#let any_b(..paths) = (
  paths
    .pos()
    .map(p => style-node(p, tag: [Y], fill: color.purple, stroke: color.purple))
)

#let either(..paths) = {
  let grad = gradient.linear(
    (red.B, 0%),
    (red.B, 42%),
    (black, 75%),
    (black, 100%),
    angle: 0deg,
  )
  paths.pos().map(p => style-node(p, tag: [0 or 1], stroke: grad, fill: grad))
}

#let maybe_double(..paths) = (
  paths.pos().map(p => style-node(p, tag: [1 or 2]))
)


== Remove Case: Red Leaf

#let arrow = align(horizon, cetz.canvas({
  import cetz.draw: *
  line((0, 0), (4, 0), mark: (end: ">"), stroke: color.orange + 20pt)
}))

#let rl = bnode(
  3,
  rnode(
    1,
    bleaf(0, label: [#sym.emptyset]),
    bleaf(2, label: [#sym.emptyset]),
    label: "",
  ),
  none,
  label: "",
)
#let rlf = bnode(2, bleaf(1, label: sym.emptyset), none, label: "")

If the node being deleted is a #red_n leaf node, no extra steps are required.

#figure(
  stack(
    dir: ltr,
    spacing: 1cm,
    context {
      let r = apply-ops(mkRBT-renderer(rl), null("LL", "LR"))
      starling.last(starling.render(r))
    },
    pause,
    h(-1cm),
    arrow,
    pause,
    context {
      let r = apply-ops(mkRBT-renderer(rlf), null("L"))
      starling.last(starling.render(r))
    },
  ),
  alt: "Diagram showing a red leaf being deleted.",
)

== Remove Case: Red with Red Predecessor

#let rr = rnode(
  3,
  bnode(1, none, rleaf(2, label: [P]), label: ""),
  none,
  label: "D",
)
#let rrf = rnode(
  2,
  bleaf(1, label: ""),
  none,
  label: [P],
)

If the node being deleted is #red_n, and it's predecessor is #red_n, no extra
steps are required.

#figure(
  stack(
    dir: ltr,
    spacing: 1cm,
    context {
      let r = apply-ops(mkRBT-renderer(rr), force_show("LL", "R"))
      starling.last(starling.render(r))
    },
    pause,
    arrow,
    pause,
    context {
      let r = apply-ops(mkRBT-renderer(rrf), force_show("LL", "R"))
      starling.last(starling.render(r))
    },
  ),
  alt: "Diagram showing a red leaf being deleted.",
)

== Remove Case: Red with Black Predecessor

If the node being deleted is #red_n, and its predecessor is #black_n:
+ Add #n_1 to the color of the predecessor's previous child.

#let rbr = rnode(
  4,
  bnode(1, none, bnode(3, bleaf(2, label: [C]), none, label: [P]), label: []),
  none,
  label: [D],
)

#let rbrf = rnode(
  4,
  bnode(1, none, bleaf(2, label: [C]), label: []),
  none,
  label: [D],
)

#figure(
  stack(
    dir: ltr,
    spacing: 1cm,
    context {
      let rbr_r = apply-ops(
        mkRBT-renderer(rbr),
        any_a("L") + subtree("LRL") + force_show("LL"),
      )
      starling.last(starling.render(rbr_r))
    },
    pause,
    arrow,
    pause,
    context {
      let rbrf_r = apply-ops(
        mkRBT-renderer(rbrf),
        any_a("L") + double_black_subtree("LR") + force_show("LL"),
      )
      cetz.canvas({
        import cetz.draw: *

        starling.draw-tree(rbrf, rbrf_r.snapshots.at(0))
        line((4, -2), (2.6, -3.6), stroke: color.orange + 3pt, mark: (end: ">"))
        content((7, -1), box(
          text(size: 0.75em)[Need to add another black node along this path],
          width: 2.5in,
          fill: color.orange,
          inset: 6pt,
          radius: 5%,
        ))
      })
    },
  ),
  alt: "When a red node with black replacement is removed, mark the child of
the removed node.",
)

== Remove Case: Black Leaf

If the node being deleted is a #black_n leaf node:
+ Add #n_1 to the color of the null replacing the value.

#let bl = bnode(1, bleaf(0, label: [D]), label: [], none)
#let blf = bleaf(1, label: [])
#figure(
  stack(
    dir: ltr,
    spacing: 1cm,
    {
      let r = apply-ops(
        mkRBT-renderer(bl),
        force_show("LL", "LR", "R") + null("LL", "LR") + any_a(""),
      )
      starling.last(starling.render(r))
    },
    pause,
    arrow,
    pause,
    {
      let r = apply-ops(
        mkRBT-renderer(blf),
        force_show("L", "R") + double_black("L") + null("L") + any_a(""),
      )
      starling.last(starling.render(r))
    },
  ),
)

== Remove Case: Black with Red Replacement

If the node being deleted is #black_n, and its replacement (either child or
predecessor) is #red_n:
+ Set the replacement to #black_n

#let br = bnode(
  3,
  bnode(1, none, rleaf(2, label: [P]), label: []),
  none,
  label: [D],
)
#let brf = bnode(2, bleaf(1, label: []), none, label: [P])
#figure(
  stack(
    dir: ltr,
    spacing: 1cm,
    {
      let r = apply-ops(mkRBT-renderer(br), force_show("LL", "R"))
      starling.last(starling.render(r))
    },
    pause,
    arrow,
    pause,
    {
      let r = apply-ops(mkRBT-renderer(brf), force_show("LL", "R"))
      starling.last(starling.render(r))
    },
  ),
)

== Remove Case: Black with Black Replacement

If the node being deleted is #black_n, and its replacement is #black_n:
+ Add #n_1 to the color of the predecessor's previous child
#v(-0.4cm)
#let bb = bnode(
  4,
  bnode(1, none, bnode(3, bleaf(2, label: [C]), none, label: [P]), label: []),
  none,
  label: [D],
)
#let bbf = bnode(
  4,
  bnode(1, none, bleaf(3, label: [C]), label: []),
  none,
  label: [P],
)
#figure(
  stack(
    dir: ltr,
    spacing: 1cm,
    {
      let r = apply-ops(
        mkRBT-renderer(bb),
        force_show("LL", "R") + any_a("L") + subtree("LRL"),
      )
      starling.last(starling.render(r))
    },
    pause,
    arrow,
    pause,
    {
      let r = apply-ops(
        mkRBT-renderer(bbf),
        force_show("LL", "R") + any_a("L") + double_black_subtree("LR"),
      )
      starling.last(starling.render(r))
    },
  ),
)

== Black-Height Violations

#align(center, cetz-canvas({
  import cetz.draw: *

  let ex_bbff = bnode(7, rnode(6, bleaf(1), none), bnode(
    17,
    rleaf(11),
    rleaf(18),
  ))

  let bbff_r = apply-ops(
    mkRBT-renderer(ex_bbff),
    attention("")
      + force_show("LR")
      + null("LR")
      + commit(
        "After deleting 7, showing null as the left child of 6.",
      )
      + double_black("LR")
      + disp_black(""),
  )
  starling.draw-tree(ex_bbff, bbff_r.snapshots.last())
  (pause,)
  on-layer(1, {
    line((7, 0), (2.3, -3.5), mark: (end: ">"), stroke: color.orange + 3pt)
    content((7, 0), box(
      text(size: 0.75em)[How to add another black node?],
      width: 1.5in,
      fill: color.orange,
      inset: 6pt,
      radius: 5%,
    ))
  })
}))

== Marked Node Cases

#align(center, {
  import fletcher.shapes: rect
  fletcher-diagram(
    spacing: (18mm, 5mm),
    node-stroke: 1pt,
    node((0, 0), [Start], name: <s>),
    pause,
    node((2, -1), [Red \ Sibling], shape: rect, name: <rs>),
    node((2, 1), [Black \ Sibling], shape: rect, name: <bs>),
    edge(<s>, <rs>, "-|>"),
    edge(<s>, <bs>, "-|>"),
    pause,
    node((4, 0), [All Black \ Nieces], name: <bn>),
    node((4, 2), [Some Red \ Nieces], name: <rn>),
    edge(<bs>, <bn>, "-|>"),
    edge(<bs>, <rn>, "-|>"),
  )
})

== Case 1: Black Sibling, Red Niece

If the sibling of the marked node is #black_n and has a #red_n child:
- Only perform the first step if B, D and C are zig-zag.

#figure(
  box(
    image(
      "02-rbt-delete.svg",
      height: 6.5in,
      alt: "Diagram showing how to correct double black nodes with a black sibling and red nice.",
    ),
    height: 3in,
    clip: true,
  ),
)

== Case 2: Black Sibling, Black Niece

If the sibling of the marked node is #black_n, and the sibling's children are
all #black_n (or null):

#figure(
  cetz-canvas({
    import cetz.draw: *
    content((0, 0), box(
      image(
        "02-rbt-delete.svg",
        alt: "Diagram showing how to correct double black nodes with a black sibling and red nice.",
      ),
      inset: (top: -5.25in, bottom: -3in),
      clip: true,
    ))
    (pause,)
    line((0, 2), (5, 2.5), stroke: color.orange + 3pt, mark: (end: ">"))
    content((-1, 3), box(
      width: 2.5in,
      fill: color.orange,
      inset: 6pt,
      radius: 5%,
      text(
        size: 0.75em,
      )[If B was originally red, stop. Otherwise *mark B* and continue resolving
        the marked node.],
    ))
  }),
)

== Case 3: Red Sibling

If the sibling of the marked node is #red_n:
+ Rotate & color swap the parent and sibling
+ Continue to resolve the marked node

#figure(box(
  image(
    "02-rbt-delete.svg",
    alt: "Diagram showing how to correct double black nodes with a red sibling.",
  ),
  inset: (top: -8.25in),
  clip: true,
))

== Case 4: Root

If the marked node is the root, remove the mark.

#let mnr = bnode(2, bleaf(1, label: [A]), rleaf(3, label: [C]), label: [B])
#figure(stack(
  dir: ltr,
  spacing: 1cm,
  cetz.canvas({
    import cetz.draw: *

    starling.draw-tree(mnr, mkRBT-renderer(mnr).snapshots.at(0))
    let root = starling.anchor("")
    mark(
      (rel: (0, 1), to: root),
      root,
      anchor: "center",
      symbol: "o",
      fill: black,
      scale: 2,
    )
  }),
  pause,
  arrow,
  pause,
  starling.last(rbt.display(mnr, bits: true)),
))

== Marked Node Cases

#align(center, image(
  "02-rbt-delete.svg",
  alt: "Complete summary of double black node corrections.",
  height: 4.2in,
))

== AVL Trees

#item-by-item[
  - *Adelson-Velsky and Landis (AVL) Trees* are self-balancing Binary Search
    Trees which use rotations to maintain balance.
  - After each insertion / deletion, perform some *rotations* to *maintain the
    balance* of the tree.
  - Rather than colors, track an explicit *balance factor*.
]

#let bf = "bf"
#let hh = "height"
#let l_st = math.equation($Delta_ell^v$, alt: "Left subtree")
#let r_st = math.equation($Delta_r^v$, alt: "Right subtree")

== Balance Factor

#definition-box[Balance Factor][
  At a node _v_, the *balance factor* is the height of the left subtree minus
  the height of the right subtree.

  #math.equation(
    $ bf (v) = hh (Delta_ell^v) - hh (Delta_r^v) $,
    block: true,
    alt: "balance factor of v equals height of left subtree
  minus height of right subtree",
  )
]

- Where #math.equation($hh (Delta_ell^v)$, alt: "height of left subtree") and
  #math.equation($hh (Delta_r^v)$, alt: "height of right subtree") give the
  height of the left and right subtrees of _v_ respectively.

== Balance Factor
#v(-1cm)
#definition-box[Balanced Node][
  A node _v_ is *balanced* if #math.equation(
    $abs(bf (v)) < 2$,
    alt: "absolute value of the
  balance factor of v is less than 2",
  ).
]
#pause
- #math.equation($bf (v) < -1$, alt: "A balance factor less than negative one")
  indicates that #l_st is smaller than #r_st.
- #math.equation($bf (v) > 1$, alt: "A balance factor grater than one")
  indicates that #l_st is taller than #r_st.
#pause
#definition-box[AVL Tree][
  An AVL Tree is a binary search tree where every node is *balanced*.
]

== AVL Example
#v(-1cm)
#let avl_ex = avl.new(10, 2, 16, 1, 5, 19, 7)
#starling.last(avl.display(avl_ex, heights: true, factors: true))
- Balance factor next to node
- Edges labeled with height of subtree rooted at the child.

== AVL Example
#let height(node) = if node == none {
  0
} else {
  1 + calc.max(height(node.left), height(node.right))
}
#let avln(value, left, right, label: auto) = avl.node(
  value,
  left,
  right,
  height: 1 + calc.max(height(left), height(right)),
  label: label,
)
#let avll(value, label: auto) = avl.leaf(
  value,
  height: 1,
  label: label,
)

#{
  let t = avln(
    40,
    avln(10, avln(3, none, none), none),
    avln(30, none, avln(44, avll(32), none)),
  )
  starling.last(avl.display(t, heights: true, factors: true))
}
#pause
- Balance factor of node 30 is -2, so the tree is unbalanced!


== Insertion Operation

+ Start with a *valid AVL tree*.
+ Perform a *BST insertion*.
+ *Update* the balance factors from the inserted node to the root.
  - For each unbalanced node from the inserted one til the root:
    - *Rotate* to repair balance factor.
    - *Update* balance factors of rotated nodes.

== Insertion Operation

- *Update* the balance factors from the inserted node to the root.
#pause
#v(-1.5cm)
#{
  let t = bst.new((2, "R"), (1, ""), (3, "⋯"), (5, ""), (4, "In"), (7, ""))
  let r = starling.apply-ops(bst.renderer(t, sticky: true), (
    style-node("R", stroke: color.white),
    style-node(
      "",
      stroke: green.B + 2pt,
      text-fill: green.B,
    ),
    style-node(
      "RR",
      stroke: green.B + 2pt,
      text-fill: green.B,
    ),
    style-node(
      "RRL",
      stroke: green.B + 2pt,
      text-fill: green.B,
    ),
    style-edge(
      "R",
      stroke: green.B + 2pt,
    ),
    style-edge(
      "RR",
      stroke: green.B + 2pt,
    ),
    style-edge(
      "RRL",
      stroke: green.B + 2pt,
    ),
    style-edge(
      "LL",
      force-show: true,
    ),
    style-edge(
      "LR",
      force-show: true,
    ),
    style-edge(
      "RRRR",
      force-show: true,
    ),
    style-edge(
      "RRRL",
      force-show: true,
    ),
  ))
  starling.last(starling.render(r))
}

== Rebalance

- If the grandchild is an _inner child_, *rotate* the grandchild and child on
  the heavy side.

#let unbalanced(path) = style-node(
  path,
  stroke: red.B,
  fill: red.B,
  text-fill: white,
)
#let descendant(path) = (
  style-node(
    path,
    stroke: color.orange,
    fill: color.orange,
    text-fill: white,
  )
    + style-edge(path, stroke: color.orange)
)
#let force_show(..paths) = (
  paths.pos().map(p => style-edge(p, force-show: true))
)
#align(center, stack(
  dir: ltr,
  spacing: 1em,
  {
    let t = bst.new((1, ""), (2, "U"), (4, "C"), (3, "G"))
    let r = starling.apply-ops(
      bst.renderer(t, sticky: true),
      (
        unbalanced("R")
          + descendant("RR")
          + descendant("RRL")
          + force_show("L", "RL", "RRR", "RRLR", "RRLL")
      ),
    )
    scale(x: 87%, y: 87%, reflow: true, starling.last(starling.render(r)))
  },
  pause,
  align(horizon, cetz-canvas({
    import cetz.draw: *
    line((0, 0), (3, 0), stroke: 15pt, mark: (end: ">", fill: black))
  })),
  pause,
  {
    let t = bst.new((1, ""), (2, "U"), (3, "G"), (4, "C"))
    let r = starling.apply-ops(
      bst.renderer(t, sticky: true),
      (
        unbalanced("R")
          + descendant("RR")
          + descendant("RRR")
          + force_show("L", "RL", "RRR", "RRRR", "RRRL")
      ),
    )
    scale(x: 87%, y: 87%, reflow: true, starling.last(starling.render(r)))
  },
))

== Rebalance

- *Rotate* the unbalanced node and its child node on the heavy side.

#align(center, stack(
  dir: ltr,
  spacing: 1em,
  {
    let t = bst.new((1, ""), (2, "U"), (3, "C"), (4, "G"))
    let r = starling.apply-ops(
      bst.renderer(t, sticky: true),
      (
        unbalanced("R")
          + descendant("RR")
          + descendant("RRR")
          + force_show("L", "RL", "RRR", "RRL", "RRRR", "RRRL")
      ),
    )
    scale(x: 87%, y: 87%, reflow: true, starling.last(starling.render(r)))
  },
  pause,
  align(horizon, cetz-canvas({
    import cetz.draw: *
    line((0, 0), (3, 0), stroke: 15pt, mark: (end: ">", fill: black))
  })),
  pause,
  {
    let t = bst.new((1, ""), (3, "C"), (2, "U"), (4, "G"))
    let r = starling.apply-ops(
      bst.renderer(t, sticky: true),
      (
        unbalanced("RL")
          + descendant("R")
          + descendant("RR")
          + force_show("L", "RLL", "RRR", "RRL", "RLR")
      ),
    )
    scale(x: 87%, y: 87%, reflow: true, starling.last(starling.render(r)))
  },
))

== B-Tree Definition

- *B-Trees* are self-balancing trees where each node may have multiple children
  and / or multiple values.
- B-Trees are not binary search trees, but do follow an order property.

// Parse a list of "value-or-(value, label)" args into parallel
// keys/labels arrays and build the node. Mirrors `parse` in b24.typ.
#let _node(vals, children) = {
  let ps = vals.map(x => if type(x) == array {
    assert(
      x.len() == 2,
      message: "expected (value, label) 2-tuple, got " + repr(x),
    )
    (value: x.at(0), label: x.at(1))
  } else {
    (value: x, label: auto)
  })
  b24.node(
    ps.map(p => (p.value, p.label)),
    ..children,
  )
}

#let n2(value, c1, c2) = _node((value,), (c1, c2))
#let l2(v) = _node((v,), ())
#let n3(v1, v2, c1, c2, c3) = _node((v1, v2), (c1, c2, c3))
#let l3(v1, v2) = _node((v1, v2), ())
#let n4(v1, v2, v3, c1, c2, c3, c4) = _node((v1, v2, v3), (c1, c2, c3, c4))
#let l4(v1, v2, v3) = _node((v1, v2, v3), ())

#pause
#{
  let t = n3(8, 13, l3(1, 3), l2(12), l4(15, 16, 18))
  starling.last(b24.display(t))
}

== B-Tree Properties

- An internal node with *n values* has *n + 1 children*.
#pause
- All *leaf* nodes must be at the same level / depth.
#pause
- *Ordering Properties* #pause
  - The values in *each node* must be *sorted*. #pause
  - All values in *subtrees* left of a value X must be smaller than X, and all
    values in *subtrees* right of X must be larger than X.

== Internal Node Types

#v(-1.5cm)
#text(0.9em, grid(
  align: center + horizon,
  inset: 10pt,
  columns: 3,
  [2 - Node],
  {
    let t = n2(
      (2, math.equation($v$, alt: "v")),
      l2((
        1,
        math.equation(
          $Delta <= v$,
          alt: "Subtree's values are less than or equal to v",
        ),
      )),
      l2((
        3,
        math.equation(
          $v < Delta$,
          alt: "Subtree's values are greater than v",
        ),
      )),
    )
    let r = starling.apply-ops(
      b24.renderer(t, sticky: true),
      (
        style-node("0", stroke: white),
        style-node("1", stroke: white),
      ),
    )
    starling.last(starling.render(r))
  },
  [1 value, 2 children],

  [3 - Node],
  {
    let t = n3(
      (2, math.equation($v_1$, alt: "v sub 1")),
      (4, math.equation($v_2$, alt: "v sub 2")),
      l2((
        1,
        math.equation(
          $Delta <= v_1$,
          alt: "Subtree's values are less than or equal to v sub 1",
        ),
      )),
      l2((
        1,
        math.equation(
          $v_1 < Delta <= v_2$,
          alt: "Subtree's values are greater than v sub 1 and less than or equal to v sub 2",
        ),
      )),
      l2((
        3,
        math.equation(
          $v_2 < Delta$,
          alt: "Subtree's values are greater than v sub 2",
        ),
      )),
    )
    let r = starling.apply-ops(
      b24.renderer(t, sticky: true),
      (
        style-node("0", stroke: white),
        style-node("1", stroke: white),
        style-node("2", stroke: white),
      ),
    )
    starling.last(starling.render(r))
  },
  [2 values, 3 children],

  [4 - Node],
  {
    let t = n4(
      (2, math.equation($v_1$, alt: "v sub 1")),
      (4, math.equation($v_2$, alt: "v sub 2")),
      (6, math.equation($v_3$, alt: "v sub 3")),
      l2((
        1,
        math.equation(
          $Delta <= v_1$,
          alt: "Subtree's values are less than or equal to v sub 1",
        ),
      )),
      l2((
        3,
        math.equation(
          $v_1 < Delta <= v_2$,
          alt: "Subtree's values are greater than v sub 1 and less than or equal to v sub 2",
        ),
      )),
      l2((
        5,
        math.equation(
          $v_2 < Delta <= v_3$,
          alt: "Subtree's values are greater than v sub 2 and less than or equal to v sub 3",
        ),
      )),
      l2((
        7,
        math.equation(
          $v_2 < Delta$,
          alt: "Subtree's values are greater than v sub 2",
        ),
      )),
    )
    let r = starling.apply-ops(
      b24.renderer(t, sticky: true),
      (
        style-node("0", stroke: white),
        style-node("1", stroke: white),
        style-node("2", stroke: white),
        style-node("3", stroke: white),
      ),
    )
    scale(x: 90%, y: 90%, reflow: true, starling.last(starling.render(r)))
  },
  [3 values, 4 children],
))

== B-Tree Insertion

- Insertion in a B-Tree is always done in a leaf node.
- When a new level is needed, the tree grows at the root level.
- *Preemptive splitting* is when we split full nodes along the search path
  during insertion.

== B-Tree Insertion Algorithm

+ Find where the value should go using the search algorithm.
  + For each "full" node along the way (including leaves), *preemptively split*
    the node, and continue the search at the new parent.
  + Don't split the new parent, even if it's full.
+ *Insert* new value *into leaf* at the end.

== Preemptive Splitting

#align(center + horizon, stack(
  dir: ltr,
  spacing: 1em,
  {
    let t = n3(7, 11, l2((5, [])), l2((10, [])), n4(
      14,
      17,
      18,
      l2((12, [A])),
      l2((15, [B])),
      l2((17, [C])),
      l2((20, [D])),
    ))
    let r = starling.apply-ops(
      b24.renderer(t, sticky: true),
      (
        style-node("0", stroke: white),
        style-node("1", stroke: white),
        style-node("20", shape: "triangle", label: "A"),
        style-node("21", shape: "triangle", label: "B"),
        style-node("22", shape: "triangle", label: "C"),
        style-node("23", shape: "triangle", label: "D"),
      ),
    )
    starling.last(starling.render(r))
  },
  cetz-canvas({
    import cetz.draw: *
    line((0, 0), (3, 0), stroke: 10pt, mark: (end: ">", fill: black, scale: 2))
    content((1.5, 1), [Split])
  }),
  {
    let t = n4(
      7,
      11,
      17,
      l2((5, [])),
      l2((10, [])),
      n2(
        14,
        l2(12),
        l2(15),
      ),
      n2(
        18,
        l2(17),
        l2(20),
      ),
    )
    let r = starling.apply-ops(
      b24.renderer(t, sticky: true),
      (
        style-node("0", stroke: white),
        style-node("1", stroke: white),
        style-node("20", shape: "triangle", label: "A"),
        style-node("21", shape: "triangle", label: "B"),
        style-node("30", shape: "triangle", label: "C"),
        style-node("31", shape: "triangle", label: "D"),
      ),
    )
    starling.last(starling.render(r))
  },
))

#pause
- Continue insertion search from parent node.

#focus-slide(
  theme: "mandarine",
  icon: nf-icon("file_pen"),
  [Practice Exam],
)

