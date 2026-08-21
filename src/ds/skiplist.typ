// Skip list — a sorted set of integer keys as a probabilistic multi-level
// linked list.
//
// Every key sits at level 0, and each also rises through a random tower of
// "express lanes" that let a search skip ahead. The structure stores the set
// as a sorted array of nodes `(key, label, height)`; the forward pointers are
// NOT stored, because at level L the level-L list is exactly the subsequence
// of nodes with `height > L`, and pointers join consecutive members. The
// backend derives them.
//
// The `label` rides along with the integer `key` for display only (the
// `value`/`label` split shared with the trees and the sorts): ordering is
// always by key.
//
// Tower heights come from one of two sources, per node:
//   * EXPLICIT — the factory or `insert` is handed a `height`.
//   * SEEDED COIN FLIPS — a deterministic LCG PRNG seeded off the list's
//     `seed`, flipped with probability `p` (default 1/2), capped at
//     `max-level`. Deterministic, so visual-regression refs are stable.
//
// Insert and delete are *interleaved single-pass*: the pointer surgery
// happens as the top-down descent reaches each lane, because the descent
// lands on the target's predecessor on every lane it occupies. There is no
// separate splice phase and no backtracking — the deferred `update[]`-array
// textbook form is the alternative, and both are single-pass.
//
// step.kind vocabulary
// --------------------
//   static                the one frame of `display`
//   init                  the opening frame of every animation
//   advance / drop        the descent: move right, or drop a level
//   found / not-found     how a search ended
//   materialize / splice  the new node appears, then joins one lane
//   unlink                one lane bypasses the target
//   settled / deleted     terminal success of an insert / a delete
// The final frame of every display carries `step.result` — the skip list the
// operation produced (the unchanged input, for a search).

#import "../core/draw-util.typ": anchor
#import "../core/frame.typ": make-frames, make-renderer
#import "../core/snapshot.typ": blank-snapshot, with-edge, with-node
#import "../core/text.typ": alt-describe, alt-intro, display-value as _display-value
#import "../draw/skiplist.typ": box-key, data-key, draw-skiplist, forward-key

#let _DS = "Skip list"

// ===================================================================
// Deterministic PRNG (Typst has no built-in RNG)
// ===================================================================
//
// A tiny linear congruential generator. The multiplier / increment / modulus
// are the classic glibc `rand()` constants; the state stays in `[0, 2^31)`,
// well inside Typst's 64-bit ints even after the multiply.

#let _lcg-next(s) = calc.rem(s * 1103515245 + 12345, 2147483648)

// Flip a coin tower: start at height 1, and while a fresh flip comes up heads
// (a uniform draw below `p`) and we are under `max-level`, grow one more
// level. Returns `(height, state')` so callers can thread the generator.
#let _coin-height(state, max-level, p) = {
  let h = 1
  let s = state
  while h < max-level {
    s = _lcg-next(s)
    if (s / 2147483648) < p { h = h + 1 } else { break }
  }
  (h, s)
}

// ===================================================================
// Node helpers
// ===================================================================
//
// A node is `(key: int, label: any, height: int)`, and `nodes` is kept sorted
// strictly ascending by key.

// A node's *visible* value, for a box body: its label when set, else the
// integer key wrapped to content.
#let _disp-val(nd) = if nd.label == auto { [#nd.key] } else { nd.label }

// A node's name in prose: its label when that is a plain string, else the key
// — the same rule the trees and the sorts use.
#let _disp(nd) = _display-value(nd, value-key: "key")

// The natural link heights of the full list — one per node.
#let _heights(nodes) = nodes.map(nd => nd.height)

// The column a data node at array index `idx` draws in. Column 0 is the
// header, so data nodes start at 1; `idx == -1` denotes the header itself.
#let _col(idx) = if idx == -1 { 0 } else { idx + 1 }

// Find `key` in the sorted `nodes`: `(present, pos)`, where `pos` is the
// index of the key when present and the insertion point when not (the first
// index whose key exceeds `key`).
#let _find(nodes, key) = {
  for (i, nd) in nodes.enumerate() {
    if nd.key == key { return (present: true, pos: i) }
    if nd.key > key { return (present: false, pos: i) }
  }
  (present: false, pos: nodes.len())
}

// The next node index strictly after `i` that is linked at level `L` (that
// is, `links[j] > L`), or `none`. `i == -1` starts the scan at the header's
// successor.
#let _next-at(nodes, links, i, L) = {
  for j in range(i + 1, nodes.len()) {
    if links.at(j) > L { return j }
  }
  none
}

/// The classic skip-list search, shared by the pure operations and every
/// animation. Descends from the top level, moving right while the next key is
/// below `key` and dropping a level when it would overshoot.
///
/// `links` gives each node's *linked* height (`links[j] > L` ⟺ node j
/// participates at level L), which is what lets an insert's search ignore its
/// own not-yet-spliced node by giving it link 0.
///
/// Returns `found`, the per-level `update` array (the node index whose
/// level-L pointer precedes the search position, `-1` = header), the
/// animation `path` of advance / drop moves, the node index `cand` the search
/// lands before at level 0, and how many `levels` it considered.
///
/// -> dictionary
#let search-walk(nodes, links, key) = {
  let levels = if links.len() == 0 { 1 } else { calc.max(1, ..links) }
  let update = range(levels).map(_ => -1)
  let cur = -1
  let path = ()
  for L in range(levels - 1, -1, step: -1) {
    while true {
      let nxt = _next-at(nodes, links, cur, L)
      if nxt != none and nodes.at(nxt).key < key {
        path.push((kind: "advance", level: L, from: cur, to: nxt))
        cur = nxt
      } else {
        path.push((kind: "drop", level: L, at: cur, next: nxt))
        break
      }
    }
    update.at(L) = cur
  }
  let cand = _next-at(nodes, links, cur, 0)
  (
    found: cand != none and nodes.at(cand).key == key,
    update: update,
    path: path,
    cand: cand,
    levels: levels,
  )
}

// Plan an insert of `key` (rng threaded through `state`): whether the key is
// already present, its sorted `pos`, the resolved tower `height`, the new
// node record, and the advanced rng `state`. Shared by the pure op and the
// display so the two always agree on the height. An explicit height (capped
// at `max-level`) wins; otherwise flip.
#let _plan-insert(nodes, state, max-level, p, key, label, height) = {
  let f = _find(nodes, key)
  if f.present {
    // Update in place: keep the existing height unless a new one is given.
    let old = nodes.at(f.pos)
    let h = if height == none { old.height } else { calc.min(height, max-level) }
    return (
      present: true,
      pos: f.pos,
      height: h,
      node: (key: key, label: label, height: h),
      state: state,
    )
  }
  let (h, s2) = if height == none {
    _coin-height(state, max-level, p)
  } else { (calc.max(1, calc.min(height, max-level)), state) }
  (
    present: false,
    pos: f.pos,
    height: h,
    node: (key: key, label: label, height: h),
    state: s2,
  )
}

// ===================================================================
// Construction
// ===================================================================

/// Build a skip list from a set of keys.
///
/// Each element is either a bare non-negative integer (its own key, an `auto`
/// label, and a seeded coin-flip tower) or a
/// `(value: <int>, label: <content>, height: <int>)` dict — `value` required,
/// the other two optional. A missing height is chosen by a deterministic coin
/// flip off `seed`, so references stay stable; duplicate keys are rejected.
///
/// Accepts a splat of elements (`skiplist.new(3, 1, 4)`) or a single array of
/// them.
///
/// ```typ
/// #let s = skiplist.new(3, 1, 4, 5, seed: 7)          // seeded towers
/// #let t = skiplist.new((value: 3, height: 3), 1, 4)  // one height pinned
/// ```
///
/// -> dictionary
#let new(
  /// The keys — a splat of ints and/or `(value:, label:, height:)` dicts, or
  /// one array of them.
  /// -> int | dictionary | array
  ..args,
  /// Coin-flip seed, giving deterministic towers for every element without an
  /// explicit height.
  /// -> int
  seed: 1,
  /// The tallest tower a coin flip may build.
  /// -> int
  max-level: 4,
  /// The probability of growing one more level on each flip.
  /// -> float
  p: 0.5,
  /// Whether to draw the nil tail sentinel.
  /// -> bool
  nil: true,
) = {
  let raw = args.pos()
  if raw.len() == 1 and type(raw.first()) == array { raw = raw.first() }

  // Parse the elements into (key, label, explicit-height?) in input order.
  let parsed = ()
  for x in raw {
    let (key, label, h) = if type(x) == dictionary {
      assert(
        "value" in x,
        message: "skiplist.new: an element dict must have a 'value' key.",
      )
      for k in x.keys() {
        assert(
          k == "value" or k == "label" or k == "height",
          message: "skiplist.new: element dict keys must be 'value' / 'label' "
            + "/ 'height', got '"
            + k
            + "'.",
        )
      }
      (x.value, x.at("label", default: auto), x.at("height", default: none))
    } else { (x, auto, none) }
    assert(
      type(key) == int and key >= 0,
      message: "skiplist.new: keys must be non-negative integers, got "
        + repr(key)
        + ".",
    )
    if h != none {
      assert(
        type(h) == int and h >= 1 and h <= max-level,
        message: "skiplist.new: an explicit height must be an integer in "
          + "1..max-level, got "
          + repr(h)
          + ".",
      )
    }
    parsed.push((key: key, label: label, height: h))
  }

  // Resolve the heights, flipping for the unset ones and threading the rng,
  // then sort by key and reject duplicates.
  let state = seed
  let nodes = ()
  for e in parsed {
    let h = e.height
    if h == none {
      let (hh, s2) = _coin-height(state, max-level, p)
      h = hh
      state = s2
    }
    nodes.push((key: e.key, label: e.label, height: h))
  }
  nodes = nodes.sorted(key: nd => nd.key)
  for i in range(1, nodes.len()) {
    assert(
      nodes.at(i).key != nodes.at(i - 1).key,
      message: "skiplist.new: duplicate key " + str(nodes.at(i).key) + ".",
    )
  }
  (
    kind: "skiplist",
    nodes: nodes,
    max-level: max-level,
    seed: seed,
    rng-state: state,
    nil: nil,
    p: p,
  )
}

// ===================================================================
// Pure operations
// ===================================================================

/// How many keys the list holds.
/// -> int
#let len(sl) = sl.nodes.len()

/// How many levels the list reaches — the tallest tower, at least one.
/// -> int
#let levels(sl) = if sl.nodes.len() == 0 {
  1
} else { calc.max(1, ..sl.nodes.map(nd => nd.height)) }

/// The keys, in sorted order.
/// -> array
#let keys(sl) = sl.nodes.map(nd => nd.key)

/// Whether `key` is in the list — answered by the same descent the animation
/// draws.
/// -> bool
#let contains(sl, key) = search-walk(sl.nodes, _heights(sl.nodes), key).found

/// The label stored at `key`, or `none` when it is absent.
/// -> any
#let get(sl, key) = {
  let f = _find(sl.nodes, key)
  if f.present { sl.nodes.at(f.pos).label } else { none }
}

/// Insert `key`, updating the label in place when it is already present.
/// `height` is explicit (capped at `max-level`) or a seeded coin flip; the rng
/// advances only when a flip actually happens.
/// -> dictionary
#let insert(sl, key, label: auto, height: none) = {
  let plan = _plan-insert(
    sl.nodes,
    sl.rng-state,
    sl.max-level,
    sl.p,
    key,
    label,
    height,
  )
  let nodes = if plan.present {
    let nn = sl.nodes
    nn.at(plan.pos) = plan.node
    nn
  } else {
    sl.nodes.slice(0, plan.pos) + (plan.node,) + sl.nodes.slice(plan.pos)
  }
  (..sl, nodes: nodes, rng-state: plan.state)
}

/// Delete `key`, returning the list unchanged when it is absent.
/// -> dictionary
#let delete(sl, key) = {
  let f = _find(sl.nodes, key)
  if not f.present { return sl }
  (..sl, nodes: sl.nodes.slice(0, f.pos) + sl.nodes.slice(f.pos + 1))
}

/// A one-line prose summary — the opening line of every alt text.
/// -> str
#let describe(sl) = if sl.nodes.len() == 0 {
  "skip list []"
} else {
  let listing = sl.nodes
    .map(nd => _disp(nd) + "(h" + str(nd.height) + ")")
    .join(", ")
  "skip list [" + listing + "]"
}

/// Check the structural invariants: keys are strictly ascending non-negative
/// integers, and every tower height is in 1..max-level. Returns `true` or
/// panics.
/// -> bool
#let check-invariants(sl) = {
  let prev = none
  for nd in sl.nodes {
    assert(
      type(nd.key) == int,
      message: "skiplist.check-invariants: keys must be integers, got "
        + repr(nd.key)
        + ".",
    )
    assert(
      nd.key >= 0,
      message: "skiplist.check-invariants: keys must be non-negative, got "
        + repr(nd.key)
        + ".",
    )
    if prev != none {
      assert(
        nd.key > prev,
        message: "skiplist.check-invariants: keys must be strictly ascending "
          + "(unique).",
      )
    }
    prev = nd.key
    assert(
      nd.height >= 1 and nd.height <= sl.max-level,
      message: "skiplist.check-invariants: tower heights must be in "
        + "1..max-level, got "
        + repr(nd.height)
        + ".",
    )
  }
  true
}

// ===================================================================
// Rendering
// ===================================================================

// The backend's column array, from a display-node list plus per-node `state`
// ("live" / "ghost") and `links` (linked height, one past the top linked
// level). `mins` gives each data node its `link-min` — the lowest linked
// level, 0 by default — so a top-down insert splice can raise the linked
// range from the top. The header comes first and the nil sentinel last.
#let _mk-cols(dnodes, states, links, nil-flag, mins: none) = {
  let cols = (
    (kind: "header", height: 1, state: "live", link-min: 0, link-height: 0),
  )
  for (j, nd) in dnodes.enumerate() {
    cols.push((
      kind: "data",
      height: nd.height,
      key: nd.key,
      label: _disp-val(nd),
      state: states.at(j),
      link-min: if mins == none { 0 } else { mins.at(j) },
      link-height: links.at(j),
    ))
  }
  if nil-flag {
    cols.push((kind: "nil", height: 1, state: "live", link-min: 0, link-height: 0))
  }
  cols
}

#let _mk-table(cols) = (cols: cols, cell-width: auto, measure-cells: ())

/// The positioned-table dict the backend consumes — the entry point for a
/// hand-composed cetz canvas (`draw-skiplist`) or the op command stream.
/// -> dictionary
#let positioned(sl, cell-width: auto) = (
  cols: _mk-cols(
    sl.nodes,
    sl.nodes.map(_ => "live"),
    _heights(sl.nodes),
    sl.nil,
  ),
  cell-width: cell-width,
  measure-cells: (),
)

/// A `Renderer` over this list, bound to the skip-list backend — the entry
/// point for driving an animation yourself with the op command stream. Pass
/// `sticky: true` when each frame's styling should accumulate.
/// -> dictionary
#let renderer(
  sl,
  cell-width: auto,
  node-style: (:),
  edge-style: (:),
  sticky: false,
  theme: (:),
) = make-renderer(
  positioned(sl, cell-width: cell-width),
  draw-skiplist,
  node-style: node-style,
  edge-style: edge-style,
  sticky: sticky,
  theme: theme,
)

// Turn per-frame specs into frames. Each spec carries its own `table` (the
// columns' link state mutates frame to frame) plus a `build(theme) =>
// snapshot`.
//
// The one piece of real work is the global measurement set: the distinct data
// labels (plus the nil sentinel) across ALL frames, threaded onto every
// frame's table so "fit" sizing measures one superset and the box footprint
// stays constant as the animation runs.
#let _frames(specs, theme, cell-width) = {
  let seen = (:)
  let measure-cells = ()
  for s in specs {
    for col in s.table.cols {
      let v = if col.kind == "data" {
        col.label
      } else if col.kind == "nil" { "NIL" } else { none }
      if v != none {
        let cell = (value: v)
        let k = repr(cell)
        if k not in seen {
          seen.insert(k, true)
          measure-cells.push(cell)
        }
      }
    }
  }
  make-frames(
    specs.map(s => (
      structure: (..s.table, cell-width: cell-width, measure-cells: measure-cells),
      build: s.build,
      caption: s.caption,
      step: s.step,
      alt: s.alt,
    )),
    draw-skiplist,
    theme: theme,
  )
}

// A blank snapshot with one box styled — keeps the spec builders terse.
#let _styled(key, ..style) = with-node(blank-snapshot(), key, style.named())

// Stamp `step.result` onto the last spec.
#let _stamp-result(specs, after) = {
  let out = specs
  let i = out.len() - 1
  let s = out.at(i)
  out.at(i) = (..s, step: (..s.step, result: after))
  out
}

// ===================================================================
// Static and search
// ===================================================================

#let _static-specs(sl) = (
  (
    table: _mk-table(_mk-cols(
      sl.nodes,
      sl.nodes.map(_ => "live"),
      _heights(sl.nodes),
      sl.nil,
    )),
    build: _ => blank-snapshot(),
    caption: none,
    step: (kind: "static"),
    alt: alt-describe(_DS, describe(sl)),
  ),
)

// The frame a search ends on: keep the trail lit, then ring the whole tower
// on a hit or mark the successor — the node the walk fell short of — on a
// miss. `trail` paints the accumulated walk; `boxes`/`edges` are its final
// extent.
#let _search-terminal-spec(table, nodes, key, w, trail, boxes, edges) = {
  let cand-col = if w.cand == none { none } else { _col(w.cand) }
  if w.found {
    let h = nodes.at(w.cand).height
    (
      table: table,
      build: th => {
        let s = trail(th, boxes, edges)
        let hit = (fill: th.op.success-fill, stroke: th.op.settled-stroke)
        for L in range(h) { s = with-node(s, box-key(cand-col, L), hit) }
        with-node(s, data-key(cand-col), hit)
      },
      caption: [found #key],
      step: (kind: "found", key: key),
      alt: "Found " + str(key) + ".",
    )
  } else {
    (
      table: table,
      build: th => {
        let s = trail(th, boxes, edges)
        if cand-col != none {
          s = with-node(s, data-key(cand-col), (stroke: th.op.danger-stroke))
        }
        s
      },
      caption: [#key not found],
      step: (kind: "not-found", key: key),
      alt: str(key) + " is not in the skip list.",
    )
  }
}

// Animate the top-left descent, leaving the WHOLE walk lit: every box the
// search has stepped on and every pointer it has followed stays in the search
// stroke — an accumulating trail — while the box currently under comparison
// is emphasized in the attention stroke. The trail is threaded through the
// loop as two growing key lists, and each frame captures its own copy of them
// (Typst arrays are values, so the per-iteration `let` pins each frame's).
#let _search-specs(sl, key) = {
  let nodes = sl.nodes
  let links = _heights(nodes)
  let table = _mk-table(_mk-cols(nodes, nodes.map(_ => "live"), links, sl.nil))
  let w = search-walk(nodes, links, key)

  // Paint every trail box and pointer, returning the snapshot so the caller
  // can layer this step's emphasis on top.
  let paint-trail(th, boxes, edges) = {
    let s = blank-snapshot()
    for b in boxes { s = with-node(s, b, (stroke: th.op.search-stroke)) }
    for e in edges { s = with-edge(s, e, (stroke: th.op.search-stroke)) }
    s
  }

  // The descent starts on the header's top box.
  let top = w.levels - 1
  let trail-boxes = (box-key(0, top),)
  let trail-edges = ()

  let specs = ((
    table: table,
    build: th => paint-trail(th, (box-key(0, top),), ()),
    caption: [search #key],
    step: (kind: "init", levels: w.levels),
    alt: alt-intro(
      _DS,
      describe(sl),
      "search for " + str(key) + " from the top-left",
    ),
  ),)

  for mv in w.path {
    let L = mv.level
    if mv.kind == "advance" {
      let to-col = _col(mv.to)
      let to-key = nodes.at(mv.to).key
      // Follow the pointer and land on the next box: both join the trail.
      trail-edges.push(forward-key(_col(mv.from), L))
      trail-boxes.push(box-key(to-col, L))
      let f-boxes = trail-boxes
      let f-edges = trail-edges
      let cur = box-key(to-col, L)
      specs.push((
        table: table,
        build: th => with-node(
          paint-trail(th, f-boxes, f-edges),
          cur,
          (stroke: th.op.attention-stroke),
        ),
        caption: [#to-key < #key #sym.arrow right],
        step: (kind: "advance", level: L),
        alt: str(to-key) + " < " + str(key) + ": move right at level " + str(L) + ".",
      ))
    } else {
      let at-col = _col(mv.at)
      let nxt = mv.next
      let cap = if nxt == none {
        if L == 0 [end of level 0] else [end of level #L #sym.arrow drop]
      } else {
        let nk = nodes.at(nxt).key
        if L == 0 [#nk #sym.gt.eq #key #sym.arrow stop] else [#nk #sym.gt.eq #key #sym.arrow drop]
      }
      let nxt-col = if nxt == none { none } else { _col(nxt) }
      let lvl = L
      // Dropping a level adds the box directly below to the trail.
      if lvl > 0 { trail-boxes.push(box-key(at-col, lvl - 1)) }
      let f-boxes = trail-boxes
      let f-edges = trail-edges
      specs.push((
        table: table,
        build: th => {
          let s = paint-trail(th, f-boxes, f-edges)
          if nxt-col != none {
            s = with-node(s, box-key(nxt-col, lvl), (stroke: th.op.attention-stroke))
          }
          s
        },
        caption: cap,
        step: (kind: "drop", level: lvl),
        alt: if nxt == none {
          "Nothing more at level " + str(lvl) + "; drop down."
        } else {
          (
            str(nodes.at(nxt).key)
              + " ≥ "
              + str(key)
              + " at level "
              + str(lvl)
              + "; drop down."
          )
        },
      ))
    }
  }

  specs.push(_search-terminal-spec(
    table,
    nodes,
    key,
    w,
    paint-trail,
    trail-boxes,
    trail-edges,
  ))
  specs
}

// ===================================================================
// Descent frames shared by insert and delete
// ===================================================================
//
// Both mutations run the same top-left descent; only the surgery they
// interleave with it differs. These two produce the pure-navigation frames,
// which read identically in both — the caller supplies the table (the two
// track different link states) and the alt text.

// One step right on a lane: follow the current box's pointer and land on the
// next one, which becomes the node under comparison.
#let _advance-spec(table, next-key, key, L, from-col, to-col, alt) = (
  table: table,
  build: th => {
    let s = blank-snapshot()
    s = with-node(s, box-key(from-col, L), (stroke: th.op.search-stroke))
    s = with-node(s, box-key(to-col, L), (stroke: th.op.attention-stroke))
    with-edge(s, forward-key(from-col, L), (stroke: th.op.search-stroke))
  },
  caption: [#next-key < #key #sym.arrow right],
  step: (kind: "advance", level: L),
  alt: alt,
)

// One step down a lane where nothing happens: the box under the cursor and
// the one below it light up.
#let _descend-spec(table, lvl, at-col, alt) = (
  table: table,
  build: th => {
    let s = blank-snapshot()
    s = with-node(s, box-key(at-col, lvl), (stroke: th.op.search-stroke))
    if lvl > 0 {
      s = with-node(s, box-key(at-col, lvl - 1), (stroke: th.op.search-stroke))
    }
    s
  },
  caption: [level #lvl #sym.arrow drop],
  step: (kind: "drop", level: lvl),
  alt: alt,
)

// ===================================================================
// Insert
// ===================================================================
//
// Interleaved single-pass insert. The descent visits the new node's
// predecessor on every lane it will occupy, top to bottom, so the splice
// happens *as the search reaches each lane*. The new node stays a ghost — its
// slot reserved so the grid does not shift, nothing drawn — until the descent
// first drops onto its top lane, where it materializes; each drop onto a
// lower lane then splices it in there, raising its linked range from the top
// by lowering `link-min` from `height` toward 0.

// The new node appearing: its slot has been reserved (ghosted) since the
// first frame, so this only turns the drawing on. Emitted on the descent's
// first contact with a lane the tower occupies.
#let _materialize-spec(table, key, height, new-col) = (
  table: table,
  build: th => {
    let s = blank-snapshot()
    for LL in range(height) {
      s = with-node(s, box-key(new-col, LL), (stroke: th.op.attention-stroke))
    }
    s
  },
  caption: [new node #key, height #height],
  step: (kind: "materialize", key: key, height: height),
  alt: "Create the node "
    + str(key)
    + " with a tower of height "
    + str(height)
    + "; splice it in from the top lane down as the search descends.",
)

// The pointer surgery on one lane: `update[L]` now points at the new node,
// and the new node at what `update[L]` pointed to.
#let _splice-spec(table, key, lvl, new-col, upd-col) = (
  table: table,
  build: th => {
    let s = blank-snapshot()
    // The two rewired pointers: update[L] -> new, and new -> old next.
    s = with-node(s, box-key(upd-col, lvl), (stroke: th.op.search-stroke))
    s = with-edge(s, forward-key(upd-col, lvl), (stroke: th.op.success-stroke))
    s = with-edge(s, forward-key(new-col, lvl), (stroke: th.op.success-stroke))
    with-node(
      s,
      box-key(new-col, lvl),
      (fill: th.op.success-fill, stroke: th.op.settled-stroke),
    )
  },
  caption: [splice level #lvl],
  step: (kind: "splice", level: lvl),
  alt: "Splice the new node into the level-"
    + str(lvl)
    + " list as the search reaches it.",
)

#let _insert-specs(sl, key, label, height) = {
  let nodes = sl.nodes
  // The node list with the new node at its sorted position.
  let new-node = (key: key, label: label, height: height)
  let ins-pos = _find(nodes, key).pos
  let dnodes = nodes.slice(0, ins-pos) + (new-node,) + nodes.slice(ins-pos)
  let new-col = _col(ins-pos)

  // Everyone, the new node included, at full height. Walking with it PRESENT
  // lands each drop's `at` on its true predecessor at every lane it occupies
  // — and makes the descent cover all `height` lanes even when the tower is
  // taller than the current list — while the frames still draw it ghosted
  // until it materializes.
  let full-links = dnodes.map(nd => nd.height)
  let ghost-cols = _mk-cols(
    dnodes,
    dnodes.enumerate().map(((j, _nd)) => if j == ins-pos { "ghost" } else { "live" }),
    full-links,
    sl.nil,
  )
  // The new node live, with its linked range [lmin, height); `lmin = height`
  // means materialized but not yet spliced anywhere.
  let live-cols(lmin) = _mk-cols(
    dnodes,
    dnodes.map(_ => "live"),
    full-links,
    sl.nil,
    mins: dnodes.enumerate().map(((j, _nd)) => if j == ins-pos { lmin } else { 0 }),
  )

  let w = search-walk(dnodes, full-links, key)

  // The search starts on the header's top *drawn* box — the existing list
  // height, not `w.levels`, which counts the taller-than-list new node whose
  // top lanes are not drawn until it materializes.
  let start-top = if nodes.len() == 0 {
    0
  } else { calc.max(1, ..nodes.map(nd => nd.height)) - 1 }
  let specs = ((
    table: _mk-table(ghost-cols),
    build: th => _styled(box-key(0, start-top), stroke: th.op.search-stroke),
    caption: [insert #key],
    step: (kind: "init", key: key, height: height),
    alt: alt-intro(
      _DS,
      describe(sl),
      "insert " + str(key) + " with a tower of height " + str(height),
    ),
  ),)

  let materialized = false
  let lmin = height // linked range [lmin, height); starts fully unlinked
  for mv in w.path {
    let L = mv.level
    if mv.kind == "advance" {
      // Below the new node's top lane it is already materialized.
      specs.push(_advance-spec(
        if materialized { _mk-table(live-cols(lmin)) } else {
          _mk-table(ghost-cols)
        },
        dnodes.at(mv.to).key,
        key,
        L,
        _col(mv.from),
        _col(mv.to),
        "Advance right at level "
          + str(L)
          + " while the next key is below "
          + str(key)
          + ".",
      ))
    } else {
      let at-col = _col(mv.at)
      let lvl = L
      if lvl < height {
        // The descent has reached the new node's predecessor on a lane it
        // occupies: materialize on first contact, then splice here.
        if not materialized {
          materialized = true
          specs.push(_materialize-spec(
            _mk-table(live-cols(height)),
            key,
            height,
            new-col,
          ))
        }
        lmin = lvl // linked range now [lvl, height)
        specs.push(_splice-spec(
          _mk-table(live-cols(lmin)),
          key,
          lvl,
          new-col,
          at-col,
        ))
      } else {
        // Above the new node's tower: just drop, still ghosted.
        specs.push(_descend-spec(
          _mk-table(ghost-cols),
          lvl,
          at-col,
          "The new tower does not reach level " + str(lvl) + "; drop down.",
        ))
      }
    }
  }

  // The whole tower spliced in.
  specs.push((
    table: _mk-table(live-cols(0)),
    build: th => {
      let s = blank-snapshot()
      let done = (fill: th.op.success-fill, stroke: th.op.settled-stroke)
      for L in range(height) { s = with-node(s, box-key(new-col, L), done) }
      with-node(s, data-key(new-col), done)
    },
    caption: [inserted #key],
    step: (kind: "settled", key: key),
    alt: str(key) + " inserted.",
  ))
  specs
}

// A delete that misses is a single terminal frame ringing the successor —
// the node the walk fell short of — if there is one.
#let _delete-miss-spec(table, key, w) = {
  let cand-col = if w.cand == none { none } else { _col(w.cand) }
  (
    table: table,
    build: th => {
      let s = blank-snapshot()
      if cand-col != none {
        s = with-node(s, data-key(cand-col), (stroke: th.op.danger-stroke))
      }
      s
    },
    caption: [#key not found],
    step: (kind: "not-found", key: key),
    alt: str(key) + " is not in the skip list; nothing to delete.",
  )
}

// The pointer surgery on one lane: `update[L]` now points past the target,
// whose box at this level is marked for removal.
#let _unlink-spec(table, key, height, lvl, tgt-col, upd-col) = (
  table: table,
  build: th => {
    let s = blank-snapshot()
    // The bypass pointer update[L] -> (the node after the target)
    // lights up; the target's box at this level is marked for removal.
    s = with-node(s, box-key(upd-col, lvl), (stroke: th.op.search-stroke))
    s = with-edge(s, forward-key(upd-col, lvl), (stroke: th.op.success-stroke))
    with-node(s, box-key(tgt-col, lvl), (stroke: th.op.danger-stroke))
  },
  caption: if lvl == height - 1 [found #key #sym.arrow unlink level #lvl] else [unlink level #lvl],
  step: (kind: "unlink", level: lvl),
  alt: "Reached "
    + str(key)
    + " at level "
    + str(lvl)
    + "; bypass it (update["
    + str(lvl)
    + "] now points past it).",
)

// ===================================================================
// Delete
// ===================================================================
//
// Interleaved single-pass delete. The descent lands on the target's
// predecessor on every lane the target occupies, top to bottom — at level L
// the first node with key >= K is exactly the target — so each lane is
// unlinked *as the search reaches it*. The target's `link-height` shrinks
// from `height` toward 0 as its top lanes are bypassed; the tower stays
// drawn, so the node ends detached in place.

#let _delete-specs(sl, key, search) = {
  let nodes = sl.nodes
  let links = _heights(nodes)
  let w = search-walk(nodes, links, key)
  let live-states = nodes.map(_ => "live")

  // A miss stops at one frame; there is nothing to unlink.
  if not w.found {
    return (_delete-miss-spec(
      _mk-table(_mk-cols(nodes, live-states, links, sl.nil)),
      key,
      w,
    ),)
  }

  let tgt = w.cand
  let tgt-col = _col(tgt)
  let height = nodes.at(tgt).height

  // Columns with the target linked across [0, tlink): unlinking top-down
  // lowers `tlink` from `height` to 0.
  let cols-with(tlink) = _mk-cols(
    nodes,
    live-states,
    links.enumerate().map(((j, h)) => if j == tgt { tlink } else { h }),
    sl.nil,
  )

  let specs = ((
    table: _mk-table(cols-with(height)),
    build: th => _styled(box-key(0, w.levels - 1), stroke: th.op.search-stroke),
    caption: [delete #key],
    step: (kind: "init", key: key),
    alt: alt-intro(_DS, describe(sl), "delete " + str(key)),
  ),)

  let tlink = height // the target is linked across [0, tlink)
  for mv in w.path {
    let L = mv.level
    if mv.kind == "advance" {
      specs.push(_advance-spec(
        _mk-table(cols-with(tlink)),
        nodes.at(mv.to).key,
        key,
        L,
        _col(mv.from),
        _col(mv.to),
        "Advance right at level " + str(L) + ".",
      ))
    } else {
      let at-col = _col(mv.at)
      let lvl = L
      if lvl < height {
        // The descent has reached the target's predecessor on a lane it
        // occupies: bypass it here, top-down.
        tlink = lvl
        specs.push(_unlink-spec(
          _mk-table(cols-with(tlink)),
          key,
          height,
          lvl,
          tgt-col,
          at-col,
        ))
      } else {
        // Above the target's tower: just drop.
        specs.push(_descend-spec(
          _mk-table(cols-with(tlink)),
          lvl,
          at-col,
          str(key) + " is not on level " + str(lvl) + "; drop down.",
        ))
      }
    }
  }

  // The target fully detached, shown removed in place.
  specs.push((
    table: _mk-table(cols-with(0)),
    build: th => {
      let s = blank-snapshot()
      for L in range(height) {
        s = with-node(s, box-key(tgt-col, L), (stroke: th.op.danger-stroke))
      }
      with-node(s, data-key(tgt-col), (stroke: th.op.danger-stroke))
    },
    caption: [deleted #key],
    step: (kind: "deleted", key: key),
    alt: str(key) + " unlinked at every level and removed.",
  ))

  // `search: false` drops the pure navigation frames. The surgery is
  // interleaved with the descent, so what is left is the init frame, one
  // unlink per lane, and the terminal — the pointer changes without the walk
  // that found them.
  if search {
    specs
  } else {
    specs.filter(s => not ("advance", "drop").contains(s.step.kind))
  }
}

// ===================================================================
// Displays
// ===================================================================
//
// `cell-width` sizes the boxes: `"fit"` (the default here) grows them to the
// widest label the animation will ever show, `auto` keeps the fixed footprint
// and never measures, and a number pins an exact width. `"fit"` is safe as a
// default only because these always render inside the `slides.typ` helpers'
// `context`, where `measure` is available.

/// The skip list as a single static frame.
/// -> array
#let display(sl, theme: (:), cell-width: "fit") = _frames(
  _stamp-result(_static-specs(sl), sl),
  theme,
  cell-width,
)

/// Animate the top-left search descent for `key`, leaving the whole walk lit
/// behind it.
/// -> array
#let search-display(sl, key, theme: (:), cell-width: "fit") = _frames(
  _stamp-result(_search-specs(sl, key), sl),
  theme,
  cell-width,
)

/// Animate inserting `key`: the descent, with the new node's column reserved
/// as a ghost, then its tower materializing and splicing into one lane per
/// frame. `height` is explicit or the seeded coin flip the pure `insert`
/// would have picked.
/// -> array
#let insert-display(
  sl,
  key,
  label: auto,
  height: none,
  theme: (:),
  cell-width: "fit",
) = {
  let plan = _plan-insert(
    sl.nodes,
    sl.rng-state,
    sl.max-level,
    sl.p,
    key,
    label,
    height,
  )
  _frames(
    _stamp-result(
      _insert-specs(sl, key, label, plan.height),
      insert(sl, key, label: label, height: height),
    ),
    theme,
    cell-width,
  )
}

/// Animate deleting `key`: the descent unlinking each of the target's lanes
/// as it reaches them, leaving the node detached in place. A miss ends on a
/// single danger frame. `search: false` drops the navigation frames and shows
/// only the pointer surgery.
/// -> array
#let delete-display(sl, key, search: true, theme: (:), cell-width: "fit") = _frames(
  _stamp-result(_delete-specs(sl, key, search), delete(sl, key)),
  theme,
  cell-width,
)
