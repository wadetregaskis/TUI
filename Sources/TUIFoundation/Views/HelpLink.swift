//  🖥️ TUI — A Terminal UI framework for Swift
//  HelpLink.swift
//
//  SwiftUI's HelpLink: a button with a standard appearance that opens help —
//  by running an action, or by opening a URL through `\.openURL`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// A button with a standard appearance that opens app-specific help
/// documentation.
///
/// ```swift
/// HelpLink {
///     showHelp = true
/// }
///
/// HelpLink(destination: URL(string: "https://example.com/help")!)
/// ```
///
/// The standard appearance is a `?` button. SwiftUI's `anchor:` forms open an
/// Apple Help book, which no terminal has; they are absent.
public struct HelpLink: View {
    /// What the link does, given the environment's URL opener.
    /// What pressing it does: the caller's action, or `nil` to open ``destination``.
    private let action: (() -> Void)?
    private let destination: URL?

    @Environment(\.openURL) private var openURL

    /// Constructs a new help link with the specified action.
    ///
    /// - Parameter action: The action to perform when the link is activated.
    public init(action: @escaping () -> Void) {
        self.action = action
        self.destination = nil
    }

    /// Constructs a new help link that opens the specified destination URL,
    /// through the environment's ``EnvironmentValues/openURL`` — so a custom
    /// ``OpenURLAction`` can take it over, as with ``Link``.
    ///
    /// - Parameter destination: The URL to open when the link is activated.
    public init(destination: URL) {
        self.action = nil
        self.destination = destination
    }

    public var body: some View {
        Button {
            if let action {
                action()
            } else if let destination {
                openURL(destination)
            }
        } label: {
            Text(verbatim: "?")
        }
    }
}

// MARK: - Environment without reflection

extension HelpLink: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _openURL.resolveEnvironment(environment)
    }
}
