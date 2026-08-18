// The Op command stream — a declarative layer over the renderer.
//
// Each op is a plain tagged dict describing one change to the in-progress
// frame; `commit` closes that frame and opens a fresh one. Every constructor
// returns an *array* of ops, so streams compose with `+`:
//
//   apply-ops(r,
//     style-node("", "LR", stroke: role("search-stroke"))
//       + annotate("LR", [6 < 7])
//       + commit(alt: "Comparing 7 against 6.")
//       + styles.success("LR")
//       + set-alt("Found 7."))
//
// The variadic-keys shape (`style-node("L", "RR", fill: red)` = two ops) is
// the load-bearing ergonomic decision: it is what every hand-written helper
// in the wild turned out to want.
//
// Captions and step metadata belong to a frame rather than to a snapshot, so
// they ride on `commit` (or are set on the renderer between batches).

#import "frame.typ" as _frame
#import "snapshot.typ" as _snap
#import "style.typ" as _style

// One op per positional key, sharing the named style.
#let _per-key(tag, keys, style, who) = {
  assert(
    keys.len() > 0,
    message: who + ": expected at least one element key.",
  )
  keys.map(k => {
    assert(
      type(k) == str,
      message: who + ": element keys are strings, got " + repr(k) + ".",
    )
    (op: tag, key: k, style: style)
  })
}

/// Style one or more nodes. Positional arguments are element keys; named
/// arguments are the node style applied to each of them.
///
/// ```typ
/// style-node("L", "RR", fill: red, tag: [0])
/// ```
#let style-node(..args) = {
  let style = args.named()
  _style.assert-node-style(style, who: "style-node")
  _per-key("style-node", args.pos(), style, "style-node")
}

/// Style one or more edges. Positional arguments are element keys; named
/// arguments are the edge style applied to each of them. An edge is keyed by
/// its child (trees) or by `edge-key(u, v)` (graphs).
#let style-edge(..args) = {
  let style = args.named()
  _style.assert-edge-style(style, who: "style-edge")
  _per-key("style-edge", args.pos(), style, "style-edge")
}

/// Attach an operation note to a node — the transient annotation drawn
/// beside it in the canvas.
#let annotate(key, note) = ((op: "annotate", key: key, note: note),)

/// Set the in-progress frame's alt text without committing. Use it for the
/// trailing frame, which has no following `commit` to carry its text.
#let set-alt(text) = ((op: "alt", text: text),)

/// Set the in-progress frame's caption without committing — the caption
/// counterpart of `set-alt`, for the same trailing frame.
#let set-caption(caption) = ((op: "caption", caption: caption),)

/// Set the in-progress frame's step metadata without committing. A
/// hand-driven renderer needs this on its last frame, since `result(frames)`
/// reads `step.result` from there.
#let set-step(step) = ((op: "step", step: step),)

/// Close the in-progress frame — attaching any caption, step metadata, and
/// alt text given here — and open a fresh one. Arguments left `none` leave
/// whatever the frame already has.
#let commit(caption: none, step: none, alt: none) = (
  (op: "commit", caption: caption, step: step, alt: alt),
)

#let _apply-op(r, op) = {
  if op.op == "style-node" {
    _frame.patch(r, s => _snap.with-node(s, op.key, op.style))
  } else if op.op == "style-edge" {
    _frame.patch(r, s => _snap.with-edge(s, op.key, op.style))
  } else if op.op == "annotate" {
    _frame.patch(r, s => _snap.note-node(s, op.key, op.note))
  } else if op.op == "alt" {
    _frame.with-alt(r, op.text)
  } else if op.op == "caption" {
    _frame.with-caption(r, op.caption)
  } else if op.op == "step" {
    _frame.with-step(r, op.step)
  } else if op.op == "commit" {
    let out = r
    if op.caption != none { out = _frame.with-caption(out, op.caption) }
    if op.step != none { out = _frame.with-step(out, op.step) }
    if op.alt != none { out = _frame.with-alt(out, op.alt) }
    _frame.push-frame(out)
  } else {
    panic("apply-ops: unknown op '" + repr(op) + "'.")
  }
}

/// Fold a stream of ops into a renderer, returning the updated renderer.
/// Nested arrays are flattened, so `+`-composed helper output needs no
/// unwrapping.
///
/// The trailing in-progress frame is kept — no closing `commit` is needed
/// after the last batch — but give it alt text with `set-alt` so it is as
/// accessible as the committed frames.
#let apply-ops(renderer, ops) = ops.flatten().fold(renderer, _apply-op)
