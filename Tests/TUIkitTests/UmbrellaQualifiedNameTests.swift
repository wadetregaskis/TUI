//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UmbrellaQualifiedNameTests.swift
//
//  An app spells `TUIkit.X` to reach TUIkit's `X` past a type of its own with
//  the same name. Since step B1 of the module split the TUIkit module declares
//  nothing: `X` is TUIkitFoundation's, or a lower module's, reached through the
//  umbrella's `@_exported import`s. Qualified lookup does go through them —
//  probe t14 of the plan's step 0b measured it on Swift 6.2.4 (Xcode and
//  swift.org) and 6.3.3 (Linux) — and this file keeps that probe's shapes as a
//  test, so a carve that broke one would stop it compiling. It imports only
//  `TUIkit`, as an app does: no `@testable`, no lower module.
//
//  t14 measured one re-export. Since step B2 a type of TUIkitStrings or
//  TUIkitTerminalHost is two away: the umbrella re-exports TUIkitFoundation,
//  which re-exports those modules (the umbrella names neither). The second
//  test spells such types through the umbrella, so it is the measurement of
//  that case, and a carve that dropped a re-export below the umbrella would
//  stop it compiling too.
//
//  Step B3 carved TUIkitApp out the other way: built on TUIkitFoundation,
//  not under it, so TUIkitFoundation cannot re-export it, and the umbrella
//  does, beside TUIkitFoundation. The third test spells its types through the
//  umbrella, so a carve that left TUIkitApp out of the umbrella's re-exports
//  would stop this file compiling as well.
//
//  Step B4 carved TUIkitColorPicker out the same way, so the umbrella
//  re-exports a second module beside TUIkitFoundation. The fourth test spells
//  its types through the umbrella: an app's own `ColorPicker` beside it is the
//  case an app meets (a colour picker of its own, written before it adopted
//  TUIkit), and a carve that left the module out of the umbrella's re-exports
//  stops this file compiling.
//
//  Step B5 carved the Navigation group the same way: one module,
//  TUIkitNavigation, that compiles two directories of the planned split,
//  Sources/TUIkitNavigation and Sources/TUIkitPresentation, until step C1 peels
//  the second into a module of its own. The fifth test spells a type from each
//  directory through the umbrella, beside an app's own `Alert` (the case an app
//  meets: an alert model of its own), so this file stops compiling if `import
//  TUIkit` misses the types of either directory. Two holes it leaves to others.
//  The umbrella's own `@_exported import TUIkitNavigation`: until C1,
//  TUIkitColorPicker re-exports TUIkitNavigation too (its panels are
//  TUIkitPresentation's `Dialog`s), and the umbrella re-exports
//  TUIkitColorPicker, so this file compiles without that line.
//  Tools/ModuleMap's `umbrella` check holds it: the umbrella re-exports, by
//  name, every module built on TUIkitFoundation. And a directory left in
//  TUIkitFoundation: its types would still compile, as TUIkitFoundation's, so
//  the test's reflected name, `TUIkitNavigation.Alert`, catches it at run time,
//  not the compiler.
//
//  Step C1 peeled Sources/TUIkitPresentation out of that group into a module
//  of its own, TUIkitPresentation, the first peel. The fifth test's alert,
//  and the detent among the reflected names, read `TUIkitPresentation.` since;
//  they read `TUIkitNavigation.` from B5 to C1, so a peel renames what an app
//  sees of each type it moves, as a carve does. The same two holes, the same
//  two guards: TUIkitColorPicker re-exports TUIkitPresentation (its panels are
//  `Dialog`s) in place of TUIkitNavigation, so the umbrella's own line for
//  each is the `umbrella` check's; and a directory left compiling in
//  TUIkitNavigation would still compile here, so the reflected names catch it.
//
//  Step B6 carved the Lists group the same way: one module, TUIkitLists, that
//  compiled four directories of the planned split, Sources/TUIkitLists,
//  TUIkitTables, TUIkitTabs and TUIkitGrid, until steps C2 to C4 peeled the
//  last three into modules of their own. The sixth test spells a type from each
//  directory through the umbrella and draws it, the table beside an app's own
//  `Table` (the case an app meets: a database table model of its own). It
//  leaves the same two holes to the same two guards: TUIkitColorPicker
//  re-exports TUIkitLists (its panel is a `TabView`): directly until C3,
//  and after it through TUIkitTabs, which depends on TUIkitLists. So the
//  umbrella's own line is the `umbrella` check's for good; and a directory
//  left in TUIkitFoundation would still compile, so the reflected names, one
//  per directory, catch it at run time.
//
//  Step C2 peeled Sources/TUIkitTables out of that group into a module of its
//  own, TUIkitTables, built on TUIkitLists, which it re-exports. The sixth
//  test's table, and the column customization behaviour among the reflected
//  names, read `TUIkitTables.` since; they read `TUIkitLists.` from B6 to C2.
//  Nothing but the umbrella re-exports TUIkitTables, so this file stops
//  compiling without the umbrella's line for it.
//
//  Step C3 peeled Sources/TUIkitTabs out of the group into TUIkitTabs, built
//  on TUIkitLists, which it re-exports. The sixth test's tab view, and the
//  tab bar placement among the reflected names, read `TUIkitTabs.` since;
//  they read `TUIkitLists.` from B6 to C3. TUIkitColorPicker re-exports
//  TUIkitTabs (its panel is a `TabView`), so the umbrella's own line for it
//  is the `umbrella` check's, as TUIkitPresentation's is.
//
//  Step C4 peeled Sources/TUIkitGrid out of the group into TUIkitGrid, built
//  on TUIkitFoundation alone, which left TUIkitLists an ordinary module. The
//  sixth test's grid, and the grid item among the reflected names, read
//  `TUIkitGrid.` since; they read `TUIkitLists.` from B6 to C4. Nothing but
//  the umbrella re-exports TUIkitGrid, so this file stops compiling without
//  the umbrella's line for it.
//
//  Step B5b carved three leaves the same way, each a module of its own:
//  TUIkitChrome, TUIkitEffects and TUIkitMenus. The seventh test spells and
//  draws a type of each through the umbrella, the menu beside an app's own
//  `Menu` (the case an app meets: a menu model of its own). The umbrella is
//  the only module that re-exports TUIkitEffects and TUIkitMenus, so this
//  file stops compiling without either line. TUIkitApp and TUIkitNavigation
//  (TUIkitPresentation since step C1) re-export TUIkitChrome, which they
//  depend on, so the umbrella's own line for it is the `umbrella` check's, for
//  good. A module left compiling in
//  TUIkitFoundation would still compile here; the reflected names, one per
//  module, catch it at run time.
//
//  Step B5c carved TUIkitBitmaps the same way, `Image`'s bitmap path, and took
//  TUIkitImage out of TUIkitFoundation's re-exports. The eighth test spells
//  and draws its types through the umbrella, an `AsyncImage` beside an app's
//  own `AsyncImage` (the case an app meets: an image loader of its own), and
//  three of its image options on an image still loading: one that takes
//  TUIkitImage's `ASCIIColorMode`, and a caption with the spinner off, which
//  the loading image draws, so the drawing shows the options reach it. The
//  umbrella is the only module that re-exports TUIkitBitmaps, so this file
//  stops compiling without its line. TUIkitImage has three: the umbrella's
//  own, TUIkitBitmaps' and TUIkitColorPicker's (their direct dependency);
//  nothing checks the umbrella's line for it, but an app would lose
//  `ASCIIColorMode` only with all three gone. A module left compiling in
//  TUIkitFoundation would still compile here; the reflected names catch it at
//  run time.
//
//  Step B7 carved the TextInput group the same way as B5's and B6's: one
//  module, TUIkitTextInput, that compiled five directories of the planned
//  split, Sources/TUIkitTextInput, TUIkitPickers, TUIkitForms, TUIkitSearch
//  and TUIkitNumericControls, until steps C5 to C8 peel the last four into
//  modules of their own (step C6 has peeled the forms, below). It took the
//  last directories out of
//  TUIkitFoundation. The ninth test spells a type from each directory through
//  the umbrella and draws it, the text field beside an app's own `TextField`
//  (the case an app meets: a form model of its own). It leaves the same two
//  holes to the same two guards: TUIkitColorPicker re-exports TUIkitTextInput
//  (its editors are sliders, its hex field a text field), so the umbrella's
//  own line is the `umbrella` check's; and a directory left compiling in
//  TUIkitFoundation would still compile here, so the reflected names, one per
//  directory, catch it at run time.
//
//  Step C6 peeled Sources/TUIkitForms out of the group into TUIkitForms,
//  built on TUIkitFoundation alone. The ninth test's labeled content, and the
//  form styles among the reflected names, read `TUIkitForms.` since; they
//  read `TUIkitTextInput.` from B7 to C6. Nothing but the umbrella
//  re-exports TUIkitForms, so this file stops compiling without the
//  umbrella's line for it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkit

/// An app's own `Label`, beside TUIkit's.
private enum Client {
    struct Label {
        let name: String
    }

    /// Both labels: the app's by its plain name, TUIkit's by the umbrella's.
    @MainActor
    static func both() -> (Label, TUIkit.Label<TUIkit.Text, TUIkit.Text>) {
        (Label(name: "mine"), TUIkit.Label { TUIkit.Text(verbatim: "t14 title") } icon: { TUIkit.Text(verbatim: "*") })
    }

    /// An app's own `TerminalClient`, beside TUIkitTerminalHost's.
    struct TerminalClient {
        let name: String
    }

    /// Both clients: the app's by its plain name, and a program of TUIkit's
    /// by the umbrella's spelling, two re-exports down.
    static func bothClients() -> (TerminalClient, TUIkit.TerminalClient.Program) {
        (TerminalClient(name: "mine"), TUIkit.TerminalClient.Program.ghostty)
    }

    /// An app's own `Scene`, beside TUIkitApp's protocol.
    struct Scene {
        let name: String
    }

    /// Both scenes: the app's by its plain name, and a window group by the
    /// umbrella's spelling of TUIkitApp's protocol and type.
    @MainActor
    static func bothScenes() -> (Scene, some TUIkit.Scene) {
        (Scene(name: "mine"), TUIkit.WindowGroup { TUIkit.Text(verbatim: "b3") })
    }

    /// An app's own `ColorPicker`, beside TUIkitColorPicker's view.
    struct ColorPicker {
        let name: String
    }

    /// Both pickers: the app's by its plain name, TUIkit's by the umbrella's.
    @MainActor
    static func bothPickers(selection: TUIkit.Binding<TUIkit.Color>) -> (ColorPicker, TUIkit.ColorPicker) {
        (ColorPicker(name: "mine"), TUIkit.ColorPicker("b4", selection: selection))
    }

    /// An app's own `Alert`, beside TUIkitPresentation's alert view (which
    /// TUIkitNavigation compiled from step B5 until step C1).
    struct Alert {
        let name: String
    }

    /// Both alerts: the app's by its plain name, TUIkit's by the umbrella's,
    /// with a TUIkitFoundation button as its action.
    @MainActor
    static func bothAlerts(title: String) -> (Alert, TUIkit.Alert<TUIkit.Button>) {
        (Alert(name: "mine"), TUIkit.Alert(title: title, message: "b5 message") {
            TUIkit.Button(action: {}, label: { TUIkit.Text(verbatim: "b5 ok") })
        })
    }

    /// An app's own `Table`, beside TUIkitTables' table view (which
    /// TUIkitLists compiled from Sources/TUIkitTables until step C2).
    struct Table {
        let name: String
    }

    /// A row of TUIkit's table.
    struct Row: Identifiable {
        let id: Int
        let name: String
    }

    /// Both tables: the app's by its plain name, TUIkit's by the umbrella's,
    /// with a column spelled the same way.
    @MainActor
    static func bothTables(rows: [Row]) -> (Table, TUIkit.Table<Row>) {
        (Table(name: "mine"), TUIkit.Table(rows) { TUIkit.TableColumn("b6 name", value: \Row.name) })
    }

    /// An app's own `Menu`, beside TUIkitMenus' view.
    struct Menu {
        let name: String
    }

    /// Both menus: the app's by its plain name, TUIkit's by the umbrella's,
    /// with a TUIkitFoundation button as its item.
    @MainActor
    static func bothMenus() -> (Menu, TUIkit.Menu<TUIkit.Text, TUIkit.Button>) {
        (Menu(name: "mine"), TUIkit.Menu("b5b menu") { TUIkit.Button("b5b item") {} })
    }

    /// An app's own `AsyncImage`, beside TUIkitBitmaps' view.
    struct AsyncImage {
        let name: String
    }

    /// Both async images: the app's by its plain name, TUIkit's by the
    /// umbrella's, with no URL, so it stays in its empty phase and draws what
    /// its content makes of that.
    @MainActor
    static func bothAsyncImages() -> (AsyncImage, TUIkit.AsyncImage<TUIkit.Text>) {
        (AsyncImage(name: "mine"), TUIkit.AsyncImage(url: nil) { phase in
            TUIkit.Text(verbatim: phase.image == nil ? "b5c empty" : "b5c image")
        })
    }

    /// An app's own `TextField`, beside TUIkitTextInput's view.
    struct TextField {
        let name: String
    }

    /// Both text fields: the app's by its plain name, TUIkit's by the
    /// umbrella's, bound to a constant text so it draws that text.
    @MainActor
    static func bothTextFields(text: String) -> (TextField, TUIkit.TextField<TUIkit.Text>) {
        (TextField(name: "mine"), TUIkit.TextField("b7 title", text: TUIkit.Binding.constant(text)))
    }
}

/// A style conforming through the umbrella's spelling of the protocol.
private struct BracketedLabelStyle: TUIkit.LabelStyle {
    func makeBody(configuration: Configuration) -> some TUIkit.View {
        TUIkit.HStack(spacing: 0) {
            TUIkit.Text(verbatim: "[")
            configuration.title
            TUIkit.Text(verbatim: "]")
        }
    }
}

extension TUIkit.Label where Title == TUIkit.Text, Icon == TUIkit.Text {
    /// A member an app adds to TUIkit's type through the umbrella's name.
    fileprivate var t14Marker: Int { 14 }
}

extension TUIkit.LocalizationService.Language {
    /// A member an app adds, through the umbrella's name, to a type of
    /// TUIkitStrings, which reaches the umbrella through TUIkitFoundation.
    fileprivate var b2Marker: String { "b2-\(rawValue)" }
}

extension TUIkit.WindowGroup {
    /// A member an app adds, through the umbrella's name, to a type of
    /// TUIkitApp, which the umbrella re-exports itself.
    fileprivate var b3Marker: Int { 3 }
}

extension TUIkit.ColorPicker {
    /// A member an app adds, through the umbrella's name, to a type of
    /// TUIkitColorPicker, which the umbrella re-exports itself.
    fileprivate var b4Marker: Int { 4 }
}

extension TUIkit.NavigationPath {
    /// A member an app adds, through the umbrella's name, to a type of
    /// TUIkitNavigation, which only the umbrella re-exports since step C1
    /// (TUIkitColorPicker did too, from step B5 until then).
    fileprivate var b5Marker: Int { 5 + count }
}

extension TUIkit.MenuOrder {
    /// A member an app adds, through the umbrella's name, to a type of
    /// TUIkitMenus, which only the umbrella re-exports.
    fileprivate var b5bMarker: Int { self == .fixed ? 1 : 0 }
}

extension TUIkit.ToolbarPlacement {
    /// A member an app adds, through the umbrella's name, to a type of
    /// TUIkitChrome, which the umbrella re-exports (and so do TUIkitApp and
    /// TUIkitPresentation; TUIkitNavigation did until step C1).
    fileprivate var b5bMarker: Int { self == .bottomBar ? 2 : 0 }
}

extension TUIkit.ImageFitTarget {
    /// A member an app adds, through the umbrella's name, to a type of
    /// TUIkitBitmaps, which only the umbrella re-exports.
    fileprivate var b5cMarker: Int { self == .viewport ? 3 : 0 }
}

extension TUIkit.SearchFieldPlacement {
    /// A member an app adds to TUIkitTextInput's type (Sources/TUIkitSearch,
    /// until step C5), by the umbrella's spelling.
    fileprivate var b7Marker: Int { self == .automatic ? 7 : 0 }
}

extension TUIkit.TabViewCustomization {
    /// A member an app adds, through the umbrella's name, to a type of
    /// TUIkitTabs (TUIkitLists' from step B6 until step C3), which the
    /// umbrella re-exports itself, and TUIkitColorPicker as well.
    fileprivate var b6Marker: Int { self == TUIkit.TabViewCustomization() ? 6 : -6 }
}

@MainActor
@Suite("TUIkit.X in an app's source")
struct UmbrellaQualifiedNameTests {
    @Test("A qualified name reaches the declaring module's type, beside an app's type of the same name")
    func qualifiedNamesResolveThroughTheUmbrella() {
        let (mine, theirs) = Client.both()
        #expect(mine.name == "mine")
        #expect(theirs.t14Marker == 14)
        // An initializer as a value, and a function a lower module declares.
        let make: (String) -> TUIkit.Text = TUIkit.Text.init(verbatim:)
        let buffer: TUIkit.FrameBuffer = TUIkit.renderToBuffer(
            TUIkit.VStack { theirs.labelStyle(BracketedLabelStyle()); make("made") },
            context: makeRenderContext(width: 40, height: 2))
        let lines = buffer.lines.map(\.stripped)
        #expect(lines.first?.contains("[t14 title]") == true, "\(lines)")
        #expect(lines.last?.contains("made") == true, "\(lines)")
    }

    @Test("A qualified name reaches a module that TUIkitFoundation re-exports in turn")
    func qualifiedNamesResolveThroughTwoReExports() {
        // TUIkitTerminalHost's types: beside an app's own `TerminalClient`,
        // and a static function as a value.
        let (mine, program) = Client.bothClients()
        #expect(mine.name == "mine")
        #expect(program == .ghostty)
        let advance: (Character, TUIkit.TerminalClient.Program) -> Int =
            TUIkit.TerminalClient.cursorAdvance(of:on:)
        #expect(advance("a", program) == 1)
        // TUIkitStrings' types: a nested type through a class, and a member an
        // app's extension adds to it.
        let language: TUIkit.LocalizationService.Language = .german
        #expect(language.b2Marker == "b2-de")
        #expect(TUIkit.LocalizationService.Language.allCases.contains(language))
    }

    @Test("A qualified name reaches TUIkitApp, which the umbrella re-exports beside TUIkitFoundation")
    func qualifiedNamesReachTheModuleBuiltOnFoundation() {
        // TUIkitApp's types: a scene beside an app's own `Scene`, as an
        // opaque `some TUIkit.Scene`, and a member an app's extension adds.
        let (mine, group) = Client.bothScenes()
        #expect(mine.name == "mine")
        #expect(String(reflecting: type(of: group)) == "TUIkitApp.WindowGroup<TUIkitFoundation.Text>")
        #expect(TUIkit.WindowGroup { TUIkit.Text(verbatim: "b3") }.b3Marker == 3)
        // A conformance spelled through the umbrella, and a free function of
        // TUIkitApp's as a value (never called: it writes to the terminal).
        let style: any TUIkit.WindowToolbarStyle = TUIkit.DefaultWindowToolbarStyle()
        #expect(style is TUIkit.DefaultWindowToolbarStyle)
        let draw: (() -> TUIkit.Text) -> Void = TUIkit.renderOnce(content:)
        _ = draw
    }

    @Test("A qualified name reaches TUIkitColorPicker, which the umbrella re-exports beside TUIkitApp")
    func qualifiedNamesReachTheColorPicker() {
        // TUIkitColorPicker's view beside an app's own `ColorPicker`, a member
        // an app's extension adds to it, and the view drawn: its label comes
        // out of the render.
        let (mine, picker) = Client.bothPickers(selection: .constant(TUIkit.Color.red))
        #expect(mine.name == "mine")
        #expect(picker.b4Marker == 4)
        let lines = TUIkit.renderToBuffer(picker, context: makeRenderContext(width: 60, height: 3)).lines
            .map(\.stripped)
        #expect(lines.first?.contains("b4") == true, "\(lines)")
        // A curve editor, whose initializer takes a TUIkitImage type, spelled
        // through the umbrella too.
        let panel = TUIkit.ToneCurveEditorPanel(
            stops: .constant([TUIkit.ASCIIToneCurve.Stop]()), isPresented: .constant(true))
        #expect(String(reflecting: type(of: panel)) == "TUIkitColorPicker.ToneCurveEditorPanel")
    }

    @Test("A qualified name reaches TUIkitNavigation and TUIkitPresentation, which the umbrella re-exports")
    func qualifiedNamesReachTheNavigationGroup() {
        // From Sources/TUIkitNavigation: a stack, drawn, and a member an app's
        // extension adds to its path.
        let stack = TUIkit.NavigationStack { TUIkit.Text(verbatim: "b5 root") }
        let lines = TUIkit.renderToBuffer(stack, context: makeRenderContext(width: 40, height: 4)).lines
            .map(\.stripped)
        #expect(lines.contains { $0.contains("b5 root") }, "\(lines)")
        #expect(TUIkit.NavigationPath([1, 2]).b5Marker == 7)
        // From Sources/TUIkitPresentation, which compiled into the same module
        // from step B5 until step C1 peeled it into a module of its own: an
        // alert beside an app's own `Alert`, drawn.
        let (mine, alert) = Client.bothAlerts(title: "b5 alert")
        #expect(mine.name == "mine")
        let drawn = TUIkit.renderToBuffer(alert, context: makeRenderContext(width: 40, height: 8)).lines
            .map(\.stripped).joined(separator: "\n")
        #expect(drawn.contains("b5 alert") && drawn.contains("b5 ok"), "\(drawn)")
        #expect(String(reflecting: type(of: alert)) == "TUIkitPresentation.Alert<TUIkitFoundation.Button>")
    }

    @Test("A qualified name reaches TUIkitLists and the three modules peeled out of it, through the umbrella")
    func qualifiedNamesReachTheListsGroup() {
        func drawn(_ view: some TUIkit.View, height: Int) -> String {
            TUIkit.renderToBuffer(view, context: makeRenderContext(width: 40, height: height)).lines
                .map(\.stripped).joined(separator: "\n")
        }
        // From Sources/TUIkitLists: a list, drawn.
        let list = TUIkit.List { TUIkit.Text(verbatim: "b6 row") }
        #expect(drawn(list, height: 4).contains("b6 row"))
        // From Sources/TUIkitTables, which compiled into the same module until
        // step C2 peeled it into TUIkitTables: a table beside an app's own
        // `Table`, drawn.
        let (mine, table) = Client.bothTables(rows: [Client.Row(id: 1, name: "b6 cell")])
        #expect(mine.name == "mine")
        let tableLines = drawn(table, height: 6)
        #expect(tableLines.contains("b6 name") && tableLines.contains("b6 cell"), "\(tableLines)")
        // From Sources/TUIkitTabs, which compiled into the same module until
        // step C3 peeled it into TUIkitTabs: a tab view, drawn, and a member
        // an app's extension adds to its customization.
        let tabs = TUIkit.TabView {
            TUIkit.Tab("b6 tab", systemImage: "list.bullet") { TUIkit.Text(verbatim: "b6 body") }
        }
        #expect(drawn(tabs, height: 6).contains("b6 body"))
        #expect(TUIkit.TabViewCustomization().b6Marker == 6)
        // From Sources/TUIkitGrid, which compiled into the same module until
        // step C4 peeled it into TUIkitGrid: a grid, drawn.
        let grid = TUIkit.Grid { TUIkit.GridRow { TUIkit.Text(verbatim: "b6 a"); TUIkit.Text(verbatim: "b6 b") } }
        #expect(drawn(grid, height: 2).contains("b6 a"))
        // One reflected name from each directory: a directory left compiling
        // in TUIkitFoundation would still build, and read
        // `TUIkitFoundation.` here.
        #expect(String(reflecting: type(of: table)).hasPrefix("TUIkitTables.Table<"))
        #expect(String(reflecting: type(of: tabs)).hasPrefix("TUIkitTabs.TabView<"))
        #expect(String(reflecting: type(of: grid)).hasPrefix("TUIkitGrid.Grid<"))
        #expect(String(reflecting: TUIkit.EditMode.self) == "TUIkitLists.EditMode")
        #expect(String(reflecting: TUIkit.TabViewCustomization.self) == "TUIkitTabs.TabViewCustomization")
        #expect(String(reflecting: TUIkit.GridItem.self) == "TUIkitGrid.GridItem")
    }

    @Test("A qualified name reaches TUIkitChrome, TUIkitEffects and TUIkitMenus, which the umbrella re-exports")
    func qualifiedNamesReachTheChromeEffectsAndMenus() {
        func drawn(_ view: some TUIkit.View, height: Int) -> String {
            TUIkit.renderToBuffer(view, context: makeRenderContext(width: 40, height: height)).lines
                .map(\.stripped).joined(separator: "\n")
        }
        // TUIkitMenus: a menu beside an app's own `Menu`, drawn (its closed
        // button shows its title), and a member an app's extension adds to its
        // order.
        let (mine, menu) = Client.bothMenus()
        #expect(mine.name == "mine")
        let menuLines = drawn(menu, height: 2)
        #expect(menuLines.contains("b5b menu"), "\(menuLines)")
        #expect(TUIkit.MenuOrder.fixed.b5bMarker == 1)
        // TUIkitEffects: a colour effect and a transition, spelled through the
        // umbrella, over a TUIkitFoundation text, drawn.
        let effected = TUIkit.Text(verbatim: "b5b effect").grayscale(0.5)
            .transition(TUIkit.AnyTransition.opacity)
        #expect(drawn(effected, height: 1).contains("b5b effect"))
        // TUIkitChrome: help on a text, drawn as the text (the help is a
        // tooltip, which the window draws), and a member an app's extension
        // adds to a toolbar placement.
        let helped = TUIkit.Text(verbatim: "b5b help").help("b5b tip")
        #expect(drawn(helped, height: 1).contains("b5b help"))
        #expect(TUIkit.ToolbarPlacement.bottomBar.b5bMarker == 2)
        // One reflected name from each module: a module left compiling in
        // TUIkitFoundation would still build, and read `TUIkitFoundation.`
        // here.
        #expect(String(reflecting: type(of: menu)).hasPrefix("TUIkitMenus.Menu<"))
        #expect(String(reflecting: TUIkit.AnyTransition.self) == "TUIkitEffects.AnyTransition")
        #expect(String(reflecting: TUIkit.ToolbarPlacement.self) == "TUIkitChrome.ToolbarPlacement")
    }

    @Test("A qualified name reaches TUIkitBitmaps, which the umbrella re-exports, and TUIkitImage beside it")
    func qualifiedNamesReachTheBitmaps() {
        func drawn(_ view: some TUIkit.View) -> String {
            TUIkit.renderToBuffer(view, context: makeRenderContext(width: 40, height: 1)).lines
                .map(\.stripped).joined(separator: "\n")
        }
        // An async image beside an app's own `AsyncImage`, drawn: with no URL
        // it stays empty, and its content says so.
        let (mine, image) = Client.bothAsyncImages()
        #expect(mine.name == "mine")
        #expect(drawn(image).contains("b5c empty"))
        // Image options of TUIkitBitmaps, spelled through the umbrella, on an
        // image of a file that is not there, so it is still loading when it is
        // drawn: TUIkitImage's colour mode, which only a decoded picture reads
        // (so here it is checked for compiling only), and a caption without a
        // spinner, which the loading image draws instead of "Loading...", so
        // the drawing shows the options reach the image.
        let caption = "b5c option"
        let optioned = TUIkit.Image(TUIkit.ImageSource.file("/b5c/missing.png"))
            .imageColorMode(TUIkit.ASCIIColorMode.mono)
            .imagePlaceholder(caption)
            .imagePlaceholderSpinner(false)
        let optionedLines = drawn(optioned)
        #expect(optionedLines.contains(caption), "\(optionedLines)")
        #expect(TUIkit.ImageFitTarget.viewport.b5cMarker == 3)
        // The reflected names: a module left compiling in TUIkitFoundation
        // would still build, and read `TUIkitFoundation.` here.
        #expect(String(reflecting: type(of: image)) == "TUIkitBitmaps.AsyncImage<TUIkitFoundation.Text>")
        #expect(String(reflecting: TUIkit.ImageFitTarget.self) == "TUIkitBitmaps.ImageFitTarget")
        #expect(String(reflecting: TUIkit.ASCIIColorMode.self) == "TUIkitImage.ASCIIColorMode")
    }

    @Test("A qualified name reaches TUIkitTextInput and the module peeled out of it, through the umbrella")
    func qualifiedNamesReachTheTextInputGroup() {
        func drawn(_ view: some TUIkit.View, height: Int) -> String {
            TUIkit.renderToBuffer(view, context: makeRenderContext(width: 40, height: height)).lines
                .map(\.stripped).joined(separator: "\n")
        }
        // From Sources/TUIkitTextInput: a text field beside an app's own
        // `TextField`, drawn.
        let (mine, field) = Client.bothTextFields(text: "b7 text")
        #expect(mine.name == "mine")
        let fieldLines = drawn(field, height: 1)
        #expect(fieldLines.contains("b7 text"), "\(fieldLines)")
        // From Sources/TUIkitPickers (until step C8): a radio group, drawn.
        let radios = TUIkit.RadioButtonGroup(selection: TUIkit.Binding.constant(1)) {
            TUIkit.RadioButtonItem(1, "b7 radio")
        }
        let radioLines = drawn(radios, height: 1)
        #expect(radioLines.contains("b7 radio"), "\(radioLines)")
        // From Sources/TUIkitForms, which compiled into the same module until
        // step C6 peeled it into TUIkitForms: labeled content, drawn.
        let labeled = TUIkit.LabeledContent("b7 label", value: "b7 value")
        let labeledLines = drawn(labeled, height: 1)
        #expect(labeledLines.contains("b7 label") && labeledLines.contains("b7 value"), "\(labeledLines)")
        // From Sources/TUIkitSearch (until step C5): a member an app's
        // extension adds to a search field placement.
        #expect(TUIkit.SearchFieldPlacement.automatic.b7Marker == 7)
        // From Sources/TUIkitNumericControls (until step C7): a gauge, drawn
        // with its label.
        let gauge = TUIkit.Gauge(value: 0.5) { TUIkit.Text(verbatim: "b7 gauge") }
        let gaugeLines = drawn(gauge, height: 2)
        #expect(gaugeLines.contains("b7 gauge"), "\(gaugeLines)")
        // One reflected name from each directory: a directory left compiling
        // in TUIkitFoundation would still build, and read
        // `TUIkitFoundation.` here.
        #expect(String(reflecting: type(of: field)) == "TUIkitTextInput.TextField<TUIkitFoundation.Text>")
        #expect(String(reflecting: TUIkit.RadioButtonOrientation.self) == "TUIkitTextInput.RadioButtonOrientation")
        #expect(String(reflecting: TUIkit.AutomaticFormStyle.self) == "TUIkitForms.AutomaticFormStyle")
        #expect(String(reflecting: TUIkit.SearchFieldPlacement.self) == "TUIkitTextInput.SearchFieldPlacement")
        #expect(String(reflecting: TUIkit.TrackStyle.self) == "TUIkitTextInput.TrackStyle")
    }

    @Test("A TUIkit type's reflected name is its declaring module's, not the umbrella's")
    func reflectedNamesNameTheDeclaringModule() {
        // So `String(reflecting:)`, `dump` and the debugger say
        // `TUIkitFoundation.Text`: the umbrella declares nothing. (`Text`
        // stays in TUIkitFoundation as the split goes on; a type that is
        // carved into another module takes that module's name.) Both
        // expectations read `TUIkit.` before step B1, when `Label` and `Text`
        // were the TUIkit module's.
        #expect(String(reflecting: TUIkit.Text.self) == "TUIkitFoundation.Text")
        // A generic type names each argument's module as well: TUIkitStyling's
        // `Color` was never the TUIkit module's, so only the other two moved.
        #expect(
            String(reflecting: TUIkit.Label<TUIkit.Text, TUIkit.Color>.self)
                == "TUIkitFoundation.Label<TUIkitFoundation.Text, TUIkitStyling.Color>")
        // Step B2 carved these out of TUIkitFoundation, and each read
        // `TUIkitFoundation.` between B1 and B2: a carve renames what an app
        // sees of every type it moves (decisions SPB2, "What an app can see").
        #expect(String(reflecting: TUIkit.TerminalClient.self) == "TUIkitTerminalHost.TerminalClient")
        #expect(
            String(reflecting: TUIkit.LocalizationService.Language.self)
                == "TUIkitStrings.LocalizationService.Language")
        if #available(macOS 15, *) {
            #expect(
                String(reflecting: TUIkit.SystemFormatStyle.Timer.self) == "TUIkitStrings.SystemFormatStyle.Timer")
        }
        // Step B3 carved these out (decisions SPB3, "What an app can see");
        // each read `TUIkitFoundation.` between B1 and B3. A generic type of
        // TUIkitApp names TUIkitFoundation for its argument.
        #expect(
            String(reflecting: TUIkit.WindowGroup<TUIkit.Text>.self)
                == "TUIkitApp.WindowGroup<TUIkitFoundation.Text>")
        #expect(String(reflecting: TUIkit.DefaultWindowToolbarStyle.self) == "TUIkitApp.DefaultWindowToolbarStyle")
        // Step B4 carved these out (decisions SPB4, "What an app can see");
        // each read `TUIkitFoundation.` between B1 and B4.
        #expect(String(reflecting: TUIkit.ColorPicker.self) == "TUIkitColorPicker.ColorPicker")
        #expect(String(reflecting: TUIkit.ColorPickerPanel.self) == "TUIkitColorPicker.ColorPickerPanel")
        // Step B5 carved these out (decisions SPB5, "What an app can see");
        // each read `TUIkitFoundation.` between B1 and B5. A type from
        // Sources/TUIkitPresentation named TUIkitNavigation, the module that
        // compiled it, until step C1 gave it a module of its own (decisions
        // SPC1, "What an app can see"): it read `TUIkitNavigation.` from B5 to
        // C1.
        #expect(String(reflecting: TUIkit.NavigationPath.self) == "TUIkitNavigation.NavigationPath")
        #expect(
            String(reflecting: TUIkit.NavigationSplitViewVisibility.self)
                == "TUIkitNavigation.NavigationSplitViewVisibility")
        #expect(String(reflecting: TUIkit.PresentationDetent.self) == "TUIkitPresentation.PresentationDetent")
        // Step B6 carved these out (decisions SPB6, "What an app can see");
        // each read `TUIkitFoundation.` between B1 and B6. A type from
        // Sources/TUIkitTables names TUIkitTables since step C2 (decisions
        // SPC2, "What an app can see"), one from Sources/TUIkitTabs TUIkitTabs
        // since step C3, and one from Sources/TUIkitGrid TUIkitGrid since step
        // C4 (decisions SPC3, "What an app can see"): each read `TUIkitLists.`
        // from B6 until its peel.
        #expect(String(reflecting: TUIkit.SidebarListStyle.self) == "TUIkitLists.SidebarListStyle")
        #expect(String(reflecting: TUIkit.TableColumnCustomizationBehavior.self)
            == "TUIkitTables.TableColumnCustomizationBehavior")
        #expect(String(reflecting: TUIkit.TabBarPlacement.self) == "TUIkitTabs.TabBarPlacement")
        #expect(String(reflecting: TUIkit.GridItem.Size.self) == "TUIkitGrid.GridItem.Size")
        // Step B5b carved these out (decisions SPB5b, "What an app can see");
        // each read `TUIkitFoundation.` between B1 and B5b.
        #expect(String(reflecting: TUIkit.StatusBar.self) == "TUIkitChrome.StatusBar")
        #expect(String(reflecting: TUIkit.NotificationService.self) == "TUIkitChrome.NotificationService")
        #expect(String(reflecting: TUIkit.ScrollTransitionPhase.self) == "TUIkitEffects.ScrollTransitionPhase")
        #expect(String(reflecting: TUIkit.MenuOrder.self) == "TUIkitMenus.MenuOrder")
        // Step B5c carved these out (decisions SPB5c, "What an app can see");
        // each read `TUIkitFoundation.` between B1 and B5c.
        #expect(String(reflecting: TUIkit.ImageSource.self) == "TUIkitBitmaps.ImageSource")
        #expect(String(reflecting: TUIkit.AsyncImagePhase.self) == "TUIkitBitmaps.AsyncImagePhase")
        // Step B7 carved these out (decisions SPB7, "What an app can see");
        // each read `TUIkitFoundation.` between B1 and B7. A type from
        // Sources/TUIkitPickers, TUIkitSearch or TUIkitNumericControls names
        // TUIkitTextInput, the module that compiles it, until steps C5, C7 and
        // C8 give it a module of its own; one from Sources/TUIkitForms names
        // TUIkitForms since step C6 (decisions SPC5, "What an app can see"),
        // and read `TUIkitTextInput.` from B7 until then.
        #expect(String(reflecting: TUIkit.TabWidth.self) == "TUIkitTextInput.TabWidth")
        #expect(String(reflecting: TUIkit.DatePickerComponents.self) == "TUIkitTextInput.DatePickerComponents")
        #expect(String(reflecting: TUIkit.GroupedFormStyle.self) == "TUIkitForms.GroupedFormStyle")
        #expect(String(reflecting: TUIkit.SearchFieldIconPlacement.self) == "TUIkitTextInput.SearchFieldIconPlacement")
        #expect(String(reflecting: TUIkit.IndeterminateStyle.self) == "TUIkitTextInput.IndeterminateStyle")
    }
}
