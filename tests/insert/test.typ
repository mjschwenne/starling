#import "/src/lib.typ" as starling
#import starling: BST

#let t = (BST.new)(value: 4, label: auto, left: none, right: none)
#let t = (t.insert)(1)
#let t = (t.insert)(0)
#let t = (t.insert)(7)
#let t = (t.insert)(3)
#let t = (t.insert)(6)
#let t = (t.insert)(8)

#starling.stacked((t.insert-display)(5))
