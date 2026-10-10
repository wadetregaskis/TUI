# Completing the SwiftUI API: lane BNDL's decisions for review

*A companion to [`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
written by the lane that made a TUIkit program run without its resource bundle
(2026-10-10): the binary-size follow-ups found that every TUIkit app stopped at
launch (`Fatal error: unable to find bundle named TUIkit_TUIkitStrings`) when
`TUIkit_TUIkitStrings.bundle` was not beside the binary. It holds only what
that work raised that was not already decided: the same three parts as the
main file.*

- **A. Needs your decision.** Nothing has shipped for these.
- **B. Shipped the safe option.** A basic, honest form is in; each entry says
  what the fuller version would be, and what it would cost.
- **C. Declined without asking.** Listed so they can be vetoed.

## B. Shipped the safe option

### B-BNDL-1. TUIkit's English is compiled in as well as bundled

*`LocalizationService`, `LocalizationService+BuiltInEnglish.swift`*

**Shipped:** a copy of `en.json`, as the file's text in a raw string literal,
parsed by the same parser the bundled files go through, and only where `en.json`
cannot be read. Without it a program shipped without the bundle would not run
"in English": TUIkit's words would read as their keys (`statusbar.quit`), the
quiet failure the first WebAssembly build showed. `BuiltInEnglishTests` fails,
naming the keys, until the copy matches the file, and the localization article's
"Adding New Keys" says to paste it.

**Price, measured** (`swiftc -O -c`, Xcode's 6.2.4, 2026-10-10): the string is
5,462 bytes of `__cstring`. A `[String: String]` literal of the same 144 pairs
measured 8,125 bytes (4,640 of 32-byte entries in `__DATA,__const`, 3,409 of
its longer strings), so the text is the smaller form as well as the one that
can be pasted. A program with the bundle carries the 5.5 KB unused.

**Fuller version:** one English. The compiled-in table becomes the only English
and `en.json` leaves the bundle (5.5 KB less in it), or a generator writes the Swift file from `en.json` so there is nothing to
paste. Either changes how a translator adds a key, so it is yours to choose.
