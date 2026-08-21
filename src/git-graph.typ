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
// It DOES share starling's one theme: every styling default lives in the
// `git:` section of `core/theme.typ`'s `default-theme` — the branch color
// palette, the lane/graph strokes, and the commit/tag/pointer decorators
// and angles. Override it document-wide with `set-theme((git: (..)))` or
// per-call with `git-graph(theme: (git: (..)))`, exactly like every other
// structure's palette. Behavioral/layout config (`direction`,
// `commit-spacing`, `lane-spacing`) and live runtime state (`branches`,
// `commit-id`, ...) are NOT theme; they are `git-graph(..)` `..style`
// arguments merged in `_git-graph-behavior`.

#import "@preview/cetz:0.5.2" as _cetz
#import "core/theme.typ": resolve-theme as _resolve-theme

#let _d = _cetz.draw

#let _offset(anchor, x: 0, y: 0) = {
  (v => _cetz.vector.add(v, (x, y)), anchor)
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

// Style overrides applied when direction == "left-to-right": the label
// angles and anchors that keep a message leaning away from a horizontal
// lane. Only those keys change — the decorators come from `git`, the
// resolved theme section, so a themed decorator survives the flip.
#let _horizontal-style(git) = (
  commit-style: (
    ..git.commit-style,
    angle: -45deg,
    dot-anchor: "south",
    text-anchor: "north-west",
  ),
  tag-style: (
    ..git.tag-style,
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

#let _graph-props(func) = {
  _d.get-ctx(ctx => {
    let props = ctx.git-graph
    props.ctx = ctx
    func(props)
  })
}

#let _set-graph-props(func) = {
  _d.set-ctx(ctx => {
    ctx.git-graph = func(ctx.git-graph)
    ctx
  })
}

#let _branch-props(func, branch: auto) = {
  _graph-props(props => {
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

/// Rule a dashed lane along every branch, from its label to just past the
/// last commit — the backdrop that makes which lane a commit sits on
/// obvious. Call it after the history, so every branch exists. Styled by
/// the theme's `git.lane-style`.
#let background-lanes() = {
  _graph-props(props => {
    for branch-name in props.branches.keys() {
      let (ctx, latest-commit) = _cetz.coordinate.resolve(props.ctx, "head")
      let extent = _along-of(props, latest-commit) + props.commit-spacing
      // Anchor the lane at the same edge of the label box that was used to
      // place the label, so the lane aligns with the commit dots regardless
      // of label width. Using `branch-name` (center) here would shift the
      // lane by half the label width — wide labels then fall short of the
      // last commit on the along axis.
      let label-edge = if _is-horizontal(props) { "east" } else { "north" }
      let start = branch-name + "." + label-edge
      let end = if _is-horizontal(props) {
        _offset(start, x: extent)
      } else {
        _offset(start, y: extent)
      }
      _d.on-layer(_layers.BACKGROUND-LANES, _d.line(
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
  _graph-props(props => {
    let ctx = props.ctx
    let (ctx, a, b) = _cetz.coordinate.resolve(ctx, src, dst)
    assert(
      _along-of(props, a) < _along-of(props, b) and _across-of(props, a) <= _across-of(props, b),
      message: "source branch must start before destination branch",
    )
    let radius = props.graph-style.radius
    let stroke = (stroke: (paint: color, ..props.graph-style.stroke))
    _d.merge-path(..stroke, name: name, {
      if _is-horizontal(props) {
        // Vertical line down from src, then quarter-arc that flips to going
        // right along the new lane.
        _d.line(src, (a.at(0), b.at(1) + radius))
        _d.arc((), start: 180deg, delta: 90deg, radius: radius)
      } else {
        _d.line(src, (b.at(0) - radius, a.at(1)))
        _d.arc((), start: -90deg, delta: 90deg, radius: radius)
      }
    })
  })
}

/// Start a branch and check it out. The first call must come before the
/// first `commit`; later ones fork from the current tip (or from `from:`, a
/// cetz anchor). `color:` pins this branch's colour, `colors:` replaces the
/// palette it is drawn from (the theme's `git.colors` by default), and
/// `edge-name:` names the fork line for later annotation.
#let branch(name, color: auto, colors: auto, edge-name: none, from: auto) = {
  if type(name) != str {
    name = name.text
  }
  _set-graph-props(props => {
    let branches = props.branches
    if name in branches {
      panic("Branch `" + name + "` already exists")
    }
    let color = color
    // Fall back to the themed palette when the caller didn't pass an
    // explicit color list.
    let colors = if colors == auto { props.colors } else { colors }
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
  _branch-props(props => {
    let label-anchor = if _is-horizontal(props) { "east" } else { "west" }
    _d.content(
      _pt(props, 0, props.lane * props.lane-spacing),
      styled(name, fill: props.branches.at(name).fill),
      name: name,
      anchor: label-anchor,
    )
  })
  _branch-props(props => {
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
      let (_, source-pos, lane-pos) = _cetz.coordinate.resolve(
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
        _d.on-layer(-props.lane + _layers.BRANCH, _branch-line(
          source,
          join-loc,
          props.fill,
          name: edge-name,
        ))
      }
    }
    _d.anchor("head", new-head)
    _d.anchor(name + "/head", new-head)
  })
}

/// Make `branch` the active one, so subsequent commits land on its lane.
#let checkout(branch) = {
  _set-graph-props(props => {
    if branch not in props.branches {
      panic("Branch `" + branch + "` does not exist")
    }
    props.active-branch = branch
    props
  })
  _d.anchor("head", branch + "/head")
}

/// Draw a commit on the active branch, with `message` beside its dot.
/// `branch:` checks that branch out first; `name:` gives the dot a cetz
/// anchor name of your choosing (otherwise it is `commit-id-<n>`), which is
/// what later annotations and `merge` refer to.
#let commit(message, branch: auto, name: none, edge-name: none) = {
  if branch != auto {
    checkout(branch)
  }
  _set-graph-props(props => {
    props.commit-id = props.commit-id + 1
    props.ref-branch-map.insert(str(props.commit-id), props.active-branch)
    props
  })
  let on-graph = _d.on-layer.with(_layers.GRAPH)
  let on-branch = _d.on-layer.with(_layers.BRANCH)
  _branch-props(props => {
    let txt = props.commit-style.at("decorator")(message)
    let (_, lane-pos) = _cetz.coordinate.resolve(props.ctx, "head")
    let (_, branch-pos) = _cetz.coordinate.resolve(
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
    _d.anchor("head", _pt(props, new-along, across))
    on-graph(_d.content(
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
      _d.line(
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
      _d.content(dot-name + "." + dot-anc, txt, anchor: text-anc, angle: rot)
    }
  })
  _graph-props(props => {
    _d.anchor(props.active-branch + "/head", "head")
    // Always provide commit-id-N as a point alias, even when a custom name
    // owns the edge anchors.
    if name != none {
      _d.anchor("commit-id-" + str(props.commit-id), "head")
    }
  })
}

/// Hang a tag label off the current tip, in the theme's `git.tag-style`.
#let tag(message) = {
  _graph-props(props => {
    let txt = props.tag-style.at("decorator")(message)
    let rot = props.tag-style.at("angle")
    let anc = props.tag-style.at("text-anchor", default: "west")
    _d.content("head", txt, anchor: anc, angle: rot, padding: 0.75em)
  })
}

/// Draw a branch pointer — the branch's name in its own colour — at the tip
/// of `name`. It mirrors the commit message through the dot: the same tilt,
/// but extending away from it. The label registers the cetz anchor
/// `branch-pointer-<name>`, which is what `head-pointer` stacks against.
#let branch-pointer(name, padding: auto, anchor: auto, angle: auto) = {
  _set-graph-props(props => {
    let drawn = props.pointer-drawn
    drawn.insert(name, true)
    props.pointer-drawn = drawn
    props
  })
  _graph-props(props => {
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
    _d.content(
      name + "/head",
      txt,
      anchor: anc,
      angle: rot,
      padding: pad,
      name: "branch-pointer-" + name,
    )
  })
}

/// Draw the `HEAD` label at the tip of `branch:` (default: the active one).
/// It stacks past that branch's pointer label when one was drawn; pass
/// `after: none` to anchor it at the dot instead, or `after: "<branch>"` to
/// stack past a different branch's pointer. Pass `target:` (any cetz anchor
/// name) to point HEAD at an arbitrary commit — a detached HEAD.
#let head-pointer(
  branch: auto,
  target: none,
  after: auto,
  padding: auto,
  anchor: auto,
  angle: auto,
) = {
  _graph-props(props => {
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
      _d.content(target, txt, anchor: anc, angle: rot, padding: pad)
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
      _d.content(resolved-target, txt, anchor: anc, angle: rot, padding: pad)
    }
  })
}

/// Draw an orphan commit dot `offset` from `from` (a cetz anchor — a
/// `commit-id-<n>` or a commit's own `name:`), joined back to it by a line
/// in the same colour (grey by default, to read as unreachable). The dot is
/// registered as `name`, so `head-pointer(target: name)` can hang a
/// detached HEAD off it. Unlike `commit` it joins no lane, advances no
/// counter, and is not a merge target.
#let detached-commit(
  from,
  message,
  name,
  offset: (1, 1),
  edge-name: none,
  color: gray,
) = {
  let on-graph = _d.on-layer.with(_layers.GRAPH)
  let on-branch = _d.on-layer.with(_layers.BRANCH)
  _graph-props(props => {
    let txt = props.commit-style.at("decorator")(message)
    on-graph(_d.content(
      (rel: offset, to: from),
      circle(fill: color, radius: 0.5em),
      name: name,
    ))
    on-branch(_d.line(
      from,
      name,
      stroke: (paint: color, ..props.graph-style.stroke),
      name: edge-name,
    ))
    if not _is-empty(message) {
      let rot = props.commit-style.at("angle")
      let dot-anc = props.commit-style.at("dot-anchor", default: "south-west")
      let text-anc = props.commit-style.at("text-anchor", default: "east")
      _d.content(name + "." + dot-anc, txt, anchor: text-anc, angle: rot)
    }
  })
}

#let _merge-line(src, dest, color, name: none) = {
  // A line with a quarter-circle turn from src to dest branch
  _graph-props(props => {
    let ctx = props.ctx
    let (ctx, a, b) = _cetz.coordinate.resolve(ctx, src, dest)
    assert(
      calc.abs(_along-of(props, a)) < calc.abs(_along-of(props, b)),
      message: "Destination must be further along than source",
    )
    let radius = props.graph-style.radius
    let p = _d.merge-path(
      stroke: (paint: color, ..props.graph-style.stroke),
      name: name,
      {
        if _is-horizontal(props) {
          _d.line(src, (b.at(0) - radius, a.at(1)))
          // Branch above dest -> arc turns east into south, otherwise north.
          if a.at(1) > b.at(1) {
            _d.arc((), start: 90deg, delta: -90deg, radius: radius)
          } else {
            _d.arc((), start: -90deg, delta: 90deg, radius: radius)
          }
          _d.line((), b)
        } else {
          _d.line(src, (a.at(0), b.at(1) - radius))
          if a.at(0) < b.at(0) {
            _d.arc((), start: 180deg, delta: -90deg, radius: radius)
          } else {
            _d.arc((), start: 0deg, delta: 90deg, radius: radius)
          }
          _d.line((), b)
        }
      },
    )
    _d.on-layer(_layers.BRANCH, p)
  })
}

/// Merge `commit-id` — a branch name, or a commit's `name:` — into the
/// active branch, drawing the merge commit and the incoming edge.
/// `fast-forward: true` draws the tip as a fast-forward instead of a merge
/// dot.
#let merge(commit-id, message: [], name: none, edge-name: none, fast-forward: false) = {
  commit(message, name: name)
  if fast-forward {
    _d.on-layer(_layers.GRAPH, _d.circle(
      (),
      radius: 0.35em,
      fill: white,
      stroke: none,
    ))
  }
  _graph-props(props => {
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


/// Redraw a commit's dot in `fill`, on a layer above the original, to pick
/// it out. Pair it with touying's `alternatives(..)` to flip a highlight on
/// and off across subslides.
#let git-highlight(commit-name, fill: yellow) = {
  _d.on-layer(_layers.COMMIT + 10, _d.content(
    commit-name,
    circle(radius: 0.5em, fill: fill, stroke: none),
  ))
}

/// The block every other verb is called inside: it seeds cetz's canvas
/// context with the resolved theme and layout defaults, then draws `graph`.
/// Place it directly in a `cetz.canvas`.
///
/// `theme:` is a partial nested theme override (`theme: (git: (..))`),
/// layered over the document's theme like any display's. `..style` takes
/// the behavioural knobs — `direction:` (`"bottom-to-top"`, the default, or
/// `"left-to-right"`), `commit-spacing:`, `lane-spacing:` — which are
/// deliberately not theme. `name:` wraps the drawing in a named cetz group
/// so its anchors are reachable from outside, at the cost of swallowing
/// touying `pause` markers inside the body.
#let git-graph(graph, name: none, theme: (:), ..style) = {
  // The theme is read inside the deferred `set-ctx` closure below, the one
  // place a cetz builder has the context a state read needs. Precedence,
  // lowest first: default-theme -> set-theme state -> theme: -> the
  // direction defaults -> ..style.
  let style-named = style.named()
  let direction = style-named.at("direction", default: "bottom-to-top")
  _d.set-ctx(ctx => {
    let git = _resolve-theme(theme).git
    let base = git + _git-graph-behavior
    let defaults = if direction == "left-to-right" {
      base + _horizontal-style(git)
    } else {
      base
    }
    ctx.git-graph = defaults + style-named
    ctx
  })
  if name == none {
    graph
  } else {
    _d.group(name: name, graph)
  }
}
