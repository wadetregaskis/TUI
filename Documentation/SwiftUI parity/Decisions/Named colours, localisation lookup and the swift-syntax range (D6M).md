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

> **Superseded for colours, 2026-10-24:** the owner chose option 3 (a
> process-wide table), and a colour set now chooses its variant where it is
> drawn: see [B-D6M-4](#b-d6m-4-an-asset-catalogue-colour-chooses-its-variant-where-it-is-drawn).
> What follows is the history. An image set's variant is still chosen when the
> `Image` is made.

**Shipped:** as decided, both kinds of asset catalogue are read: the uncompiled
`.xcassets` folder (which is what `swift build` puts in a resource bundle —
measured: `.process("Resources")` copies the folder as it is, and only Xcode
makes an `Assets.car`), on every platform, by TUI; and on macOS a compiled
`Assets.car` too, through AppKit, by `TUIAppKit` (B50's module, since TUI
may not import AppKit). A missing colour is `Color.clear`, which is SwiftUI's
answer (measured: `#00000000`).

**What differs:** the decision said a colour set's light and dark variants are
"chosen by `\.colorScheme`". SwiftUI keeps both in the `Color` and chooses where
the colour is drawn. A TUI `Color` is five bytes with no padding (the A16
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

*The `TUIMacros` product's swift-syntax dependency (A52)*

**Shipped:** `"602.0.0"..<"700.0.0"`. A52 asked for swift-syntax "pinned to the
toolchain's release line", and it first shipped as `"602.0.0"..<"603.0.0"`,
Swift 6.2's line. But every client of TUI resolves that range, macros or
not: SwiftPM builds by target and resolves by package (measured: a client of
the `TUI` product alone clones swift-syntax and compiles none of it). So
the cap refused any app that also depends on a package wanting a newer
swift-syntax — measured: a client with TUI and a package requiring
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
that a TUI-only client never resolves it. That is a release-process cost
(versioning two packages together) for the owner to weigh; nothing in the
code would change.

**A package trait instead (option (c), measured 2026-10-24, lane MISC).** The
owner asked for (c) to be checked and taken if it works. The experiment, on a
shallow clone of the tree tagged as a version and resolved by `file://` URL
as a client resolves a release, changed two things. It added a non-default
trait, `Macros`. It made the plugin's two swift-syntax products conditional
on it, `condition: .when(traits: ["Macros"])`. The results:

- A client of the `TUI` product with no traits listed resolves
  `["tuikit"]`: no swift-syntax in its `Package.resolved`, none in
  `.build/checkouts`.
- A client of `TUIMacros` with `traits: [.defaults, "Macros"]` resolves
  `["swift-syntax", "tuikit"]`. So does every client of the unchanged tree.
- Both held with Xcode's Swift 6.2.4 and swift.org's 6.3.3 and 6.4.0.
- The root package resolves the same way. A plain `swift package resolve`
  rewrote the committed `Package.resolved` without the swift-syntax pin.
  `--enable-all-traits` resolved it again, and
  `swift package --enable-all-traits resolve swift-syntax --version 602.0.0`
  took the 6.2 prebuilt.

So (c) works for clients. Its cost to the repository is a second build
configuration and a `Package.resolved` that differs between them. Its cost to
macro users is a trait to write, and an unpointed error when they forget it.
These were not in its price, so they went back to the owner (Open owner
decisions, follow-up B-D6M-2). The shipped range stands meanwhile.


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
environment's value. `.white`, `.black` and TUI's `.magenta` stay plain RGB,
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


### B-D6M-4. An asset catalogue colour chooses its variant where it is drawn

*`Color.init(_:bundle:)` (uncompiled and compiled catalogues),
`Color(nsColor:)` for a dynamic `NSColor` (the owner's ruling B-D6M-1, option
3, 2026-10-24: "Try (3), then")*

**Shipped:** a colour with a light and a dark value of its own is a new
`ColorValue.lightDark(LightDarkIndex)`: a two-byte place (two `UInt8`s, so
alignment one; a `UInt16` would align `Color` to two and give it a padding
byte) in a process-wide table of (light, dark) RGB pairs,
`LightDarkColorTable.shared` (`Sources/TUIStyling/Color/LightDarkColor.swift`).
`Color` stays five bytes with no padding; the colour's alpha is its own byte, as
for every colour. `Color.resolve(with:)` turns it into the RGB for the palette's
`colorScheme`, beside `.semantic` and `.system`, so it takes the scheme in force
where it is drawn, a `.environment(\.colorScheme, …)` pin included, and in
either direction, also when the colour was made above the pin (which option 4
would have got wrong). Unresolved, as a body measures it (`rgbComponents`,
`estimatedRGB`, a blend, the emitters' and downsamplers' own arms), it is its
light value, as `.system` is and as SwiftUI's `resolve(in:
EnvironmentValues())` is; `resolve(in:)` answers each environment's value.

**The table** is the owner's design: a value-keyed, append-only interner. The
key is the pair of values, not a bundle, a catalogue or a name, so equal pairs
share a place however and wherever they were made (two colours of one pair are
equal), and one table serves every test, bundle and catalogue in the process;
no test can disturb another or need a table of its own. A place never changes
once given. It is behind an `NSLock` (Foundation's, on every platform;
`Mutex` would need macOS 15, and the package's floor is 14): making a colour
takes it once, and so does resolving a `.lightDark` colour, the only colour that
reads the table. **The owner granted this exception to "No Singletons"**
(2026-10-24); it is recorded on the rule in `.claude/CLAUDE.md`, beside the
pure-memo exemption of SINGLETON-CACHES.

**Who makes one:** `Color.lightDark(light:dark:)` (package), which answers the
colour itself where the two values are equal (a set with one colour stays a
plain colour, with no entry), a `.lightDark` colour where both are plain RGB of
one alpha, and `nil` otherwise, for the caller to choose a variant now as it did
before:

- an uncompiled catalogue's colour set, interned once as the set is parsed
  (`AssetCatalog.ColorSet.drawn`);
- `Color(nsColor:)`, which reads the colour under the aqua and the darkAqua
  appearances: a dynamic colour (a compiled catalogue's `NSColor(named:)`,
  `NSColor.systemTeal`, `NSColor(name:dynamicProvider:)`) whose two differ is
  kept as a pair, and a static one is the plain colour it was. The compiled
  catalogue reads through it, so it is chosen where it is drawn too.

**What is still chosen when the colour is made**, by the default palette's
scheme as before (documented on `Color(_:bundle:)`, `Color(nsColor:)` and
deviations C1):

- two variants that differ in alpha: a `Color` carries one alpha, and the
  table keeps RGB only, which keeps an entry at six bytes;
- a variant that is not plain RGB: a reference to a system colour (`.red`
  already follows the scheme by itself) or a palette role (`labelColor` is
  `.primary`), and a `NSColor` that has no sRGB form (a pattern);
- any new pair once the table holds 65,536 (the places two bytes name).
  Nothing is evicted, so a process that makes that many different pairs keeps
  every earlier one exact and chooses for the rest when made. Six bytes a pair
  plus the dictionary that finds it, a few megabytes at the very most.

Display P3 and linear components are converted to 8-bit sRGB as the colour is
read, so they are plain RGB here.

**Never serialised by its place:** no `Codable` or persistence path writes a
`Color` as such. What does save colours (the gradient editor's recents, the
Example's stores) writes `estimatedRGB`, which is the light value; a place means
nothing in another process.

**What changed for an app:** a catalogue colour on a palette of the scheme
other than the default's, or in a pinned subtree, now draws the right variant.
Such a colour no longer equals either variant's RGB and describes itself by
both (`"#CC6633FF light, #1080FFFF dark"`). An image set's variant is still
chosen when the `Image` is made (B-D6M-1).

**The cost:** the common colours pay nothing new: the case is one more arm of
the switches `resolve(with:)` and the emitters already make, as `.system` was.
Resolving a `.lightDark` colour reads `palette.colorScheme` and takes the
table's lock once. An A/B is owed before this lands; no Stress scenario draws a
catalogue colour, so it is a check that nothing else moved.


## Decided

### A14's lookup order — decided 2026-10-05

*`LocalizationService`, `Text(_:tableName:bundle:comment:)`, TUI's own
controls' strings*

The first order (60296e574) read an app's `Localizable` table ahead of
TUI's own strings for every key, so an app that happened to spell
`button.ok` in it changed TUI's OK by accident. The owner accepted the
recommendation, with one rule added: "if there are no built-in TUI
translations for the active language, … automatically try the app's strings.
Better to get some of them, even if imperfect, than none at all."

**Shipped:** both orders go language by language — the languages the user
asked for, including any ahead of the first TUI ships (`LANG=pt_BR`), then
English.

- **TUI's own words** (its controls and the typed `LocalizationKey`s, which
  name TUI through `frameworkString(for:)`): registered strings, a
  `TUI.strings` table the app ships, TUI's translation, and — only where
  TUI has no translation of the key in that language — the app's
  `Localizable`, before English.
- **The app's keys:** the table the call names, registered strings,
  `Localizable`, then TUI's strings (so an app can borrow them). This is a
  deviation from SwiftUI where the call names a table (or a bundle) that lacks
  the key: SwiftUI's `Text("greeting", tableName: "Onboarding")` shows
  `greeting`, and TUI goes on to the rest of the order. Kept as the owner's
  order; the compatibility doc marks it.
- Writing out the default table (`tableName: "Localizable"`, `bundle: .main`)
  reads exactly as leaving it off.
