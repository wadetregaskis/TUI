# Completing the SwiftUI API: decisions from lane SPB5c

*Lane SPB5c took step B5c of the module split
([`Module split plan, revision 4`](Historical/Module%20split%20plan,%20revision%204%20(2026-10-07).md),
§5), 2026-10-09: the carve of TUIkitBitmaps (`Sources/TUIkitBitmaps`:
`Image(_:)` from a file or URL, `Image(_:bundle:)`, `AsyncImage`,
`_ImageCore` with its render cache, templates, resizing and orientation,
`.terminalGraphics(_:)` and the `.image*` options, asset catalogues and
`Color(_:bundle:)`, the `image:` initialisers of `Label` and
`ContentUnavailableView`), a leaf built on TUIkitFoundation and TUIkitImage,
and with it the plan's other half of the row: TUIkitFoundation no longer
depends on TUIkitImage or CSTBImage. It changed no public API: the umbrella
re-exports TUIkitBitmaps, and names TUIkitImage itself, so `import TUIkit`
gives an app what it gave before. This file holds the judgement calls the
step reached that the plan did not already settle, in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):*

- **A-SPB5c-n — needs your decision.** Nothing has shipped for these.
- **B-SPB5c-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB5c-n — declined.** With the reason.

There is no A entry: nothing waits on the owner.

## What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because this step made them. Each
name below was `TUIkitFoundation`'s after step B1; of the types, only
`ImageSource` was in v0.6.0, as `TUIkit.ImageSource`.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name a
  moved type's new module: `TUIkitBitmaps.AsyncImage<…>`,
  `TUIkitBitmaps.AsyncImagePhase`, `TUIkitBitmaps.ImageSource`,
  `TUIkitBitmaps.ImageFitTarget`. `Image` itself stays
  `TUIkitFoundation.Image`, whichever initialiser made it.
  `UmbrellaQualifiedNameTests` pins four of them. The plan's map moves no
  type out of TUIkitBitmaps later, so these names are final.
- **Saved state is unaffected.** TUIkitBitmaps declares no `Codable` type.
  One of its public types is `Hashable` (`ImageFitTarget`) and so can be a
  value of a `NavigationPath`, but a path holding one has no `codable`
  representation, which is the only saved form that stores type names
  (decisions SPB5, "Saved navigation paths").
- **The bundle is unchanged.** The directory holds Swift files only, so the
  bundle is still `TUIkit_TUIkitStrings` (decisions SPB2). An image named in
  a bundle is read from the app's bundle, as before.
- **The documentation lists the module's options on `View` and on its own
  types, not on TUIkitFoundation's.** As at steps B5, B6 and B5b:
  `symbolgraph-extract` copies onto a module's conforming types the
  protocol-extension members that module can see, its own and its
  dependencies', so neither `Text`'s page nor `Image`'s (which stays
  TUIkitFoundation's) lists `imageColorMode(_:)`, `terminalGraphics(_:)`,
  `imageCharacterSet(_:)` or `imageFitTarget(_:)` among its default
  implementations any more, while `View`'s and `AsyncImage`'s pages do;
  `scaledToFit()`, which stays, is on all four: checked in the strict docs
  build's archive, 2026-10-09. The archive has 53,761 pages against step B5b's
  55,840; how many of the 2,079 are such copies was not counted. No doc link
  had resolved only through one: the strict build reports nothing.
- **The modules' edges, which is what each import will bring once
  per-module products ship.** TUIkitBitmaps depends on TUIkitFoundation and
  TUIkitImage and re-exports both, so `import TUIkitBitmaps` brings the
  options' `ASCIIColorMode`, `ASCIIToneCurve` and the rest. No module of the
  map depends on it but the umbrella: `import TUIkitApp` does not bring
  `AsyncImage` or `Image(_:bundle:)` (plan §4, "Any app using … bitmaps:
  + TUIkitBitmaps"), and no longer brings TUIkitImage either:
  TUIkitFoundation does not re-export it. TUIkitAppKit, the AppKit bridges,
  depends on TUIkitBitmaps (B-SPB5c-1). `Image(systemName:)`, `.resizable()`,
  `.aspectRatio`, `.scaledToFit()`, `.scaledToFill()` and `.imageCellAspect`
  stay TUIkitFoundation's (the plan's S1), so an app that draws only symbols
  needs neither module.

## B. Shipped

### B-SPB5c-1. TUIkitAppKit depends on TUIkitBitmaps

*Package.swift, Sources/TUIkitAppKit — no API*

The plan (§8) found that TUIkitAppKit reaches `Color.catalogColor` and
`catalogColorScheme`, which the map puts in Bitmaps, "through the umbrella's
re-export". TUIkitAppKit does not depend on the umbrella: its target depends
on the modules whose types it extends (Package.swift's comment on it), which
were TUIkitFoundation and TUIkitImage. After the carve, those declarations,
and `Image(_:decoded:)`, `_DecodedImage`, `ImageSource` and
`Image.bundleResource(named:in:)`, which an image made from a `CGImage`, an
`NSImage` or a compiled asset catalogue draws through, are TUIkitBitmaps'
(21 references from 2 files, all `package` or public already).

**Shipped:** TUIkitAppKit depends on TUIkitBitmaps, beside the other two, and
its two files that use it import it. It is no module of the map, so the
map's "pure leaf" is unaffected: no module of the map depends on Bitmaps but
the umbrella.

**The other version:** TUIkitAppKit depends on the umbrella, as the plan's
sentence assumed. **Price:** every module would be built before the bridges
could be, and an app that takes the bridges à la carte, once per-module
products ship, would take the whole framework with them; the target's
comment says why it does not.

### B-SPB5c-2. `placeholderRows` is a non-generic core under an `@inlinable` generic shim

*Sources/TUIkitFoundation/Rendering/TerminalImageStore.swift — no API*

PRESPEC (session notes, recommendation.md) recommends making
`TerminalImageStore.placeholderRows<Signature>` non-generic at this step: its
only generic work is erasing the signature, and after the carve
`_ImageCore` (TUIkitBitmaps) called the unspecialised generic once a frame
for every image drawn with Kitty graphics. Its other three callers, and their
signature types, are TUIkitFoundation's until step B7 carves
NumericControls.

**Shipped:** the inventory's form: a two-line `@inlinable` generic shim that
erases the signature in the caller's module, specialised there, and a
non-generic `@usableFromInline` internal core. The class,
`AnyImageSignature` and `ImageStoreSignature` are `@usableFromInline` for it.
The store's private stored properties were checked dynamically before
(every copy of the method holds 15 `swift_beginAccess` calls, in c181ec0f9
too), so nothing changes there. The bucket goes to the core as a closure, so
it is still computed only on a miss.

**The other version:** each caller erases the signature itself and calls a
non-generic `package` method, with no shim. **Price:** the erasure spelled at
four sites, and `AnyImageSignature`'s initializer would still have to be
`@inlinable` for TUIkitBitmaps' call to be specialised: the same exposure,
more code. `@_specialize(exported:)` is not available: TUIkitFoundation
cannot name `TerminalImageSignature`.

### B-SPB5c-3. The image's environment reads, `Image.init(raster:)` and `Label`'s designated initializer stay calls

*Sources/TUIkitFoundation — no API*

After the carve, `_ImageCore` calls across the boundary, once a frame for
each image drawn, fourteen environment accessors TUIkitFoundation declares
(`imageCellAspect`, `imageContentMode`, `imageAspectRatio`,
`scrollViewportSize`, `terminalImageStore`, `lifecycle` and the rest). In
c181ec0f9 each was inlined into its caller, which then called a
specialisation of the environment subscript: a dictionary lookup and a cast
out of `Any`. Now the caller calls the accessor (152 to 184 bytes, or a tail
call to that specialisation, 28 to 64), which does the same. The step's
brief puts a call that does its own work outside tier 2, as B5b did for the
scroll transition's geometry reads.

`Image.init(raster:)` (68 bytes: it boxes the raster into the image's
content) and the generic `Label.init(title:icon:iconIsVisible:)` run once a
body evaluation of a view built with an image name (`Image("name", bundle:)`,
`Label(_:image:)`, `ContentUnavailableView(_:image:description:)`).

**Shipped:** all three stay calls. The plan's tier 2 at B5c lists more of
these accessors than are inlined; the commit that inlines
`isNaturalExtentBudget(_:)` and `_ImageResizing`'s `slices` and `filling`,
each less work than its call, says which.

**The other version:** `@inlinable` on each. **Price:** for the accessors,
each environment key `@usableFromInline` (they are `private` today) and one
call and return saved beside a dictionary lookup, per accessor per image per
frame; for `Image.init(raster:)`, `Image.Content` and the raster protocol
(R2's seam) `@usableFromInline`, which exposes the seam to every module's
inline code; for `Label`'s initializer, the initializer of its `styles`
property wrapper would run out of line from every inlined copy
(CONTRIBUTING's rule on stored-property defaults), adding a call where one
is saved. The coordinator's A/B decides; no Stress scenario reaches them
(no scenario draws a bitmap), Example's image pages and IdleProbe do.

## C. Declined

### C-SPB5c-1. `_OpacityView.fading` is left generic

*Sources/TUIkitFoundation/Modifiers/OpacityModifier.swift — nothing*

PRESPEC recommended moving `_OpacityView.fading` (generic in name only) off
the generic type at step B5b; that step's carve did not. It is not this
step's crossing: its only caller in another module is TUIkitEffects'
`_ColorEffectView`, since B5b, and TUIkitBitmaps does not call it. The
release binary shows c181ec0f9 called it out of line from the same caller
too (SPH2's edgecmp: one call per colour-effect render in both). It is
B5b's A/B's to call for (`modifiers --variant color-effects`).
