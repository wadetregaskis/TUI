# Completing the SwiftUI API: decisions from lane SPM1

*Lane SPM1, 2026-10-09, landed remedy M1 of the profile diagnosis of module split step B5b (session notes,
`SPB5b/regress/diagnosis.md`): the inline menu's column is built in TUIkitFoundation again, so that it is
specialised and resolves no opaque type at run time. It changed no public API and no behaviour. This file holds what
it found that the brief did not settle, in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):*

- **A-SPM1-n — needs your decision.** Nothing has shipped for these.
- **B-SPM1-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPM1-n — declined.** With the reason.

Every count below is a static count in a release `Stress` (Xcode's Swift 6.2.4,
`swift build -c release --product Stress -Xswiftc -g`, `otool -tV`, each function attributed to its module by the
debug map), against the binary of 4771bb09c (steps B5b and B5c). None is a timing; the coordinator's A/B measures
time.

## B. Shipped the safe option

### B-SPM1-1. The inline menu's core and column stay in TUIkitFoundation, not in TUIkitMenus as the plan maps them

*Sources/TUIkitFoundation/Rendering/_InlineMenuCore.swift, MenuColumnLayout.swift — no API*

Plan revision 4 maps `_InlineMenuCore` and the menu column's layout to TUIkitMenus, and step B5b carved them there.
From TUIkitMenus the column could not see the types it is made of: `View.bordered`'s result names the internal
`_BorderRings` and `foregroundStyle(_:)`'s the internal `_StyleEnvironmentView`, so the column looked both up at run
time on every call (`swift_getOpaqueTypeConformance2`, four call sites), and it called `bordered`, a `package`
generic, unspecialised. The diagnosis priced these frames at about 0.24 of B5b's menus-cold time against B6s's code
(from profile shares, not times; net about -0.1 to +0.2 on the same path). What ships is its remedy M1: both files
compile in TUIkitFoundation, as they did until B5b; `_InlineMenuCore` is `package` so that `InlineMenuStyle`
(TUIkitMenus) can make it; and the five declarations the carve widened for these two files alone are internal again.
The map follows the files (Tools/ModuleMap's map.json and the TUIkitMenus entry of rules.json). One type widens and
five narrow; nothing becomes usable from outside the package.

The other versions, as the diagnosis priced them:

- **M1′: keep `_InlineMenuCore` in TUIkitMenus** and give it two non-generic `package` entries in TUIkitFoundation
  that build the column there (`measureInlineMenuColumn(label:content:context:capHeight:)` and a render twin). The
  same recovery, the map unchanged for `_InlineMenuCore.swift`, at the price of two new names where M1 widens one
  type. Choose it if the plan's map matters more than the smaller surface.
- **Widen `_BorderRings` and `_StyleEnvironmentView` to `package`.** Removes the run-time lookups but not the
  unspecialised `bordered`, and every app could then see through `.border()` and `.foregroundStyle()` too (Stress
  has 6 and 37 such symbols): the app's own code would change, so no A/B could separate the remedy from the app
  change. Declined by the brief.
- **`@inlinable` on `bordered`** (with `@usableFromInline` on what it names). TUIkitMenus would specialise it, but
  `_BorderRings` becomes effectively public, the same app change, and it does nothing for `foregroundStyle`.
  Declined by the brief.

The price of what ships: about 420 lines compile in TUIkitFoundation's job again (about 0.1 s at the carve's own
rate), and two files depart from the plan's map.
