// Snapshot — the sparse style overlay for one frame.
//
//   (nodes: ("<key>": <node style>, ..), edges: ("<key>": <edge style>, ..))
//
// Keys are opaque strings; the alphabet is the backend's business (tree
// paths `""`/`"L"`/`"LR"`, graph ids and edge keys `"u->v"`, hash-map cells
// `"c3:1"`, array cells `"count:5"`, skip-list boxes `"b2:0"`). The core
// never interprets them.
//
// A snapshot is data, not an object: every function here takes one and
// returns a new one.

#import "style.typ" as _style

/// A snapshot with no overrides.
#let blank-snapshot() = (nodes: (:), edges: (:))

/// Merge `style` into the node styling for `key`. `key-styles` merges
/// index-wise (see `style.merge-key-styles`); everything else is replaced.
#let with-node(snap, key, style) = {
  _style.assert-node-style(style, who: "style-node")
  let nodes = snap.nodes
  nodes.insert(key, _style.merge-style(nodes.at(key, default: (:)), style))
  (nodes: nodes, edges: snap.edges)
}

/// Merge `style` into the edge styling for `key`.
#let with-edge(snap, key, style) = {
  _style.assert-edge-style(style, who: "style-edge")
  let edges = snap.edges
  edges.insert(key, _style.merge-into(edges.at(key, default: (:)), style))
  (nodes: snap.nodes, edges: edges)
}

/// Attach an operation note to a node — the transient annotation slot drawn
/// in-canvas beside the element.
#let note-node(snap, key, note) = with-node(snap, key, (note: note))

/// Attach an operation note to an edge.
#let note-edge(snap, key, note) = with-edge(snap, key, (note: note))

/// Drop every operation note, keeping the structural styling. Sticky
/// animations use this between phases so notes don't pile up.
#let clear-notes(snap) = (
  nodes: _style.strip-notes(snap.nodes),
  edges: _style.strip-notes(snap.edges),
)

/// Fold styling ops into a snapshot, returning the new snapshot.
///
/// Accepts `style-node` / `style-edge` / `annotate` ops (see `core/ops.typ`)
/// and nested arrays of them; frame-level ops (`commit`, `alt`) panic,
/// because a snapshot has no frames to commit — fold those into a renderer
/// with `apply-ops` instead.
#let apply-snapshot(snap, ops) = {
  ops
    .flatten()
    .fold(snap, (s, op) => {
      if op.op == "style-node" {
        with-node(s, op.key, op.style)
      } else if op.op == "style-edge" {
        with-edge(s, op.key, op.style)
      } else if op.op == "annotate" {
        note-node(s, op.key, op.note)
      } else {
        panic(
          "apply-snapshot: '"
            + op.op
            + "' is a frame-level op with no meaning for a lone snapshot — "
            + "fold it into a renderer with apply-ops instead.",
        )
      }
    })
}
