// Visual regression for the trie `insert-display`. Three inserts:
//   - a word extending an existing prefix (one new suffix node)
//   - a brand-new branch (a whole chain of new nodes grows)
//   - a word that is an existing prefix (only the terminal bit flips)

#import "/src/lib.typ" as starling
#import starling: Trie, trie

#set page(width: auto, height: auto, margin: 1em)

#let t = trie("cat", "car", "card", "dog")

== Extend an existing prefix — insert "care"
#starling.stacked((t.insert-display)("care"))

#pagebreak()

== Brand-new branch — insert "bat"
#starling.stacked((t.insert-display)("bat"))

#pagebreak()

== Existing prefix becomes a word — insert "ca"
#starling.stacked((t.insert-display)("ca"))
