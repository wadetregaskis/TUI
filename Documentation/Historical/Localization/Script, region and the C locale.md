# Script, region and the C locale

*Which variant of a language a key is read in, and what the neutral `C`
locale asks for. Ids: HUNT-TOOLS-10, HUNT-FENV-16, HUNT-O-06 (findings
FENV-5, TOOLS-10), HUNT-O-07 (findings XPLAT-4, TOOLS-11): hunt 1120, item
H-54; the owner's rulings of 2026-11-21.*

## In short

A language is told apart by its script and region: a key is read under the
full tag first (`pt-BR`, `zh-Hant-TW`) and then the bare one (`pt`,
`zh-Hant`), everywhere a key is looked up (O-06 (a), 2026-11-21). TUI's
Chinese is Simplified, so a reader of Traditional Chinese is not given it.
`Text(localized:)` reads its key when drawn, so it follows a subtree's
`\.locale`.

## The record

### HUNT-TOOLS-10. A Traditional Chinese reader is not given TUI's Simplified table

*`LanguageTag`, `LocalizationService+Detection.swift`, `TimeSpanLanguage`*

**Before:** a locale name was read as its language code alone, so `zh_TW`
and `zh-Hant-TW` were `zh`, which is `.simplifiedChinese`, and every one of
TUI's words was Simplified for a reader of Traditional, beside English years
and months (`TimeSpanLanguage` already ruled the other way).

**Shipped:** a language is its code with its script where that is not the
language's own, by Foundation's likely subtags: `zh_TW` and `zh_HK` are
`zh-Hant`, `zh-Hans-TW` is `zh`. `zh-Hant` is a language TUI ships none of,
so the walk goes on to the user's next language, and the app's own
`zh-Hant` strings and `zh-Hant.lproj` are read first. One predicate,
`Language(reading:)`, decides both the words and the time spans.

### HUNT-FENV-16. `Text(localized:)` with a string reads its key when drawn

*`Text(localized:)` (`LocalizationExtensions.swift`)*

**Before:** it resolved the key when the `Text` was made and kept the words,
so a subtree's `\.locale` did not change them, where `Text("key")` and
`LocalizedString("key")` follow it.

**SwiftUI:** has no `Text(localized:)`; its nearest, `Text(_:)` of a
`LocalizedStringResource`, follows `\.locale` (`de` reads `Hallo`) and draws
the string's Markdown, where `Text(String(localized:))` does neither
(measured 2026-11-23, macOS 15;
`Tools/SwiftUIProbes/Small parity items (PARITYMISC)/locale-scripts/`).

**Shipped:** it is the key's `Text`, so it is read again under a subtree's
`\.locale` and its Markdown is drawn, as SwiftUI's resource is.

### HUNT-O-06. Script and region variants are told apart, everywhere

*Owner, 2026-11-21: (a). Findings FENV-5 (and TOOLS-10).*

**The question:** should TUI tell `zh-Hans` from `zh-Hant` and `pt-BR` from
`pt-PT` at all, given that its own strings come in one Chinese? (a) yes, full
tag first and then the bare code, everywhere; (b) no, the bare language code,
as before.

**SwiftUI (measured 2026-11-23, macOS 15, an app with `en`, `de`, `zh-Hans`,
`zh-Hant`, `pt`, `pt-BR` and `pt-PT` tables):** a subtree's `\.locale` picks
the script's and the region's table: `zh-Hant`, `zh_TW`, `zh_HK` read
`zh-Hant`; `zh`, `zh_CN`, `zh-Hans-SG` read `zh-Hans`; `pt-BR` and `pt_PT`
their own; `pt` the bare `pt`; `pt_AO` and `pt_MZ` `pt-PT` (CLDR's parent).
It reads one table only, so a key `pt-BR` lacks shows the key (E4 again).

**Shipped:** a key is read under each language's full tag and then its bare
one: the service's languages from the environment (`LANG=pt_BR.UTF-8` reads
`pt-BR`, `pt`, then `en`), a subtree's `\.locale` (which now carries its
script and region, so a subtree reads no better than the root), the
translations an app registers (keyed by any spelling, `zh_TW` or
`zh-Hant-TW`) and its `.lproj` folders. The bare tag keeps a script that is
not the language's own: Traditional Chinese falls back to `zh-Hant`, never to
`zh`, which is Simplified, as Foundation's own matching gives `zh-Hant` no
`zh.lproj`. Off Darwin a region with a parent of its own other than the bare
language (`pt_AO`'s `pt-PT`) reads the bare `pt`; on Darwin Foundation's
matching finds `pt-PT`.
