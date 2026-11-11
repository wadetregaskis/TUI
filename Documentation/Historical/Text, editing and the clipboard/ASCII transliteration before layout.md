# ASCII transliteration before layout

An experiment behind a flag, `TUI_PLAIN_TEXT=transliterate` (owner, 2026-11-08: "Build. At least try it, and let's see
if it works well in practice … behind a 'feature flag' … until we're confident it's a good idea."). Round 2, the same
day: "Keep working on the improved ASCII-only mode; try to remove the limitations and fix the flaws."

## The problem

For a terminal that can show only ASCII, `PlainTerminalText` (TUIApp) folds each row on its way out. The frame is laid
out by then, so every character keeps the cells it was given: `你好`, four cells, becomes `niha`, ICU's `ni hao` cut to
four. Readable for accents (`Café` → `Cafe`), poor for any other script.

## What was built

The truer mode spells text in ASCII **before** it is measured, so layout makes room: `你好` is `ni hao`, six cells.

- **Where.** `Text.displayString`, the one function the measure, the render and the per-run walk of an interpolated
  `Text` all go through, and where `.textCase` and redaction already apply. Order: spell, then case, then redact, so
  `.uppercase` has letters to raise (`NI HAO`) and a placeholder covers the spelled words cell for cell.
- **Strings drawn without a `Text`** go through one entry point, `RenderContext.spelled(_:)`, called once where the
  string is first read in a measure or a render so the width it is measured at is the width it is drawn at: a button's
  title, a table's string and plain-`Text` cells and headers, a panel's, sheet's or alert's border title, a field's
  prompt (on one line and vertical), a tab strip's titles and badges (spelled once before the strip's first measure),
  a tab's drag preview, a list's empty placeholder, title width and row badges, status bar items, the status bar's
  tooltip and copy note, `.help` tooltips, the navigation bar's title and crumbs (and the trail's own `…` and `›`,
  measured to choose the trail), a spinner's label, an image's placeholder and error, a stepper's read-out and the
  width its bounds reserve, the graphical date picker's month and weekdays, a file panel's path segments, a menu row's
  key hint and the shortcut list's key column. Menus, alerts, toasts, pickers, toolbars, the shortcut overlay, the quit
  prompt and file-panel cells draw through `Text` and were already spelled.
- **The flag.** A value of the existing `TUI_PLAIN_TEXT` rather than a variable of its own: it is the same question
  (what to send a terminal that shows only ASCII), `transliterate` implies `1`, and a second variable would allow
  `TUI_PLAIN_TEXT=0` with the transliteration on, which means nothing. Off unless named; never on by locale. The app
  runner, `HeadlessApp` (so `TestApp`), `renderOnce`/`renderOnceToString` and the Stress harness all read it and write
  `EnvironmentValues.textSpelling` at the root (package-only), read as the root locale's language reads its script. A
  framework test asks for it with `headless.configureEnvironment { $0.spellTextInASCII() }` or by setting
  `textSpelling` on its context.
- **Carried by the context, not read from the environment.** `RenderContext.textSpelling` is seeded from the
  environment when a context is made from one and carried by every copy, so a `Text` asks it with a byte load. Round 1
  read an environment value per `Text` measure and render; with the flag **off**, that measured +1.5% to +2.6% in ten
  of 25 `Stress --bench` scenarios against the commit before it (fanout +2.1%, textwall +1.8%, dashboard +2.4%, grids
  +2.6%, geometry +2.6%, modifiers +1.6%, anyview +1.5%, texteffects +1.0%, tables-scroll +2.3%; CIs excluding 0). The
  byte is the one `hasExplicitWidth` and `hasExplicitHeight` gave up when they became two bits of one `UInt8`: the
  context's 104-byte stride is load-bearing and had no byte spare. The A/B after the change is in the commit message.

## How each script is spelled

1. **Emoji** become short ASCII, without ICU (the standard library carries Unicode names): an emoticon where a
   well-known one exists (`🙂` `:)`, `😂` `:'D`, `❤️` `<3`, `👍` `:+1:`), a shorter name for a few common ones whose
   Unicode name is long or misleading (`🎉` `:tada:`, `✅` `:check:`), and otherwise the Unicode name between colons,
   lowercased with `_` for spaces and without a trailing "sign" (`🚀` `:rocket:`, `🦋` `:butterfly:`). A flag is its
   region code (`🇯🇵` `[JP]`), a keycap its key (`1️⃣` `[1]`); skin tones and the presentation selector are dropped; a
   zero-width-joined sequence names each part (`:man_woman_girl:`). Width: an emoticon is 2–4 cells where the emoji
   took 2; a name is its length plus two, `:butterfly:` 11. CLDR's short names would read slightly better (`red heart`
   for `HEAVY BLACK HEART`) but are not in any API Foundation or the standard library exposes; the table covers the
   common cases where the two differ. `©` and `™`, text by default, are left to `Latin-ASCII` (`(C)`, `TM`).
2. **Japanese** is read as Japanese, on Darwin, where the string has kana in it or the app's language is Japanese:
   `CFStringTokenizer` in its Japanese locale gives each word's Latin transcription and knows kanji readings. Words are
   joined with spaces, as romaji is written. A Han-only string in an app in any other language is read as Chinese:
   nothing in the characters says which it is (`保存` is `hozon` to one reader and `bao cun` to the other). The
   tokenizer in a neutral locale guesses per word, and guessed shared words like `保存` and `学生` as Japanese, which
   a Chinese reader would find wrong, so it is not used that way. Linux has no tokenizer: Japanese goes to ICU, whose
   kana are right and whose kanji are read as Chinese.
3. **Cyrillic** by BGN/PCGN, the romanization that reads as the words sound, rather than ISO 9, which `Any-Latin`
   applies and which folded to ASCII loses letters (`я` was `a`). The language's own where the app's language writes
   Cyrillic another way: Ukrainian, Belarusian, Bulgarian, Macedonian and Serbian have their BGN tables; every other
   app, Russian's. BGN's soft and hard sign marks (`ʹ`, `ʺ`) are dropped, as the simplified form people type does.
4. **Greek** by UNGEGN (ELOT 743), the modern-pronunciation romanization (`Αθήνα` `Athina`), rather than `Any-Latin`'s
   classical one (`Athena`). ICU's `Greek-Latin/UNGEGN` marks every `:` with a combining macron below whatever the
   script, so it is filtered to Greek letters (`[:Greek:]Greek-Latin/UNGEGN`; note the filter has no space after it,
   since a filter and a space before the first element of a chain filter the whole chain).
5. **Korean** is ICU's `Hangul-Latin`, which is the Revised Romanization's transliteration rules (§8): letter for
   letter, with a hyphen where a syllable starts with a silent `ㅇ` after a consonant (`한국어` `hangug-eo`), correct
   where it matters most (`서울` `seoul`, `중앙` `jung-ang`, `안녕하세요` `annyeonghaseyo`). The transcription used on
   signs (`hangugeo`, `hanguk`) applies sound changes across syllables, which ICU doesn't have.
6. **Arabic and Hebrew** are written without their short vowels, so no rule-based transliteration can supply them:
   `العربية` is `al'rbyt`, not `al-ʿarabiyya`. ICU's `Arabic-Latin` is the standard scholarly transliteration, letter for
   letter; its `ʿ` and `ʾ` (ʿayin, hamza), which `Latin-ASCII` keeps, become `'` as ASCII romanizations write them.
   Supplying the vowels needs a dictionary or a model per language, which nothing on either platform offers, so it is
   left there. ICU's BGN tables for both are incomplete (they leave letters unspelled) and are not used.
7. **Everything else** is `Any-Latin; Latin-ASCII`: Chinese as pinyin without tones, Devanagari, Thai (ISO 11940, so
   `ไทย` is `thiy`), and Latin's accents and punctuation (`…` `...`, `→` `->`, curly quotes straight).

What none of these knows (box drawing, `✓`) comes back as it was and is folded at output, which stays the safety net.

## Cost

Uncached, a string costs about 20–50 µs through ICU and about 160 µs through the Japanese tokenizer. A private,
bounded memo of the pure function (2,048 entries, first in first out; strings over 1 KiB not kept), keyed by the string
and its reading, under the CLAUDE.md exemption for memos of pure functions: the transforms are fixed, and ICU's data
and the tokenizer's don't change in a process. ASCII strings return before the memo is looked at.

With the flag **on** (2026-11-08, release `Stress --bench`, one binary off and on, 11 interleaved pairs, `LANGUAGE=zh`):
`table` +7%, `dashboard` +8%, `textwall` +3%. Round 1 had measured `table` +21% by medians of separate runs; paired
the same way as here, round 1's binary is +6%, so round 2's routing and readings cost nothing measurable on top (and
the A/B of the two with the flag on found `table`, `dashboard` and `tables-scroll` indistinguishable, `textwall` and
`kitchensink` 1–3% faster). What is left is a memo hit per string per measure and render (a lock and a string hash,
which normalises non-ASCII text: about 150 ns, measured in isolation) and the spelled words themselves, which are
wider (`bei jing` for `北京`) and so take more cells to lay out and draw. A direct-mapped front for the memo, keyed by a
cheap hash of the first bytes, made a lookup about three times faster in isolation and moved none of these numbers,
so it was not kept. Caching the spelling in `Text`'s own measure memo would need a slot per `Text`, which the memo
doesn't have.

## Text being edited

A field's or editor's contents are never transliterated; they are folded at output as before. They are what the person
is editing: the caret, the selection and the mouse count their characters, and the binding holds them as written.
Showing the spelling while unfocused and the original while editing was considered and rejected: the field would change
its contents, and possibly its width, as focus moves through it, which is more surprising than a cut spelling. A
suggestion with no explicit completion completes with its label's own words, not their spelling.

## How well it works

Round 1 and round 2, rendered headless (the folding at output, which a real ASCII terminal also gets, is not shown):

```
as written                 round 1                     round 2
中文: 你好，世界            zhong wen: ni hao, shi jie  zhong wen: ni hao, shi jie
日本語: こんにちは          ri ben yu: kon'nichiha      nippon go: kon'nichiha
東京へ行きます              dong jinghe xingkimasu      toukyou he iki masu
Имя, Щука, Юрий            Ima, Suka, Urij             Imya, Shchuka, Yuriy
Київ (Ukrainian app)       Kiiv                        Kyyiv
Ελληνικά, Αθήνα            Ellenika, Athena            Ellinika, Athina
한국어, 서울                hangug-eo, seoul            hangug-eo, seoul
العربية                    alʿrbyt                     al'rbyt
Emoji: 🙂 ok 🎉 👍          Emoji: 🙂 ok 🎉 👍           Emoji: :) ok :tada: :+1:
```

## The framework's own glyphs (2026-11-10)

The owner tried the experiment by hand on 2026-11-10 and found the framework's own glyphs the weak part: SF Symbols
vanished, toggles showed no state (`■` and `□` both folded to `#`, `⬛︎` and `⬜︎` to nothing), a toggle in a menu read
`:white_large_square:`, radio buttons marked only the selected option (`◯` folded to a blank), half the spinners stood
still or showed nothing, a file panel's icons were names of different widths (`:file_folder:`, `:memo:`), and most of
the Example's bracket pairs were blank. The cause was one thing: those glyphs went through the paths meant for an
app's words — the emoji spelling before layout, or the folding at output, cell for cell — and neither has room for a
deliberate ASCII form. What was built, so each has one:

- **One table** of the framework's shapes in ASCII, `TerminalSymbols.ASCII` (TUICore), beside the glyphs themselves.
  The folding at output reads it (it was `PlainTerminalText`'s private table), and so does the transliteration's new
  last step (`GlyphSpelling`), so a `▶` is `>` in a `Text` and in a stepper alike. Added to it: a control's half-block
  ends, `▐ ▌`, as `[ ]` (fields, rounded buttons, pickers and compact tabs were walled in `#`); bracket pairs as their
  ASCII counterparts (`⌜⌟` `[]`, `❨❩` `()`, `⟨⟩` `<>`, `⟦⟧` `[]`); the thin edge blocks `▏▕` as `|`; `◯` and `◌` as
  `o`; the light and medium shades as `.` and `:`, so a `░` track under a `█` fill reads `#####.....`.
- **Wider forms chosen where the glyph is drawn**, at the point that already chooses it, read when the context spells
  text in ASCII (`TextSpelling.isASCII`):
  - a toggle's marks: `effectiveToggleCharacterSet` answers `.ascii`, `[x]` and `[ ]`, for any set whose marks are not
    ASCII, so the menu row's mark too. A set that is ASCII already is the app's and is kept.
  - a radio button: `(*)` selected (or focused, as `●` is), `( )` otherwise, disabled included: the dotted `◌` has no
    ASCII shape that would not read as a mark, and a disabled option is dimmed as its label is. Parentheses because
    they say "one of these" as `[ ]` says "any of these", and the star says which without colour, which answers the
    owner's question 19.8 without a second luminosity.
  - a spinner: `SpinnerStyle.asciiFrames`, one cell each, after each style's shape: the Braille `dots` a dot growing
    and shrinking (`. o O o`), the circles and the square a line turning (`| / - \`), the bracket's corners as the
    slashes that slope like them, `column` and `bar` filling through `_ - = #`, `shade` through ` . + #`,
    `blockWedge` as `L F 7 J`, the moon by its lit side (`O C ( . ) D`), the clock by its hour hand. `bouncing` draws
    its track as `.`, the highlight `O` and the trail `o`, where every cell was `●` set apart only by colour. A
    `custom` sequence is the app's text and is spelled as its words are.
  - a file panel: a letter in a column of its own, as a long listing writes the type: `d` a folder, `l` an alias, `f`
    anything else, whose differences the extension already tells (`FilePanelIcon.letters`).
- **No emoji chrome** where text is spelled in ASCII: `spellTextInASCII()` and `spellKeysInASCII()` turn
  `supportsEmojiChrome` off, so a control that draws an emoji only where the terminal shows them legibly draws what it
  draws elsewhere. The search field's magnifier was `:right_pointing_magnifying_glass:`; it is now no icon, as on a
  terminal without emoji chrome.
- **SF Symbols as their names**, `:star:` for `star.fill`: the transliteration's last step looks a Private Use glyph up
  in the name table (`SFSymbol.name(ofGlyph:)`, a walk of the packed codepoints, memoized with the words around it)
  and writes it between colons, as an emoji's name is: one convention for a picture named in words, whether the app
  used an emoji or a symbol. Without `fill`, which says how it is drawn, as an emoji's skin tone and selector are
  dropped; the rest of the name as Apple wrote it, dots and all, so it can be looked up. Only where the table is
  (Apple platforms), and only where the symbol would have been drawn (the SF Symbols font installed): where it would
  not, `Label` shows its title alone and a bare `Image` nothing, as without the flag.
- **Emoji that are text by default** (`❤`, `☺`, `☝` with no selector) are spelled at the transliteration's end, after
  `Latin-ASCII` has had `©` and `™`; they folded to blanks. A text base with a skin tone (`☝🏽`) is an emoji, and
  spelled with the others.

**Which mode.** Everything but the SF Symbols' names and the emoji applies wherever the terminal is sent plain text
(`TUI_PLAIN_TEXT=1`, or a locale naming a character set other than UTF-8), not only under `transliterate`: the
folding left the same toggles and radio buttons stateless there, and the owner's KEY-SPELL ruling had already taken a
changed layout over blank glyphs for that mode. Names are words, and words are spelled only under `transliterate`.

**Cost.** The Example's release binary (`swift build -c release`, Xcode 26.3's Swift 6.2.4, then `strip`) grew by
33,056 bytes, 18,600,864 to 18,633,920 (+0.18%); unstripped by 38,688. What it holds: one table of a few dozen
entries, each spinner style's ASCII frames, and a reverse lookup over the SF Symbols table already in the binary.
With the flag off, the one addition on a hot path is `effectiveToggleCharacterSet`'s read of `textSpelling`, an
environment lookup per toggle drawn.

## Limits left

- Han-only Japanese in an app whose language isn't Japanese is read as Chinese (see above), and a subtree's own
  `.environment(\.locale, _)` doesn't change the reading: it is the root's, carried by the context.
- Japanese romaji follows the tokenizer: `nippon` for `日本`, long vowels as `ou`/`uu`, particles as written (`he`, `ha`).
- Arabic and Hebrew stay without vowels; Thai is a transliteration, not the RTGS transcription Thais use.
- Linux: `applyingTransform` is ICU there too, through swift-corelibs-foundation, and the static-Linux build compiles;
  no Linux run was possible here. Where the transforms answer `nil`, text keeps what the steps before them made of it
  (the emoji are spelled; the rest is folded at output). Japanese uses ICU there, as above.
