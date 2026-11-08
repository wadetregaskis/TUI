# ASCII transliteration before layout

An experiment behind a flag, `TUI_PLAIN_TEXT=transliterate` (owner, 2026-11-08: "Build. At least try it, and let's see
if it works well in practice … behind a 'feature flag' … until we're confident it's a good idea.").

## The problem

For a terminal that can show only ASCII, `PlainTerminalText` (TUIApp) folds each row on its way out. The frame is laid
out by then, so every character keeps the cells it was given: `你好`, four cells, becomes `niha`, ICU's `ni hao` cut to
four. Readable for accents (`Café` → `Cafe`), poor for any other script.

## What was built

The truer mode spells text in ASCII **before** it is measured, so layout makes room: `你好` is `ni hao`, six cells.

- **Where.** `Text.displayString`, the one function the measure, the render and the per-run walk of an interpolated
  `Text` all go through, and where `.textCase` and redaction already apply. Order: transliterate, then case, then
  redact, so `.uppercase` has letters to raise (`NI HAO`) and a placeholder covers the spelled words cell for cell.
- **Controls that draw a string without `Text`**, routed the same way: a button's title (`Button.title(in:)`), a
  table's string and plain-`Text` cells and its headers (`Table.prepared`, `cellValue`, `plainLines`), a panel's,
  sheet's or alert's title in its border (`_ContainerViewCore.spelled(in:)`), and a text field's prompt.
- **The flag.** A value of the existing `TUI_PLAIN_TEXT` rather than a variable of its own: it is the same question
  (what to send a terminal that shows only ASCII), `transliterate` implies `1`, and a second variable would allow
  `TUI_PLAIN_TEXT=0` with the transliteration on, which means nothing. Off unless named; never on by locale. The app
  runner reads it and writes `EnvironmentValues.transliteratesText` (package-only) at the root of every frame, as it
  does the accessibility variables. Headless loops and tests leave it off unless they set it.
- **The transform.** Foundation's `applyingTransform("Any-Latin; Latin-ASCII")`, ICU's rules. What ICU has nothing to
  say about (emoji, box drawing, `✓`) comes back unchanged and is folded at output as before, which stays the safety
  net for chrome and for everything this does not reach.
- **Cost.** About 54 µs a string uncached (measured on this Mac, a 7-character CJK string). A private, bounded memo of
  the pure function (2,048 strings, first in first out; strings over 1 KiB not kept) keyed by the string alone, under the
  CLAUDE.md exemption for memos of pure functions: the transform is fixed and ICU's data does not change in a process.
  ASCII strings return before the memo is looked at.
- **Measured** (2026-11-08, release `Stress --bench`, 120×40, 200 frames, median of 11 interleaved runs, same binary,
  flag off vs on; other lanes were running, so ±5% is noise). With Chinese strings (`LANGUAGE=zh`): `dashboard` +3.5%,
  `textwall` +1.2%, `kitchensink` +1.8%, `table` +21% (8.4 → 10.2 µs a frame: a memo lookup for every string cell of
  every frame, repeated at +24% in a first run of 7). With English strings all four were within noise (−4% to +6%). The
  memo's hits are what's paid: a lock and a string hash a string a frame. Off, the cost is one environment read for
  each `Text` measure and render, not measured against `main`.

## Text being edited

A field's or editor's contents are never transliterated; they are folded at output as before. They are what the person
is editing: the caret, the selection and the mouse count their characters, and the binding holds them as written.
Showing the spelling while unfocused and the original while editing was considered and rejected: the field would change
its contents, and possibly its width, as focus moves through it, which is more surprising than a cut spelling. A
suggestion with no explicit completion completes with its label's own words, not their spelling.

## How well it works

Rendered headless at 60 columns, flag off and on (the folding at output, which a real ASCII terminal also gets, is not
shown):

```
off                          on
中文: 你好，世界 |            zhong wen: ni hao, shi jie |
日本語: こんにちは |           ri ben yu: kon'nichiha |
Русский: Привет, мир |       Russkij: Privet, mir |
Ελληνικά: Γειά σου κόσμε |   Ellenika: Geia sou kosme |
Emoji: 🙂 ok 🎉 |             Emoji: 🙂 ok 🎉 |
▐ Готово ▌ ▐ 取消 ▌           ▐ Gotovo ▌ ▐ qu xiao ▌
```

Good for Cyrillic, Greek and Chinese (pinyin without tones). Weaker elsewhere, as ICU is:

- Japanese kanji are read as Chinese (`日本語` → `ri ben yu`); kana are fine (`kon'nichiha`).
- Arabic and Hebrew lose their vowels and keep a few non-ASCII marks (`العربية` → `alʿrbyt`), which the folding at
  output then turns into ASCII.
- ICU's Cyrillic is ISO 9 folded to ASCII, so `я` is `a` (`Имя` → `Ima`), lossy.

## What is not reached

These still draw their strings without `Text`, so they keep the cut folding at output: tab strip titles and badges,
status bar items and their tooltips, `.help` tooltips, list badges and a list's empty placeholder, drag previews,
the navigation crumb style's titles, and a vertical (`axis: .vertical`) field's prompt. `renderOnce` and
`TUITesting` do not read the flag. Linux is unverified: Foundation routes `applyingTransform` to ICU there too, but no
Linux run was possible here; where it answers `nil`, text stays as written and the output folding applies.
