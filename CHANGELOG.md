# Changelog

TUI has no tagged releases yet and is pre-1.0. Public API can change in any commit, and the project deletes deprecated or superseded spellings outright instead of keeping compatibility shims.

## Unreleased

These notes cover the change from the single-module package (a `TUI` target plus `TUICore`, `TUIStyling`, `TUIView` and `TUIImage`, as of 1 October 2026) to current `main` (29 October 2026). The module split itself landed between 8 and 19 October. If you were already building against a commit from after 8 October, skip the parts that describe things you already have. What changed from 23 to 29 October that an existing app may notice, and is not described elsewhere, is under "Since 23 October" in the upgrade-affecting changes.

### TUIkit is now TUI

The project, its package, products and modules are renamed (25 October 2026). Every name drops the "kit": the
package `TUIkit` is `TUI`, the umbrella `import TUIkit` is `import TUI`, and each module `TUIkitX` is `TUIX`
(`TUIkitApp` is `TUIApp`, `TUIkitTables` is `TUITables`, and so on). Type names are unchanged. These notes use the
new names throughout, for the package as it was on 1 October as well.

- Change each `import TUIkit…` to `import TUI…`, and each `.product(name: "TUIkit…", …)` to
  `.product(name: "TUI…", …)`. The repository is renamed too (29 October): depend on
  `https://github.com/wadetregaskis/TUI.git`. The `package:` argument is the package's identity, which SwiftPM
  takes from that URL, so it is `"TUI"`: `.product(name: "TUI", package: "TUI")`. GitHub redirects the old URL,
  but a dependency that still names it keeps the identity `TUIkit`, and its `package:` arguments must say so.
- The trait `UnexportTUIkitSymbols` is `UnexportTUISymbols`. A dependency that names its traits
  (`traits: […]`) must use the new name.
- The resource bundle that ships beside an app is `TUI_TUIStrings.bundle`, not `TUIkit_TUIkitStrings.bundle`.
- The documentation's paths are `/documentation/tui/…`, not `/documentation/tuikit/…`.
- Every environment variable's `TUIKIT_` prefix is `TUI_` (`TUIKIT_CONFIG_DIR` is `TUI_CONFIG_DIR`, and so on), and
  so is the `TUIKIT_TEST_SUPPORT` compilation condition; the old names are not read.
- Unchanged: the folders and defaults keys where an app's settings are kept, so nothing a user saved is lost.

### If you only need the short version

- If your target depends on the `TUI` product and writes `import TUI`, it still compiles the same framework with the same names. Nothing about the split forces a change.
- Check the "Upgrade-affecting changes" list below. The ones most likely to bite are the renamed resource bundle, the opt-in status bar and toolbars, the AppKit bridges that need `import TUIAppKit`, and the removed spellings.
- If you want a smaller app, depend on the module products you use instead of `TUI`.
- Two package traits are on by default and change how your macOS release build is linked. They are described below, with the opt-outs.

### The module split

TUI is now 32 library products. Before, there were five (`TUI`, `TUICore`, `TUIStyling`, `TUIView`, `TUIImage`).

#### The umbrella still works

- `import TUI` is the whole framework, as `import SwiftUI` is SwiftUI. The `TUI` module declares nothing itself. It re-exports every other module except `TUIAppKit`, `TUIFilePanelsAppKit` and `TUIMacros`, which you import separately.
- `import TUI` also re-exports Foundation, as `import SwiftUI` does, so a file ported from SwiftUI that names `CGRect`, `URL` or `Date` needs no `import Foundation`. The module products do not re-export it.
- Qualified names such as `TUI.Label` or `TUI.ColorPicker` still resolve, through the umbrella's re-exports. The test suite pins this for types from many of the modules.
- `TUI` is still the right default for an app. The README and the docs assume it.

#### Depending on fewer modules

- Each module an app might want alone is a library product with the module's own name. List the products you use in your target's `dependencies:` and import those modules.
- SwiftPM compiles and links the products your target lists, plus what they are built on. Your `import` lines decide only which names your files can see. A target that depends on `TUI` and imports only `TUITables` still builds and links all of TUI.
- Every app needs `TUIApp` (`App`, `Scene`, `WindowGroup`, the run loop and the terminal). Add the product of each module whose names you use.
- Each module re-exports the modules it is built on, so `import TUITables` also gives you `List`.
- Measured on a hello-world app with Swift 6.4.0, stripped, default traits: `TUI` is 9,241,968 bytes. `TUIApp` alone is 5,751,768 bytes (-37.8%), compiling 8 TUI modules instead of 25.
- If you forget a product, the compiler says `cannot find 'Table' in scope` or `value of type 'Text' has no member 'tableStyle'`, and does not name a module. The documentation has a "Which Module Provides It" page that lists every public name with its module and product.
- Mixing `TUI` with module products in one app is safe. Each module is linked once.
- If you write a library on top of TUI, depend on module products (or `TUIFoundation`), never on `TUI`. Anything in an app's graph that depends on `TUI` gives that app the whole framework.
- Do not build a `.dynamic` library product from TUI's modules while an app also links a TUI product statically. SwiftPM's own build system gives the app two copies of the shared modules. Swift Build makes them dynamic libraries the app must ship.
- Module and product names are now part of what you depend on. Before 1.0, types can move between modules, and a `Package.swift` that lists a module changes if that module is renamed or split. An app on `TUI` never sees such a change.

```swift
.executableTarget(
    name: "YourApp",
    dependencies: [
        .product(name: "TUIApp", package: "TUI"),
        .product(name: "TUITables", package: "TUI"),
    ]
)
```

```swift
import TUIApp
import TUITables
```

#### The products

Foundation and app:

- `TUI`: the umbrella. Everything below except `TUIAppKit`, `TUIFilePanelsAppKit`, `TUIMacros` and `TUITesting`.
- `TUIApp`: `App`, `Scene`, `WindowGroup` and the scene modifiers, the run loop, the terminal (POSIX only), and `renderOnce`. Re-exports `TUIChrome` and `TUIFoundation`.
- `TUIFoundation`: what everything else is built on: `View`, `Text`, stacks, `ScrollView`, `Button`, `Toggle`, `Label`, `Image(systemName:)`, layout, state, the environment, focus and rendering. It cannot run an app on its own. It re-exports `TUICore`, `TUIStyling`, `TUIView`, and two modules that have no product of their own: `TUIStrings` (localization, string tables, SF Symbols names, the resource bundle) and `TUITerminalHost` (the terminal's identity, quirks and capabilities).

Feature modules:

- `TUIBitmaps`: `Image` from a file, URL or bundle, `AsyncImage`, the `.image*` options. Re-exports `TUIImage`.
- `TUIChrome`: the `StatusBar` view, toolbars, notifications, tooltips and `.help`. `TUIApp` and `TUIPresentation` re-export it.
- `TUIColorPicker`: `ColorPicker`, `ColorPickerPanel`, `GradientEditorPanel`.
- `TUICommands`: `Commands`, `CommandMenu`, `CommandGroup` and the placements, and the menu bar they draw. Re-exports `TUIApp` and `TUIPresentation`.
- `TUICurveEditors`: the tone-curve and channel-curve editor panels.
- `TUIEffects`: transitions, content transitions, `.symbolEffect`, `.visualEffect`, `.scrollTransition`, matched geometry.
- `TUIFilePanels`: `fileImporter`, `fileExporter`, `fileMover`, the `fileDialog` modifiers, and the open and save panels. Re-exports the modules its panels are built from: `TUINavigation`, `TUIPickers`, `TUIPresentation`, `TUITables` and `TUITextInput`.
- `TUIFilePanelImages`: `fileDialogPicturePreviews()`, which previews a selected picture in the file panels. Re-exports `TUIBitmaps` and `TUIFilePanels`, and is a product of its own so that an app with file panels and no pictures carries no image decoders, and one showing pictures no file panels.
- `TUIForms`: `Form`, `LabeledContent`, `GroupBox`, `Card`, `Panel`.
- `TUIGrid`: `Grid`, `GridRow`, `LazyVGrid`, `LazyHGrid`.
- `TUILists`: `List`, `OutlineGroup`, `EditMode`, list styles and row modifiers.
- `TUIMenus`: `Menu`, `ControlGroup`, `.contextMenu`, menu styles.
- `TUINavigation`: `NavigationStack`, `NavigationPath`, `NavigationLink`, split views, the inspector.
- `TUINumericControls`: `Slider`, `Stepper`, `Gauge`, `ProgressView`.
- `TUIPickers`: `Picker`, `RadioButtonGroup`, `DatePicker`.
- `TUIPresentation`: `alert`, `confirmationDialog`, `Dialog`, `sheet`, `fullScreenCover`, `modal`.
- `TUIScenes`: the `Settings` scene (shown as a sheet) and `AlertScene`.
- `TUISearch`: `.searchable`, search tokens and scopes, `searchSuggestions`, `dismissSearch`.
- `TUITables`: `Table`, columns, rows, styles, row drag and drop. Re-exports `TUILists`.
- `TUITabs`: `TabView`, `Tab`, `TabSection`, tab styles. Re-exports `TUILists`, and `TUIPresentation`, whose sheet a tab's popover becomes in a compact size class.
- `TUITabImages`: `Tab(_:image:…)`, the tabs whose picture is an image resource named by a string. Re-exports `TUIBitmaps` and `TUITabs`, and is a product of its own so that an app showing images pays nothing for tabs, and one using tabs nothing for image decoding.
- `TUITextInput`: `TextField`, `SecureField`, `TextEditor`.

Opt-in (not in the umbrella):

- `TUIAppKit`: `Color(nsColor:)`, `NSColor(_:)` and `Image(nsImage:)`, and compiled asset catalogue reading. Apple platforms only; empty elsewhere.
- `TUIFilePanelsAppKit`: `fileDialogSystemIcons()`, which draws the file panels' items with the Finder's icons. Built on `TUIAppKit` and `TUIFilePanels`, and a product of its own so that an app that takes `TUIAppKit` for `Color(nsColor:)` does not link the file panels (+29% in an app that does). Apple platforms only; empty elsewhere.
- `TUIMacros`: the `@Animatable`, `@AnimatableIgnored` and `@Entry` macros.
- `TUITesting`: `TestApp`, which runs an app or a view in a unit test with no terminal: press keys, click, move a clock by hand and read the screen. For test targets, so a shipping app carries none of it. See [Testing Your App](https://swift-tui.com/docs/documentation/tui/testingyourapp).

Low-level, as before:

- `TUICore`, `TUIStyling`, `TUIView`, `TUIImage`. These four build on Windows. `TUIView` and `TUIImage` now re-export the lower modules their API names, so one import covers either.

Executable products for trying things out: `Example`, `Stress`, and the development tools `EmojiBugScanner`, `EmojiBenchmark`, `RenderHarness` and `ImageHarness`.

### Package traits: smaller macOS release builds

Two traits are enabled by default. Both apply only to macOS release builds. Debug builds, `swift test` and documentation builds compile and link as before. Neither is applied on Linux or Windows, where they have not been measured. Both apply to every module that a library product ships.

**`DeadStripUnusedAPI`**

- Swift marks every public symbol so the linker keeps it, called or not. With this trait TUI's modules are compiled with `-internalize-at-link`, and your app's linker keeps only the TUI API your app reaches.
- `swift build -c release` passes `-dead_strip`. An Xcode app needs `DEAD_CODE_STRIPPING = YES`, which is not Xcode's default.
- Measured (stripped, 2026-10-11): a hello-world app is 14.7% smaller and `Stress` 12.1% smaller on Swift 6.4.0. On Xcode's Swift 6.2.4 it is 14.9% and 12.3%.
- What it breaks: a statically linked app that `dlopen`s a plugin which calls TUI API the app never calls itself. That symbol is gone from the app and the plugin fails to load.

**`UnexportTUISymbols`**

- A program exports every external symbol it defines, including TUI's. This trait passes one `-unexported_symbol` pattern per TUI module to the linker, which removes them from the export table (bytes that `strip` leaves in place).
- Measured (stripped, 2026-10-12, on top of `DeadStripUnusedAPI`): a hello-world app is a further 3.2% smaller and `Stress` 2.9%, on both toolchains.
- What it breaks:
  - A plugin loaded with `dlopen` into a statically linked app that calls any TUI API through the app fails to load ("symbol not found in flat namespace").
  - A `.dynamic` library that contains TUI exports none of TUI's symbols. A client that uses TUI through it fails to link, or fails at launch if it was linked against an older build of the library.
  - Your own extensions of TUI's types and protocols (`extension View { func card() }`, `extension Color { static var brand }`), and your conformances of TUI types to your protocols, are not exported either, because Swift names those symbols after the TUI module. A client in another module that calls one fails to link, unless the compiler copied its body into the client.
  - The linker refuses `-unexported_symbol` beside an export list. A link that passes `-no_exported_symbols`, `-exported_symbol` or `-exported_symbols_list` (as Xcode's `LD_EXPORT_SYMBOLS = NO` and `EXPORTED_SYMBOLS_FILE` do) stops with "-unexported_symbol cannot be used with -exported_symbol*".

**Opting out**

- `traits: []` on the dependency turns off every default trait of TUI's (today these two).
- `traits: ["DeadStripUnusedAPI"]` keeps dead stripping and turns off the symbol-hiding trait. Use this if your link needs an export list.
- No compiler or linker flag undoes what the traits do. The traits are the only way out.

```swift
.package(url: "https://github.com/wadetregaskis/TUI.git", branch: "main", traits: [])
```

```swift
.package(url: "https://github.com/wadetregaskis/TUI.git", branch: "main", traits: ["DeadStripUnusedAPI"])
```

### Upgrade-affecting changes

#### Because of the module split

- **The resource bundle is now `TUI_TUIStrings`.** It was `TUIkit_TUIkit` when the resources belonged to the umbrella target, and `TUIkit_TUIkitStrings` from the module split to the rename. It is `TUI_TUIStrings.bundle` on macOS and `TUI_TUIStrings.resources` elsewhere. If you ship TUI's bundle beside your executable (an archive, an installer, a Homebrew formula), copy the new name. The bundle holds the translations (German, French, Italian, Spanish, Chinese, Japanese) and the version.
- **A missing bundle no longer stops the program at launch.** TUI's words then read in English, whatever language the user asks for, and `tuiVersion` reads `unknown`. A program copied out of `.build` no longer finds the bundle left in `.build`. It reads the bundle beside it or none.
- **Type names seen at runtime name the declaring module, not `TUI`.** `String(reflecting:)`, `dump` and the debugger show `TUILists.List<...>`, `TUIApp.WindowGroup<...>` and `TUIFoundation.Text`. This is true whichever products you depend on. Code that matches on those strings needs updating.
- **A saved `NavigationPath.codable` representation is tied to module names.** It stores each value's type by its mangled name, which includes the module. A saved path holding a TUI type that has moved to another module stops decoding. This already affected `LocalizationService.Language` and the system format styles, which moved to `TUIStrings`. Types can still move before 1.0, so do not keep such a path across versions.
- **`renderOnce(content:)` is in `TUIApp`.** A tool that uses only it depends on `TUIApp`. With `import TUI` nothing changes.
- **`ASCIIConverter` and the rest of `TUIImage` are not re-exported by `TUIFoundation`.** With `import TUI` you still get them. An app on module products adds `TUIImage` (or `TUIBitmaps`, which re-exports it).
- **MemberImportVisibility is on for TUI's own modules.** Every carved module, `TUIFoundation`, `TUIAppKit` and `TUIFilePanelsAppKit` compile with Swift's `MemberImportVisibility` upcoming feature. It does not apply to your code unless you enable it yourself. If you do, a call to a member that a module adds in an extension needs `import` of the module that declares it in that file. `import TUI` covers every module except `TUIAppKit`, `TUIFilePanelsAppKit` and `TUIMacros`. On an app built from module products, the compiler's fix-it names the module to add, but only when that module is already loaded. One effect you get without turning anything on: because TUI's modules use it, SwiftUICore's extension members no longer reach an app through TUI.
- **The AppKit bridges need `import TUIAppKit`.** `Color(nsColor:)`, `NSColor(_:)` and `Image(nsImage:)` (and compiled asset catalogue reading) are in the separate `TUIAppKit` product, because a module that imports AppKit makes every importing app see SwiftUICore's extension members. Without this split, `FormatStyle.offset(to:)` and similar SwiftUI members were ambiguous in apps importing TUI. The Core Graphics bridges (`Color(cgColor:)`, `Color.Resolved.cgColor`, `Image(_:scale:orientation:label:)`, `Image(decorative:scale:orientation:)`) need only TUI.
- **swift-syntax is resolved for every client**, although only apps that depend on `TUIMacros` build it (see Dependencies).

#### API removed or renamed before the split began (3 to 7 October)

All of these are pre-1.0 changes with no old spelling kept.

- **Window chrome is opt-in.** The status bar no longer draws itself. Place `StatusBar()` in the window's bottom bar, for example `ToolbarItem(placement: .bottomBar) { StatusBar() }`. A bare `WindowGroup` now draws on every row with no key-hint line. The `a` (appearance) key is opt-in too.
- **`.appHeader` is removed.** Use `.navigationTitle`, `.navigationSubtitle` and `.toolbar` items.
- **`Scene.chromeStyle(_:)` and `chromeStyle(appHeader:statusBar:)` are removed.** Use `.windowToolbarStyle(_:)`.
- **`onDragGesture` and `DragGestureEvent` are removed.** Use `DragGesture(minimumDistance: 0)` with `onChanged` and `onEnded`, or `updating`.
- **`onRowActivate` on `List` and `Table` is removed.** Use `primaryAction` of `contextMenu(forSelectionType:menu:primaryAction:)`.
- **`onTapGesture`'s `(x, y)` overload is removed.** Use the closure that takes a `CellPoint`, or one with no argument.
- **TUI's focus-blind key handlers are renamed `onKeyEvent`.** `onKeyPress` is now SwiftUI's: focus-gated, with `KeyPress` and `KeyPress.Result`.
- **TUI's buffer-level modifier protocol is renamed `BufferModifier`.** `ViewModifier` is SwiftUI's, with `body(content:)`.
- **Button styles use SwiftUI's names:** `automatic`, `bordered`, `borderedProminent`, `borderless`, `plain`, `link`, `accessoryBar`, `accessoryBarAction`. TUI's `.default` and `.primary` are gone. `.plain` now means SwiftUI's undecorated plain; the old accent-tinted `.plain` is `.borderless`.
- **`ProgressViewStyle` is SwiftUI's protocol.** A bar's track is set with `trackStyle(_:)`, not `progressViewStyle(_:)`.
- **`TabViewStyle` is a protocol** (`DefaultTabViewStyle`, `CompactTabViewStyle`, `BorderedTabViewStyle`), no longer an enum.
- **`PresentationDetent` is a struct**, no longer an enum.
- **`Table` columns have SwiftUI's shape.** `TableColumn<RowValue, Sort, Content, Label>` with a content closure that builds a view. The String-returning closure columns are gone. `Table` no longer requires `Sendable` rows. A column's alignment is a `TableColumnAlignment`.
- **`Gauge` has SwiftUI's fourth type parameter.** The three-parameter spelling is gone.
- **`onHover` takes its closure as `perform:`.**
- **A popover attaches to any rectangle:** `attachmentAnchor` takes `.rect(...)`, and `PopoverAttachmentRect` is gone.
- **`ScrollGranularity.row` is replaced by `.scrollTargetBehavior(.viewAligned)`.** `.paging` is built in too.
- **Keys are drawn with macOS's symbols** (`⌃ ⌥ ⇧ ⌘`, then the key). `Shortcut.returnKey` is gone, and `Shortcut.enter`, `.home`, `.end`, `.shiftTab` and `.space` have new glyphs or words.
- **`ContextMenuModifier` is no longer public.**
- **The AppKit bridges moved to `TUIAppKit`** (see above).

#### API removed or renamed with and after the split (8 to 23 October)

- **`AppState.shared` is removed**, along with `AppState.setLanguage(_:)` and `currentLanguage`. Every app owns its render state. `DismissAction()` and `LocalizationService.setLanguage(_:)` act on the running app. Still process-wide: the localization service, the notification queue and the default `@AppStorage` store.
- **`Text + Text` is removed** (see the deprecated list below). Interpolate a styled `Text` into another `Text` instead.
- **The row-level drop closure takes its payloads first, then the index:** `([Payload], Int)`. This applies to `ForEach`, `DynamicTableRowContent` and the `Table`-level `dropDestination`. Before it was `(Int, [Payload])`.
- **`@AppStorage` on `UserDefaults` keeps property-list values as themselves.** A `Bool`, `Int`, `Double`, `String`, `Date`, `Data`, `URL`, a raw-representable value, or an optional of these is stored natively, so `UserDefaults.standard.bool(forKey:)` reads what `@AppStorage` wrote. Values written earlier (as JSON) read as absent. There is no migration. `@AppStorage` and `@SceneStorage` take raw-representable values, stored as their raw value. Other `Codable` values are still JSON.
- **`.automatic` picker style's type is `DefaultPickerStyle`**, not `AutomaticPickerStyle`.
- **`.memoized(id:)` returns `_MemoizedView<Self, ID>`**, not `EquatableView<_MemoizedView<Self, ID>>`, and `_MemoizedView` is no longer `Equatable`. The token is the memo's key, not the view's equality, so nothing can mistake it for a re-check of the view. Code that spelled out the old type names the new one; code that used `some View` is unaffected.
- **`TextContentType.url` is `.URL`.** Every `NSTextContentType` is now a `TextContentType`.
- **`Spacer.minLength` is a public `var`** under SwiftUI's name. `SpacerProtocol`'s requirement is `minLength`, not `spacerMinLength`.
- **`UnitCurve.easeInEaseOut`, `WindowGroup.init(content:)` and the `CoordinateSpace`-enum overloads are removed or made internal** (see below).
- **TUI's alert panel view is `AlertPanel`**, no longer `Alert`, whose name read as SwiftUI's retired value type. `.alert(…)` is unchanged; only code that names the view (`Alert(title:message:)`, `Alert.warning(…)`) changes. Its `.warning`, `.error`, `.info` and `.success` presets now start their titles with ⚠️, 🛑, ℹ️ and ✅.
- **`\.terminalFeatures` (`TerminalFeatures`) and `\.keyboardReporting` (`KeyboardReporting`) are no longer public.** `\.terminalCapabilities` answers what they did: `.pointerShapes`, `.progressReports` and `.notifications` for `pointerShapes`, `showsProgress` and `postsNotifications`, and `.disambiguatedKeys`, `.shiftedKeys`, `.keyRepeats`, `.keyReleases`, `.modifierKeys`, `.capsLock` and `.numericPad` for the seven `reports…`/`disambiguatesKeys` properties. Ask `terminal.supports(.keyReleases)` where you read `keyboard.reportsReleases`. A feature can also be undetermined where nobody knows, such as pointer shapes under tmux, where `pointerShapes` read `true` or `false` by what TUI sends. `KeyboardReporting.isEnhanced` has no single replacement: ask about the feature you need, as a terminal can speak the kitty protocol and take only some of it.
- **`URLImageCache.shared` is removed.** Each app has its own URL image cache, which `Image` and `AsyncImage` find through the environment; `.urlImageCache(_:)` hands a subtree a different one (a test's own, say). The cache is bounded now, at `URLImageCache.defaultByteLimit` (64 MiB) unless made with `URLImageCache(byteLimit:)`, the least recently used images going first. `PlatformImageLoader.loadImage(fromURL:cache:…)` takes an optional cache, and caches nothing without one. Outside an app (a one-off render) nothing is cached.
- **`UndoShortcuts.hint(for:on:commandKey:)` takes the `TerminalCapabilities`** (`\.terminalCapabilities`) where it took a `KeyboardReporting`.

#### Behaviour changes you may notice

- A `ForEach` row whose view is `Equatable`, or a view in `.equatable()`, is kept when its parent writes — its own `@State`, or an `@Observable` property its body read — and served if its rebuilt value compares equal and its environment is unchanged, as SwiftUI does; before, every row below the write was drawn again. A long log or chat draws in about three quarters of the time or less. A row's `==` must cover everything the row draws: one that leaves something out now shows the old picture after its parent writes, as it would in SwiftUI. `TUI_VERIFY_RENDER_MEMO=1` finds such a row, and `TUI_OPTION_C=0` turns the re-check off to compare. See "Re-checking Rows After a Parent Writes" in the render cycle article.

- The Violet palette draws success green, warning amber and error red, as every other palette does. Its semantic colours were colour-theory offsets from violet, so success was orange and error lime green.

- Inside GNU screen a copy is sent to the terminal through screen's passthrough and reported "Sent", where it was "Not copied". In a tmux pane whose `allow-passthrough` is on, a copy goes through tmux's passthrough when `set-clipboard` is not `on`, and is reported "Sent". Measured on screen 4.00.03 and tmux 3.7c with `Tools/TerminalProbes/keeper_passthrough_probe.py`.

- The page behind a sheet or an alert stays visible: everything on it keeps its glyphs and attributes, and each colour keeps 40% of its saturation (`FrameBuffer.modalVeilSaturation`) and is then laid at a quarter strength (`FrameBuffer.modalVeilOpacity`) over the palette's overlay colour, where the page used to be redrawn as plain text in two colours, with pictures drawn in text cells, bars and borders left blank. A terminal picture on the page is veiled the same way, pixel by pixel. It is still inert. `.dimmed()` keeps the two-colour look.

- `TextEditor` selects from the keyboard, as `TextField` does: Shift-←/→ a character, Shift-Option-←/→ a word, Shift-↑/↓ a line, Shift-Page Up/Down a page, Shift-Home/End to the document's ends. A plain ← or → with a selection lands at its start or end. It used to select only with the mouse, and Shift-arrows just moved the caret.

- A focused radio group, or a segmented picker, moves its cursor onto a selection made elsewhere: a menu, a shortcut, another control over the same binding. It used to keep its cursor where it was and mark two options, the new selection and the focused one, with the same bullet.

- A view with a `@Bindable` property is made with the model itself, `AccountView(account: account)`, as in SwiftUI. Its memberwise initialiser used to ask for a `Bindable<Account>`.

- On Apple Terminal and Warp a flag emoji is drawn as its country code, `JP` for 🇯🇵, in the same two cells. Terminal 455.1 draws the flag either as a boxed letter (after the repair TUI used to send) or shifted, with the rest of its row one cell left (sent bare), and Warp draws its two letters in boxes. Other terminals draw the flag. `TerminalQuirks.flagsAsCountryCodes` asks for this on a terminal you describe yourself.

- `.textSelection(.enabled)` on one `Table` cell's `Text` makes that cell's text selectable and nothing else: a click on another column's text selects the row again, and a drag there selects nothing. Around the whole table, a drag still selects across a row's columns.

- A drag selection begun inside a bordered container (`.border()`, `Box`, `Card`, `Panel`, `GroupBox`, a dialog, an alert) keeps to the container's interior, leaving out its border, its title and the page around it. A drag begun on the border or outside the container crosses it, and `.textSelectionScope(.pane)` turns the rule off for a subtree. As an experiment, a drag that goes more than 3 rows above or below the interior, or more than 6 columns beside it, widens to what the container sits in (the box around it, an enabled `textSelection`, or the pane) and stays widened until the release.

- A title key that reads the clock — `Button("Ends \(deadline, style: .relative)") {}` — stays live in a button's and a colour picker's title, a text, secure or value field's placeholder (and a `prompt:` `Text`), and a table column's header, as SwiftUI's does: each draws the frame's reading and wakes at the next change. A navigation title, an alert's title and message, help and a tab's title still read it once. `SecureField` and `TextField(_:value:format:)` parse their title key's Markdown, as `TextField` does.

- A number interpolated into a key with no specifier is written in the locale, as SwiftUI writes it: `Text("\(count) rows")` draws `1,234,567 rows` in English, `1.234.567` in German and `1 234 567` (a narrow no-break space) in French, where it drew `1234567`. A floating-point number has at most six fraction digits and no trailing zeros, so `\(3.5)` is `3.5` (`3,5` in German), not SwiftUI's `3.500000`, a deliberate deviation. The locale is `\.locale`: the app's, or the one a subtree sets for its `Text`s. The key is unchanged (`%lld`, `%lf` as SwiftUI spells it), so translations still match. Interpolate a `String` (`\(String(year))`) or use `Text(verbatim:)` for a number that must not be grouped, such as a year or a port.

- A number interpolated with a specifier, `Text("\(price, specifier: "%.2f")")`, follows `\.locale` too: it is written by exactly that conversion (`String(format:locale:)`) in the app's locale, `3.14` in English and `3,14` in German, and again in a subtree's own `\.locale` where its `Text` draws, as a bare number is. It was written once in the process's locale, so under an app-chosen language its numbers could differ from a bare one's. The key keeps the specifier as SwiftUI's does, so translations match.

- `Text("… \(value)")` (and every other key) of a value SwiftUI has no interpolation for — a `Bool`, an `Optional`, an enum, an array, a value typed `Any` — warns, as SwiftUI 26 does: "Localized string interpolation produces an unlocalized, debug description for this type of value." It still writes the description. Interpolate a `String` (`\(String(flag))`, `\(value.name)`) to say what you mean. SwiftUI's typed interpolations are all there: a `Substring`, an `AttributedString` (its looks kept), a `Date`, `URL` or other `ReferenceConvertible` value or an `NSObject` with an optional `formatter:`, and a `TimeDataSource` with `format:` are new. `\(value, specifier:)` takes a number only, as SwiftUI's does, where it took any `CVarArg`.

- On Ghostty, a `List` draws SwiftUI's separators by default: a line a pixel or two thick along the top of each row, drawn with Kitty graphics and taking no row, under `.automatic`, `.inset`, `.bordered`, `.plain` and `.surface` (not `.sidebar` or `.insetGrouped`), and not beside the focused or a selected row. A separator an app asks for with `.listRowSeparator(.visible)` is such a line there too, where it was a rule line of its own. Every other terminal draws lists as before. `.listSeparatorStyle(.line)` keeps the rule line on every terminal, `.listSeparatorStyle(.hairline)` asks for the thin line everywhere (drawn only where the terminal can), and `TUI_HAIRLINES=1` or `0` answers for a terminal TUI has not measured (decisions A-D6L-2). A prototype: the lines are hidden, not dimmed, under a fade or a sheet's backdrop.
- A `Table` stripes every other row by default.
- A sheet's, full-screen cover's or popover's content is built only while it is presented, and a dismissed one loses its `@State`, as in SwiftUI.
- `onChange(of:)` on an optional that starts set no longer fires on its first render.
- Effects run after the walk of a frame, as SwiftUI runs them after its update, and their state shows in the same frame. `onAppear`, `onChange`, `onPreferenceChange`, `onGeometryChange`, a `.task`'s start, the scroll observers and a bound `ScrollPosition`'s report used to run where their view was in the walk, so a view drawn before one showed the old state for a frame beside views after it that showed the new, and an `onChange`'s derived value or a size fed back through a preference reached the screen a frame late. Now they run once the walk is done — geometry first, then preferences, then `onAppear`, then `onChange`, as SwiftUI orders them — and if they wrote state the frame is walked again before it is written, at most twice. The first frame of a page that loads in `onAppear` shows what it loaded. A view drawn after an effect no longer sees what the effect wrote in that same walk, only in the walk made again. A chain of effects longer than two continues a step a frame, as before. An `onChange` or `onPreferenceChange` action that keeps triggering itself runs twice a frame and then not again for that change, and an `onGeometryChange` whose action sends its view back to the size before last is cut off, each with SwiftUI's warning ("… tried to update multiple times per frame.", "Geometry action is cycling between duplicate values.") on the diagnostic channel; such a loop used to run a step a frame until it ended. A trigger-less `PhaseAnimator`'s first frame shows its second phase's content, its animated values starting from the first phase.
- A view in a subtree that geometry correction draws twice in one frame acts once, for the drawing that reaches the screen. This is a reader of a named space, `.scrollView` or `.global` on its first frame, or on a frame something its prediction does not follow moves it. Its `onChange`, `onPreferenceChange`, `onGeometryChange`, `onAppear`, `onDisappear`, `.task`, `onModifierKeysChanged`, `onInteractiveResizeChange`, scroll observers and bound `ScrollPosition` used to act for both drawings. A reader's first frame no longer fires `.onChange(of: proxy.frame(in: …).minY)` from its guess to its answer, as SwiftUI fires nothing, and a view only the guess drew no longer appears.
- `Animation.default` is SwiftUI's: the no-bounce spring at the default pace.
- A `ScrollView`'s `proxy.scrollTo(_:anchor:)` (a row, or a purely horizontal view's column), `ScrollPosition` request (a row, an edge or an offset, either axis) or written `anchorPosition` edge made inside `withAnimation` glides to its target a line or column at a time along the animation's curve, as SwiftUI's animates, where it jumped, and `onScrollPhaseChange` reports `.animating` until it lands. `withAnimation`'s completion fires when it lands. The wheel, a key or a focus move stops it where it is. A `List`'s or a `Table`'s glides too, a row at a time, leaving the cursor and the selection, and both now report their scroll phases to `onScrollPhaseChange`. Under reduce motion it still jumps.
- `.scrollKeyboardAnimation(_:)` (TUI-specific) makes a `ScrollView`'s Page Up/Down, Home and End glide to where they land — the page a scroll target behaviour picks, an edge, the tail — rather than jump, and a `List`'s or a `Table`'s glide the rows to where the cursor's reveal puts them, the cursor moving at once; a key pressed during the glide counts from its target. Without it the keys jump, as before.
- Controls' faces — bordered buttons, pop-up pickers, combo boxes, text fields' caps — follow a new `ControlStyle` (`.controlStyle(_:)`), apart from the border's `Appearance`: filled by default (`.automatic`), or `.lines` in the border's own lines, `.braille(thickness:)` or `.blank`. Under `.automatic` the `.braille` and `.blank` appearances still set the controls' look too. For a week from 15 October the face followed the appearance, lines by default; `.controlStyle(.lines)` brings that look back.
- Segmented and palette pickers, and a compact `TabView`'s chips (the colour picker's mode tabs among them), end in the caps a button has in the control style and `buttonBorderShape` in force. By default nothing changes; under `.controlStyle(.lines)` a segmented picker is `( S │ M │ L )` with no field, and the selected tab's chip `( title )`. A focused strip's selected chip breathes those caps with its title, as a lines button breathes its caps with its label.
- A `.switch` toggle under `.controlStyle(.lines)` is a knob between the caps of the `buttonBorderShape` in force, four cells in every shape: `(○ )` off and `( ●)` on in a capsule (the default shape), `⦗● ⦘` / `⦗ ●⦘` in a rounded rectangle, `│● │` / `│ ●│` with square corners, and between a `.brackets` pair's glyphs. The caps breathe the accent while it holds the focus. Under Braille it takes the shape's dotted ends, under `.blank` the knob alone (`○ ` / ` ●`). Filled controls, the default, keep the coloured track, and the `.ascii` character set keeps `[o ]` everywhere.
- A `.bordered` (or `.grouped`) `TabView` draws its folder tabs and content box in the border of the `Appearance` in force — square under `.line`, heavy, double, Braille dots, blocks or nothing — where it was always rounded lines.
- A `ControlGroup` draws its buttons as one segmented face, as a segmented picker is drawn: caps only at the two ends and a rule between buttons, `▐ − │ 100% │ + ▌`, where each button drew its own caps (`▐ − ▌▐ 100% ▌▐ + ▌`). Its buttons stay one row at `.large` and `.extraLarge`, as a segmented picker does.
- A `List` row's `.standard` (and `.increased`) badge sits in a capsule, as macOS draws it: on a tinted field a cell wider each side, ` 12 `, or between the control family's caps under `.controlStyle(.lines)`, `(12)`. A badged row's badge is two cells wider, so a list that hugs its rows is two cells wider for it; a `.decreased` badge stays plain text.
- A `.buttonBorderShape(.underline)` button drawn in lines keeps its underline at `.controlSize(.mini)`, where it was the bare label: the line takes no cell.
- A large or extra-large filled `.circle` button is a disc rather than a plus: its label's row is the one-row circle's `▐ + ▌`, and the rows above and below are cut on the diagonal with `◢ ◣` / `◥ ◤` (Ghostty, iTerm2), `▄`/`▀` half blocks (Warp), or whole cells (Apple Terminal).
- On Apple Terminal, a large or extra-large rounded or capsule button keeps its shape: its face leaves out the corner cells the curve only nicks, where it was drawn as the same square block as a square button.
- A branch an `if`/`else` flips to, a `switch` case or a `ForEach` row that a change puts in under an animation fades in. One taken out goes at once, unless it carries a transition of its own.
- `.contentTransition(_:)` is read by each `Text` and image inside it, as in SwiftUI, rather than dissolving everything it wraps: an inner `.contentTransition(.identity)` now exempts its part, and a shape or colour under the modifier animates its own change instead of dissolving.
- On terminals whose Block Elements fill the line (all but Apple Terminal), a gradient or mesh that changes down a column draws each blank cell it fills as two samples, `▄` in the bottom half's colour over the top half's: gradient views, `.background(gradient)` behind blank cells and rectangle-family gradient fills. Copying such a region gives `▄` rather than spaces.
- A material (and glass) frosts what is behind it: the glyphs beneath are dropped and each cell takes the average of a box of its neighbours' colours before the tint is laid over, so text behind a material reads as a wash of colour rather than as letters. A thicker material blurs a larger box, as SwiftUI's do: 3 × 1 cells for `.ultraThinMaterial` up to 11 × 5 for `.ultraThickMaterial`; glass blurs as a material one thickness thinner. `.materialFrost(_:)` (TUI-specific) sets the box for a subtree: `.radius(columns:rows:)`, or `.none` for the glyphs dropped and nothing blurred. Over the page alone a material looks as before.
- `\.accessibilityReduceTransparency`, `\.accessibilityDifferentiateWithoutColor` and `\.colorSchemeContrast` follow the user: `TUI_REDUCE_TRANSPARENCY=1`, `TUI_DIFFERENTIATE_WITHOUT_COLOR=1`, `TUI_INCREASE_CONTRAST=1`, or the macOS (or GNOME high-contrast) setting where TUI is sure the session is local, as reduce motion does. Under reduced transparency materials and glass are opaque. `\.colorSchemeContrast` is no longer always `.standard`.
- A paste of any size now arrives whole. The earlier 16 MiB limit is gone.
- A popover attached with `.rect(.rect(_:))` that is wider than its rectangle starts where the rectangle starts, as a menu and a tooltip do, rather than centring on it: a link's destination popover inside a `Text` now lines up with the link as a `Link`'s does.
- A link inside a `Text` (from Markdown or an attributed string) is a control, as a `Link` is: Tab reaches it, Return or a click opens it and shows its destination in a popover, and Shift+F10 or a right-click opens `Link`'s menu. A page with inline links gains a Tab stop per link. Not where `.linkDisplay` writes the URL out, in a disabled subtree, or in a list's row.
- The status bar draws an item's one-letter key as a macOS menu draws it: `Q quit` for `"q"`, `⇧N` for an item on `"N"`, matching `⌃Z undo` beside it. The item's string still binds the key. `.statusBarKeySpelling(.asTyped)` draws the strings as typed, as before.
- ⌃Y redoes, the one redo key every terminal sends, except in a focused text field or editor, where it is still the yank. The status bar's and the menu bar's redo hint names ⌃Y, and another redo key while a text control has the focus.
- While a `List`, a `Table`, an open `Picker` drop-down or an open menu has the keyboard, its type select takes every bare character, the first of a prefix included. TUI's `q`, `t`, `a` and help key, an app's bare `.keyboardShortcut`, a menu row's bare key equivalent and a status-bar item's bare key no longer fire there, and the status bar leaves those items out meanwhile. Before, the first character of a prefix gave way to such a binding. A modified key, an F-key or the menu bar still reaches its command.
- Under the kitty keyboard protocol, a ⌘ chord the terminal lets through (kitty and Ghostty pass some) reaches `onKeyPress` with `.command` in its modifiers, where it was dropped. It reaches nothing that matches a bare key, so ⌘K types nothing into a field. A `.keyboardShortcut` written with ⌘ still fires on its `.commandKey(_:)` stand-in (Control by default), and on a real ⌘ as well only under the new `.keyboardShortcutsMatchCommand()`. `KeyEvent` has a `command` field.
- A hierarchical `Table(_:children:)` keeps its outline from frame to frame while its rows (the same array) and its open branches are the same, so a frame costs what a flat table's does: 1.66 ms where it took 41.8 ms at 20,000 rows (debug build). A file panel's list view is now an outline for a folder of any size, where one of more than 5,000 items was drawn flat.
- A paused drag activates a spring-loaded control after the user's spring-loading delay (System Settings ▸ Accessibility ▸ Pointer Control) where TUI is sure the user is at the machine the app runs on, and after half a second elsewhere, as before. `TUI_SPRING_LOADING_DELAY=0.3` (seconds) sets it for a run, and the new `.springLoadingDelay(_:)` sets it for a subtree. A `ColorPicker`'s well no longer spring-loads under `.springLoadingBehavior(.enabled)`, as SwiftUI's does not.
- A spring-loaded control a paused drag rests on draws as hovered while the pause runs, and as pressed for a tenth of a second as it fires, as macOS highlights it. A button style of your own sees it as `isHovered` and `isPressed`.
- A debug build stops (a `SoftTrap`) where a `Picker` leaves out a member of its content with no tag of the selection's type, and where an alert or confirmation dialog leaves out a `TextField`, `SecureField` or `Toggle` among its actions. SwiftUI shows both, so they were silent gaps. A release build reports each once and draws as before. Tag a picker's items with values of the selection's type.
- A list section's `.sectionActions` show only while the section is in use: the focused list's cursor is on one of its rows, the focus is on one of the actions, or the pointer is over the section. They were always shown, each a Tab stop. Tab from the list reaches the actions of the section the cursor is in. Hidden, their cells stay blank, so nothing moves as they come and go.
- An empty `List`'s or `Table`'s placeholder ("No items", or `.listEmptyPlaceholder(_:)`'s) is in the secondary ink and starts where a row's text would, no longer flush against the border.
- A `Stepper` with bounds reserves the width of the wider of its two ends, so ▶ no longer moves as the value gains a digit; a narrower value stands at the trailing edge. `.stepperValueWidth(_:)` sets the reservation (`0` for none).
- `Color.red`, `.blue` and the other named colours (all but `.white`, `.black` and TUI's `.magenta`) take Apple's dark values where they are drawn under a dark colour scheme, as SwiftUI's do: on a dark palette, and in a subtree pinned with `.environment(\.colorScheme, .dark)`. Most palettes are dark, so `.red` draws `#FF453A` there, not `#FF3B30`. What a body computes from one (`rgbComponents`, `opacity(_:over:)`, `mix(with:by:)`) still uses the light value. A named colour no longer equals the RGB it was (`Color.red != Color.hex(0xFF3B30)`), and it describes itself by name (`"red"`).
- A colour from an asset catalogue (`Color(_:bundle:)`, compiled catalogues included) and a dynamic `NSColor` (`Color(nsColor:)`) draw their light or dark variant by the colour scheme where they are drawn, as SwiftUI's do: the palette's, or a `.environment(\.colorScheme, …)` pin's, even when the colour was made outside the pinned subtree. Before, the variant was chosen when the colour was made, by the default palette's scheme. A body that measures one reads its light variant. Two variants that differ in opacity, or that are not plain colours, are still chosen when the colour is made, as is every new pair once a process has made 65,536 different ones. Such a colour no longer equals either variant's RGB, and describes itself by both (`"#CC6633FF light, #1080FFFF dark"`).

#### Since 23 October

What landed from 23 to 29 October that an existing app may notice, beyond the rename at the top and the lists above. Nothing here keeps an old spelling.

API, environment and requirements:

- **An app with no terminal says so and exits.** With stdout or stdin not a terminal, or `TERM=dumb`, `App.main()` used to enter the alternate screen anyway and sit there, writing escape codes down the pipe. It now prints one line to stderr and exits with status 1. An app with an alternate way of running implements `App.runWithoutTerminal(_:)`, which is told what is missing (`NoTerminal`) and returns an exit status, or `.drawOnControllingTerminal` to draw on `/dev/tty` while its pipes stay reachable, as `fzf` does.
- **`renderOnce` draws where the cursor is.** It no longer moves the cursor to the top of the screen and draws over what was there: it draws from the current line, gives the view the height it asks for rather than the screen's, and ends with a newline, so what the program prints next follows on. When stdout isn't a terminal it writes plain text. `renderOnce(output: .escapeSequences)`, `TUI_FORCE_ESCAPES` and `FORCE_COLOR` keep the escape sequences down a pipe, and `NO_COLOR` leaves the colours out (`RenderOnceOutput`).
- **⌃\\ asks before it quits.** It raised `SIGQUIT` at once. Where nothing of the app's takes it, it now puts up a dialog (Return or Escape stays; Tab then Return quits). Pressing it again while it's up quits at once, and a ⌃\\ at an app that doesn't read it within two seconds quits too, with the terminal restored; `kill -QUIT` never asks. While it is to ask, the app has the key rather than the driver, so the first ⌃\\ leaves the app's child processes alone and pasted text holding 0x1C no longer quits. `Scene.quitConfirmation(.whenWarned)` gives the key back, `.always` has ⌃Q and the menu's Quit ask too, and `View.quitWarning(_:isActive:)` has every quit ask and name what would be lost. `TUIApp` now links `TUIPresentation` for the alert.
- **Control-Q quits, not `q`.** A bare `q` was typed by a focused text field and searched for by a focused list, so an app could have no way to quit from where it opened. The status bar and the menu bar's Quit now say ⌃Q. For an app with nothing to type into, `statusBar.quitShortcut = .q` gives the old key back; `QuitShortcut.q` is still there. Raw mode already had flow control off, so ⌃Q reaches the app rather than being taken for XON.
- **`TUI_POINTER_SHAPES` takes `1`, `0` or `apps`.** `1` and `0` turn pointer shapes on or off whatever TUI detected; `apps` turns them on and keeps them to the app's own `pointerStyle(_:)`. The value `all` is gone: TUI's own shapes (the I-beam over a text field, the hand over a link, the resize arrows over dividers, column edges, grips and a sheet's grabber) are now on wherever the terminal takes shapes, where they were on only for iTerm2 or under `all`. `TerminalClient.pointerShapeSupport` still overrides the variable.
- **The pointing hand is over links only, by default.** A button no longer turns the pointer into a hand; a `Link`, a link inside a `Text` and a `.link`-styled button do, as on a Mac. `.pointingHandCursor(over: .everythingClickable)` gives the hand to everything that acts on a click, as a web page does (`PointingHandCursorScope`, `\.pointingHandCursorScope`). A view's own `pointerStyle(_:)` wins over either.
- **`import TUI` re-exports Foundation** (see "The umbrella still works").
- **The framework's working parts are no longer public.** 78 types and functions that only TUI's own modules use are now `package`, along with what names them: the stores (`StateStorage`, `RenderCache`, `AppState` and the like), the `*Modifier` wrappers behind the modifiers (`PaddingModifier`, `OverlayModifier`), the child helpers (`renderChild`, `measureChild`), `.onRenderPass`, `String.hyperlinked(to:)` and `TerminalQuirks.widthTraits`. The modifiers themselves are unchanged, and a custom view has every route in the Custom Views article: composition, `ViewModifier`, `BufferModifier` and `Renderable`, with `FrameBuffer` and `RenderContext`.
- **On macOS, TUI supports only an SDK from Xcode 26 or Command Line Tools 26 or later.** The macOS 15 SDKs (Command Line Tools 16.x) carry Swift 6.1's interfaces and are neither built nor tested.
- **The app's language is its scene's root `\.locale`.** `WindowGroup { … }.environment(\.locale, Locale(identifier: "de"))` now also sets the language of the words TUI reads where no view is drawing: the bars' labels, undo titles, clipboard notes. A scene that sets no locale is unchanged.
- **More words follow a subtree's `\.locale`**, where they were read once in the app's language: `Text(localized:)` of TUI's own keys, a `Button` titled from a key (TUI's own buttons among them), an `AlertPanel`'s title and message and its presets' titles, and the key-titled `.alert`, `.confirmationDialog` and `.dismissalConfirmationDialog` forms.

Keys:

- **Behind a sheet, an alert or another modal, only the modal's own keyboard shortcuts and status-bar items work**, as behind macOS's app-modal alert. A shortcut or status-bar item declared outside the view that presents the sheet used to show and fire behind it. The menu bar is drawn faint, as a disabled control is, while a modal holds the input.
- **Ctrl-U kills from the caret to the start of its line, and Ctrl-W kills the word before the caret**, in every text control, as readline does: each one undo step, kept for Ctrl-Y (a `SecureField` keeps nothing). Ctrl-U used to erase a field's whole text and do nothing in a `TextEditor`. An app's ⌘U or ⌘W, which arrive as these chords under `.commandKey(.control)`, comes first, as every Control or Command shortcut does over a text control's editing chord (select-all and the editor's Ctrl-A and Ctrl-E included); only the clipboard and undo chords stay the control's.
- **Ctrl-J (LF) is a key of its own.** A vertical `TextField` inserts a newline for it; where nothing takes it, it acts as Return, as before. Automation that sends LF to mean Return should send CR.
- **Under the kitty keyboard protocol, Ctrl-Return goes to the app first** (its key handlers and shortcuts, so an app's ⌘↩ fires under `.commandKey(.control)`), then opens a context menu on the focused view, then makes a vertical `TextField` insert a line break, and only then acts as Return. It used to be Return.
- **F10 enters the menu bar's bar mode.** It lights the first title and opens nothing, with every title's letter underlined; ↓, Return, Space or a title's letter opens a menu. F10 then ↓ is what F10 alone used to do.
- **View ▸ Customize Toolbar… is in the menu bar wherever the page shows a customizable toolbar** (`toolbar(id:)`), so F10, then View, reaches the customization panel from the keyboard. It needed `ToolbarCommands`, as on macOS; an app with a menu bar and a customizable toolbar but no `ToolbarCommands` now has a View menu holding it. With `ToolbarCommands` the menu still has one. A scene with no `commands` has no menu bar: the bar's right-click, or Shift+F10 on one of its items, opens it there.
- **Each menu-bar title has an Option letter of its own**: in bar order, the first letter of its title that no earlier title has taken, so two titles that start alike (File and Format) no longer share one. While a text control has the focus, a title whose letter the control edits with (Option-F, Option-B) takes its next free letter. Where the terminal reports Option held on its own, the letters are underlined while it is held.
- **Find (⌃F under the default command key) moves the focus to a `.searchable` view's field**, as ⌘F does in a Mac window. An app's own shortcut on those keys wins, and so do a text field's ⌃F (forward a character) and a `TextEditor`'s own find.
- **Where the terminal composes a character with Option** (Ghostty's default, under the kitty keyboard protocol: ⌥F arrives as `ƒ`), **the Option chord on its key still fires** when nothing takes the character: a menu's letter, ⌥? for every tooltip, ⌥⇧- for redo, an app's ⌥ shortcut. A focused text field still types the character, and a list's or a menu's type select leaves it to the chord.
- **Built-in controls register undo steps.** A person's change to a `Toggle`, a menu, segmented or radio `Picker`, a `Slider`, a `Stepper`, a `DatePicker` (its fields and its graphical calendar), a `ColorPicker`'s grids or a tone curve editor's stops is undone by ⌃Z and Edit ▸ Undo; a run of changes to a continuous control is one step. The app's own writes are not steps. SwiftUI's controls register nothing.

Pointer, drag and drop:

- **A control's action is drawn before the next input event is read.** A `.disabled(isSaving)` an action writes now stops a second press that arrived with the first, by keyboard, mouse or shortcut, as in SwiftUI, where a burst used to run the action twice. An alert or menu an action opens is what the next key reaches, too. Typing, arrow keys, scrolling, drags and pastes still batch. A key held on a button that stays enabled gets a frame per press, up to a quarter of a second behind.
- **A press released off a control acts on nothing.** A `Button`, a `Toggle`, a radio or segmented option, a link in a `Text`, a tab, a swatch, a status-bar item or a calendar day used to act on a release anywhere after its press. Now, as on macOS, a release elsewhere cancels it, and a button's pressed look follows the pointer off and back. A gesture attached to the control hears the press once the control's click fails.
- **Dragging a selected row of a `List` or `Table` with a `Set` selection carries every selected row**, in the container's order, as Finder does, and each destination is handed all the payloads in one call: a destination that expected one value per drop can now get several. Shift held as the drag starts extends the selection to the row first. From the keyboard, Ctrl-R on a selected row carries the whole selection too; Copy takes the focused row alone.
- **The preview of a selection's drag shows the grabbed row and a "+N more" line for the rest.** The new `.dragPreviewRowLimit(_:)`, on the `List` or `Table` or a view around it, lets up to that many of the carried rows ride the pointer, stacked in the container's order with the grabbed row still under the pointer, before the rest are counted; `nil` shows every row, and a limit below 1 is taken as 1.
- **Ctrl-R on a `.draggable` row of a `List` or `Table`, or on a `.draggable` tab, carries it from the keyboard** (it used to need the mouse), and Copy copies its payload. On such a row Ctrl-R always carries, as the pointer's drag does; where the list also accepts its own rows, the list is one of the carry's places, so Up and Down choose the landing slot and Return reorders. Rows without a drag keep the old keyboard move.
- **`.tabViewSearchActivation(.searchTabSelection)` goes back to the previous tab only when the search is dismissed**: when the field gives up the focus with nothing in it, as `dismissSearch` and Escape leave it. Tab from a field that holds a query into the search tab's results keeps the tab.
- **A drop's operation follows macOS's three-party model.** The source states what it allows with the new `dragConfiguration(_:)` (a copy by default; a list's, table's or sidebar's reorder is a move); a drop into the container the drag came from proposes a move and anywhere else a copy; the modifier the terminal delivers flips the two. A plain `dropDestination` now shows the + badge for a copy.

Drawing and layout:

- **A faint level is never invisible.** At 16 colours, a `foregroundStyle`'s `.secondary` and fainter levels that would land on their own background, or at full strength, are drawn in their own colour with SGR 2 (faint); at 256 colours such an ink steps toward full strength until the palette has an entry apart from the background. At 16 colours `.tertiary` and below drew as the page and `.secondary` as `.primary`. Truecolour is unchanged, and a layer's `.opacity` still fades to nothing.
- **A list separator with no `listRowSeparatorTint(_:edges:)` is fainter**: the border's ink faded half way into the page, where it was the border's own.
- **`.redacted(reason: .privacy)` masks text with ●**, as a `SecureField` masks its text, so hidden data no longer looks like a loading placeholder (░). Where both reasons apply, the placeholder wins. SwiftUI draws both alike.
- **A `.graphical` `DatePicker` draws the weekend in the secondary text colour**, its days taken from the environment's calendar (Friday and Saturday in Saudi Arabia). `.datePickerDistinguishesWeekends(false)` turns it off, and `.datePickerDistinguishesPastDays()` draws the days before today faint.
- **A column shares an overfull height by flexibility**, as SwiftUI's does: children of one layout priority each give up room, where the leading ones took their height and the trailing ones were cut. A `Table` reports a flexible height, as a `List` does, so it takes the share it is offered and scrolls the rest; one whose rows fit still hugs them.
- **A column that has room for all its children keeps each at its natural height**, and only views that grow share what is left; the flexibility rule above applies only once the column is overfull. A column beside a view that fills any height was shrunk, and a `ScrollView`'s content cut (the Example's Colors page lost its mesh gradient).
- **Lengths an app states are held to 65,536 cells.** A frame, padding, offset, position, spacing, a `Spacer`'s minimum, a grid's or a table's widths past that, and NaN or infinite values, used to trap or build strings of billions of blanks. A negative stack `spacing` overlaps the neighbour, as SwiftUI's does.
- **A negative `padding` works as SwiftUI's does.** The view reports a frame that many cells smaller on each edge (never below zero), its content is offered that many more and is drawn at its full size past the frame: over the views before it, under the views after it. `Text("Hello").padding(.horizontal, -1)` is three columns wide and draws all five letters. A negative inset used to trap.
- **A bare `Button` in a `Form` goes where SwiftUI's does**: in a `.columns` form's control column, and at a `.grouped` form's row's leading edge. It stood at the trailing edge; `.formRowAlignment(.trailing)` gives that look.
- **A background on a bordered view reaches the border's line.** `.background(m).border()` left the blank cell TUI keeps inside the line unfilled; `.backgroundStopsAtContent()` keeps it clear.
- **A focus section's breathing ● is drawn only by a border around the whole section**, no longer by each bordered view inside one.
- **A dialog's footer is laid out across its whole inner width**, so an alert's buttons stand as far from the right border as from the left, where they stood two cells further in. The "Do not ask again" toggle is centred over the buttons, with a blank row between.
- **A circular `Gauge` centres its value in the ring** (`│ 7% │`), by its figures: a sign or a unit hangs outside them, and where the range goes below zero a minus's cell is kept so the figures stand still. Its label is centred under the ring. The value was right-aligned.
- **A stated `.tint` colours gauges and progress bars**, and `.tint` takes any `ShapeStyle`: a gradient runs along a bar or around a ring. With no tint they keep their quiet secondary ink.
- **Glass and materials stay frosted in an inactive window**, their surface half way to opaque, where they went flat, and a tinted glass greys toward a quarter of its colour rather than brightening.
- **Under a scroll target behaviour, an "N more" line with nothing past it is blank** rather than "▲ 0 more". Under `.paging`, the pair comes and goes over content that does not size itself against the scroll view, so each page starts on the line after the last one read; over a `scrollTargetLayout` whose rows are taller than a line, a page never cuts a row, but leaves it blank and starts the next page on it.
- **A later view shows an unclipped scroll view's overflow through the blank cells between its words**, as SwiftUI shows it between its glyphs, where it hid the overflow from its first painted cell to its last on each line.
- **A `Tab` whose label is a view of its own draws that view whole in its chip**, several rows tall if it is, where only its first line was taken as text.
- **`TrackStyle.threeSegment`'s background pattern stays put as the fill grows**, laid from the track's first cell, where it was laid again from wherever the fill ended.

Pictures:

- **A picture keeps its own aspect at every size.** `.scaledToFit()`, and a picture at its natural size, letterbox within the cell box (up to half a cell shows the page); `.scaledToFill()` crops to the box; `.resizable()` with no aspect ratio stretches. Each used to be stretched slightly to the box's aspect, differently at each size.
- **A picture file of up to 256 KB draws on the frame that first shows it**, as SwiftUI's `Image` of a local file does, where it showed a placeholder while a task decoded it. `.imageSynchronousDecodeLimit(_:)` sets the size in bytes, `0` for every file in a task. A picture another view has already shown draws at once, whatever the size of its file.
- **Braille in colour paints each cell's background** in the average of its unlit pixels, so tones below the threshold no longer vanish into the page. Shape-aware glyphs ink a cell by its brightness, as the character ramps do, where a white ground drew black.

Fixes an app may have worked around:

- **A long list of pictures holds at most the image cache's bytes of pixels** (64 MiB unless `.urlImageCache(_:)` gives another). A row keeps its state for as long as its list lives, as in SwiftUI, and that state used to hold the row's decoded picture, so every picture a list had ever drawn stayed in memory. A picture loaded from a file or a URL is now kept by the cache, and its view holds it only while drawn. One drawn again after the cache let it go loads again: a small file on that frame, as before; a larger file or a URL in a task, the row showing what it last drew meanwhile (its placeholder, where the terminal drew it as a picture). A picture made from pixels in memory is kept by its view, as before.
- **The app's own image cache can be given another bound without code**: `TUI_IMAGE_CACHE_SIZE=256M` (bytes, or KiB, MiB or GiB with a `K`, `M` or `G` suffix; `0` keeps nothing). In code, an app hands its views a cache of its own with `.urlImageCache(_:)`, made once (a `let` on the `App`, or `@State`), not in a `body`, which would make a new, empty one on each evaluation.
- **An app that calls `exit()` hands the terminal back** (raw mode, the alternate screen, the cursor, mouse reporting, the kitty keyboard flags) as a quit does; so does a stack overflow in a frame, and resuming after an external `SIGSTOP` takes the terminal back as resuming after ⌃Z does. Quitting puts xterm's `modifyCursorKeys` back to its initial value, where it set it to 0.
- **`TimelineView(.periodic(from:by:))` with an interval of 0, below 0 or NaN gives one entry** instead of stopping the app, and one too long or too short for the date to move ends its entries instead of hanging. Animations, timelines and notifications take any duration without trapping.
- **A picture file that is a named pipe or a device is refused** rather than opened, which froze the app waiting for a writer.
- **An `Image` whose source changes is laid out at the new picture's size on that frame.** A viewer stepping from one photo to the next drew each new one in the last one's box for a frame, then snapped it to its own.
- **An `.offset` view that comes or goes with a transition moves and stays in place as it should.** Under `.move` or `.offset` its picture stood still where it ended and a blank box of its size was drawn where it was laid out; under a fade, an overlay that centred it drew it half its width aside until the fade was over (a toast `.offset` into place and moved in from the bottom jumped sideways as it settled).
- **A focused toggle's breathing no longer flickers in Ghostty**: every frame that draws a row now holds the terminal's display (synchronized output), one row included.
- **A `@FocusState` set before its control has registered focuses the control when it does**: `.onAppear { field = .email }` on a view that has just appeared takes the focus from another control, as in SwiftUI. The write was dropped.
- **A write made outside an event (a timer, a `Task`, a network reply) asks for a frame** when what it changed was read only by a top-level control's `Binding`, a custom style's `makeBody` or the app's body. The control used to show the old value until something else drew.
- **Where several views hold one object, an `@Environment` the object reads in a closure** (a key or mouse handler, a gesture's callback, a `.task`) is the environment of the view the closure runs for, where it was the first holder's: a sheet sharing its page's object now dismisses the sheet. Timers, detached tasks and hover handlers still read the first holder's.
- **A URL image answered with a failure status fails as a download.** A 404's page used to go to the decoder, which reported `ImageLoadError.decodingFailed`; it is now `.downloadFailed`, naming the status, even when the response's body is a picture.

#### Since 29 October

- **`List(data, selection:)` takes a selection of any type**, as SwiftUI's does, in every form: `Identifiable` data, an `id:` key path, a `Range<Int>`, a tree (`children:`), a binding to a tree or to editable data (`editActions:`), and the non-optional selection. A row's value for the selection is its `.tag(_:)` or link value, else its element's `id` where that is of the selection's type. One source change: `List(items, selection: nil) { … }` can no longer infer a selection type from the `id`, as in SwiftUI; write `selection: nil as Binding<MyID?>?`, or leave the argument out.
- **A `NavigationLink(value:)` names its row in a selecting `List`**, so `List(categories, selection: $category) { NavigationLink($0.name, value: $0) }` selects with Return, Space or a click and a `NavigationSplitView`'s next column switches. Such a row draws the link as its label, with no button and no Tab stop. In a `NavigationStack`, selecting the row also follows its link.
- **Return or Space on a `List`'s cursor follows a `NavigationLink` in that row**, in a list with no selection, with no Tab to the link first. The link keeps its button there, and Tab still reaches it.
- **A row of a windowed `List` whose tag or link value says nothing for the selection, after row 0 said something, no longer stops the app.** It draws and selects nothing.
- **The geometry of a custom `Layout` fits together.** `LayoutSubview.place(at:anchor:proposal:)` takes a `CellPoint`, such as `bounds.origin`, beside its tuple; `CellSize.zero` and `ViewSize.zero` exist; `ProposedSize(_:)` makes a proposal of a `ViewSize` or a `CellSize`, and `ProposedViewSize` is SwiftUI's name for `ProposedSize`. `ViewSize` and `CellSize` stay apart, since a `ViewSize` also says which axes can grow, and `CellSize(_:)` and `ViewSize(_:)` convert.
- **`.overlay(.red)` takes a style with no `in:`**, as `.background(.red)` does, filling the view's frame.
- **`.refreshable`'s action inherits the actor it is written on**, as SwiftUI's does. Written in a `body` it can write `@State`, and it runs on the main actor, so long synchronous work belongs in a `Task` of its own or a `nonisolated` function.
- **`onAppear(perform:)` and `onDisappear(perform:)` take an optional closure, defaulting to none**, as SwiftUI's do.
- **Controls show their state without colour.** At `.noColor`, however it was reached, most controls showed neither the focus nor being disabled. The focus is now reverse video, on a button's or tab's face, a toggle's or radio option's label, a stepper, a slider's arrows or a link. A disabled control is faint. A text field's caret, its selection and its prompt each show, where the first two were invisible and the prompt read as typed text. A scroll bar's thumb is a shade glyph, where it was invisible, and it turns solid with the focus. A radio option's ● no longer also means focus there, which made it look selected. An indeterminate `ProgressView` in `.pulse` or `.gradient` sweeps, where it stood still. A gradient drawn as a picture goes back to cells at `.noColor`, and a list's hairlines go. An `Image` keeps its pixels.

### Removed deprecated spellings

The project removes SwiftUI API that SwiftUI itself has deprecated, and does not add it. The spellings real code uses most, and the modifiers a terminal can't honour, now get a compile error saying what to use instead (`'cornerRadius(_:antialiased:)' is unavailable: A cell has square corners...`), on the line that used them, in under a second. They were 10 to 20 seconds of "unable to type-check this expression" at `var body`. They don't appear in code completion or the documentation. These went:

- `Text + Text`, deprecated in SwiftUI on macOS 26. An interpolated `Text` keeps its fragments' styling, which replaces it.
- `UnitCurve.easeInEaseOut`, renamed `easeInOut` in SwiftUI.
- `WindowGroup.init(content:)`, replaced by `init(makeContent:)`. A call written `WindowGroup { ... }` binds either.
- The `CoordinateSpace`-enum overloads of `GeometryProxy.frame(in:)`, `onTapGesture(count:coordinateSpace:perform:)`, `onContinuousHover(coordinateSpace:perform:)`, `DragGesture.init` and `SpatialTapGesture.init`. They are internal now. The `some CoordinateSpaceProtocol` forms are public, and `.local`, `.global`, `.named(_:)` and `.scrollView` bind to them.

Deprecated SwiftUI spellings TUI still has, on purpose:

- The soft-deprecated `dropDestination(for:action:isTargeted:)`, until the drag-session work.
- The catch-all `Text("... \(anything)")` string interpolation, deprecated as SwiftUI deprecates it on the macOS 26 SDK: it compiles and warns.
- The `.roundedBorder` and `.squareBorder` text field styles, which SwiftUI deprecates in macOS 27. TUI's parity baseline is the macOS 26 SDK.

`Tools/APIParity/api_parity.py --deprecated` lists the SwiftUI declarations deprecated on macOS that TUI still implements (23 against the macOS 26.2 SDK). Most are cases where TUI has the live overload and SwiftUI's deprecated one shares its name.

### Concurrency

The compiler now checks what `@unchecked Sendable` used to assert. If your code stops compiling, it was relying on one of these:

- `EnvironmentValues`, `DropInfo`, `ToolbarItemPlacement`, `ToolbarPlacement` and `RenameAction` are not `Sendable`, as SwiftUI declares them not to be. Their built-in placements are computed, so `static let favorites = ToolbarItemPlacement.accessoryBar(id: "f")` of your own needs to be a `static var`, as it does on SwiftUI in Swift 6 mode. So are `PreferenceValues`, `ThemeManager`, `FocusManager`, `StateStorage`, `RenderCache`, `TUIContext`, `TooltipState`, `StatusBarState`, `StatusBarItem`, and `RequestAttentionAction`, and an `EnvironmentKey`'s default of one of them has to be computed.
- `GestureState` is no longer `Sendable`, where SwiftUI's is `@unchecked` when its value is. It holds a `State`, which never was.
- `Focusable.handleKeyEvent(_:)` and `MouseEventDispatcher.dispatch(_:)` are `@MainActor`, where the run loop always called them.
- An animation completion is `@MainActor`. `withAnimation(_:completionCriteria:_:completion:isolation:)`, and `withTransaction(_:_:isolation:)`, have a defaulted `isolation:`, so a completion can run at once where the caller is on the main actor; elsewhere it runs as soon as the main actor can take it. A closure literal compiles as before. A completion held in a variable is written `{ done() }`.
- `Lock` is built on `Mutex`, and is no longer re-entrant anywhere, as it was not on macOS. On macOS re-entering one ends the process with a SIGKILL.
- `CustomPresentationDetent` refines `SendableMetatype`.

### Dependencies and requirements

- Swift: `swift-tools-version: 6.2`. The README says Swift 6.2 or later. CI builds with Xcode 26 and 27 on macOS and with Swift 6.2, 6.3 and 6.4 on Linux. The tools version is unchanged by the split. On macOS the SDK must be Xcode 26's or Command Line Tools 26's or newer; the macOS 15 SDKs are not supported.
- Platforms: macOS 15 or later (`.macOS(.v15)`, raised from macOS 14: a package below it gets SwiftPM's "requires macos 15.0" error, and adding the line, or raising it, is the fix), and Linux (no platform declaration needed). The package also builds for `wasm32-unknown-wasip1` (the README describes a browser build of the Example app). On Windows, the four lowest modules (`TUICore`, `TUIStyling`, `TUIView`, `TUIImage`) build, and the rest do not yet.
- **swift-docc-plugin** (from 1.4.3): documentation. No target uses it.
- **swift-syntax** (`602.0.0` up to, not including, `700.0.0`): added for the compiler plugin behind `TUIMacros`. It is built only for an app that depends on that product. Every client still resolves and fetches it, because SwiftPM resolves by package. The range is wide so that TUI does not refuse an app whose other packages want a newer swift-syntax. SwiftPM uses a prebuilt swift-syntax only where one is published for the version and toolchain: 602.0.0 on Swift 6.2, and 604.0.0 on swift.org's Swift 6.4.0 on macOS. An app on Swift 6.2 that wants prebuilts can pin `exact: "602.0.0"`.
- **swift-collections** is no longer a dependency. TUI used its `UniqueDeque` for input buffering. Linking swift-collections' `DequeModule` pulled in a reference to `libswiftCompatibilitySpan.dylib`, which macOS has only from version 26, so a release program copied out of `.build` failed at launch on macOS 14 and 15. `TUIApp` now has its own input buffers. If your own program uses the standard library's `Span` types or links swift-collections 1.4 or later, see [Building and Shipping an App](https://swift-tui.com/docs/documentation/tui/shippinganapp) for what to ship.
- `ordo-one/benchmark` is added only when `TUI_BENCHMARKS` is set in the environment.
- The repository no longer tracks `Package.resolved`. SwiftPM never read a dependency's pins, so nothing changes for an app.
- The `tuikit` project generator (`project-template/`, installed with `curl … | bash`) is removed. A new app needs only the two lines of `Package.swift` that the README's "Getting started" gives, and the README's sample is a whole app. A `tuikit` command already installed goes on working, as it was; nothing will update it.

### Highlights since the split

- A menu bar. A scene that declares `commands` gets a menu bar on the window's top row, with `CommandMenu`, `CommandGroup`, the standard command sets, and TUI's own app, File (Close and Close All, for an app that can have more than one window), Edit, View, Window and Help menus. Menus open by click, by F10 and the arrows, or by Option and a title's letter. As on a Mac, a press on a title dragged down its menu runs the item it is let go on, and with one menu open the pointer on another title opens that title's. About shows the app's name, version, credits and copyright, as the scene's `aboutPanel(applicationName:applicationVersion:version:copyright:credits:)` or the bundle's Info.plist states them. Help ▸ Show Tooltips turns tooltips off and on, and Show All Tooltips (⌥?, or Shift-F1 on any terminal) shows every one on the screen at once. TUI's own `DisplayCommands()` adds View ▸ Palette, Border Style and Control Style, each a submenu of the built-in choices: it chooses through the app's palette and appearance managers and a new control style manager (`\.controlStyleManager`), disables a submenu whose value the scene sets itself, and writes the app's own state instead where it is given a binding (`DisplayCommands(palette:appearance:controlStyle:)`).
- Several scenes and windows. A body can declare more than one scene. `openWindow`, `dismissWindow`, windows presenting data, a `Settings` scene shown as a sheet (`openSettings`), `AlertScene`, per-window `@SceneStorage`, and the terminal's title following the window in front.
- Toolbars. SwiftUI's `.toolbar` places items in the top and bottom bars by placement. Window toolbar styles, accessory bars, title menus, `toolbar(id:)` customization from a panel, and tab view sidebar toolbars. While the Customize Toolbar panel is open, the bar's customizable items are dragged in the bar to move them, or off it to take them out (in macOS's puff of smoke), and each of the panel's rows has a grip to drag it into place.
- File panels. `fileImporter`, `fileExporter`, `fileMover` and the `fileDialog` modifiers present open and save panels that TUI draws, in the new `TUIFilePanels` module. Each item is drawn after an icon of its kind; `fileDialogIcon(_:)` draws an app's own instead, and `fileDialogSystemIcons()`, from `TUIFilePanelsAppKit`, the Finder's, where the terminal draws pictures. A panel browsing a machine the user is not at (over ssh or mosh, or from a tmux client attached from one) says so in a line above the path, which `fileDialogRemoteNotice(_:)` hides.
  - The path is a segmented path control, a segment per folder, after a ↰ button to the enclosing folder.
  - The list view is an outline: → opens a folder in place, ← closes it, Backspace goes up. A switcher beside the path chooses it or a column view, as Finder's, and the choice is kept per app (per `fileDialogCustomizationID(_:)` where one is set). In the column view → opens a folder, and going up keeps the way back down beside the folder come from.
  - A preview pane shows the item selected: behind a splitter in the list view (open by default where the panel is wide enough, and kept as chosen), and as a column of its own in the column view. It shows a text file's opening lines and the item's name, kind, size and date, with an app's own view above them from `fileDialogPreview(_:)`, or a picture under `fileDialogPicturePreviews()`, from `TUIFilePanelImages`.
  - A panel with more than one type has a pop-up of them, Show to open and Format to save; `fileDialogContentTypePicker(_:)` shows or hides it.
  - A save panel, and one that chooses a folder, has New Folder (or `+` in the folder).
  - Finder's chords, written with ⌘ and resolved through the command key (⌃ by default): ⌘2 and ⌘3 for the views, ⇧⌘P the preview, ⌘↑ and ⌘↓, ⇧⌘G to go to a folder, ⇧⌘H, ⇧⌘D, ⌥⌘L, ⇧⌘O and ⇧⌘A for the home, Desktop, Downloads, Documents and Applications folders, ⇧⌘N New Folder, ⇧⌘. hidden files and ⌘. cancel. The status bar names only those the terminal can send.
  - Two TUI-only `fileExporter` forms save on every platform, Linux included, where SwiftUI's take a `Transferable` or a `FileDocument`: `fileExporter(isPresented:contents:contentType:defaultFilename:onCompletion:onCancellation:)` takes `Data`, a `String` or a type of the app's own (`FileExportContents`), and `fileExporter(isPresented:encoding:contentType:defaultFilename:onCompletion:onCancellation:)` any `Encodable` value, written as JSON or a property list.
- Shapes and paths. Shapes are views, drawn in box glyphs or rasterized, with `Path`, container shapes, and shapes as backgrounds, overlays, clips and hit areas. `mask(alignment:_:)` keeps a view's cells where another view draws (`gradient.mask { Text(…) }` draws gradient text), and `drawingGroup(opaque:colorMode:)` blends in linear light inside the group under `ColorRenderingMode.linear`.
- Materials, glass, shadows and blend modes. Materials as translucent surfaces, `GlassEffectContainer` that joins glass, drop and inner shadows (animatable), `View.blendMode`, `ShapeStyle.blendMode`, and image paints. A material or glass over a terminal picture frosts the picture itself, and `.materialFrostResolution(_:)` (TUI-specific) draws that frost at more of the terminal's pixels: `.native`, or `.downsampled(by:)` a factor.
- Animation. Branch fades, matched geometry, the zoom navigation transition, `.blurReplace` (its scale and a fade, the blur drawn as the fade), `CustomAnimation`, animations that carry their motion when interrupted, and stacks whose children glide when a view comes or goes. A grid's cells glide when its lattice changes, a view leaving a `Layout` gives its room back at once while the others glide over it, a strikethrough changed under an animation is drawn along its text and taken back, and a navigation zoom scales and moves the terminal pictures it reveals or folds away.
- Scrolling. Scroll target behaviours (`.paging`, `.viewAligned`), bound scroll positions that `List` and `Table` follow, and horizontal scroll fixes. `.scrollIndicatorPlacement(.overContent)` (TUI-specific) takes no room for the indicators and draws them over the content's edge while the pointer is over a `ScrollView`, `List`, `Table` or `TextEditor` whose content overflows, and beside the content, as `.besideContent` draws them, while the view has the focus; `.besideContent`, the default, keeps them in room of their own.
- Pictures. Each cell's background in coloured braille, `.imageInkThreshold(_:)` to state where braille's dots and a mono picture's ink begin (measured from the picture by default), `.imageAdjustments(_:)` (`ImageAdjustments`: exposure, black point, highlights and contrast), and `.imagePosterization(levels:)`, which reduces each channel to a few levels and gives `.imageDithering(_:)` something to spread in true colour, all TUI-specific. A terminal picture that changes is swapped in one held update without a blank frame, and one at rest is sent again at its box's exact size. A terminal picture faded with `.opacity`, recoloured by a colour effect, under glass or behind a modal draws a changed copy of itself instead of being left as it was or blanked.
- Lists, tables and navigation. SwiftUI-shaped `Table` columns, `OutlineGroup` over a binding to a tree, `sidebarAdaptable` tab views with a customizable sidebar, `HSplitView`, `VSplitView` and the inspector, and compact-size adaptation for popovers, tables, split views and tab bars (`tabBarMinimizeBehavior`). A list row's `swipeActions(edge:allowsFullSwipe:content:)` are revealed by ⇧→ and ⇧← (or ⌃L and ⌃T, rebindable as `RowAction`s), again for the full swipe, or by a sideways swipe where the terminal reports one as the horizontal wheel. An `HSplitView`'s or `VSplitView`'s divider takes Home and End.
- Drag and drop. A focused `.draggable` copies its payload with Copy and a focused drop destination takes it with Paste, and Ctrl-R picks a `.draggable` up to carry it from the keyboard: Tab and the arrows move among the places that accept it, each marked ‹, Return drops it, Space flips copy and move, and Escape puts it back.
- Search. `tabViewSearchActivation(_:)` with `.searchTabSelection` (SwiftUI's `TabSearchActivation`) moves the focus to the search field when a `Tab(role: .search)` is selected, and selects the tab before it again when that search ends. Find (⌃F) reaches a `.searchable` field from anywhere in its view.
- Controls. A radio group's option can be disabled alone (`RadioButtonItem.disabled(_:)`). A `.graphical` `DatePicker` tells the weekend and, where asked, past days apart. A slider's fill from its neutral value starts within a cell under `.blockFine`.
- Control sizes. Text fields, sliders, steppers and segmented pickers follow `controlSize` from mini to extra large, and a bare picker, slider or stepper in a `Form` is a field row.
- Text. `AttributedString` runs, `Text` that keeps its styling when interpolated, Markdown in control titles, underline patterns and colours, and `MeshGradient`. SwiftUI's `TextRenderer` (`View.textRenderer(_:)`, `TextProxy`), `Text.Layout` with its lines, runs and glyphs, `Text.customAttribute(_:)` and the part of `GraphicsContext` that text needs, in cells: a renderer redraws a text from its layout, glyph by glyph, and is interpolated under an animation. TUI adds `GraphicsContext.drawSubstituting(_:for:options:)`, which draws a glyph as another character, and `textAttributes` for bold, italic, underline and the rest per glyph. Inline Markdown reaches everything a `Text` can do to its words, through Apple's `^[text](key: value)` syntax with TUI's own keys (colours, underline and strikethrough styles and colours, font, weight, dim, blink, inverse and text scale), decodes all 2,125 of HTML's named character references, and reads link reference definitions as Foundation does.
- Text input and undo. Typing is grouped into undo steps as macOS does, Ctrl-Z and the undo and redo keys, Option-drag block selection in `TextEditor`, and content-type filters. `TextEditor`'s find bar (`findNavigator`) opens with Ctrl-F, finds the next match with Ctrl-G, tints every match and has macOS's options; the wheel scrolls an editor and a capped vertical field; a search field shows a ✗ that empties it. Selected text dragged elsewhere in a `TextEditor` moves there, as one undo step. A caret at a soft wrap leans to the end of the earlier row or the start of the later one as macOS's does, by the key or click that put it there.
- Screen selection. A drag selection's highlight keeps to the text it crosses: each `Text` it crosses lights its own frame, so a card's padding, the blanks past a short line and the gap between two texts side by side stay unlit. What is copied is unchanged.
- Tasks. SwiftUI's `task(name:priority:file:line:_:)`, `task(id:name:priority:file:line:_:)` and `task(name:executorPreference:priority:file:line:action:)`, which name the task they start.
- Terminal integration. Pointer shapes (`pointerStyle`, and TUI's own over its controls, with the hand placed by `pointingHandCursor(over:)`), a progress bar on the terminal's tab (`.terminalProgress`), desktop attention notifications, OSC 52 and OSC 5522 clipboard with HTML, RTF and images, and the kitty keyboard protocol. `\.terminalCapabilities` tells an app what the terminal can do, feature by feature (curly underlines, pictures, links, key releases, Option as Meta and more), as supported, unsupported or undetermined, so a page can say "this terminal does not draw that" only where it is true.
- Platforms. GNOME Terminal (VTE) is recognized and compensated for, and there are fixes for Linux and WebAssembly (WASI).
- Macros. The `TUIMacros` product adds `@Animatable`, `@AnimatableIgnored` and `@Entry`.
- Documentation. A "Choosing Products" article, a generated "Which Module Provides It" page, and CI that builds one small app for each library product.
