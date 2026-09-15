#import "@preview/touying:0.7.3": *
#import "@local/touying-solaris:0.2.0": *

#import "@preview/theorion:0.6.0": *
#import cosmos.clouds: *
#show: show-theorion

#import "@preview/booktabs:0.0.4": *
#show: booktabs-default-table-style

#import "@preview/cetz:0.5.2"
#import "@preview/fletcher:0.5.8" as fletcher: diagram, edge, node
#import fletcher.shapes: chevron, circle, triangle
#let cetz-canvas = touying-reducer.with(
  reduce: cetz.canvas,
  cover: cetz.draw.hide.with(bounds: true),
)
#let fletcher-diagram = touying-reducer.with(
  reduce: fletcher.diagram,
  cover: fletcher.hide,
)

#import "@preview/lovelace:0.3.1": *
#import "@preview/zebraw:0.6.3": *
#show raw: zebraw.with(numbering-separator: true)
#set raw(syntaxes: (
  "00-common-assets/JSX.sublime-syntax",
  "00-common-assets/JavaScript.sublime-syntax",
))
#import "@preview/pinit:0.2.2": *
#show raw: it => {
  show regex("pin\d"): it => pin(eval(it.text.slice(3)))
  it
}

#import "../src/lib.typ" as starling: (
  apply-ops, auto-layout, aux-strip, graph, hashmap, skiplist, sort, trie,
)

#let handout = sys.inputs.at("handout", default: "false") == "true"

#show: solaris-theme.with(
  aspect-ratio: "16-9",
  config-info(
    title: [Final Exam Review],
    subtitle: [_CS 400 -- Programming III_],
    author: [Matt Schwennesen],
    date: datetime(year: 2026, month: 8, day: 5).display(
      "[month repr:long] [day], [year repr:full]",
    ),
    logo: image("./00-common-assets/uw-logo.svg"),
  ),
  config-common(
    handout: handout,
  ),
)

#title-slide(
  logo: image(
    "00-common-assets/uw-logo-horizontal-color-reverse-web-digital.svg",
    height: 1in,
    alt: "University of Wisconsin-Madison logo.",
  ),
)

#outline-slide()

#focus-slide(
  theme: "lemon",
  icon: nf-icon("file_pen"),
  [Final Exam Logistics],
)

#let fmt = "[weekday], [month repr:long] [day], [year] at [hour repr:12]:[minute]:[second] [period] Central Time"

== Final Exam Logistics
#v(-10mm)
- Final exam released #datetime(
    year: 2026,
    month: 08,
    day: 06,
    hour: 0,
    minute: 0,
    second: 0,
  ).display(fmt)
- Final exam due #datetime(
    year: 2026,
    month: 08,
    day: 07,
    hour: 23,
    minute: 59,
    second: 59,
  ).display(fmt)
- Two hour time limit.
- 30 questions, no written code questions.
- Scratch paper allowed and recommended.
- Honorlock required.
  - Google chrome based browser with Honorlock extension

== Final Exam Topics

#columns(2)[
  - Graphs
  - Graph traversals
  - Minimum Spanning Trees
  - Shortest Path
  - Tries
  - Hashtables
  - Linear Sorts
  - Skip Lists
  - Regular Expressions
  - HTML + CSS
  - Web Servers
  - JavaScript
  - GUI Programming
    - Signals
    - JSX
    - Effects & Resources
  - Streams & Pipes
]

#focus-slide(
  theme: "ocean",
  icon: nf-icon("file_pen"),
  [Final Exam Review],
)

== Graphs
#v(-1cm)
#definition-box[Node][
  A _node_ or _vertex_ is an atomic element of a graph.

  #v(-10mm)
  #align(center, stack(
    dir: ltr,
    spacing: 1in,
    math.equation($v in cal(V)$, block: true, alt: "v in calligraphic V."),

    starling.last(graph.display(graph.new((("v", 0, 0),)), theme: (
      render: (
        node-fill: rgb(0, 0, 0, 0),
      ),
    ))),
  ))
]
#definition-box[Edge][
  An _edge_ or _link_ is the connection joining a pair of nodes.

  #v(-10mm)
  #align(center, stack(
    dir: ltr,
    spacing: 1in,
    math.equation(
      $e = {v_1, v_2} in cal(E)$,
      block: true,
      alt: "e equals the set of v sub 1 and v sub 2 which is in calligraphic E.",
    ),

    starling.last(graph.display(
      graph.new((("v", 0, 0), ("u", 3, 0)), edges: (("v", "u", [e]),)),
      theme: (render: (node-fill: rgb(0, 0, 0, 0), note-bg: rgb(0, 0, 0, 0))),
    )),
  ))
]

== Graphs
#definition-box[Graph][
  A _graph_ is a set of *nodes* and a set of *edges*.

  #math.equation(
    $G = (cal(V), cal(E))$,
    alt: "G equals tuple of calligraphic V and calligraphic E",
    block: true,
  )

  #let g = graph.new(
    ("v", "u", "w"),
    edges: (("v", "u", []), ("u", "w", [])),
  )
  #starling.last(
    graph.display(
      g,
      positions: auto-layout(g, engine: "circo"),
      theme: (render: (node-fill: rgb(0, 0, 0, 0), note-bg: rgb(0, 0, 0, 0))),
    ),
  )
]

== Undirected Graph

- Edges are *directionless* #sym.arrow Can go in either direction.
- Example: Friendship network

#{
  let g = graph.new(
    (
      ("A", [Alice]),
      ("B", [Bob]),
      ("C", [Charlie]),
      ("D", [Dan]),
      ("E", [Eric]),
    ),
    edges: (
      ("A", "C", []),
      ("A", "B", []),
      ("B", "C", []),
      ("B", "D", []),
      ("C", "D", []),
      ("D", "E", []),
    ),
  )
  starling.last(graph.display(
    g,
    node-style: (shape: "ellipse", autosize: true),
    layout: "neato",
    scale: 1.5,
  ))
}

== Directed Graph

- Edges are *directed* #sym.arrow They go in a specified direction
- Example: Street map

#{
  let eq = rotate(90deg, text(2em)[=])
  let g = graph.new(
    (
      ("A", 0, 0, text(0.7em)[#pin(2)N. Randall \ University]),
      ("B", 6, 0, text(0.7em)[N. Charter \ University#pin(1)]),
      ("C", 0, -3, text(0.7em)[N. Randall \ Campus]),
      ("D", 6, -3, text(0.7em)[N. Charter \ W. Johnson]),
      ("E", 0, -6, text(0.7em)[N. Randall \ W. Dayton]),
      ("F", 6, -6, text(0.7em)[N. Charter \ W. Dayton]),
    ),
    edges: (
      ("B", "A", []),
      ("B", "D", []),
      ("D", "B", []),
      ("A", "C", []),
      ("C", "D", []),
      ("C", "E", []),
      ("D", "F", []),
      ("F", "D", []),
      ("E", "C", []),
      ("E", "F", []),
      ("F", "E", []),
    ),
    directed: true,
  )
  stack(
    dir: ltr,
    h(1in),
    starling.last(graph.display(
      g,
      node-style: (
        shape: "rectangle",
        autosize: true,
        text-fill: white,
        fill: blue.B,
        stroke: blue.B,
      ),
    )),
    h(3in),
    cetz-canvas({
      import cetz.draw: *
      line((0, 0), (4, 0), stroke: 2pt)
      content((2, -2), eq)
      line((0, -4), (4, -4), stroke: 2pt, mark: (symbol: ">", fill: black))
      content((2, -6), eq)
      line((0, -8), (4, -8), stroke: 2pt, mark: (end: ">", fill: black))
      line((0, -8.25), (4, -8.25), stroke: 2pt, mark: (start: ">", fill: black))
    }),
  )
}
#pinit-point-from(1)[Source node]
#pinit-point-from(
  2,
  offset-dx: -70pt,
  body-dx: -70pt,
  pin-dx: -5pt,
)[Target node]

== Weighted Graph

- Edges can contain *weights / labels*.
- Example: Travel time
#{
  let g = graph.new(
    (
      ("A", 0, 0, text(0.7em)[#pin(2)N. Randall \ University]),
      ("B", 6, 0, text(0.7em)[N. Charter \ University#pin(1)]),
      ("C", 0, -3, text(0.7em)[N. Randall \ Campus]),
      ("D", 6, -3, text(0.7em)[N. Charter \ W. Johnson]),
      ("E", 0, -6, text(0.7em)[N. Randall \ W. Dayton]),
      ("F", 6, -6, text(0.7em)[N. Charter \ W. Dayton]),
    ),
    edges: (
      ("B", "A", 30),
      ("B", "D", 55),
      ("D", "B", []),
      ("A", "C", 40),
      ("C", "D", 35),
      ("C", "E", []),
      ("D", "F", 10, [10#pin(1)]),
      ("F", "D", 120),
      ("E", "C", 20),
      ("E", "F", 25),
      ("F", "E", []),
    ),
    directed: true,
  )
  let r = starling.apply-ops(
    graph.renderer(g, node-style: (
      shape: "rectangle",
      autosize: true,
      text-fill: white,
      fill: blue.B,
      stroke: blue.B,
    )),
    (
      starling.style-edge("D->F", bend: 0.6),
      starling.style-edge("F->D", bend: 0.6),
    ),
  )
  starling.last(starling.render(r))
}

#pinit-point-from(1)[Each direction can have \ a separate weight!]

== Graph Representations

There are multiple ways to *represent* a graph; each is more useful for
*different algorithms* or with a different *set of graphs*.

#{
  let g = graph.new(
    ("A", "B", "C", "D"),
    edges: (
      ("A", "B", []),
      ("A", "C", []),
      ("B", "C", []),
      ("B", "D", []),
      ("C", "D", []),
    ),
    directed: true,
  )
  align(center, stack(
    dir: ltr,
    uncover("2-", graph.adjacency-matrix(g)),
    h(1.5cm),
    align(horizon, cetz-canvas({
      import cetz.draw: *
      uncover("2-", line((0, 0), (3, 0), stroke: 20pt + blue.B, mark: (
        start: ">",
      )))
    })),
    h(0.5cm),
    uncover(
      "1-",
      align(horizon, starling.last(graph.display(g, layout: "circo"))),
    ),
    h(0.5cm),
    align(horizon, cetz-canvas({
      import cetz.draw: *
      uncover("3-", line((0, 0), (3, 0), stroke: 20pt + blue.B, mark: (
        end: ">",
      )))
    })),
    h(1.5cm),
    graph.adjacency-list(g),
  ))
}

== Graph Representation Complexity

#{
  show: booktabs-default-table-style
  align(center, table(
    columns: 3,
    align: (left, center, center),
    inset: 7pt,
    toprule(),
    table.header([Operation], [Adjacency Matrix], [Adjacency List]),
    midrule(), [Space], math.equation($cal(O)(V^2)$, alt: "Big-O of V squared"),
    math.equation($cal(O)(V + E)$, alt: "Big-O of V plus E"),
    [Edge Query],
    math.equation($cal(O)(1)$, alt: "Big-O of 1"),

    math.equation($cal(O)(deg (x))$, alt: "Big-O of the degree of x"),
    [All Neighbors],
    math.equation($cal(O)(V)$, alt: "Big-O of V"),

    math.equation($cal(O)(deg (x))$, alt: "Big-O of the degree of x"),
    bottomrule(),
  ))
}
- Adjacency matrices take up more space but have constant edge query time.
- Adjacency lists take up less space for *sparse graphs*. Operation speeds also
  depend on sparsity.

== Graph Traversals

- *Depth-first* traversal
  - Greedily follow the *first unvisited neighbor*.
  - Similar to in-order, pre-order or post-order tree traversals.
- *Breadth-first* traversal
  - Explore all nodes 1 edge away from the start, then all nodes 2 edges away, 3
    edges away, etc...
  - Similar to level-order tree traversals.

== Graph Traversals -- DFS

#columns(2)[
  #text(0.8em, pseudocode-list[
    DFT(_v_):
    + _s_ #sym.arrow.l stack
    + _s_.push(v)
    + while _s_ is *not empty* do
      + _v_ #sym.arrow.l _s_.pop()
      + #pin("1")mark _v_ as *visited*
      + for each *neighbor* _u_ of _v_ do#pin("2")
        + if _v_ is *unvisited* then
          + _s_.push(_u_)#pin("3")
  ])
  #pinit-rect(
    "1",
    "2",
    "3",
    extended-width: 0.2em,
    dy: -0.5em,
    dx: -2pt,
    stroke: color.orange + 2pt,
  )

  #colbreak()
  #align(bottom, text(0.8em, pseudocode-list[
    DFT(_v_):
    + mark _v_ as *visited*
    + for each *neighbor* _u_ of _v_ do
      + if _u_ is *unvisited*:
        + DFT(_u_)
  ]))
]

== Graph Traversals -- DFS Example

#{
  let e(s, t) = ((s, t, []),)
  let u(s, t) = ((s, t, []), (t, s, []))
  let g = graph.new(
    ("A", "B", "C", "D", "E", "F", "G", "H", "I"),
    edges: u("A", "B")
      + e("A", "G")
      + e("A", "D")
      + e("B", "C")
      + e("C", "E")
      + e("D", "C")
      + e("D", "F")
      + e("E", "B")
      + e("E", "F")
      + e("E", "G")
      + e("E", "H")
      + e("F", "I")
      + e("G", "F")
      + e("H", "F"),
    directed: true,
  )
  let frames = graph.dfs-display(g, "A", layout: "patchwork", layout-unit: 8pt)
  grid(
    columns: (1fr, 1fr),
    column-gutter: 0em,
    align: horizon,
    alternatives(..frames.map(f => starling.canvas(f))),
    stack(
      dir: ttb,
      spacing: 1.2em,
      alternatives(..frames.map(f => starling.aux-strip(f.step))),
      alternatives(..frames.map(f => {
        f.caption
      })),
    ),
  )
}

== Graph Traversal -- BFS

#v(-2em)
#pseudocode-list[
  BFT(_v_):
  + _q_ #sym.arrow.l *queue*
  + *enqueue* _v_ and mark _v_ *visited*
  + while _q_ is not empty do
    + *dequeue* the next node _w_
    + for each *neighbor* _u_ of _w_#pin("w") do
      + if _u_ is *unvisited*
        + mark _u_ *visited*
        + *enqueue* _u_
]
#pinit-point-from(
  "w",
)[Different order of neighbors lead \ to different visitation orders]

== Graph Traversal -- BFS Example

#{
  let e(s, t) = ((s, t, []),)
  let u(s, t) = ((s, t, []), (t, s, []))
  let g = graph.new(
    ("A", "B", "C", "D", "E", "F", "G", "H", "I"),
    edges: u("A", "B")
      + e("A", "D")
      + e("A", "G")
      + e("B", "C")
      + e("C", "E")
      + e("D", "C")
      + e("D", "F")
      + e("E", "B")
      + e("E", "F")
      + e("E", "G")
      + e("E", "H")
      + e("F", "I")
      + e("G", "F")
      + e("H", "F"),
    directed: true,
  )
  let frames = graph.bfs-display(g, "A", layout: "patchwork", layout-unit: 8pt)
  grid(
    columns: (1fr, 1fr),
    column-gutter: 0em,
    align: horizon,
    alternatives(..frames.map(f => starling.canvas(f))),
    stack(
      dir: ttb,
      spacing: 1.2em,
      alternatives(..frames.map(f => starling.aux-strip(f.step))),
      alternatives(..frames.map(f => {
        f.caption
      })),
    ),
  )
}

== Graph Traversal -- Complexity

#align(center, table(
  columns: 3,
  inset: 7pt,
  toprule(),
  table.header([Traversal], [Adjacency List], [Adjacency Matrix]),
  midrule(),

  [DFS],
  math.equation($cal(O)(V + E)$, alt: "Big-O of V plus E"),
  math.equation($cal(O)(V^2)$, alt: "Big-O of V squared"),

  [BFS],
  math.equation($cal(O)(V + E)$, alt: "Big-O of V plus E"),
  math.equation($cal(O)(V^2)$, alt: "Big-O of V squared"),

  bottomrule(),
))

- Finding all neighbors in adjacency list is #math.equation(
    $cal(O)(deg (x))$,
    alt: "Big-O of the degree of x",
  ).
- Finding all neighbors in adjacency matrix is #math.equation(
    $cal(O)(V)$,
    alt: "Big-O of V",
  ).

== Minimum Spanning Trees

#v(-1cm)
#definition-box[Minimum Spanning Tree][
  A minimum spanning tree _T_ of a graph _G_ is the spanning tree with the
  smallest sum of edge weights.
]

#{
  let g = graph.new(
    (("A", 0, 0), ("B", 1, 0), ("C", 0, -1), ("D", 1, -1)),
    edges: (("C", "D", 9), ("B", "D", 7)),
  )
  align(center, grid(
    columns: 3,
    column-gutter: 1in,
    row-gutter: 0.5em,
    align: center + horizon,
    [Option 1], [Option 2], [Room Layout],
    {
      let g = graph.add-edge(g, "A", "B", weight: 10)
      starling.last(graph.display(g, scale: 2))
    },
    {
      let g = graph.add-edge(g, "A", "C", weight: 5)
      starling.last(graph.display(g, scale: 2))
    },
    {
      let g = graph.add-edge(g, "A", "B", weight: 10)
      g = graph.add-edge(g, "A", "C", weight: 5)
      starling.last(graph.display(g, scale: 2))
    },

    [*Cost: 26*], [*Cost: 21*],
  ))
}

== MST -- Prim's Algorithm
#v(-1.8cm)
#pseudocode-list[
  prim(_v_)
  + _q_ #sym.arrow.l new *priority queue*#pin("q")
  + *insert* all edges of _v_ in _q_ and mark _v_ as *visited*
  + while _q_ is *not empty*:
    + *remove* minimum edge {_w_, _u_} from _q_
    + if _u_ *is unvisited*
      + *add* {_w_, _u_} to the spanning tree
      + *insert* all edges of _u_ into _q_
      + mark _u_ as *visited*
  #pinit-point-from(
    "q",
    offset-dy: -50pt,
    pin-dy: -5pt,
    body-dy: -15pt,
    body-dx: -1pt,
    stroke: color.orange,
    fill: color.orange,
    box(fill: color.orange, inset: 7pt, radius: 3pt)[Implement ADT with heap],
  )
]

== MST -- Prim's Example

#let prim_tree = none
#{
  let g = graph.new(
    ("A", "B", "C", "D", "E", "F", "G", "H", "I"),
    edges: (
      ("A", "B", 3),
      ("A", "D", 5),
      ("B", "C", 5),
      ("B", "E", 1),
      ("C", "F", 1),
      ("D", "E", 4),
      ("D", "G", 4),
      ("E", "F", 5),
      ("E", "H", 1),
      ("F", "I", 2),
      ("G", "H", 3),
      ("H", "I", 3),
    ),
  )
  let layout = (
    "A": (0, 2),
    "B": (1, 2),
    "C": (2, 2),
    "D": (0, 1),
    "E": (1, 1),
    "F": (2, 1),
    "G": (0, 0),
    "H": (1, 0),
    "I": (2, 0),
  )
  let frames = graph.prim-display(
    g,
    "A",
    positions: layout,
    scale: 2.5,
  )
  prim_tree = (frames.last(),)
  grid(
    columns: (1fr, 1fr),
    column-gutter: 0em,
    align: horizon,
    stack(
      dir: ttb,
      spacing: 1.2em,
      alternatives(..frames.map(f => starling.canvas(f))),
      alternatives(..frames.map(f => {
        f.caption
      })),
    ),
    alternatives(..frames.map(f => starling.aux-strip(f.step))),
  )
}

== MST -- Kruskal's Algorithm

#v(-1.8cm)
#pseudocode-list[
  kruskal(_V_, _L_)
  + sort *edge list _L_*
  + _s_ #sym.arrow.l #math.equation(
      $[{v_1}, {v_2}, ..., {v_n}]$,
      alt: "union-find data structure with each node in it's own set.",
    )#pin("s")
  + while _L_ is not empty:
    + *remove* {_w_, _u_} from _L_
    + if _u_ and _w_ are *not* in the same set in _s_:
      + add {_w_, _u_} to the spanning tree
      + *join* the sets for _u_ and _w_ in _s_
]
#pause
#pinit-point-from(
  "s",
  body-dy: -15pt,
  body-dx: -1pt,
  stroke: color.orange,
  fill: color.orange,
  box(fill: color.orange, inset: 7pt, radius: 3pt)[Union-find data structure],
)

== MST -- Kruskal's Example

#let kruskal_tree = none
#{
  let g = graph.new(
    ("A", "B", "C", "D", "E", "F", "G", "H", "I"),
    edges: (
      ("A", "B", 3),
      ("A", "D", 5),
      ("B", "C", 5),
      ("B", "E", 1),
      ("C", "F", 1),
      ("D", "E", 4),
      ("D", "G", 4),
      ("E", "F", 5),
      ("E", "H", 1),
      ("F", "I", 2),
      ("G", "H", 3),
      ("H", "I", 3),
    ),
  )
  let layout = (
    "A": (0, 2),
    "B": (1, 2),
    "C": (2, 2),
    "D": (0, 1),
    "E": (1, 1),
    "F": (2, 1),
    "G": (0, 0),
    "H": (1, 0),
    "I": (2, 0),
  )
  let frames = graph.kruskal-display(
    g,
    positions: layout,
    scale: 2.5,
  )
  kruskal_tree = (frames.last(),)
  grid(
    columns: (1fr, 1fr),
    column-gutter: -8em,
    align: horizon,
    stack(
      dir: ttb,
      spacing: 1.2em,
      alternatives(..frames.map(f => starling.canvas(f))),
      alternatives(..frames.map(f => {
        f.caption
      })),
    ),
    text(size: 0.7em, font: "JetBrainsMono NF", alternatives(..frames.map(
      f => starling.aux-strip(f.step),
    ))),
  )
}

== Shortest Path
#v(-2cm)
#text(0.7em, pseudocode-list[
  Dijkstra(_start_)
  + visited #sym.arrow.l *new* Map; dist #sym.arrow.l *new* Map
  + queue #sym.arrow.l *new* Priority Queue; prev #sym.arrow.l *new* Map
  + queue.add(_start_, 0); dist[_start_] #sym.arrow.l 0; prev[_start_]
    #sym.arrow.l #sym.emptyset
  + while queue *is not empty*:
    + _u_ #sym.arrow.l queue.poll()
    + if _u_ is *not visited*:
      + mark _u_ as *visited*
      + for each neighbor _v_ of _u_:
        + if _v_ is *not visited*:
          + _new-dist_ #sym.arrow.l dist[_u_] + cost(_u_, _v_)
          + if _new-dist_ \< dist[_v_]:
            + queue.add(_v_, _new-dist_); dist[_v_] #sym.arrow.l _new-dist_;
              prev[_v_] #sym.arrow.l _u_
])

== Shortest Path
#v(-1.5cm)
#pseudocode-list[
  ConstructShortestPath(_prev_, _dest_)
  + _path_ #sym.arrow.l *new* List
  + _current_ #sym.arrow.l _dest_
  + while _current_ *is not null*:
    + insert _current_ at the *beginning* of _path_
    + _current_ #sym.arrow.l prev[_current_]
  + return _path_
]

== Shortest Path -- Example

#{
  let g = graph.new(
    ("A", "B", "C", "D", "E", "F", "G", "H", "I"),
    edges: (
      ("A", "B", 3),
      ("A", "D", 5),
      ("B", "C", 5),
      ("B", "E", 1),
      ("C", "F", 1),
      ("D", "E", 4),
      ("D", "G", 4),
      ("E", "F", 5),
      ("E", "H", 1),
      ("F", "I", 2),
      ("G", "H", 3),
      ("H", "I", 3),
    ),
  )
  let layout = (
    "A": (0, 2),
    "B": (1, 2),
    "C": (2, 2),
    "D": (0, 1),
    "E": (1, 1),
    "F": (2, 1),
    "G": (0, 0),
    "H": (1, 0),
    "I": (2, 0),
  )
  let frames = graph.dijkstra-display(
    g,
    positions: layout,
    scale: 2.5,
    "A",
    target: "F",
    node-distances: false,
    reconstruct: true,
  )
  grid(
    columns: (1fr, 1fr),
    column-gutter: -8em,
    align: horizon,
    stack(
      dir: ttb,
      spacing: 1.2em,
      alternatives(..frames.map(f => starling.canvas(f))),
      alternatives(..frames.map(f => {
        f.caption
      })),
    ),
    text(size: 0.7em, font: "JetBrainsMono NF", alternatives(..frames.map(
      f => grid(
        columns: 2,
        column-gutter: 1em,
        row-gutter: 2em,
        grid.cell(rowspan: 2, aux-strip(f.step, view: "dist-pq", title: true)),
        aux-strip(f.step, view: "dist-map", title: true),
        aux-strip(f.step, view: "prev-map", title: true),
      ),
    ))),
  )
}

== Tries
#v(-1.2cm)
#definition-box[Trie][
  Also called a "prefix tree", a data structure which stores a set of strings
  which can be queried by their prefixes.
]
#v(-0.8cm)
- Tries allow a user to query strings based on prefixes and they support
  *quickly resolving an update* to the query.
- Tries are a graph, but rather than storing data on the nodes, we *store the
  data along the edges*.
- Each edge corresponds to a *single character* in the string which is
  represented by a *path in the tree*.

== Tries -- Lookup

#pseudocode-list[
  + Start at the *root*
  + For each letter in the word we are looking up:
    + If there is an edge corresponding to that letter:
      + Take *that edge* to the next node
    + Else
      + Return *false*
  + If the current node is *final*, return *true*, else return *false*
]

== Tries -- Lookup Example

- Lookup "cats"

#align(center, scale(x: 90%, y: 90%, reflow: true, alternatives(
  ..starling.figures(
    trie.search-display(trie.new("car", "cat", "cars", "cart", "carp"), "cats"),
  ),
)))

== Tries -- Insert

#pseudocode-list[
  + Start at the *root*
  + For each letter in the word we are looking up:
    + If there is an edge corresponding to that letter:
      + Take *that edge* to the next node
    + Else
      + Return *false*
  + If the current node is *final*, return *true*, else return *false*
]

== Tries -- Insert Example
- Insert "saw"
#let insert_trie = trie.new("sets", "sew", "set")
#align(center, scale(x: 90%, y: 90%, reflow: true, alternatives(
  ..starling.figures(
    trie.insert-display(insert_trie, "saw"),
  ),
)))
#(insert_trie = trie.insert(insert_trie, "saw"))

== Tries -- Insert Example
- Insert "saw"
#align(center, scale(x: 90%, y: 90%, reflow: true, starling.last(
  trie.display(insert_trie),
)))

== Tries -- Deletion

#pseudocode-list[
  + Perform a *lookup* of the word
  + Set the current node to *non-final* to remove it from trie
  + While the current node is *not the root node*:
    + If the current node is *non-final* and has *no children*:
      + *Delete* the node from the trie
    + Set current node to the *parent* node
]

== Tries -- Deletion Example
- Delete "saw"
#let delete_trie = insert_trie
#align(center, scale(x: 90%, y: 90%, reflow: true, alternatives(
  ..starling.figures(
    trie.delete-display(insert_trie, "saw"),
  ),
)))

== Linear Sorts -- Counting Sort
#v(-1.5cm)
#text(size: 0.75em, font: "JetBrainsMono NF", pseudocode-list[
  + count #sym.arrow.l array of _k_ zeros
  + output #sym.arrow.l array same length as input
  + *for* _i_ #sym.arrow.l 0 *to* length(input) - 1 *do*#pin(1)
    + _j_ #sym.arrow.l key(input[_i_])
    + count[_j_] #sym.arrow.l count[_j_] + 1
  + *for* _i_ #sym.arrow.l 1 *to* _k_ *do*#pin(2)
    + count[_i_] #sym.arrow.l count[_i_] + count[_i_ - 1]
  + *for* _i_ #sym.arrow.l length(input) - 1 *to* 0 *do*#pin(3)
    + _j_ #sym.arrow.l key(input[_i_])
    + count[_j_] #sym.arrow.l count[_j_] - 1
    + output[count[_j_]] #sym.arrow.l input[_i_]
])
#pinit-point-from(1)[Count Values]
#pinit-point-from(
  2,
  offset-dy: 0pt,
  offset-dx: 100pt,
  body-dy: -10pt,
  pin-dy: -5pt,
)[Convert to Cumulative]
#pinit-point-from(3)[Copy to Output]

== Linear Sorts -- Radix Sort
#v(-1.25cm)
#definition-box[Radix Sort][
  A linear sort using *counting sort*'s stability to sort each digit one at a
  time.
]
#v(-7mm)
- Can compare digits right-to-left / least significant digit (*LSD*) or
  left-to-right / most significant digit (*MSD*).
- We will *only use LSD* in this course.

#align(
  center,
)[#text(fill: green.B)[8]#text(fill: blue.B)[1]#text(fill: color.orange)[2],
  #text(fill: green.B)[9]#text(fill: blue.B)[9]#text(fill: color.orange)[5]]

- LSD #sym.arrow #text(fill: color.orange)[Digit 2], #text(fill: blue.B)[Digit
    1], #text(fill: green.B)[Digit 0]
- MSD #sym.arrow #text(fill: green.B)[Digit 0], #text(fill: blue.B)[Digit 1],
  #text(fill: color.orange)[Digit 2]

== Linear Sorts -- Radix Example

#{
  let s = sort.new(812, 995, 078, 781, 709, 377, 736, 795)
  alternatives(..starling.figures(sort.radix-display(s)))
}

== Skip Lists
#v(-1cm)
#definition-box[Skip List][
  A linked-list like data structure were you can jump *more than one node* at a
  time by including *multiple next pointers*.
]
#{
  let l = skiplist.new(
    (value: 24, height: 4),
    (value: 37, height: 1),
    (value: 40, height: 2),
    (value: 44, height: 1),
    (value: 50, height: 3),
    (value: 68, height: 1),
    (value: 70, height: 2),
    (value: 73, height: 1),
    (value: 94, height: 4),
    nil: false,
  )
  starling.last(skiplist.display(l))
}

== Skip List -- Lookup
#v(-1em)
#pseudocode-list[
  + Start at the head node and the most express lane
  + While the *current node* is *not null*:
    + *Peek* ahead at the next node
    + If the lookup value is found, return *true*
    + If the lookup value is *less* than the peeked value:
      + Move to the *next slower lane*
    + Otherwise take one step ahead, update *next node*
  + Return *false* if the node was not found
]

== Skip List -- Lookup Example
- Lookup *73*

#{
  let l = skiplist.new(
    (value: 24, height: 4),
    (value: 37, height: 1),
    (value: 40, height: 2),
    (value: 44, height: 1),
    (value: 50, height: 3),
    (value: 68, height: 1),
    (value: 70, height: 2),
    (value: 73, height: 1),
    (value: 94, height: 4),
    nil: false,
  )
  alternatives(..starling.figures(skiplist.search-display(l, 73)))
}

== HTML + CSS + JavaScript
Some HTML tags. This is not an exhaustive list.
- ```html <html>``` #sym.arrow Root of an HTML document.
- ```html <head>``` #sym.arrow Page metadata.
- ```html <body>``` #sym.arrow Page content.
- ```html <p>``` #sym.arrow Paragraph of text.
- ```html <h1>, <h2>, ..., <h6>``` #sym.arrow Section headings.
- ```html <a>``` #sym.arrow Hyperlink / "anchor".
- ```html <img>``` #sym.arrow Image.
- ```html <div>``` #sym.arrow Container to group other elements.

== HTML + CSS + JavaScript

#figure(
  image("00-common-assets/html.png", height: 4.2in),
  alt: "Structure of an html document, shown as a series of nested boxes.",
)

== HTML + CSS + JavaScript

#v(-1cm)
```css
h2 { /* Apply to all h2 tags */
  color: orange;
  text-decoration: underline;
}
.bolded { /* Apply to elements with class="bolded" */
  font-weight: bold;
}
#apple { /* Apply to elements with id="apply" */
  color: red;
  text-decoration: underline;
}
```

== HTML + CSS + JavaScript

#text(0.8em)[
  ```js
  function init_ratings() {
    for (const [_, title_code] of Object.entries(titles)) {
      fetch("http://127.0.0.1:8080/query?title=" + title_code)
        .then(result => result.text())
        .then(r => {
          let elem = document.querySelector(
            "#" + title_code + "-rating"
          )
          elem.innerHTML = "&diams;".repeat(r)
        })
    }
  }
  ```
]

== GUI Programming

#text(0.9em)[
  #v(-1cm)
  #definition-box[Declarative UI][
    A user interface paradigm where the develop describes what the UI should
    look like for the current data. The framework works out which DOM updates
    make that true.
  ]
  - *Imperative* #sym.arrow find the node, then set its `innerHTML`,
    _everywhere, on every change._
  - *Declarative* #sym.arrow the span is the book's rating, and stays updated:

  ```jsx
  <span>{"♦".repeat(rating())}</span>
  ```
]

== GUI Programming -- JSX

```jsx
function App() {
  return (
    <>pin1
      <h1>Book Ratings</h1>
      <img src=pin2{cover}pin3 width="150"/>pin4
    </>​
  );
}
```
#pinit-point-from((2, 3), offset-dy: 70pt, body-dx: -10pt, body-dy: -10pt, box(
  fill: black,
  inset: 7pt,
  radius: 5%,
  text(fill: white)[Embed JavaScript in HTML],
))
#pinit-point-from(4, body-dx: -10pt, body-dy: -10pt, box(
  fill: black,
  inset: 7pt,
  radius: 5%,
  text(
    fill: white,
  )[Every tag must close],
))
#pinit-point-from(
  1,
  offset-dy: -7pt,
  offset-dx: 50pt,
  body-dy: -15pt,
  body-dx: -10pt,
  pin-dy: -7pt,
  box(
    fill: black,
    inset: 7pt,
    radius: 5%,
    text(
      fill: white,
    )[Must return one top-level element],
  ),
)

== GUI Programming -- Components & Props
Data flows *down* into a component as *properties* or props.

#align(center, fletcher-diagram(spacing: 1.6em, node-stroke: black, {
  node((0, 0), [`App`], name: <app>)
  node((2, -0.55), [`Book`], name: <b1>)
  node((2, 0), [`Book`], name: <b2>)
  node((2, 0.55), [`Book`], name: <b3>)
  edge(<app>, <b1>, "-|>", [props])
  edge(<app>, <b2>, "-|>")
  edge(<app>, <b3>, "-|>")
}))

```jsx
function Book(propspin1) {
  return <div id={props.code}>
    {props.title} by {props.author}</div>;
}
```
#pinit-point-from(
  1,
  offset-dy: -40pt,
  offset-dx: 75pt,
  body-dy: -15pt,
  body-dx: -10pt,
  pin-dy: -7pt,
  box(
    fill: black,
    inset: 7pt,
    radius: 5%,
    text(
      fill: white,
    )[Don't destructure `props`],
  ),
)

== GUI Programming -- Signals
#v(-1cm)
#definition-box[Signal][
  A reactive value. Read it with `s()`, write it with `setS(v)`. Solid re-runs
  only the spots that read `s()`.
]

```jsx
const [rating, setRating] = createSignal(5);
const diamonds = () => "♦".repeat(rating());
```

- `diamonds` is a *derived* value #sym.arrow a function of the signal.
- The component body runs *once*; there is no whole-component re-render.

== GUI Programming -- Callbacks

#align(center, fletcher-diagram(spacing: 5em, node-stroke: black, {
  node((0, 0), [`App`], name: <app>)
  node((2, 0), [`Book`], name: <book>)
  edge(<app>, <book>, "-|>", [`rating` (prop)], bend: 20deg)
  edge(<book>, <app>, "-|>", [`onRate()` (event)], bend: 20deg)
}))

- Lift shared state to the common parent (`App`).
- Data flows *down* as props; a *callback* prop sends events *up*.
- One update site: `rate(code, value)`.

== GUI Programming -- Effects & Resources
#v(-1cm)
#definition-box[Effect][
  Runs a side effect whenever the signals it *reads* change. Useful for when you
  need to interact with a server.
]
#definition-box[Resource][
  An asynchronous effect. Exposes more information about the state of the
  asynchronous request.
]


#focus-slide(
  theme: "mandarine",
  icon: nf-icon("file_pen"),
  [Practice Exam],
)
