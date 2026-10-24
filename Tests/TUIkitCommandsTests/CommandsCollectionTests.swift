//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CommandsCollectionTests.swift
//
//  A scene's commands walked into the menu bar's menus: the order SwiftUI
//  puts menus in, how `CommandGroup`'s three positions compose, and commands
//  of an app's own type, whose properties resolve as a view's do. The order
//  and the composition are SwiftUI's as measured on macOS 15.8
//  (`Tools/SwiftUIProbes/The menu bar (O13)/menus.swift`, the main menu read back).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCommands
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// An environment value a set of commands reads, to show its body resolves.
private struct ShowsExtrasKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    fileprivate var showsExtras: Bool {
        get { self[ShowsExtrasKey.self] }
        set { self[ShowsExtrasKey.self] = newValue }
    }
}

/// Commands of an app's own type, whose body reads the environment.
private struct ExtraCommands: Commands {
    @Environment(\.showsExtras) private var showsExtras

    var body: some Commands {
        if showsExtras {
            CommandMenu("Extras") { Button("More") {} }
        }
    }
}

@MainActor
@Suite("Commands walked into menus")
struct CommandsCollectionTests {

    /// The menus `commands` declares, as the bar would show them.
    private func menus<C: Commands>(
        _ commands: C, environment: EnvironmentValues = EnvironmentValues(),
        defaults: (CommandGroupPlacement.Group) -> CommandItems? = { _ in nil }
    ) -> [ResolvedCommandMenu] {
        var collector = CommandsCollector(
            environment: environment, storage: nil, identity: ViewIdentity(rootType: Self.self))
        collector.collect(commands)
        return collector.resolvedMenus(defaults: defaults)
    }

    /// Each menu's title, as the bar would name it.
    private func titles(_ menus: [ResolvedCommandMenu]) -> [String] {
        menus.map { menu in
            switch menu.title {
            case .standard(let standard): "\(standard)"
            case .declared(let name): text(name)
            }
        }
    }

    /// What `view` draws, row by row, a button as its bare title.
    private func text(_ view: some View) -> String {
        renderToBuffer(view.buttonStyle(.plain), context: makeBareRenderContext(width: 30, height: 10)).lines.map(\.stripped)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "|")
    }

    /// Each group of `menu`, as the rows its declarations draw.
    private func groups(_ menu: ResolvedCommandMenu) -> [[String]] {
        menu.groups.map { $0.map { text($0.view) } }
    }

    @Test("The app's own menus sit between View and Window, in declaration order")
    func menuOrder() {
        let menus = menus(
            Group {
                CommandMenu("Zeta") { Button("Z1") {} }
                CommandGroup(after: .help) { Button("Guide") {} }
                CommandGroup(after: .sidebar) { Button("Panel") {} }
                CommandGroup(after: .windowList) { Button("Tile") {} }
                CommandGroup(after: .newItem) { Button("New Note") {} }
                CommandMenu("Alpha") { Button("A1") {} }
            })
        #expect(titles(menus) == ["file", "view", "Zeta", "Alpha", "window", "help"])
    }

    @Test("A standard menu with nothing in it is left out; an app's own menu is a menu even empty")
    func emptyMenus() {
        let menus = menus(Group { CommandMenu("Empty") {} })
        #expect(titles(menus) == ["Empty"])
    }

    @Test("Within a group: the newest before first, the afters in order, the last replacement")
    func groupComposition() {
        let menus = menus(
            Group {
                CommandGroup(replacing: .newItem) { Button("R1") {} }
                CommandGroup(replacing: .newItem) { Button("R2") {} }
                CommandGroup(after: .newItem) { Button("After1") {} }
                CommandGroup(after: .newItem) { Button("After2") {} }
                CommandGroup(before: .newItem) { Button("Before1") {} }
                CommandGroup(before: .newItem) { Button("Before2") {} }
            })
        #expect(menus.count == 1)
        #expect(groups(menus[0]) == [["Before2", "Before1", "R2", "After1", "After2"]])
    }

    @Test("A group's own commands stand where no replacement takes their place, and go where one does")
    func defaultsAndReplacement() {
        let quit = CommandItems(view: AnyView(Button("Quit") {}), children: { _ in [] }, key: "default-quit")
        let defaults: (CommandGroupPlacement.Group) -> CommandItems? = { $0 == .appTermination ? quit : nil }
        let kept = menus(CommandGroup(before: .appTermination) { Button("Lock") {} }, defaults: defaults)
        #expect(groups(kept[0]) == [["Lock", "Quit"]])
        let replaced = menus(CommandGroup(replacing: .appTermination) { Button("Leave") {} }, defaults: defaults)
        #expect(groups(replaced[0]) == [["Leave"]])
    }

    @Test("Groups of one menu are kept apart, in the menu's order")
    func groupsOfOneMenu() {
        let menus = menus(
            Group {
                CommandGroup(after: .pasteboard) { Button("Paste Plain") {} }
                CommandGroup(after: .undoRedo) { Button("Undo History") {} }
            })
        #expect(titles(menus) == ["edit"])
        #expect(groups(menus[0]) == [["Undo History"], ["Paste Plain"]])
    }

    @Test("An if, an if/else and an optional pick their commands")
    func conditionals() {
        func declared(_ flag: Bool) -> [String] {
            titles(
                menus(
                    Group {
                        if flag {
                            CommandMenu("Yes") {}
                        } else {
                            CommandMenu("No") {}
                        }
                        if flag { CommandMenu("Only") {} }
                    }))
        }
        #expect(declared(true) == ["Yes", "Only"])
        #expect(declared(false) == ["No"])
    }

    @Test("Commands of the app's own type resolve their @Environment before their body")
    func customCommandsResolveTheirProperties() {
        #expect(titles(menus(ExtraCommands())).isEmpty)
        var environment = EnvironmentValues()
        environment.showsExtras = true
        #expect(titles(menus(ExtraCommands(), environment: environment)) == ["Extras"])
    }

    @Test("Each declaration is keyed by its place in the commands, not its index among the bar's")
    func keysFollowDeclarations() {
        func key(_ flag: Bool) -> String? {
            menus(
                Group {
                    if flag { CommandMenu("Gone") {} }
                    CommandMenu("Kept") {}
                }
            ).last?.key
        }
        #expect(key(true) == key(false))
    }
}
