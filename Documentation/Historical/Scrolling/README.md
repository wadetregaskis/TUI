# Scrolling: how it came to be

One story per subject: the problem, what was measured and considered, what the owner and the
lanes decided and when, where it stands, and what a future reader should watch for, with the
record of each decision below it in the words of the day. The current design is in
[Layout and scrolling](<../../Layout and scrolling/>), chiefly
[Scroll anchoring.md](<../../Layout and scrolling/Scroll anchoring.md>); deliberate departures
from SwiftUI are in [Deliberate deviations from SwiftUI.md](<../../SwiftUI parity/Deliberate deviations from SwiftUI.md>).

| Story | What it covers |
|---|---|
| [Holding the reader's place as rows change above](<Holding the reader's place as rows change above.md>) | The top row held through insertions, removals and resizes above it; `.scrollWindowHold`; the `Transaction` scroll members (B30, SCROLLANCHOR). |
| [Paging and view-aligned scrolling](<Paging and view-aligned scrolling.md>) | Scroll target behaviours on every scrollable, the "N more" lines under them, content margins, the alignment anchor role (A6, A8, D2S, SCROLL). **Owed:** B-D2S-6 as ruled on 2026-10-26. |
| [Content past a scroll view's edge](<Content past a scroll view's edge.md>) | `scrollClipDisabled`, what a later view hides, and clicks (A10, D2S). **Owed:** D2S-SCROLLCLIP. |
| [Scroll phases, animated scrolling, flash and bounce](<Scroll phases, animated scrolling, flash and bounce.md>) | `ScrollPhase`, gliding programmatic scrolls, `scrollIndicatorsFlash`, the `.always` bounce (B27, B28, B31, SCROLLB), with the animated-scrolling design as an appendix. |
| [Scroll position, visibility and nested scrollables](<Scroll position, visibility and nested scrollables.md>) | `onScrollTargetVisibilityChange`, a bound position when scrollables nest, `scrollTo` across axes (SCROLL). |
| [Measuring a scroll view's content: the overflow check, wide rows and nested lazy stacks](<Measuring a scroll view's content: the overflow check, wide rows and nested lazy stacks.md>) | The scrollbar's early-stopping overflow check, rows that widen off screen, lazy stacks inside padding or below other content (CHURN, SCROLL, Q1). **Open:** A-CHURN-1 and 2. **Owed:** design C. |
