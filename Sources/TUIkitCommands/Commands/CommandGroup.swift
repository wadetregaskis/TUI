//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CommandGroup.swift
//
//  An addition to one of the standard groups of the menu bar's standard menus.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Command Group

/// Where a ``CommandGroup``'s views go in its group.
enum CommandGroupPosition {
    case before, after, replacing
}

/// Groups of controls that you can add to existing command menus — mirrors
/// SwiftUI's `CommandGroup`.
///
/// A group goes into one of the standard groups of the standard menus
/// (``CommandGroupPlacement``): before what the group holds, after it, or in
/// its place. Within a group the additions run on with no separator between
/// them, the newest `before:` first and the `after:`s in order, and the last
/// `replacing:` is the one that counts — as SwiftUI composes them on macOS
/// (measured on macOS 15.8: the session notes' `O13/probe/menus.swift`).
///
/// ```swift
/// CommandGroup(replacing: .newItem) {
///     Button("New Note") { newNote() }
///         .keyboardShortcut("n")
/// }
/// ```
public struct CommandGroup<Content: View>: Commands {
    /// The group.
    let placement: CommandGroupPlacement

    /// Where in the group.
    let position: CommandGroupPosition

    /// The views.
    let content: Content

    /// A value describing the addition of the given views to the beginning of
    /// the indicated group.
    ///
    /// - Parameters:
    ///   - group: The group to add to.
    ///   - addition: The views.
    public init(before group: CommandGroupPlacement, @ViewBuilder addition: () -> Content) {
        self.placement = group
        self.position = .before
        self.content = addition()
    }

    /// A value describing the addition of the given views to the end of the
    /// indicated group.
    ///
    /// - Parameters:
    ///   - group: The group to add to.
    ///   - addition: The views.
    public init(after group: CommandGroupPlacement, @ViewBuilder addition: () -> Content) {
        self.placement = group
        self.position = .after
        self.content = addition()
    }

    /// A value describing the complete replacement of the contents of the
    /// indicated group with the given views.
    ///
    /// - Parameters:
    ///   - group: The group to replace.
    ///   - addition: The views.
    public init(replacing group: CommandGroupPlacement, @ViewBuilder addition: () -> Content) {
        self.placement = group
        self.position = .replacing
        self.content = addition()
    }

    /// Never called: a command group hands itself over to the menu bar.
    public var body: Never { fatalError("CommandGroup hands its commands over itself") }
}

extension CommandGroup: _CommandsPrimitive {
    func collectCommands(into collector: inout CommandsCollector) {
        collector.edit(placement.group, position, with: collector.items(content))
    }
}
