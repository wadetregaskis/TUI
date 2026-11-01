//  🖥️ TUI — A Terminal UI framework for Swift
//  Scene+SwiftUIUnavailable.swift
//
//  SwiftUI's desktop window modifiers, each with a compile error that says why a
//  terminal app has no use for them. TUIFoundation's View+SwiftUIUnavailable.swift
//  says why these exist and how they are written.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// No documentation: nothing here reaches a reader except its message.
// swiftlint:disable missing_docs

extension Scene {
    @available(*, unavailable, message: "An app fills the terminal window, and the terminal decides that window's size. Delete this.")
    @_alwaysEmitIntoClient
    public func defaultSize<Size>(_ size: Size) -> Self { self }

    @available(*, unavailable, message: "An app fills the terminal window, and the terminal decides that window's size. Delete this.")
    @_alwaysEmitIntoClient
    public func defaultSize<Width, Height>(width: Width, height: Height) -> Self { self }

    @available(*, unavailable, message: "An app fills the terminal window, and the terminal decides that window's size. Delete this.")
    @_alwaysEmitIntoClient
    public func windowResizability(_ resizability: WindowResizability) -> Self { self }

    @available(*, unavailable, message: "An app fills the terminal window, and the terminal decides how that window looks. Delete this.")
    @_alwaysEmitIntoClient
    public func windowStyle(_ style: WindowStyle) -> Self { self }
}

/// The choices `windowResizability(_:)` offers, there only for that modifier's
/// compile error.
@available(*, unavailable, message: "An app fills the terminal window, and the terminal decides that window's size.")
public enum WindowResizability {
    case automatic, contentMinSize, contentSize
}

/// The styles `windowStyle(_:)` offers, there only for that modifier's compile
/// error.
@available(*, unavailable, message: "An app fills the terminal window, and the terminal decides how that window looks.")
public enum WindowStyle {
    case automatic, hiddenTitleBar, plain, titleBar
}

// swiftlint:enable missing_docs
