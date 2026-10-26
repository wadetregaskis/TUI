//  🖥️ TUI — A Terminal UI framework for Swift
//  DisplayCommandsTests.swift
//
//  TUI's DisplayCommands: View ▸ Palette ▸, Border Style ▸ and Control
//  Style ▸ choose through the app's managers, are disabled where the scene
//  states its own, and write a binding where one is given.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICommands
@testable import TUIFoundation

// MARK: - Fixtures

/// What the frame draws with, in words: the palette and appearance managers'
/// choices, and the palette, appearance and control style in force.
private struct DisplayReadout: View {
    @Environment(\.paletteManager) private var paletteManager
    @Environment(\.appearanceManager) private var appearanceManager
    @Environment(\.palette) private var palette
    @Environment(\.appearance) private var appearance
    @Environment(\.controlStyle) private var controlStyle

    var body: some View {
        VStack(alignment: .leading) {
            Text(verbatim: "MANAGED=\(paletteManager?.current.id ?? "-")/\(appearanceManager?.current.id ?? "-")")
            Text(verbatim: "DRAWN=\(palette.id)/\(appearance.id)/\(controlStyle.id)")
        }
    }
}

/// Nothing but the set: every choice is the managers'.
private struct ManagedApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { DisplayReadout() }
            .commandsRemoved()
            .commands { DisplayCommands() }
    }
}

/// A scene that states its own palette and control style, and leaves the
/// border to the appearance manager (`.appearance(nil)`).
private struct StatedApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { DisplayReadout() }
            .palette(PaletteRegistry.all[1])
            .appearance(nil)
            .environment(\.controlStyle, .lines)
            .commandsRemoved()
            .commands { DisplayCommands() }
    }
}

/// A root view that states its border: the content no longer shows the
/// appearance manager's.
private struct RootViewApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { DisplayReadout().appearance(.heavy) }
            .commandsRemoved()
            .commands { DisplayCommands() }
    }
}

/// The app's own state, which the bound set writes.
private final class DisplayState: @unchecked Sendable {
    static let shared = DisplayState()
    var palette: any Palette = PaletteRegistry.all[0]
    var appearance: Appearance = .rounded
    var controlStyle: ControlStyle = .automatic
}

/// A scene that applies the app's state, and the set bound to it.
private struct BoundApp: App {
    init() {}
    var body: some Scene {
        let state = DisplayState.shared
        WindowGroup { DisplayReadout() }
            .palette(state.palette)
            .appearance(state.appearance)
            .environment(\.controlStyle, state.controlStyle)
            .commandsRemoved()
            .commands {
                DisplayCommands(
                    palette: Binding(get: { state.palette }, set: { state.palette = $0 }),
                    appearance: Binding(get: { state.appearance }, set: { state.appearance = $0 }),
                    controlStyle: Binding(get: { state.controlStyle }, set: { state.controlStyle = $0 }))
            }
    }
}

// MARK: - Tests

@MainActor
@Suite("DisplayCommands", .serialized)
struct DisplayCommandsTests {
    private var now: Int64 = 0

    private mutating func frame<A: App>(_ app: HeadlessApp<A>) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private func rows<A: App>(_ app: HeadlessApp<A>) -> [String] { app.screen.map(\.stripped) }

    private mutating func launched<A: App>(_ app: A) -> HeadlessApp<A> {
        let headless = HeadlessApp(app, width: 80, height: 24)
        frame(headless)
        frame(headless)
        return headless
    }

    /// The readout line that starts with `prefix`, without it.
    private func readout<A: App>(_ prefix: String, in app: HeadlessApp<A>) -> String? {
        for row in rows(app) {
            guard let range = row.range(of: prefix) else { continue }
            return String(row[range.upperBound...].prefix { $0 != " " })
        }
        return nil
    }

    /// Opens View, goes `row` rows down to a submenu, opens it, and chooses its
    /// `item`th option (from 0).
    private mutating func choose<A: App>(row: Int, item: Int, in app: HeadlessApp<A>) {
        for key: Key in [.f10] + Array(repeating: .down, count: row) + [.right] + Array(repeating: .down, count: item)
            + [.enter]
        {
            app.send(KeyEvent(key: key))
            frame(app)
        }
        frame(app)
        frame(app)
    }

    /// Opens View, goes `row` rows down to a disabled submenu, opens it — a
    /// submenu of disabled items, which opens, as macOS's — presses Return,
    /// which has no item to choose, and closes the menus.
    private mutating func tryDisabled<A: App>(row: Int, in app: HeadlessApp<A>) {
        for key: Key in [.f10] + Array(repeating: .down, count: row) + [.right, .enter, .escape, .escape] {
            app.send(KeyEvent(key: key))
            frame(app)
        }
    }

    /// The rows of the submenu `row` rows down View, opened.
    private mutating func submenuRows<A: App>(row: Int, in app: HeadlessApp<A>) -> [String] {
        for key: Key in [.f10] + Array(repeating: .down, count: row) + [.right] {
            app.send(KeyEvent(key: key))
            frame(app)
        }
        let shown = rows(app)
        app.send(KeyEvent(key: .escape))
        frame(app)
        app.send(KeyEvent(key: .escape))
        frame(app)
        return shown
    }

    @Test("View holds Palette, Border Style and Control Style, each a submenu of its choices, the current one checked")
    mutating func viewMenu() {
        let app = launched(ManagedApp())
        #expect(rows(app)[0].contains("View"), "\(rows(app))")
        app.send(KeyEvent(key: .f10))
        frame(app)
        let menu = rows(app)
        for title in ["Palette", "Border Style", "Control Style"] {
            #expect(menu.contains { $0.contains(title) && $0.contains("▸") }, "\(title): \(menu)")
        }
        app.send(KeyEvent(key: .escape))
        frame(app)
        let styles = submenuRows(row: 2, in: app)
        #expect(styles.contains { $0.contains("✓") && $0.contains("Automatic") }, "\(styles)")
        #expect(styles.contains { $0.contains("Braille, 4 Dots") }, "every Braille thickness: \(styles)")
    }

    @Test("With no arguments each submenu chooses through the app's manager, and then checks the new choice")
    mutating func managersChoose() {
        let app = launched(ManagedApp())
        let first = PaletteRegistry.all[0].id
        let second = PaletteRegistry.all[1].id
        #expect(readout("MANAGED=", in: app) == "\(first)/rounded", "\(rows(app))")
        choose(row: 0, item: 1, in: app)
        choose(row: 1, item: 2, in: app)
        choose(row: 2, item: 2, in: app)
        #expect(readout("MANAGED=", in: app) == "\(second)/doubleLine", "\(rows(app))")
        #expect(readout("DRAWN=", in: app) == "\(second)/doubleLine/lines", "\(rows(app))")
        let palettes = submenuRows(row: 0, in: app)
        let name = PaletteRegistry.all[1].name
        #expect(palettes.contains { $0.contains("✓") && $0.contains(name) }, "\(palettes)")
    }

    @Test("Where the scene states a palette or control style, that submenu is disabled; the border still chooses")
    mutating func sceneStatementsDisable() {
        let app = launched(StatedApp())
        let first = PaletteRegistry.all[0].id
        let stated = PaletteRegistry.all[1].id
        #expect(readout("DRAWN=", in: app) == "\(stated)/rounded/lines", "\(rows(app))")
        tryDisabled(row: 0, in: app)
        tryDisabled(row: 2, in: app)
        #expect(readout("MANAGED=", in: app) == "\(first)/rounded", "the managers were left alone: \(rows(app))")
        #expect(readout("DRAWN=", in: app) == "\(stated)/rounded/lines", "\(rows(app))")
        // The palette in force is checked, though the manager holds another.
        let palettes = submenuRows(row: 0, in: app)
        #expect(palettes.contains { $0.contains("✓") && $0.contains(PaletteRegistry.all[1].name) }, "\(palettes)")
        // `.appearance(nil)` states nothing: Border Style still chooses.
        choose(row: 1, item: 3, in: app)
        #expect(readout("DRAWN=", in: app) == "\(stated)/heavy/lines", "\(rows(app))")
    }

    @Test("An environment modifier of the border on the window group's root view disables Border Style")
    mutating func rootViewStatementDisables() {
        let app = launched(RootViewApp())
        tryDisabled(row: 1, in: app)
        #expect(readout("MANAGED=", in: app)?.hasSuffix("/rounded") == true, "\(rows(app))")
        #expect(readout("DRAWN=", in: app)?.contains("/heavy/") == true, "\(rows(app))")
    }

    @Test("Given bindings, the submenus write the app's state, which the scene applies")
    mutating func bindingsWrite() {
        DisplayState.shared.palette = PaletteRegistry.all[0]
        DisplayState.shared.appearance = .rounded
        DisplayState.shared.controlStyle = .automatic
        let app = launched(BoundApp())
        choose(row: 0, item: 1, in: app)
        choose(row: 1, item: 3, in: app)
        choose(row: 2, item: 4, in: app)
        #expect(DisplayState.shared.palette.id == PaletteRegistry.all[1].id)
        #expect(DisplayState.shared.appearance == .heavy)
        #expect(DisplayState.shared.controlStyle == .braille(thickness: 2))
        #expect(
            readout("DRAWN=", in: app) == "\(PaletteRegistry.all[1].id)/heavy/braille2", "\(rows(app))")
        #expect(
            readout("MANAGED=", in: app) == "\(PaletteRegistry.all[0].id)/rounded", "the managers were not asked")
    }
}
