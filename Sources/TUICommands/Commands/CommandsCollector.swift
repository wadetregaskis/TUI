//  🖥️ TUI — A Terminal UI framework for Swift
//  CommandsCollector.swift
//
//  A scene's commands, walked into the menus and groups they declare, and
//  those resolved into the menu bar's menus.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - The Items a Declaration Holds

/// The views one ``CommandMenu`` or ``CommandGroup`` holds, and where it sits in
/// the commands that declared it.
struct CommandItems {
    /// The views, erased.
    let view: AnyView

    /// The views as separate rows of a menu, resolved where their type was
    /// known: a `ForEach` of `Button`s is that many rows, not one block, and a
    /// `Section` is a section — as a ``Menu``'s items are.
    let children: @MainActor (RenderContext) -> [ChildView]

    /// The declaration's place in the commands — the member of each block it
    /// is in and the branch of each `if`/`else` — as the key of its identity,
    /// so what its views keep follows the declaration rather than its index
    /// among the bar's.
    let key: String
}

/// A menu of the app's own (``CommandMenu``).
struct DeclaredCommandMenu {
    /// The menu's name.
    let name: Text

    /// The menu's items.
    let items: CommandItems
}

/// What the ``CommandGroup``s on one group said, in the order SwiftUI composes
/// them (measured on macOS 15.8: `Tools/SwiftUIProbes/The menu bar (O13)/menus.swift`).
struct CommandGroupEdits {
    /// The `before:` additions, newest first: each goes in front of the group.
    var before: [CommandItems] = []

    /// The last `replacing:` addition, if any: the group's own items, in place
    /// of what it held.
    var replacement: CommandItems?

    /// The `after:` additions, in order.
    var after: [CommandItems] = []
}

// MARK: - The Collector

/// Walks a scene's commands into the menus and group edits they declare.
///
/// The framework's command types hand themselves over (`_CommandsPrimitive`);
/// any other ``Commands`` is walked through its body, which is evaluated as a
/// view's is: its `@Environment`, `@FocusedValue` and `@FocusedBinding`
/// resolved first, in the environment the walk is given — so a command that
/// reads the focused view's value reads this frame's.
@MainActor
struct CommandsCollector {
    /// What a set of commands' properties are resolved in.
    private let environment: EnvironmentValues

    /// Where a set of commands' `@State` lives, if anywhere.
    private let storage: StateStorage?

    /// The identity the commands' identities are keyed under.
    private let identity: ViewIdentity

    /// The menus of the app's own, in declaration order.
    private(set) var menus: [DeclaredCommandMenu] = []

    /// What the group edits said, by group.
    private(set) var groups: [CommandGroupPlacement.Group: CommandGroupEdits] = [:]

    /// Whether the commands offer View ▸ Customize Toolbar… themselves
    /// (``ToolbarCommands``): the scene's own item is then left out, so the
    /// menu never has two.
    var offersCustomizeToolbar = false

    /// The place being collected: one step per block member and `if` branch.
    private var path: [Int] = []

    /// A collector whose commands resolve their properties in `environment`,
    /// keep their `@State` in `storage`, and are keyed under `identity`.
    init(environment: EnvironmentValues, storage: StateStorage?, identity: ViewIdentity) {
        self.environment = environment
        self.storage = storage
        self.identity = identity
    }

    /// Collects `commands`.
    mutating func collect<C: Commands>(_ commands: C) {
        if let primitive = commands as? any _CommandsPrimitive {
            primitive.collectCommands(into: &self)
            return
        }
        var prepared = commands
        if let plan = propertyPlan(for: C.self) {
            let identity = identity.child(erasedType: C.self, key: pathKey)
            prepareProperties(
                of: &prepared, plan: plan, identity: identity, storage: storage, environment: environment,
                isMeasuring: false)
            storage?.markActive(identity)
        }
        collect(prepared.body)
    }

    /// Collects `commands` one step further in, at `index`: a block's member,
    /// an `if`/`else`'s branch.
    mutating func step<C: Commands>(_ index: Int, _ commands: C) {
        path.append(index)
        collect(commands)
        path.removeLast()
    }

    /// `content`, at the place being collected.
    func items<Content: View>(_ content: Content) -> CommandItems {
        CommandItems(
            view: AnyView(content), children: { resolveChildViews(from: content, context: $0) }, key: pathKey)
    }

    /// Adds a menu of the app's own.
    mutating func addMenu(named name: Text, items: CommandItems) {
        menus.append(DeclaredCommandMenu(name: name, items: items))
    }

    /// Adds `items` to `group`, at `position`.
    mutating func edit(
        _ group: CommandGroupPlacement.Group, _ position: CommandGroupPosition, with items: CommandItems
    ) {
        switch position {
        case .before: groups[group, default: CommandGroupEdits()].before.insert(items, at: 0)
        case .after: groups[group, default: CommandGroupEdits()].after.append(items)
        case .replacing: groups[group, default: CommandGroupEdits()].replacement = items
        }
    }

    /// The place being collected, as an identity key.
    private var pathKey: String {
        path.map(String.init).joined(separator: ".")
    }
}

// MARK: - The Menus

/// One menu of the menu bar, resolved: its title, and the non-empty groups it
/// shows, in order.
struct ResolvedCommandMenu {
    /// What the menu's title is.
    enum Title {
        /// A standard menu: the app's menu, File, Edit and the rest.
        case standard(StandardMenu)
        /// A menu of the app's own, with its name.
        case declared(Text)
    }

    /// The menu's title.
    let title: Title

    /// The groups the menu shows, each a run of declarations' items, in order:
    /// a menu draws a separator between two.
    let groups: [[CommandItems]]

    /// The menu's identity key among the bar's: its standard menu's, or the
    /// declaration's.
    let key: String
}

extension CommandsCollector {
    /// The menu bar's menus: the standard menus that have something in them,
    /// with the app's own menus between View and Window, in declaration order,
    /// as SwiftUI orders them (measured on macOS 15.8:
    /// `Tools/SwiftUIProbes/The menu bar (O13)/menus.swift`).
    ///
    /// A menu of the app's own is a menu even with nothing in it, as there; a
    /// standard menu with nothing in any of its groups is left out.
    ///
    /// - Parameter defaults: What each group holds before an edit: TUI's
    ///   own commands, or `nil` for an empty group.
    func resolvedMenus(
        defaults: (CommandGroupPlacement.Group) -> CommandItems? = { _ in nil }
    ) -> [ResolvedCommandMenu] {
        var resolved: [ResolvedCommandMenu] = []
        for menu in StandardMenu.allCases {
            if menu == .window {
                resolved += menus.map {
                    ResolvedCommandMenu(title: .declared($0.name), groups: [[$0.items]], key: "menu-" + $0.items.key)
                }
            }
            let groups = menu.groups.compactMap { group -> [CommandItems]? in
                let edits = self.groups[group] ?? CommandGroupEdits()
                let items = edits.before + [edits.replacement ?? defaults(group)].compactMap { $0 } + edits.after
                return items.isEmpty ? nil : items
            }
            guard !groups.isEmpty else { continue }
            resolved.append(ResolvedCommandMenu(title: .standard(menu), groups: groups, key: "standard-\(menu)"))
        }
        return resolved
    }
}
