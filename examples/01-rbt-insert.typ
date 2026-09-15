#import "/src/lib.typ" as starling
#import starling: apply-snapshot, rbt, styles
#import "@preview/cetz:0.5.2"

#set page(width: auto, height: auto, margin: 2pt)
#set text(size: 24pt, font: "Inria Sans")

// The five hand-built trees of the insert fix-up, each a textbook shape
// rather than anything `rbt.insert` would produce — hence the explicit
// colours and the letter labels standing in for arbitrary keys.

#let rbt_zz = rbt.black(
  3,
  rbt.red(1, none, rbt.red(2, label: [B]), label: [A]),
  rbt.black(4, label: [D]),
  label: [C],
)

#let rbt_ss = rbt.black(
  3,
  rbt.red(2, rbt.red(1, label: [A]), none, label: [B]),
  rbt.black(4, label: [D]),
  label: [C],
)

#let rbt_baf = rbt.black(
  2,
  rbt.red(1, label: [A]),
  rbt.red(3, none, rbt.black(4, label: [D]), label: [C]),
  label: [B],
)

#let rbt_ra = rbt.black(
  3,
  rbt.red(2, rbt.red(1, label: [A]), none, label: [B]),
  rbt.red(4, label: [D]),
  label: [C],
)

#let rbt_raf = rbt.red(
  3,
  rbt.black(2, rbt.red(1, label: [A]), none, label: [B]),
  rbt.black(4, label: [D]),
  label: [C],
)

// One static snapshot per tree: the red-black palette with black-height
// bits, plus a stub edge forced into each nil slot so every leaf shows the
// two prongs the handout draws.
#let snap(tree, ..nils) = apply-snapshot(
  rbt.renderer(tree, bits: true).snapshots.first(),
  styles.force-show(..nils.pos()),
)

#let zz_s = snap(rbt_zz, "LL", "LRL", "LRR", "RL", "RR")
#let ss_s = snap(rbt_ss, "LLL", "LLR", "LR", "RL", "RR")
#let baf_s = snap(rbt_baf, "LL", "LR", "RL", "RRL", "RRR")
#let ra_s = snap(rbt_ra, "LLL", "LLR", "LR", "RL", "RR")
#let raf_s = snap(rbt_raf, "LLL", "LLR", "LR", "RL", "RR")

#cetz.canvas({
  import cetz.draw: *

  starling.draw-tree(rbt_zz, zz_s, name: "zz", grow: 0.5, spread: 0.1)
  let zz_root = starling.anchor("", canvas: "zz")
  line(zz_root, (rel: (0, 1), to: zz_root))
  line((0, -4), (-2, -6), stroke: 20pt + orange, mark: (end: ">"))
  content((-2, -4), text(fill: orange)[Rotate])

  set-origin((-6, -7))
  starling.draw-tree(rbt_ss, ss_s, name: "ss", grow: 0.5, spread: 0.1)
  let ss_root = starling.anchor("", canvas: "ss")
  line(ss_root, (rel: (0, 1), to: ss_root))
  line((7, -2), (10, -2), stroke: 20pt + orange, mark: (end: ">"))
  content((8.5, 0), align(center, text(fill: orange)[Rotate & \ Color Swap]))

  set-origin((10, 0))
  starling.draw-tree(rbt_baf, baf_s, name: "baf", grow: 0.5, spread: 0.1)
  let baf_root = starling.anchor("", canvas: "baf")
  line(baf_root, (rel: (0, 1), to: baf_root))

  set-origin((-10, -6))
  starling.draw-tree(rbt_ra, ra_s, name: "ra", grow: 0.5, spread: 0.1)
  let ra_root = starling.anchor("", canvas: "ra")
  line(ra_root, (rel: (0, 1), to: ra_root))
  line((7, -2), (10, -2), stroke: 20pt + orange, mark: (end: ">"))
  content((8.5, -1), align(center, text(fill: orange)[Recolor]))

  set-origin((10, 0))
  starling.draw-tree(rbt_raf, raf_s, name: "raf", grow: 0.5, spread: 0.1)
  let raf_root = starling.anchor("", canvas: "raf")
  line(raf_root, (rel: (0, 1), to: raf_root))
  content((6, 0), align(center, text(fill: orange)[#sym.arrow.t Check]))
})
