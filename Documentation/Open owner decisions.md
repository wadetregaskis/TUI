# Open owner decisions

What is waiting on you, re-checked on 2026-10-26 against `main`. Each question was put to you between
2026-10-18 and 2026-10-24, and its full write-up, with the options and the evidence, is in the
historical record, [Owner decisions, 2026-10-18 to 2026-10-25](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md>). That record also holds every
question you have already answered and what each answer set in motion. None of these blocks other work:
each has a default, which holds until you answer.

Answer by id and option ("B75: a"); a bare "yes" takes the recommendation.

## Owner actions

- **Push `main`.** Local `main` is 261 commits ahead of GitHub (last pushed 2026-10-24, `9f8439764`).
  It includes the rename to TUI (`c5cdfca27`): pushing it renames every module and product for anyone
  depending on `main`.
- **Rename the GitHub repository to `TUI`,** then say so. The commit that points every URL at the new
  name (branch `hold-repourls`) lands only after the rename, since GitHub redirects old names to new and
  never new to old.
- **The 2026-09-01 stash** (`stash@{0}`, "WIP on main: e4155942 RTL: the override is refused…") is still
  there, made by no agent: keep or drop.
- **Compiler bug reports** on the Desktop, one file per bug, are yours to file.

## Decisions waiting on you

These are the follow-ups to answers you gave on 2026-10-23 and 2026-10-24: each was answered or
measured, and ends "your call".

| Id | Question | Recommended | If you don't answer |
|---|---|---|---|
| [B-D6M-2](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md#b-d6m-2>) | Should the @Animatable and @Entry macros move into a separate package, in a second repository, so apps that don't use them never resolve swift-syntax? | (a) for now, and measure (c) cheaply. Take (b) only if users complain about resolution time or conflicts, because two packages are an ongoing release cost. | Things stay as they are: every client resolves swift-syntax and only macro users compile it. |
| [B-DYNVFIX-3](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md#b-dynvfix-3>) | When several views hold one class object, closures made in any of them read the first holder's environment. Do you accept that limit, want the cheap 'focused holder becomes primary' fix prototyped, or want the full per-dispatch fix built? | (b), landing it only if the A/B is flat. Decline (c). | The limit stays documented, and a sheet that shares its page's object needs the workaround. |
| [PACKAGE-RESOLVED](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md#package-resolved>) | Should Package.resolved be committed fresh once, as an exception to your 'never commit it' rule, or removed from git and ignored? | (b). It matches your never-commit rule permanently and ends the noise. (a) is the census's earlier suggestion if you'd rather keep pins. | The stale file stays committed, and every worktree carries a local modification that agents must skip. |
| [SDK15-CI](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md#sdk15-ci>) | Should CI build TUI with a swift.org 6.2 toolchain against the macOS 15.5 SDK, which is what a swiftly user on macOS 15 with the default Command Line Tools gets? | (a) if you want swiftly users on macOS 15 supported (your 10-07 point that users may not use Xcode); otherwise (c). I lean (a). | In effect (b): it builds today and may silently stop. |
| [B-D2S-6](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md#b-d2s-6>) | Under a scroll target behaviour such as `.paging`, should a `.text`-indicator scroll view keep its '▲ N more' / '▼ N more' lines drawn at every stop (shipped), or let them come and go and make every page two lines shorter? | Option 1, unless the '▲ 0 more' line at the top bothers you on the Example's Scroll View page. | The pair stays drawn at every stop under a scroll target behaviour. |
| [S3-NO-EXTENT-SPACING](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md#s3-no-extent-spacing>) | Should a stack put its spacing on both sides of a child that takes no rows (an empty `VStack`, `Color.clear.frame(height: 0)`), as SwiftUI does, or keep TUI's rule that such a child takes no gap? | Option 2. Your stack-spacing rulings so far all followed SwiftUI (A-BITEMS1-1, L12, L14), and the gap is the app's own spacing request. Ship it only after the audit shows framework internals won't add stray gaps. | TUI's rule stays, the Example keeps relying on it, and it stays an open divergence in guide §3. |
| [B75](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md#b75>) | Should a tab whose label is the app's own view (Tab(content:label:)) draw that view inside its chip in the tab strip, instead of only its first line as plain text? | Option a, unless you want pictures in chips for TAB-IMAGE-NAME, in which case b. | Chips keep drawing a custom label as text. The shipped option stands, open to your veto. |
| [B-D5C-1](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md#b-d5c-1>) | Keep TUI's extra windowToolbarStyle(_: any WindowToolbarStyle) overload, replace it with if/else support in SceneBuilder, or have the Example choose its toolbar style only at launch? | Option 1. | The overload stays. |
| [B63-CTRLJ](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md#b63-ctrlj>) | Should the input parser read LF (0x0A) as Ctrl-J instead of Return, so a vertical TextField can bind Ctrl-J to insert a newline on every terminal? | Parse LF as Ctrl-J. The existing fallback limits the risk to vertical fields, and the result is a newline key that works on every terminal, Apple Terminal included. | LF stays Return. In a vertical field a newline is Ctrl-O everywhere, or Option-Return where Option is sent as Meta. |
| [B63-KITTY](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md#b63-kitty>) | Under the kitty keyboard protocol, should Ctrl-Return in a vertical TextField insert U+2028 LINE SEPARATOR, as SwiftUI does, instead of submitting? | Insert U+2028, as SwiftUI does, once the text-path work is priced. If that comes to more than about a day, ship '\n' for now. | Ctrl-Return submits a vertical field on every terminal, as it does today. |
| [B89](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md#b89>) | Should every control's press become a full gesture recognizer that can wait, fail and be cancelled, as SwiftUI's plain-style button is? | Keep for now. Build it when a port needs a gesture on a control to hear a press that failed: the cases are narrow, and the change touches every control's click path. | Controls never fail or wait, and the two differences stay as documented. |
| [A48](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md#a48>) | How should SwiftUI's .swipeActions be reached in a terminal: as an edge menu opened by a row chord or a horizontal wheel, as buttons revealed in the row, or not at all? | Option 1. A swipe action is a context menu for one edge, and the menu engine already provides the keyboard handling, dismissal and colours. | swipeActions stays unbuilt (two parity gaps), and SwiftUI code that uses it does not compile. |
| [A53-KEYBOARD-DRAG](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md#a53-keyboard-drag>) | Should .draggable get a keyboard route, overriding your 2026-07-30 decision to table keyboard drag-and-drop on modality, or should .draggable be recorded as an explicit exception to the no-mouse-only rule? | Confirm the tabling as an explicit exception and document the .copyable/.pasteDestination route. The modality objection still stands, and the same copy-and-paste route is what SwiftUI offers on macOS. | .draggable stays mouse-only with no recorded exception, an open breach of the no-mouse-only rule. |
| [B-BITEMS1-1](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md#b-bitems1-1>) | Beyond the badges ruled on 10-12 (+ for copy, ↗ for link, ⊘ for forbidden, nothing for move), should a .delete drop wear a glyph, and should dropDestination propose .copy so its drags show +? | Leave .delete bare. Have dropDestination propose .copy only once a real-window macOS probe shows the +, since TUI shouldn't claim macOS behaviour it hasn't measured. | Only item-provider drops show badges; .delete, .cancel and TUI's own destinations show none. |
| [O13-KEYS](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md#o13-keys>) | For the menu bar that O13 has now landed on main, should the keys stay the ones you accepted on 10-04 (F10, Alt-letter, a click), with no extra chord and no TUI-only menuBarVisibility for now? | The 10-04 keys. The 10-05 objection was about spending F-keys on a minor feature, and opening a menu bar is F10's standard use. Measure F10 (the lane landed without measuring it), and add a chord or menuBarVisibility only if an app asks. | The menu bar keeps the keys it shipped with (F10, Alt-letter, click), with no extra chord and no menuBarVisibility. |
| [B-HELP-2](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md#b-help-2>) | Should '?' pressed when the focused control has no help show every help panel on screen, with '?' again hiding them, as the keyboard route to the help on views that can't take focus? | '?' reveals all. It closes the mouse-only gap that your 10-12 ruling and the no-mouse-only rule both point at, using the help key users already know. | Non-focusable help stays keyboard-reachable only where the app turns on .tooltips(.always), and '?' with no help on the focused control does nothing. |
| [B-PASTE-1-EDITOR](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md#b-paste-1-editor>) | Should TextEditor and TextField be redesigned for large text: undo that records edits instead of whole-text copies, and possibly UTF-8 storage? If so, should it be folded into A42's storage refactor once the 16 MiB paste has been measured? | Measure first, then do undo-as-edits inside R1: it is the big, cheap win. Take on the UTF-8 storage redesign only if the measurement shows a 16 MiB document is unusable. | Nothing changes. Large texts keep the memory costs above, and R1 keeps whole-text undo. |
| [B86](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md#b86>) | Should TUI's Markdown parse close its two known differences from Foundation's: all 2,125 HTML named entities, and link reference definitions? | Leave both until a translation needs them, as the decision doc says. If you want the parse identical, do reference definitions first, since they cost no bytes. | Both differences stay, recorded in T3. |
| [A27](<Historical/Owner decisions, 2026-10-18 to 2026-10-25.md#a27>) | For Wave 16's leftovers, do you take the recommended set (decline the six transforms, ship mask(alignment:_:) at cell coverage, ship drawingGroup as compositingGroup)? And should linear-light blending be added so that drawingGroup(colorMode: .linear) is honoured rather than ignored? | Option 2. Declining the transforms keeps rule 2 (nothing is silently ignored), mask and drawingGroup have honest cell readings, and linear blending is cheap and makes drawingGroup's colorMode honoured instead of documented as ignored. | All eight stay as gaps that fail to compile, A39 keeps waiting, and blending stays in encoded sRGB only. |

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
