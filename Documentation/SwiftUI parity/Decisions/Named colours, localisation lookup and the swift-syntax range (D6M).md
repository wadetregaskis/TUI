# Completing the SwiftUI API: lane D6M's decisions for review

*A companion to [`SwiftUI API completion decisions.md`](<SwiftUI API completion decisions.md>),
written by the lane that implemented the owner's answers to A5, A14, A15, A16
(HDR), A32, A35, A52, B36, B37 and B4 (2026-10-05). It holds only what that work
raised that was not already decided: the same three parts as the main file.*

- **A. Needs your decision.** Nothing has shipped for these.
- **B. Shipped the safe option.** A basic, honest form is in; each entry says
  what the fuller version would be, and what it would cost.
- **C. Declined without asking.** Recorded in `parity-map.json`, listed so they
  can be vetoed.

## B. Shipped the safe option

### B-D6M-1. A named colour's light and dark variants are chosen when it is made

*`Color.init(_:bundle:)`, and the dark variants of an image set
(`Image.init(_:bundle:)` and its two siblings) (A15)*

**Shipped:** as decided, both kinds of asset catalogue are read: the uncompiled
`.xcassets` folder (which is what `swift build` puts in a resource bundle —
measured: `.process("Resources")` copies the folder as it is, and only Xcode
makes an `Assets.car`), on every platform, by TUIkit; and on macOS a compiled
`Assets.car` too, through AppKit, by `TUIkitAppKit` (B50's module, since TUIkit
may not import AppKit). A missing colour is `Color.clear`, which is SwiftUI's
answer (measured: `#00000000`).

**What differs:** the decision said a colour set's light and dark variants are
"chosen by `\.colorScheme`". SwiftUI keeps both in the `Color` and chooses where
the colour is drawn. A TUIkit `Color` is five bytes with no padding (the A16
analysis: every `Text` carries two, every cell run carries them, the value hash
reads them as words), with no room for a second colour or a reference to the
set. So the variant is chosen when the colour is made, by the colour scheme a
view reads where nothing has set a palette (`EnvironmentValues().colorScheme`,
the default palette's) — the same environment `NSColor(_:)` already resolves a
palette role against. An app whose root palette is of the other scheme, a
subtree under such a `.palette(_:)`, or an `.environment(\.colorScheme, …)` pin
gets the default palette's variant. A set with one colour (the common case) is
exact everywhere.

**The fuller version** chooses where the colour is drawn: a `ColorValue` case
holding an index into an app-scoped table of the catalogue's colours, resolved
beside `.semantic` with the palette's scheme. It fits in the five bytes (the
payload is two bytes, under `.rgb`'s three), but it is the custom-colour-provider
mechanism of A16 in a narrower form: a table that has to live somewhere a
`Color` made in a `body` can reach without an environment (which is a
process-wide registry, or a singleton by another name), and twenty-six switches
over `ColorValue` to teach, several on the hot path. About a day, plus the
benchmark A16 already asks for — so it belongs with the A16 provider decision,
and should be built with it if that goes ahead.

### B-D6M-2. swift-syntax is taken from 602.0.0 up to the next major, not pinned to 602

*The `TUIkitMacros` product's swift-syntax dependency (A52)*

**Shipped:** `"602.0.0"..<"700.0.0"`. A52 asked for swift-syntax "pinned to the
toolchain's release line", and it first shipped as `"602.0.0"..<"603.0.0"`,
Swift 6.2's line. But every client of TUIkit resolves that range, macros or
not: SwiftPM builds by target and resolves by package (measured: a client of
the `TUIkit` product alone clones swift-syntax and compiles none of it). So
the cap refused any app that also depends on a package wanting a newer
swift-syntax — measured: a client with TUIkit and a package requiring
`from: "603.0.0"` failed `swift package resolve` with a conflict, and
resolves with the wide range. Swift 6.3's 603 and 6.4's 604 are out, so that
is any app with a current macro package in it. The wide range is what macro
packages commonly declare.

**The price:** prebuilts. SwiftPM resolves the newest in range (604.0.0 today)
and takes swift-syntax prebuilt only where one is published for that version
and the toolchain: measured on download.swift.org, only 602.0.0 for Swift
6.2.x (Linux and Windows; none for macOS, none for 603 or 604 under any
toolchain). So an app on Swift 6.2 that uses the macros now compiles
swift-syntax once, unless it pins `exact: "602.0.0"` itself, which the
Package.swift comment says. Checked that the plugin builds and expands
against 604.0.0 with Swift 6.2.4 (zero warnings; a probe using `@Animatable`
reads and writes its data correctly). CI's Linux 6.2 lane pins 602.0.0
(`swift package resolve swift-syntax --version 602.0.0`), which keeps it on
the prebuilt and tests the range's floor; every other lane tests its top.

**The fuller version** keeps a client off swift-syntax entirely: the macros in
a package of their own, in a second repository (SwiftPM cannot take a package from a subfolder of a remote one), so
that a TUIkit-only client never resolves it. That is a release-process cost
(versioning two packages together) for the owner to weigh; nothing in the
code would change.


### B-D6M-3. SwiftUI's named colours take their dark values where they are drawn

*`Color.red`, `.orange`, `.yellow`, `.green`, `.mint`, `.teal`, `.cyan`,
`.blue`, `.indigo`, `.purple`, `.pink`, `.brown`, `.gray`
(owner's ruling NAMED-COLOURS-DARK, option a, 2026-10-23)*

**Shipped:** each is a `ColorValue.system(SystemColor)`, a one-byte payload
under `.rgb`'s three, so a `Color` is still five bytes with no padding. Its
light and dark values are a constant table (`SystemColor.swift`, a switch per
scheme), not a registry. `Color.resolve(with:)` turns it into the RGB for the
palette's `colorScheme`, beside `.semantic`, and that is the one place it is
resolved: every path that draws a colour already resolves it there, so the
scheme is the one in force where the colour is drawn, a
`.environment(\.colorScheme, …)` pin included (a pin is stated on the
palette). Unresolved, it measures and spells as its light value
(`rgbComponents`, every blend, the emitters' own arm for it), which is what
SwiftUI's `resolve(in: EnvironmentValues())` answers; such arithmetic returns a
plain colour, which no longer follows the scheme. `resolve(in:)` answers each
environment's value. `.white`, `.black` and TUIkit's `.magenta` stay plain RGB,
the same in both schemes.

**Measured:** the dark values are SwiftUI's, `Color.resolve(in:)` under a dark
`EnvironmentValues` on macOS 15.8.1, and agree with `NSColor.systemRed` and
friends under darkAqua
(`Tools/SwiftUIProbes/Named colours by scheme/namedcolours.swift` and its
`.out`). A bare environment answers the light values there, as the 09-15
decision said.

**What changed for an app:** on a dark palette, which most are, `.red` draws
`#FF453A` where it drew `#FF3B30`. A name no longer equals the RGB it was, and
describes itself by name (`"red"`), as SwiftUI's does. A palette whose page is a
named colour is measured at the name's light value to decide its scheme;
resolving the page by the scheme would ask the scheme. A style given to
`.foregroundStyle(_:)` or `.background(_:)` is resolved where the modifier is
applied, as a palette role is, so a pin below the modifier does not reach it;
`Text`'s own `foregroundStyle(_:)` resolves at the text.

**The cost:** resolving a named colour reads `palette.colorScheme`, which a
palette that does not state one computes from its page (two contrast ratios).
Only named colours pay it, once per resolve; every other colour pays a tag test
it already paid for `.semantic`. An A/B on pages that draw many named colours is
owed before this lands.


## Decided

### A14's lookup order — decided 2026-10-05

*`LocalizationService`, `Text(_:tableName:bundle:comment:)`, TUIkit's own
controls' strings*

The first order (60296e574) read an app's `Localizable` table ahead of
TUIkit's own strings for every key, so an app that happened to spell
`button.ok` in it changed TUIkit's OK by accident. The owner accepted the
recommendation, with one rule added: "if there are no built-in TUIkit
translations for the active language, … automatically try the app's strings.
Better to get some of them, even if imperfect, than none at all."

**Shipped:** both orders go language by language — the languages the user
asked for, including any ahead of the first TUIkit ships (`LANG=pt_BR`), then
English.

- **TUIkit's own words** (its controls and the typed `LocalizationKey`s, which
  name TUIkit through `frameworkString(for:)`): registered strings, a
  `TUIkit.strings` table the app ships, TUIkit's translation, and — only where
  TUIkit has no translation of the key in that language — the app's
  `Localizable`, before English.
- **The app's keys:** the table the call names, registered strings,
  `Localizable`, then TUIkit's strings (so an app can borrow them). This is a
  deviation from SwiftUI where the call names a table (or a bundle) that lacks
  the key: SwiftUI's `Text("greeting", tableName: "Onboarding")` shows
  `greeting`, and TUIkit goes on to the rest of the order. Kept as the owner's
  order; the compatibility doc marks it.
- Writing out the default table (`tableName: "Localizable"`, `bundle: .main`)
  reads exactly as leaving it off.
