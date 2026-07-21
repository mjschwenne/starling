// LSD radix sort (base 10): one stable prefix counting-sort pass per digit
// place. Each input cell shows its extracted digit as a subscript for the
// active pass. Kept small (two 2-digit passes) so the reference stays legible.
#import "/src/lib.typ" as starling
#import starling: sort

#set page(width: auto, height: auto, margin: 10pt)

#starling.stacked((sort(23, 4, 8, 17).radix-sort-display)())
