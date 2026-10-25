# Changelog

TUIkit has no tagged releases yet and is pre-1.0. Public API can change in any commit, and the project deletes deprecated or superseded spellings outright instead of keeping compatibility shims.

## Unreleased

These notes cover the change from the single-module package (a `TUIkit` target plus `TUIkitCore`, `TUIkitStyling`, `TUIkitView` and `TUIkitImage`, as of 1 October 2026) to current `main` (23 October 2026). The module split itself landed between 8 and 19 October. If you were already building against a commit from after 8 October, skip the parts that describe things you already have.

### If you only need the short version

- If your target depends on the `TUIkit` product and writes `import TUIkit`, it still compiles the same framework with the same names. Nothing about the split forces a change.
- Check the "Upgrade-affecting changes" list below. The ones most likely to bite are the renamed resource bundle, the opt-in status bar and toolbars, the AppKit bridges that need `import TUIkitAppKit`, and the removed spellings.
- If you want a smaller app, depend on the module products you use instead of `TUIkit`.
- Two package traits are on by default and change how your macOS release build is linked. They are described below, with the opt-outs.

### The module split

TUIkit is now 30 library products. Before, there were five (`TUIkit`, `TUIkitCore`, `TUIkitStyling`, `TUIkitView`, `TUIkitImage`).

#### The umbrella still works

- `import TUIkit` is the whole framework, as `import SwiftUI` is SwiftUI. The `TUIkit` module declares nothing itself. It re-exports every other module except `TUIkitAppKit` and `TUIkitMacros`, which you import separately.
- Qualified names such as `TUIkit.Label` or `TUIkit.ColorPicker` still resolve, through the umbrella's re-exports. The test suite pins this for types from many of the modules.
- `TUIkit` is still the right default for an app. The README and the docs assume it.

#### Depending on fewer modules

- Each module an app might want alone is a library product with the module's own name. List the products you use in your target's `dependencies:` and import those modules.
- SwiftPM compiles and links the products your target lists, plus what they are built on. Your `import` lines decide only which names your files can see. A target that depends on `TUIkit` and imports only `TUIkitTables` still builds and links all of TUIkit.
- Every app needs `TUIkitApp` (`App`, `Scene`, `WindowGroup`, the run loop and the terminal). Add the product of each module whose names you use.
- Each module re-exports the modules it is built on, so `import TUIkitTables` also gives you `List`.
- Measured on a hello-world app with Swift 6.4.0, stripped, default traits: `TUIkit` is 9,241,968 bytes. `TUIkitApp` alone is 5,751,768 bytes (-37.8%), compiling 8 TUIkit modules instead of 25.
- If you forget a product, the compiler says `cannot find 'Table' in scope` or `value of type 'Text' has no member 'tableStyle'`, and does not name a module. The documentation has a "Which Module Provides It" page that lists every public name with its module and product.
- Mixing `TUIkit` with module products in one app is safe. Each module is linked once.
- If you write a library on top of TUIkit, depend on module products (or `TUIkitFoundation`), never on `TUIkit`. Anything in an app's graph that depends on `TUIkit` gives that app the whole framework.
- Do not build a `.dynamic` library product from TUIkit's modules while an app also links a TUIkit product statically. SwiftPM's own build system gives the app two copies of the shared modules. Swift Build makes them dynamic libraries the app must ship.
- Module and product names are now part of what you depend on. Before 1.0, types can move between modules, and a `Package.swift` that lists a module changes if that module is renamed or split. An app on `TUIkit` never sees such a change.

```swift
.executableTarget(
    name: "YourApp",
    dependencies: [
        .product(name: "TUIkitApp", package: "TUIkit"),
        .product(name: "TUIkitTables", package: "TUIkit"),
    ]
)
```

```swift
import TUIkitApp
import TUIkitTables
```

#### The products

Foundation and app:

- `TUIkit`: the umbrella. Everything below except `TUIkitAppKit` and `TUIkitMacros`.
- `TUIkitApp`: `App`, `Scene`, `WindowGroup` and the scene modifiers, the run loop, the terminal (POSIX only), and `renderOnce`. Re-exports `TUIkitChrome` and `TUIkitFoundation`.
- `TUIkitFoundation`: what everything else is built on: `View`, `Text`, stacks, `ScrollView`, `Button`, `Toggle`, `Label`, `Image(systemName:)`, layout, state, the environment, focus and rendering. It cannot run an app on its own. It re-exports `TUIkitCore`, `TUIkitStyling`, `TUIkitView`, and two modules that have no product of their own: `TUIkitStrings` (localization, string tables, SF Symbols names, the resource bundle) and `TUIkitTerminalHost` (the terminal's identity, quirks and capabilities).

Feature modules:

- `TUIkitBitmaps`: `Image` from a file, URL or bundle, `AsyncImage`, the `.image*` options. Re-exports `TUIkitImage`.
- `TUIkitChrome`: the `StatusBar` view, toolbars, notifications, tooltips and `.help`. `TUIkitApp` and `TUIkitPresentation` re-export it.
- `TUIkitColorPicker`: `ColorPicker`, `ColorPickerPanel`, `GradientEditorPanel`.
- `TUIkitCommands`: `Commands`, `CommandMenu`, `CommandGroup` and the placements, and the menu bar they draw. Re-exports `TUIkitApp` and `TUIkitPresentation`.
- `TUIkitCurveEditors`: the tone-curve and channel-curve editor panels.
- `TUIkitEffects`: transitions, content transitions, `.symbolEffect`, `.visualEffect`, `.scrollTransition`, matched geometry.
- `TUIkitFilePanels`: `fileImporter`, `fileExporter`, `fileMover`, the `fileDialog` modifiers, and the open and save panels.
- `TUIkitForms`: `Form`, `LabeledContent`, `GroupBox`, `Card`, `Panel`.
- `TUIkitGrid`: `Grid`, `GridRow`, `LazyVGrid`, `LazyHGrid`.
- `TUIkitLists`: `List`, `OutlineGroup`, `EditMode`, list styles and row modifiers.
- `TUIkitMenus`: `Menu`, `ControlGroup`, `.contextMenu`, menu styles.
- `TUIkitNavigation`: `NavigationStack`, `NavigationPath`, `NavigationLink`, split views, the inspector.
- `TUIkitNumericControls`: `Slider`, `Stepper`, `Gauge`, `ProgressView`.
- `TUIkitPickers`: `Picker`, `RadioButtonGroup`, `DatePicker`.
- `TUIkitPresentation`: `alert`, `confirmationDialog`, `Dialog`, `sheet`, `fullScreenCover`, `modal`.
- `TUIkitScenes`: the `Settings` scene (shown as a sheet) and `AlertScene`.
- `TUIkitSearch`: `.searchable`, search tokens and scopes, `searchSuggestions`, `dismissSearch`.
- `TUIkitTables`: `Table`, columns, rows, styles, row drag and drop. Re-exports `TUIkitLists`.
- `TUIkitTabs`: `TabView`, `Tab`, `TabSection`, tab styles. Re-exports `TUIkitLists`, and `TUIkitPresentation`, whose sheet a tab's popover becomes in a compact size class.
- `TUIkitTabImages`: `Tab(_:image:…)`, the tabs whose picture is an image resource named by a string. Re-exports `TUIkitBitmaps` and `TUIkitTabs`, and is a product of its own so that an app showing images pays nothing for tabs, and one using tabs nothing for image decoding.
- `TUIkitTextInput`: `TextField`, `SecureField`, `TextEditor`.

Opt-in (not in the umbrella):

- `TUIkitAppKit`: `Color(nsColor:)`, `NSColor(_:)` and `Image(nsImage:)`, and compiled asset catalogue reading. Apple platforms only; empty elsewhere.
- `TUIkitMacros`: the `@Animatable`, `@AnimatableIgnored` and `@Entry` macros.

Low-level, as before:

- `TUIkitCore`, `TUIkitStyling`, `TUIkitView`, `TUIkitImage`. These four build on Windows. `TUIkitView` and `TUIkitImage` now re-export the lower modules their API names, so one import covers either.

Executable products for trying things out: `Example`, `Stress`, and the development tools `EmojiBugScanner`, `EmojiBenchmark`, `RenderHarness` and `ImageHarness`.

### Package traits: smaller macOS release builds

Two traits are enabled by default. Both apply only to macOS release builds. Debug builds, `swift test` and documentation builds compile and link as before. Neither is applied on Linux or Windows, where they have not been measured. Both apply to every module that a library product ships.

**`DeadStripUnusedAPI`**

- Swift marks every public symbol so the linker keeps it, called or not. With this trait TUIkit's modules are compiled with `-internalize-at-link`, and your app's linker keeps only the TUIkit API your app reaches.
- `swift build -c release` passes `-dead_strip`. An Xcode app needs `DEAD_CODE_STRIPPING = YES`, which is not Xcode's default.
- Measured (stripped, 2026-10-11): a hello-world app is 14.7% smaller and `Stress` 12.1% smaller on Swift 6.4.0. On Xcode's Swift 6.2.4 it is 14.9% and 12.3%.
- What it breaks: a statically linked app that `dlopen`s a plugin which calls TUIkit API the app never calls itself. That symbol is gone from the app and the plugin fails to load.

**`UnexportTUIkitSymbols`**

- A program exports every external symbol it defines, including TUIkit's. This trait passes one `-unexported_symbol` pattern per TUIkit module to the linker, which removes them from the export table (bytes that `strip` leaves in place).
- Measured (stripped, 2026-10-12, on top of `DeadStripUnusedAPI`): a hello-world app is a further 3.2% smaller and `Stress` 2.9%, on both toolchains.
- What it breaks:
  - A plugin loaded with `dlopen` into a statically linked app that calls any TUIkit API through the app fails to load ("symbol not found in flat namespace").
  - A `.dynamic` library that contains TUIkit exports none of TUIkit's symbols. A client that uses TUIkit through it fails to link, or fails at launch if it was linked against an older build of the library.
  - Your own extensions of TUIkit's types and protocols (`extension View { func card() }`, `extension Color { static var brand }`), and your conformances of TUIkit types to your protocols, are not exported either, because Swift names those symbols after the TUIkit module. A client in another module that calls one fails to link, unless the compiler copied its body into the client.
  - The linker refuses `-unexported_symbol` beside an export list. A link that passes `-no_exported_symbols`, `-exported_symbol` or `-exported_symbols_list` (as Xcode's `LD_EXPORT_SYMBOLS = NO` and `EXPORTED_SYMBOLS_FILE` do) stops with "-unexported_symbol cannot be used with -exported_symbol*".

**Opting out**

- `traits: []` on the dependency turns off every default trait of TUIkit's (today these two).
- `traits: ["DeadStripUnusedAPI"]` keeps dead stripping and turns off the symbol-hiding trait. Use this if your link needs an export list.
- No compiler or linker flag undoes what the traits do. The traits are the only way out.

```swift
.package(url: "https://github.com/wadetregaskis/TUIkit.git", branch: "main", traits: [])
```

```swift
.package(url: "https://github.com/wadetregaskis/TUIkit.git", branch: "main", traits: ["DeadStripUnusedAPI"])
```

### Upgrade-affecting changes

#### Because of the module split

- **The resource bundle is now `TUIkit_TUIkitStrings`.** It was `TUIkit_TUIkit` when the resources belonged to the `TUIkit` target. It is `TUIkit_TUIkitStrings.bundle` on macOS and `TUIkit_TUIkitStrings.resources` elsewhere. If you ship TUIkit's bundle beside your executable (an archive, an installer, a Homebrew formula), copy the new name. The bundle holds the translations (German, French, Italian, Spanish, Chinese, Japanese) and the version.
- **A missing bundle no longer stops the program at launch.** TUIkit's words then read in English, whatever language the user asks for, and `tuiKitVersion` reads `unknown`. A program copied out of `.build` no longer finds the bundle left in `.build`. It reads the bundle beside it or none.
- **Type names seen at runtime name the declaring module, not `TUIkit`.** `String(reflecting:)`, `dump` and the debugger show `TUIkitLists.List<...>`, `TUIkitApp.WindowGroup<...>` and `TUIkitFoundation.Text`. This is true whichever products you depend on. Code that matches on those strings needs updating.
- **A saved `NavigationPath.codable` representation is tied to module names.** It stores each value's type by its mangled name, which includes the module. A saved path holding a TUIkit type that has moved to another module stops decoding. This already affected `LocalizationService.Language` and the system format styles, which moved to `TUIkitStrings`. Types can still move before 1.0, so do not keep such a path across versions.
- **`renderOnce(content:)` is in `TUIkitApp`.** A tool that uses only it depends on `TUIkitApp`. With `import TUIkit` nothing changes.
- **`ASCIIConverter` and the rest of `TUIkitImage` are not re-exported by `TUIkitFoundation`.** With `import TUIkit` you still get them. An app on module products adds `TUIkitImage` (or `TUIkitBitmaps`, which re-exports it).
- **MemberImportVisibility is on for TUIkit's own modules.** Every carved module, `TUIkitFoundation` and `TUIkitAppKit` compile with Swift's `MemberImportVisibility` upcoming feature. It does not apply to your code unless you enable it yourself. If you do, a call to a member that a module adds in an extension needs `import` of the module that declares it in that file. `import TUIkit` covers every module except `TUIkitAppKit` and `TUIkitMacros`. On an app built from module products, the compiler's fix-it names the module to add, but only when that module is already loaded. One effect you get without turning anything on: because TUIkit's modules use it, SwiftUICore's extension members no longer reach an app through TUIkit.
- **The AppKit bridges need `import TUIkitAppKit`.** `Color(nsColor:)`, `NSColor(_:)` and `Image(nsImage:)` (and compiled asset catalogue reading) are in the separate `TUIkitAppKit` product, because a module that imports AppKit makes every importing app see SwiftUICore's extension members. Without this split, `FormatStyle.offset(to:)` and similar SwiftUI members were ambiguous in apps importing TUIkit. The Core Graphics bridges (`Color(cgColor:)`, `Color.Resolved.cgColor`, `Image(_:scale:orientation:label:)`, `Image(decorative:scale:orientation:)`) need only TUIkit.
- **swift-syntax is resolved for every client**, although only apps that depend on `TUIkitMacros` build it (see Dependencies).

#### API removed or renamed before the split began (3 to 7 October)

All of these are pre-1.0 changes with no old spelling kept.

- **Window chrome is opt-in.** The status bar no longer draws itself. Place `StatusBar()` in the window's bottom bar, for example `ToolbarItem(placement: .bottomBar) { StatusBar() }`. A bare `WindowGroup` now draws on every row with no key-hint line. The `a` (appearance) key is opt-in too.
- **`.appHeader` is removed.** Use `.navigationTitle`, `.navigationSubtitle` and `.toolbar` items.
- **`Scene.chromeStyle(_:)` and `chromeStyle(appHeader:statusBar:)` are removed.** Use `.windowToolbarStyle(_:)`.
- **`onDragGesture` and `DragGestureEvent` are removed.** Use `DragGesture(minimumDistance: 0)` with `onChanged` and `onEnded`, or `updating`.
- **`onRowActivate` on `List` and `Table` is removed.** Use `primaryAction` of `contextMenu(forSelectionType:menu:primaryAction:)`.
- **`onTapGesture`'s `(x, y)` overload is removed.** Use the closure that takes a `CellPoint`, or one with no argument.
- **TUIkit's focus-blind key handlers are renamed `onKeyEvent`.** `onKeyPress` is now SwiftUI's: focus-gated, with `KeyPress` and `KeyPress.Result`.
- **TUIkit's buffer-level modifier protocol is renamed `BufferModifier`.** `ViewModifier` is SwiftUI's, with `body(content:)`.
- **Button styles use SwiftUI's names:** `automatic`, `bordered`, `borderedProminent`, `borderless`, `plain`, `link`, `accessoryBar`, `accessoryBarAction`. TUIkit's `.default` and `.primary` are gone. `.plain` now means SwiftUI's undecorated plain; the old accent-tinted `.plain` is `.borderless`.
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
- **The AppKit bridges moved to `TUIkitAppKit`** (see above).

#### API removed or renamed with and after the split (8 to 23 October)

- **`AppState.shared` is removed**, along with `AppState.setLanguage(_:)` and `currentLanguage`. Every app owns its render state. `DismissAction()` and `LocalizationService.setLanguage(_:)` act on the running app. Still process-wide: the localization service, the notification queue and the default `@AppStorage` store.
- **`Text + Text` is removed** (see the deprecated list below). Interpolate a styled `Text` into another `Text` instead.
- **The row-level drop closure takes its payloads first, then the index:** `([Payload], Int)`. This applies to `ForEach`, `DynamicTableRowContent` and the `Table`-level `dropDestination`. Before it was `(Int, [Payload])`.
- **`@AppStorage` on `UserDefaults` keeps property-list values as themselves.** A `Bool`, `Int`, `Double`, `String`, `Date`, `Data`, `URL`, a raw-representable value, or an optional of these is stored natively, so `UserDefaults.standard.bool(forKey:)` reads what `@AppStorage` wrote. Values written earlier (as JSON) read as absent. There is no migration. `@AppStorage` and `@SceneStorage` take raw-representable values, stored as their raw value. Other `Codable` values are still JSON.
- **`.automatic` picker style's type is `DefaultPickerStyle`**, not `AutomaticPickerStyle`.
- **`TextContentType.url` is `.URL`.** Every `NSTextContentType` is now a `TextContentType`.
- **`Spacer.minLength` is a public `var`** under SwiftUI's name. `SpacerProtocol`'s requirement is `minLength`, not `spacerMinLength`.
- **`UnitCurve.easeInEaseOut`, `WindowGroup.init(content:)` and the `CoordinateSpace`-enum overloads are removed or made internal** (see below).
- **TUIkit's alert panel view is `AlertPanel`**, no longer `Alert`, whose name read as SwiftUI's retired value type. `.alert(…)` is unchanged; only code that names the view (`Alert(title:message:)`, `Alert.warning(…)`) changes. Its `.warning`, `.error`, `.info` and `.success` presets now start their titles with ⚠️, 🛑, ℹ️ and ✅.

#### Behaviour changes you may notice

- Inside GNU screen a copy is sent to the terminal through screen's passthrough and reported "Sent", where it was "Not copied". In a tmux pane whose `allow-passthrough` is on, a copy goes through tmux's passthrough when `set-clipboard` is not `on`, and is reported "Sent". Measured on screen 4.00.03 and tmux 3.7c with `Tools/TerminalProbes/keeper_passthrough_probe.py`.

- `.textSelection(.enabled)` on one `Table` cell's `Text` makes that cell's text selectable and nothing else: a click on another column's text selects the row again, and a drag there selects nothing. Around the whole table, a drag still selects across a row's columns.

- A drag selection begun inside a bordered container (`.border()`, `Box`, `Card`, `Panel`, `GroupBox`, a dialog, an alert) keeps to the container's interior, leaving out its border, its title and the page around it. A drag begun on the border or outside the container crosses it, and `.textSelectionScope(.pane)` turns the rule off for a subtree. As an experiment, a drag that goes more than 3 rows above or below the interior, or more than 6 columns beside it, widens to what the container sits in (the box around it, an enabled `textSelection`, or the pane) and stays widened until the release.

- A title key that reads the clock — `Button("Ends \(deadline, style: .relative)") {}` — stays live in a button's and a colour picker's title, a text, secure or value field's placeholder (and a `prompt:` `Text`), and a table column's header, as SwiftUI's does: each draws the frame's reading and wakes at the next change. A navigation title, an alert's title and message, help and a tab's title still read it once. `SecureField` and `TextField(_:value:format:)` parse their title key's Markdown, as `TextField` does.

- A number interpolated into a key with no specifier is written in the locale, as SwiftUI writes it: `Text("\(count) rows")` draws `1,234,567 rows` in English, `1.234.567` in German and `1 234 567` (a narrow no-break space) in French, where it drew `1234567`. A floating-point number has at most six fraction digits and no trailing zeros, so `\(3.5)` is `3.5` (`3,5` in German), not SwiftUI's `3.500000`, a deliberate deviation. The locale is `\.locale`: the app's, or the one a subtree sets for its `Text`s. The key is unchanged (`%lld`, `%lf` as SwiftUI spells it), so translations still match. Interpolate a `String` (`\(String(year))`) or use `Text(verbatim:)` for a number that must not be grouped, such as a year or a port.

- A number interpolated with a specifier, `Text("\(price, specifier: "%.2f")")`, follows `\.locale` too: it is written by exactly that conversion (`String(format:locale:)`) in the app's locale, `3.14` in English and `3,14` in German, and again in a subtree's own `\.locale` where its `Text` draws, as a bare number is. It was written once in the process's locale, so under an app-chosen language its numbers could differ from a bare one's. The key keeps the specifier as SwiftUI's does, so translations match.

- `Text("… \(value)")` (and every other key) of a value SwiftUI has no interpolation for — a `Bool`, an `Optional`, an enum, an array, a value typed `Any` — warns, as SwiftUI 26 does: "Localized string interpolation produces an unlocalized, debug description for this type of value." It still writes the description. Interpolate a `String` (`\(String(flag))`, `\(value.name)`) to say what you mean. SwiftUI's typed interpolations are all there: a `Substring`, an `AttributedString` (its looks kept), a `Date`, `URL` or other `ReferenceConvertible` value or an `NSObject` with an optional `formatter:`, and a `TimeDataSource` with `format:` are new. `\(value, specifier:)` takes a number only, as SwiftUI's does, where it took any `CVarArg`.

- A `Table` stripes every other row by default.
- A sheet's, full-screen cover's or popover's content is built only while it is presented, and a dismissed one loses its `@State`, as in SwiftUI.
- `onChange(of:)` on an optional that starts set no longer fires on its first render.
- `Animation.default` is SwiftUI's: the no-bounce spring at the default pace.
- A `ScrollView`'s `proxy.scrollTo(_:anchor:)` (a row, or a purely horizontal view's column), `ScrollPosition` request (a row, an edge or an offset, either axis) or written `anchorPosition` edge made inside `withAnimation` glides to its target a line or column at a time along the animation's curve, as SwiftUI's animates, where it jumped, and `onScrollPhaseChange` reports `.animating` until it lands. `withAnimation`'s completion fires when it lands. The wheel, a key or a focus move stops it where it is. Under reduce motion it still jumps, and so does a `List`'s or a `Table`'s.
- `.scrollKeyboardAnimation(_:)` (TUI-specific) makes a `ScrollView`'s Page Up/Down, Home and End glide to where they land — the page a scroll target behaviour picks, an edge, the tail — rather than jump; a key pressed during the glide counts from its target. Without it the keys jump, as before.
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
- A material (and glass) frosts what is behind it: the glyphs beneath are dropped, so text behind a material no longer shows between the words on it. The colours beneath are tinted as before, each cell its own. Over the page alone a material looks as before.
- `\.accessibilityReduceTransparency`, `\.accessibilityDifferentiateWithoutColor` and `\.colorSchemeContrast` follow the user: `TUIKIT_REDUCE_TRANSPARENCY=1`, `TUIKIT_DIFFERENTIATE_WITHOUT_COLOR=1`, `TUIKIT_INCREASE_CONTRAST=1`, or the macOS (or GNOME high-contrast) setting where TUIkit is sure the session is local, as reduce motion does. Under reduced transparency materials and glass are opaque. `\.colorSchemeContrast` is no longer always `.standard`.
- A paste of any size now arrives whole. The earlier 16 MiB limit is gone.
- A popover attached with `.rect(.rect(_:))` that is wider than its rectangle starts where the rectangle starts, as a menu and a tooltip do, rather than centring on it: a link's destination popover inside a `Text` now lines up with the link as a `Link`'s does.
- A link inside a `Text` (from Markdown or an attributed string) is a control, as a `Link` is: Tab reaches it, Return or a click opens it and shows its destination in a popover, and Shift+F10 or a right-click opens `Link`'s menu. A page with inline links gains a Tab stop per link. Not where `.linkDisplay` writes the URL out, in a disabled subtree, or in a list's row.
- The status bar draws an item's one-letter key as a macOS menu draws it: `Q quit` for `"q"`, `⇧N` for an item on `"N"`, matching `⌃Z undo` beside it. The item's string still binds the key. `.statusBarKeySpelling(.asTyped)` draws the strings as typed, as before.
- ⌃Y redoes, the one redo key every terminal sends, except in a focused text field or editor, where it is still the yank. The status bar's and the menu bar's redo hint names ⌃Y, and another redo key while a text control has the focus.
- While a `List`, a `Table`, an open `Picker` drop-down or an open menu has the keyboard, its type select takes every bare character, the first of a prefix included. TUIkit's `q`, `t`, `a` and help key, an app's bare `.keyboardShortcut`, a menu row's bare key equivalent and a status-bar item's bare key no longer fire there, and the status bar leaves those items out meanwhile. Before, the first character of a prefix gave way to such a binding. A modified key, an F-key or the menu bar still reaches its command.
- Under the kitty keyboard protocol, a ⌘ chord the terminal lets through (kitty and Ghostty pass some) reaches `onKeyPress` with `.command` in its modifiers, where it was dropped. It reaches nothing that matches a bare key, so ⌘K types nothing into a field. A `.keyboardShortcut` written with ⌘ still fires on its `.commandKey(_:)` stand-in (Control by default), and on a real ⌘ as well only under the new `.keyboardShortcutsMatchCommand()`. `KeyEvent` has a `command` field.
- A hierarchical `Table(_:children:)` keeps its outline from frame to frame while its rows (the same array) and its open branches are the same, so a frame costs what a flat table's does: 1.66 ms where it took 41.8 ms at 20,000 rows (debug build). A file panel's list view is now an outline for a folder of any size, where one of more than 5,000 items was drawn flat.
- A paused drag activates a spring-loaded control after the user's spring-loading delay (System Settings ▸ Accessibility ▸ Pointer Control) where TUIkit is sure the user is at the machine the app runs on, and after half a second elsewhere, as before. `TUIKIT_SPRING_LOADING_DELAY=0.3` (seconds) sets it for a run, and the new `.springLoadingDelay(_:)` sets it for a subtree. A `ColorPicker`'s well no longer spring-loads under `.springLoadingBehavior(.enabled)`, as SwiftUI's does not.
- A spring-loaded control a paused drag rests on draws as hovered while the pause runs, and as pressed for a tenth of a second as it fires, as macOS highlights it. A button style of your own sees it as `isHovered` and `isPressed`.
- A debug build stops (a `SoftTrap`) where a `Picker` leaves out a member of its content with no tag of the selection's type, and where an alert or confirmation dialog leaves out a `TextField`, `SecureField` or `Toggle` among its actions. SwiftUI shows both, so they were silent gaps. A release build reports each once and draws as before. Tag a picker's items with values of the selection's type.
- A list section's `.sectionActions` show only while the section is in use: the focused list's cursor is on one of its rows, the focus is on one of the actions, or the pointer is over the section. They were always shown, each a Tab stop. Tab from the list reaches the actions of the section the cursor is in. Hidden, their cells stay blank, so nothing moves as they come and go.
- An empty `List`'s or `Table`'s placeholder ("No items", or `.listEmptyPlaceholder(_:)`'s) is in the secondary ink and starts where a row's text would, no longer flush against the border.
- A `Stepper` with bounds reserves the width of the wider of its two ends, so ▶ no longer moves as the value gains a digit; a narrower value stands at the trailing edge. `.stepperValueWidth(_:)` sets the reservation (`0` for none).
- `Color.red`, `.blue` and the other named colours (all but `.white`, `.black` and TUIkit's `.magenta`) take Apple's dark values where they are drawn under a dark colour scheme, as SwiftUI's do: on a dark palette, and in a subtree pinned with `.environment(\.colorScheme, .dark)`. Most palettes are dark, so `.red` draws `#FF453A` there, not `#FF3B30`. What a body computes from one (`rgbComponents`, `opacity(_:over:)`, `mix(with:by:)`) still uses the light value. A named colour no longer equals the RGB it was (`Color.red != Color.hex(0xFF3B30)`), and it describes itself by name (`"red"`).
- A colour from an asset catalogue (`Color(_:bundle:)`, compiled catalogues included) and a dynamic `NSColor` (`Color(nsColor:)`) draw their light or dark variant by the colour scheme where they are drawn, as SwiftUI's do: the palette's, or a `.environment(\.colorScheme, …)` pin's, even when the colour was made outside the pinned subtree. Before, the variant was chosen when the colour was made, by the default palette's scheme. A body that measures one reads its light variant. Two variants that differ in opacity, or that are not plain colours, are still chosen when the colour is made, as is every new pair once a process has made 65,536 different ones. Such a colour no longer equals either variant's RGB, and describes itself by both (`"#CC6633FF light, #1080FFFF dark"`).

### Removed deprecated spellings

The project removes SwiftUI API that SwiftUI itself has deprecated, and does not add it. These went:

- `Text + Text`, deprecated in SwiftUI on macOS 26. An interpolated `Text` keeps its fragments' styling, which replaces it.
- `UnitCurve.easeInEaseOut`, renamed `easeInOut` in SwiftUI.
- `WindowGroup.init(content:)`, replaced by `init(makeContent:)`. A call written `WindowGroup { ... }` binds either.
- The `CoordinateSpace`-enum overloads of `GeometryProxy.frame(in:)`, `onTapGesture(count:coordinateSpace:perform:)`, `onContinuousHover(coordinateSpace:perform:)`, `DragGesture.init` and `SpatialTapGesture.init`. They are internal now. The `some CoordinateSpaceProtocol` forms are public, and `.local`, `.global`, `.named(_:)` and `.scrollView` bind to them.

Deprecated SwiftUI spellings TUIkit still has, on purpose:

- The soft-deprecated `dropDestination(for:action:isTargeted:)`, until the drag-session work.
- The catch-all `Text("... \(anything)")` string interpolation, deprecated as SwiftUI deprecates it on the macOS 26 SDK: it compiles and warns.
- The `.roundedBorder` and `.squareBorder` text field styles, which SwiftUI deprecates in macOS 27. TUIkit's parity baseline is the macOS 26 SDK.

`Tools/APIParity/api_parity.py --deprecated` lists the SwiftUI declarations deprecated on macOS that TUIkit still implements (23 against the macOS 26.2 SDK). Most are cases where TUIkit has the live overload and SwiftUI's deprecated one shares its name.

### Dependencies and requirements

- Swift: `swift-tools-version: 6.2`. The README says Swift 6.2 or later. CI builds with Xcode 26 and 27 on macOS and with Swift 6.2, 6.3 and 6.4 on Linux. The tools version and the minimum macOS are unchanged by the split.
- Platforms: macOS 14 or later (`.macOS(.v14)`, unchanged), and Linux (no platform declaration needed). The package also builds for `wasm32-unknown-wasip1` (the README describes a browser build of the Example app). On Windows, the four lowest modules (`TUIkitCore`, `TUIkitStyling`, `TUIkitView`, `TUIkitImage`) build, and the rest do not yet.
- **swift-docc-plugin** (from 1.4.3): documentation. No target uses it.
- **swift-syntax** (`602.0.0` up to, not including, `700.0.0`): added for the compiler plugin behind `TUIkitMacros`. It is built only for an app that depends on that product. Every client still resolves and fetches it, because SwiftPM resolves by package. The range is wide so that TUIkit does not refuse an app whose other packages want a newer swift-syntax. SwiftPM uses a prebuilt swift-syntax only where one is published for the version and toolchain: 602.0.0 on Swift 6.2, and 604.0.0 on swift.org's Swift 6.4.0 on macOS. An app on Swift 6.2 that wants prebuilts can pin `exact: "602.0.0"`.
- **swift-collections** is no longer a dependency. TUIkit used its `UniqueDeque` for input buffering. Linking swift-collections' `DequeModule` pulled in a reference to `libswiftCompatibilitySpan.dylib`, which macOS has only from version 26, so a release program copied out of `.build` failed at launch on macOS 14 and 15. `TUIkitApp` now has its own input buffers. If your own program uses the standard library's `Span` types or links swift-collections 1.4 or later, see "Shipping a program" in the README for what to ship.
- `ordo-one/benchmark` is added only when `TUIKIT_BENCHMARKS` is set in the environment.

### Highlights since the split

- A menu bar. A scene that declares `commands` gets a menu bar on the window's top row, with `CommandMenu`, `CommandGroup`, the standard command sets, and TUIkit's own app, Edit, View and Window menus. Menus open by click, F10, or Alt and a title's first letter. TUIkit's own `DisplayCommands()` adds View ▸ Palette, Border Style and Control Style, each a submenu of the built-in choices: it chooses through the app's palette and appearance managers and a new control style manager (`\.controlStyleManager`), disables a submenu whose value the scene sets itself, and writes the app's own state instead where it is given a binding (`DisplayCommands(palette:appearance:controlStyle:)`).
- Several scenes and windows. A body can declare more than one scene. `openWindow`, `dismissWindow`, windows presenting data, a `Settings` scene shown as a sheet (`openSettings`), `AlertScene`, per-window `@SceneStorage`, and the terminal's title following the window in front.
- Toolbars. SwiftUI's `.toolbar` places items in the top and bottom bars by placement. Window toolbar styles, accessory bars, title menus, `toolbar(id:)` customization from a panel, and tab view sidebar toolbars.
- File panels. `fileImporter`, `fileExporter`, `fileMover` and the `fileDialog` modifiers present open and save panels that TUIkit draws, in the new `TUIkitFilePanels` module.
- Shapes and paths. Shapes are views, drawn in box glyphs or rasterized, with `Path`, container shapes, and shapes as backgrounds, overlays, clips and hit areas.
- Materials, glass, shadows and blend modes. Materials as translucent surfaces, `GlassEffectContainer` that joins glass, drop and inner shadows (animatable), `View.blendMode`, `ShapeStyle.blendMode`, and image paints.
- Animation. Branch fades, matched geometry, the zoom navigation transition, `.blurReplace` (its scale and a fade, the blur drawn as the fade), `CustomAnimation`, animations that carry their motion when interrupted, and stacks whose children glide when a view comes or goes.
- Scrolling. Scroll target behaviours (`.paging`, `.viewAligned`), bound scroll positions that `List` and `Table` follow, and horizontal scroll fixes.
- Lists, tables and navigation. SwiftUI-shaped `Table` columns, `OutlineGroup` over a binding to a tree, `sidebarAdaptable` tab views with a customizable sidebar, `HSplitView`, `VSplitView` and the inspector, and compact-size adaptation for popovers, tables, split views and tab bars (`tabBarMinimizeBehavior`).
- Control sizes. Text fields, sliders, steppers and segmented pickers follow `controlSize` from mini to extra large, and a bare picker, slider or stepper in a `Form` is a field row.
- Text. `AttributedString` runs, `Text` that keeps its styling when interpolated, Markdown in control titles, underline patterns and colours, and `MeshGradient`.
- Text input and undo. Typing is grouped into undo steps as macOS does, Ctrl-Z and the undo and redo keys, Option-drag block selection in `TextEditor`, and content-type filters. `TextEditor`'s find bar (`findNavigator`) opens with Ctrl-F, finds the next match with Ctrl-G, tints every match and has macOS's options; the wheel scrolls an editor and a capped vertical field; a search field shows a ✗ that empties it.
- Terminal integration. Pointer shapes (`pointerStyle`), a progress bar on the terminal's tab (`.terminalProgress`), desktop attention notifications, OSC 52 and OSC 5522 clipboard with HTML, RTF and images, and the kitty keyboard protocol.
- Platforms. GNOME Terminal (VTE) is recognized and compensated for, and there are fixes for Linux and WebAssembly (WASI).
- Macros. The `TUIkitMacros` product adds `@Animatable`, `@AnimatableIgnored` and `@Entry`.
- Documentation. A "Choosing Products" article, a generated "Which Module Provides It" page, and CI that builds one small app for each library product.
