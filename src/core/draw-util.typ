// Drawing utilities shared by every backend in `draw/`.
//
// Anything a second backend would otherwise copy belongs here: the anchor
// naming scheme, stroke and text-color derivation, the halo behind small
// in-canvas labels, and the "fit" cell-sizing rule that the three table
// backends (hash map, array, skip list) all need.

// ===================================================================
// Anchors
// ===================================================================
//
// One scheme for every structure. A backend names its cetz elements
// `anchor(key)`, so a caller who knows an element's snapshot key can point
// at it without knowing which backend drew it:
//
//   tree     ""       -> "el-root"      "LR"      -> "el-LR"
//   graph    "A"      -> "el-A"         "u->v"    -> "el-u--v"
//   hashmap  "c3"     -> "el-c3"        "c3:1"    -> "el-c3-1"
//   array    "count:5"-> "el-count-5"
//   skiplist "b2:0"   -> "el-b2-0"
//   b24      "01#1"   -> "el-01.key-1"  (compartment sub-anchor)
//
// The usual cetz compass sub-anchors work on top: `anchor("c3") + ".north"`.

// Every character outside this class becomes "-", so a key is always a legal
// cetz element name.
#let _ANCHOR-SAFE = regex("[^a-zA-Z0-9_-]")

/// The cetz element name for a snapshot key.
///
/// A `"#<int>"` suffix addresses one compartment of a multi-key node (B24)
/// and becomes a cetz sub-anchor: `anchor("01#1")` is `"el-01.key-1"`. Pass
/// `canvas:` to qualify the name with the enclosing group's name, which is
/// what a backend's `name:` argument creates.
#let anchor(key, canvas: none) = {
  let parts = key.split("#")
  let base = parts.first()
  let sub = if parts.len() > 1 { ".key-" + parts.at(1) } else { "" }
  let cleaned = if base == "" { "root" } else { base.replace(_ANCHOR-SAFE, "-") }
  let name = "el-" + cleaned + sub
  if canvas == none { name } else { canvas + "." + name }
}

// ===================================================================
// Color helpers
// ===================================================================

/// The paint of a stroke spec — used to fill an arrowhead so it matches its
/// line. Accepts a color, dict, or stroke; falls back to black for `auto` /
/// `none` or a stroke with no explicit paint.
#let stroke-paint(s) = {
  if s == auto or s == none { return black }
  let st = stroke(s)
  if st.paint == auto { black } else { st.paint }
}

/// A readable text fill for a given background, chosen from the background's
/// oklab lightness. Keeps a label legible across a gradient palette or a
/// component-colored node.
#let text-fill-for(bg) = {
  let l = bg.oklab().components().first()
  if l < 60% { white } else { black }
}

/// A de-emphasized version of a theme color, for the parts of a drawing that
/// should read second: an absent adjacency-matrix cell, an empty auxiliary
/// structure, a rejected element's label.
#let muted(c) = c.transparentize(55%)

/// A small piece of content on a filled halo, so index labels and edge tags
/// stay legible over any connector running beneath them. `theme` is the full
/// resolved theme; the halo uses `theme.render.note-bg`.
#let haloed(draw, pos, body, theme, anchor: "center") = draw.content(
  pos,
  anchor: anchor,
  frame: "rect",
  fill: theme.render.note-bg,
  stroke: none,
  padding: 0.05,
  body,
)

// ===================================================================
// "Fit" cell sizing
// ===================================================================
//
// The three table backends draw boxes that must not clip their labels but
// must also not jitter frame to frame. Both requirements are one rule:
// measure a *superset* of every label the animation will ever show, and size
// every frame's boxes to that.
//
// `cell-width` selects the mode:
//
//   auto      the historical fixed footprint. Never measures, so it is safe
//             outside a layout context (the raw `draw-*` path).
//   "fit"     grow to fit the widest and tallest body, floored at the fixed
//             footprint so short numeric tables are unchanged. Calls
//             `measure`, so it REQUIRES a layout context — which the display
//             methods always have, being wrapped by the `slides.typ`
//             helpers' `context`.
//   a number  pin the width exactly (no measuring).

/// Padding per side, in cetz units, between a label and its box edge when
/// sizing to fit.
#let PAD-X = 0.22
#let PAD-Y = 0.15

/// The largest rendered width and height (in cetz units) over a set of
/// cells, as `(w, h)`. `body-fn(cell)` builds the cell's content; cells whose
/// body is `none` are skipped. Returns `(w: 0, h: 0)` when nothing is
/// measurable.
///
/// `measure-cells`, when non-empty, is measured *instead of* `cells`. An
/// animation passes the global set of bodies across all its frames here, so
/// every frame measures the same superset and the canvas never jumps as a
/// running count grows wider than the widest value.
#let measure-max(cells, body-fn, measure-cells: ()) = {
  let subjects = if measure-cells.len() > 0 { measure-cells } else { cells }
  let w = 0
  let h = 0
  for cell in subjects {
    let body = body-fn(cell)
    if body != none {
      let d = measure(body)
      w = calc.max(w, d.width / 1cm)
      h = calc.max(h, d.height / 1cm)
    }
  }
  (w: w, h: h)
}

/// Resolve a box footprint for one render, as `(w, h)` in cetz units.
///
/// The shared implementation behind the hash-map, array, and skip-list
/// backends' cell sizing — see the mode table above. `floor-w` / `floor-h`
/// are the fixed footprint each backend falls back to (and never shrinks
/// below); `pad-x` / `pad-y` are added on each side of a measured body.
#let resolve-dims(
  cells,
  body-fn,
  cell-width,
  floor-w: 0,
  floor-h: 0,
  pad-x: PAD-X,
  pad-y: PAD-Y,
  measure-cells: (),
) = {
  if cell-width == "fit" {
    let m = measure-max(cells, body-fn, measure-cells: measure-cells)
    (
      w: calc.max(floor-w, m.w + 2 * pad-x),
      h: calc.max(floor-h, m.h + 2 * pad-y),
    )
  } else if cell-width != auto {
    (w: cell-width, h: floor-h)
  } else {
    (w: floor-w, h: floor-h)
  }
}
