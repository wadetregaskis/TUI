# Completing the SwiftUI API: lane GUIDE's new judgement calls

*The lane that fixed two alignment-guide parity bugs measured on 2026-10-11:
a guide outside its own view was clamped to that view's size, and a trailing or
centred run that a child overhung was shifted so its guides no longer met.
Where the work met a judgement call the brief did not settle, the safe option
shipped and is written up here, in the three parts the other lanes use: A needs
a decision, B shipped the safe option (with the fuller version and its price),
C declined with a parity-map reason. SwiftUI's behaviour was measured with
SwiftUI 6.5.4 on macOS 15.8.1 with offscreen `NSHostingView`s (probes in the
session notes, `GUIDE/probe/` and `GUIDE/probe2/`).*

## B. Shipped the safe option

### B-GUIDE-1. A region smaller than the run keeps the run's leading edge on its own

*`AlignmentGuideRun.resolve`: a `.frame` or `.overlay` narrower than its
content, a column a flexible child fills, a lazy column's window*

SwiftUI's rule, measured, is that each view sits at `max(guides) - its guide`
and the stack is as big as that needs. TUIkit now places a run so, and when the
region is bigger than the run, moves the run as a whole toward the region's own
guide only as far as all of it still fits: `anchor = min(max(M, regionGuide(E)),
M + room)`, where `room = max(0, E - contentExtent)`.

The brief wrote the room without the `max(0, …)`. That differs only for a
region SMALLER than the run, where it would move the run back so its far edge
met the region's — a leading-aligned column then lost the alignment of every
row whose base is less than the overhang, where today it loses only the rows
that overhang. With the `max`, a run in a region too small for it keeps its
leading edge on the region's, as a `.leading` run always did, and the per-child
clamp pulls back only the views that would fall outside, as before.

**The fuller version** is SwiftUI's: the stack reports the size the run needs,
past its proposal, and the parent places and clips it. Measured: in a 400-point
host, `VStack(alignment: .trailing)` holding a 3-wide view with trailing guide
0, a 6-wide view and a view with `maxWidth: .infinity` is 403 wide, the
flexible view at 0 and the 3-wide one at 400. **Price:** every TUIkit container
holds its report to its proposal ("never advertise a size larger than the
constraint", `_VStackCore.sizeThatFits`), and the parent's buffer is the size
it reported, so this is a change to every container's contract, not to the
guide run.
