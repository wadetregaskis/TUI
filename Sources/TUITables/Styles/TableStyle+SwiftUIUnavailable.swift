//  🖥️ TUI — A Terminal UI framework for Swift
//  TableStyle+SwiftUIUnavailable.swift
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

extension TableStyle where Self == InsetTableStyle {
    @available(*, unavailable, message: "Use .tableStyle(.inset) and .alternatingRowBackgrounds(). SwiftUI has deprecated this form too.")
    @_alwaysEmitIntoClient
    public static func inset(alternatesRowBackgrounds: Bool) -> InsetTableStyle { .inset }
}

extension TableStyle where Self == BorderedTableStyle {
    @available(*, unavailable, message: "Use .tableStyle(.bordered) and .alternatingRowBackgrounds(). SwiftUI has deprecated this form too.")
    @_alwaysEmitIntoClient
    public static func bordered(alternatesRowBackgrounds: Bool) -> BorderedTableStyle { .bordered }
}

// swiftlint:enable missing_docs
