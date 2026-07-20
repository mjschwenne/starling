#import "@preview/typsy:0.2.2": (
  Any, Array, Bool, Dictionary, None, Refine, Str, Union, class,
)
#import "./tree-anim.typ" as tree-anim

// ===================================================================
// Trie — prefix tree (set of strings)
// ===================================================================
//
// A trie is an n-ary tree whose EDGES carry the letters: a node's
// identity is the prefix spelled by the edges from the root down to it
// (the root is the empty prefix). A node is `terminal` when a stored
// word ends there. This is a *set*-trie — nodes carry membership only,
// not stored values.
//
// It rides the shared tree backend (`draw-tree` in `tree-anim.typ`):
// nodes are ordinary circles whose drawn value is the terminal bit —
// "1" when a word ends there, "0" for an interior prefix — and each
// edge's letter is drawn via the edge `tag` slot (the same persistent
// structural-label slot AVL heights and graph weights use). Terminal
// nodes are additionally shaded via the per-DS `default-trie-theme`.
//
// Path identity: a node's starling key is its prefix string (root "",
// then "c", "ca", "cat"); an edge is keyed by its child's prefix, whose
// last character is the drawn letter. The core keys everything by opaque
// strings, so this needs no change to `PathId` — trie methods type path
// args as plain strings. The `tree-anim` trie builder
// (`_build-cetz-tree-trie`) extends each child's path by its `char`.

// --- node-construction & structural helpers ------------------------
//
// Every helper takes `cls` first so it can call `cls.new` without
// referring to `Trie` (not yet defined while the helpers are declared).

#let _node(cls, char, terminal, children) = (cls.new)(
  char: char,
  terminal: terminal,
  children: children,
)

// Index of the child whose incoming letter is `ch`, or -1.
#let _child-index(node, ch) = {
  let result = -1
  for (j, c) in node.children.enumerate() {
    if c.char == ch {
      result = j
      break
    }
  }
  result
}

// Resolve the node at `prefix`, or `none` if the prefix runs off the
// tree. `prefix == ""` returns `node` itself.
#let _resolve-at(node, prefix) = {
  let cur = node
  for ch in prefix.codepoints() {
    let idx = _child-index(cur, ch)
    if idx == -1 { return none }
    cur = cur.children.at(idx)
  }
  cur
}

// Insert a child in sorted-by-char position (children stay ascending).
#let _insert-child-sorted(children, child) = {
  let pos = 0
  while pos < children.len() and children.at(pos).char < child.char {
    pos += 1
  }
  children.slice(0, pos) + (child,) + children.slice(pos)
}

// Create the path `cps` beneath `node`, marking the endpoint terminal
// when `mark-terminal` is true (else leaving new nodes non-terminal —
// used by the insert animation's suffix-growth frames). Immutable
// rebuild.
#let _ensure-path(cls, node, cps, mark-terminal) = {
  if cps.len() == 0 {
    _node(cls, node.char, node.terminal or mark-terminal, node.children)
  } else {
    let ch = cps.first()
    let idx = _child-index(node, ch)
    let new-children = if idx == -1 {
      _insert-child-sorted(
        node.children,
        _ensure-path(cls, _node(cls, ch, false, ()), cps.slice(1), mark-terminal),
      )
    } else {
      let nc = node.children
      nc.at(idx) = _ensure-path(cls, nc.at(idx), cps.slice(1), mark-terminal)
      nc
    }
    _node(cls, node.char, node.terminal, new-children)
  }
}

// Clear the terminal bit at `cps` (children preserved, no pruning).
#let _unmark(cls, node, cps) = {
  if cps.len() == 0 {
    _node(cls, node.char, false, node.children)
  } else {
    let ch = cps.first()
    let idx = _child-index(node, ch)
    let nc = node.children
    nc.at(idx) = _unmark(cls, nc.at(idx), cps.slice(1))
    _node(cls, node.char, node.terminal, nc)
  }
}

// Remove the child subtree reached by `cps` (which must be non-empty
// and present). Used by the delete animation to prune one node per
// frame; each pruned node is a leaf at removal time.
#let _remove-subtree(cls, node, cps) = {
  let ch = cps.first()
  let idx = _child-index(node, ch)
  let nc = if cps.len() == 1 {
    node.children.slice(0, idx) + node.children.slice(idx + 1)
  } else {
    let m = node.children
    m.at(idx) = _remove-subtree(cls, m.at(idx), cps.slice(1))
    m
  }
  _node(cls, node.char, node.terminal, nc)
}

// Delete `cps` and prune the resulting dead branch. Returns the new
// node, or `none` when the node itself should be pruned (a non-terminal
// leaf after the delete). The public `delete` translates a `none` root
// into an empty root.
#let _delete-rec(cls, node, cps) = {
  if cps.len() == 0 {
    if not node.terminal { return node } // word not stored — no-op
    let unmarked = _node(cls, node.char, false, node.children)
    if unmarked.children.len() == 0 { none } else { unmarked }
  } else {
    let ch = cps.first()
    let idx = _child-index(node, ch)
    if idx == -1 { return node } // word not present — no-op
    let new-child = _delete-rec(cls, node.children.at(idx), cps.slice(1))
    let nc = if new-child == none {
      node.children.slice(0, idx) + node.children.slice(idx + 1)
    } else {
      let m = node.children
      m.at(idx) = new-child
      m
    }
    let rebuilt = _node(cls, node.char, node.terminal, nc)
    if not rebuilt.terminal and rebuilt.children.len() == 0 {
      none
    } else { rebuilt }
  }
}

// Collect every stored word (terminal prefixes), lexicographically
// ordered because children are kept sorted.
#let _words(node, prefix) = {
  let out = ()
  if node.terminal { out.push(prefix) }
  for c in node.children {
    out += _words(c, prefix + c.char)
  }
  out
}

// Every (prefix, node) pair, root-first. Used by the paint helper.
#let _all-nodes(node, prefix) = {
  let out = ((prefix, node),)
  for c in node.children {
    out += _all-nodes(c, prefix + c.char)
  }
  out
}

// ===================================================================
// Per-DS theme — the terminal-node palette
// ===================================================================
//
// The only styling intrinsic to a trie: how word-end nodes are shaded.
// Interior nodes use the structural render-theme defaults. Mirrors the
// RBT red/black palette in `rbt.typ`.

/// Default trie palette. Pass a partial dict to #raw("set-trie-theme(..)")
/// to override individual roles.
#let default-trie-theme = (
  terminal-fill: rgb("#2f855a"),
  terminal-stroke: rgb("#22543d"),
  terminal-text-fill: white,
)

#let _trie-theme-keys = (
  "terminal-fill",
  "terminal-stroke",
  "terminal-text-fill",
)

/// Typsy refinement: a dictionary whose keys are a subset of the
/// trie-theme keys (#raw("terminal-fill"), #raw("terminal-stroke"),
/// #raw("terminal-text-fill")). Used by #raw("set-trie-theme") and the
/// per-call #raw("theme:") arguments to give early errors on typos.
#let TrieTheme = Refine(
  Dictionary(..Any),
  d => d.keys().all(k => _trie-theme-keys.contains(k)),
)

#let _trie-theme-state = state("starling:trie-theme", default-trie-theme)

/// Override one or more trie-theme keys for the rest of the document
/// (state-based, scoped by Typst's normal layout flow). Pass a partial
/// dictionary — only the keys you list are changed; the rest stay at
/// their current values. Unknown keys panic.
#let set-trie-theme(theme) = {
  for k in theme.keys() {
    if not _trie-theme-keys.contains(k) {
      panic(
        "set-trie-theme: unknown key '"
          + k
          + "'. Valid keys: "
          + _trie-theme-keys.join(", ")
          + ".",
      )
    }
  }
  _trie-theme-state.update(prev => {
    let next = prev
    for (k, v) in theme.pairs() { next.insert(k, v) }
    next
  })
}

// Merge a partial trie-theme override into `default-trie-theme`,
// panicking on unknown keys. Used by per-call `theme:` arguments.
#let _merge-trie-theme(override) = {
  for k in override.keys() {
    if not _trie-theme-keys.contains(k) {
      panic(
        "trie-theme: unknown key '"
          + k
          + "'. Valid keys: "
          + _trie-theme-keys.join(", ")
          + ".",
      )
    }
  }
  let next = default-trie-theme
  for (k, v) in override.pairs() { next.insert(k, v) }
  next
}

#let _resolve-trie-theme-arg(theme) = if theme == auto {
  auto
} else { _merge-trie-theme(theme) }

#let _resolve-render-theme-arg(theme) = if theme == auto {
  auto
} else { tree-anim._merge-render-theme(theme) }

// Base styling shared by every trie display: shade the terminal nodes
// (per-DS palette) and stamp each non-root node's edge with its letter.
// The `0`/`1` node bits come from the builder (`draw-tree`), not from
// here. The `paint-rbt` analog. Returns the patched renderer.
#let _paint-trie(r, trie, tt) = {
  let result = r
  for (p, n) in _all-nodes(trie, "") {
    if n.terminal {
      result = (result.patch)(f => (f.style-node)(
        p,
        fill: tt.terminal-fill,
        stroke: tt.terminal-stroke,
        text-fill: tt.terminal-text-fill,
      ))
    }
    if p != "" {
      // The edge into this node carries its letter.
      result = (result.patch)(f => (f.style-edge)(p, tag: n.char))
    }
  }
  result
}

/// Apply the trie palette (terminal-node shading) and edge-letter tags
/// to every node of #raw("trie"), returning the updated
/// #raw("TreeRenderer"). Use this when you're calling #raw("draw-tree")
/// yourself inside a custom #raw("cetz.canvas") — the #raw("*-display")
/// methods do it for you. When #raw("theme: auto") the active
/// #raw("set-trie-theme") state is read, so the call must run inside a
/// #raw("context { .. }") block; pass an explicit partial dict to skip
/// the state lookup.
///
/// -> TreeRenderer
#let paint-trie(r, trie, theme: auto) = {
  let tt = if theme == auto {
    _trie-theme-state.get()
  } else { _merge-trie-theme(theme) }
  _paint-trie(r, trie, tt)
}

// ===================================================================
// Frame construction
// ===================================================================
//
// Mirrors bst.typ / b24.typ. The per-DS trie palette is resolved here
// (from state, or the per-call `theme:` override); the op-theme arrives
// as `op-arg` from the lib.typ helpers, and render-theme from `rt-arg`.
// `build-snapshots(tt, op, rt)` returns an Array(Snapshot) shared across
// all of one phase's frames (single, unchanging tree).
#let _make-frames(
  tree,
  build-snapshots,
  captions,
  steps-meta,
  alts,
  theme,
  render-theme,
) = {
  let n = captions.len()
  range(n).map(i => (tree-anim.Frame.new)(
    _builder: (
      fn: (op-arg, rt-arg) => {
        let tt = if theme == auto { _trie-theme-state.get() } else { theme }
        let rt = if render-theme == auto { rt-arg } else { render-theme }
        let snaps = build-snapshots(tt, op-arg, rt)
        tree-anim._render-canvas(tree, snaps.at(i), (:), (:), rt)
      },
    ),
    caption: captions.at(i),
    step: steps-meta.at(i),
    alt: alts.at(i),
  ))
}

// Multi-tree frame builder for shape-changing phases (insert grows a
// suffix; delete prunes a chain). Each spec carries its own `tree` plus
// a `build(tt, op, rt) -> Snapshot` closure. Mirrors b24.typ's
// `_make-frames-multi`.
#let _make-frames-multi(specs, theme, render-theme) = {
  specs.map(s => (tree-anim.Frame.new)(
    _builder: (
      fn: (op-arg, rt-arg) => {
        let tt = if theme == auto { _trie-theme-state.get() } else { theme }
        let rt = if render-theme == auto { rt-arg } else { render-theme }
        let snap = (s.build)(tt, op-arg, rt)
        tree-anim._render-canvas(s.tree, snap, (:), (:), rt)
      },
    ),
    caption: s.caption,
    step: s.step,
    alt: s.alt,
  ))
}

// Quote a word for alt text / captions.
#let _q(w) = "\"" + w + "\""

// ===================================================================
// The Trie class
// ===================================================================

#let Trie = class(
  name: "Trie",
  fields: (
    // The letter on this node's incoming edge; `none` at the root.
    char: Union(None, Str),
    // Whether a stored word ends at this node.
    terminal: Bool,
    // Child nodes, kept sorted ascending by `char`.
    children: Array(..Any),
  ),
  methods: (
    resolve: (self, prefix) => _resolve-at(self, prefix),

    contains: (self, word) => {
      let n = _resolve-at(self, word)
      n != none and n.terminal
    },

    // True when `prefix` is a path in the trie (whether or not a word
    // ends there).
    has-prefix: (self, prefix) => _resolve-at(self, prefix) != none,

    insert: (self, word) => {
      let cls = self.meta.cls
      _ensure-path(cls, self, word.codepoints(), true)
    },

    insert-many: (self, ..words) => {
      let t = self
      for w in words.pos() { t = (t.insert)(w) }
      t
    },

    delete: (self, word) => {
      let cls = self.meta.cls
      let result = _delete-rec(cls, self, word.codepoints())
      if result == none {
        _node(cls, none, false, ()) // whole trie emptied
      } else { result }
    },

    // Sequence of prefixes visited walking `word`, root-first. Panics
    // if the word's path isn't present.
    path-to: (self, word) => {
      let prefixes = ("",)
      let cur = self
      let p = ""
      for ch in word.codepoints() {
        let idx = _child-index(cur, ch)
        if idx == -1 {
          panic("Trie.path-to: prefix not present: " + repr(word))
        }
        p = p + ch
        prefixes.push(p)
        cur = cur.children.at(idx)
      }
      prefixes
    },

    // Lexicographically-ordered list of stored words.
    words: self => _words(self, ""),

    describe: self => {
      let ws = _words(self, "")
      if ws.len() == 0 {
        "empty trie"
      } else {
        "trie of " + ws.map(_q).join(", ")
      }
    },

    // Returns `none` if all invariants hold, otherwise a message:
    // root char is `none`; every other node's char is a single
    // character; children are strictly ascending by char.
    check-invariants: self => {
      let walk(node, is-root) = {
        if is-root {
          if node.char != none {
            return "root node must have char = none, got " + repr(node.char)
          }
        } else if type(node.char) != str or node.char.clusters().len() != 1 {
          return (
            "non-root node char must be a single character, got "
              + repr(node.char)
          )
        }
        let prev = none
        for c in node.children {
          if prev != none and not (prev < c.char) {
            return (
              "children not strictly sorted by char: "
                + repr(node.children.map(x => x.char))
            )
          }
          prev = c.char
          let e = walk(c, false)
          if e != none { return e }
        }
        none
      }
      walk(self, true)
    },

    // --- display methods --------------------------------------------

    display: (self, theme: auto, render-theme: auto) => {
      // One static frame. `step` is none.
      let captions = (none,)
      let steps-meta = (none,)
      let alts = ("Trie: " + (self.describe)() + ".",)
      let build = (tt, _op, _rt) => {
        let r = tree-anim.make-renderer(self, sticky: true)
        r = _paint-trie(r, self, tt)
        r.snapshots
      }
      _make-frames(
        self,
        build,
        captions,
        steps-meta,
        alts,
        _resolve-trie-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
      )
    },

    search-display: (self, word, theme: auto, render-theme: auto) => {
      // Init frame + one frame per query character. A matched character
      // lights up the descended edge + child node in `search-stroke`.
      // Terminal outcomes: a missing edge rings the last matched node in
      // `danger-stroke`; a full match on a terminal node rings it in
      // `settled-stroke` + `success-fill`; a full match on an interior
      // node is flagged "prefix only".
      //
      // step.kind: "init", "match" (prefix, char), "miss" (prefix, char),
      // "found" (prefix), "prefix" (prefix).
      let cps = word.codepoints()
      let steps = ()
      let cur = self
      let prefix = ""
      let dead = false
      for ch in cps {
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
      let found-terminal = (not dead) and cur.terminal

      let captions = (none,)
      let steps-meta = ((kind: "init"),)
      let alts = (
        "Trie: "
          + (self.describe)()
          + ". About to search for "
          + _q(word)
          + ".",
      )
      for st in steps {
        if st.matched {
          captions.push(raw(st.to))
          steps-meta.push((kind: "match", prefix: st.to, char: st.char))
          alts.push(
            "Matched '"
              + st.char
              + "'; prefix so far "
              + _q(st.to)
              + ".",
          )
        } else {
          captions.push("no '" + st.char + "' edge")
          steps-meta.push((kind: "miss", prefix: st.from, char: st.char))
          alts.push(
            "No edge labelled '"
              + st.char
              + "' from "
              + _q(st.from)
              + "; "
              + _q(word)
              + " is not in the trie.",
          )
        }
      }
      if not dead {
        if found-terminal {
          captions.push("found " + _q(word))
          steps-meta.push((kind: "found", prefix: word))
          alts.push("Reached " + _q(word) + ", a stored word.")
        } else {
          captions.push(_q(word) + " is a prefix only")
          steps-meta.push((kind: "prefix", prefix: word))
          alts.push(
            "Reached "
              + _q(word)
              + ", but it is only a prefix — not a stored word.",
          )
        }
      }

      let build = (tt, op, _rt) => {
        let r = tree-anim.make-renderer(self, sticky: true)
        r = _paint-trie(r, self, tt)
        for st in steps {
          r = (r.push-frame)()
          if st.matched {
            r = (r.patch)(f => (f.style-edge)(st.to, stroke: op.search-stroke))
            r = (r.patch)(f => (f.style-node)(st.to, stroke: op.search-stroke))
          } else {
            r = (r.patch)(f => (f.style-node)(
              st.from,
              stroke: op.danger-stroke,
              note: "no '" + st.char + "'",
            ))
          }
        }
        if not dead {
          r = (r.push-frame)()
          if found-terminal {
            r = (r.patch)(f => (f.style-node)(
              word,
              stroke: op.settled-stroke,
              fill: op.success-fill,
            ))
          } else {
            r = (r.patch)(f => (f.style-node)(
              word,
              stroke: op.attention-stroke,
              note: "prefix",
            ))
          }
        }
        r.snapshots
      }

      _make-frames(
        self,
        build,
        captions,
        steps-meta,
        alts,
        _resolve-trie-theme-arg(theme),
        _resolve-render-theme-arg(render-theme),
      )
    },

    insert-display: (self, word, theme: auto, render-theme: auto) => {
      // Phase A walks the longest existing prefix (search-style). Phase B
      // grows the remaining suffix one node per frame (each a new "0"
      // node in `success-stroke`), then flips the endpoint to terminal
      // ("1", shaded, `success-fill` + `settled-stroke`).
      //
      // step.kind: "init", "walk" (prefix), "add"/"add-last" (path),
      // "mark" (path), "already" (path).
      let cls = self.meta.cls
      let cps = word.codepoints()
      let pre = k => cps.slice(0, k).join("")

      // Longest existing prefix.
      let cur = self
      let existing-prefixes = ()
      let prefix = ""
      for ch in cps {
        let idx = _child-index(cur, ch)
        if idx == -1 { break }
        prefix = prefix + ch
        existing-prefixes.push(prefix)
        cur = cur.children.at(idx)
      }
      let existing-len = existing-prefixes.len()
      let already = existing-len == cps.len() and cur.terminal

      let resolved-theme = _resolve-trie-theme-arg(theme)
      let resolved-rt = _resolve-render-theme-arg(render-theme)

      // Phase A: init + one frame per existing-prefix character.
      let captions-a = (none,)
      let steps-meta-a = ((kind: "init"),)
      let alts-a = (
        "Trie: "
          + (self.describe)()
          + ". About to insert "
          + _q(word)
          + ".",
      )
      for p in existing-prefixes {
        captions-a.push(raw(p))
        steps-meta-a.push((kind: "walk", prefix: p))
        alts-a.push("Prefix " + _q(p) + " already exists; descending.")
      }
      let build-a = (tt, op, _rt) => {
        let r = tree-anim.make-renderer(self, sticky: true)
        r = _paint-trie(r, self, tt)
        for p in existing-prefixes {
          r = (r.push-frame)()
          r = (r.patch)(f => (f.style-edge)(p, stroke: op.search-stroke))
          r = (r.patch)(f => (f.style-node)(p, stroke: op.search-stroke))
        }
        r.snapshots
      }
      let frames-a = _make-frames(
        self,
        build-a,
        captions-a,
        steps-meta-a,
        alts-a,
        resolved-theme,
        resolved-rt,
      )

      // Phase B: suffix growth + terminal mark (or "already present").
      let b-events = ()
      if already {
        b-events.push((tree: self, kind: "already", path: word))
      } else {
        for k in range(existing-len + 1, cps.len() + 1) {
          b-events.push((
            tree: _ensure-path(cls, self, cps.slice(0, k), false),
            kind: if k == cps.len() { "add-last" } else { "add" },
            path: pre(k),
          ))
        }
        b-events.push((tree: (self.insert)(word), kind: "mark", path: word))
      }

      let specs-b = b-events.map(ev => {
        let caption = none
        let step = (kind: ev.kind, path: ev.path)
        let alt = ""
        if ev.kind == "add" or ev.kind == "add-last" {
          caption = raw(ev.path)
          alt = "Added node for prefix " + _q(ev.path) + "."
        } else if ev.kind == "mark" {
          caption = "inserted " + _q(word)
          alt = "Marked " + _q(word) + " as a stored word."
        } else if ev.kind == "already" {
          caption = _q(word) + " already present"
          alt = _q(word) + " is already a stored word; nothing to do."
        }
        let build = (tt, op, _rt) => {
          let r = tree-anim.make-renderer(ev.tree, sticky: false)
          r = _paint-trie(r, ev.tree, tt)
          if ev.kind == "add" or ev.kind == "add-last" {
            r = (r.patch)(f => (f.style-edge)(ev.path, stroke: op.success-stroke))
            r = (r.patch)(f => (f.style-node)(ev.path, stroke: op.success-stroke))
          } else if ev.kind == "mark" {
            r = (r.patch)(f => (f.style-node)(
              ev.path,
              stroke: op.settled-stroke,
              fill: op.success-fill,
            ))
            if ev.path != "" {
              r = (r.patch)(f => (f.style-edge)(ev.path, stroke: op.success-stroke))
            }
          } else if ev.kind == "already" {
            r = (r.patch)(f => (f.style-node)(ev.path, stroke: op.settled-stroke))
          }
          r.snapshots.first()
        }
        (tree: ev.tree, build: build, caption: caption, step: step, alt: alt)
      })
      let frames-b = _make-frames-multi(specs-b, resolved-theme, resolved-rt)

      frames-a + frames-b
    },

    delete-display: (self, word, theme: auto, render-theme: auto) => {
      // Phase A walks to the word's terminal node. Phase B unmarks it
      // (bit "1"->"0", shading gone), then prunes the now-dead branch one
      // node per frame (`danger-stroke` on the node + its edge before it
      // vanishes). Ends on the pruned tree. Panics if `word` isn't a
      // stored word.
      //
      // step.kind: "init", "walk" (prefix), "unmark" (path),
      // "prune-mark" (path), "done".
      let cls = self.meta.cls
      assert(
        (self.contains)(word),
        message: "Trie.delete-display: word not stored: " + repr(word),
      )
      let cps = word.codepoints()

      let resolved-theme = _resolve-trie-theme-arg(theme)
      let resolved-rt = _resolve-render-theme-arg(render-theme)

      // Phase A: search walk (every character matches).
      let walk-prefixes = ()
      let acc = ""
      for ch in cps {
        acc = acc + ch
        walk-prefixes.push(acc)
      }
      let captions-a = (none,)
      let steps-meta-a = ((kind: "init"),)
      let alts-a = (
        "Trie: "
          + (self.describe)()
          + ". About to delete "
          + _q(word)
          + ".",
      )
      for p in walk-prefixes {
        captions-a.push(raw(p))
        steps-meta-a.push((kind: "walk", prefix: p))
        alts-a.push("Descending to " + _q(p) + ".")
      }
      let build-a = (tt, op, _rt) => {
        let r = tree-anim.make-renderer(self, sticky: true)
        r = _paint-trie(r, self, tt)
        for p in walk-prefixes {
          r = (r.push-frame)()
          r = (r.patch)(f => (f.style-edge)(p, stroke: op.search-stroke))
          r = (r.patch)(f => (f.style-node)(p, stroke: op.search-stroke))
        }
        r.snapshots
      }
      let frames-a = _make-frames(
        self,
        build-a,
        captions-a,
        steps-meta-a,
        alts-a,
        resolved-theme,
        resolved-rt,
      )

      // Which nodes get pruned: the leaf `word` (if childless), then each
      // ancestor that is non-terminal with only that child, up the chain.
      let prune-prefixes = ()
      if _resolve-at(self, word).children.len() == 0 {
        prune-prefixes.push(word)
        let j = cps.len() - 1
        while j >= 1 {
          let parent-prefix = cps.slice(0, j).join("")
          let parent = _resolve-at(self, parent-prefix)
          if (not parent.terminal) and parent.children.len() == 1 {
            prune-prefixes.push(parent-prefix)
            j -= 1
          } else { break }
        }
      }

      // Phase B events: unmark, then a danger-mark per pruned node
      // (shown on the tree that still holds it), then the settled result.
      let tree-unmarked = _unmark(cls, self, cps)
      let b-events = ((tree: tree-unmarked, kind: "unmark", path: word),)
      let running = tree-unmarked
      for pp in prune-prefixes {
        b-events.push((tree: running, kind: "prune-mark", path: pp))
        running = _remove-subtree(cls, running, pp.codepoints())
      }
      b-events.push((tree: running, kind: "done", path: word))

      let specs-b = b-events.map(ev => {
        let caption = none
        let step = (kind: ev.kind, path: ev.path)
        let alt = ""
        if ev.kind == "unmark" {
          caption = "unmark " + _q(word)
          alt = "Cleared the word-end mark at " + _q(word) + "."
        } else if ev.kind == "prune-mark" {
          caption = "prune " + _q(ev.path)
          alt = "Node " + _q(ev.path) + " is now a dead branch — removing it."
        } else if ev.kind == "done" {
          caption = "deleted " + _q(word)
          alt = "Deletion of " + _q(word) + " complete."
        }
        let build = (tt, op, _rt) => {
          let r = tree-anim.make-renderer(ev.tree, sticky: false)
          r = _paint-trie(r, ev.tree, tt)
          if ev.kind == "unmark" {
            r = (r.patch)(f => (f.style-node)(
              ev.path,
              stroke: op.attention-stroke,
            ))
          } else if ev.kind == "prune-mark" {
            r = (r.patch)(f => (f.style-node)(ev.path, stroke: op.danger-stroke))
            if ev.path != "" {
              r = (r.patch)(f => (f.style-edge)(ev.path, stroke: op.danger-stroke))
            }
          }
          r.snapshots.first()
        }
        (tree: ev.tree, build: build, caption: caption, step: step, alt: alt)
      })
      let frames-b = _make-frames-multi(specs-b, resolved-theme, resolved-rt)

      frames-a + frames-b
    },
  ),
)

// ===================================================================
// Convenience constructor
// ===================================================================

/// Build a #raw("Trie") from a list of words. Words are inserted
/// left-to-right; the result is an empty-root trie when no words are
/// given.
///
/// ```typc
/// #let t = trie("cat", "car", "card", "dog")
/// ```
///
/// -> dictionary
#let trie(
  /// Positional word strings.
  ..words,
) = {
  let t = (Trie.new)(char: none, terminal: false, children: ())
  for w in words.pos() {
    assert(
      type(w) == str,
      message: "trie: expected a string word, got " + repr(w),
    )
    t = (t.insert)(w)
  }
  t
}
