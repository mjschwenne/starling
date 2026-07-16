// Cells / chain entries grow to fit labels wider than the historical
// fixed footprint (the default "fit" sizing on the display methods), so a
// key/value label like "(k1, v1)" isn't clipped. Covers open addressing
// and chaining, both orientations, plus an explicit `cell-width` pin and
// the `auto` (fixed, no-measure) opt-out.
#import "/src/lib.typ" as starling
#import starling: hashmap

#set page(width: auto, height: auto, margin: 10pt)

// Open addressing: wide key/value labels, horizontal.
#let l = hashmap(5, strategy: "linear")
#let l = (l.insert)(3, value: "v1", label: "(k1, v1)")
#let l = (l.insert)(8, value: "v2", label: "(k2, v2)")
#starling.last((l.display)())

#v(1.5em)

// Same table, vertical (memory-diagram) orientation.
#starling.last((l.display)(orientation: "vertical"))

#v(1.5em)

// Chaining: wide entry labels widen the entry boxes and the array pitch.
#let c = hashmap(3, strategy: "chaining")
#let c = (c.insert)(1, label: "(k1, v1)")
#let c = (c.insert)(4, label: "(k2, v2)")
#starling.last((c.display)())

#v(1.5em)

// Explicit `cell-width` pin (fixed 2.2 units, no measuring).
#starling.last((l.display)(cell-width: 2.2))

#v(1.5em)

// `cell-width: auto` keeps the historical fixed footprint (clips wide
// labels on purpose — the opt-out).
#starling.last((l.display)(cell-width: auto))
