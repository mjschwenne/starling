// Git graph — a stateful, imperative cetz DSL for drawing git commit
// graphs (commits, branches, merges, tags, HEAD/branch pointers,
// detached commits, lane backgrounds).
//
// This module deliberately does NOT ride starling's `Frame` / `Renderer`
// / `*-display` stack — it is not an immutable data structure animated
// step by step, but a builder DSL whose commands (`commit`, `branch`,
// `merge`, ...) are called inside a `git-graph({ ... })` block and mutate
// cetz's canvas context (`ctx.git-graph`). Its animation story is
// touying-native: put `pause` / `alternatives(..)` markers inside the
// canvas body, or redraw a commit dot with `git-highlight`. The lib.typ
// frame helpers (`last`, `stacked`, `figures`) do not apply here.
//
// It DOES adopt starling's per-DS theme pattern: all styling defaults
// live in `default-git-theme` and are overridable document-wide with
// `set-git-theme(..)` (state) or per-call with `git-graph(theme: (..))`.
// See the RBT palette (`src/rbt.typ`) for the mirrored template.

#import "@preview/cetz:0.5.2"
#import "@preview/typsy:0.2.2": Refine, Dictionary, Any

#let d = cetz.draw

#let offset(anchor, x: 0, y: 0) = {
  (v => cetz.vector.add(v, (x, y)), anchor)
}
#let default-colors = (red, orange, yellow, green, blue, purple, fuchsia, gray)
#let color-boxed(..args) = {
  set text(0.8em)
  box(
    inset: (y: 0.25em, x: 0.1em),
    fill: yellow.lighten(80%),
    stroke: black + 0.5pt,
    radius: 0.2em,
    ..args,
  )
}
#let _default-branch-pointer-decorator(color, name) = {
  set text(0.8em, weight: "bold", fill: white)
  box(
    inset: (y: 0.25em, x: 0.3em),
    fill: color,
    stroke: black + 0.5pt,
    radius: 0.2em,
    name,
  )
}
#let _default-head-pointer-decorator() = {
  set text(0.8em, weight: "bold")
  box(
    inset: (y: 0.25em, x: 0.3em),
    fill: yellow.lighten(60%),
    stroke: black + 0.5pt,
    radius: 0.2em,
    "HEAD",
  )
}
// Negative layers render behind the default (0); positive ones in front.
#let _layers = (
  BACKGROUND-LANES: -20,
  LANES: -4,
  BRANCH: -3,
  GRAPH: -2,
  COMMIT: 1,
  TAG: 1,
)

// ===================================================================
// Per-DS theme — the git-graph styling surface
// ===================================================================
//
// Mirrors the RBT palette pattern (`default-rbt-theme` /
// `set-rbt-theme` / `RbtTheme` in `src/rbt.typ`). Only *styling* lives
// here — the branch color palette, the lane/graph strokes, and the
// commit/tag/pointer decorators and angles. Behavioral/layout config
// (`direction`, `commit-spacing`, `lane-spacing`) and live runtime
// state (`branches`, `commit-id`, ...) are NOT theme; they are
// `git-graph(..)` `..style` arguments merged in `_git-graph-behavior`.
//
// Merging is *shallow* at the top level: overriding e.g. `commit-style`
// replaces the whole sub-dict (each sub-style must be complete). This
// matches the existing `_horizontal-style-defaults` contract below.

/// Default styling theme for git graphs. Pass a partial dict to
/// #raw("set-git-theme(..)") (document-wide) or #raw("git-graph(theme: (..))")
/// (per-call) to override individual roles. Each top-level value is a
/// *complete* sub-style dict — merging is shallow.
#let default-git-theme = (
  colors: default-colors,
  lane-style: (
    stroke: (paint: gray, dash: "dashed"),
  ),
  graph-style: (
    stroke: (thickness: 0.25em),
    radius: 0.1,
  ),
  commit-style: (
    decorator: color-boxed,
    angle: 45deg,
    dot-anchor: "south-west",
    text-anchor: "east",
  ),
  tag-style: (
    decorator: color-boxed.with(fill: blue.lighten(75%), stroke: black),
    angle: -45deg,
    text-anchor: "west",
  ),
  // Pointers borrow the tag/commit-message look (boxed, tilted at `angle`)
  // and extend opposite the commit message: NE of the dot in bottom-to-top
  // mode, NW in left-to-right mode. head-pointer stacks past the active
  // branch's pointer along that diagonal (with `stack-padding` between
  // them); pass `after: none` on head-pointer to anchor it at the dot.
  pointer-style: (
    branch-decorator: _default-branch-pointer-decorator,
    head-decorator: _default-head-pointer-decorator,
    angle: 45deg,
    padding: 0.75em,
    stack-padding: 0.2em,
  ),
)

#let _git-theme-keys = (
  "colors",
  "lane-style",
  "graph-style",
  "commit-style",
  "tag-style",
  "pointer-style",
)

/// Typsy refinement: a dictionary whose keys are a subset of the
/// git-theme keys. Used by #raw("set-git-theme") and the per-call
/// #raw("theme:") argument to give early errors on typos.
#let GitTheme = Refine(
  Dictionary(..Any),
  d => d.keys().all(k => _git-theme-keys.contains(k)),
)

#let _git-theme-state = state("starling:git-theme", default-git-theme)

/// Override one or more git-theme keys for the rest of the document
/// (state-based, scoped by Typst's normal layout flow). Pass a partial
/// dictionary — only the top-level keys you list are replaced (shallow),
/// the rest stay at their current values. Unknown keys panic.
#let set-git-theme(theme) = {
  for k in theme.keys() {
    if not _git-theme-keys.contains(k) {
      panic(
        "set-git-theme: unknown key '"
          + k
          + "'. Valid keys: "
          + _git-theme-keys.join(", ")
          + ".",
      )
    }
  }
  _git-theme-state.update(prev => {
    let next = prev
    for (k, v) in theme.pairs() { next.insert(k, v) }
    next
  })
}

// Merge a partial git-theme override into `default-git-theme`, panicking
// on unknown keys. Used by the per-call `theme:` argument (the non-state
// path — no `context` needed, so it doubles as the perf escape hatch).
#let _merge-git-theme(override) = {
  for k in override.keys() {
    if not _git-theme-keys.contains(k) {
      panic(
        "git-theme: unknown key '"
          + k
          + "'. Valid keys: "
          + _git-theme-keys.join(", ")
          + ".",
      )
    }
  }
  let next = default-git-theme
  for (k, v) in override.pairs() { next.insert(k, v) }
  next
}

// Non-styling defaults merged beneath every git-graph. These are
// behavioral/layout knobs and live runtime state, NOT theme.
#let _git-graph-behavior = (
  branches: (:),
  active-branch: "main",
  commit-id: 0,
  commit-spacing: 0.8,
  ref-branch-map: (:),
  // Set of branch names for which branch-pointer has been drawn. head-pointer
  // consults this when `after: auto` to decide whether it can stack against
  // the branch pointer label or must anchor at the dot.
  pointer-drawn: (:),
  lane-spacing: 2,
  // "bottom-to-top" stacks commits upward, lanes spread to the right.
  // "left-to-right" stacks commits to the right, lanes spread downward.
  direction: "bottom-to-top",
)

// Style overrides applied when direction == "left-to-right". Each entry
// must be a complete style dict because dict merging is shallow.
#let _horizontal-style-defaults = (
  commit-style: (
    decorator: color-boxed,
    angle: -45deg,
    dot-anchor: "south",
    text-anchor: "north-west",
  ),
  tag-style: (
    decorator: color-boxed.with(fill: blue.lighten(75%), stroke: black),
    angle: 45deg,
    text-anchor: "west",
  ),
)

#let _is-horizontal(props) = props.direction == "left-to-right"

// Index of the axis along which commits progress (0 = x, 1 = y).
#let _along-axis(props) = if _is-horizontal(props) { 0 } else { 1 }
// Index of the axis along which lanes spread.
#let _across-axis(props) = if _is-horizontal(props) { 1 } else { 0 }

// Build a 2D coordinate from along/across values respecting direction.
// Across grows downward (negative y) in horizontal mode so the first lane
// stays on top.
#let _pt(props, along, across) = {
  if _is-horizontal(props) { (along, -across) } else { (across, along) }
}

#let _along-of(props, p) = p.at(_along-axis(props))
#let _across-of(props, p) = {
  let v = p.at(_across-axis(props))
  if _is-horizontal(props) { -v } else { v }
}

#let _is-empty(c) = {
  if type(c) == str { return c == "" }
  if c == [] { return true }
  c.has("text") and c.text == ""
}

#let graph-props(func) = {
  d.get-ctx(ctx => {
    let props = ctx.git-graph
    props.ctx = ctx
    func(props)
  })
}

#let set-graph-props(func) = {
  d.set-ctx(ctx => {
    ctx.git-graph = func(ctx.git-graph)
    ctx
  })
}

#let branch-props(func, branch: auto) = {
  graph-props(props => {
    let branch = branch
    if branch == auto {
      branch = props.active-branch
    }
    if branch not in props.branches {
      panic("Branch `" + branch + "` does not exist")
    }
    let sub-props = props.branches.at(branch)
    props.name = branch
    func(props + sub-props)
  })
}

#let background-lanes() = {
  graph-props(props => {
    for branch-name in props.branches.keys() {
      let (ctx, latest-commit) = cetz.coordinate.resolve(props.ctx, "head")
      let extent = _along-of(props, latest-commit) + props.commit-spacing
      // Anchor the lane at the same edge of the label box that was used to
      // place the label, so the lane aligns with the commit dots regardless
      // of label width. Using `branch-name` (center) here would shift the
      // lane by half the label width — wide labels then fall short of the
      // last commit on the along axis.
      let label-edge = if _is-horizontal(props) { "east" } else { "north" }
      let start = branch-name + "." + label-edge
      let end = if _is-horizontal(props) {
        offset(start, x: extent)
      } else {
        offset(start, y: extent)
      }
      d.on-layer(_layers.BACKGROUND-LANES, d.line(
        start,
        end,
        ..props.lane-style,
      ))
    }
  })
}

#let _branch-line(src, dst, color, name: none) = {
  // Easier than a merge line since src is guaranteed to be earlier on the
  // along-axis than dst.
  graph-props(props => {
    let ctx = props.ctx
    let (ctx, a, b) = cetz.coordinate.resolve(ctx, src, dst)
    assert(
      _along-of(props, a) < _along-of(props, b) and _across-of(props, a) <= _across-of(props, b),
      message: "source branch must start before destination branch",
    )
    let radius = props.graph-style.radius
    let stroke = (stroke: (paint: color, ..props.graph-style.stroke))
    d.merge-path(..stroke, name: name, {
      if _is-horizontal(props) {
        // Vertical line down from src, then quarter-arc that flips to going
        // right along the new lane.
        d.line(src, (a.at(0), b.at(1) + radius))
        d.arc((), start: 180deg, delta: 90deg, radius: radius)
      } else {
        d.line(src, (b.at(0) - radius, a.at(1)))
        d.arc((), start: -90deg, delta: 90deg, radius: radius)
      }
    })
  })
}

#let branch(name, color: auto, colors: auto, edge-name: none, from: auto) = {
  if type(name) != str {
    name = name.text
  }
  set-graph-props(props => {
    let branches = props.branches
    if name in branches {
      panic("Branch `" + name + "` already exists")
    }
    let color = color
    // Fall back to the themed palette (props.colors) when the caller
    // didn't pass an explicit color list.
    let colors = if colors == auto {
      props.at("colors", default: default-colors)
    } else { colors }
    let n-cur = branches.len()
    if color == auto {
      color = colors.at(calc.rem(n-cur, colors.len()))
    }
    branches.insert(name, (fill: color, lane: n-cur))
    props.branches = branches
    props.head = name
    props.active-branch = name
    props
  })
  let styled(..args) = {
    set text(weight: "bold", fill: white)
    rect(radius: 0.25em, ..args)
  }
  branch-props(props => {
    let label-anchor = if _is-horizontal(props) { "east" } else { "west" }
    d.content(
      _pt(props, 0, props.lane * props.lane-spacing),
      styled(name, fill: props.branches.at(name).fill),
      name: name,
      anchor: label-anchor,
    )
  })
  branch-props(props => {
    let new-head = name
    if props.commit-id > 0 {
      // `from:` accepts a branch name (resolves to its tip), any cetz anchor
      // name (typically a commit's custom `name:` or `commit-id-N`), or
      // `auto` for the current HEAD.
      let source = if from == auto {
        "head"
      } else if from in props.branches {
        from + "/head"
      } else {
        from
      }
      let (_, source-pos, lane-pos) = cetz.coordinate.resolve(
        props.ctx,
        source,
        name,
      )
      let parent-along = _along-of(props, source-pos)
      let new-across = _across-of(props, lane-pos)
      let join-loc = _pt(
        props,
        parent-along + props.commit-spacing,
        new-across,
      )
      new-head = _pt(props, parent-along, new-across)
      if parent-along > 0 {
        d.on-layer(-props.lane + _layers.BRANCH, _branch-line(
          source,
          join-loc,
          props.fill,
          name: edge-name,
        ))
      }
    }
    d.anchor("head", new-head)
    d.anchor(name + "/head", new-head)
  })
}

#let checkout(branch) = {
  set-graph-props(props => {
    if branch not in props.branches {
      panic("Branch `" + branch + "` does not exist")
    }
    props.active-branch = branch
    props
  })
  d.anchor("head", branch + "/head")
}

#let commit(message, branch: auto, name: none, edge-name: none) = {
  if branch != auto {
    checkout(branch)
  }
  set-graph-props(props => {
    props.commit-id = props.commit-id + 1
    props.ref-branch-map.insert(str(props.commit-id), props.active-branch)
    props
  })
  let on-graph = d.on-layer.with(_layers.GRAPH)
  let on-branch = d.on-layer.with(_layers.BRANCH)
  branch-props(props => {
    let txt = props.commit-style.at("decorator")(message)
    let (_, lane-pos) = cetz.coordinate.resolve(props.ctx, "head")
    let (_, branch-pos) = cetz.coordinate.resolve(
      props.ctx,
      props.active-branch + "/head",
    )
    // The dot's primary name gets edge anchors (.east, .north-west, ...).
    // Prefer a user-supplied name so annotations survive commit reordering.
    let dot-name = if name == none {
      "commit-id-" + str(props.commit-id)
    } else {
      name
    }
    let new-along = props.commit-id * props.commit-spacing
    let across = _across-of(props, lane-pos)
    d.anchor("head", _pt(props, new-along, across))
    on-graph(d.content(
      "head",
      circle(fill: props.fill, radius: 0.5em),
      name: dot-name,
    ))
    let rel-offset = if _is-horizontal(props) {
      (props.graph-style.radius / 2, 0)
    } else {
      (0, props.graph-style.radius / 2)
    }
    on-branch(
      d.line(
        (rel: rel-offset, to: branch-pos),
        "head",
        stroke: (paint: props.fill, ..props.graph-style.stroke),
        name: edge-name,
      ),
    )
    if not _is-empty(message) {
      let rot = props.commit-style.at("angle")
      let default-dot-anc = if _is-horizontal(props) {
        "south"
      } else {
        "south-west"
      }
      let default-text-anc = if _is-horizontal(props) {
        "north-west"
      } else {
        "east"
      }
      let dot-anc = props.commit-style.at(
        "dot-anchor",
        default: default-dot-anc,
      )
      let text-anc = props.commit-style.at(
        "text-anchor",
        default: default-text-anc,
      )
      d.content(dot-name + "." + dot-anc, txt, anchor: text-anc, angle: rot)
    }
  })
  graph-props(props => {
    d.anchor(props.active-branch + "/head", "head")
    // Always provide commit-id-N as a point alias, even when a custom name
    // owns the edge anchors.
    if name != none {
      d.anchor("commit-id-" + str(props.commit-id), "head")
    }
  })
}

#let tag(message) = {
  graph-props(props => {
    let txt = props.tag-style.at("decorator")(message)
    let rot = props.tag-style.at("angle")
    let anc = props.tag-style.at("text-anchor", default: "west")
    d.content("head", txt, anchor: anc, angle: rot, padding: 0.75em)
  })
}

// Draws a tilted colored label at the tip of `name`. Mirrors the
// commit-message decoration through the dot: same +45deg tilt, but the
// label extends NE (bottom-to-top mode) or NW (left-to-right mode).
//
// The drawn label is registered as the cetz anchor "branch-pointer-<name>"
// so head-pointer can stack against its rotated bounding box.
#let branch-pointer(name, padding: auto, anchor: auto, angle: auto) = {
  set-graph-props(props => {
    let drawn = props.pointer-drawn
    drawn.insert(name, true)
    props.pointer-drawn = drawn
    props
  })
  graph-props(props => {
    if name not in props.branches {
      panic("Branch `" + name + "` does not exist")
    }
    let style = props.pointer-style
    let color = props.branches.at(name).fill
    let txt = (style.branch-decorator)(color, name)
    let anc = if anchor == auto {
      if _is-horizontal(props) { "east" } else { "west" }
    } else { anchor }
    let rot = if angle == auto {
      // Horizontal mirrors the bottom-to-top layout 90° clockwise, which
      // negates the tilt so the label still leans away from the lane axis.
      if _is-horizontal(props) { -style.angle } else { style.angle }
    } else { angle }
    let pad = if padding == auto { style.padding } else { padding }
    d.content(
      name + "/head",
      txt,
      anchor: anc,
      angle: rot,
      padding: pad,
      name: "branch-pointer-" + name,
    )
  })
}

// Draws a "HEAD" label at the tip of `branch` (default: active branch).
// By default stacks along the rotated bounding box of `branch`'s pointer
// label (drawn by a previous `branch-pointer(branch)` call). Pass
// `after: none` to place it at the dot instead, or `after: "other"` to
// stack past a different branch's pointer.
//
// Pass `target:` (any cetz anchor name) to point HEAD at an arbitrary
// commit instead of a branch tip — useful for detached-HEAD demos.
#let head-pointer(
  branch: auto,
  target: none,
  after: auto,
  padding: auto,
  anchor: auto,
  angle: auto,
) = {
  graph-props(props => {
    let style = props.pointer-style
    let txt = (style.head-decorator)()
    let anc = if anchor == auto {
      if _is-horizontal(props) { "east" } else { "west" }
    } else { anchor }
    let rot = if angle == auto {
      if _is-horizontal(props) { -style.angle } else { style.angle }
    } else { angle }

    if target != none {
      // Detached: anchor directly at the supplied target, no branch logic.
      let pad = if padding == auto { style.padding } else { padding }
      d.content(target, txt, anchor: anc, angle: rot, padding: pad)
    } else {
      let branch = if branch == auto { props.active-branch } else { branch }
      if branch not in props.branches {
        panic("Branch `" + branch + "` does not exist")
      }
      let after = if after == auto {
        // Stack against the branch pointer only if one was actually drawn
        // for this branch earlier in the body; otherwise fall back to the
        // dot so a standalone head-pointer() just works.
        if props.pointer-drawn.at(branch, default: false) {
          branch
        } else {
          none
        }
      } else { after }
      let resolved-target = if after == none {
        branch + "/head"
      } else {
        // The branch pointer is rotated, so its bbox east (vertical) /
        // north (horizontal) lies along the diagonal we want to stack into.
        let edge = if _is-horizontal(props) { "north" } else { "east" }
        "branch-pointer-" + after + "." + edge
      }
      let default-pad = if after == none {
        style.padding
      } else {
        style.stack-padding
      }
      let pad = if padding == auto { default-pad } else { padding }
      d.content(resolved-target, txt, anchor: anc, angle: rot, padding: pad)
    }
  })
}

// Draws an orphan commit dot offset from `from` (a cetz anchor — typically
// a `commit-id-N` or a custom commit `name:`). The dot is colored `color`
// (gray by default to suggest it is unreachable) and is connected back to
// `from` with a same-color line. The dot is registered as `name` so a
// later `head-pointer(target: name)` can hang HEAD off it.
//
// Unlike `commit()`, the dot is not on any lane, does not advance the
// commit counter, and is not registered in `ref-branch-map`.
#let detached-commit(
  from,
  message,
  name,
  offset: (1, 1),
  edge-name: none,
  color: gray,
) = {
  let on-graph = d.on-layer.with(_layers.GRAPH)
  let on-branch = d.on-layer.with(_layers.BRANCH)
  graph-props(props => {
    let txt = props.commit-style.at("decorator")(message)
    on-graph(d.content(
      (rel: offset, to: from),
      circle(fill: color, radius: 0.5em),
      name: name,
    ))
    on-branch(d.line(
      from,
      name,
      stroke: (paint: color, ..props.graph-style.stroke),
      name: edge-name,
    ))
    if not _is-empty(message) {
      let rot = props.commit-style.at("angle")
      let dot-anc = props.commit-style.at("dot-anchor", default: "south-west")
      let text-anc = props.commit-style.at("text-anchor", default: "east")
      d.content(name + "." + dot-anc, txt, anchor: text-anc, angle: rot)
    }
  })
}

#let _merge-line(src, dest, color, name: none) = {
  // A line with a quarter-circle turn from src to dest branch
  graph-props(props => {
    let ctx = props.ctx
    let (ctx, a, b) = cetz.coordinate.resolve(ctx, src, dest)
    assert(
      calc.abs(_along-of(props, a)) < calc.abs(_along-of(props, b)),
      message: "Destination must be further along than source",
    )
    let radius = props.graph-style.radius
    let p = d.merge-path(
      stroke: (paint: color, ..props.graph-style.stroke),
      name: name,
      {
        if _is-horizontal(props) {
          d.line(src, (b.at(0) - radius, a.at(1)))
          // Branch above dest -> arc turns east into south, otherwise north.
          if a.at(1) > b.at(1) {
            d.arc((), start: 90deg, delta: -90deg, radius: radius)
          } else {
            d.arc((), start: -90deg, delta: 90deg, radius: radius)
          }
          d.line((), b)
        } else {
          d.line(src, (a.at(0), b.at(1) - radius))
          if a.at(0) < b.at(0) {
            d.arc((), start: 180deg, delta: -90deg, radius: radius)
          } else {
            d.arc((), start: 0deg, delta: 90deg, radius: radius)
          }
          d.line((), b)
        }
      },
    )
    d.on-layer(_layers.BRANCH, p)
  })
}

#let merge(commit-id, message: [], name: none, edge-name: none, fast-forward: false) = {
  commit(message, name: name)
  if fast-forward {
    d.on-layer(_layers.GRAPH, d.circle(
      (),
      radius: 0.35em,
      fill: white,
      stroke: none,
    ))
  }
  graph-props(props => {
    let commit-id = commit-id
    let refs = props.ref-branch-map
    // Resolve `commit-id` to (src-branch, anchor). A branch name like
    // "origin/main" maps to its "<branch>/head" anchor; a custom commit
    // ref is looked up directly in `ref-branch-map`. We track the source
    // branch explicitly rather than recovering it from the anchor string
    // so branch names containing "/" survive.
    let src-branch = if commit-id in props.branches {
      let branch = commit-id
      commit-id = commit-id + "/head"
      refs.insert(commit-id, branch)
      branch
    } else if commit-id in refs {
      refs.at(commit-id)
    } else {
      panic("Commit ref `" + commit-id + "` does not exist")
    }
    if src-branch == props.active-branch {
      panic(
        "Cannot merge branch into itself. head is already at `"
          + src-branch
          + "`, and commit `"
          + commit-id
          + "` belongs to the same branch.
        Perhaps you forgot to checkout a different branch before merging?",
      )
    }
    let branch-props = props.branches.at(src-branch)
    _merge-line(commit-id, "head", branch-props.fill, name: edge-name)
  })
}


// Highlight a commit by redrawing its dot in a different fill, on a higher
// layer so it covers the original. Pair with touying alternatives() to flip
// the highlight on and off across subslides.
#let git-highlight(commit-name, fill: yellow) = {
  d.on-layer(_layers.COMMIT + 10, d.content(
    commit-name,
    circle(radius: 0.5em, fill: fill, stroke: none),
  ))
}

// Trade-off on the `name:` parameter:
//   - name: none (default) — no d.group wrapper. Anchors created inside
//     (commit-id-N, branch labels, named edges, ...) live at the canvas
//     scope. Touying (pause,) / alternatives() markers inside the body are
//     visible to the outer reducer, so animation works.
//   - name: "x" — wraps the body in d.group(name: "x"). Anchors are
//     namespaced as "x.commit-id-N" and reachable from outside the block,
//     but (pause,) inside the body is swallowed by the group and animation
//     breaks. Pick per slide: external anchors OR in-block animation.
//
// `direction:` accepts "bottom-to-top" (default) or "left-to-right". When
// left-to-right is selected, sensible defaults for commit/tag label angles
// and anchors are applied unless the caller passes their own commit-style
// or tag-style dict.
//
// Styling comes from the git-theme: `theme: auto` reads the active
// `set-git-theme` state (resolved inside the cetz ctx, where a context is
// available); pass a partial dict to override per-call without touching
// state (the perf escape hatch). Precedence, lowest to highest:
//   theme -> horizontal-direction defaults -> ..style
#let git-graph(graph, name: none, theme: auto, ..style) = {
  let style-named = style.named()
  let direction = style-named.at("direction", default: "bottom-to-top")
  d.set-ctx(ctx => {
    // `theme == auto` reads state (needs context — supplied by cetz's
    // element processing); a dict bypasses state via `_merge-git-theme`.
    let resolved-theme = if theme == auto {
      _git-theme-state.get()
    } else {
      _merge-git-theme(theme)
    }
    let base = resolved-theme + _git-graph-behavior
    let defaults = if direction == "left-to-right" {
      base + _horizontal-style-defaults
    } else {
      base
    }
    ctx.git-graph = defaults + style-named
    ctx
  })
  if name == none {
    graph
  } else {
    d.group(name: name, graph)
  }
}
