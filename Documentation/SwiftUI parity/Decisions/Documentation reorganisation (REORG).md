# The documentation reorganisation: lane REORG's decisions for review

*A companion to [`SwiftUI API completion decisions.md`](<SwiftUI API completion decisions.md>),
written by the lane that carried out the owner's request of 2026-10-12: "use human-readable names
(e.g. spaces between words, not underscores or hyphens) with reasonable detail … And arrange things
into subfolders when there's multiple related items (related in topic, not merely date)." Every
document under `Documentation/` but `Historical/` moved or was renamed (116 files, `git mv`, so
`git log --follow` keeps their history), and every reference to one, in the documentation, the code's
comments, the tools, CI and `.claude/CLAUDE.md`, names the new path. `git diff -M --name-status b95d6039f bbe8e918f`
lists every old-to-new name. No document was split, merged or rewritten. It holds only what
that work raised that the request did not settle, in the main file's three parts.*

- **A. Needs your decision.** Nothing has shipped for these. None.
- **B. Shipped the safe option.** Each entry says what the fuller version would be, and its price.
- **C. Declined without asking.** None.

## B. Shipped the safe option

### B-REORG-1. The main decisions document moved, and only its references changed

*[`SwiftUI API completion decisions.md`](<SwiftUI API completion decisions.md>)*

The brief said not to edit it: the owner is reading it, and the coordinator removes finished items
from it himself. The request moves it beside its companions, and a move breaks every relative link
in it. It moved, and 16 of its lines changed, each one only where it names another document: a link
target (to the plan, `Future options.md`, the refusal review, the text-editing design study, the
DYNP file, the deviations page) or a file named in prose (`Terminal compatibility survey.md`,
`Scroll anchoring.md`). Nothing else in it changed.

**Fuller version:** none needed. **Price:** a removal of a finished item that touches one of those
16 lines conflicts when this commit is merged; the resolution is to keep the removal.

### B-REORG-2. A link with a space in it is written `<like this.md>`

Two spellings work on GitHub: CommonMark's pointy-bracket destination, `[x](<Some name.md>)`, and
percent escapes, `[x](Some%20name.md)`. The names now carry spaces, commas and parentheses, and
`Some%20name%2C%20A28%20%282026-10-04%29.md` is not readable in the source, so every relative link
whose target has a space or a parenthesis uses the brackets, and the old `%20` links (to
`Historical/`) were converted. A link without a space stays plain. Absolute URLs would still be
percent-escaped; no committed document has one into `Documentation/`.

**Fuller version:** none. **Price:** a Markdown renderer that is not CommonMark-conformant reads
`<…>` as text; GitHub, DocC and the Swift Package Index (which shows GitHub's rendering of the
README) are not such renderers (unmeasured for the last).

### B-REORG-3. A hyphen inside a compound word stays

"Spaces between words, not … hyphens" is read as: a hyphen that SEPARATED the words of a name
(as in the old names of the compatibility guide and the review batches) became a space; a hyphen
that is part of a word's spelling stays (`Keyboard drag-and-drop.md`, `Out-of-band styling surface.md`, `Intra-line output
diffing.md`, `the input-reader loop`, `opt-in`, `write-back`, the package name `swift-syntax`, and
ISO dates). `Out of band styling surface.md` would misspell the document's own title.

**Fuller version:** none. **Price:** none known.

### B-REORG-4. `Historical/` keeps its prose

`Historical/`'s files are records of their time and were already readably named; none moved. Its
prose names documents by their names of the day 17 times (the live-sheets study 10, the geometry
study 3, the module split plan 2, the emoji note 2); those stay, as quoted history. No file in
`Historical/` has a relative link, so no link there broke.

**Fuller version:** rename those mentions too. **Price:** history that no longer says what it said,
for a reader who can follow `git log --follow` from either name.

### B-REORG-5. Links that were broken before the move are fixed; one stale reference is left

`Tools/validate-markdown-links.py` (new, run in CI beside the table check) found 16 broken links in
the tree before the move, and they were fixed in the commit that adds it:

- 15 in `Gradients where a colour is accepted.md` were written from the repository's root with a
  line number, `Sources/X.swift:123`, which GitHub reads as a file named `X.swift:123` beside the
  document. Each now points at the file from the document, with GitHub's line anchor (`#L123`).
- 1 in the deviations page named B-D3M-1's heading without the U+FE0F variation selector of its ⚠️.
  GitHub's slug keeps combining marks (its filter keeps letters, marks, numbers, `_`, `-` and space),
  so the anchor now carries it, escaped as `%EF%B8%8F`. Unmeasured on GitHub itself.

Three references named wave decisions files that had been folded into the main document (wave 12:
B52–B61; wave 11a: B48–B51). The two to wave 12 (`Transaction.swift`, B55; the compatibility guide's
Animation row, B52) now name the main document, where both items still are. The one to wave 11a
(`TimeSpan.swift`, the unit spellings) is left as it was: its item is no longer in the main document,
so there is nothing to point it at. The text-editing design study's sentence that names wave 6b's
decisions file as one "which no longer exists" is about that absence and stays.

**Fuller version:** point `TimeSpan.swift` at the commit that folded wave 11a in (3c8fcbff0) or at
wherever the owner keeps finished items. **Price:** a comment pointing at history.

### B-REORG-6. Inside `Decisions/`, two topic folders, and step order for the module split

`Decisions/` holds the main document and every per-lane companion. Two groups are one topic each and
got a folder: **Module split/** (23 lanes: the steps, their cost recovery, the per-module products)
and **Compile time and binary size/** (BT1, TC1, TT2, SHIP, SHIP2, BNDL). The module split's files
are named "Step B5b, carving …", "Steps C3 and C4, peeling …", so a listing reads in step order, and
its cost-recovery lanes sort together as "Cost recovery, …". The SwiftUI API lanes, and the fixes and
follow-ups recorded in the same format, stay flat: their topics overlap (one lane covers input and
gestures, another lists and scrolling), so finer folders would split them arbitrarily. Every file
keeps its lane tag in parentheses at the end of its name, because commit messages and notes cite the
tags. This file is here rather than at `Documentation/SwiftUI-API-completion-decisions-REORG.md`,
the old scheme's path, which the move retires.

**Fuller version:** topic folders for the flat lanes too (input, lists and tables, presentation).
**Price:** a lane in two topics lives in one; the owner's call if the flat list grows.
