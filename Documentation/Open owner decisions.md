# Open owner decisions

What is waiting on you, re-checked on 2026-10-26 against `main`, after your third batch of answers that day. Most questions were put to you between
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

None: every question put to you on 2026-10-26 is answered below.

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
| B-D2S-6 | Variable page sizes where they can be had; blank rows where they cannot, or cost too much; never a row cut off. | Queued. |
| S3-NO-EXTENT-SPACING | Yes: a child with no rows takes no gap. | Done: deliberate deviation L17. |
| FORMATTER | Skip both: an inferior API with a better replacement (`format:`), and on Linux a custom `Formatter` does not parse. | Done: refusals wave 17, O11. |
| D2S-SCROLLCLIP | As SwiftUI: overflow shows through the blank cells inside a later line too. | Queued, with an A/B of the geometry. |
| B-D2S-7 | As SwiftUI: `.paging` and `.viewAligned` honour `.contentMargins`, after a resize probe. | Queued. |
| TEXT2-INTERIOR | The default stays (opt-out allowed, not opt-in); try to cut its cost. | Queued. |
| OPACITY-28.2 | Not open: you answered it on 2026-09-10 (carry: a surface stepped off a faded page is as faded as the page), and it shipped then (`cff2e7190`, Opacity §39). Listed here by mistake. | Done. |
| OPACITY-92 | Try it. | Queued. |

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
