//  🖥️ TUI — A Terminal UI framework for Swift
//  View+SwiftUIUnavailable.swift
//
//  SwiftUI's `tabItem`, with a compile error that says what to write instead.
//  TUIFoundation's file of this name says why these exist and how they are
//  written.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// No documentation, and long lines. Nothing here reaches a reader except its message,
// and a message has to be one string literal.
// swiftlint:disable missing_docs line_length

extension View {
    @available(*, unavailable, message: "Write each tab as a Tab: Tab(\"Home\", systemImage: \"house\") { HomeView() }. SwiftUI has replaced tabItem with this too.")
    @_alwaysEmitIntoClient
    public func tabItem<Label: View>(@ViewBuilder _ label: () -> Label) -> Self { self }
}

extension TabContentBuilder {
    // A view in a TabView's content, with `tabItem` or without it, otherwise gets
    // "requires that 'Text' conform to 'TabContent'".
    @available(*, unavailable, message: "A TabView holds tabs, not views. Write each one as a Tab: Tab(\"Home\", systemImage: \"house\") { HomeView() }.")
    @_alwaysEmitIntoClient
    public static func buildExpression<Content: View>(_ view: Content) -> Tab<TabValue, Content, EmptyView> {
        fatalError("A view in a TabView's content is unavailable")
    }
}

// swiftlint:enable missing_docs line_length
