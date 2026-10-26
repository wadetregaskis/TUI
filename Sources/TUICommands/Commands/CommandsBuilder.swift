//  🖥️ TUI — A Terminal UI framework for Swift
//  CommandsBuilder.swift
//
//  The result builder a scene's commands are written in.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// SwiftUI's builder spells out every arity to ten; so does this one, and the
// longest signatures have ten parameters by design.
// swiftlint:disable function_parameter_count

/// Constructs command sets from multi-expression closures — mirrors SwiftUI's
/// `CommandsBuilder`.
///
/// You don't use this type directly; `Scene.commands(content:)`'s `content`
/// parameter is annotated with it, and so is a ``Commands/body-swift.property``.
/// An `if` and an `if`/`else` compose commands, as in SwiftUI; past ten, wrap
/// some in a `Group`.
@MainActor
@resultBuilder
public struct CommandsBuilder {
    /// Builds an expression within the builder.
    public static func buildExpression<Content: Commands>(_ content: Content) -> Content {
        content
    }

    /// Builds an empty command set from a block containing no statements.
    public static func buildBlock() -> EmptyCommands {
        EmptyCommands()
    }

    /// Passes a single command group written as a child group through
    /// unmodified.
    ///
    /// Typed as the commands themselves rather than SwiftUI's `some Commands`,
    /// as ``ViewBuilder``'s is, so a primitive's `body: Never` — whose
    /// `fatalError()` this builder transforms like any other body — type-checks.
    public static func buildBlock<Content: Commands>(_ content: Content) -> Content {
        content
    }

    /// Produces an optional command group for an `if` with no `else`.
    public static func buildIf<Content: Commands>(_ content: Content?) -> Content? {
        content
    }

    /// Produces content for a conditional statement in a multi-statement
    /// closure, when the condition is true.
    public static func buildEither<TrueContent: Commands, FalseContent: Commands>(
        first: TrueContent
    ) -> _ConditionalContent<TrueContent, FalseContent> {
        .trueContent(first)
    }

    /// Produces content for a conditional statement in a multi-statement
    /// closure, when the condition is false.
    public static func buildEither<TrueContent: Commands, FalseContent: Commands>(
        second: FalseContent
    ) -> _ConditionalContent<TrueContent, FalseContent> {
        .falseContent(second)
    }

    /// Processes commands for a conditional compiler-control statement that
    /// performs an availability check.
    public static func buildLimitedAvailability(_ content: any Commands) -> some Commands {
        _AnyCommands(content)
    }
}

// MARK: - Blocks of two to ten

extension CommandsBuilder {
    /// Combines two commands.
    public static func buildBlock<C0: Commands, C1: Commands>(
        _ c0: C0, _ c1: C1
    ) -> some Commands {
        _TupleCommands { commands in
            commands.step(0, c0)
            commands.step(1, c1)
        }
    }

    /// Combines three commands.
    public static func buildBlock<C0: Commands, C1: Commands, C2: Commands>(
        _ c0: C0, _ c1: C1, _ c2: C2
    ) -> some Commands {
        _TupleCommands { commands in
            commands.step(0, c0)
            commands.step(1, c1)
            commands.step(2, c2)
        }
    }

    /// Combines four commands.
    public static func buildBlock<C0: Commands, C1: Commands, C2: Commands, C3: Commands>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3
    ) -> some Commands {
        _TupleCommands { commands in
            commands.step(0, c0)
            commands.step(1, c1)
            commands.step(2, c2)
            commands.step(3, c3)
        }
    }

    /// Combines five commands.
    public static func buildBlock<
        C0: Commands, C1: Commands, C2: Commands, C3: Commands, C4: Commands
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4
    ) -> some Commands {
        _TupleCommands { commands in
            commands.step(0, c0)
            commands.step(1, c1)
            commands.step(2, c2)
            commands.step(3, c3)
            commands.step(4, c4)
        }
    }

    /// Combines six commands.
    public static func buildBlock<
        C0: Commands, C1: Commands, C2: Commands, C3: Commands, C4: Commands, C5: Commands
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5
    ) -> some Commands {
        _TupleCommands { commands in
            commands.step(0, c0)
            commands.step(1, c1)
            commands.step(2, c2)
            commands.step(3, c3)
            commands.step(4, c4)
            commands.step(5, c5)
        }
    }

    /// Combines seven commands.
    public static func buildBlock<
        C0: Commands, C1: Commands, C2: Commands, C3: Commands, C4: Commands, C5: Commands, C6: Commands
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6
    ) -> some Commands {
        _TupleCommands { commands in
            commands.step(0, c0)
            commands.step(1, c1)
            commands.step(2, c2)
            commands.step(3, c3)
            commands.step(4, c4)
            commands.step(5, c5)
            commands.step(6, c6)
        }
    }

    /// Combines eight commands.
    public static func buildBlock<
        C0: Commands, C1: Commands, C2: Commands, C3: Commands, C4: Commands, C5: Commands, C6: Commands, C7: Commands
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7
    ) -> some Commands {
        _TupleCommands { commands in
            commands.step(0, c0)
            commands.step(1, c1)
            commands.step(2, c2)
            commands.step(3, c3)
            commands.step(4, c4)
            commands.step(5, c5)
            commands.step(6, c6)
            commands.step(7, c7)
        }
    }

    /// Combines nine commands.
    public static func buildBlock<
        C0: Commands, C1: Commands, C2: Commands, C3: Commands, C4: Commands, C5: Commands, C6: Commands,
        C7: Commands, C8: Commands
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8
    ) -> some Commands {
        _TupleCommands { commands in
            commands.step(0, c0)
            commands.step(1, c1)
            commands.step(2, c2)
            commands.step(3, c3)
            commands.step(4, c4)
            commands.step(5, c5)
            commands.step(6, c6)
            commands.step(7, c7)
            commands.step(8, c8)
        }
    }

    /// Combines ten commands.
    public static func buildBlock<
        C0: Commands, C1: Commands, C2: Commands, C3: Commands, C4: Commands, C5: Commands, C6: Commands,
        C7: Commands, C8: Commands, C9: Commands
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9
    ) -> some Commands {
        _TupleCommands { commands in
            commands.step(0, c0)
            commands.step(1, c1)
            commands.step(2, c2)
            commands.step(3, c3)
            commands.step(4, c4)
            commands.step(5, c5)
            commands.step(6, c6)
            commands.step(7, c7)
            commands.step(8, c8)
            commands.step(9, c9)
        }
    }
}

// swiftlint:enable function_parameter_count
