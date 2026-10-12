# Completing the SwiftUI API: lane SHIP2's decisions for review

*A companion to [`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
written by the lane that shipped the owner's decisions of 2026-10-12 on size and
products: TUIkit's symbols out of the app's export table, the gradient editor
back in TUIkitColorPicker, the `-deduplicate` check on the 6.2.4 lane, and the
tests' temporary directories. It holds only what that work raised that was not
already decided, in the main file's three parts.*

- **A. Needs your decision.** Nothing has shipped for these.
- **B. Shipped the safe option.** A basic, honest form is in; each entry says
  what the fuller version would be, and what it would cost.
- **C. Declined without asking.** Listed so they can be vetoed.

## B. Shipped the safe option

### B-SHIP2-1. `-unexported_symbol` is a trait of its own, `UnexportTUIkitSymbols`, beside `DeadStripUnusedAPI`

*`Package.swift` (the "App size" section), `README.md` ("Shipping size")*

**Asked:** the unexport patterns gated on the same `DeadStripUnusedAPI` trait,
so that `traits: []` turns both off, unless there was a reason for a trait of
their own.

**Found:** ld refuses `-unexported_symbol` beside any export list. A link
that also passes `-no_exported_symbols`, `-exported_symbol` or
`-exported_symbols_list` stops with "-unexported_symbol cannot be used with
-exported_symbol*" (or "-no_exported_symbols cannot be used with
-[un]exported_symbol*", by flag order): measured 2026-10-12 with Xcode 26.3's
ld-1230, and `-ld_classic` says the same, on a one-function program and on the
hello world relinked from both toolchains' builds. Xcode's
`LD_EXPORT_SYMBOLS = NO` and `EXPORTED_SYMBOLS_FILE` pass those flags (untried
in Xcode). So a developer whose own link needs an export list (a plugin host,
a dynamic library with a curated interface, or the README's own
`-no_exported_symbols` until now) cannot build with the default traits at all.

**Shipped:** a second default trait, `UnexportTUIkitSymbols`. `traits: []`
still turns both off; such a developer writes `traits:
["DeadStripUnusedAPI"]` and keeps the −14.7% of the dead stripping, which with
one trait they would have had to give up to make their link work at all. The
README's `-no_exported_symbols` lever is gone with it: the trait takes 97% of
what that flag saved (the hello world's export table 317 KB → 9 KB), and the
rest goes with `-Xlinker -unexported_symbol -Xlinker '*'`, which ld takes
beside the patterns (9 KB, −0.1%). `Tools/DedupCheck/ci-check.sh` follows the
README and links with `-deduplicate` alone.

**The other version, and its price:** one trait, as asked. One name fewer in
the docs; but the export-list developer's only way to a working link would be
`traits: []`, and the dead stripping with it.
