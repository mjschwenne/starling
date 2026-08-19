// Visual regression for the trie `insert-display`. Three inserts:
//   - a word extending an existing prefix (one new suffix node)
//   - a brand-new branch (a whole chain of new nodes grows)
//   - a word that is an existing prefix (only the terminal bit flips)

#import "/src/lib.typ" as starling
#import starling: trie

#set page(width: auto, height: auto, margin: 1em)

#let t = trie.new("cat", "car", "card", "dog")

== Extend an existing prefix — insert "care"
#starling.stacked(trie.insert-display(t, "care"))

#pagebreak()

== Brand-new branch — insert "bat"
#starling.stacked(trie.insert-display(t, "bat"))

#pagebreak()

== Existing prefix becomes a word — insert "ca"
#starling.stacked(trie.insert-display(t, "ca"))
