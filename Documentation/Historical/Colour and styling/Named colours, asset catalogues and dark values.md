# Named colours, asset catalogues and dark values

*How `Color.red` and its kind, and a colour from an asset catalogue, choose
their light or dark value, and the colours that resolve themselves. Ids: A16,
B-D6M-1, B-D6M-3, B-D6M-4, NAMED-COLOURS-DARK, B-D6M-1's interner grant.*

## In short

SwiftUI's named colours take Apple's dark values under a dark colour scheme,
resolved where they are drawn (NAMED-COLOURS-DARK, reversing the 09-15 "light
values for now"). An asset catalogue's colour chooses its variant where it is
drawn, through `LightDarkColorTable.shared`, a value-keyed append-only
interner the owner granted as an exception to the no-singletons rule
(2026-10-24). The HDR half of A16 shipped; a custom colour provider waits on
its benchmark.

## The record

### A16. Colours that resolve themselves, and HDR

**2026-10-05: the HDR half shipped** (`Color.headroom(_:)`; `ResolvedHDR`,
`resolveHDR(in:)` and `exposureAdjust(_:)` declined in the parity map). What is
left is the custom colour provider, which waits on its benchmark.

*`Color.init(_:)` for a `ShapeStyle & Hashable` whose `Resolved` is
`Color.Resolved` or `Color.ResolvedHDR`; `Color.ResolvedHDR` and its
members; `Color.resolveHDR(in:)`, `Color.headroom(_:)`,
`Color.exposureAdjust(_:)`*

`Color.Resolved`, `resolve(in:)` and the component initialisers have
shipped. Two things remain.

- **A custom colour provider.** SwiftUI's `Color(MyStyle())` defers to the
  style at every resolve. TUI's `Color` is five bytes with no padding:
  every `Text` carries two, every cell's run carries them, and the value
  hash reads them as plain words. A provider case would hold an existential
  (40 bytes), growing every one of those, or an index into a registry, which
  is a singleton. Resolving the provider once at `init` against a default
  environment would be the quiet lie the parity rules forbid.
- **HDR.** A terminal is SDR, so a headroom cap is always met
  (`headroom(_:)` would return the colour unchanged, honestly), and
  `ResolvedHDR` is a value type that could ship as data.
  `exposureAdjust(_:)` brightens by stops, though, and a palette role or a
  terminal slot has no numbers until it is painted, so it cannot be applied
  at `init`.

**Options.** (a) Decline the provider, ship `ResolvedHDR`, `resolveHDR(in:)`
and `headroom(_:)`, and decline `exposureAdjust(_:)`. (b) Decline all of it.
(c) Grow `Color` for the provider.

**Recommendation:** (a). All of these are macOS 26 APIs (the HDR half could
not even be probed on this machine's macOS 15), and they are rare in ported
code.

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
