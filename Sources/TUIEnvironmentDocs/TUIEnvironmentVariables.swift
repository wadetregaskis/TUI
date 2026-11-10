//  🖥️ TUI — A Terminal UI framework for Swift
//  TUIEnvironmentVariables.swift
//
//  The table of every environment variable TUI reads, for an app's own documentation.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Every environment variable that TUI reads, and the text an app's documentation
/// needs to describe them.
///
/// This is one table, in code, that TUI's own documentation is checked against. A test
/// fails when a variable read anywhere in TUI's sources isn't in it, or when the
/// generated tables in the documentation differ from it. So when an app regenerates its
/// man page from this, upgrading TUI updates the man page.
///
/// ```swift
/// import TUIEnvironmentDocs
///
/// print(TUIEnvironmentVariables.manPageSection(format: .mdoc))
/// ```
///
/// A build script would rather run the executable of the same text, which needs no code in
/// the app: `swift run tui-environment-docs --format man`.
///
/// This is in a product of its own, `TUIEnvironmentDocs`, so that an app that doesn't
/// ask for it doesn't carry the text. It depends on nothing, and `TUI` doesn't
/// include it. A TUI-specific API, with no SwiftUI counterpart.
///
/// ## Topics
///
/// ### The table
///
/// - ``all``
/// - ``variables(for:)``
/// - ``TUIEnvironmentVariable``
///
/// ### Text for an app's documentation
///
/// - ``manPageSection(format:audience:includesHeading:)``
/// - ``ManPageFormat``
/// - ``markdownSection(audience:headingLevel:)``
public enum TUIEnvironmentVariables {
    /// Every variable TUI reads: for the person running an app, for someone building
    /// one, and those that TUI only reads to work out where it's running.
    public static let all: [TUIEnvironmentVariable] = endUser + developer + detected

    /// The variables for `audience`, grouped by ``TUIEnvironmentVariable/Topic``.
    public static func variables(for audience: TUIEnvironmentVariable.Audience) -> [TUIEnvironmentVariable] {
        all.filter { $0.audience == audience }
    }

    /// `variables`, as a run of topics, each with its variables, in the order the
    /// topics are declared.
    static func grouped(_ variables: [TUIEnvironmentVariable]) -> [(topic: TUIEnvironmentVariable.Topic, variables: [TUIEnvironmentVariable])] {
        TUIEnvironmentVariable.Topic.allCases.compactMap { topic in
            let members = variables.filter { $0.topic == topic }
            return members.isEmpty ? nil : (topic, members)
        }
    }

    /// The topics a generated section has for `audience`, each with its variables:
    /// the audience's own, and, for the person running the app, what their terminal
    /// sets after them, so that they know what it's telling the program.
    static func sectionGroups(
        for audience: TUIEnvironmentVariable.Audience
    ) -> [(topic: TUIEnvironmentVariable.Topic, variables: [TUIEnvironmentVariable])] {
        let own = grouped(variables(for: audience))
        return audience == .endUser ? own + grouped(variables(for: .detected)) : own
    }

    /// The opening every generated section has for `audience`, in Markdown.
    static func introduction(for audience: TUIEnvironmentVariable.Audience) -> String {
        switch audience {
        case .endUser:
            """
            This program is built with TUI, which reads these variables. Set one for a single run by \
            writing it before the command, as in `NO_COLOR=1 myapp`, or for every run by exporting it from \
            your shell's profile. An empty value counts as unset, and a value that isn't listed is ignored. \
            A setting the program makes itself, such as from a command-line flag, usually wins, but it \
            can't undo what you ask for so that you can use it, such as less motion. Those marked as an \
            experiment may change. The ones your terminal, tmux or ssh sets for you come last.
            """
        case .developer:
            """
            These are for testing and debugging a program built with TUI. An empty variable counts as unset, \
            and a value that isn't listed is ignored.
            """
        case .detected:
            """
            TUI reads these to work out where the program is running and what the terminal can do. Your \
            terminal, tmux, GNU screen or ssh sets them, so there's rarely a reason to set one yourself: to say \
            which terminal this is, use `TUI_TERM_PROGRAM`.
            """
        }
    }
}
