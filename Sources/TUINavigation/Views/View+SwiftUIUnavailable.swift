//  🖥️ TUI — A Terminal UI framework for Swift
//  View+SwiftUIUnavailable.swift
//
//  SwiftUI's older navigation API, and the iOS navigation bar's, each with a
//  compile error that says what to write instead. TUIFoundation's file of this
//  name says why these exist and how they are written.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// No documentation: nothing here reaches a reader except its message.
// swiftlint:disable missing_docs

/// SwiftUI's older navigation container, there only for its compile error.
@available(*, unavailable, renamed: "NavigationStack", message: "For columns, use NavigationSplitView. SwiftUI has deprecated NavigationView too.")
nonisolated public struct NavigationView<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    @MainActor public var body: some View { content }
}

extension NavigationLink {
    @available(*, unavailable, message: "Put the destination in a closure: NavigationLink { ... } label: { ... }. SwiftUI has deprecated this form too.")
    public init(destination: Destination, @ViewBuilder label: () -> Label) {
        self.init(destination: { destination }, label: label)
    }

    @available(*, unavailable, message: "Put the destination in a closure: NavigationLink(\"Title\") { ... }. SwiftUI has deprecated this form too.")
    public init<Title>(_ title: Title, destination: Destination) where Label == Text {
        self.init("\(String(describing: title))", destination: { destination })
    }

    @available(*, unavailable, message: "Use NavigationLink(value:) and .navigationDestination, or a NavigationPath. SwiftUI has deprecated this form too.")
    public init(destination: Destination, isActive: Binding<Bool>, @ViewBuilder label: () -> Label) {
        self.init(destination: { destination }, label: label)
    }

    @available(*, unavailable, message: "Use NavigationLink(value:) and .navigationDestination, or a NavigationPath. SwiftUI has deprecated this form too.")
    public init<Title>(_ title: Title, destination: Destination, isActive: Binding<Bool>) where Label == Text {
        self.init("\(String(describing: title))", destination: { destination })
    }
}

extension View {
    @available(*, unavailable, renamed: "navigationTitle(_:)", message: "SwiftUI has deprecated navigationBarTitle too.")
    @_alwaysEmitIntoClient
    nonisolated public func navigationBarTitle<Title>(_ title: Title) -> Self { self }

    @available(*, unavailable, message: "Use .navigationTitle. A title is one line of text, so it has no display modes.")
    @_alwaysEmitIntoClient
    nonisolated public func navigationBarTitle<Title>(_ title: Title, displayMode: NavigationBarItem.TitleDisplayMode) -> Self { self }

    @available(*, unavailable, message: "A title is one line of text, so it has no display modes. Delete this.")
    @_alwaysEmitIntoClient
    nonisolated public func navigationBarTitleDisplayMode(_ displayMode: NavigationBarItem.TitleDisplayMode) -> Self { self }

    @available(*, unavailable, message: "Use .toolbarVisibility(.hidden). SwiftUI has deprecated navigationBarHidden too.")
    @_alwaysEmitIntoClient
    nonisolated public func navigationBarHidden(_ hidden: Bool) -> Self { self }

    @available(*, unavailable, message: "NavigationStack is always a stack. For columns, use NavigationSplitView, with .navigationSplitViewStyle.")
    @_alwaysEmitIntoClient
    nonisolated public func navigationViewStyle(_ style: NavigationViewStyle) -> Self { self }
}

/// The home of the display modes `navigationBarTitleDisplayMode(_:)` offers, there
/// only for that modifier's compile error.
@available(*, unavailable, message: "A title is one line of text, so it has no display modes.")
public enum NavigationBarItem {
    /// The display modes of a title.
    public enum TitleDisplayMode {
        case automatic, inline, large
    }
}

/// The styles `navigationViewStyle(_:)` offers, there only for that modifier's
/// compile error.
@available(*, unavailable, message: "NavigationStack is always a stack. For columns, use NavigationSplitView.")
public enum NavigationViewStyle {
    case automatic, columns, stack
}

// swiftlint:enable missing_docs
