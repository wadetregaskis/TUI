# Open owner decisions

What is waiting on you, re-checked on the morning of 2026-10-28 against `main`. Most questions were put to you between
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
- **Xcode 27**, if it can be installed again: the SwiftUI comparison was last re-baselined on the 6.3.3
  SDK and now runs against Xcode 26.3's, and MACOS27-PARITY waits on it.

## Decisions waiting on you

### Open on 2026-10-28

| Id | Question | Recommended | If you don't answer |
|---|---|---|---|
| A-APPSTATE-1 (root) | The locale is the language (your (b)); words drawn in views follow a subtree's `\.locale`. About 130 places read words where no view draws (the status bar's and menu bar's labels, undo titles, clipboard notes), at the app's root: where does the app's own language live? | The root `\.locale` of the app's scene (`WindowGroup { … }.environment(\.locale, …)`, SwiftUI's idiom for an in-app language), which TUI's chrome reads too. | They keep reading the process's language. |
| NEW-FOLDER | The file panels have no way to make a folder; a Mac's save panel has New Folder (`NSSavePanel.canCreateDirectories`, on by default), its open panel not by default. | A New Folder button, with a keyboard route, in the save and move panels (`fileExporter`, `fileMover`). About half a day. | None. |
| SMALL-IMAGE-ON-FRAME | Landed: an image file up to 256 KB is decoded on the frame that first shows it (a few ms), so icons no longer flash in after a placeholder; larger files still load in a task. Keep, or keep every load off the frame? | Keep. | Kept. |
| PICTURE-ASPECT | A resized picture: always drawn the same (more bytes while resizing), reuse while moving and exact once settled, sent at its own aspect, or reuse as now? You asked to see them. | Pending: each filmed in Ghostty, kitty and iTerm2, with bytes. | Reuse as now. |
| SCROLLBAR-PLACEMENT | Try `.overContent` before the final say: the Example's Theme page now switches it (Scroll indicators). Hover a list, then click it: the bar moves from over the rows to beside them. | — | Both stay, beside the content by default. |

## Answered on 2026-10-29

| Id | Answer | Status |
|---|---|---|
| A-CHURN-2 (focus) | Under `.overContent`, over the content for the pointer; while the view has the focus, beside the content as `.besideContent` draws them, the content laid out again; losing the focus restores its room. | Done for `ScrollView`, `List`, `Table` and `TextEditor`: the placement is resolved per view per frame, before layout. |

## Answered on 2026-10-28

| Id | Answer | Status |
|---|---|---|
| VEIL | 25% of each colour kept, 60% of its colour taken out ("25d60"). | Done (g263): pictures behind a sheet are muted the same way. |
| PREVIEW-IMAGES | Glue: a module on the file panels and the image decoders. | Done (TUIFilePanelImages, `.fileDialogPicturePreviews()`). |
| TEXT-EFFECTS | SwiftUI's `TextRenderer`, `Text.Layout` and `customAttribute`, on the part of `GraphicsContext` text needs, plus a TUI glyph swap. | Design first. |

## Answered on 2026-10-27

| Id | Answer | Status |
|---|---|---|
| A-EFFECTS-1 | 3: never invisible; dim and the other attributes widen the palette. | Done: faint in the ink's colour at 16 colours, a step toward it at 256. |
| A-O12-1 | Configurable, app-wide (a Mac's links-only or a web page's every clickable control). | Done: `pointingHandCursor(over:)`, `.links` (the default) or `.everythingClickable`. |
| A-MODALS-1 | 3, if macOS agrees: it does (measured). | Done: behind a modal only its own shortcuts and status bar items show and fire. |
| A-O10-1 | 2, generic beyond `Data` (strings, `Codable`). | Done: `fileExporter(isPresented:contents:…)` and `fileExporter(isPresented:encoding:…)`, on every platform. |
| A-FORMS-1 | 2: follow SwiftUI. | Done: a bare button in the control column (columns), at the row's leading edge (grouped). |
| ENV-VARS | Rename `TUIKIT_` to `TUI_`. | Done (`af22656f9`). |
| DRAG-SELECTION | The Mac's way: the whole selection; Shift-drag extends it first. | Done for the mouse and the keyboard's Copy and carry, List and Table. |
| A-LAYOUT-1 | Optimise it, then decide. | Done: a column's minimum height is answered without measuring, and columns share (`stateful` +1.5%, `tables-vstack` +7.5% for drawing all eight tables). |
| A-WIDTHS-1 | Assume a perfect terminal by default; optional features never assumed. | Done. |
| A-FB16-1 | Option 3: every frame glides with relayout. | Queued, after the transitions below. |
| A-APPSTATE-1 | (b): the locale is the language. | Built in four slices (keys, buttons, alerts, dialogs); the root's language is open above. |
| A-CHURN-1 | Keep the exact first round. | Nothing to change. |
| A-O9-1 | `true`. | As shipped. |
| A-PARITYMISC-1 | 2: build Core Data's `FetchRequest` when an app asks. | Not built. |
| A-TRANSITIONS2-1 | All: transitions everywhere a stack's do. | Grid and `Layout` done; lazy stacks and `List`/`Table` rows queued. |
| IMAGE-PAGE-PHOTO | None of the three: a cartoony picture. | Done: the platform's mascot, cycled with `p`. |
| A-APPSTATE-2 | Multi-client in one process: tabled. The three statics: no practical benefit in moving them. | Done: all three stay shared, recorded as exemptions on the CLAUDE.md rule. |
| A-W1-1 | 2: re-export Foundation from TUI, as SwiftUI does. | Done: `import TUI` brings Foundation. |
| GLASS-BORDER-GAP | (a): a background on the bordered view fills the border's inset; an explicit option keeps it clear. | Done: `.backgroundStopsAtContent()` is the option. |
| A-CHURN-2 / SCROLLBAR-NAMES | Both: `.scrollIndicatorPlacement(.besideContent / .overContent)`; over the content for the pointer; the "N more" lines follow it. (The focus: see 2026-10-29, which corrected "never the focus".) | Built for `ScrollView`, `List`, `Table` and `TextEditor` (and the menus). The owner wants to try it before the final say. |

## Answered later on 2026-10-26

| Id | Answer | Status |
|---|---|---|
| INACTIVE-GLASS | Glass stays frosted in an inactive window; it may dim or turn a little more opaque. | Done (`85791b8ae`). |
| UNDER-TEXT-PICTURES | Lay a picture under the text where the terminal can (Ghostty), adapted per terminal, conservative by default. | Done (`4ba32c983`, `72d9df103`). |
| GAUGE-TINT | (b): a linear gauge or progress bar fills with the tint only where one is stated; gradients along every gauge, around a ring's arc. | Done (`6813bad99`). |
| FROST-RESOLUTION | An integer downsampling factor of the terminal's own pixels. | Done (`4bb6762a3`). |
| CLIP-ASPECT | Size symmetry: one shape for the clips. | Done: every clip at 16:10 (`cfe0a713a`…`2b437e6f7`); the re-film waits on a quiet machine. |

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

## New on 2026-10-25

- **The README's hero clip.** You haven't chosen. Candidates filmed or sketched: the system monitor,
  now playing, the weather; the 10-24 pick was the slider driving a gauge.
- **The Animation clip** is settled (2026-10-26): it keeps ordinary view animation, and the photo zoom
  went into the Navigation clip.
- **Environment variables** (answered 2026-10-27: rename): every `TUIKIT_` variable is `TUI_` now.
- **The page behind a sheet** is now veiled rather than flattened (your ruling of 2026-10-25), with a
  cost of +6.4% on a frame with a sheet open in the notes session, and a gain of 11.8% in another. Its
  strength is now 25% kept with 60% of the colour out (your pick of 2026-10-28, "25d60").

## Deferred, by your choice

- **DORMANT-DESIGNS**: after the SwiftUI API compatibility work.
- **MACOS27-PARITY**: when a macOS 27 machine is available.
- **OOB-STYLING**: explore along (a) later; a reminder when the queue runs out.
- **A-D6L-1**: a reminder at the end of the queue.
- **BINARY-DISTRIBUTION**: two compiler bug reports are on the Desktop; the rest waits on them.
- **Right-to-left text**: wanted, after the SwiftUI API compatibility work (2026-10-12).
