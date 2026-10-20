# Sheets, the page around them and their content: lane MODALS's judgement calls

*Lane MODALS, 2026-10-19, fixed five framework problems that lane O10 found
in sheets and worked round for its file panels alone (O10's final report,
"Framework issues found"). Each fix landed with a test that fails without it.
Where it let the file panel drop its workaround, the workaround went in the
same commit:*

- *M1: a sheet's status bar items replaced its Escape item.*
- *M2: an alert at a sheet content's root took the sheet's size.*
- *M3: a sheet built its content on every frame.*
- *M4: a sheet's content kept its state after dismissal under a container
  that keeps its subtree's.*
- *M5: the input-chain harness ran no lifecycle passes.*

*Popovers got the M3 and M4 fixes too. Where the work met a call the brief
did not settle, the safe option shipped and is written up here: A needs a
decision, B shipped the safe option (with the fuller version and its price).
Nothing was declined.*

## A. Needs a decision

### A-MODALS-1. Keys declared outside a modal sheet still work behind it

*`sheet`, `fullScreenCover`, `modal`, `alert` and `confirmationDialog`, and
what a page declares around the view presenting one*

A modal presentation makes the page behind it inert on four channels
(memory: modal input channels). The mouse is inert across the whole screen,
because the dimmed backdrop drops every hit region. Focus is held by the
modal's section, which Tab cannot leave. `onKeyEvent` handlers are silenced
across the whole tree by `grabInput`. The page drawn beneath the sheet is
isolated (`isolatedForBackground()`), so its own status bar items and
`.keyboardShortcut`s neither show nor fire.

Two channels are inert only inside the view that presents the sheet. Status
bar items and keyboard shortcuts declared *outside* that view stay live:

- **Status bar items.** The modal's section merges with the items declared
  outside it (`StatusBarState.resolvedSectionItems`, `.merge`). A page's
  `.statusBarItems { n new }` wrapped around the view that presents a sheet
  still shows "n new" over the sheet, and `n` still runs it. This was decided
  on 2026-08-22: "what is left to merge with is whatever the app declares
  outside the presented subtree, which is live and should show"
  (`ModalPresentationModifier.takeKeyboard`). M1 closed it for Escape alone:
  the sheet's Escape item now always shadows the page's "⎋ back".
- **`.keyboardShortcut`.** With no live sheet docked, every shortcut
  registered outside the presenting view is in the page's table, and it
  fires behind a modal sheet (`KeyboardShortcutRegistry.paneScoped`: with no
  active pane it reads `page[trigger]`). `reachesPage` gates only a pane's
  fall-through.

A scratch probe through the input-chain harness confirmed both (session
notes, `MODALS/ZZScratchOutsideKeysTests.swift`). Over a presented sheet the
bar read "⎋ dismiss", "n new" and "q quit". `n` ran the page's item, and ⌃K
fired the shortcut of a button beside the view presenting the sheet. It was
not run in a live app.

**Options.**
1. **Leave it** (shipped): Escape is the presentation's, and every other key
   declared outside the presenting view stays live and shown.
2. **Silence status bar items behind a modal.** While a modal section holds
   the focus (`activeSectionIsModal`), the bar shows and runs only that
   section's items and the system items (quit). An app item the app wants
   over its sheets is declared in the sheet. About two hours with tests. It
   reverses the 2026-08-22 note above.
3. **Option 2, plus shortcuts.** While a modal section holds the focus, only
   shortcuts registered inside it fire. The registry records each
   registration's section, as it already records its pane. The menu bar's
   commands stay app-wide. About half a day.

**Recommendation:** 3. The dimmed backdrop already says that the whole
screen behind a modal sheet is inert. Three channels of five already behave
that way, and a key that works behind the dimming contradicts the picture.

## B. Shipped the safe option

### B-MODALS-1. A dismissed sheet posts a dock resolver on every frame

*`sheet(isPresented:)`, `fullScreenCover(isPresented:)`, `modal(isPresented:)`*

A live sheet (`presentationBackgroundInteraction(.enabled)`) docks at the
bottom of the content area. The root lays the page out above it before the
walk, using the resolvers the sheets posted the frame before. A sheet the app
presents between two frames must therefore have posted one while it was
dismissed, or its first frame draws it over the page's bottom rows. A test
pins this (`LiveSheetLayoutTests.appDrivenOpenIsNotLate`). A dismissed sheet
used to learn whether it could be live by reading its content's trait, which
meant building its content on every frame.

**Shipped:** every dismissed sheet posts a resolver every frame: one closure
and one dictionary entry keyed by its section's name. The root asks it twice
a frame, before the walk and after it, and each time it reads the sheet's
binding once. Only if the sheet has been presented by then does it build the
content, and the presenter's records of a presentation with it. It replaces
building the content and reading two traits every frame. The sheet's posts
are forgotten when the run loop ends (B-MODALS-3).
**A/B owed:** `Stress --scenario sheetrows`, da6ac224e against 05e0d085f,
and the head of the lane against both.

**Fuller version, if the A/B says the post costs more than the build saved:**
key the posts by the presenter's identity, not by its section's name, which
is rendered from the identity's path on every frame, dismissed or not. Or
post only from presenters that have been presented live before, and let a
first live presentation dock a frame late. That is the `item:` forms'
behaviour today (B-MODALS-2), and it regresses the pinned test. About two
hours either way.

Cheaper, and worth doing whatever the A/B says: an `item:` sheet's dismissed
post, and the sheet form's of every closed popover, can never dock. The
first's content is made from no item (B-MODALS-2), and the second's binding
holds the form read while the popover was closed. A flag from those
presenters would skip the post. About an hour with tests.

### B-MODALS-2. An `item:` live sheet presented between frames still docks a frame late

*`sheet(item:)`, `fullScreenCover(item:)`*

An `item:` sheet's content is built from the item read when its presenter
was built, together with the identity key. That item is none while the sheet
is dismissed. So the dismissed resolver has nothing to build, and the first
frame of an `item:` live sheet still draws it over the page's bottom rows
and settles on the next frame, as before.

**Fuller version:** have the resolver read the item binding when the root
asks, and derive the key from that same read, so that the first frame docks.
About two hours, with the key's "same read as the content" contract moved
into the resolver.

### B-MODALS-3. The last frame's dock resolvers are forgotten when the run loop ends

*`RenderLoop.deinit`, `FocusManager.forgetPresentationDocks()`*

A resolver holds its presentation's binding and the closure that builds its
content. Either may reach the environment, and the environment holds the
focus manager the resolver is posted to. The Settings scene's binding holds
the app's scene presenter, for one. Each frame's posts replace the last's,
but the last frame's stayed after the loop ended. They held the app's focus
manager, state storage, render cache and status bar
(`ScenesLifetimeTests.scenesFreed` caught it once every dismissed sheet
posted). The loop now forgets them when it goes.

A focus manager that no run loop owns had no such end, and nothing replaced
its posts either, because no root read them. The windowed stack's
focus-reach probe draws each row it asks under a scratch manager of its own,
and every probed row that held a sheet left its manager alive, every frame.
A snapshot (`renderOnce`) of a view holding a sheet kept its whole render, and
so did a test host per test. A manager now takes docks only once a root has
asked it for them, before its first walk, and never while it is a backdrop's
(`FocusManager.takesPresentationDocks`). In an app only the run loop's
manager takes them, and the loop's end forgets what it holds.

A presented live sheet's resolver has always kept its presenter's whole
environment. It needs that environment for custom detents, which may read
any value in it. While the sheet is presented, that resolver and the focus
manager hold each other until the next frame replaces it.

**Fuller version:** keep the docks somewhere the environment cannot reach.
The ledger lives in the focus manager, which every environment holds; it
would move to an object only the run loop holds, with the root reading it
through a weak reference. About a day, in the A19 machinery.

### B-MODALS-4. TUIkit's own popovers and the dialog builders are still built eagerly

*`alert`, `confirmationDialog`, and the popovers TUIkit draws for its own
controls*

The sheet's and the popover's content closures now run only while presented.
Some builders still run on every frame while dismissed:

- `alert`'s and `confirmationDialog`'s `actions` and `message` builders.
- The values TUIkit's own popovers are made from: the compact date picker's
  calendar, a link's destination, a tab's popovers, the toolbar's
  customization panel.

These are a handful of buttons or one small view, with no app closure whose
side effects could run early.

**Fuller version:** the same closure in each presenter, called once the
dialog or popover is presented. About three hours with tests, for little
measured benefit. It would need an A/B on a page of many date pickers to
justify it.

## Found on the way

- **A view an `if` removes keeps its `@State` under a container that keeps
  its subtree.** A scratch probe (session notes, `MODALS/`) put a counter
  button in a `ScrollView { LazyVStack { … } }`, pressed it, removed the
  counter with an `if` and brought it back. It came back still reading
  "count 1", both as `if`/`else` (`ConditionalView`) and as a plain `if`
  (`Optional`). SwiftUI ends the view's identity there.
  - `ConditionalView`'s flip drops the other branch's descendants strictly.
    A composite's `@State` lives at its own identity, which for a branch's
    root view is the branch identity itself, so the root's own state
    survives.
  - `Optional` drops nothing when it goes, and relies on the end of the
    pass to prune, which a retaining container prevents.

  The `includingItself:` flag M4 added to `invalidateDescendants` is the
  first half of a fix. The second is an invalidation on `Optional`'s
  presence flip. Not this lane's to land: it is core rendering, and every
  `if` in every app pays for it.
- **M5 widened nothing in the suite.** All 12674 tests passed with the
  harness's frames inside the lifecycle passes. No test written against the
  harness had relied on a view never disappearing.
