# The owner's decisions, 2026-10-27 to 2026-11-07

*The owner's rulings from 2026-10-27 to 2026-11-07, each with the reason he
gave where one was recorded, and where it went. It completes, rather than
repeats, two other records: [Open owner decisions](<../../Open owner decisions.md>)
lists every question asked on a page and its status, and the
[SwiftTUI comparison](<../SwiftTUI comparison, 2026-11/README.md>) tabulates
the rulings of 2026-11-01. Rulings with a story of their own are linked, not
retold.*

## In short

The owner answered a questions page most days (2026-10-27 twice, 10-28 twice,
10-29, 10-31, 11-01, 11-02), and two decisions on 2026-11-07 came out of a
review. The answers had been kept in the ledger, terse and without reasons,
and the rest only in an agent's memory files. This collects every ruling the
committed docs did not already state, and every reason the owner gave, so
that nobody has to ask again or guess why. Where no reason was recorded, it
says so.

## How it unfolded

Each page asked by id, with options, a recommendation and what would happen
unanswered; the owner answered by id, often adding a direction of his own.
Rulings that changed shipped behaviour were built in lanes the same or the
next day. From 2026-11-02 the owner asked for one lane at a time, then gate
and land it, then the next, after six had run at once.

## Where it stands

Open, and listed in the ledger's "Decisions waiting on you": SCROLL-REGIONS
(the owner will try it first), SCROLLBAR-PLACEMENT (try `.overContent`
first), HR-ALL (the owner will review the hot reload design), PARTIAL-TUI
(planned for after 1.0; the owner will review the design). Queued, not built:
A-FB16-1 (every frame glides), kitty OSC 72 drag and drop, SHEET-KEYBOARD.

## For a future reader

- **"No reason recorded" means none was written down,** not that there was
  none. Several rulings simply took the recommendation as offered; the
  page's reasoning is then the nearest thing to a reason, and is quoted
  where it matters.
- **Standing rules behind many of these:** don't copy SwiftUI's limitations
  (change only where a SwiftUI program would misbehave); assume a perfect
  terminal by default; no mouse-only interactions; no memory-for-speed trades.

## The record

### 2026-10-27, round 2 (evening)

The first page of the day is in the ledger with its statuses. Round 2's
answers the ledger does not hold:

| Id | Decision | Why, as recorded | Where it went |
|---|---|---|---|
| MARKDOWN-SCOPE | Block Markdown is not TUI's: a separate package built on TUI, out of scope. Everything `Text` can do must be reachable from TUI's inline Markdown parser. | Out of scope; no further reason recorded. | `4324fc72e` (inline Markdown reaches every `Text` style). Supersedes the earlier wish for Markdown beyond Foundation. |
| POINTER-API | The structure is right; the name `controlPointerStyle` is rejected. Then `.pointingHandCursor(over: .links / .everythingClickable)` approved. | "Control" is overloaded; pick a precise, self-explanatory name. | [Pointer shapes](<../Terminals/Pointer shapes.md>) |
| A-APPSTATE-2 | Multi-client in one process: tabled. The three process-wide statics stay shared, exempt from the no-singletons rule. | The rule is about testability and conflicting needs; moving the notification queue per app has little practical benefit. | The exemption on CLAUDE.md's rule; [per-app render state](<../State and dynamic properties/Per-app render state - no singletons.md>) |
| OS-MASCOTS | The Example's picture defaults to the platform's mascot (macOS: Lil' Finder Guy; Linux: Tux; Windows: Touko Madobe; WebAssembly: Swift's logo), and the built-ins can be cycled. The owner re-encoded the files. | The first page asked for a cartoony, CC-licensed picture with subtle gradients that stays clear in glyph modes. Licensing of the Apple and Microsoft characters: fine, the owner's call. | `6713bae9c`, `e8c0e8108`; credits in `THIRD-PARTY-NOTICES.md` (2026-10-31, below) |
| KITTY-DND | kitty's OSC 72 drag and drop: a to-do, not now. | None recorded. | Queued |
| DOCUMENTS | Document support is wanted, but is a big project (overlapping windows or a tab-based document model): design first. | None recorded. | `DocumentGroup` approved 2026-11-01, below |
| CLIPS | The clipboard clip drops its drag-out-to-Finder part unless a real, creative way exists; a document-lifecycle clip showing the open and save panels, drafted and approved. | None recorded. | Not traced |
| VEIL | Flattening hid borders and progress bars, wrongly; veiled was too bright. Dim and mute it more, so the page reads as disabled and unimportant yet stays visible on a close look. | As stated. | 25d60 on 2026-10-28; [sheets](<../Presentation and windows/Sheets - sizes, detents, live sheets and the page behind.md>) |

### 2026-10-28

The morning's VEIL, PREVIEW-IMAGES, TEXT-EFFECTS and PICTURE-ASPECT are in
the ledger. Also:

| Id | Decision | Why, as recorded | Where it went |
|---|---|---|---|
| SMALL-IMAGE-ON-FRAME | Keep decoding a small file on its first frame, but make the threshold configurable, down to 0 for all asynchronous. | None recorded. | `b554f6c37`, `.imageSynchronousDecodeLimit(_:)` |
| PICTURE-ASPECT | Asked to see the options first (filmed); chose each picture at its own aspect (fit letterboxes, fill crops, stretch stretches), and exact pixels at rest with no peak image. | None recorded. | [Terminal graphics protocols §8](<../../Images and terminal graphics/Terminal graphics protocols.md>) |
| CURSOR-GATE | (b): control pointer shapes on for the documented OSC 22 terminals, and the pointer shape reset on exit. | Assume terminals restore the pointer on quit, and reset it anyway to be safe. | [Terminal compatibility survey](<../../Terminals/Terminal compatibility survey.md>), OSC 22 |
| CURSOR-CHOICES | (a), the agent's picks: the arrow over buttons and rows; the hand only for links; drags keep the arrow; a `NavigationLink` the arrow; a sheet's grabber row-resize; no not-allowed shape. | None recorded. | [Pointer shapes](<../Terminals/Pointer shapes.md>) |
| SELECTION-BOX | (b): a screen selection is boxed by the views: each `Text` files its frame, and the highlight is clipped to the frames it crosses. | None recorded. | [Keyboard screen selection](<../../Input and focus/Keyboard screen selection.md>) |
| LIST-PREVIEW | A preview pane in the file panels' list mode too, behind a collapsible splitter, open by default only where the panel is wide enough for it and the list. | None recorded. | `758c89ce5` |
| FILE-DIALOG-KEYS | Shortcuts for much of the file panels (view modes and so on), following macOS's conventions as far as possible. | None recorded. | Not traced |
| READOUTS | (a): an optical read-out wherever a built-in centres a numeric value. | None recorded. | `OpticalReadout` (numeric controls) |
| SPLIT-COLLAPSE | (a): removing the sidebar toggle is what was meant. | None recorded. | Not traced |
| OPTION-KEYS | (a); the owner runs the key probe in Ghostty for ⌥F, ⌥⇧F and ⌥/. | None recorded. | Settled 2026-10-29 (OPTION-IN-FIELD) |
| LIVE-LOOK | (a): the live look may take the whole screen. | For Ghostty's bugs. | Not traced |
| BRAILLE | (a): colour braille paints its background from the mean of its unlit dots; an explicit threshold control, "Auto" by default, for braille and mono; exposure, contrast, black point and highlights after. | None recorded. | `be14c25b8`; `.imageInkThreshold` in the compatibility guide |
| DITHER | Unanswered, so the default (b): dithering left to reduced palettes. | No answer. | As built |
| HERO-CLIP | The owner reviews and decides later. | — | Open |

### 2026-10-29

| Id | Decision | Why, as recorded | Where it went |
|---|---|---|---|
| NEG-PADDING | Negative padding as SwiftUI does it: the frame shrinks, the content overhangs. Replaces the clamp to zero shipped the night before. | As SwiftUI does. | `398eeb1e4`; deviation U6 |
| TIMELINE-ZERO | Never crash: a zero, negative or NaN `TimelineView` interval keeps giving one entry. | Never crash. | As built |
| SECOND-RUN | Guard a second `App.run()` while one runs. | None recorded beyond one app per process. | `9ded51e06` |
| OPTION-IN-FIELD | Characters reached with Option or Shift-Option are typed in a text field; chords whose modifiers reach no character (Control, Command) go to shortcut handlers first, with no exceptions: a field's ⌃U, ⌃W and ⌃A give way to an app's shortcut on the chord. | Text first where a character is meant. | `KeyboardShortcuts` article, "Your Shortcuts and the Editing Chords" |
| OVERCONTENT-KEYS | `.overContent` indicators sit over the content for the pointer's hover; while the view has the focus they move beside it. The agent had misread round 2 as "never on focus". | A correction of a misreading. | `b2fa6517d`; the ledger, 2026-10-29 |
| SELECTION-KEYS | Screen selection stays mouse-only for now; a design proposal (selectable `Text`, hints, a copy mode) is written into Documentation and shelved. | None recorded. An explicit exception to the no-mouse-only rule, for now. | [Keyboard screen selection](<../../Input and focus/Keyboard screen selection.md>) |
| ROW-STATE | A+: keep SwiftUI's lifetime; decoded pixels out of row state. | "No compromises that make it unpredictable … Deterministic or nothing." | [Row state lifetime](<../State and dynamic properties/Row state lifetime (2026-10-29).md>) |
| CUSTOMIZE-CHORD | No new chord: View ▸ Customize Toolbar… wherever a customizable toolbar is shown, reached by F10, even without `ToolbarCommands`. | None recorded. | `21e40a50d`; [toolbars](<../Menus, toolbars and chrome/Toolbars and opt-in window chrome.md>) |

### 2026-10-31

| Id | Decision | Why, as recorded | Where it went |
|---|---|---|---|
| QUIT | ⌃Q is the default quit, with no dialog unless something would be lost (an unsaved document, the developer said so, activities in progress, each named). ⌃\ asks first, and a second press quits. ⌃C is copy and never quits, not even with a dialog. | Revised the same weekend: don't overload Control-C, which is copy. | `07fd3eda3`, `79030ff9e`; the scenes and quitting articles |
| NOTTY | With no terminal to draw on (a file, a pipe), exit gracefully with a message by default, and give an app a clean way to run another mode instead. | None recorded. | `6d858f7b4` |
| RENDERONCE | Draw from the current line, end with a newline, and write plain text when piped, unless a variable or parameter asks for escapes anyway. | None recorded. | `d545e8078`; `TUI_FORCE_ESCAPES` |
| STUBS | `@available(*, unavailable)` stubs, with a message naming the alternative, if they don't clutter code completion. | Only if they don't clutter IDE autocomplete. | The compatibility guide's introduction |
| HONEST | A positive, accurate tagline in place of "most of it": "TUI speaks SwiftUI's language, with a terminal accent." | "Most of it" raises questions. | README |
| ART | The eagle photo is the owner's, CC BY-NC 2.0, noted sufficiently, not prominently; other art may be used with its source linked and authors credited. All nature and wildlife photos are the owner's, same licence. | None recorded. | `THIRD-PARTY-NOTICES.md` |
| CIPUSH | No `ci/*` branches. The owner pushes to main when needed; batch work and ask for a push only when a round is worth a CI run. | CI runs are expensive. | Working practice |
| RELEASE, WINDOWS | Leave both for now; the owner will do Windows soon, on another machine. | None recorded. | — |
| A7 | Try per-change transactions and bring the A/B; approved to land on 2026-11-01. | None recorded. | `ac0a736d3`; deviation A7 |
| MAINACTOR | Fix it, better than SwiftUI; then no async overloads or policies, no `@preconcurrency`, and the floor may rise to macOS 15. | "Better than SwiftUI"; none recorded for declining the overloads. | [Building views off the main actor](<../Swift language and platforms/Building views off the main actor.md>) |
| TESTKIT | A testing product, used for TUI's own tests, replacing internal helpers where it can, documented prominently on the docs' landing page. | None recorded. | `0d095d0ed`; the testing article |
| SHIP | The README is the landing page for discovery; the website (mostly DocC) is the outward documentation; inward-facing `Documentation/` must not appear on the website. | None recorded. | `Documentation/README.md` |
| HOVER | A hover effect may keep or enlarge its view, never shrink it; keep the anti-flicker guard. | None recorded. | `53f940de8`, `78d05f084` |

### 2026-11-01

The rulings are tabulated in the [SwiftTUI comparison](<../SwiftTUI comparison, 2026-11/README.md>).
The reasons the owner gave, which that table leaves out:

| Subject | Why, as recorded |
|---|---|
| A checked-in record of the comparison | So progress can be compared after optimisation. |
| No ASCII-only mode | It makes no sense; a text-only mode is doubtful, and the owner asked for concrete examples. |
| Local web server, never a listening port unasked | The owner dislikes bespoke servers and unencrypted HTTP. |
| `DocumentGroup` | One-at-a-time windows are no barrier; `FileWrapper` on Linux seems the only real challenge. |
| Pixel mouse | A compatibility gain (SwiftUI's types); supported, decided later that day. |
| Hot reload, not hot restart | Hot restart would lose all state TUI doesn't know about. A reload may relax the usual performance limits but must not take more than a second or two. |
| Breathing stays | Idle cost is accepted; that SwiftTUI lacks it is its flaw. |
| FIGlet | No 7 MB cost in apps for a neat feature; later the same day, punted: a third-party package can do it. |
| Animated images | Do it, if it fits the existing `Image` API as easily as described. |
| `FORCE_COLOR` | A boolean that overrides automatic colour removal, so it must never lower a depth: a floor. |
| Help overlay | F1 feels right, perhaps ⌃F1. |
| Running bodies less | More work wanted; [the plain-body memo](<../State and dynamic properties/When a body runs - the plain-body memo.md>) followed. |

### 2026-11-02

The ledger holds every answer of the day. The reasons recorded:

| Id | Why, as recorded |
|---|---|
| PLAIN-MEMO | [Its story](<../State and dynamic properties/When a body runs - the plain-body memo.md>). |
| WARP-PARTIAL | A partly visible picture on Warp can't just be dropped: send a cropped copy, several if the crop is irregular (a view over its middle, or a corner). Warp's own cost isn't critical, since it is paying for its missing functionality; mind the cost on other terminals, and code size. |
| SIXEL | Build it now, tested on a Mac client (iTerm2) with Kitty graphics turned off on the client side where possible, to mimic the real case of falling back to Sixel. |
| ANIM-MOTION | A per-image override of whether Reduce Motion stops its animation: content probably animates regardless, chrome probably doesn't. |
| ENV-PRECEDENCE | `TUI_REDUCE_MOTION` beats the system's setting either way; `COLUMNS` and `LINES` are gospel even where the size can be detected and differs. No reason recorded. |
| ONE-LANE | One agent at a time, then gate and land, then the next, after six ran at once; holds until the owner lifts it. |

### 2026-11-07

- **SHEET-KEYBOARD:** resizing and moving a sheet from the keyboard, its
  rejected alternatives and the owner's reasons, in
  [the sheets story](<../Presentation and windows/Sheets - sizes, detents, live sheets and the page behind.md>).
- **The review of 71 commits by another author,** in
  [Reviews and audits](<../Reviews and audits/A review of 71 commits by another author (2026-11-07).md>).
