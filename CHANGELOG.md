# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0]

<details>
<summary>Migration guide from v0.1.X</summary>

The `*-display` methods now return `Array(Frame)` instead of pre-wrapped
content. Each `Frame` is a record `(canvas, caption, step)`. The
`configure(wrap: ...)` entrypoint and the closure-captured `wrap`
parameter are gone — wrap the frames yourself with one of the new
helpers (`last`, `stacked`, `figures`, `canvases-only`).

**Static use:**

```typ
// before
#(t.insert-display)(5)

// after
#starling.last((t.insert-display)(5))
```

**Touying:**

```typ
// before
#let (BST,) = (starling.configure)(wrap: alternatives)
#(t.search-display)(6)

// after
#import starling: BST
#alternatives(..starling.figures((t.search-display)(6)))
```

**Custom slide layouts:**

```typ
#let frames = (t.search-display)(6)
#grid(columns: 2,
  alternatives(..starling.figures(frames, caption: false)),
  alternatives(..frames.map(f => f.caption)),
)
```

`Op.Caption` was removed from the `Op` enum. Captions are renderer-level
now, set directly via `r.with-caption(...)` between Op batches.

The internal `Frame` typsy class (a sparse style overlay) was renamed
`Snapshot`. `blank-frame` is now `blank-snapshot`. The public `Frame`
name now refers to the output record described above.

The rotation animation gained a "restructure" frame between breaking
the old edges and connecting the new ones, plus a final settled frame
with highlights cleared. The dashed-red "edge about to break"
intermediate frame was dropped.

</details>

### Changed

- `*-display` methods return `Array(Frame)`; wrap with `starling.last`,
  `starling.stacked`, or `starling.figures` (the latter splats into
  touying's `alternatives(..)`).
- The internal style snapshot class `Frame` was renamed `Snapshot`;
  `blank-frame` → `blank-snapshot`. The public `Frame` name is now the
  output record (`canvas`, `caption`, `step`).
- Rotation animation reordered: init → pivots → break → restructure →
  connect → settle. The intermediate dashed-red break frame was dropped.

### Added

- `Frame` record class with `canvas`, `caption`, `step` fields. Each
  `*-display` method documents the `step.kind` values it emits.
- Render helpers: `last`, `stacked`, `figures`, `canvases-only`.
- `TreeRenderer.with-caption(c)` and `TreeRenderer.with-step(s)` for
  setting renderer-level frame metadata.
- `draw-tree(tree, snapshot, ...)` — cetz draw commands for one
  snapshot, *without* the surrounding `cetz.canvas`, so callers can
  compose with their own annotations.
- `path-anchor(path)` — translates an L/R path to the cetz anchor name
  of the corresponding node circle, for annotating specific nodes from
  user-provided cetz code.

### Removed

- `configure(wrap: ...)`. Callers wrap frame arrays with the new helpers
  (or any other strategy) themselves.
- `Op.Caption` variant. Use `r.with-caption(...)` between Op batches.
- `Snapshot.with-caption` (caption moved off the snapshot).
- `Snapshot.caption` field.
- `TreeRenderer.static(...)` (replaced by `starling.last(frames)`).

## [0.1.0] - 2025-01-01

Initial release.

[Unreleased]: https://github.com/mjschwenne/starling/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/mjschwenne/starling/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/mjschwenne/starling/releases/tag/v0.1.0
