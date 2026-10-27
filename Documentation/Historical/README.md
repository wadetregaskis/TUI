# Historical

How TUI came to be the way it is: the problems met, what was measured and considered, what was
decided and by whom, and where each thread ended. Nothing here describes the code as it is now;
the live documentation in `Documentation/` does that. This is the context a future reader (human
or AI) needs to understand *why*, and to know what to watch for.

## How it is arranged

**By topic, one story per subject** (reorganised on 2026-10-26). A story gathers every thread about one subject from wherever it was recorded — the
owner's decisions, the lanes' decision files, investigations, design studies — and tells it in one
place:

- **In short**: where it ended, in a paragraph.
- **The problem**, and **how it unfolded**: dated, with who decided what.
- **Where it stands**, including anything still open or owed.
- **For a future reader**: what to revisit, what holds only while something else is true, and
  measurements owed.
- **The record**: each decision entry in the words of the day, under its original heading, so its
  id and its anchor are unchanged. A link to an entry needs only its file name updated when the
  entry moves.

| Topic | Stories |
|---|---|
| [Colour and styling](<Colour and styling/>) | Named colours and dark values; content levels, foreground styles and legibility weight. |
| [Controls and forms](<Controls and forms/>) | Forms and control density; sliders, selections and search. |
| [Images and terminal graphics](<Images and terminal graphics/>) | An image's natural size, tiles and caps. |
| [Input, keys and gestures](<Input, keys and gestures/>) | The kitty keyboard protocol; how keys are named; gestures and taps; drag and drop; large pastes; focus and focused values. |
| [Layout and geometry](<Layout and geometry/>) | Alignment guides that travel; drawing past a region; stack spacing and what a container counts as its children; sections and pinned headers in lazy stacks; where a view is (coordinate spaces, geometry readers, scroll visibility); sharing space; safe areas, size classes and layout direction. |
| [Lists, tables and tabs](<Lists, tables and tabs/>) | Stripes, surfaces and separators; badges and row prominence; acting on rows; table columns; type select, Home and End; which rows a list draws; tab views. |
| [Localization](<Localization/>) | Which language a key is read in. |
| [Menus, toolbars and chrome](<Menus, toolbars and chrome/>) | Pop-up menus; the menu bar; toolbars and opt-in window chrome. |
| [Module split, compile time and binary size](<Module split, compile time and binary size/>) | The module split; winning back its cost; per-module products; binary size; compile time and the test targets; the linker's RWX warning on Linux aarch64. |
| [Presentation and windows](<Presentation and windows/>) | Sheets and the page behind; windows; file panels; help and tooltips; compact adaptation; dialogs and pickers. |
| [Reviews and audits](<Reviews and audits/>) | The first reviews of the codebase and its tests (May 2026). |
| [Scrolling](Scrolling/) | Holding the reader's place; paging and view-aligned scrolling; content past a scroll view's edge; scroll phases, animated scrolling, flash and bounce; scroll position and visibility; measuring a scroll view's content. |
| [Shapes, effects and animation](<Shapes, effects and animation/>) | Transitions; animation timing; shapes; shadows; matched geometry; materials and glass; pixel effects; accessibility settings. |
| [State and dynamic properties](<State and dynamic properties/>) | Finding dynamic properties; class properties held by several views; per-app render state; the update model. |
| [SwiftUI parity process](<SwiftUI parity process/>) | The refusals re-examined; the semantic audit; completing the SwiftUI API; Apple-only API; the owner's decisions record. |
| [Terminals](<Terminals/>) | Adopting Ghostty's documented features; the host ledger; pointer shapes; grapheme widths; terminal capabilities for apps. |
| [Text, editing and the clipboard](<Text, editing and the clipboard/>) | Copying out of a terminal; text fields and the wrapping editor; undo; links, Markdown and attributed text; formatting and live text. |

[Index of decision ids](<Index of decision ids.md>) finds the story holding any id (B30,
B-D2S-6, A-SCROLLANCHOR-1…) cited by a commit message, a code comment or an older document. The
originals of a dissolved file are in git: `git log --diff-filter=D --name-only -- 'Documentation/SwiftUI parity/Decisions' Documentation/Historical`
lists them, and `git show <commit>^:<path>` reads one as it was. A story's source citations (a
file and its line numbers) name the files as they were when the entry was written.


## Conventions

- When a document in `Documentation/` becomes outdated or is replaced, its substance joins the
  topic's story here (or becomes one), rather than being deleted. Dates go in the text, not the
  file name, since a story spans many.
- Genuinely **transient** scratch files — working notes, question trackers, throwaway TODOs —
  are not committed at all.
