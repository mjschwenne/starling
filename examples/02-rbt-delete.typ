#import "/src/lib.typ" as starling
#import starling: apply-snapshot, rbt, style-node, styles
#import "@preview/cetz:0.5.2"

#set page(width: auto, height: auto, margin: 2pt)
#set text(size: 24pt, font: "Inria Sans")

// The seven hand-built trees of the delete fix-up. These are textbook case
// shapes, not anything `rbt.delete` would hand back mid-operation, so the
// colours and the letter labels are set explicitly.

#let rbt_rni = rbt.black(
  2,
  rbt.black(1, label: [A]),
  rbt.black(
    5,
    rbt.red(4, rbt.black(3, label: [C]), none, label: [D]),
    none,
    label: [E],
  ),
  label: [B],
)

#let rbt_rno = rbt.black(
  2,
  rbt.black(1, label: [A]),
  rbt.black(4, rbt.black(3, label: [C]), rbt.red(5, label: [E]), label: [D]),
  label: [B],
)

#let rbt_rnf = rbt.black(
  4,
  rbt.black(2, rbt.black(1, label: [A]), rbt.black(3, label: [C]), label: [B]),
  rbt.black(5, label: [E]),
  label: [D],
)

#let rbt_ba = rbt.red(
  2,
  rbt.black(1, label: [A]),
  rbt.black(4, rbt.black(3, label: [C]), rbt.black(5, label: [E]), label: [D]),
  label: [B],
)

#let rbt_baf = rbt.black(
  2,
  rbt.black(1, label: [A]),
  rbt.red(4, rbt.black(3, label: [C]), rbt.black(5, label: [E]), label: [D]),
  label: [B],
)

#let rbt_ra = rbt.black(
  2,
  rbt.black(1, label: [A]),
  rbt.red(4, rbt.black(3, label: [C]), rbt.black(5, label: [E]), label: [D]),
  label: [B],
)

#let rbt_raf = rbt.black(
  4,
  rbt.red(2, rbt.black(1, label: [A]), rbt.black(3, label: [C]), label: [B]),
  rbt.black(5, label: [E]),
  label: [D],
)

// Stand-ins for "some subtree of the right black height": a letter tag and
// a fill deliberately outside the red-black palette, so nobody reads X or Y
// as a real node.
#let any_a(key) = style-node(key, tag: [X], fill: blue, stroke: blue)
#let any_b(key) = style-node(key, tag: [Y], fill: purple, stroke: purple)

// "Either colour" — the node whose colour the case leaves unconstrained.
#let either(key) = {
  let grad = gradient.linear(
    (red, 0%),
    (red, 42%),
    (black, 75%),
    (black, 100%),
    angle: 0deg,
  )
  style-node(key, tag: [0 or 1], stroke: grad, fill: grad)
}

// "Black, or double-black" — a height bit the fix-up has yet to settle.
#let maybe_double(key) = style-node(key, tag: [1 or 2])

// One static snapshot per tree: the red-black palette with black-height
// bits, stub edges forced into the nil slots named by `nils`, and whatever
// case-specific marking the diagram calls for.
#let snap(tree, nils: (), ..ops) = apply-snapshot(
  rbt.renderer(tree, bits: true).snapshots.first(),
  styles.force-show(..nils) + ops.pos(),
)

#let rni_s = snap(
  rbt_rni,
  nils: ("LL", "LR", "RLR", "RL", "RLLL", "RLLR", "RR"),
  rbt.double-black("L"),
  any_a(""),
)

#let rno_s = snap(
  rbt_rno,
  nils: ("LL", "LR", "RLL", "RLR", "RRL", "RRR"),
  rbt.double-black("L"),
  any_a(""),
  any_b("RL"),
)

#let rnf_s = snap(
  rbt_rnf,
  nils: ("LLL", "LLR", "LRL", "LRR", "RL", "RR"),
  any_a(""),
  any_b("LR"),
)

#let ba_s = snap(
  rbt_ba,
  nils: ("LL", "LR", "RLL", "RLR", "RRL", "RRR"),
  rbt.double-black("L"),
  either(""),
)

#let baf_s = snap(
  rbt_baf,
  nils: ("LL", "LR", "RLL", "RLR", "RRL", "RRR"),
  maybe_double(""),
)

#let ra_s = snap(
  rbt_ra,
  nils: ("LL", "LR", "RLL", "RLR", "RRL", "RRR"),
  rbt.double-black("L"),
)

#let raf_s = snap(
  rbt_raf,
  nils: ("LLL", "LLR", "LRL", "LRR", "RL", "RR"),
  rbt.double-black("LL"),
)

#cetz.canvas({
  import cetz.draw: *

  starling.draw-tree(rbt_rni, rni_s, name: "rni", grow: 0.5, spread: 0.1)
  let rni_root = starling.anchor("", canvas: "rni")
  line(rni_root, (rel: (0, 1), to: rni_root))
  line((0, -5), (-2, -7), stroke: 20pt + orange, mark: (end: ">"))
  content((-2.5, -4), align(center, text(
    fill: orange,
  )[Rotate & \ Color Swap]))

  set-origin((-7, -7))
  starling.draw-tree(rbt_rno, rno_s, name: "rno", grow: 0.5, spread: 0.1)
  let rno_root = starling.anchor("", canvas: "rno")
  line(rno_root, (rel: (0, 1), to: rno_root))
  line((9, -3), (12, -3), stroke: 20pt + orange, mark: (end: ">"))
  content((10.5, -1), align(center, text(
    fill: orange,
  )[Rotate, \ Color Swap, \ Recolor]))

  set-origin((12, 0))
  starling.draw-tree(rbt_rnf, rnf_s, name: "rnf", grow: 0.5, spread: 0.1)
  let rnf_root = starling.anchor("", canvas: "rnf")
  line(rnf_root, (rel: (0, 1), to: rnf_root))

  set-origin((-12, -7))
  starling.draw-tree(rbt_ba, ba_s, name: "ba", grow: 0.5, spread: 0.1)
  let ba_root = starling.anchor("", canvas: "ba")
  line(ba_root, (rel: (0, 1), to: ba_root))
  line((9, -3), (12, -3), stroke: 20pt + orange, mark: (end: ">"))
  content((10.5, -2), align(center, text(fill: orange)[Recolor]))

  set-origin((12, 0))
  starling.draw-tree(rbt_baf, baf_s, name: "baf", grow: 0.5, spread: 0.1)
  let baf_root = starling.anchor("", canvas: "baf")
  let baf_grad = gradient.linear(
    (white, 0%),
    (white, 44%),
    (black, 44%),
    (black, 100%),
    angle: 0deg,
  )
  line(
    baf_root,
    (rel: (0, 1.3), to: baf_root),
    mark: (
      start: "o",
      fill: baf_grad,
      stroke: baf_grad,
      scale: 2,
      offset: 0.6,
    ),
  )
  content((6, 0), align(center, text(fill: orange)[#sym.arrow.t Check]))

  set-origin((-12, -7))
  starling.draw-tree(rbt_ra, ra_s, name: "ra", grow: 0.5, spread: 0.1)
  let ra_root = starling.anchor("", canvas: "ra")
  line(ra_root, (rel: (0, 1), to: ra_root))
  line((9, -3), (12, -3), stroke: 20pt + orange, mark: (end: ">"))
  content((10.5, -1), align(center, text(
    fill: orange,
  )[Rotate & \ Color Swap]))

  set-origin((12, 0))
  starling.draw-tree(rbt_raf, raf_s, name: "raf", grow: 0.5, spread: 0.1)
  let raf_root = starling.anchor("", canvas: "raf")
  line(raf_root, (rel: (0, 1), to: raf_root))
  content((3, -5.25), align(center, text(fill: orange)[#sym.arrow.t Check]))
})
