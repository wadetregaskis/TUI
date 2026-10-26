//  🖥️ TUI — A Terminal UI framework for Swift
//  LinkActivation.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Link activation

/// What activating a ``Link`` — a click, Return or Space — does.
///
/// See ``View/linkActivation(_:)``.
public enum LinkActivation: Sendable, Equatable, CaseIterable {
    /// Opens the destination through the environment's ``OpenURLAction``. The
    /// default.
    case open

    /// Copies the destination to the clipboard, and says so in the status bar,
    /// instead of opening it.
    case copy
}

private struct LinkActivationKey: EnvironmentKey {
    static let defaultValue = LinkActivation.open
}

extension EnvironmentValues {
    /// What activating a ``Link`` does — see ``View/linkActivation(_:)``.
    public var linkActivation: LinkActivation {
        get { self[LinkActivationKey.self] }
        set { self[LinkActivationKey.self] = newValue }
    }
}

extension View {
    /// Sets what activating a ``Link`` within this view does: open its
    /// destination, the default, or copy it to the clipboard.
    ///
    /// Copying suits an app run over ssh, where opening a link runs the
    /// opener on the server (see ``OpenURLAction``), and an app whose links
    /// are addresses to paste elsewhere rather than pages to visit. Either way
    /// the destination's popover shows what the link holds, and the link's
    /// context menu offers Copy Link.
    ///
    /// ```swift
    /// VStack {
    ///     Link("Server log", destination: logURL)
    ///     Link("Dashboard", destination: dashboardURL)
    /// }
    /// .linkActivation(.copy)
    /// ```
    ///
    /// TUI-specific: SwiftUI's links always open, which is what a desktop's
    /// browser is there for.
    ///
    /// - Parameter activation: What activating a link does.
    /// - Returns: A view whose links do it.
    public func linkActivation(_ activation: LinkActivation) -> some View {
        environment(\.linkActivation, activation)
    }
}
