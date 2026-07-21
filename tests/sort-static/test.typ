// Static single-row array display (no operation styling).
#import "/src/lib.typ" as starling
#import starling: sort

#set page(width: auto, height: auto, margin: 10pt)

#starling.last((sort(3, 1, 4, 1, 5, 9, 2, 6).display)())
