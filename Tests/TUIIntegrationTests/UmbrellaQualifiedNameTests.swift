//  🖥️ TUI — A Terminal UI framework for Swift
//  UmbrellaQualifiedNameTests.swift
//
//  An app spells `TUI.X` to reach TUI's `X` past a type of its own with
//  the same name. Since step B1 of the module split the TUI module declares
//  nothing: `X` is TUIFoundation's, or a lower module's, reached through the
//  umbrella's `@_exported import`s. Qualified lookup does go through them —
//  probe t14 of the plan's step 0b measured it on Swift 6.2.4 (Xcode and
//  swift.org) and 6.3.3 (Linux) — and this file keeps that probe's shapes as a
//  test, so a carve that broke one would stop it compiling. It imports only
//  `TUI`, as an app does: no `@testable`, no lower module.
//
//  t14 measured one re-export. Since step B2 a type of TUIStrings or
//  TUITerminalHost is two away: the umbrella re-exports TUIFoundation,
//  which re-exports those modules (the umbrella names neither). The second
//  test spells such types through the umbrella, so it is the measurement of
//  that case, and a carve that dropped a re-export below the umbrella would
//  stop it compiling too.
//
//  Step B3 carved TUIApp out the other way: built on TUIFoundation,
//  not under it, so TUIFoundation cannot re-export it, and the umbrella
//  does, beside TUIFoundation. The third test spells its types through the
//  umbrella, so a carve that left TUIApp out of the umbrella's re-exports
//  would stop this file compiling as well.
//
//  Step B4 carved TUIColorPicker out the same way, so the umbrella
//  re-exports a second module beside TUIFoundation. The fourth test spells
//  its types through the umbrella: an app's own `ColorPicker` beside it is the
//  case an app meets (a colour picker of its own, written before it adopted
//  TUI), and a carve that left the module out of the umbrella's re-exports
//  stops this file compiling.
//
//  Step B5 carved the Navigation group the same way: one module,
//  TUINavigation, that compiles two directories of the planned split,
//  Sources/TUINavigation and Sources/TUIPresentation, until step C1 peels
//  the second into a module of its own. The fifth test spells a type from each
//  directory through the umbrella, beside an app's own `AlertPanel` (the case an app
//  meets: an alert model of its own), so this file stops compiling if `import
//  TUI` misses the types of either directory. Two holes it leaves to others.
//  The umbrella's own `@_exported import TUINavigation`: until C1,
//  TUIColorPicker re-exports TUINavigation too (its panels are
//  TUIPresentation's `Dialog`s), and the umbrella re-exports
//  TUIColorPicker, so this file compiles without that line.
//  Tools/ModuleMap's `umbrella` check holds it: the umbrella re-exports, by
//  name, every module built on TUIFoundation. And a directory left in
//  TUIFoundation: its types would still compile, as TUIFoundation's, so
//  the test's reflected name, `TUINavigation.Alert`, catches it at run time,
//  not the compiler.
//
//  Step C1 peeled Sources/TUIPresentation out of that group into a module
//  of its own, TUIPresentation, the first peel. The fifth test's alert,
//  and the detent among the reflected names, read `TUIPresentation.` since;
//  they read `TUINavigation.` from B5 to C1, so a peel renames what an app
//  sees of each type it moves, as a carve does. The same two holes, the same
//  two guards: TUIColorPicker re-exports TUIPresentation (its panels are
//  `Dialog`s) in place of TUINavigation, so the umbrella's own line for
//  each is the `umbrella` check's; and a directory left compiling in
//  TUINavigation would still compile here, so the reflected names catch it.
//
//  Step B6 carved the Lists group the same way: one module, TUILists, that
//  compiled four directories of the planned split, Sources/TUILists,
//  TUITables, TUITabs and TUIGrid, until steps C2 to C4 peeled the
//  last three into modules of their own. The sixth test spells a type from each
//  directory through the umbrella and draws it, the table beside an app's own
//  `Table` (the case an app meets: a database table model of its own). It
//  leaves the same two holes to the same two guards: TUIColorPicker
//  re-exports TUILists (its panel is a `TabView`): directly until C3,
//  and after it through TUITabs, which depends on TUILists. So the
//  umbrella's own line is the `umbrella` check's for good; and a directory
//  left in TUIFoundation would still compile, so the reflected names, one
//  per directory, catch it at run time.
//
//  Step C2 peeled Sources/TUITables out of that group into a module of its
//  own, TUITables, built on TUILists, which it re-exports. The sixth
//  test's table, and the column customization behaviour among the reflected
//  names, read `TUITables.` since; they read `TUILists.` from B6 to C2.
//  Nothing but the umbrella re-exports TUITables, so this file stops
//  compiling without the umbrella's line for it.
//
//  Step C3 peeled Sources/TUITabs out of the group into TUITabs, built
//  on TUILists, which it re-exports. The sixth test's tab view, and the
//  tab bar placement among the reflected names, read `TUITabs.` since;
//  they read `TUILists.` from B6 to C3. TUIColorPicker re-exports
//  TUITabs (its panel is a `TabView`), so the umbrella's own line for it
//  is the `umbrella` check's, as TUIPresentation's is.
//
//  Step C4 peeled Sources/TUIGrid out of the group into TUIGrid, built
//  on TUIFoundation alone, which left TUILists an ordinary module. The
//  sixth test's grid, and the grid item among the reflected names, read
//  `TUIGrid.` since; they read `TUILists.` from B6 to C4. Nothing but
//  the umbrella re-exports TUIGrid, so this file stops compiling without
//  the umbrella's line for it.
//
//  Step B5b carved three leaves the same way, each a module of its own:
//  TUIChrome, TUIEffects and TUIMenus. The seventh test spells and
//  draws a type of each through the umbrella, the menu beside an app's own
//  `Menu` (the case an app meets: a menu model of its own). The umbrella is
//  the only module that re-exports TUIEffects and TUIMenus, so this
//  file stops compiling without either line. TUIApp and TUINavigation
//  (TUIPresentation since step C1) re-export TUIChrome, which they
//  depend on, so the umbrella's own line for it is the `umbrella` check's, for
//  good. A module left compiling in
//  TUIFoundation would still compile here; the reflected names, one per
//  module, catch it at run time.
//
//  Step B5c carved TUIBitmaps the same way, `Image`'s bitmap path, and took
//  TUIImage out of TUIFoundation's re-exports. The eighth test spells
//  and draws its types through the umbrella, an `AsyncImage` beside an app's
//  own `AsyncImage` (the case an app meets: an image loader of its own), and
//  three of its image options on an image still loading: one that takes
//  TUIImage's `ASCIIColorMode`, and a caption with the spinner off, which
//  the loading image draws, so the drawing shows the options reach it. The
//  umbrella is the only module that re-exports TUIBitmaps, so this file
//  stops compiling without its line. TUIImage has three: the umbrella's
//  own, TUIBitmaps' and TUIColorPicker's (their direct dependency);
//  nothing checks the umbrella's line for it, but an app would lose
//  `ASCIIColorMode` only with all three gone. A module left compiling in
//  TUIFoundation would still compile here; the reflected names catch it at
//  run time.
//
//  Step B7 carved the TextInput group the same way as B5's and B6's: one
//  module, TUITextInput, that compiled five directories of the planned
//  split, Sources/TUITextInput, TUIPickers, TUIForms, TUISearch
//  and TUINumericControls, until steps C5 to C8 peeled the last four into
//  modules of their own (below). It took the last directories out of
//  TUIFoundation. The ninth
//  test spells a type from each directory through the umbrella and draws it,
//  the text field beside an app's own `TextField` (the case an app meets: a
//  form model of its own). It leaves the same two holes to the same two
//  guards: TUIColorPicker re-exports TUITextInput (its editors are
//  sliders, its hex field a text field), so the umbrella's own line is the
//  `umbrella` check's; and a directory left compiling in TUIFoundation
//  would still compile here, so the reflected names, one per directory,
//  catch it at run time.
//
//  Step C6 peeled Sources/TUIForms out of the group into TUIForms,
//  built on TUIFoundation alone. The ninth test's labeled content, and the
//  form styles among the reflected names, read `TUIForms.` since; they
//  read `TUITextInput.` from B7 to C6. Nothing but the umbrella
//  re-exports TUIForms, so this file stops compiling without the
//  umbrella's line for it.
//
//  Step C5 peeled Sources/TUISearch out of the group into TUISearch,
//  built on TUITextInput, which it re-exports (a search field is a
//  `TextField`). The search field's placements among the reflected names, and
//  the type the ninth test's member is added to, read `TUISearch.` since;
//  they read `TUITextInput.` from B7 to C5. Nothing but the umbrella
//  re-exports TUISearch, so this file stops compiling without the
//  umbrella's line for it.
//
//  Step C8 peeled Sources/TUIPickers out of the group into TUIPickers,
//  built on TUIFoundation alone. The ninth test's radio group, and the
//  date picker's components among the reflected names, read `TUIPickers.`
//  since; they read `TUITextInput.` from B7 to C8. TUIColorPicker and
//  TUISearch re-export TUIPickers too (a radio group picks a curve
//  editor's channel, a segmented picker is the scope bar), so the umbrella's
//  own line for it is the `umbrella` check's, and the reflected names catch
//  a directory left compiling in TUITextInput.
//
//  Step C7 peeled Sources/TUINumericControls, the group's last member, out
//  into TUINumericControls, built on TUIFoundation alone, which left
//  TUITextInput compiling its own directory alone. The ninth test's gauge,
//  and the track and indeterminate styles among the reflected names, read
//  `TUINumericControls.` since; they read `TUITextInput.` from B7 to
//  C7. TUIColorPicker re-exports TUINumericControls too (its editors are
//  sliders), so the umbrella's own line for it is the `umbrella` check's.
//
//  C9b peeled the gradient, tone-curve and channel-curve editors out of
//  TUIColorPicker into TUIColorEditors, built on it, so that an app with
//  a `ColorPicker` alone links none of them; on 2026-10-12 the gradient editor
//  went back, and the module, holding the two curve editors, became
//  TUICurveEditors. The fourth test's curve editor, and the curve editors
//  among the reflected names, read `TUICurveEditors.` since; they read
//  `TUIColorEditors.` from C9b to then, and `TUIColorPicker.` from B4 to
//  C9b, as the gradient editor does again. Nothing but the umbrella re-exports
//  TUICurveEditors, so the umbrella's line for it is what lets this file
//  compile.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUI
@testable import TUITestSupport

/// An app's own `Label`, beside TUI's.
private enum Client {
    struct Label {
        let name: String
    }

    /// Both labels: the app's by its plain name, TUI's by the umbrella's.
    @MainActor
    static func both() -> (Label, TUI.Label<TUI.Text, TUI.Text>) {
        (Label(name: "mine"), TUI.Label { TUI.Text(verbatim: "t14 title") } icon: { TUI.Text(verbatim: "*") })
    }

    /// An app's own `TerminalClient`, beside TUITerminalHost's.
    struct TerminalClient {
        let name: String
    }

    /// Both clients: the app's by its plain name, and a program of TUI's
    /// by the umbrella's spelling, two re-exports down.
    static func bothClients() -> (TerminalClient, TUI.TerminalClient.Program) {
        (TerminalClient(name: "mine"), TUI.TerminalClient.Program.ghostty)
    }

    /// An app's own `Scene`, beside TUIApp's protocol.
    struct Scene {
        let name: String
    }

    /// Both scenes: the app's by its plain name, and a window group by the
    /// umbrella's spelling of TUIApp's protocol and type.
    @MainActor
    static func bothScenes() -> (Scene, some TUI.Scene) {
        (Scene(name: "mine"), TUI.WindowGroup { TUI.Text(verbatim: "b3") })
    }

    /// An app's own `ColorPicker`, beside TUIColorPicker's view.
    struct ColorPicker {
        let name: String
    }

    /// Both pickers: the app's by its plain name, TUI's by the umbrella's.
    @MainActor
    static func bothPickers(selection: TUI.Binding<TUI.Color>) -> (ColorPicker, TUI.ColorPicker) {
        (ColorPicker(name: "mine"), TUI.ColorPicker("b4", selection: selection))
    }

    /// An app's own `AlertPanel`, beside TUIPresentation's alert view (which
    /// TUINavigation compiled from step B5 until step C1).
    struct AlertPanel {
        let name: String
    }

    /// Both alerts: the app's by its plain name, TUI's by the umbrella's,
    /// with a TUIFoundation button as its action.
    @MainActor
    static func bothAlerts(title: String) -> (AlertPanel, TUI.AlertPanel<TUI.Button>) {
        (AlertPanel(name: "mine"), TUI.AlertPanel(title: title, message: "b5 message") {
            TUI.Button(action: {}, label: { TUI.Text(verbatim: "b5 ok") })
        })
    }

    /// An app's own `Table`, beside TUITables' table view (which
    /// TUILists compiled from Sources/TUITables until step C2).
    struct Table {
        let name: String
    }

    /// A row of TUI's table.
    struct Row: Identifiable {
        let id: Int
        let name: String
    }

    /// Both tables: the app's by its plain name, TUI's by the umbrella's,
    /// with a column spelled the same way.
    @MainActor
    static func bothTables(rows: [Row]) -> (Table, TUI.Table<Row>) {
        (Table(name: "mine"), TUI.Table(rows) { TUI.TableColumn("b6 name", value: \Row.name) })
    }

    /// An app's own `Menu`, beside TUIMenus' view.
    struct Menu {
        let name: String
    }

    /// Both menus: the app's by its plain name, TUI's by the umbrella's,
    /// with a TUIFoundation button as its item.
    @MainActor
    static func bothMenus() -> (Menu, TUI.Menu<TUI.Text, TUI.Button>) {
        (Menu(name: "mine"), TUI.Menu("b5b menu") { TUI.Button("b5b item") {} })
    }

    /// An app's own `AsyncImage`, beside TUIBitmaps' view.
    struct AsyncImage {
        let name: String
    }

    /// Both async images: the app's by its plain name, TUI's by the
    /// umbrella's, with no URL, so it stays in its empty phase and draws what
    /// its content makes of that.
    @MainActor
    static func bothAsyncImages() -> (AsyncImage, TUI.AsyncImage<TUI.Text>) {
        (AsyncImage(name: "mine"), TUI.AsyncImage(url: nil) { phase in
            TUI.Text(verbatim: phase.image == nil ? "b5c empty" : "b5c image")
        })
    }

    /// An app's own `TextField`, beside TUITextInput's view.
    struct TextField {
        let name: String
    }

    /// Both text fields: the app's by its plain name, TUI's by the
    /// umbrella's, bound to a constant text so it draws that text.
    @MainActor
    static func bothTextFields(text: String) -> (TextField, TUI.TextField<TUI.Text>) {
        (TextField(name: "mine"), TUI.TextField("b7 title", text: TUI.Binding.constant(text)))
    }
}

/// A style conforming through the umbrella's spelling of the protocol.
private struct BracketedLabelStyle: TUI.LabelStyle {
    func makeBody(configuration: Configuration) -> some TUI.View {
        TUI.HStack(spacing: 0) {
            TUI.Text(verbatim: "[")
            configuration.title
            TUI.Text(verbatim: "]")
        }
    }
}

extension TUI.Label where Title == TUI.Text, Icon == TUI.Text {
    /// A member an app adds to TUI's type through the umbrella's name.
    fileprivate var t14Marker: Int { 14 }
}

extension TUI.LocalizationService.Language {
    /// A member an app adds, through the umbrella's name, to a type of
    /// TUIStrings, which reaches the umbrella through TUIFoundation.
    fileprivate var b2Marker: String { "b2-\(rawValue)" }
}

extension TUI.WindowGroup {
    /// A member an app adds, through the umbrella's name, to a type of
    /// TUIApp, which the umbrella re-exports itself.
    fileprivate var b3Marker: Int { 3 }
}

extension TUI.ColorPicker {
    /// A member an app adds, through the umbrella's name, to a type of
    /// TUIColorPicker, which the umbrella re-exports itself.
    fileprivate var b4Marker: Int { 4 }
}

extension TUI.NavigationPath {
    /// A member an app adds, through the umbrella's name, to a type of
    /// TUINavigation, which only the umbrella re-exports since step C1
    /// (TUIColorPicker did too, from step B5 until then).
    fileprivate var b5Marker: Int { 5 + count }
}

extension TUI.MenuOrder {
    /// A member an app adds, through the umbrella's name, to a type of
    /// TUIMenus, which only the umbrella re-exports.
    fileprivate var b5bMarker: Int { self == .fixed ? 1 : 0 }
}

extension TUI.ToolbarPlacement {
    /// A member an app adds, through the umbrella's name, to a type of
    /// TUIChrome, which the umbrella re-exports (and so do TUIApp and
    /// TUIPresentation; TUINavigation did until step C1).
    fileprivate var b5bMarker: Int { self == .bottomBar ? 2 : 0 }
}

extension TUI.ImageFitTarget {
    /// A member an app adds, through the umbrella's name, to a type of
    /// TUIBitmaps, which only the umbrella re-exports.
    fileprivate var b5cMarker: Int { self == .viewport ? 3 : 0 }
}

extension TUI.SearchFieldPlacement {
    /// A member an app adds, through the umbrella's name, to a type of
    /// TUISearch (TUITextInput's from step B7 until step C5), which only
    /// the umbrella re-exports.
    fileprivate var b7Marker: Int { self == .automatic ? 7 : 0 }
}

extension TUI.TabViewCustomization {
    /// A member an app adds, through the umbrella's name, to a type of
    /// TUITabs (TUILists' from step B6 until step C3), which the
    /// umbrella re-exports itself, and TUIColorPicker as well.
    fileprivate var b6Marker: Int { self == TUI.TabViewCustomization() ? 6 : -6 }
}

@MainActor
@Suite("TUI.X in an app's source")
struct UmbrellaQualifiedNameTests {
    @Test("A qualified name reaches the declaring module's type, beside an app's type of the same name")
    func qualifiedNamesResolveThroughTheUmbrella() {
        let (mine, theirs) = Client.both()
        #expect(mine.name == "mine")
        #expect(theirs.t14Marker == 14)
        // An initializer as a value, and a function a lower module declares.
        let make: (String) -> TUI.Text = TUI.Text.init(verbatim:)
        let buffer: TUI.FrameBuffer = TUI.renderToBuffer(
            TUI.VStack { theirs.labelStyle(BracketedLabelStyle()); make("made") },
            context: makeRenderContext(width: 40, height: 2))
        let lines = buffer.lines.map(\.stripped)
        #expect(lines.first?.contains("[t14 title]") == true, "\(lines)")
        #expect(lines.last?.contains("made") == true, "\(lines)")
    }

    @Test("A qualified name reaches a module that TUIFoundation re-exports in turn")
    func qualifiedNamesResolveThroughTwoReExports() {
        // TUITerminalHost's types: beside an app's own `TerminalClient`,
        // and a static function as a value.
        let (mine, program) = Client.bothClients()
        #expect(mine.name == "mine")
        #expect(program == .ghostty)
        let advance: (Character, TUI.TerminalClient.Program) -> Int =
            TUI.TerminalClient.cursorAdvance(of:on:)
        #expect(advance("a", program) == 1)
        // TUIStrings' types: a nested type through a class, and a member an
        // app's extension adds to it.
        let language: TUI.LocalizationService.Language = .german
        #expect(language.b2Marker == "b2-de")
        #expect(TUI.LocalizationService.Language.allCases.contains(language))
    }

    @Test("A qualified name reaches TUIApp, which the umbrella re-exports beside TUIFoundation")
    func qualifiedNamesReachTheModuleBuiltOnFoundation() {
        // TUIApp's types: a scene beside an app's own `Scene`, as an
        // opaque `some TUI.Scene`, and a member an app's extension adds.
        let (mine, group) = Client.bothScenes()
        #expect(mine.name == "mine")
        #expect(String(reflecting: type(of: group)) == "TUIApp.WindowGroup<TUIFoundation.Text>")
        #expect(TUI.WindowGroup { TUI.Text(verbatim: "b3") }.b3Marker == 3)
        // A conformance spelled through the umbrella, and a free function of
        // TUIApp's as a value (never called: it writes to the terminal).
        let style: any TUI.WindowToolbarStyle = TUI.DefaultWindowToolbarStyle()
        #expect(style is TUI.DefaultWindowToolbarStyle)
        let draw: (TUI.RenderOnceOutput, () -> TUI.Text) -> Void = TUI.renderOnce(output:content:)
        _ = draw
    }

    @Test("A qualified name reaches TUIColorPicker, which the umbrella re-exports beside TUIApp")
    func qualifiedNamesReachTheColorPicker() {
        // TUIColorPicker's view beside an app's own `ColorPicker`, a member
        // an app's extension adds to it, and the view drawn: its label comes
        // out of the render.
        let (mine, picker) = Client.bothPickers(selection: .constant(TUI.Color.red))
        #expect(mine.name == "mine")
        #expect(picker.b4Marker == 4)
        let lines = TUI.renderToBuffer(picker, context: makeRenderContext(width: 60, height: 3)).lines
            .map(\.stripped)
        #expect(lines.first?.contains("b4") == true, "\(lines)")
        // A curve editor, whose initializer takes a TUIImage type, spelled
        // through the umbrella too: TUICurveEditors' since 2026-10-12,
        // TUIColorEditors' since C9b, which TUIColorPicker compiled until
        // then.
        let panel = TUI.ToneCurveEditorPanel(
            stops: .constant([TUI.ASCIIToneCurve.Stop]()), isPresented: .constant(true))
        #expect(String(reflecting: type(of: panel)) == "TUICurveEditors.ToneCurveEditorPanel")
    }

    @Test("A qualified name reaches TUINavigation and TUIPresentation, which the umbrella re-exports")
    func qualifiedNamesReachTheNavigationGroup() {
        // From Sources/TUINavigation: a stack, drawn, and a member an app's
        // extension adds to its path.
        let stack = TUI.NavigationStack { TUI.Text(verbatim: "b5 root") }
        let lines = TUI.renderToBuffer(stack, context: makeRenderContext(width: 40, height: 4)).lines
            .map(\.stripped)
        #expect(lines.contains { $0.contains("b5 root") }, "\(lines)")
        #expect(TUI.NavigationPath([1, 2]).b5Marker == 7)
        // From Sources/TUIPresentation, which compiled into the same module
        // from step B5 until step C1 peeled it into a module of its own: an
        // alert beside an app's own `AlertPanel`, drawn.
        let (mine, alert) = Client.bothAlerts(title: "b5 alert")
        #expect(mine.name == "mine")
        let drawn = TUI.renderToBuffer(alert, context: makeRenderContext(width: 40, height: 8)).lines
            .map(\.stripped).joined(separator: "\n")
        #expect(drawn.contains("b5 alert") && drawn.contains("b5 ok"), "\(drawn)")
        #expect(String(reflecting: type(of: alert)) == "TUIPresentation.AlertPanel<TUIFoundation.Button>")
    }

    @Test("A qualified name reaches TUILists and the three modules peeled out of it, through the umbrella")
    func qualifiedNamesReachTheListsGroup() {
        func drawn(_ view: some TUI.View, height: Int) -> String {
            TUI.renderToBuffer(view, context: makeRenderContext(width: 40, height: height)).lines
                .map(\.stripped).joined(separator: "\n")
        }
        // From Sources/TUILists: a list, drawn.
        let list = TUI.List { TUI.Text(verbatim: "b6 row") }
        #expect(drawn(list, height: 4).contains("b6 row"))
        // From Sources/TUITables, which compiled into the same module until
        // step C2 peeled it into TUITables: a table beside an app's own
        // `Table`, drawn.
        let (mine, table) = Client.bothTables(rows: [Client.Row(id: 1, name: "b6 cell")])
        #expect(mine.name == "mine")
        let tableLines = drawn(table, height: 6)
        #expect(tableLines.contains("b6 name") && tableLines.contains("b6 cell"), "\(tableLines)")
        // From Sources/TUITabs, which compiled into the same module until
        // step C3 peeled it into TUITabs: a tab view, drawn, and a member
        // an app's extension adds to its customization.
        let tabs = TUI.TabView {
            TUI.Tab("b6 tab", systemImage: "list.bullet") { TUI.Text(verbatim: "b6 body") }
        }
        #expect(drawn(tabs, height: 6).contains("b6 body"))
        #expect(TUI.TabViewCustomization().b6Marker == 6)
        // From Sources/TUIGrid, which compiled into the same module until
        // step C4 peeled it into TUIGrid: a grid, drawn.
        let grid = TUI.Grid { TUI.GridRow { TUI.Text(verbatim: "b6 a"); TUI.Text(verbatim: "b6 b") } }
        #expect(drawn(grid, height: 2).contains("b6 a"))
        // One reflected name from each directory: a directory left compiling
        // in TUIFoundation would still build, and read
        // `TUIFoundation.` here.
        #expect(String(reflecting: type(of: table)).hasPrefix("TUITables.Table<"))
        #expect(String(reflecting: type(of: tabs)).hasPrefix("TUITabs.TabView<"))
        #expect(String(reflecting: type(of: grid)).hasPrefix("TUIGrid.Grid<"))
        #expect(String(reflecting: TUI.EditMode.self) == "TUILists.EditMode")
        #expect(String(reflecting: TUI.TabViewCustomization.self) == "TUITabs.TabViewCustomization")
        #expect(String(reflecting: TUI.GridItem.self) == "TUIGrid.GridItem")
    }

    @Test("A qualified name reaches TUIChrome, TUIEffects and TUIMenus, which the umbrella re-exports")
    func qualifiedNamesReachTheChromeEffectsAndMenus() {
        func drawn(_ view: some TUI.View, height: Int) -> String {
            TUI.renderToBuffer(view, context: makeRenderContext(width: 40, height: height)).lines
                .map(\.stripped).joined(separator: "\n")
        }
        // TUIMenus: a menu beside an app's own `Menu`, drawn (its closed
        // button shows its title), and a member an app's extension adds to its
        // order.
        let (mine, menu) = Client.bothMenus()
        #expect(mine.name == "mine")
        let menuLines = drawn(menu, height: 2)
        #expect(menuLines.contains("b5b menu"), "\(menuLines)")
        #expect(TUI.MenuOrder.fixed.b5bMarker == 1)
        // TUIEffects: a colour effect and a transition, spelled through the
        // umbrella, over a TUIFoundation text, drawn.
        let effected = TUI.Text(verbatim: "b5b effect").grayscale(0.5)
            .transition(TUI.AnyTransition.opacity)
        #expect(drawn(effected, height: 1).contains("b5b effect"))
        // TUIChrome: help on a text, drawn as the text (the help is a
        // tooltip, which the window draws), and a member an app's extension
        // adds to a toolbar placement.
        let helped = TUI.Text(verbatim: "b5b help").help("b5b tip")
        #expect(drawn(helped, height: 1).contains("b5b help"))
        #expect(TUI.ToolbarPlacement.bottomBar.b5bMarker == 2)
        // One reflected name from each module: a module left compiling in
        // TUIFoundation would still build, and read `TUIFoundation.`
        // here.
        #expect(String(reflecting: type(of: menu)).hasPrefix("TUIMenus.Menu<"))
        #expect(String(reflecting: TUI.AnyTransition.self) == "TUIEffects.AnyTransition")
        #expect(String(reflecting: TUI.ToolbarPlacement.self) == "TUIChrome.ToolbarPlacement")
    }

    @Test("A qualified name reaches TUIBitmaps, which the umbrella re-exports, and TUIImage beside it")
    func qualifiedNamesReachTheBitmaps() {
        func drawn(_ view: some TUI.View) -> String {
            TUI.renderToBuffer(view, context: makeRenderContext(width: 40, height: 1)).lines
                .map(\.stripped).joined(separator: "\n")
        }
        // An async image beside an app's own `AsyncImage`, drawn: with no URL
        // it stays empty, and its content says so.
        let (mine, image) = Client.bothAsyncImages()
        #expect(mine.name == "mine")
        #expect(drawn(image).contains("b5c empty"))
        // Image options of TUIBitmaps, spelled through the umbrella, on an
        // image of a file that is not there, so it is still loading when it is
        // drawn: TUIImage's colour mode, which only a decoded picture reads
        // (so here it is checked for compiling only), and a caption without a
        // spinner, which the loading image draws instead of "Loading...", so
        // the drawing shows the options reach the image.
        let caption = "b5c option"
        let optioned = TUI.Image(TUI.ImageSource.file("/b5c/missing.png"))
            .imageColorMode(TUI.ASCIIColorMode.mono)
            .imagePlaceholder(caption)
            .imagePlaceholderSpinner(false)
        let optionedLines = drawn(optioned)
        #expect(optionedLines.contains(caption), "\(optionedLines)")
        #expect(TUI.ImageFitTarget.viewport.b5cMarker == 3)
        // The reflected names: a module left compiling in TUIFoundation
        // would still build, and read `TUIFoundation.` here.
        #expect(String(reflecting: type(of: image)) == "TUIBitmaps.AsyncImage<TUIFoundation.Text>")
        #expect(String(reflecting: TUI.ImageFitTarget.self) == "TUIBitmaps.ImageFitTarget")
        #expect(String(reflecting: TUI.ASCIIColorMode.self) == "TUIImage.ASCIIColorMode")
    }

    @Test("A qualified name reaches TUITextInput and the modules peeled out of it, through the umbrella")
    func qualifiedNamesReachTheTextInputGroup() {
        func drawn(_ view: some TUI.View, height: Int) -> String {
            TUI.renderToBuffer(view, context: makeRenderContext(width: 40, height: height)).lines
                .map(\.stripped).joined(separator: "\n")
        }
        // From Sources/TUITextInput: a text field beside an app's own
        // `TextField`, drawn.
        let (mine, field) = Client.bothTextFields(text: "b7 text")
        #expect(mine.name == "mine")
        let fieldLines = drawn(field, height: 1)
        #expect(fieldLines.contains("b7 text"), "\(fieldLines)")
        // From Sources/TUIPickers, which compiled into the same module until
        // step C8 peeled it into TUIPickers: a radio group, drawn.
        let radios = TUI.RadioButtonGroup(selection: TUI.Binding.constant(1)) {
            TUI.RadioButtonItem(1, "b7 radio")
        }
        let radioLines = drawn(radios, height: 1)
        #expect(radioLines.contains("b7 radio"), "\(radioLines)")
        // From Sources/TUIForms, which compiled into the same module until
        // step C6 peeled it into TUIForms: labeled content, drawn.
        let labeled = TUI.LabeledContent("b7 label", value: "b7 value")
        let labeledLines = drawn(labeled, height: 1)
        #expect(labeledLines.contains("b7 label") && labeledLines.contains("b7 value"), "\(labeledLines)")
        // From Sources/TUISearch, which compiled into the same module until
        // step C5 peeled it into TUISearch: a member an app's extension adds
        // to a search field placement.
        #expect(TUI.SearchFieldPlacement.automatic.b7Marker == 7)
        // From Sources/TUINumericControls, which compiled into the same
        // module until step C7 peeled it into TUINumericControls: a gauge,
        // drawn with its label.
        let gauge = TUI.Gauge(value: 0.5) { TUI.Text(verbatim: "b7 gauge") }
        let gaugeLines = drawn(gauge, height: 2)
        #expect(gaugeLines.contains("b7 gauge"), "\(gaugeLines)")
        // One reflected name from each directory: a directory left compiling
        // in TUIFoundation would still build, and read
        // `TUIFoundation.` here.
        #expect(String(reflecting: type(of: field)) == "TUITextInput.TextField<TUIFoundation.Text>")
        #expect(String(reflecting: TUI.RadioButtonOrientation.self) == "TUIPickers.RadioButtonOrientation")
        #expect(String(reflecting: TUI.AutomaticFormStyle.self) == "TUIForms.AutomaticFormStyle")
        #expect(String(reflecting: TUI.SearchFieldPlacement.self) == "TUISearch.SearchFieldPlacement")
        #expect(String(reflecting: TUI.TrackStyle.self) == "TUINumericControls.TrackStyle")
    }

    @Test("A TUI type's reflected name is its declaring module's, not the umbrella's")
    func reflectedNamesNameTheDeclaringModule() {
        // So `String(reflecting:)`, `dump` and the debugger say
        // `TUIFoundation.Text`: the umbrella declares nothing. (`Text`
        // stays in TUIFoundation as the split goes on; a type that is
        // carved into another module takes that module's name.) Both
        // expectations read `TUI.` before step B1, when `Label` and `Text`
        // were the TUI module's.
        #expect(String(reflecting: TUI.Text.self) == "TUIFoundation.Text")
        // A generic type names each argument's module as well: TUIStyling's
        // `Color` was never the TUI module's, so only the other two moved.
        #expect(
            String(reflecting: TUI.Label<TUI.Text, TUI.Color>.self)
                == "TUIFoundation.Label<TUIFoundation.Text, TUIStyling.Color>")
        // Step B2 carved these out of TUIFoundation, and each read
        // `TUIFoundation.` between B1 and B2: a carve renames what an app
        // sees of every type it moves (decisions SPB2, "What an app can see").
        #expect(String(reflecting: TUI.TerminalClient.self) == "TUITerminalHost.TerminalClient")
        #expect(
            String(reflecting: TUI.LocalizationService.Language.self)
                == "TUIStrings.LocalizationService.Language")
        #expect(
            String(reflecting: TUI.SystemFormatStyle.Timer.self) == "TUIStrings.SystemFormatStyle.Timer")
        // Step B3 carved these out (decisions SPB3, "What an app can see");
        // each read `TUIFoundation.` between B1 and B3. A generic type of
        // TUIApp names TUIFoundation for its argument.
        #expect(
            String(reflecting: TUI.WindowGroup<TUI.Text>.self)
                == "TUIApp.WindowGroup<TUIFoundation.Text>")
        #expect(String(reflecting: TUI.DefaultWindowToolbarStyle.self) == "TUIApp.DefaultWindowToolbarStyle")
        // Step B4 carved these out (decisions SPB4, "What an app can see");
        // each read `TUIFoundation.` between B1 and B4.
        #expect(String(reflecting: TUI.ColorPicker.self) == "TUIColorPicker.ColorPicker")
        #expect(String(reflecting: TUI.ColorPickerPanel.self) == "TUIColorPicker.ColorPickerPanel")
        // C9b peeled these out of TUIColorPicker; each read
        // `TUIColorPicker.` between B4 and C9b (and `TUIFoundation.`
        // between B1 and B4), and `TUIColorEditors.` from C9b to
        // 2026-10-12, when the gradient editor went back to
        // TUIColorPicker and the curve editors' module was renamed.
        #expect(String(reflecting: TUI.GradientEditorPanel.self) == "TUIColorPicker.GradientEditorPanel")
        #expect(String(reflecting: TUI.ToneCurveEditorPanel.self) == "TUICurveEditors.ToneCurveEditorPanel")
        #expect(
            String(reflecting: TUI.ChannelCurveEditorPanel.self) == "TUICurveEditors.ChannelCurveEditorPanel")
        // Step B5 carved these out (decisions SPB5, "What an app can see");
        // each read `TUIFoundation.` between B1 and B5. A type from
        // Sources/TUIPresentation named TUINavigation, the module that
        // compiled it, until step C1 gave it a module of its own (decisions
        // SPC1, "What an app can see"): it read `TUINavigation.` from B5 to
        // C1.
        #expect(String(reflecting: TUI.NavigationPath.self) == "TUINavigation.NavigationPath")
        #expect(
            String(reflecting: TUI.NavigationSplitViewVisibility.self)
                == "TUINavigation.NavigationSplitViewVisibility")
        #expect(String(reflecting: TUI.PresentationDetent.self) == "TUIPresentation.PresentationDetent")
        // Step B6 carved these out (decisions SPB6, "What an app can see");
        // each read `TUIFoundation.` between B1 and B6. A type from
        // Sources/TUITables names TUITables since step C2 (decisions
        // SPC2, "What an app can see"), one from Sources/TUITabs TUITabs
        // since step C3, and one from Sources/TUIGrid TUIGrid since step
        // C4 (decisions SPC3, "What an app can see"): each read `TUILists.`
        // from B6 until its peel.
        #expect(String(reflecting: TUI.SidebarListStyle.self) == "TUILists.SidebarListStyle")
        #expect(String(reflecting: TUI.TableColumnCustomizationBehavior.self)
            == "TUITables.TableColumnCustomizationBehavior")
        #expect(String(reflecting: TUI.TabBarPlacement.self) == "TUITabs.TabBarPlacement")
        #expect(String(reflecting: TUI.GridItem.Size.self) == "TUIGrid.GridItem.Size")
        // Step B5b carved these out (decisions SPB5b, "What an app can see");
        // each read `TUIFoundation.` between B1 and B5b.
        #expect(String(reflecting: TUI.StatusBar.self) == "TUIChrome.StatusBar")
        #expect(String(reflecting: TUI.NotificationService.self) == "TUIChrome.NotificationService")
        #expect(String(reflecting: TUI.ScrollTransitionPhase.self) == "TUIEffects.ScrollTransitionPhase")
        #expect(String(reflecting: TUI.MenuOrder.self) == "TUIMenus.MenuOrder")
        // Step B5c carved these out (decisions SPB5c, "What an app can see");
        // each read `TUIFoundation.` between B1 and B5c.
        #expect(String(reflecting: TUI.ImageSource.self) == "TUIBitmaps.ImageSource")
        #expect(String(reflecting: TUI.AsyncImagePhase.self) == "TUIBitmaps.AsyncImagePhase")
        // Step B7 carved these out (decisions SPB7, "What an app can see");
        // each read `TUIFoundation.` between B1 and B7. A type from
        // Sources/TUIForms names TUIForms since step C6, one from
        // Sources/TUISearch TUISearch since step C5 (decisions SPC5,
        // "What an app can see"), and one from Sources/TUIPickers
        // TUIPickers since step C8 and one from
        // Sources/TUINumericControls TUINumericControls since step C7
        // (decisions SPC7, "What an app can see"): each read
        // `TUITextInput.` from B7 until its peel.
        #expect(String(reflecting: TUI.TabWidth.self) == "TUITextInput.TabWidth")
        #expect(String(reflecting: TUI.DatePickerComponents.self) == "TUIPickers.DatePickerComponents")
        #expect(String(reflecting: TUI.GroupedFormStyle.self) == "TUIForms.GroupedFormStyle")
        #expect(String(reflecting: TUI.SearchFieldIconPlacement.self) == "TUISearch.SearchFieldIconPlacement")
        #expect(String(reflecting: TUI.IndeterminateStyle.self) == "TUINumericControls.IndeterminateStyle")
    }
}
