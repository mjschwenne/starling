// Assertion-style test for the animation core (`src/core/*` + `src/styles.typ`).
// Exercises snapshots, the op stream, theme merging and resolution, the
// theme-reference choke point, `make-frames`, `overlay`, and `result` — with
// a stub draw backend standing in for a real data structure.
//
// The rendered page at the bottom is a small end-to-end canvas: it keeps the
// visual-regression harness honest about `make-canvas` assembly (backend
// commands, then `extra` overlays, inside one canvas) and about the `el-`
// anchor names actually resolving in cetz.

#import "@preview/cetz:0.5.2"
#import "/src/core/draw-util.typ": anchor
#import "/src/core/frame.typ": make-canvas, make-frames, make-renderer, overlay, render, result
#import "/src/core/ops.typ": annotate, apply-ops, commit, set-alt, style-edge, style-node
#import "/src/core/snapshot.typ": apply-snapshot, blank-snapshot, clear-notes, with-edge, with-node
#import "/src/core/style.typ": merge-key-styles, merge-style, resolve-refs, role, theme-ref
#import "/src/core/text.typ": alt-describe, alt-intro, display-value
#import "/src/core/theme.typ": default-theme, merge-theme, resolve-theme, set-theme
#import "/src/styles.typ" as styles

// ===================================================================
// Snapshots
// ===================================================================

#assert.eq(blank-snapshot(), (nodes: (:), edges: (:)))

// Styling merges per key; later writes win key-by-key rather than replacing
// the whole style.
#let s = with-node(with-node(blank-snapshot(), "L", (fill: red)), "L", (stroke: blue))
#assert.eq(s.nodes.L, (fill: red, stroke: blue))
#assert.eq(s.edges, (:))

#let s = with-edge(s, "L", (stroke: blue, hide: true))
#assert.eq(s.edges.L.hide, true)

// `key-styles` is the exception: it merges index-wise, so highlighting
// compartment 0 in one frame and compartment 1 in the next keeps both.
#assert.eq(
  merge-key-styles(((fill: red), (:)), ((:), (fill: blue))),
  ((fill: red), (fill: blue)),
)
#assert.eq(
  merge-style((key-styles: ((fill: red),)), (key-styles: ((:), (fill: blue)))),
  (key-styles: ((fill: red), (fill: blue))),
)

// Notes are transient; the structural styling survives clearing them.
#let noted = with-node(with-node(blank-snapshot(), "R", (fill: red)), "R", (note: [x]))
#assert.eq(clear-notes(noted).nodes.R, (fill: red))

// ===================================================================
// Op constructors
// ===================================================================

// Positional args are element keys, named args the shared style: one op per
// key.
#let ops = style-node("L", "RR", fill: red)
#assert.eq(ops.len(), 2)
#assert.eq(ops.at(0), (op: "style-node", key: "L", style: (fill: red)))
#assert.eq(ops.at(1).key, "RR")

#assert.eq(style-edge("R", hide: true).at(0).op, "style-edge")
#assert.eq(annotate("L", [h = 2]).at(0), (op: "annotate", key: "L", note: [h = 2]))
#assert.eq(set-alt("done").at(0), (op: "alt", text: "done"))
#assert.eq(commit(alt: "a").at(0).op, "commit")

// Every constructor returns an array, so streams compose with `+`.
#assert.eq((style-node("L", fill: red) + commit(alt: "a")).len(), 2)

// `apply-snapshot` folds styling ops into one snapshot; frame-level ops have
// no meaning there and are rejected.
#let folded = apply-snapshot(
  blank-snapshot(),
  style-node("L", fill: red) + style-edge("L", hide: true) + annotate("L", [n]),
)
#assert.eq(folded.nodes.L, (fill: red, note: [n]))
#assert.eq(folded.edges.L, (hide: true))

// ===================================================================
// apply-ops — sticky mode, commits, metadata
// ===================================================================

// A stub backend: asserts nothing, draws nothing measurable. The core never
// interprets the structure, so a string is a perfectly good one.
#let noop-draw(structure, snapshot, node-style: (:), edge-style: (:), theme: (:)) = ()

#let stream = (
  style-node("", fill: red)
    + commit(caption: [first], step: (kind: "init"), alt: "Frame one.")
    + style-node("L", fill: blue)
    + set-alt("Frame two.")
)

// Sticky: frame two inherits frame one's styling.
#let sticky = apply-ops(make-renderer("s", noop-draw, sticky: true), stream)
#assert.eq(sticky.snapshots.len(), 2)
#assert.eq(sticky.snapshots.at(0), (nodes: ("": (fill: red)), edges: (:)))
#assert.eq(
  sticky.snapshots.at(1),
  (nodes: ("": (fill: red), "L": (fill: blue)), edges: (:)),
)

// Non-sticky (the default): each frame starts blank.
#let fresh = apply-ops(make-renderer("s", noop-draw), stream)
#assert.eq(fresh.snapshots.at(1), (nodes: ("L": (fill: blue)), edges: (:)))

// The trailing in-progress frame is kept, so no closing `commit` is needed.
#let frames = render(sticky)
#assert.eq(frames.len(), 2)
#assert.eq(frames.at(0).caption, [first])
#assert.eq(frames.at(0).step, (kind: "init"))
#assert.eq(frames.at(0).alt, "Frame one.")
#assert.eq(frames.at(1).caption, none)
#assert.eq(frames.at(1).alt, "Frame two.")

// Nested arrays flatten, so `+`-composed helper output needs no unwrapping.
#assert.eq(
  apply-ops(make-renderer("s", noop-draw), (style-node("a", fill: red), commit())).snapshots.len(),
  2,
)

// ===================================================================
// Theme — merge and resolution precedence
// ===================================================================

// Merging is two levels deep: a section's listed keys change, its other keys
// and every other section stay put.
#let merged = merge-theme(default-theme, (op: (search-stroke: (paint: teal))))
#assert.eq(merged.op.search-stroke, (paint: teal))
#assert.eq(merged.op.attention-stroke, default-theme.op.attention-stroke)
#assert.eq(merged.render, default-theme.render)

// The subtree idiom's gray lives in the render section, so it is themeable.
#assert.eq(default-theme.render.elided-fill, gray)

// default < state < per-call.
#context {
  assert.eq(resolve-theme((:)).op.search-stroke, default-theme.op.search-stroke)
  assert.eq(resolve-theme((op: (search-stroke: (paint: teal)))).op.search-stroke, (paint: teal))
}

#set-theme((op: (search-stroke: (paint: olive)), render: (note-bg: silver)))

#context {
  // State beats the defaults ...
  assert.eq(resolve-theme((:)).op.search-stroke, (paint: olive))
  assert.eq(resolve-theme((:)).render.note-bg, silver)
  // ... and a per-call override beats the state, key by key.
  let th = resolve-theme((op: (search-stroke: (paint: teal))))
  assert.eq(th.op.search-stroke, (paint: teal))
  assert.eq(th.render.note-bg, silver)
  assert.eq(th.op.danger-stroke, default-theme.op.danger-stroke)
}

// ===================================================================
// Theme references
// ===================================================================

#assert.eq(theme-ref("op", "search-stroke"), (starling-theme-ref: ("op", "search-stroke")))
#assert.eq(role("search-stroke"), theme-ref("op", "search-stroke"))

// References resolve against whatever theme is active, including inside
// nested values (a `key-styles` array, a partial dict).
#let th = merge-theme(default-theme, (op: (search-stroke: (paint: teal))))
#assert.eq(resolve-refs((stroke: role("search-stroke")), th), (stroke: (paint: teal)))
#assert.eq(
  resolve-refs((key-styles: ((fill: role("success-fill")),)), th),
  (key-styles: ((fill: th.op.success-fill),)),
)
#assert.eq(resolve-refs((fill: red), th), (fill: red))

// The style vocabulary is built out of references, so it follows the theme.
#assert.eq(styles.attention("L"), style-node("L", stroke: role("attention-stroke")))
#assert.eq(styles.ghost("L").len(), 2)
#assert.eq(styles.subtree("L").at(1), (op: "style-edge", key: "L", style: (child-anchor: "north")))
#assert.eq(
  resolve-refs(styles.success("L").at(0).style, th),
  (fill: th.op.success-fill, stroke: th.op.settled-stroke),
)

// ===================================================================
// make-frames, make-canvas, overlay, result
// ===================================================================

// This backend asserts what the core hands a draw function: theme references
// already resolved (in the snapshot and in both base style layers), and the
// full nested theme with the display's per-call override applied.
#let checking-draw(structure, snapshot, node-style: (:), edge-style: (:), theme: (:)) = {
  assert.eq(snapshot.nodes.at("a"), (stroke: theme.op.search-stroke))
  assert.eq(edge-style, (stroke: theme.op.danger-stroke))
  assert.eq(theme.op.attention-stroke, (paint: purple))
  // The per-spec `node-style` wins over the `make-frames` default.
  if structure == "one" {
    assert.eq(node-style, (shape: "circle"))
  } else {
    assert.eq(node-style, (fill: aqua))
  }
  ()
}

#let specs = (
  (
    structure: "one",
    build: th => apply-snapshot(blank-snapshot(), styles.search("a")),
    caption: [step one],
    step: (kind: "init"),
    alt: "Step one.",
  ),
  (
    structure: "two",
    build: th => apply-snapshot(blank-snapshot(), styles.search("a")),
    caption: [step two],
    step: (kind: "settled", result: "the structure"),
    alt: "Step two.",
    node-style: (fill: aqua),
  ),
)

#let fs = make-frames(
  specs,
  checking-draw,
  theme: (op: (attention-stroke: (paint: purple))),
  node-style: (shape: "circle"),
  edge-style: (stroke: role("danger-stroke")),
)

#assert.eq(fs.len(), 2)
#assert.eq(fs.at(0).caption, [step one])
#assert.eq(fs.at(0).extra, ())

// The structure carried per spec is what lets one animation span a shape
// change; the final frame's `step.result` is what replaces writing every
// operation twice.
#assert.eq(result(fs), "the structure")

// Rendering the frames runs the backend assertions above — including that
// the per-call `theme:` override beat the ambient theme.
#context {
  for f in fs { assert.eq(type((f.builder)(resolve-theme((:)))), content) }
}

// `overlay` appends cetz commands to one frame — and the frame it hands back
// actually draws them, which is the part a stale closure would silently
// swallow. `at` counts from the end when negative.
#let over = overlay(fs, at: 0, draw: theme => {
  assert.eq(theme.op.attention-stroke, (paint: purple))
  ()
})
#assert.eq(over.at(0).extra.len(), 1)
#assert.eq(over.at(1).extra, ())
#assert.eq(overlay(fs, at: -1, draw: ()).at(1).extra.len(), 1)
#context {
  assert.eq(type((over.at(0).builder)(resolve-theme((:)))), content)
}

// ===================================================================
// Anchors and text helpers
// ===================================================================

#assert.eq(anchor(""), "el-root")
#assert.eq(anchor("LR"), "el-LR")
#assert.eq(anchor("A"), "el-A")
#assert.eq(anchor("u->v"), "el-u--v")
#assert.eq(anchor("a--b"), "el-a--b")
#assert.eq(anchor("c3:1"), "el-c3-1")
#assert.eq(anchor("count:5"), "el-count-5")
#assert.eq(anchor("b2:0"), "el-b2-0")
#assert.eq(anchor("01#1"), "el-01.key-1")
#assert.eq(anchor("A", canvas: "g"), "g.el-A")

#assert.eq(display-value((value: 5, label: auto)), "5")
#assert.eq(display-value((value: 5, label: "five")), "five")
#assert.eq(display-value((key: 5, label: auto), value-key: "key"), "5")
#assert.eq(alt-describe("Trie", "3 words"), "Trie: 3 words.")
#assert.eq(alt-intro("BST", "4 (left: 1)", "insert 5"), "BST: 4 (left: 1). About to insert 5.")

// ===================================================================
// One rendered frame, end to end
// ===================================================================

// A minimal backend over a list of keys: one named circle each, so the
// sanitized `el-` names must be legal cetz element names and resolvable
// (including a sub-anchor) from the `extra` commands drawn in the same
// canvas.
#let dot-draw(keys, snapshot, node-style: (:), edge-style: (:), theme: (:)) = {
  import cetz.draw: circle, content
  for (i, key) in keys.enumerate() {
    let style = snapshot.nodes.at(key, default: (:))
    circle(
      (i * 2, 0),
      radius: 0.5,
      name: anchor(key),
      fill: style.at("fill", default: theme.render.node-fill),
      stroke: style.at("stroke", default: theme.render.node-stroke),
    )
    content((i * 2, 0), text(fill: theme.render.node-text-fill, key))
  }
}

#let keys = ("a", "b:1", "c->d")
#let demo = make-frames(
  (
    (
      structure: keys,
      build: th => apply-snapshot(
        blank-snapshot(),
        styles.search("a") + styles.success("c->d"),
      ),
      caption: [end to end],
      step: (kind: "static", result: keys),
      alt: "Three dots.",
    ),
  ),
  dot-draw,
)

#let demo = overlay(demo, draw: theme => {
  import cetz.draw: line
  line(
    (rel: (0, 1.2), to: anchor("a")),
    anchor("c->d") + ".north",
    stroke: theme.op.attention-stroke,
    mark: (end: ">"),
  )
})

#context (demo.first().builder)(resolve-theme((:)))
