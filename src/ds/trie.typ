// Trie — a prefix tree holding a set of strings.
//
// An n-ary tree whose EDGES carry the letters: a node's identity is the
// prefix spelled by the edges from the root down to it (the root is the
// empty prefix), and a node is `terminal` when a stored word ends there.
// This is a set-trie — nodes carry membership only, not values.
//
// A node is `(kind: "trie", char, terminal, children)`. `char` is the letter
// on the node's incoming edge (`none` at the root), and `children` is kept
// sorted ascending by `char`, which is what makes `words` come out
// lexicographically.
//
// It rides the shared tree backend: nodes are ordinary circles whose drawn
// label is the terminal *bit* — "1" where a word ends, "0" for an interior
// prefix — and each edge's letter is drawn through the edge `tag` slot, the
// same persistent structural-label slot AVL heights and graph weights use.
// Terminal nodes are shaded from the theme's `trie` palette.
//
// Element identity: a node's key is its prefix string (`""`, then `"c"`,
// `"ca"`, `"cat"`); an edge is keyed by its child's prefix, whose last
// character is the letter drawn on it. The core keys everything by opaque
// strings, so none of this needs a path alphabet of its own.
//
// step.kind vocabulary
// --------------------
//   static                the one frame of `display`
//   init                  the opening frame of every animation
//   match / not-found     a query character matched an edge, or didn't
//   found / prefix        the query ended on a stored word, or merely on a
//                         prefix of one
//   walk                  one character of a descent that is known to match
//   add / add-last        a new node on the grown suffix
//   mark / already        the endpoint became a word end, or already was one
//   unmark                the word-end mark cleared
//   prune-mark            a node about to be removed as a dead branch
//   done                  the pruning is finished
// The final frame of every display carries `step.result` — the trie the
// operation produced (the unchanged input, for a search).

#import "../core/draw-util.typ": anchor
#import "../core/frame.typ": make-frames, make-renderer, patch
#import "../core/snapshot.typ": blank-snapshot, with-edge, with-node
#import "../core/style.typ": theme-ref
#import "../core/text.typ": alt-describe, alt-intro
#import "../draw/tree.typ": draw-tree

#let _DS = "Trie"

// A word quoted for a caption or alt string.
#let _q(w) = "\"" + w + "\""

// A caption built from a string. Trie captions carry literal straight
// quotes around words, so the string is interpolated into content rather
// than written as markup — where `'` and `"` would become smart quotes.
#let _cap(s) = [#s]

// ===================================================================
// Structure
// ===================================================================

#let _mk(char, terminal, children) = (
  kind: "trie",
  char: char,
  terminal: terminal,
  children: children,
)

// Index of the child whose incoming letter is `ch`, or -1.
#let _child-index(node, ch) = {
  let found = -1
  for (j, c) in node.children.enumerate() {
    if c.char == ch {
      found = j
      break
    }
  }
  found
}

/// The node at `prefix`, or `none` when the prefix runs off the trie.
/// `""` returns the root.
/// -> dictionary | none
#let resolve(
  /// The trie.
  /// -> dictionary
  trie,
  /// The prefix to walk.
  /// -> str
  prefix,
) = {
  let cur = trie
  for ch in prefix.codepoints() {
    let idx = _child-index(cur, ch)
    if idx == -1 { return none }
    cur = cur.children.at(idx)
  }
  cur
}

// Insert a child in sorted-by-char position, so children stay ascending.
#let _insert-child-sorted(children, child) = {
  let pos = 0
  while pos < children.len() and children.at(pos).char < child.char { pos += 1 }
  children.slice(0, pos) + (child,) + children.slice(pos)
}

// Create the path `cps` beneath `node`, marking the endpoint terminal when
// `mark-terminal`. Leaving it false is what lets the insert animation grow
// the suffix one node at a time before the word officially exists.
#let _ensure-path(node, cps, mark-terminal) = {
  if cps.len() == 0 {
    _mk(node.char, node.terminal or mark-terminal, node.children)
  } else {
    let ch = cps.first()
    let idx = _child-index(node, ch)
    let new-children = if idx == -1 {
      _insert-child-sorted(
        node.children,
        _ensure-path(_mk(ch, false, ()), cps.slice(1), mark-terminal),
      )
    } else {
      let nc = node.children
      nc.at(idx) = _ensure-path(nc.at(idx), cps.slice(1), mark-terminal)
      nc
    }
    _mk(node.char, node.terminal, new-children)
  }
}

// Clear the terminal bit at `cps`, keeping children and pruning nothing.
#let _unmark(node, cps) = {
  if cps.len() == 0 {
    _mk(node.char, false, node.children)
  } else {
    let ch = cps.first()
    let idx = _child-index(node, ch)
    let nc = node.children
    nc.at(idx) = _unmark(nc.at(idx), cps.slice(1))
    _mk(node.char, node.terminal, nc)
  }
}

// Remove the subtree reached by `cps` (non-empty and present). The delete
// animation prunes one node per frame with this; each is a leaf by then.
#let _remove-subtree(node, cps) = {
  let ch = cps.first()
  let idx = _child-index(node, ch)
  let nc = if cps.len() == 1 {
    node.children.slice(0, idx) + node.children.slice(idx + 1)
  } else {
    let m = node.children
    m.at(idx) = _remove-subtree(m.at(idx), cps.slice(1))
    m
  }
  _mk(node.char, node.terminal, nc)
}

// Delete `cps` and prune the dead branch it leaves behind. Returns the new
// node, or `none` when the node itself should go (a non-terminal leaf after
// the delete). The public `delete` turns a `none` root into an empty one.
#let _delete-rec(node, cps) = {
  if cps.len() == 0 {
    if not node.terminal { return node } // the word isn't stored — no-op
    let unmarked = _mk(node.char, false, node.children)
    if unmarked.children.len() == 0 { none } else { unmarked }
  } else {
    let ch = cps.first()
    let idx = _child-index(node, ch)
    if idx == -1 { return node } // the word isn't present — no-op
    let new-child = _delete-rec(node.children.at(idx), cps.slice(1))
    let nc = if new-child == none {
      node.children.slice(0, idx) + node.children.slice(idx + 1)
    } else {
      let m = node.children
      m.at(idx) = new-child
      m
    }
    let rebuilt = _mk(node.char, node.terminal, nc)
    if not rebuilt.terminal and rebuilt.children.len() == 0 {
      none
    } else { rebuilt }
  }
}

// Every (prefix, node) pair, root first.
#let _all-nodes(node, prefix) = {
  let out = ((prefix, node),)
  for c in node.children { out += _all-nodes(c, prefix + c.char) }
  out
}

// ===================================================================
// Construction and pure operations
// ===================================================================

/// Insert `word`, returning a new trie. Inserting a word that is already
/// stored changes nothing.
/// -> dictionary
#let insert(
  /// The trie.
  /// -> dictionary
  trie,
  /// The word to store.
  /// -> str
  word,
) = _ensure-path(trie, word.codepoints(), true)

/// Insert several words in order.
/// -> dictionary
#let insert-many(
  /// The trie.
  /// -> dictionary
  trie,
  /// The words to store.
  /// -> str
  ..words,
) = {
  let out = trie
  for w in words.pos() {
    assert(
      type(w) == str,
      message: "trie.insert-many: expected a word, got " + repr(w) + ".",
    )
    out = insert(out, w)
  }
  out
}

/// Build a trie from a list of words, inserted left to right. With no
/// arguments the result is an empty trie — a root and nothing else.
///
/// ```typ
/// trie.new("cat", "car", "card", "dog")
/// ```
///
/// -> dictionary
#let new(
  /// The words to store.
  /// -> str
  ..words,
) = insert-many(_mk(none, false, ()), ..words.pos())

/// Whether `word` is stored — a node exists at that prefix *and* a word
/// ends there.
/// -> bool
#let contains(
  /// The trie.
  /// -> dictionary
  trie,
  /// The word to look for.
  /// -> str
  word,
) = {
  let n = resolve(trie, word)
  n != none and n.terminal
}

/// Whether `prefix` is a path in the trie, whether or not a word ends there.
/// -> bool
#let has-prefix(
  /// The trie.
  /// -> dictionary
  trie,
  /// The prefix to look for.
  /// -> str
  prefix,
) = resolve(trie, prefix) != none

/// Delete `word`, returning a new trie with the dead branch pruned. Deleting
/// a word that isn't stored changes nothing.
/// -> dictionary
#let delete(
  /// The trie.
  /// -> dictionary
  trie,
  /// The word to remove.
  /// -> str
  word,
) = {
  let out = _delete-rec(trie, word.codepoints())
  // Unlike the other structures, an emptied trie is still a trie: the root
  // is a real node holding the empty prefix, so there is no `none` to
  // surface.
  if out == none { _mk(none, false, ()) } else { out }
}

/// Every prefix visited walking `word`, root first — `("", "c", "ca")`.
/// Panics when the word's path isn't present.
/// -> array
#let path-to(
  /// The trie.
  /// -> dictionary
  trie,
  /// The word to walk.
  /// -> str
  word,
) = {
  let prefixes = ("",)
  let cur = trie
  let p = ""
  for ch in word.codepoints() {
    let idx = _child-index(cur, ch)
    if idx == -1 {
      panic("trie.path-to: prefix not present in trie: " + repr(word) + ".")
    }
    p = p + ch
    prefixes.push(p)
    cur = cur.children.at(idx)
  }
  prefixes
}

/// Every stored word, lexicographically ordered.
/// -> array
#let words(
  /// The trie.
  /// -> dictionary
  trie,
) = {
  let walk(node, prefix) = {
    let out = if node.terminal { (prefix,) } else { () }
    for c in node.children { out += walk(c, prefix + c.char) }
    out
  }
  walk(trie, "")
}

/// A textual rendering of the stored set, used in alt text.
/// -> str
#let describe(
  /// The trie.
  /// -> dictionary
  trie,
) = {
  let ws = words(trie)
  if ws.len() == 0 { "empty trie" } else { "trie of " + ws.map(_q).join(", ") }
}

/// Check the structural invariants: the root's `char` is `none`, every other
/// node's is a single character, and children are strictly ascending by
/// `char`. Returns `true` or panics naming the first violation.
/// -> bool
#let check-invariants(
  /// The trie.
  /// -> dictionary
  trie,
) = {
  let walk(node, is-root) = {
    if is-root {
      assert(
        node.char == none,
        message: "trie.check-invariants: the root's char must be none, got "
          + repr(node.char)
          + ".",
      )
    } else {
      assert(
        type(node.char) == str and node.char.clusters().len() == 1,
        message: "trie.check-invariants: a non-root node's char must be a "
          + "single character, got "
          + repr(node.char)
          + ".",
      )
    }
    let prev = none
    for c in node.children {
      assert(
        prev == none or prev < c.char,
        message: "trie.check-invariants: children are not strictly sorted by "
          + "char: "
          + repr(node.children.map(x => x.char))
          + ".",
      )
      prev = c.char
      walk(c, false)
    }
  }
  walk(trie, true)
  true
}

// ===================================================================
// The palette
// ===================================================================

// The structural painting every trie display starts from: terminal nodes
// shaded from the theme's trie palette, and each non-root node's incoming
// edge stamped with its letter. The `0`/`1` node bits come from the tree
// backend, not from here.
//
// The colours are theme *references* rather than concrete values, because
// the snapshot is often built long before the frame is drawn — a renderer
// handed to the op stream, a display whose theme override arrives later —
// and a reference follows whichever theme wins.
#let _paint(trie) = {
  let snap = blank-snapshot()
  for (p, n) in _all-nodes(trie, "") {
    if n.terminal {
      snap = with-node(
        snap,
        p,
        (
          fill: theme-ref("trie", "terminal-fill"),
          stroke: theme-ref("trie", "terminal-stroke"),
          text-fill: theme-ref("trie", "terminal-text-fill"),
        ),
      )
    }
    // The edge into this node carries its letter.
    if p != "" { snap = with-edge(snap, p, (tag: n.char)) }
  }
  snap
}

// ===================================================================
// Rendering
// ===================================================================

/// A `Renderer` over this trie, bound to the tree backend and pre-painted
/// with the terminal shading and the edge letters — the entry point for
/// driving an animation yourself with the `Op` command stream. Pass
/// `sticky: true` so the painting (and your own highlights) carry from
/// frame to frame.
/// -> dictionary
#let renderer(
  /// The trie.
  /// -> dictionary
  trie,
  /// Base node styling beneath every frame's snapshot.
  /// -> dictionary
  node-style: (:),
  /// Base edge styling beneath every frame's snapshot.
  /// -> dictionary
  edge-style: (:),
  /// Whether new frames inherit the previous frame's styling.
  /// -> bool
  sticky: false,
  /// Partial theme override for this renderer.
  /// -> dictionary
  theme: (:),
) = patch(
  make-renderer(
    trie,
    draw-tree,
    node-style: node-style,
    edge-style: edge-style,
    sticky: sticky,
    theme: theme,
  ),
  _ => _paint(trie),
)

// Every display shares this: build the frames on the tree backend with the
// caller's style layers and theme override.
#let _frames(specs, theme, node-style, edge-style) = make-frames(
  specs,
  draw-tree,
  theme: theme,
  node-style: node-style,
  edge-style: edge-style,
)

// Stamp `step.result` onto the last spec — the trie the operation produced.
#let _stamp-result(specs, after) = {
  let out = specs
  let i = out.len() - 1
  let s = out.at(i)
  out.at(i) = (..s, step: (..s.step, result: after))
  out
}

/// The trie as a single static frame: word-end nodes shaded, letters on the
/// edges, terminal bits in the nodes.
/// -> array
#let display(
  /// The trie.
  /// -> dictionary
  trie,
  /// Base node styling.
  /// -> dictionary
  node-style: (:),
  /// Base edge styling.
  /// -> dictionary
  edge-style: (:),
  /// Partial theme override for this call.
  /// -> dictionary
  theme: (:),
) = _frames(
  (
    (
      structure: trie,
      build: _ => _paint(trie),
      caption: none,
      step: (kind: "static", result: trie),
      alt: alt-describe(_DS, describe(trie)),
    ),
  ),
  theme,
  node-style,
  edge-style,
)

// The descent for `word`, one step per character. Each step records the
// prefix it left, the character it followed, and whether an edge for that
// character existed; the walk stops at the first missing edge.
#let _search-steps(trie, word) = {
  let steps = ()
  let cur = trie
  let prefix = ""
  let dead = false
  for ch in word.codepoints() {
    if dead { break }
    let idx = _child-index(cur, ch)
    if idx == -1 {
      steps.push((from: prefix, char: ch, to: prefix + ch, matched: false))
      dead = true
    } else {
      steps.push((from: prefix, char: ch, to: prefix + ch, matched: true))
      prefix = prefix + ch
      cur = cur.children.at(idx)
    }
  }
  (steps: steps, dead: dead, terminal: (not dead) and cur.terminal)
}

// One shared closure builds every snapshot, each frame indexing into the
// result; Typst memoizes the call, so the accumulation runs once.
#let _search-build(trie, word, walk) = th => {
  let cur = _paint(trie)
  let out = (cur,)
  for st in walk.steps {
    if st.matched {
      cur = with-edge(cur, st.to, (stroke: th.op.search-stroke))
      cur = with-node(cur, st.to, (stroke: th.op.search-stroke))
    } else {
      cur = with-node(
        cur,
        st.from,
        (stroke: th.op.danger-stroke, note: "no '" + st.char + "'"),
      )
    }
    out.push(cur)
  }
  if not walk.dead {
    cur = if walk.terminal {
      with-node(
        cur,
        word,
        (stroke: th.op.settled-stroke, fill: th.op.success-fill),
      )
    } else {
      with-node(cur, word, (stroke: th.op.attention-stroke, note: "prefix"))
    }
    out.push(cur)
  }
  out
}

// The frame a completed descent ends on: a stored word, or a prefix that
// merely leads somewhere — the distinction a trie exists to make.
#let _search-terminal-spec(trie, build, at, word, terminal) = if terminal {
  (
    structure: trie,
    build: th => build(th).at(at),
    caption: _cap("found " + _q(word)),
    step: (kind: "found", prefix: word),
    alt: "Reached " + _q(word) + ", a stored word.",
  )
} else {
  (
    structure: trie,
    build: th => build(th).at(at),
    caption: _cap(_q(word) + " is a prefix only"),
    step: (kind: "prefix", prefix: word),
    alt: "Reached "
      + _q(word)
      + ", but it is only a prefix — not a stored word.",
  )
}

/// Animate searching for `word`: one frame per query character, each
/// lighting the edge it matched and the node it reached.
///
/// Three ways to end. A missing edge rings the last matched node in
/// `danger-stroke` and stops. A full match on a word-end node rings it in
/// `settled-stroke`. A full match on an interior node is flagged a prefix
/// only — the distinction a trie exists to make.
/// -> array
#let search-display(
  /// The trie.
  /// -> dictionary
  trie,
  /// The word to search for.
  /// -> str
  word,
  /// Base node styling.
  /// -> dictionary
  node-style: (:),
  /// Base edge styling.
  /// -> dictionary
  edge-style: (:),
  /// Partial theme override for this call.
  /// -> dictionary
  theme: (:),
) = {
  let walk = _search-steps(trie, word)
  let build-all = _search-build(trie, word, walk)

  let specs = (
    (
      structure: trie,
      build: th => build-all(th).at(0),
      caption: none,
      step: (kind: "init"),
      alt: alt-intro(_DS, describe(trie), "search for " + _q(word)),
    ),
  )
  for (i, st) in walk.steps.enumerate() {
    let at = i + 1
    specs.push((
      structure: trie,
      build: th => build-all(th).at(at),
      ..if st.matched {
        (
          caption: raw(st.to),
          step: (kind: "match", prefix: st.to, char: st.char),
          alt: "Matched '" + st.char + "'; prefix so far " + _q(st.to) + ".",
        )
      } else {
        (
          caption: _cap("no '" + st.char + "' edge"),
          step: (kind: "not-found", prefix: st.from, char: st.char),
          alt: "No edge labelled '"
            + st.char
            + "' from "
            + _q(st.from)
            + "; "
            + _q(word)
            + " is not in the trie.",
        )
      },
    ))
  }
  if not walk.dead {
    specs.push(_search-terminal-spec(
      trie,
      build-all,
      walk.steps.len() + 1,
      word,
      walk.terminal,
    ))
  }
  // A search leaves the trie alone, so the result is the input.
  _frames(_stamp-result(specs, trie), theme, node-style, edge-style)
}

// The walk phase both mutations open with: init, then one frame per
// character of an already-existing prefix, lighting the edge and node it
// reaches. `action` completes the init frame's "About to …"; `walk-alt`
// turns one prefix into its frame's alt text, since an insert is checking
// what already exists and a delete already knows. Returns an array of specs.
#let _walk-specs(trie, prefixes, action, walk-alt) = {
  let build-all = th => {
    let cur = _paint(trie)
    let out = (cur,)
    for p in prefixes {
      cur = with-edge(cur, p, (stroke: th.op.search-stroke))
      cur = with-node(cur, p, (stroke: th.op.search-stroke))
      out.push(cur)
    }
    out
  }
  let specs = (
    (
      structure: trie,
      build: th => build-all(th).at(0),
      caption: none,
      step: (kind: "init"),
      alt: alt-intro(_DS, describe(trie), action),
    ),
  )
  for (i, p) in prefixes.enumerate() {
    let at = i + 1
    specs.push((
      structure: trie,
      build: th => build-all(th).at(at),
      caption: raw(p),
      step: (kind: "walk", prefix: p),
      alt: walk-alt(p),
    ))
  }
  specs
}

/// Animate inserting `word`: first the walk down the longest prefix that
/// already exists, then the remaining suffix growing one node per frame,
/// then the endpoint flipping to a word end.
///
/// A word that is already stored gets a single terminal frame saying so —
/// the trie is unchanged, and that is worth showing rather than hiding.
/// -> array
#let insert-display(
  /// The trie.
  /// -> dictionary
  trie,
  /// The word to store.
  /// -> str
  word,
  /// Base node styling.
  /// -> dictionary
  node-style: (:),
  /// Base edge styling.
  /// -> dictionary
  edge-style: (:),
  /// Partial theme override for this call.
  /// -> dictionary
  theme: (:),
) = {
  let cps = word.codepoints()
  let pre = k => cps.slice(0, k).join("")

  // The longest prefix of `word` that is already in the trie.
  let cur = trie
  let existing = ()
  let prefix = ""
  for ch in cps {
    let idx = _child-index(cur, ch)
    if idx == -1 { break }
    prefix = prefix + ch
    existing.push(prefix)
    cur = cur.children.at(idx)
  }
  let already = existing.len() == cps.len() and cur.terminal
  let after = insert(trie, word)

  // Phase B: the suffix grows one node per frame — each new node is drawn
  // non-terminal ("0") until the last frame marks the word end.
  let events = if already {
    ((tree: trie, kind: "already", path: word),)
  } else {
    let grown = range(existing.len() + 1, cps.len() + 1).map(k => (
      tree: _ensure-path(trie, cps.slice(0, k), false),
      kind: if k == cps.len() { "add-last" } else { "add" },
      path: pre(k),
    ))
    grown + ((tree: after, kind: "mark", path: word),)
  }

  let specs-b = events.map(ev => {
    let caption = none
    let alt = ""
    if ev.kind == "add" or ev.kind == "add-last" {
      caption = raw(ev.path)
      alt = "Added node for prefix " + _q(ev.path) + "."
    } else if ev.kind == "mark" {
      caption = _cap("inserted " + _q(word))
      alt = "Marked " + _q(word) + " as a stored word."
    } else if ev.kind == "already" {
      caption = _cap(_q(word) + " already present")
      alt = _q(word) + " is already a stored word; nothing to do."
    }
    let build = th => {
      let cur = _paint(ev.tree)
      if ev.kind == "add" or ev.kind == "add-last" {
        cur = with-edge(cur, ev.path, (stroke: th.op.success-stroke))
        cur = with-node(cur, ev.path, (stroke: th.op.success-stroke))
      } else if ev.kind == "mark" {
        cur = with-node(
          cur,
          ev.path,
          (stroke: th.op.settled-stroke, fill: th.op.success-fill),
        )
        if ev.path != "" {
          cur = with-edge(cur, ev.path, (stroke: th.op.success-stroke))
        }
      } else if ev.kind == "already" {
        cur = with-node(cur, ev.path, (stroke: th.op.settled-stroke))
      }
      cur
    }
    (
      structure: ev.tree,
      build: build,
      caption: caption,
      step: (kind: ev.kind, path: ev.path),
      alt: alt,
    )
  })

  _frames(
    _stamp-result(
      _walk-specs(
        trie,
        existing,
        "insert " + _q(word),
        p => "Prefix " + _q(p) + " already exists; descending.",
      )
        + specs-b,
      after,
    ),
    theme,
    node-style,
    edge-style,
  )
}

/// Animate deleting `word`: the walk down to its word-end node, the mark
/// coming off (the bit flips "1" to "0" and the shading goes), then the
/// branch that has just died pruned one node per frame.
///
/// A node is pruned when it is a childless non-terminal — so deleting
/// `"card"` from a trie that also holds `"car"` removes exactly one node,
/// while deleting the only word removes the whole chain.
///
/// With `search: false` the walk is dropped and the animation starts at the
/// unmark. Panics when `word` isn't stored.
/// -> array
#let delete-display(
  /// The trie.
  /// -> dictionary
  trie,
  /// The word to remove.
  /// -> str
  word,
  /// Whether to walk down to the word before removing it.
  /// -> bool
  search: true,
  /// Base node styling.
  /// -> dictionary
  node-style: (:),
  /// Base edge styling.
  /// -> dictionary
  edge-style: (:),
  /// Partial theme override for this call.
  /// -> dictionary
  theme: (:),
) = {
  assert(
    contains(trie, word),
    message: "trie.delete-display: " + repr(word) + " is not a stored word.",
  )
  let cps = word.codepoints()

  // Which nodes die: the word's own node if it is childless, then each
  // ancestor that is non-terminal with only that one child, up the chain.
  let prune = ()
  if resolve(trie, word).children.len() == 0 {
    prune.push(word)
    let j = cps.len() - 1
    while j >= 1 {
      let parent-prefix = cps.slice(0, j).join("")
      let parent = resolve(trie, parent-prefix)
      if (not parent.terminal) and parent.children.len() == 1 {
        prune.push(parent-prefix)
        j -= 1
      } else { break }
    }
  }

  // Phase B: unmark, then one danger-marked frame per node about to be
  // pruned (drawn on the tree that still holds it), then the settled result.
  let unmarked = _unmark(trie, cps)
  let events = ((tree: unmarked, kind: "unmark", path: word),)
  let running = unmarked
  for pp in prune {
    events.push((tree: running, kind: "prune-mark", path: pp))
    running = _remove-subtree(running, pp.codepoints())
  }
  events.push((tree: running, kind: "done", path: word))

  let specs-b = events.map(ev => {
    let caption = none
    let alt = ""
    if ev.kind == "unmark" {
      caption = _cap("unmark " + _q(word))
      alt = "Cleared the word-end mark at " + _q(word) + "."
    } else if ev.kind == "prune-mark" {
      caption = _cap("prune " + _q(ev.path))
      alt = "Node " + _q(ev.path) + " is now a dead branch — removing it."
    } else if ev.kind == "done" {
      caption = _cap("deleted " + _q(word))
      alt = "Deletion of " + _q(word) + " complete."
    }
    let build = th => {
      let cur = _paint(ev.tree)
      if ev.kind == "unmark" {
        cur = with-node(cur, ev.path, (stroke: th.op.attention-stroke))
      } else if ev.kind == "prune-mark" {
        cur = with-node(cur, ev.path, (stroke: th.op.danger-stroke))
        if ev.path != "" {
          cur = with-edge(cur, ev.path, (stroke: th.op.danger-stroke))
        }
      }
      cur
    }
    (
      structure: ev.tree,
      build: build,
      caption: caption,
      step: (kind: ev.kind, path: ev.path),
      alt: alt,
    )
  })

  // Every character of the word matches, so the walk is the whole word.
  let walk-prefixes = range(1, cps.len() + 1).map(k => cps.slice(0, k).join(""))
  let specs-a = if search {
    _walk-specs(
      trie,
      walk-prefixes,
      "delete " + _q(word),
      p => "Descending to " + _q(p) + ".",
    )
  } else {
    _walk-specs(trie, (), "delete " + _q(word), p => "")
  }

  _frames(
    _stamp-result(specs-a + specs-b, running),
    theme,
    node-style,
    edge-style,
  )
}
