#import "/src/lib.typ": BST

#let t = (BST.new)(value: 4, left: none, right: none)
#let t = (t.insert)(1)
#let t = (t.insert)(0)
#let t = (t.insert)(7)
#let t = (t.insert)(3)
#let t = (t.insert)(6)
#let t = (t.insert)(8)

#(t.delete-display)(0)
