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
(TUIkitMenus) can make it; and the nine declarations the carve widened for these two files alone are internal again.
Five are the diagnosis's: `View.bordered`, `EnvironmentValues.isInsideMenu` and `menuRowWidth`, `_MenuSectionedItems`
and `_MenuItemButtonStyle`. Four more the diagnosis did not name: `ScrollView`'s `withoutFocusStop()` and
`asChrome()`, which the column sets on its scroller, and `FocusManager.SubtreeFocusJump` and
`moveFocus(inSubtreeAt:jump:)`, which the core's paging keys call (Page Up and Down, Home and End). The index store
finds no file of another module that names any of the nine (session notes, `plan/overwide.py`: every `package`
declaration of TUIkitFoundation's six directories that gained `package` since fc6f6b7db and that no other module
references). The map follows the files (Tools/ModuleMap's map.json and the TUIkitMenus entry of rules.json). One type
widens and nine narrow; nothing becomes usable from outside the package.

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
rate), and two files depart from the plan's map. A third part of the price comes due only when the package ships a
product per module, which none does yet: an app that links TUIkitFoundation but not TUIkitMenus would still carry
`_InlineMenuCore` and its specialised column, which its protocol conformance records keep from being dead-stripped.
How many bytes that is, is unmeasured.

### B-SPM1-2. `_InlineMenuCore.swift` imports TUIkitView itself, which M1 did not ask for

*Sources/TUIkitFoundation/Rendering/_InlineMenuCore.swift — no API*

Back in TUIkitFoundation, the inline menu's paging-key replay closure carried a `swift_task_isCurrentExecutor`
check that it had not carried in TUIkitMenus. Swift 6.2.4 marks a closure literal for that check unless the callee's
module is one the calling file imports and is concurrency-checked, or is the caller's own module (CSApply.cpp
L6283-6299). The closure goes to `EffectJournal.Entry` (TUIkitView), and TUIkitFoundation reaches TUIkitView only
through its Exports.swift's `@_exported import`, which counts for no other file. The file in TUIkitMenus imported
TUIkitFoundation, and so TUIkitView. B6s's file imported only TUIkitCore, and had the check too. What ships is one
`import TUIkitView` in that file, with a comment saying why: the replay, which runs whenever a memo serves an inline
menu, checks the executor no more, as at 4771bb09c.

The fuller version is an audit. The same rule applies to every file the TUIkitFoundation target compiles that passes
a closure literal to TUIkitView's (or TUIkitStyling's, or TUIkitCore's) API without importing that module. The target
compiles 571 files from six directories (Sources/TUIkitFoundation and the five planned modules not yet carved:
TUIkitNumericControls, TUIkitTextInput, TUIkitPickers, TUIkitForms, TUIkitSearch; Package.swift's `directories:`),
and 124 of them import TUIkitView (117 of Sources/TUIkitFoundation's 476). How many of TUIkitFoundation's 607 check
sites, a count over the whole module, that accounts for is unmeasured, and so is how many of them run per frame. Its
price: an import per file where the index shows such a closure, and Tools/ModuleMap's `imports` check, which skips
TUIkitFoundation's own files today, extended to them for the lower modules. It is not a split regression (no carve
changed those files' imports), so it belongs to a lane of its own, measured first.

### B-SPM1-3. Two static totals stay above the base's: every extra site is B6s's, and none adds a check at run time

*`View.bordered`, `renderMenuColumn`, `_InlineMenuCore.registerPagingKeys` — no API*

The brief's gate asks that `swift_task_isCurrentExecutor`, `swift_beginAccess` and stored-property initialiser sites
not exceed 4771bb09c's (1,398, 4,061, 60). After M1 and B-SPM1-2 they are 1,401, 4,063 and 60. Each extra site is in
a function that xc-spB6s, step B6's binary (before B5b), has with the same site:

- **Two executor checks, in `bordered`'s two specialisations,** which M1 brings back. Each copies the generic
  entry's check, which guards the `reduce` closure that nests a second ring around the first. That closure runs only
  for a border wider than one cell, so no menu reaches it.
- **One executor check, in the scrolled branch of `renderMenuColumn`:** `View.frame(width:height:alignment:)`'s
  own check, inlined. 4771bb09c called `frame` out of line and ran the same check inside it.
- **Two exclusivity checks, in `registerPagingKeys` and its replay closure:**
  `KeyEventDispatcher.addHandler(sectionID:_:)`, inlined. 4771bb09c called it out of line and ran the same accesses
  inside it.

What ships leaves them. The other version: `bordered` nests its rings in a loop rather than through `reduce`, which
removes the check from the generic entry and both specialisations (-3: 1,398 in all). The price is a change to code
that every app's `.border()` and `Box` run, made for a static count, with a run-time effect only on borders wider
than one cell. The inlined checks could go only by calling `frame` and `addHandler` out of line again, which is the
kind of cost M1 removes.

## C. Declined

### C-SPM1-1. Two other opaque results the carved modules resolve at run time

*TUIkitChrome's `_ToolbarModifier.presentationEntries(depth:context:)`, TUIkitMenus' `_MenuPopupCore` — no API*

The predictor fix this lane made (session notes, `plan/crossing_hazards.py`, called by the newest carve predictor
`SPB5c/predict.py` and crossing report `SPB5c/xings_b5c.py`) flags, over B5b's and B5c's four modules after M1, two
callees besides the column's:

- **`keyboardShortcut(_:)`**, whose result names the internal `KeyboardShortcutModifier`, from the toolbar rows of a
  presentation (`ToolbarPresentationRows.swift`, a confirmation or cancellation item). The release binary confirms
  one `swift_getOpaqueTypeConformance2` site in `presentationEntries`, which runs whenever that function builds
  such an item's row. Stress uses neither placement, so no benchmark scenario reaches it; how often an app does is
  unmeasured.
- **`focusable(_:)`**, whose result names the internal `FocusableModifier`, from `_MenuPopupCore`. The binary calls
  the runtime only from a lazy witness-table accessor, which caches what it finds, so the lookup happens once per
  process.

Neither is changed here: the first is the same class as M1's, but on no measured path (the remedy would be M1's
pattern, a concrete entry in TUIkitFoundation), and the second costs nothing per call.
