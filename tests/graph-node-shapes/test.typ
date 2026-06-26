// Graph node shapes and sizing via `node-style:`, plus the displays'
// internal `layout:` argument. `node-style` applies one base node style
// across the whole graph (merged beneath per-frame algorithm styling).
// "ellipse" and autosize fit long labels (names) that overflow the
// fixed circle; edges trim to each shape's true boundary. The last page
// exercises `layout:` (the display calls auto-layout itself, the only
// page that pulls diagraph-layout) with `sizes: auto` heuristic spacing.
#import "/src/lib.typ" as starling
#import starling: graph

// Names overflow the default circle — manual positions keep pages 1–3
// deterministic (autosize measures the label, independent of layout).
#let people = graph(
  (
    ("A", 0, 0, [Alice]),
    ("B", 3, 0, [Bob]),
    ("C", 1.5, 2.4, [Charlie]),
    ("D", 4.5, 2.4, [Dan]),
  ),
  edges: (
    ("A", "B", 1),
    ("A", "C", 1),
    ("B", "C", 1),
    ("B", "D", 1),
    ("C", "D", 1),
  ),
)

// Fixed ellipse (default rx/ry).
#starling.last((people.display)(node-style: (shape: "ellipse")))

// Autosize ellipse — each node fits its own name.
#starling.last((people.display)(node-style: (shape: "ellipse", autosize: true)))

// Autosize rectangle, exercised through a traversal so per-frame fills
// merge over the doc-wide shape and the trim stays shape-aware.
#starling.last((people.dfs-display)(
  "A",
  node-style: (shape: "rectangle", autosize: true),
))

// Internal layout: the display lays the graph out itself (sizes: auto
// heuristic) and draws autosize ellipses. Pulls diagraph-layout.
#starling.last((people.display)(
  node-style: (shape: "ellipse", autosize: true),
  layout: "neato",
))
