//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WindowGroup+Identifiers.swift
//
//  The window group's titled and identified forms: an identifier that
//  `openWindow` opens its windows by, and a title.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

extension WindowGroup {
    /// Creates a window group with an identifier — mirrors SwiftUI's
    /// `init(id:makeContent:)`.
    ///
    /// ``EnvironmentValues/openWindow`` opens a new window of the group by
    /// `id`, over the window in front.
    ///
    /// - Parameters:
    ///   - id: A string that uniquely identifies the window group.
    ///   - makeContent: A closure that creates the content for each instance
    ///     of the group.
    public init(id: String, @ViewBuilder makeContent: @escaping () -> Content) {
        self.init(title: nil, id: id, makeContent: makeContent)
    }

    /// Creates a window group with a text view title and an identifier —
    /// mirrors SwiftUI's `init(_:id:makeContent:)`.
    ///
    /// - Parameters:
    ///   - title: The ``Text`` title of the group's windows.
    ///   - id: A string that uniquely identifies the window group.
    ///   - makeContent: A closure that creates the content for each instance
    ///     of the group.
    public init(_ title: Text, id: String, @ViewBuilder makeContent: @escaping () -> Content) {
        self.init(title: title, id: id, makeContent: makeContent)
    }

    /// Creates a window group with a localized title string and an identifier
    /// — mirrors SwiftUI's `init(_:id:makeContent:)`.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the localized title of the group's windows.
    ///   - id: A string that uniquely identifies the window group.
    ///   - makeContent: A closure that creates the content for each instance
    ///     of the group.
    public init(_ titleKey: LocalizedStringKey, id: String, @ViewBuilder makeContent: @escaping () -> Content) {
        self.init(title: Text(titleKey), id: id, makeContent: makeContent)
    }

    /// Creates a window group with a title string and an identifier — mirrors
    /// SwiftUI's `init(_:id:makeContent:)`.
    ///
    /// Generic over `StringProtocol`, as SwiftUI's is, and disfavoured, so a
    /// string literal binds to the localized form above.
    ///
    /// - Parameters:
    ///   - title: The title of the group's windows, shown as written.
    ///   - id: A string that uniquely identifies the window group.
    ///   - makeContent: A closure that creates the content for each instance
    ///     of the group.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, id: String, @ViewBuilder makeContent: @escaping () -> Content) {
        self.init(title: Text(title), id: id, makeContent: makeContent)
    }

    /// Creates a window group with a text view title — mirrors SwiftUI's
    /// `init(_:makeContent:)`.
    ///
    /// - Parameters:
    ///   - title: The ``Text`` title of the group's windows.
    ///   - makeContent: A closure that creates the content for each instance
    ///     of the group.
    public init(_ title: Text, @ViewBuilder makeContent: @escaping () -> Content) {
        self.init(title: title, id: nil, makeContent: makeContent)
    }

    /// Creates a window group with a localized title string — mirrors
    /// SwiftUI's `init(_:makeContent:)`.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the localized title of the group's windows.
    ///   - makeContent: A closure that creates the content for each instance
    ///     of the group.
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder makeContent: @escaping () -> Content) {
        self.init(title: Text(titleKey), id: nil, makeContent: makeContent)
    }

    /// Creates a window group with a title string — mirrors SwiftUI's
    /// `init(_:makeContent:)`, disfavoured so a literal is a localized key.
    ///
    /// - Parameters:
    ///   - title: The title of the group's windows, shown as written.
    ///   - makeContent: A closure that creates the content for each instance
    ///     of the group.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @ViewBuilder makeContent: @escaping () -> Content) {
        self.init(title: Text(title), id: nil, makeContent: makeContent)
    }
}

// MARK: - A Window Scene

extension WindowGroup: WindowScene {
    var windowTitle: Text? { title }

    var opensOneWindow: Bool { false }

    var presentedValueType: Any.Type? {
        (Content.self as? any PresentingWindowContent.Type)?.presentedValueType
    }
}
