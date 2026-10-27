# Historical

How TUI came to be the way it is: the problems met, what was measured and considered, what was
decided and by whom, and where each thread ended. Nothing here describes the code as it is now;
the live documentation in `Documentation/` does that. This is the context a future reader (human
or AI) needs to understand *why*, and to know what to watch for.

## How it is arranged

**By topic, one story per subject** (reorganised from 2026-10-26; topics are being moved in one
at a time). A story gathers every thread about one subject from wherever it was recorded — the
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
| [Scrolling](Scrolling/) | Holding the reader's place; paging and view-aligned scrolling; content past a scroll view's edge; scroll phases, animated scrolling, flash and bounce; scroll position and visibility; measuring a scroll view's content. |

[Index of decision ids](<Index of decision ids.md>) finds the story holding any id (B30,
B-D2S-6, A-SCROLLANCHOR-1…) cited by a commit message, a code comment or an older document. The
originals of a dissolved file are in git: `git log --diff-filter=D --name-only -- 'Documentation/SwiftUI parity/Decisions'`
lists them, and `git show <commit>^:<path>` reads one as it was.

## Still to be arranged

The records below predate the arrangement and will be folded into topic stories:

- [Owner decisions, 2026-10-18 to 2026-10-25](<Owner decisions, 2026-10-18 to 2026-10-25.md>):
  every owner question of that week, the answers and what each set in motion.
- [Investigations/](Investigations/): one-page summaries of investigations whose decision landed.
- The dated design studies, plans and reviews in this folder.

## Conventions

- When a document in `Documentation/` becomes outdated or is replaced, its substance joins the
  topic's story here (or becomes one), rather than being deleted. Dates go in the text, not the
  file name, since a story spans many.
- Genuinely **transient** scratch files — working notes, question trackers, throwaway TODOs —
  are not committed at all.
