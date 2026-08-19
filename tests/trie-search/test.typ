// Visual regression for the trie `search-display`. Three searches:
//   - a stored word (ends on a terminal node)
//   - a prefix that is not itself a stored word
//   - a miss (a character with no matching edge)

#import "/src/lib.typ" as starling
#import starling: trie

#set page(width: auto, height: auto, margin: 1em)

#let t = trie.new("cat", "car", "card", "dog")

== Hit — stored word "card"
#starling.stacked(trie.search-display(t, "card"))

#pagebreak()

== Prefix only — "ca" is not a stored word
#starling.stacked(trie.search-display(t, "ca"))

#pagebreak()

== Miss — no 'b' edge out of "ca"
#starling.stacked(trie.search-display(t, "cab"))
