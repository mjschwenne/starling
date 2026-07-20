// Visual regression for the trie `delete-display`. Three deletes:
//   - unmark-only: the node has children (a prefix of another word)
//   - partial prune: one leaf is pruned, stopping at a branch point
//   - full-chain prune: a whole dead branch is pruned to the root

#import "/src/lib.typ" as starling
#import starling: Trie, trie

#set page(width: auto, height: auto, margin: 1em)

#let t = trie("cat", "car", "card", "dog")

== Unmark only — delete "car" ("card" keeps the branch alive)
#starling.stacked((t.delete-display)("car"))

#pagebreak()

== Partial prune — delete "card" (stops at "car")
#starling.stacked((t.delete-display)("card"))

#pagebreak()

== Full-chain prune — delete "dog"
#starling.stacked((t.delete-display)("dog"))
