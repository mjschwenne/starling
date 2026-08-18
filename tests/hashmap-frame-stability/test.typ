// The insert/search/delete animations must keep the table in a fixed place on
// the slide: when the hash box appears on the second subslide the canvas must
// not grow, or the table jumps. The leading `init` frame reserves the hash
// box's footprint with an invisible "ghost" box, so every pre-mutation frame
// (init + hash + probe/compare walk) renders at identical canvas dimensions.
// This asserts that equality directly (independent of pixel refs).
#import "/src/lib.typ" as starling
#import starling: default-theme, hashmap

#set page(width: auto, height: auto, margin: 2pt)


// Dimensions of a frame's rendered canvas.
#let dims-of(f) = {
  let m = measure((f.builder)(default-theme))
  (w: m.width, h: m.height)
}

// Every frame up to (but excluding) the terminal mutation shares the walk's
// footprint — the ghost hash box on `init` matches the real box that follows.
#let check-stable(frames, mutation-kinds) = context {
  let pre = frames.filter(f => f.step.kind not in mutation-kinds)
  assert(pre.len() >= 2, message: "expected a multi-frame walk")
  let d0 = dims-of(pre.first())
  for f in pre {
    let d = dims-of(f)
    assert(
      d.w == d0.w and d.h == d0.h,
      message: "frame '" + f.step.kind + "' size " + repr(d) + " != init " + repr(d0),
    )
  }
}

// Single-axis stability. Chaining's terminal frame legitimately changes the
// *along-chain* dimension as the chain grows (insert) or shrinks (delete): the
// chain hangs downward when horizontal (height moves) and rightward when
// vertical (width moves). The *other* axis must stay pinned — a ghost hash box
// over an end cell reserves the same footprint as the visible box before it, so
// the table never slides on the fixed axis.
#let check-axis-stable(frames, axis) = context {
  assert(frames.len() >= 2, message: "expected a multi-frame walk")
  let d0 = dims-of(frames.first())
  for f in frames {
    let d = dims-of(f)
    assert(
      d.at(axis) == d0.at(axis),
      message: "frame '" + f.step.kind + "' " + axis + " " + repr(d.at(axis)) + " != " + repr(d0.at(axis)),
    )
  }
}

// Open addressing (linear) — a multi-probe insert.
#let l = hashmap.new(7, strategy: "linear", entries: (14, 21, 7))
#check-stable(hashmap.insert-display(l, 28), ("insert", "update", "full"))

// Chaining — insert that walks the bucket, both orientations.
#let c = hashmap.new(5, strategy: "chaining", entries: (5, 10, 7))
#check-stable(hashmap.insert-display(c, 20), ("insert", "update"))
#check-stable(hashmap.insert-display(c, 20, orientation: "vertical"), ("insert", "update"))

// Search and delete share the same leading walk.
#check-stable(hashmap.search-display(l, 7), ("found", "not-found"))
#check-stable(hashmap.search-display(hashmap.delete(l, 21), 7), ("found", "not-found"))

// Open-addressing delete is pinned end-to-end: the terminal tombstone frame
// (and the naive `cleared` variant) fills the existing cell and carries a ghost
// hash box, so the WHOLE animation renders at one canvas size — no jump up when
// the box vanishes, no slide sideways when it sat over an end cell.
#check-stable(hashmap.delete-display(l, 21), ())
#check-stable(hashmap.delete-display(l, 21, tombstone: false), ())

// Chaining delete: the chain retracts along its own axis (height when
// horizontal, width when vertical), but the ghost hash box pins the cross axis
// so the table never slides there — the end-cell jump this bug fix removed.
#check-axis-stable(hashmap.delete-display(c, 10), "w")
#check-axis-stable(hashmap.delete-display(c, 10, orientation: "vertical"), "h")

// A large (touying-like) font must stay stable too.
#[
  #set text(size: 24pt)
  #check-stable(hashmap.insert-display(c, 20), ("insert", "update"))
]

// Placeholder page so tytanic has something to compare.
#align(center, text(fill: green, [frame-stability OK]))
