//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Commands.swift
//
//  SwiftUI's commands: app-level actions, grouped into the menu bar's menus,
//  with shortcuts that work whether a menu is open or not.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Commands

/// Conforming types represent a group of related commands that can be exposed
/// to the user via the main menu — mirrors SwiftUI's `Commands`.
///
/// You declare commands on a scene with `Scene.commands(content:)`, in a
/// ``CommandsBuilder`` closure: ``CommandMenu``s, which add menus of their own
/// to the menu bar, and ``CommandGroup``s, which add to, or replace, one of the
/// standard groups (``CommandGroupPlacement``) of the standard menus. A type of
/// your own conforms by returning such commands from its
/// ``body-swift.property``, as a view returns views, and reads what it acts on
/// the way a view does — with `@FocusedValue`, `@FocusedBinding` and
/// `@Environment`, read afresh each frame:
///
/// ```swift
/// struct NoteCommands: Commands {
///     @FocusedValue(\.selectedNote) private var note
///
///     var body: some Commands {
///         CommandMenu("Note") {
///             Button("Duplicate") { note?.duplicate() }
///                 .keyboardShortcut("d")
///                 .disabled(note == nil)
///         }
///     }
/// }
/// ```
///
/// A terminal has no menu bar of its own, so TUIkit draws one, on the top row
/// of the window, wherever a scene declares commands.
@MainActor
@preconcurrency
public protocol Commands {
    /// The type of commands that represents the body of this command
    /// hierarchy.
    associatedtype Body: Commands

    /// The contents of the command hierarchy.
    @CommandsBuilder var body: Body { get }
}

/// `Never` is commands, so the framework's own commands can declare
/// `Body == Never`, as SwiftUI's do; their bodies are never asked for. The
/// `body` witness is the one `extension Never: View` already declares.
extension Never: Commands {}

// MARK: - Empty Commands

/// An empty group of commands — mirrors SwiftUI's `EmptyCommands`.
public struct EmptyCommands: Commands {
    /// Creates an empty command hierarchy.
    public init() {}

    /// Never called: empty commands hand over nothing.
    public var body: Never { fatalError("EmptyCommands hands its commands over itself") }
}

extension EmptyCommands: _CommandsPrimitive {
    func collectCommands(into collector: inout CommandsCollector) {}
}

// MARK: - Optional

extension Optional: Commands where Wrapped: Commands {
    /// Never called: an optional hands its commands over itself.
    public var body: Never { fatalError("Optional hands its commands over itself") }
}

extension Optional: _CommandsPrimitive where Wrapped: Commands {
    func collectCommands(into collector: inout CommandsCollector) {
        guard let self else { return }
        collector.step(0, self)
    }
}

// MARK: - Conditional

extension _ConditionalContent: Commands where TrueContent: Commands, FalseContent: Commands {
    /// Never called: a branch hands its commands over itself.
    public var body: Never { fatalError("_ConditionalContent hands its commands over itself") }
}

extension _ConditionalContent: _CommandsPrimitive where TrueContent: Commands, FalseContent: Commands {
    func collectCommands(into collector: inout CommandsCollector) {
        switch self {
        case .trueContent(let content): collector.step(0, content)
        case .falseContent(let content): collector.step(1, content)
        }
    }
}

// MARK: - Group

extension Group: Commands where Content: Commands {
    /// Creates a group of commands — past a ``CommandsBuilder`` block's limit
    /// of ten, as a view `Group` is past a view builder's.
    ///
    /// - Parameter content: A ``CommandsBuilder`` that creates the commands.
    public init(@CommandsBuilder content: () -> Content) {
        self = .grouping(content())
    }

    /// Never called: a group hands its commands over itself.
    public var body: Never { fatalError("Group hands its commands over itself") }
}

extension Group: _CommandsPrimitive where Content: Commands {
    func collectCommands(into collector: inout CommandsCollector) {
        collector.step(0, content)
    }
}

// MARK: - Blocks

/// Several commands written one after another in a builder: they hand over
/// their menus and groups in order.
struct _TupleCommands: Commands, _CommandsPrimitive {
    /// Collects every member, captured where their types were known.
    let collectMembers: @MainActor (inout CommandsCollector) -> Void

    var body: Never { fatalError("_TupleCommands hands its commands over itself") }

    func collectCommands(into collector: inout CommandsCollector) {
        collectMembers(&collector)
    }
}

/// Commands whose type `if #available(…)` erased.
struct _AnyCommands: Commands, _CommandsPrimitive {
    /// Collects the erased commands.
    let collect: @MainActor (inout CommandsCollector) -> Void

    init(_ commands: any Commands) {
        func open<C: Commands>(_ commands: C) -> @MainActor (inout CommandsCollector) -> Void {
            { $0.step(0, commands) }
        }
        collect = open(commands)
    }

    var body: Never { fatalError("_AnyCommands hands its commands over itself") }

    func collectCommands(into collector: inout CommandsCollector) {
        collect(&collector)
    }
}

// MARK: - Primitives

/// Commands that hand over their menus and groups themselves, rather than
/// through ``Commands/body``. Every command type this framework defines is
/// one; commands an app writes are not, and are walked through their body.
@MainActor
protocol _CommandsPrimitive {
    /// Hands this content's menus and groups to `collector`, in order.
    func collectCommands(into collector: inout CommandsCollector)
}
