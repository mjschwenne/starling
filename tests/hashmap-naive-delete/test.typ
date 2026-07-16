// Naive open-addressing deletion (`tombstone: false`): the slot is
// blanked to empty instead of tombstoned. Then a search for a key whose
// probe sequence ran through that slot stops early and (wrongly) misses
// — the classic bug tombstones prevent. Chaining ignores the flag.
#import "/src/lib.typ" as starling
#import starling: hashmap

#set page(width: auto, height: auto, margin: 10pt)

// 14, 21, 7 all hash to slot 0 (k mod 7): 14 -> 0, 21 -> 1, 7 -> 2.
#let l = hashmap(7, strategy: "linear", entries: (14, 21, 7))

// Naive delete of 21 clears slot 1 to empty (no tombstone).
#starling.stacked((l.delete-display)(21, tombstone: false))

#v(1.5em)

// The bug: searching 7 now stops at the cleared slot 1 and misses,
// even though 7 is still in the table at slot 2.
#let broken = (l.delete)(21, tombstone: false)
#starling.stacked((broken.search-display)(7))
