// Visual regression for the trie static `display`. Shows the 0/1
// terminal bits, shaded word-end nodes, and letters on the edges —
// including an interior node that is *also* terminal ("do" is a stored
// word with a child leading to "dog"). Second panel exercises a
// `set-trie-theme` palette override.

#import "/src/lib.typ" as starling
#import starling: Trie, trie, set-trie-theme

#set page(width: auto, height: auto, margin: 1em)

#let t = trie("cat", "car", "card", "dog", "do")

== Default palette
#starling.last((t.display)())

#pagebreak()

== Recoloured terminals via set-trie-theme
#set-trie-theme((terminal-fill: rgb("#6b46c1"), terminal-stroke: black))
#starling.last((t.display)())
