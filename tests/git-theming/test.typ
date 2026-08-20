// The git palette is a section of the one theme, so it follows the same
// precedence as every other structure's: `default-theme` < `set-theme`
// state < a per-call `theme:` override. Before 1.0 it was a separate state
// with its own setter, and a per-call theme *replaced* the palette instead
// of layering on it.
//
// The read happens inside git-graph's deferred `set-ctx` closure — the one
// place a cetz builder has a context to read state from — so this also
// covers that the state actually reaches the DSL.
#import "@preview/cetz:0.5.2"
#import "/src/lib.typ" as starling
#import starling: git, set-theme

#set page(width: auto, height: auto, margin: 10pt)

#let panel(label, body) = stack(
  dir: ttb,
  spacing: 0.6em,
  align(center, strong(label)),
  body,
)

// Document-wide palette override (state-based).
#set-theme((
  git: (
    colors: (teal, maroon, olive),
    lane-style: (stroke: (paint: teal, dash: "dotted")),
  ),
))

#let history = {
  git.branch("main")
  git.commit("a")
  git.branch("dev")
  git.commit("b")
  git.checkout("main")
  git.commit("c")
  git.background-lanes()
}

#grid(
  columns: 2,
  gutter: 2em,
  align: bottom,
  panel([From state], cetz.canvas(git.git-graph(history))),
  // Per-call: only the edge thickness and corner radius are named, so the
  // teal/maroon branches and the dotted teal lanes from the state carry
  // through.
  panel(
    [Per-call, layered],
    cetz.canvas(git.git-graph(
      theme: (git: (graph-style: (stroke: (thickness: 0.5em), radius: 0.2))),
      history,
    )),
  ),
)
