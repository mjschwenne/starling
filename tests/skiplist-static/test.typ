// Static skip list: a sparse grid of node towers with horizontal forward
// pointers, a header sentinel (left) and a NIL tail (right). Explicit
// tower heights keep the reference deterministic.
#import "/src/lib.typ" as starling
#import starling: skiplist

#set page(width: auto, height: auto, margin: 10pt)

#starling.last((skiplist(
  (value: 2, height: 1),
  (value: 5, height: 3),
  (value: 8, height: 1),
  (value: 12, height: 2),
  (value: 17, height: 1),
  (value: 20, height: 2),
).display)())
