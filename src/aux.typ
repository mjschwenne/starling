// Auxiliary-structure strips — the bookkeeping beside the canvas.
//
// An algorithm animation shows what happens to the *structure*; half of what
// a student has to learn is what happens to the algorithm's own bookkeeping
// — the BFS queue, the DFS stack, Prim's frontier, Kruskal's disjoint sets,
// Dijkstra's priority queue and its `dist` / `prev` maps. Each display
// stashes a snapshot of that state on every frame's `step.aux-views`, and
// `aux-strip` renders it.
//
// The output is plain Typst content, not a `Frame`: it carries no cetz and no
// canvas, so a slide can place it wherever it likes relative to the drawing
// (`slides.subslides` does exactly that with its `aux:` argument).
//
// A view is `(kind: <str>, items: <array>)`. The kinds, and what `items`
// holds for each:
//
//   queue / stack    node ids, in structure order
//   pq               (u, v, weight, status) crossing edges, min first
//   dist-pq          (node, dist, status) queue entries, min first
//   edge-list        (u, v, weight, status) edges in weight order
//   partition        arrays of node ids, one per component
//   dist-map         (key, value, status) cells, one per node
//   prev-map         same
//
// `status` colors an element by what the algorithm just did to it, so the
// strip and the canvas agree: `chosen` / `current` ring in the attention
// stroke, `added` fills with the success color, `rejected` greys out behind a
// danger stroke, and anything else stays neutral.

#import "core/draw-util.typ": muted, text-fill-for
#import "core/theme.typ": resolve-theme

// ===================================================================
// Box primitives
// ===================================================================

// A single strip cell: a node-styled box carrying `body`. `fill`, `stroke` (a
// ready stroke value — the caller decides thickness), and `text-fill` are
// passed in so the status kinds can recolor cells while the queue/stack kinds
// keep plain structural styling. `inset` defaults to the horizontal-strip
// padding; the vertical edge-list cells tighten it.
#let _strip-box(body, fill, stroke, text-fill, inset: (x: 0.6em, y: 0.45em)) = box(
  fill: fill,
  stroke: stroke,
  inset: inset,
  radius: 2pt,
  text(fill: text-fill, body),
)

// A neutral (unstyled) strip cell.
#let _neutral-box(body, rt) = _strip-box(
  body,
  rt.node-fill,
  0.5pt + rt.node-stroke,
  rt.node-text-fill,
)

// The "nothing here" cell every view falls back to when its structure is
// empty.
#let _empty-box(rt, body: "(empty)") = _strip-box(
  body,
  rt.node-fill,
  0.5pt + rt.node-stroke,
  muted(rt.node-text-fill),
)

// A small muted annotation (end labels like front/rear/min, cursors,
// per-view titles).
#let _end-label(rt, t) = text(size: 0.75em, fill: muted(rt.node-text-fill), t)

// Style one element box by its operation `status`, pulling colors from the op
// theme so the strip matches the canvas:
//   chosen / current -> attention-stroke ring (about to be popped/examined)
//   added            -> success fill + stroke (an accepted tree edge)
//   rejected         -> danger stroke, muted text (a cycle edge, skipped)
//   candidate / pending / other -> neutral structural styling
#let _status-box(body, status, op, rt, inset: (x: 0.6em, y: 0.45em)) = {
  let stroke = if status == "chosen" or status == "current" {
    op.attention-stroke
  } else if status == "added" {
    op.success-stroke
  } else if status == "rejected" {
    op.danger-stroke
  } else {
    0.5pt + rt.node-stroke
  }
  let fill = if status == "added" { op.success-fill } else { rt.node-fill }
  let text-fill = if status == "added" {
    text-fill-for(op.success-fill)
  } else if status == "rejected" {
    muted(rt.node-text-fill)
  } else {
    rt.node-text-fill
  }
  _strip-box(body, fill, stroke, text-fill, inset: inset)
}

// ===================================================================
// Element formatting
// ===================================================================

// An edge element `(u, v, weight)` as `u–v (w)`, honoring the `labels`
// id -> content map for the endpoints.
#let _edge-body(item, labels) = {
  let lu = labels.at(item.u, default: item.u)
  let lv = labels.at(item.v, default: item.v)
  [#lu–#lv (#item.weight)]
}

// A `(node, dist)` priority-queue element as `node: d`. The Dijkstra analog
// of `_edge-body` — a node keyed by its tentative distance rather than an
// edge keyed by its weight.
#let _node-dist-body(item, labels) = {
  let ln = labels.at(item.node, default: item.node)
  [#ln: #item.dist]
}

// A tall, narrow variant of `_edge-body`: the endpoints stacked over a short
// connector with the weight beneath, so a long horizontal edge list stays
// compact.
//
//   u
//   |
//   v
//  (w)
//
// The connector inherits the surrounding text fill (set by `_status-box`) so
// a rejected edge's label greys out as one piece.
#let _edge-body-vertical(item, labels) = {
  let lu = labels.at(item.u, default: item.u)
  let lv = labels.at(item.v, default: item.v)
  align(center, stack(
    dir: ttb,
    spacing: 0.18em,
    lu,
    text(size: 0.9em, "|"),
    lv,
    text(size: 0.85em, [(#item.weight)]),
  ))
}

// ===================================================================
// The views
// ===================================================================

// Queue / stack (BFS / DFS): a horizontal strip of node-styled boxes. `ids`
// is the element order (front-first for a queue, bottom-first for a stack).
// End annotations mark the live ends: front/rear for a queue, top (the
// push/pop end, drawn rightmost) for a stack.
#let _nodes-content(ids, kind, labels, rt) = {
  if ids.len() == 0 {
    return stack(
      dir: ttb,
      spacing: 0.3em,
      _empty-box(rt),
      _end-label(rt, if kind == "stack" { "top" } else { "front" }),
    )
  }
  let boxes = ids.map(id => _neutral-box(labels.at(id, default: id), rt))
  let last = ids.len() - 1
  let labels-row = range(ids.len()).map(i => if kind == "stack" {
    // Stack top is the right end (where we push and pop).
    if i == last { _end-label(rt, "top") } else { [] }
  } else if ids.len() == 1 {
    _end-label(rt, "front / rear")
  } else if i == 0 {
    _end-label(rt, "front")
  } else if i == last {
    _end-label(rt, "rear")
  } else { [] })
  grid(
    columns: ids.len(),
    column-gutter: 0.4em,
    row-gutter: 0.3em,
    align: center,
    ..boxes,
    ..labels-row,
  )
}

// Priority queue: entries sorted ascending by priority, min at the front.
// Rendered as a vertical column — a priority queue's natural orientation, and
// it stays narrow when the frontier is wide — with the `min` marked at the
// top. `body-fn(item, labels)` formats one entry: Prim's frontier uses
// `_edge-body` (crossing edges `u–v (w)`), Dijkstra's queue
// `_node-dist-body` (nodes keyed by distance `node: d`).
#let _pq-content(items, labels, op, rt, body-fn: _edge-body) = {
  if items.len() == 0 {
    return grid(
      columns: (auto, auto),
      column-gutter: 0.4em,
      align: (right + horizon, left + horizon),
      _end-label(rt, "min"),
      _empty-box(rt),
    )
  }
  let cells = ()
  for (i, it) in items.enumerate() {
    cells.push(if i == 0 { _end-label(rt, "min") } else { [] })
    cells.push(_status-box(body-fn(it, labels), it.status, op, rt))
  }
  grid(
    columns: (auto, auto),
    column-gutter: 0.4em,
    row-gutter: 0.35em,
    align: (right + horizon, left + horizon),
    ..cells,
  )
}

// Kruskal's sorted edge list: every edge in weight order, each tagged with a
// status (`pending` / `current` / `added` / `rejected`). A cursor (▲) sits
// under the current edge.
#let _edge-list-content(items, labels, op, rt) = {
  if items.len() == 0 {
    return _empty-box(rt, body: "(no edges)")
  }
  // Vertical (tall, narrow) edge labels keep the strip compact even when the
  // graph has many edges.
  let boxes = items.map(it => _status-box(
    _edge-body-vertical(it, labels),
    it.status,
    op,
    rt,
    inset: (x: 0.45em, y: 0.4em),
  ))
  // Every cell reserves the cursor glyph's height (via `hide`) so the row
  // keeps a constant height whether or not this frame has a current edge —
  // otherwise the strip bounces vertically across a touying animation.
  let cursor-row = items.map(it => if it.status == "current" {
    _end-label(rt, "▲")
  } else { hide(_end-label(rt, "▲")) })
  grid(
    columns: items.len(),
    column-gutter: 0.4em,
    row-gutter: 0.3em,
    align: center,
    ..boxes,
    ..cursor-row,
  )
}

// Kruskal's disjoint sets: one bordered group per component, each holding its
// members as node boxes. `groups` is an array of id arrays.
#let _partition-content(groups, labels, rt) = {
  if groups.len() == 0 { return _empty-box(rt) }
  let group-box = ids => box(
    stroke: 0.75pt + rt.node-stroke,
    radius: 3pt,
    inset: 0.35em,
    grid(
      columns: ids.len(),
      column-gutter: 0.3em,
      ..ids.map(id => _neutral-box(labels.at(id, default: id), rt)),
    ),
  )
  grid(
    columns: groups.len(),
    column-gutter: 0.6em,
    align: horizon,
    ..groups.map(g => group-box(g)),
  )
}

// A node-keyed map (Dijkstra's `dist` / `prev`): a two-row strip with a
// node-styled header per key over a value cell. `items` is an ordered array
// of `(key, value, status)` — one per node — where `value` is the
// already-formatted cell content (a distance, `∞`, a predecessor id, or `∅`)
// and `status` colors the cell like the other kinds (`current` rings the node
// just polled, `added` fills a value just updated). Rendered as a grid of
// boxes rather than a bordered table, to match the other strips.
#let _map-content(items, labels, op, rt) = {
  if items.len() == 0 { return _empty-box(rt) }
  let headers = items.map(it => _neutral-box(
    text(weight: "bold", labels.at(it.key, default: it.key)),
    rt,
  ))
  let values = items.map(it => _status-box(it.value, it.status, op, rt))
  grid(
    columns: items.len(),
    column-gutter: 0.4em,
    row-gutter: 0.3em,
    align: center,
    ..headers,
    ..values,
  )
}

// Dispatch one view to its content builder.
#let _view-content(kind, items, labels, op, rt) = if (
  kind == "queue" or kind == "stack"
) {
  _nodes-content(items, kind, labels, rt)
} else if kind == "pq" {
  _pq-content(items, labels, op, rt)
} else if kind == "dist-pq" {
  _pq-content(items, labels, op, rt, body-fn: _node-dist-body)
} else if kind == "dist-map" or kind == "prev-map" {
  _map-content(items, labels, op, rt)
} else if kind == "edge-list" {
  _edge-list-content(items, labels, op, rt)
} else if kind == "partition" {
  _partition-content(items, labels, rt)
} else {
  panic("aux-strip: unknown view kind '" + repr(kind) + "'.")
}

// ===================================================================
// The public surface
// ===================================================================

/// The human-readable name of one view `kind` — the same heading
/// @@aux-strip() stamps above each view when it stacks several.
///
/// Exposed so a slide that places views separately (via `aux-strip(step,
/// view: ..)`) can render each view's title in its own style. The kinds a
/// frame carries are the `kind` fields of its `step.aux-views`.
///
/// -> str
#let aux-view-title(
  /// A view kind: `"queue"` / `"stack"` / `"pq"` / `"edge-list"` /
  /// `"partition"` / `"dist-pq"` / `"dist-map"` / `"prev-map"`.
  /// -> str
  kind,
) = if kind == "edge-list" {
  "Sorted edges"
} else if kind == "partition" {
  "Components"
} else if kind == "pq" {
  "Frontier"
} else if kind == "dist-pq" {
  "Priority queue"
} else if kind == "dist-map" {
  "Distances"
} else if kind == "prev-map" {
  "Predecessors"
} else if kind == "queue" {
  "Queue"
} else if kind == "stack" {
  "Stack"
} else { "" }

/// Render the auxiliary bookkeeping captured for one animation frame as a
/// placeable strip of boxes — a teaching aid so students can track the
/// algorithm's own state alongside the canvas. Pass a frame's `step`:
///
/// ```typ
/// #let frames = graph.bfs-display(g, "A")
/// #grid(columns: 2, canvas(frames.at(2)), aux-strip(frames.at(2).step))
/// ```
///
/// What each display stashes:
///
/// - `bfs-display` / `dfs-display` — the BFS queue / DFS stack (the stack is
///   shown faithfully, duplicates and all, since a node may be pushed more
///   than once before an earlier copy is popped).
/// - `prim-display` — the frontier priority queue of crossing edges, min
///   first, the chosen edge ringed.
/// - `kruskal-display` — two views: the sorted edge list with a cursor and
///   per-edge status, plus the disjoint-set partition.
/// - `dijkstra-display` — three views: the priority queue of `(node, dist)`
///   entries (min first, the polled entry ringed), and the `dist` and `prev`
///   maps.
///
/// Returns plain content, not a `Frame`, so it drops anywhere. When a step
/// carries several views they stack vertically; pass `view:` to render just
/// one for separate placement.
///
/// -> content
#let aux-strip(
  /// One frame's `step` metadata dict.
  /// -> dictionary
  step,
  /// Optional `id -> content` map giving each node a display label (to match
  /// custom node labels; also used for the endpoints of edge elements). Ids
  /// not present fall back to the id string itself.
  /// -> dictionary
  labels: (:),
  /// Select a single view by its kind when the step carries more than one
  /// (e.g. `"partition"` for Kruskal's disjoint sets). `auto` renders every
  /// view the step holds, stacked.
  /// -> auto | str
  view: auto,
  /// Whether to stamp each view's title above it. `auto` shows titles only
  /// when several views are stacked, so a single `view:` is untitled; `true`
  /// forces one on, `false` suppresses it even for a stack.
  /// -> auto | bool
  title: auto,
  /// Partial theme override, merged over the ambient theme. Elements are
  /// colored from `theme.op` (by status) and `theme.render` (structurally).
  /// -> dictionary
  theme: (:),
) = {
  assert(
    type(step) == dictionary and step.at("aux-views", default: none) != none,
    message: "aux-strip: expected a frame's `step` carrying `aux-views` — "
      + "every graph algorithm display stamps one on each frame; got "
      + repr(step)
      + ".",
  )
  let views = step.aux-views
  if view != auto { views = views.filter(v => v.kind == view) }
  // `auto`: titles only when >1 view is stacked. `true`/`false` force them
  // on/off (e.g. `true` to name a single `view:`-selected strip).
  let show-titles = if title == auto { views.len() > 1 } else { title }
  context {
    let th = resolve-theme(theme)
    let rendered = views.map(v => {
      let body = _view-content(v.kind, v.items, labels, th.op, th.render)
      if show-titles {
        stack(
          dir: ttb,
          spacing: 0.25em,
          _end-label(th.render, aux-view-title(v.kind)),
          body,
        )
      } else { body }
    })
    if rendered.len() == 1 {
      rendered.first()
    } else { stack(dir: ttb, spacing: 0.7em, ..rendered) }
  }
}
