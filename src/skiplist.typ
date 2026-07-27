// Skip list — the `Skiplist` typsy class, the `skiplist(..)` factory, and
// the per-DS theme. Rides on the skip-list draw backend in
// `skiplist-draw.typ` (the analog of how `sort.typ` rides on
// `array-draw.typ` and `hashmap.typ` on `hashmap-draw.typ`).
//
// A skip list is a sorted set of integer keys stored as a probabilistic
// multi-level linked list: every key sits at level 0, and each also rises
// through a random tower of "express lanes" that let a search skip ahead.
// This class stores the set as a sorted array of nodes `(key, label,
// height)` — the forward pointers need NOT be stored, because at level L
// the level-L list is exactly the subsequence of nodes with `height > L`,
// and pointers connect consecutive members. The backend derives them.
//
// The `label` rides along with the integer `key` for display only (the
// `value`/`label` split shared with `sort.typ` / `bst.typ`): the ordering
// is always by `key`, the label is what's drawn in the box.
//
// Tower heights come from one of two sources (chosen per node):
//   * EXPLICIT — the factory / `insert` is handed a `height`.
//   * SEEDED COIN FLIPS — a deterministic LCG PRNG seeded off the list's
//     `seed`, flipped with probability `p` (default 1/2), capped at
//     `max-level`. Deterministic, so visual-regression refs are stable.
//
// It animates `search` / `insert` / `delete`. Insert reserves the
// new node's column (drawn as a ghost) during the search phase so the
// grid doesn't shift when the node appears, then splices its tower into
// the list one level at a time; delete unlinks the target level by level
// and leaves it detached in place.

#import "@preview/typsy:0.2.2": *
#import "./anim-core.typ" as core
#import "./skiplist-draw.typ" as sl-draw

// Resolve a `render-theme:` argument that may be `auto` (read state) or a
// partial dict (merge into default). Mirrors the same helper in the other
// DS modules.
#let _resolve-render-theme-arg(theme) = if theme == auto {
  auto
} else { core._merge-render-theme(theme) }

// ===================================================================
// Per-DS theme — the skip-list palette
// ===================================================================
//
// Structural colours (node/edge fills) come from `render-theme`;
// operation strokes (search walk, splice, unlink) from `op-theme`. This
// per-DS theme carries only what's intrinsic to a skip-list drawing: the
// header and nil sentinel shading, the small column captions, and the
// default forward-pointer colour.

/// Default skip-list palette. Pass a partial dict to
/// #raw("set-skiplist-theme(..)") to override individual roles.
#let default-skiplist-theme = (
  header-fill: rgb("#eef4fb"),
  header-stroke: black,
  header-text-fill: black,
  nil-fill: rgb("#f2f2f2"),
  nil-stroke: black,
  nil-text-fill: rgb("#666666"),
  index-fill: rgb("#888888"),
  pointer-stroke: black,
)

#let _skiplist-theme-keys = (
  "header-fill",
  "header-stroke",
  "header-text-fill",
  "nil-fill",
  "nil-stroke",
  "nil-text-fill",
  "index-fill",
  "pointer-stroke",
)

/// Typsy refinement: a dictionary whose keys are a subset of the
/// skip-list theme keys. Used by #raw("set-skiplist-theme") and the
/// per-call #raw("theme:") arguments to give early errors on typos.
#let SkiplistTheme = Refine(
  Dictionary(..Any),
  d => d.keys().all(k => _skiplist-theme-keys.contains(k)),
)

#let _skiplist-theme-state = state("starling:skiplist-theme", default-skiplist-theme)

/// Override one or more skip-list theme keys for the rest of the document
/// (state-based, scoped by Typst's normal layout flow). Pass a partial
/// dictionary — only the keys you list are changed. Unknown keys panic.
#let set-skiplist-theme(theme) = {
  for k in theme.keys() {
    if not _skiplist-theme-keys.contains(k) {
      panic(
        "set-skiplist-theme: unknown key '"
          + k
          + "'. Valid keys: "
          + _skiplist-theme-keys.join(", ")
          + ".",
      )
    }
  }
  _skiplist-theme-state.update(prev => {
    let next = prev
    for (k, v) in theme.pairs() { next.insert(k, v) }
    next
  })
}

// Merge a partial skip-list-theme override into `default-skiplist-theme`,
// panicking on unknown keys. Used by per-call `theme:` arguments.
#let _merge-skiplist-theme(override) = {
  for k in override.keys() {
    if not _skiplist-theme-keys.contains(k) {
      panic(
        "skiplist-theme: unknown key '"
          + k
          + "'. Valid keys: "
          + _skiplist-theme-keys.join(", ")
          + ".",
      )
    }
  }
  let next = default-skiplist-theme
  for (k, v) in override.pairs() { next.insert(k, v) }
  next
}

#let _resolve-skiplist-theme-arg(theme) = if theme == auto {
  auto
} else { _merge-skiplist-theme(theme) }

// The render-theme dict `draw-skiplist` consumes is the merged
// render-theme plus the skip-list palette laid on top (the backend reads
// both key families off one dict). Combine them here.
#let _combined-render-theme(rt, st) = {
  let out = rt
  for (k, v) in st.pairs() { out.insert(k, v) }
  out
}

// ===================================================================
// Deterministic PRNG (Typst has no built-in RNG)
// ===================================================================
//
// A tiny linear congruential generator. The multiplier/increment/modulus
// are the classic glibc `rand()` constants; `state` stays in `[0, 2^31)`,
// well inside Typst's 64-bit ints even after the multiply.

#let _lcg-next(s) = calc.rem(s * 1103515245 + 12345, 2147483648)

// Flip a coin tower: start at height 1, and while a fresh flip comes up
// "heads" (uniform draw < `p`) and we're below `max-level`, grow one more
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
// Node helpers (module-level)
// ===================================================================
//
// A node is `(key: int, label: any, height: int)`. `nodes` is kept sorted
// strictly ascending by `key`.

// The *visible* display value of a node (a cell body): the label when
// set, else the integer key wrapped to content. Returns content.
#let _disp-val(nd) = if nd.label == auto { [#nd.key] } else { nd.label }

// String reference to a node for captions / alt text: the label when it's
// a plain string, else the key (the `tree-anim._alt-label` rule).
#let _disp(nd) = if type(nd.label) == str { nd.label } else { str(nd.key) }

// Per-node tower heights (the natural link heights of the full list).
#let _heights(nodes) = nodes.map(nd => nd.height)

// The column index a data node at array index `idx` maps to (0 = header,
// so data nodes start at 1). `idx == -1` denotes the header itself.
#let _col(idx) = if idx == -1 { 0 } else { idx + 1 }

// Find `key` in the sorted `nodes`: returns `(present: bool, pos: int)`
// where `pos` is the index of the key (present) or the insertion point
// (absent — the first index whose key exceeds `key`).
#let _find(nodes, key) = {
  for (i, nd) in nodes.enumerate() {
    if nd.key == key { return (present: true, pos: i) }
    if nd.key > key { return (present: false, pos: i) }
  }
  (present: false, pos: nodes.len())
}

// The next node index strictly after `i` that is linked at level `L`
// (i.e. `links[j] > L`), or `none`. `i == -1` starts the scan at 0 (the
// header's successor).
#let _next-at(nodes, links, i, L) = {
  for j in range(i + 1, nodes.len()) {
    if links.at(j) > L { return j }
  }
  none
}

// The classic skip-list search over `nodes`, using per-node `links`
// (linked height; `links[j] > L` ⟺ node j participates at level L —
// letting an insert search ignore the not-yet-spliced new node by giving
// it link 0). Descends from the top level, moving right while the next
// node's key is below `key`, dropping a level when it would overshoot.
// Returns:
//   found  — bool
//   update — per-level array of the node index whose level-L pointer
//            precedes the search position (−1 = header)
//   path   — animation moves: (kind: "advance"|"drop", level, ...)
//   cand   — the node index the search lands before at level 0 (the hit
//            when `found`, else the successor / `none`)
//   levels — number of levels considered
#let _search-walk(nodes, links, key) = {
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
  let found = cand != none and nodes.at(cand).key == key
  (found: found, update: update, path: path, cand: cand, levels: levels)
}

// Plan an insert of `key` on `nodes` (rng threaded through `state`):
// returns whether the key is already present, the sorted insertion `pos`,
// the resolved tower `height`, the new node record, and the advanced rng
// `state'`. Shared by the pure op and the display so both agree on the
// height. Explicit `height` (capped at `max-level`) wins; otherwise flip.
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
  } else {
    (calc.max(1, calc.min(height, max-level)), state)
  }
  (present: false, pos: f.pos, height: h, node: (key: key, label: label, height: h), state: s2)
}

// ===================================================================
// Positioned-table + frame plumbing
// ===================================================================

// Build the backend column array from a display-node list plus per-node
// `state` ("live"/"ghost") and `link` (linked height). Prepends the
// header and (optionally) appends the nil sentinel.
#let _mk-cols(dnodes, states, links, nil-flag) = {
  let cols = ((kind: "header", height: 1, state: "live", link-height: 0),)
  for (j, nd) in dnodes.enumerate() {
    cols.push((
      kind: "data",
      height: nd.height,
      key: nd.key,
      label: _disp-val(nd),
      state: states.at(j),
      link-height: links.at(j),
    ))
  }
  if nil-flag { cols.push((kind: "nil", height: 1, state: "live", link-height: 0)) }
  cols
}

#let _mk-table(cols) = (cols: cols, cell-width: auto, measure-cells: ())

// Build Frame records from per-frame specs (the `_sort-make-frames-multi`
// analog). Each spec carries `table`, `build: (op-theme, render-theme) =>
// Snapshot`, and `caption`/`step`/`alt`. `sl-theme` / `render-theme` are
// pre-resolved (`auto` => read state at render time); op-theme is always
// the `op-arg` the lib helpers resolve and pass in. The render-theme
// handed to the backend and the snapshot builder is the render theme with
// the skip-list palette merged on top.
#let _sl-make-frames-multi(specs, sl-theme, render-theme, cell-width: "fit") = {
  // Global measurement set: the distinct data-box labels (plus the nil
  // sentinel) across ALL frames, so "fit" sizing measures one superset and
  // the box size — and canvas footprint — stays constant frame to frame.
  let seen = (:)
  let measure-cells = ()
  for s in specs {
    for col in s.table.cols {
      let v = if col.kind == "data" {
        col.label
      } else if col.kind == "nil" { "NIL" } else { none }
      if v != none {
        let cell = (value: v)
        let key = repr(cell)
        if key not in seen {
          seen.insert(key, true)
          measure-cells.push(cell)
        }
      }
    }
  }
  specs.map(s => (core.Frame.new)(
    _builder: (
      fn: (op-arg, rt-arg) => {
        let st = if sl-theme == auto {
          _skiplist-theme-state.get()
        } else { sl-theme }
        let rt = if render-theme == auto { rt-arg } else { render-theme }
        let combined = _combined-render-theme(rt, st)
        let snap = (s.build)(op-arg, combined)
        let table = s.table
        table.cell-width = cell-width
        table.measure-cells = measure-cells
        core._make-canvas(
          sl-draw._draw-skiplist-backend,
          table,
          snap,
          (:),
          (:),
          combined,
        )
      },
    ),
    caption: s.caption,
    step: s.step,
    alt: s.alt,
  ))
}

// A blank snapshot with one box styled — keeps spec build closures terse.
#let _styled(key, ..style) = {
  let s = core.blank-snapshot()
  (s.style-node)(key, ..style)
}

// ===================================================================
// Static + search specs
// ===================================================================

#let _static-specs(nodes, nil-flag) = {
  let states = nodes.map(_ => "live")
  let links = _heights(nodes)
  let cols = _mk-cols(nodes, states, links, nil-flag)
  ((
    table: _mk-table(cols),
    build: (_op, _rt) => core.blank-snapshot(),
    caption: none,
    step: (kind: "static"),
    alt: "Skip list ["
      + nodes.map(nd => _disp(nd) + "(h" + str(nd.height) + ")").join(", ")
      + "].",
  ),)
}

// Highlight the "current" box of the walk plus, for an advance, the
// traversed forward pointer and the box moved onto.
#let _search-specs(nodes, nil-flag, key) = {
  let states = nodes.map(_ => "live")
  let links = _heights(nodes)
  let cols = _mk-cols(nodes, states, links, nil-flag)
  let w = _search-walk(nodes, links, key)
  let table = _mk-table(cols)

  let base-alt = (
    "Skip list ["
      + nodes.map(_disp).join(", ")
      + "]. Search for "
      + str(key)
      + " from the top-left."
  )

  let specs = ((
    table: table,
    build: (op, _rt) => _styled(
      sl-draw.sl-box-key(0, w.levels - 1),
      stroke: op.search-stroke,
    ),
    caption: [search #key],
    step: (kind: "init", levels: w.levels),
    alt: base-alt,
  ),)

  for mv in w.path {
    if mv.kind == "advance" {
      let L = mv.level
      let from-col = _col(mv.from)
      let to-col = _col(mv.to)
      let to-key = nodes.at(mv.to).key
      specs.push((
        table: table,
        build: (op, _rt) => {
          let s = core.blank-snapshot()
          s = (s.style-node)(sl-draw.sl-box-key(from-col, L), stroke: op.search-stroke)
          s = (s.style-node)(sl-draw.sl-box-key(to-col, L), stroke: op.attention-stroke)
          s = (s.style-edge)(sl-draw.sl-forward-key(from-col, L), stroke: op.search-stroke)
          s
        },
        caption: [#to-key < #key #sym.arrow right],
        step: (kind: "advance", level: L),
        alt: str(to-key) + " < " + str(key) + ": move right at level " + str(L) + ".",
      ))
    } else {
      let L = mv.level
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
      specs.push((
        table: table,
        build: (op, _rt) => {
          let s = core.blank-snapshot()
          s = (s.style-node)(sl-draw.sl-box-key(at-col, lvl), stroke: op.search-stroke)
          if nxt-col != none {
            s = (s.style-node)(sl-draw.sl-box-key(nxt-col, lvl), stroke: op.attention-stroke)
          }
          if lvl > 0 {
            s = (s.style-node)(sl-draw.sl-box-key(at-col, lvl - 1), stroke: op.search-stroke)
          }
          s
        },
        caption: cap,
        step: (kind: "drop", level: lvl),
        alt: if nxt == none {
          "Nothing more at level " + str(lvl) + "; drop down."
        } else {
          str(nodes.at(nxt).key) + " ≥ " + str(key) + " at level " + str(lvl) + "; drop down."
        },
      ))
    }
  }

  // Terminal frame: found (ring the whole tower) or miss (danger).
  if w.found {
    let cand = w.cand
    let cand-col = _col(cand)
    let h = nodes.at(cand).height
    specs.push((
      table: table,
      build: (op, _rt) => {
        let s = core.blank-snapshot()
        for L in range(h) {
          s = (s.style-node)(
            sl-draw.sl-box-key(cand-col, L),
            fill: op.success-fill,
            stroke: op.settled-stroke,
          )
        }
        s
      },
      caption: [found #key],
      step: (kind: "found", key: key),
      alt: "Found " + str(key) + ".",
    ))
  } else {
    let cand = w.cand
    let cand-col = if cand == none { none } else { _col(cand) }
    specs.push((
      table: table,
      build: (op, _rt) => {
        let s = core.blank-snapshot()
        if cand-col != none {
          s = (s.style-node)(sl-draw.sl-box-key(cand-col, 0), stroke: op.danger-stroke)
        }
        s
      },
      caption: [#key not found],
      step: (kind: "not-found", key: key),
      alt: str(key) + " is not in the skip list.",
    ))
  }
  specs
}

// ===================================================================
// Insert specs
// ===================================================================

// `ins-pos` is the index the new node occupies in the union `dnodes`;
// `height` its tower height. During the search phase the new node is a
// ghost (link 0), so the walk routes as if it weren't there; then it
// materializes and its links climb 0 -> height, splicing one level per
// frame.
#let _insert-specs(nodes, nil-flag, key, label, height) = {
  // Union node list with the new node inserted at its sorted position.
  let new-node = (key: key, label: label, height: height)
  let dnodes = ()
  let ins-pos = _find(nodes, key).pos
  for (i, nd) in nodes.enumerate() {
    if i == ins-pos { dnodes.push(new-node) }
    dnodes.push(nd)
  }
  if ins-pos == nodes.len() { dnodes.push(new-node) }
  let new-col = _col(ins-pos)

  // Search-phase links: everyone at full height, the new node ghosted (0).
  let search-links = dnodes.enumerate().map(((j, nd)) => if j == ins-pos { 0 } else { nd.height })
  let ghost-states = dnodes.enumerate().map(((j, _nd)) => if j == ins-pos { "ghost" } else { "live" })
  let live-states = dnodes.map(_ => "live")

  let w = _search-walk(dnodes, search-links, key)

  let base-alt = (
    "Skip list ["
      + nodes.map(_disp).join(", ")
      + "]. Insert "
      + str(key)
      + " (tower height "
      + str(height)
      + ")."
  )

  // --- search phase (new node ghosted) ---
  let search-cols = _mk-cols(dnodes, ghost-states, search-links, nil-flag)
  let search-table = _mk-table(search-cols)
  let specs = ((
    table: search-table,
    build: (op, _rt) => _styled(sl-draw.sl-box-key(0, w.levels - 1), stroke: op.search-stroke),
    caption: [insert #key],
    step: (kind: "init", key: key, height: height),
    alt: base-alt,
  ),)
  for mv in w.path {
    if mv.kind == "advance" {
      let L = mv.level
      let from-col = _col(mv.from)
      let to-col = _col(mv.to)
      specs.push((
        table: search-table,
        build: (op, _rt) => {
          let s = core.blank-snapshot()
          s = (s.style-node)(sl-draw.sl-box-key(from-col, L), stroke: op.search-stroke)
          s = (s.style-node)(sl-draw.sl-box-key(to-col, L), stroke: op.attention-stroke)
          s = (s.style-edge)(sl-draw.sl-forward-key(from-col, L), stroke: op.search-stroke)
          s
        },
        caption: [#dnodes.at(mv.to).key < #key #sym.arrow right],
        step: (kind: "advance", level: L),
        alt: "Advance right at level " + str(L) + " while the next key is below " + str(key) + ".",
      ))
    } else {
      let L = mv.level
      let at-col = _col(mv.at)
      let lvl = L
      specs.push((
        table: search-table,
        build: (op, _rt) => {
          let s = core.blank-snapshot()
          s = (s.style-node)(sl-draw.sl-box-key(at-col, lvl), stroke: op.search-stroke)
          if lvl > 0 {
            s = (s.style-node)(sl-draw.sl-box-key(at-col, lvl - 1), stroke: op.search-stroke)
          }
          s
        },
        caption: if lvl == 0 [record update, level 0] else [record update #sym.arrow drop],
        step: (kind: "drop", level: lvl, update: _col(mv.at)),
        alt: "Record the update pointer at level " + str(lvl) + ", then drop down.",
      ))
    }
  }

  // --- materialize the new tower (still unlinked: link 0) ---
  let mat-cols = _mk-cols(dnodes, live-states, dnodes.enumerate().map(((j, nd)) => if j == ins-pos { 0 } else { nd.height }), nil-flag)
  specs.push((
    table: _mk-table(mat-cols),
    build: (op, _rt) => {
      let s = core.blank-snapshot()
      for L in range(height) {
        s = (s.style-node)(sl-draw.sl-box-key(new-col, L), stroke: op.attention-stroke)
      }
      s
    },
    caption: [new node #key, height #height],
    step: (kind: "materialize", key: key, height: height),
    alt: "Create the node "
      + str(key)
      + " with a tower of height "
      + str(height)
      + "; now splice it in level by level.",
  ))

  // --- splice one level per frame (link climbs 0 -> height) ---
  for L in range(height) {
    let link = L + 1
    let cur-links = dnodes.enumerate().map(((j, nd)) => if j == ins-pos { link } else { nd.height })
    let cols = _mk-cols(dnodes, live-states, cur-links, nil-flag)
    let upd-col = _col(w.update.at(L))
    let lvl = L
    specs.push((
      table: _mk-table(cols),
      build: (op, _rt) => {
        let s = core.blank-snapshot()
        // The two rewired pointers: update[L] -> new, and new -> old next.
        s = (s.style-edge)(sl-draw.sl-forward-key(upd-col, lvl), stroke: op.success-stroke)
        s = (s.style-edge)(sl-draw.sl-forward-key(new-col, lvl), stroke: op.success-stroke)
        s = (s.style-node)(sl-draw.sl-box-key(new-col, lvl), fill: op.success-fill, stroke: op.settled-stroke)
        s
      },
      caption: [splice level #lvl],
      step: (kind: "splice", level: lvl),
      alt: "Splice the new node into the level-" + str(lvl) + " list.",
    ))
  }

  // --- settled ---
  let final-cols = _mk-cols(dnodes, live-states, _heights(dnodes), nil-flag)
  specs.push((
    table: _mk-table(final-cols),
    build: (op, _rt) => {
      let s = core.blank-snapshot()
      for L in range(height) {
        s = (s.style-node)(sl-draw.sl-box-key(new-col, L), fill: op.success-fill, stroke: op.settled-stroke)
      }
      s
    },
    caption: [inserted #key],
    step: (kind: "settled", key: key),
    alt: str(key) + " inserted.",
  ))
  specs
}

// ===================================================================
// Delete specs
// ===================================================================

#let _delete-specs(nodes, nil-flag, key) = {
  let links = _heights(nodes)
  let w = _search-walk(nodes, links, key)
  let live-states = nodes.map(_ => "live")

  let base-alt = (
    "Skip list ["
      + nodes.map(_disp).join(", ")
      + "]. Delete "
      + str(key)
      + "."
  )

  // Miss: single terminal frame ringing the successor (or nothing).
  if not w.found {
    let cols = _mk-cols(nodes, live-states, links, nil-flag)
    let cand-col = if w.cand == none { none } else { _col(w.cand) }
    return ((
      table: _mk-table(cols),
      build: (op, _rt) => {
        let s = core.blank-snapshot()
        if cand-col != none {
          s = (s.style-node)(sl-draw.sl-box-key(cand-col, 0), stroke: op.danger-stroke)
        }
        s
      },
      caption: [#key not found],
      step: (kind: "not-found", key: key),
      alt: str(key) + " is not in the skip list; nothing to delete.",
    ),)
  }

  let tgt = w.cand
  let tgt-col = _col(tgt)
  let height = nodes.at(tgt).height

  // --- search phase ---
  let search-cols = _mk-cols(nodes, live-states, links, nil-flag)
  let search-table = _mk-table(search-cols)
  let specs = ((
    table: search-table,
    build: (op, _rt) => _styled(sl-draw.sl-box-key(0, w.levels - 1), stroke: op.search-stroke),
    caption: [delete #key],
    step: (kind: "init", key: key),
    alt: base-alt,
  ),)
  for mv in w.path {
    if mv.kind == "advance" {
      let L = mv.level
      let from-col = _col(mv.from)
      let to-col = _col(mv.to)
      specs.push((
        table: search-table,
        build: (op, _rt) => {
          let s = core.blank-snapshot()
          s = (s.style-node)(sl-draw.sl-box-key(from-col, L), stroke: op.search-stroke)
          s = (s.style-node)(sl-draw.sl-box-key(to-col, L), stroke: op.attention-stroke)
          s = (s.style-edge)(sl-draw.sl-forward-key(from-col, L), stroke: op.search-stroke)
          s
        },
        caption: [#nodes.at(mv.to).key < #key #sym.arrow right],
        step: (kind: "advance", level: L),
        alt: "Advance right at level " + str(L) + ".",
      ))
    } else {
      let L = mv.level
      let at-col = _col(mv.at)
      let lvl = L
      specs.push((
        table: search-table,
        build: (op, _rt) => {
          let s = core.blank-snapshot()
          s = (s.style-node)(sl-draw.sl-box-key(at-col, lvl), stroke: op.search-stroke)
          if lvl > 0 {
            s = (s.style-node)(sl-draw.sl-box-key(at-col, lvl - 1), stroke: op.search-stroke)
          }
          s
        },
        caption: if lvl == 0 [found target] else [record update #sym.arrow drop],
        step: (kind: "drop", level: lvl),
        alt: "Record the update pointer at level " + str(lvl) + ".",
      ))
    }
  }

  // --- unlink top-down (link shrinks height -> 0) ---
  for L in range(height - 1, -1, step: -1) {
    let link = L
    let cur-links = links.enumerate().map(((j, h)) => if j == tgt { link } else { h })
    let cols = _mk-cols(nodes, live-states, cur-links, nil-flag)
    let upd-col = _col(w.update.at(L))
    let lvl = L
    specs.push((
      table: _mk-table(cols),
      build: (op, _rt) => {
        let s = core.blank-snapshot()
        // The bypass pointer update[L] -> (node after target) lights up;
        // the target's box at this level is marked for removal.
        s = (s.style-edge)(sl-draw.sl-forward-key(upd-col, lvl), stroke: op.success-stroke)
        s = (s.style-node)(sl-draw.sl-box-key(tgt-col, lvl), stroke: op.danger-stroke)
        s
      },
      caption: [unlink level #lvl],
      step: (kind: "unlink", level: lvl),
      alt: "Bypass the target at level " + str(lvl) + " (update[" + str(lvl) + "] now points past it).",
    ))
  }

  // --- settled: target fully detached, shown removed in place ---
  let detached-links = links.enumerate().map(((j, h)) => if j == tgt { 0 } else { h })
  let cols = _mk-cols(nodes, live-states, detached-links, nil-flag)
  specs.push((
    table: _mk-table(cols),
    build: (op, _rt) => {
      let s = core.blank-snapshot()
      for L in range(height) {
        s = (s.style-node)(sl-draw.sl-box-key(tgt-col, L), stroke: op.danger-stroke)
      }
      s
    },
    caption: [deleted #key],
    step: (kind: "deleted", key: key),
    alt: str(key) + " unlinked at every level and removed.",
  ))
  specs
}

// ===================================================================
// Skiplist class
// ===================================================================

/// Typsy class wrapping a skip list: a sorted set of non-negative integer
/// keys (field #raw("nodes"), each #raw("(key, label, height)")), a coin
/// #raw("seed") + advancing #raw("rng-state"), a tower #raw("max-level")
/// cap, the flip probability #raw("p"), and whether to draw the
/// #raw("nil") tail sentinel. Ordering is by #raw("key"); the
/// #raw("label") rides along for display (the #raw("value")/#raw("label")
/// split shared with #raw("BST")). Build one via the @@skiplist() factory. The
/// #raw("*-display") methods return #raw("Array(Frame)").
#let Skiplist = class(
  name: "Skiplist",
  fields: (
    nodes: Array(..Any),
    max-level: Int,
    seed: Int,
    rng-state: Int,
    nil: Bool,
    p: Any,
  ),
  methods: (
    len: (self) => self.nodes.len(),
    // Current number of levels the list reaches (tallest tower, min 1).
    levels: (self) => if self.nodes.len() == 0 {
      1
    } else { calc.max(1, ..self.nodes.map(nd => nd.height)) },
    // The sorted keys (the correctness oracle).
    keys: (self) => self.nodes.map(nd => nd.key),
    contains: (self, key) => _search-walk(self.nodes, _heights(self.nodes), key).found,
    // The label stored at `key`, or `none` if absent.
    get: (self, key) => {
      let f = _find(self.nodes, key)
      if f.present { self.nodes.at(f.pos).label } else { none }
    },
    // Insert `key` (updating the label in place if already present).
    // `height` is explicit (capped at `max-level`) or a seeded coin flip.
    // Returns a new `Skiplist` (rng advanced when a flip happened).
    insert: (self, key, label: auto, height: none) => {
      let plan = _plan-insert(self.nodes, self.rng-state, self.max-level, self.p, key, label, height)
      let next-nodes = if plan.present {
        let nn = self.nodes
        nn.at(plan.pos) = plan.node
        nn
      } else {
        self.nodes.slice(0, plan.pos) + (plan.node,) + self.nodes.slice(plan.pos)
      }
      (self.meta.cls.new)(
        nodes: next-nodes,
        max-level: self.max-level,
        seed: self.seed,
        rng-state: plan.state,
        nil: self.nil,
        p: self.p,
      )
    },
    // Delete `key`. Returns a new `Skiplist` (unchanged if absent).
    delete: (self, key) => {
      let f = _find(self.nodes, key)
      if not f.present { return self }
      (self.meta.cls.new)(
        nodes: self.nodes.slice(0, f.pos) + self.nodes.slice(f.pos + 1),
        max-level: self.max-level,
        seed: self.seed,
        rng-state: self.rng-state,
        nil: self.nil,
        p: self.p,
      )
    },
    describe: (self) => if self.nodes.len() == 0 {
      "skip list []"
    } else {
      (
        "skip list ["
          + self.nodes.map(nd => _disp(nd) + "(h" + str(nd.height) + ")").join(", ")
          + "]"
      )
    },
    // Structural invariants: keys strictly ascending non-negative ints,
    // each height in 1..max-level.
    check-invariants: (self) => {
      let prev = none
      for nd in self.nodes {
        assert(type(nd.key) == int, message: "check-invariants: keys must be integers.")
        assert(nd.key >= 0, message: "check-invariants: keys must be non-negative.")
        if prev != none {
          assert(nd.key > prev, message: "check-invariants: keys must be strictly ascending (unique).")
        }
        prev = nd.key
        assert(
          nd.height >= 1 and nd.height <= self.max-level,
          message: "check-invariants: tower heights must be in 1..max-level.",
        )
      }
      true
    },
    // The positioned-table dict the backend consumes (the `Graph.positioned`
    // / `HashMap.positioned` analog) — feed it to `draw-skiplist` for
    // hand-composed cetz canvases.
    positioned: (self, cell-width: auto) => {
      let states = self.nodes.map(_ => "live")
      let cols = _mk-cols(self.nodes, states, _heights(self.nodes), self.nil)
      (cols: cols, cell-width: cell-width, measure-cells: ())
    },
    // -----------------------------------------------------------------
    // Display methods
    // -----------------------------------------------------------------
    // Static skip list, no operation styling.
    display: (self, theme: auto, render-theme: auto, cell-width: "fit") => _sl-make-frames-multi(
      _static-specs(self.nodes, self.nil),
      _resolve-skiplist-theme-arg(theme),
      _resolve-render-theme-arg(render-theme),
      cell-width: cell-width,
    ),
    // Animate the top-left search descent for `key`.
    search-display: (self, key, theme: auto, render-theme: auto, cell-width: "fit") => _sl-make-frames-multi(
      _search-specs(self.nodes, self.nil, key),
      _resolve-skiplist-theme-arg(theme),
      _resolve-render-theme-arg(render-theme),
      cell-width: cell-width,
    ),
    // Animate inserting `key`: search (new node reserved as a ghost),
    // create its tower, then splice level by level. `height` explicit or a
    // seeded coin flip (same result the pure `insert` would pick).
    insert-display: (
      self,
      key,
      label: auto,
      height: none,
      theme: auto,
      render-theme: auto,
      cell-width: "fit",
    ) => {
      let plan = _plan-insert(self.nodes, self.rng-state, self.max-level, self.p, key, label, height)
      _sl-make-frames-multi(
        _insert-specs(self.nodes, self.nil, key, label, plan.height),
        _resolve-skiplist-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
        cell-width: cell-width,
      )
    },
    // Animate deleting `key`: search, then unlink top-down, leaving the
    // node detached in place. A miss ends on a single danger frame.
    delete-display: (self, key, theme: auto, render-theme: auto, cell-width: "fit") => _sl-make-frames-multi(
      _delete-specs(self.nodes, self.nil, key),
      _resolve-skiplist-theme-arg(theme),
      _resolve-render-theme-arg(render-theme),
      cell-width: cell-width,
    ),
  ),
)

// ===================================================================
// Factory
// ===================================================================

/// Build a @@Skiplist from a set of keys. Each element is either a bare
/// non-negative integer (its own key, with `auto` label and a seeded
/// coin-flip tower height) or a dict #raw("(value: <int>, label:
/// <content>, height: <int>)") — #raw("value") required, #raw("label")
/// and #raw("height") optional. A missing #raw("height") is chosen by a
/// deterministic coin flip off #raw("seed") (so refs are stable);
/// duplicate keys are rejected. Accepts a splat of elements
/// (#raw("skiplist(3, 1, 4)")) or a single array of them. Write
/// #raw("skiplist(3, 1, 4, 5, seed: 7)") for seeded towers, or
/// #raw("skiplist((value: 3, height: 3), ..)") to pin each height.
///
/// -> Skiplist
#let skiplist(
  /// The keys — a splat of ints and/or #raw("(value:, label:, height:)")
  /// dicts, or one array of them.
  /// -> int | dictionary
  ..args,
  /// Coin-flip seed (deterministic tower heights for any element without
  /// an explicit #raw("height")).
  /// -> int
  seed: 1,
  /// Maximum tower height (coin flips are capped here).
  /// -> int
  max-level: 4,
  /// Coin-flip probability of growing one more level (default 1/2).
  /// -> float
  p: 0.5,
  /// Whether to draw the nil tail sentinel.
  /// -> bool
  nil: true,
) = {
  let raw = args.pos()
  if raw.len() == 1 and type(raw.first()) == array { raw = raw.first() }

  // Parse elements into (key, label, explicit-height?) in input order.
  let parsed = ()
  for x in raw {
    let (key, label, h) = if type(x) == dictionary {
      assert("value" in x, message: "skiplist: an element dict must have a 'value' key.")
      for k in x.keys() {
        assert(
          k == "value" or k == "label" or k == "height",
          message: "skiplist: element dict keys must be 'value' / 'label' / 'height', got '" + k + "'.",
        )
      }
      (x.value, x.at("label", default: auto), x.at("height", default: none))
    } else {
      (x, auto, none)
    }
    assert(
      type(key) == int and key >= 0,
      message: "skiplist: keys must be non-negative integers.",
    )
    if h != none {
      assert(
        type(h) == int and h >= 1 and h <= max-level,
        message: "skiplist: an explicit height must be an integer in 1..max-level.",
      )
    }
    parsed.push((key: key, label: label, height: h))
  }

  // Resolve heights (coin-flip the unset ones, threading the rng), then
  // sort by key. Reject duplicate keys.
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
      message: "skiplist: duplicate key " + str(nodes.at(i).key) + ".",
    )
  }

  (Skiplist.new)(
    nodes: nodes,
    max-level: max-level,
    seed: seed,
    rng-state: state,
    nil: nil,
    p: p,
  )
}
