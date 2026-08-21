// Style vocabulary — the node/edge style key allowlists, the merge rules
// that combine style layers, and the theme-reference marker that lets a
// style built ahead of time follow whatever theme is active when it is
// finally drawn.
//
// Nothing here knows what a structure is. A "style" is a plain dict whose
// keys come from one of the two allowlists below; the draw backends decide
// which keys they honor.

// ===================================================================
// Assertion helpers (shared by every module's constructors)
// ===================================================================

/// Panic unless every key of `dict` appears in `allowed`. `who` names the
/// caller in the message (e.g. `"node style"`, `"skiplist.new"`).
#let assert-keys(dict, allowed, who) = {
  for k in dict.keys() {
    if not allowed.contains(k) {
      panic(
        who + ": unknown key '" + k + "'. Valid keys: " + allowed.join(", ") + ".",
      )
    }
  }
}

/// Panic unless `value` is one of `options`. `who` names the caller.
#let assert-any-of(value, options, who) = {
  if not options.contains(value) {
    panic(
      who
        + ": expected one of "
        + options.map(o => repr(o)).join(", ")
        + ", got "
        + repr(value)
        + ".",
    )
  }
}

// ===================================================================
// Key allowlists
// ===================================================================

/// The recognised node-style keys.
///
/// Honored by every backend: `fill`, `stroke`, `text-fill`, `note`,
/// `note-fill`, `hide`, `ghost`, `tag`, `label`.
///
/// Tree backend only: `shape` (`"circle"` | `"triangle"` | `"rectangle"` |
/// `"btree-node"`), `materialize` (draw an otherwise-phantom slot as a real
/// node), `key-styles` (per-compartment styling for a `"btree-node"`, an
/// array of dicts merged index-wise across sticky frames).
///
/// Graph backend only — node geometry, all in cetz units: `r` (circle
/// radius), `rx`/`ry` (ellipse/rectangle half-extents), `autosize` (fit the
/// node to its label via `measure`), `pad-x`/`pad-y` (padding for that fit).
/// The graph backend also honors `shape` with its own smaller dispatch
/// (`"circle"` | `"ellipse"` | `"rectangle"`/`"square"`).
///
/// `ghost: true` is "invisible but space-reserving": the element still
/// contributes its exact normal footprint to the canvas bounds and still
/// emits its anchors, but nothing is painted. Contrast `hide: true`, which
/// drops the element from layout entirely (and so shifts everything around
/// it).
#let node-style-keys = (
  "fill",
  "stroke",
  "text-fill",
  "note",
  "note-fill",
  "hide",
  "ghost",
  "shape",
  "tag",
  "label",
  "materialize",
  "key-styles",
  "r",
  "rx",
  "ry",
  "autosize",
  "pad-x",
  "pad-y",
)

/// The recognised edge-style keys.
///
/// Honored by every backend: `stroke`, `note`, `note-fill`, `tag`, `mark`,
/// `hide`.
///
/// Tree backend only: `parent-anchor` / `child-anchor` (a cetz anchor name
/// overriding the default fractional-distance endpoint — how an edge lands
/// flush on a non-circular shape, e.g. `child-anchor: "north"` for a
/// triangle's apex) and `force-show` (draw an edge even when one endpoint
/// is a phantom).
///
/// Graph backend only: `bend` (cetz units; curve the edge into an arc whose
/// control point is the straight midpoint pushed perpendicular by this
/// amount, positive = left of the u→v direction) and `label-offset` (signed
/// cetz units; seat a straight edge's weight/label off the line, sign picks
/// the side).
///
/// `tag` is a small persistent annotation near the edge (drawn in the render
/// theme's `edge-tag-fill`) — AVL subtree heights, trie letters, graph edge
/// weights. `note` is the transient gold operation slot.
#let edge-style-keys = (
  "stroke",
  "note",
  "note-fill",
  "tag",
  "mark",
  "hide",
  "parent-anchor",
  "child-anchor",
  "force-show",
  "bend",
  "label-offset",
)

/// Panic unless `d` is a valid node-style dict.
#let assert-node-style(d, who: "node style") = assert-keys(d, node-style-keys, who)

/// Panic unless `d` is a valid edge-style dict.
#let assert-edge-style(d, who: "edge style") = assert-keys(d, edge-style-keys, who)

// ===================================================================
// Merging style layers
// ===================================================================

/// Shallow dict merge: every key of `override` wins over `base`.
#let merge-into(base, override) = {
  let out = base
  for (k, v) in override.pairs() { out.insert(k, v) }
  out
}

/// Index-wise merge of two `key-styles` arrays. Position i in the result is
/// `merge-into(old.at(i), new.at(i))`, so per-compartment overrides
/// accumulate across sticky frames instead of the second call wiping out the
/// first. Out-of-range positions on either side are the empty dict.
#let merge-key-styles(old, new) = {
  let m = calc.max(old.len(), new.len())
  range(m).map(i => merge-into(
    old.at(i, default: (:)),
    new.at(i, default: (:)),
  ))
}

/// Merge one style dict over another. Like `merge-into`, except that
/// `key-styles` merges index-wise (see `merge-key-styles`) rather than being
/// replaced wholesale.
#let merge-style(base, override) = {
  let ov = override
  if "key-styles" in base and "key-styles" in ov {
    ov.insert("key-styles", merge-key-styles(base.key-styles, ov.key-styles))
  }
  merge-into(base, ov)
}

/// Drop the `note` / `note-fill` slots from every style in a `key`-to-style
/// dict. The operation-note slot is transient; sticky animations clear it
/// between phases while keeping the structural highlights.
#let strip-notes(styles) = {
  let out = (:)
  for (k, style) in styles.pairs() {
    let kept = (:)
    for (sk, sv) in style.pairs() {
      if sk != "note" and sk != "note-fill" { kept.insert(sk, sv) }
    }
    out.insert(k, kept)
  }
  out
}

// ===================================================================
// Theme references
// ===================================================================
//
// A style is often built long before it is drawn — an op stream is folded at
// call time, but the theme is not resolved until the frame is rendered. A
// theme reference is a placeholder value standing for "whatever
// `theme.<section>.<key>` turns out to be", swapped for the real value by
// `resolve-refs` at the single choke point in `core/frame.typ`. That is what
// lets `styles.attention("L")` follow a `set-theme(..)` made after the op was
// constructed.

/// A placeholder for `theme.<section>.<key>`, resolved when the frame is
/// drawn. Usable anywhere a style value is expected.
#let theme-ref(section, key) = (starling-theme-ref: (section, key))

/// Shorthand for the common case: a reference into the `op` section (the
/// operation-semantic roles — `search-stroke`, `attention-stroke`, …).
#let role(key) = theme-ref("op", key)

/// Whether `v` is a theme reference.
#let is-theme-ref(v) = type(v) == dictionary and "starling-theme-ref" in v

/// Look one theme reference up in a resolved theme dict.
#let resolve-ref(ref, theme) = {
  let (section, key) = ref.starling-theme-ref
  if section not in theme {
    panic("theme-ref: unknown theme section '" + section + "'.")
  }
  if key not in theme.at(section) {
    panic(
      "theme-ref: unknown key '" + key + "' in theme section '" + section + "'.",
    )
  }
  theme.at(section).at(key)
}

/// Replace every theme reference in a value by its value in `theme`.
/// Recurses through nested dicts and arrays, so a reference inside a
/// `key-styles` entry or a partial stroke dict resolves too. Values that are
/// not references are returned untouched.
#let resolve-refs(style, theme) = {
  if is-theme-ref(style) {
    resolve-ref(style, theme)
  } else if type(style) == dictionary {
    let out = (:)
    for (k, v) in style.pairs() { out.insert(k, resolve-refs(v, theme)) }
    out
  } else if type(style) == array {
    style.map(v => resolve-refs(v, theme))
  } else { style }
}

/// Resolve theme references in a whole `key`-to-style map.
#let resolve-refs-map(styles, theme) = {
  let out = (:)
  for (k, style) in styles.pairs() { out.insert(k, resolve-refs(style, theme)) }
  out
}
