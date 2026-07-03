// Git graph DSL — the stateful cetz builder (commits, branches, merges,
// tags, HEAD/branch pointers, detached commits) surfaced under the
// `starling.git.*` namespace. This is NOT a `Frame`-based structure, so
// there is no `*-display` / `last` here; each case is a `cetz.canvas`
// wrapping a `git.git-graph({ .. })` block. Covers both layout
// directions and the per-DS theme (per-call `theme:` override, which
// goes through `_merge-git-theme` + the `GitTheme` refinement).
#import "@preview/cetz:0.5.2"
#import "/src/lib.typ" as starling
#import starling: git

#set page(width: auto, height: auto, margin: 0.5in)

#let panel(label, body) = stack(
  dir: ttb,
  spacing: 0.6em,
  align(center, strong(label)),
  body,
)

#grid(
  columns: 2,
  gutter: 2em,
  align: bottom,
  // Full vocabulary: branch, commit, merge, tag, branch-pointer,
  // head-pointer — the default red/orange palette.
  panel(
    [Branch + merge],
    cetz.canvas(git.git-graph({
      git.branch("main")
      git.commit("init")
      git.commit("work")
      git.branch("dev")
      git.commit("feature")
      git.checkout("main")
      git.commit("main work")
      git.merge("dev", message: "merge dev")
      git.branch-pointer("main")
      git.head-pointer()
      git.tag("v1.0")
    })),
  ),
  // Left-to-right layout (commits progress rightward, lanes spread down).
  panel(
    [Horizontal],
    cetz.canvas(git.git-graph(direction: "left-to-right", {
      git.branch("main")
      git.commit("a")
      git.commit("b")
      git.branch("dev")
      git.commit("c")
      git.checkout("main")
      git.commit("d")
    })),
  ),
  // Detached HEAD hung off an orphan commit.
  panel(
    [Detached HEAD],
    cetz.canvas(git.git-graph({
      git.branch("main")
      git.commit("init", name: "root")
      git.commit("work")
      git.detached-commit("root", "orphan", "loose", offset: (1.4, 0.6))
      git.head-pointer(target: "loose")
    })),
  ),
  // Per-call theme: custom palette + thicker edges via `_merge-git-theme`
  // (bypasses `set-git-theme` state entirely).
  panel(
    [Per-call theme],
    cetz.canvas(git.git-graph(
      theme: (
        colors: (teal, maroon, olive),
        graph-style: (stroke: (thickness: 0.4em), radius: 0.15),
      ),
      {
        git.branch("main")
        git.commit("a")
        git.branch("dev")
        git.commit("b")
        git.checkout("main")
        git.commit("c")
        git.merge("dev")
      },
    )),
  ),
)
