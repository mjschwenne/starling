// `scale:` spreads manually-positioned nodes apart while their drawn
// size stays fixed — the manual-layout analog of auto-layout's `unit:`.
// Page 1 is the default (scale 1); page 2 is the same graph at scale
// 1.6 (wider gaps, identical node/label/weight sizes).
#import "/src/lib.typ" as starling
#import starling: graph

#let g = graph(
  (("A", 0, 0), ("B", 3, 1), ("C", 1.5, 2.6), ("D", 4.5, 2.6)),
  edges: (
    ("A", "B", 7),
    ("B", "C", 2),
    ("A", "C", 4),
    ("C", "D", 5),
    ("B", "D", 1),
  ),
)

#starling.last((g.display)())
#starling.last((g.display)(scale: 1.6))
