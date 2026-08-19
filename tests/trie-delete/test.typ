// Visual regression for the trie `delete-display`. Three deletes:
//   - unmark-only: the node has children (a prefix of another word)
//   - partial prune: one leaf is pruned, stopping at a branch point
//   - full-chain prune: a whole dead branch is pruned to the root
// Plus `search: false`, which starts at the unmark.

#import "/src/lib.typ" as starling
#import starling: trie

#set page(width: auto, height: auto, margin: 1em)

#let t = trie.new("cat", "car", "card", "dog")

== Unmark only — delete "car" ("card" keeps the branch alive)
#starling.stacked(trie.delete-display(t, "car"))

#pagebreak()

== Partial prune — delete "card" (stops at "car")
#starling.stacked(trie.delete-display(t, "card"))

#pagebreak()

== Full-chain prune — delete "dog"
#starling.stacked(trie.delete-display(t, "dog"))

#pagebreak()

== `search: false` — straight to the unmark
#starling.stacked(trie.delete-display(t, "dog", search: false))
