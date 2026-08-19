// Visual regression for the trie static `display`. Shows the 0/1
// terminal bits, shaded word-end nodes, and letters on the edges —
// including an interior node that is *also* terminal ("do" is a stored
// word with a child leading to "dog"). The second panel exercises a
// `set-theme` palette override.

#import "/src/lib.typ" as starling
#import starling: set-theme, trie

#set page(width: auto, height: auto, margin: 1em)

#let t = trie.new("cat", "car", "card", "dog", "do")

== Default palette
#starling.last(trie.display(t))

#pagebreak()

== Recoloured terminals via set-theme
#set-theme((trie: (terminal-fill: rgb("#6b46c1"), terminal-stroke: black)))
#starling.last(trie.display(t))
