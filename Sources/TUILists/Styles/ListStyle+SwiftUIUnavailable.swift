//  🖥️ TUI — A Terminal UI framework for Swift
//  ListStyle+SwiftUIUnavailable.swift
//
//  SwiftUI's older spelling of striped rows, with a compile error that says what
//  to write instead. TUIFoundation's View+SwiftUIUnavailable.swift says why these
//  exist and how they are written.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// No documentation: nothing here reaches a reader except its message.
// swiftlint:disable missing_docs

extension ListStyle where Self == InsetListStyle {
    @available(*, unavailable, message: "Use .listStyle(.inset) and .alternatingRowBackgrounds(). SwiftUI has deprecated this form too.")
    @_alwaysEmitIntoClient
    public static func inset(alternatesRowBackgrounds: Bool) -> InsetListStyle { .inset }
}

extension ListStyle where Self == BorderedListStyle {
    @available(*, unavailable, message: "Use .listStyle(.bordered) and .alternatingRowBackgrounds(). SwiftUI has deprecated this form too.")
    @_alwaysEmitIntoClient
    public static func bordered(alternatesRowBackgrounds: Bool) -> BorderedListStyle { .bordered }
}

// swiftlint:enable missing_docs
