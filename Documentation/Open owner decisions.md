# Open owner decisions

What is waiting on you, re-checked on the evening of 2026-10-26 against `main`, after a full audit of the record, the notes and the queue, and kept up as the night of 2026-10-27's work landed. Most questions were put to you between
2026-10-18 and 2026-10-26. The full write-ups of those asked by 2026-10-25, with the options and the
evidence, are in the historical record, [Owner decisions, 2026-10-18 to 2026-10-25](<Historical/SwiftUI parity process/The owner's decisions, 2026-10-18 to 2026-10-25.md>). That record also holds every
question you have already answered and what each answer set in motion. None of these blocks other work:
each has a default, which holds until you answer.

Answer by id and option ("B75: a"); a bare "yes" takes the recommendation.

## Owner actions

- **B-F2-4, once in Ghostty:** run `IDLE_PROBE_MODE=hang ~/Library/Caches/tuikit-probe/owner-keys/IdleProbe`
  (a release `IdleProbe`, staged there because Ghostty may not open files under `~/Documents`), press ⌃\\
  once, wait about two seconds, and press it again: the app should quit at the second press, the terminal
  restored. Under the kitty keyboard protocol ⌃\\ arrives as a key report, and only the stall watchdog
  makes a hung app quit.
- **Push `main`.** Local `main` is several hundred commits ahead of GitHub (last pushed 2026-10-24, `9f8439764`).
  It includes the rename to TUI (`c5cdfca27`): pushing it renames every module and product for anyone
  depending on `main`.
- **Rename the GitHub repository to `TUI`,** then say so. The commit that points every URL at the new
  name (branch `hold-repourls`) lands only after the rename, since GitHub redirects old names to new and
  never new to old.
- **Compiler bug reports** on the Desktop, one file per bug, are yours to file.

## Decisions waiting on you

### Lane questions of 2026-10-18 that were never answered

The lanes building on 2026-10-18 wrote these as they landed. They were listed at the end of the
record ([From the lanes building on 2026-10-18](<Historical/SwiftUI parity process/The owner's decisions, 2026-10-18 to 2026-10-25.md#from-the-lanes-building-on-2026-10-18>)),
never answered, and dropped from this page when the record moved to `Historical/` on 2026-10-25
(found by the audit of 2026-10-26). Each entry there links to the full write-up. Each default has
been in force since 2026-10-18.

| Id | Question | Recommended | If you don't answer |
|---|---|---|---|
| A-WIDTHS-1 | What does an unidentified host claim for a conjunct: one cluster's width, or a width per code point? | 1 for now (clustered), then measure xterm and VTE (and kitty) with `advance_probe.py` before choosing. | Clustered. |
| A-O10-1 | Linux has no save panel, since every `fileExporter` takes an Apple-only type. | 2: a TUI-only exporter form that takes `Data`, adding no second spelling of SwiftUI's. | Linux apps can open and move files but not ask where to save one. |
| A-FB16-1 | A container's own size changes at once, where SwiftUI's frame glides (the unbuilt half of your FB16 (a′)). | 1 now (record positions-only as a deviation); 2 if the Example's section borders read badly. | Sizes jump. |
| A-LAYOUT-1 | A column shares an overfull height only once a child's minimum is cheap to ask (the attempt cost +11 to +34%). | 2: make a child's minimum cheap to ask (a static witness), then land the sharing. | A column cuts its trailing children where SwiftUI squeezes them all. |
| A-APPSTATE-1 | `LocalizationService.shared` goes with draw-time lookup (now landed). | (b): the locale is the language, as SwiftUI's is, built on LOCALE-B. | The shared service stays. |
| A-APPSTATE-2 | Three more process-wide statics: the notification queue, the default store, the URL opener. | Exempt the default store and the URL opener (documented on the CLAUDE.md rule); make the notification queue per app later. | All three stay shared. |
| A-O12-1 | A hand pointer over every button, or over links only? | Links only: the Mac's convention, and what your Q2 answer named. About an hour. | Buttons and links (off everywhere until a host's reset is read). |
| A-CHURN-1 | Presume last frame's scrollbar (hysteresis), skipping the first measuring round? | As now: the round is exact, and with the early stop it costs a screenful. | As now. |
| A-CHURN-2 | Overlay scrollbars that take no column? | Decline: it would reverse R4 and R5, and is not needed for performance. | Bars keep a column. |
| A-O9-1 | `\.supportsMultipleWindows` is `true`. | `true`, as shipped. | `true`. |
| A-W1-1 | Should `import TUI` bring Foundation's geometry (and so `CGRect`) with it, as `import SwiftUI` does? | 2: re-export it. | A ported shape file needs `import Foundation`. |
| A-MODALS-1 | Keys declared outside a modal sheet still work behind it. | 3: make the page behind a modal inert to them, as the backdrop already says. | They keep working. |
| A-PARITYMISC-1 | Core Data's `FetchRequest` family: build it now, or when an app asks? | 2: when an app asks. | Not built. |
| A-TRANSITIONS2-1 | B52: a custom transition that changes its view's size — lay the body out at each frame's size? | 1: leave it; FB16 closes the gap B52 was opened for. | As now. |

### Asked in conversation on 2026-10-26

| Id | Question | Recommended | If you don't answer |
|---|---|---|---|
| DRAG-SELECTION | A `.draggable` row in a multi-selection drags only itself (List and Table), and `dropDestination` receives one item. Should dragging a selected row carry every selected row, as AppKit's tables do (probe SwiftUI first)? | Yes, after the probe. | Each row drags alone. |
| IMAGE-PAGE-PHOTO | The Example's image page shows the bald eagle, whose feather detail no block glyph can draw. Which photograph replaces it: the galago, the trillium or the snail? | The galago. | The eagle stays. |
| GLASS-BORDER-GAP | Under glass, the one-cell gap between a `.border()` and the material: inset the border and lay the glass under it, as the Materials clip now does by hand? | Yes, as a `.border()` inset with the material reaching under it. | The gap stays. |

## Answered on 2026-10-26

| Id | Answer | Status |
|---|---|---|
| B-D6M-2 | (a): swift-syntax is cloned by everyone, compiled only by macro users. | Nothing to change. |
| B-DYNVFIX-3 | (c), the dispatching identity; then (b), then (a), if each is too costly after optimisation. | (c) built (2026-10-27): a click, a key, a gesture or a `.task` inside a holder reads that holder's environment. Its A/B (2026-10-27, 35 scenarios warm and cold, the flagged ones re-run at 40 reps) found no measurable cost, so (c) stays. |
| PACKAGE-RESOLVED | Untrack it and ignore it. | Done in lane SMALL1026. |
| SDK15-CI | (c): the macOS 15 SDKs are not supported. | Done in lane SMALL1026: the guards and CONTRIBUTING. |
| B-D5C-1 | (1): the existential overload stays. | Nothing to change. |
| B63-CTRLJ | LF is Ctrl-J. | Done in lane SMALL1026: a vertical field's newline; Return where nothing takes it. |
| B63-KITTY | Ctrl-Return: an app's handler, then a context menu, then U+2028 in a vertical field or `TextEditor`; a plain CR stays Return. | Done (`f5ae4baff`). |
| B89 | Full gesture recognisers for every control, now. | Done (2026-10-27) for every control that acts on its click: it fails when released off it, draws pressed at once behind an undecided gesture, and a gesture attached after it hears the press once it fails. A control that acts on the press itself waits, as a recognizer would. |
| A48 | The recommendation: buttons revealed in the row, ⇧→ / ⇧← (again for the full swipe), Ctrl-L / Ctrl-T fallbacks. | Done (2026-10-26): keys, clicks and the horizontal wheel. **Needs you:** a real trackpad swipe recorded in Apple Terminal and iTerm2 (the burst gap is an estimate, 250 ms, and the replay test uses representative bytes). |
| A53-KEYBOARD-DRAG | The carry mode, after its prerequisite (`.draggable` as a focus stop with Copy and Paste). | Prerequisite done (2026-10-26). The carry is done (2026-10-27): Ctrl-R picks up; Tab and the arrows move among the stops that can take it, which are marked with a `‹`; Up and Down move between a list's rows; Return drops and Escape puts it back, both named in the status bar; Space flips copy and move. No idle expiry, because a slow hand would lose what it carried. Still owed: Pick Up in a context menu, which needs a way for a modifier to add a menu item. |
| B-BITEMS1-1 | The three-party model. | Done (2026-10-26): `dragConfiguration(_:)`, the destination's proposal, the modifier flip, the narrowing and the badge. The image well's badge (Generic, not Copy?) is still to be probed in a real window. |
| O13-KEYS | The recommendation: F10 enters bar mode; measure F10 and fn-F10. | Bar mode done (2026-10-26). **Needs you:** F10 and fn-F10 pressed in Apple Terminal, iTerm2 and Ghostty: `PROBE_KEYS=f10,fn_f10,shift_f1 python3 Tools/TerminalProbes/key_probe.py` in each (a key press cannot be sent from here), and whether the standard-function-keys setting is on. |
| B-HELP-2 | Shift-F1 at the lowest priority (any app or built-in handler takes it first); ⌥? toggles all help; a menu-bar item where Option does not arrive. | Done (`897751413`); what each terminal sends for Shift-F1 is still to be measured, in the same `key_probe.py` run as O13-KEYS. |
| B-PASTE-1-EDITOR | Undo as edits, not snapshots, with exhaustive tests that the stack cannot drift from the text; and undo for every built-in control that changes a value. | Undo as edits done (2026-10-26), checked against the snapshot history by a differential test. The controls' undo done the same night: toggles, pickers, sliders, steppers, date fields and calendar, colour grids, curve editors. |
| B75 | Draw a tab's custom label view in its chip (variable heights allowed); text labels keep their path and cost. | Done (2026-10-26): drawn whole in its chip, the row as tall as its tallest label. |
| B86 | Both now: the full entity table, stored compressed, and link reference definitions. | Done (`b3ab3f8b5`, `813a00cb3`). |
| A27 | (2). | Done: the transforms declined (`73aa70327`), `mask(alignment:_:)` (`bfedecf3d`), `drawingGroup` in linear light (`8fdc5b447`). |
| O9 | ⌃W stays delete-word in text fields; File ▸ Close and Close All (⌘W, ⌥⌘W) only where the focus is outside a text field and nothing else takes the key. | Done (`301c60b47`, `e57e3cb0c`). |
| INERT-APIS (wave 17) | No stubs: an API that does nothing on macOS either is implemented for real, doing what its user would expect, or not at all. | Recorded. |
| B82 | Not open: answered 2026-10-23, built 2026-10-24. | Done. |
| B-D2S-6 | Variable page sizes where they can be had; blank rows where they cannot, or cost too much; never a row cut off. | Done (2026-10-27): variable pages under `.paging` (the pair comes and goes; every line read once), blanks where a page cannot vary (container-sized pages, `.viewAligned`). Never a row cut (2026-10-27): over a `scrollTargetLayout`'s rows, `.paging` draws the row a page would cut blank and starts the next page with it. |
| S3-NO-EXTENT-SPACING | Yes: a child with no rows takes no gap. | Done: deliberate deviation L17. |
| FORMATTER | Skip both: an inferior API with a better replacement (`format:`), and on Linux a custom `Formatter` does not parse. | Done: refusals wave 17, O11. |
| D2S-SCROLLCLIP | As SwiftUI: overflow shows through the blank cells inside a later line too. | Built (2026-10-27): a later view hides the overflow only under its runs of painted cells. Its A/B (2026-10-27) found no measurable cost. |
| B-D2S-7 | As SwiftUI: `.paging` and `.viewAligned` honour `.contentMargins`, after a resize probe. | Not open: built on 2026-10-19 after the probe (lane SCROLL), and listed here by mistake. One measured SwiftUI quirk is not copied: its `.paging` page is half the top margin longer (deviation R15). |
| TEXT2-INTERIOR | The default stays (opt-out allowed, not opt-in); try to cut its cost. | Queued. |
| OPACITY-28.2 | Not open: you answered it on 2026-09-10 (carry: a surface stepped off a faded page is as faded as the page), and it shipped then (`cff2e7190`, Opacity §39). Listed here by mistake. | Done. |
| OPACITY-92 | Try it. | Done (`1ad2199fe`): a hidden view asks for no frames unless it presents a sheet. |

## Answered on 2026-10-27

| Id | Answer | Status |
|---|---|---|
| A-EFFECTS-1 | 3: never invisible; dim and the other attributes widen the palette. | Done: faint in the ink's colour at 16 colours, a step toward it at 256. |

## Answered on 2026-10-27

| Id | Answer | Status |
|---|---|---|
| A-FORMS-1 | 2: follow SwiftUI. | Done: a bare button in the control column (columns), at the row's leading edge (grouped). |

## Answered later on 2026-10-26

| Id | Answer | Status |
|---|---|---|
| INACTIVE-GLASS | Glass stays frosted in an inactive window; it may dim or turn a little more opaque. | Done (`85791b8ae`). |
| UNDER-TEXT-PICTURES | Lay a picture under the text where the terminal can (Ghostty), adapted per terminal, conservative by default. | Done (`4ba32c983`, `72d9df103`). |
| GAUGE-TINT | (b): a linear gauge or progress bar fills with the tint only where one is stated; gradients along every gauge, around a ring's arc. | Done (`6813bad99`). |
| FROST-RESOLUTION | An integer downsampling factor of the terminal's own pixels. | Done (`4bb6762a3`). |
| CLIP-ASPECT | Size symmetry: one shape for the clips. | Done: every clip at 16:10 (`cfe0a713a`…`2b437e6f7`); the re-film waits on a quiet machine. |

## New on 2026-10-25

- **The README's hero clip.** You haven't chosen. Candidates filmed or sketched: the system monitor,
  now playing, the weather; the 10-24 pick was the slider driving a gauge.
- **The Animation clip** is settled (2026-10-26): it keeps ordinary view animation, and the photo zoom
  went into the Navigation clip.
- **Environment variables** (answered 2026-10-27: rename): every `TUIKIT_` variable is `TUI_` now.
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
