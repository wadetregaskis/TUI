# A review of 71 commits by another author (2026-11-07)

*The owner's request of 2026-11-07 to review everything another author
committed while the usual lanes were away (`c13e4536d..5d300ea7c`), what was
found, what was fixed, and the faults that recurred. Ids: none.*

## In short

Seventy-one commits were read by seven read-only reviewers, one per area
(file preview, text input, text layout, sheet resizing, folders, observation,
rendering), and the small ones directly, after CI run 97 on `16dfc440f` had
failed. Most were good. Ten needed correcting and twenty-one were right but
incomplete, by the reviewers' verdicts. The fixes, the lint the gate needed and a sweep of the
observation sites still missed landed as `b5bc4886a` to `6675bf56a` (40
commits). One finding needed the owner: sheet resizing (`4daf05ce9`) had no
keyboard route, and the owner designed one the same day (the
[sheets story](<../Presentation and windows/Sheets - sizes, detents, live sheets and the page behind.md>)).

## The problem

The owner asked, for each commit: is it valid, does it have bugs, is the fix
complete? Then fix, and report what was good, what was corrected and what was
elaborated. CI had already failed on the range: a `file://` image on Linux
(URLSession can't load one there), three DocC links broken by a changed
signature, the `Task.sleep` ratchet at 61 against a limit of 50, and a macOS
15 flake.

## How it unfolded

1. **The review.** Verdicts per commit: GOOD, CORRECT (wrong, fix it) or
   ELABORATE (right but incomplete: a twin site missed, docs stale, a test
   that can't fail). The findings log stayed in session notes; its substance
   is below.
2. **The fixes**, one per finding, each with a test that fails without it.
3. **The gate gap.** The local gate did not run `Tools/check-ratchets.py`,
   which CI's API-parity job does, so the ratchet was blown unseen. The gate
   runs it now. CI's lint is not `--strict`, so lint failures (file length,
   complexity) don't fail there either; they were fixed by hand.

## What was corrected

| Commit reviewed | What was wrong | Fixed in |
|---|---|---|
| `e76d296cf` | An animation decoded while not shown, and scaled pixels animated wrongly: a deliberate guard removed without reading its comment. `file://` went through URLSession, which can't on Linux. | `c04b4591a`, `762547811`, `9ecc5a7f8` |
| `d3bcd757e` | A "Linux fix" removed the document and then moved the new one in, losing the atomic save, and swallowed the remove's error. | `cba2b9800` |
| `11268b779` | A nil underline took the palette's foreground; picture placement ids could be rewritten; colon-form SGR 58 mismatched. | `267205175`, `d8d8b93c3`, `19d6f2ae5` |
| `8d9b36156` | A zero-width spacer stayed in its priority group on the second deal, overflowing the row. | `b5bc4886a` |
| `7b449109b` | The paste filter dropped tabs, and the test locked that in; `TextEditor` drew control characters unsanitised. | `39d5ac512` |
| `1bd7d297a` | A sheet saved the axis the user hadn't sized. | `e4c8c364e` |
| `e15bcf07d`, `fbab540cf` | The preview's "more" indicator counted bytes after tab expansion, and sized truncation from `stat` (0 on procfs). | `e4a763633` |
| `431882f8f` | Folder timers on the wall clock, with tests that passed without the change. | `05ebae471` |
| `4daf05ce9` | Sheet resizing by mouse only, against the rule that every interaction has a keyboard route; no docs. | The owner's design, 2026-11-07 (sheets story); queued |

Elaborated, among others: the caret after a typed mark that merges
(`61d594f75`), a triple-click's paragraph at CR LF (`79855ab24`), an asset
catalogue's hex (`304599e07`), raw mode's INLCR and IGNCR (`e8a29289c`),
SecureField's ⌃W (`6c25af2aa`), "Loading…" rows kept out of the selection
(`d2a82ea01`), a fold's indent (`5b96ce078`), styling after a reversed span
(`c6547e512`), the format characters' zero width stated as Unicode's rather
than measured (`88e96355e`), a copied sampler shared (`7c562d0ae`), sleeps
replaced by waits and the ratchet lowered to 46 (`8300812c2`), and the
untracked closures the observation reviewer listed (`e325b7cc9` to
`d002555e9`, `6675bf56a`).

## For a future reader

The faults that recurred, worth checking first in any batch from an author
new to the codebase:

- **Tests that pass without the fix** (`19a59fcae`, `431882f8f`'s): revert
  the fix and run the test.
- **Real-time `Task.sleep` in tests and timers on the machine's clock**:
  they flaked on CI and blew the ratchet.
- **One site of a bug class fixed, its twins not**: `TextField` but not
  `TextEditor`, paste but not typing, `Color.hex` but not the asset
  catalogue, one observation site of many.
- **A deliberate guard undone without reading its doc comment.**
- **Data-safety regressions inside "platform fixes".**
- **Docs claiming measurements with no committed record** (`8e7908032`'s
  survey lines on tmux).
- **Lint never run locally**, which CI does not catch.
- **A commit landing before the fix to its own test** (`09cde9a5a`, fixed in
  `c3a12c05a`), which breaks bisection.
