# Open owner decisions

What is waiting on you, re-checked on 2026-10-26 against `main`. Most questions were put to you between
2026-10-18 and 2026-10-26. The full write-ups of those asked by 2026-10-25, with the options and the
evidence, are in the historical record, [Owner decisions, 2026-10-18 to 2026-10-25](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md>). That record also holds every
question you have already answered and what each answer set in motion. None of these blocks other work:
each has a default, which holds until you answer.

Answer by id and option ("B75: a"); a bare "yes" takes the recommendation.

## Owner actions

- **Push `main`.** Local `main` is several hundred commits ahead of GitHub (last pushed 2026-10-24, `9f8439764`).
  It includes the rename to TUI (`c5cdfca27`): pushing it renames every module and product for anyone
  depending on `main`.
- **Rename the GitHub repository to `TUI`,** then say so. The commit that points every URL at the new
  name (branch `hold-repourls`) lands only after the rename, since GitHub redirects old names to new and
  never new to old.
- **Compiler bug reports** on the Desktop, one file per bug, are yours to file.

## Decisions waiting on you

Asked again on 2026-10-26, after your answers that day: each needs one more word from you.

| Id | Question | Recommended | If you don't answer |
|---|---|---|---|
| [B-D2S-6](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md#b-d2s-6>) | A scroll target behaviour with `.text` indicators: pages TUI sizes follow your rule (no repeats or skips, a "N more" line only where needed or under `.visible`, no blank rows), and only content whose pages are sized to the container (`containerRelativeFrame`, which TUI can tell) keeps both lines reserved, since a page of a fixed height cannot land whole otherwise. Agreed? | Yes. | Both lines stay reserved under any behaviour, as shipped. |
| [S3-NO-EXTENT-SPACING](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md#s3-no-extent-spacing>) | Keep TUI's rule (a child with no rows takes no gap, so "A B" becomes "A C B" and never "A, two gaps, B"; `EmptyView` and an empty stack agree) and record it as a deliberate deviation from SwiftUI? | Yes: your reading of 2026-10-26, which removes the audit too. | TUI's rule stays, recorded as an open divergence. |
| FORMATTER (Refusals re-examined, wave 17, O11) | Ship `Text(_:formatter:)` and `TextField(value:formatter:)` beside the `format:` forms (the interpolation already ships), without the deprecated `onEditingChanged:`/`onCommit:` variants? On Linux a custom `Formatter` subclass displays but does not parse; the common ones parse. | Yes, about a day and a half. | Both stay refused. |
| D2S-SCROLLCLIP ([D2S](<SwiftUI parity/Decisions/Scrolling/Scroll anchors, target behaviours and clipping (D2S).md>)) | Under `scrollClipDisabled`, should a scroll view's overflow also show through the blank cells inside a later view's line (between its words), as SwiftUI's shows between glyphs, not only around them? | No: two texts interleaved cell by cell are hardly legible. | Overflow shows only around a line's drawn cells. |
| B-D2S-7 ([D2S](<SwiftUI parity/Decisions/Scrolling/Scroll anchors, target behaviours and clipping (D2S).md>)) | Should `.paging` and `.viewAligned` honour `.contentMargins` as SwiftUI documents (pages land inside the margins; a carousel aligns at its leading margin with neighbours showing)? | Yes, with a resize probe first: half a day. | Behaviours page and align by the whole window, margins included. |
| TEXT2-INTERIOR ([TEXT2](<SwiftUI parity/Decisions/Input, clipboard and text editing/Ctrl-U, selection kept to a container, undoable reorders (TEXT2).md>)) | A drag selection begun in a bordered box keeps to its interior by default, at `modifiers` +6.4% and `dashboard` +3.7% warm. Make that opt-in instead, which removes the cost? | Keep the default: it fixed the Contact card, and the cost is under your ~10% line. | The default stays. |
| OPACITY-28.2 ([Opacity §28.2](<Colour and styling/Opacity as composition.md>)) | A field well or lifted surface stepped off a half-transparent page: as transparent as the page (one wash), or solid (a field to read in)? Nothing reaches it today. | Solid: a field is where text is read. | They drop the page's alpha, as today. |
| OPACITY-92 ([Opacity §92](<Colour and styling/Opacity as composition.md>)) | Carry a view's request for frames on the buffer it drew, so a `.hidden()` view's animation stops costing renders (a sheet presented from inside it keeps animating)? Nine places that build a run from parts must carry the flag. | Yes. | A hidden view that animates keeps asking for frames. |

## Answered on 2026-10-26

| Id | Answer | Status |
|---|---|---|
| B-D6M-2 | (a): swift-syntax is cloned by everyone, compiled only by macro users. | Nothing to change. |
| B-DYNVFIX-3 | (c), the dispatching identity; then (b), then (a), if each is too costly after optimisation. | Queued. |
| PACKAGE-RESOLVED | Untrack it and ignore it. | Done in lane SMALL1026. |
| SDK15-CI | (c): the macOS 15 SDKs are not supported. | Done in lane SMALL1026: the guards and CONTRIBUTING. |
| B-D5C-1 | (1): the existential overload stays. | Nothing to change. |
| B63-CTRLJ | LF is Ctrl-J. | Done in lane SMALL1026: a vertical field's newline; Return where nothing takes it. |
| B63-KITTY | Ctrl-Return: an app's handler, then a context menu, then U+2028 in a vertical field or `TextEditor`; a plain CR stays Return. | Queued, with a probe of a single-line field. |
| B89 | Full gesture recognisers for every control, now. | Queued. |
| A48 | The recommendation: buttons revealed in the row, ⇧→ / ⇧← (again for the full swipe), Ctrl-L / Ctrl-T fallbacks. | Queued. |
| A53-KEYBOARD-DRAG | The carry mode, after its prerequisite (`.draggable` as a focus stop with Copy and Paste). | Queued. |
| B-BITEMS1-1 | The three-party model. | Queued. |
| O13-KEYS | The recommendation: F10 enters bar mode; measure F10 and fn-F10. | Queued. |
| B-HELP-2 | Shift-F1 at the lowest priority (any app or built-in handler takes it first); ⌥? toggles all help; a menu-bar item where Option does not arrive. | Queued. |
| B-PASTE-1-EDITOR | Undo as edits, not snapshots, with exhaustive tests that the stack cannot drift from the text; and undo for every built-in control that changes a value. | Queued. |
| B75 | Draw a tab's custom label view in its chip (variable heights allowed); text labels keep their path and cost. | Queued. |
| B86 | Both now: the full entity table, stored compressed, and link reference definitions. | Queued. |
| A27 | (2). | Queued. |
| O9 | ⌃W stays delete-word in text fields; File ▸ Close and Close All (⌘W, ⌥⌘W) only where the focus is outside a text field and nothing else takes the key. | Queued. |
| INERT-APIS (wave 17) | No stubs: an API that does nothing on macOS either is implemented for real, doing what its user would expect, or not at all. | Recorded. |
| B82 | Not open: answered 2026-10-23, built 2026-10-24. | Done. |

## New on 2026-10-25

- **The README's hero clip.** You haven't chosen. Candidates filmed or sketched: the system monitor,
  now playing, the weather; the 10-24 pick was the slider driving a gauge.
- **The Animation clip.** Five ideas to choose from: a photo wall opening into a full-size picture with
  the zoom transition (recommended); a now-playing card with cross-fades, rolling digits and a spectrum;
  a system monitor with streaming sparklines, springing gauges and re-sorting rows; a weather strip with
  scroll transitions and a moving sun; a keyframed launch sequence with phase-animated buttons.
- **Environment variables.** The rename kept the `TUIKIT_…` variables as they are, since a bare `TUI_`
  prefix could collide with other tools. Say if you want them renamed too.
- **The page behind a sheet** is now veiled rather than flattened (your ruling of 2026-10-25), with a
  cost of +6.4% on a frame with a sheet open in the notes session, and a gain of 11.8% in another. Look
  at it when you can.

## Deferred, by your choice

- **DORMANT-DESIGNS**: after the SwiftUI API compatibility work.
- **MACOS27-PARITY**: when a macOS 27 machine is available.
- **OOB-STYLING**: explore along (a) later; a reminder when the queue runs out.
- **A-D6L-1**: a reminder at the end of the queue.
- **BINARY-DISTRIBUTION**: two compiler bug reports are on the Desktop; the rest waits on them.
- **Right-to-left text**: wanted, after the SwiftUI API compatibility work (2026-10-12).
