//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WindowGroup+PresentedData.swift
//
//  The window group's `for:` initializers: a group whose windows each present
//  a value, opened by `openWindow(value:)`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// A group that presents data, in SwiftUI's sixteen spellings: with or without
// an identifier, a title of three kinds or none, and an optional binding or a
// default value. Each is one line onto `init(title:id:content:)`.

extension WindowGroup {
    /// Creates a data-presenting window group — mirrors SwiftUI's
    /// `init(for:content:)`.
    ///
    /// Each window presents a value of `type`: the one
    /// ``EnvironmentValues/openWindow`` opened it with
    /// (`openWindow(value:)`), or `nil` for a window opened at launch or by
    /// identifier. Opening a value a window presents already brings that window
    /// to the front.
    ///
    /// - Parameters:
    ///   - type: The type of presented data this window group accepts.
    ///   - content: A closure that creates the content for each instance of the
    ///     group, from a binding to the value it presents.
    public init<D, C>(for type: D.Type, @ViewBuilder content: @escaping (Binding<D?>) -> C)
    where Content == PresentedWindowContent<D, C>, D: Decodable & Encodable & Hashable, C: View {
        self.init(title: nil, id: nil, content: PresentedWindowContent(present: content, defaultValue: nil))
    }

    /// Creates a data-presenting window group with a default value — mirrors
    /// SwiftUI's `init(for:content:defaultValue:)`.
    ///
    /// A window opened with no value presents `defaultValue()`.
    ///
    /// - Parameters:
    ///   - type: The type of presented data this window group accepts.
    ///   - content: A closure that creates the content for each instance of the
    ///     group, from a binding to the value it presents.
    ///   - defaultValue: A closure that returns the value a window opened with
    ///     none presents.
    public init<D, C>(
        for type: D.Type = D.self, @ViewBuilder content: @escaping (Binding<D>) -> C,
        defaultValue: @escaping () -> D
    ) where Content == PresentedWindowContent<D, C>, D: Decodable & Encodable & Hashable, C: View {
        self.init(title: nil, id: nil, content: .defaulting(content, to: defaultValue))
    }

    /// Creates a data-presenting window group with an identifier — mirrors
    /// SwiftUI's `init(id:for:content:)`.
    ///
    /// - Parameters:
    ///   - id: A string that uniquely identifies the window group.
    ///   - type: The type of presented data this window group accepts.
    ///   - content: A closure that creates the content for each instance of the
    ///     group, from a binding to the value it presents.
    public init<D, C>(id: String, for type: D.Type, @ViewBuilder content: @escaping (Binding<D?>) -> C)
    where Content == PresentedWindowContent<D, C>, D: Decodable & Encodable & Hashable, C: View {
        self.init(title: nil, id: id, content: PresentedWindowContent(present: content, defaultValue: nil))
    }

    /// Creates a data-presenting window group with an identifier and a default
    /// value — mirrors SwiftUI's `init(id:for:content:defaultValue:)`.
    ///
    /// - Parameters:
    ///   - id: A string that uniquely identifies the window group.
    ///   - type: The type of presented data this window group accepts.
    ///   - content: A closure that creates the content for each instance of the
    ///     group, from a binding to the value it presents.
    ///   - defaultValue: A closure that returns the value a window opened with
    ///     none presents.
    public init<D, C>(
        id: String, for type: D.Type = D.self, @ViewBuilder content: @escaping (Binding<D>) -> C,
        defaultValue: @escaping () -> D
    ) where Content == PresentedWindowContent<D, C>, D: Decodable & Encodable & Hashable, C: View {
        self.init(title: nil, id: id, content: .defaulting(content, to: defaultValue))
    }
}

// MARK: - Titled

extension WindowGroup {
    /// Creates a data-presenting window group with a text view title — mirrors
    /// SwiftUI's `init(_:for:content:)`.
    ///
    /// - Parameters:
    ///   - title: The ``Text`` title of the group's windows.
    ///   - type: The type of presented data this window group accepts.
    ///   - content: A closure that creates the content for each instance of the
    ///     group, from a binding to the value it presents.
    public init<D, C>(_ title: Text, for type: D.Type, @ViewBuilder content: @escaping (Binding<D?>) -> C)
    where Content == PresentedWindowContent<D, C>, D: Decodable & Encodable & Hashable, C: View {
        self.init(title: title, id: nil, content: PresentedWindowContent(present: content, defaultValue: nil))
    }

    /// Creates a data-presenting window group with a localized title —
    /// mirrors SwiftUI's `init(_:for:content:)`.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the localized title of the group's windows.
    ///   - type: The type of presented data this window group accepts.
    ///   - content: A closure that creates the content for each instance of the
    ///     group, from a binding to the value it presents.
    public init<D, C>(
        _ titleKey: LocalizedStringKey, for type: D.Type, @ViewBuilder content: @escaping (Binding<D?>) -> C
    ) where Content == PresentedWindowContent<D, C>, D: Decodable & Encodable & Hashable, C: View {
        self.init(title: Text(titleKey), id: nil, content: PresentedWindowContent(present: content, defaultValue: nil))
    }

    /// Creates a data-presenting window group with a title string — mirrors
    /// SwiftUI's `init(_:for:content:)`, disfavoured so a literal is a key.
    ///
    /// - Parameters:
    ///   - title: The title of the group's windows, shown as written.
    ///   - type: The type of presented data this window group accepts.
    ///   - content: A closure that creates the content for each instance of the
    ///     group, from a binding to the value it presents.
    @_disfavoredOverload
    public init<S, D, C>(_ title: S, for type: D.Type, @ViewBuilder content: @escaping (Binding<D?>) -> C)
    where Content == PresentedWindowContent<D, C>, S: StringProtocol, D: Decodable & Encodable & Hashable, C: View {
        self.init(title: Text(title), id: nil, content: PresentedWindowContent(present: content, defaultValue: nil))
    }

    /// Creates a data-presenting window group with a text view title and a
    /// default value — mirrors SwiftUI's `init(_:for:content:defaultValue:)`.
    ///
    /// - Parameters:
    ///   - title: The ``Text`` title of the group's windows.
    ///   - type: The type of presented data this window group accepts.
    ///   - content: A closure that creates the content for each instance of the
    ///     group, from a binding to the value it presents.
    ///   - defaultValue: A closure that returns the value a window opened with
    ///     none presents.
    public init<D, C>(
        _ title: Text, for type: D.Type = D.self, @ViewBuilder content: @escaping (Binding<D>) -> C,
        defaultValue: @escaping () -> D
    ) where Content == PresentedWindowContent<D, C>, D: Decodable & Encodable & Hashable, C: View {
        self.init(title: title, id: nil, content: .defaulting(content, to: defaultValue))
    }

    /// Creates a data-presenting window group with a localized title and a
    /// default value — mirrors SwiftUI's `init(_:for:content:defaultValue:)`.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the localized title of the group's windows.
    ///   - type: The type of presented data this window group accepts.
    ///   - content: A closure that creates the content for each instance of the
    ///     group, from a binding to the value it presents.
    ///   - defaultValue: A closure that returns the value a window opened with
    ///     none presents.
    public init<D, C>(
        _ titleKey: LocalizedStringKey, for type: D.Type = D.self,
        @ViewBuilder content: @escaping (Binding<D>) -> C, defaultValue: @escaping () -> D
    ) where Content == PresentedWindowContent<D, C>, D: Decodable & Encodable & Hashable, C: View {
        self.init(title: Text(titleKey), id: nil, content: .defaulting(content, to: defaultValue))
    }

    /// Creates a data-presenting window group with a title string and a
    /// default value — mirrors SwiftUI's `init(_:for:content:defaultValue:)`,
    /// disfavoured so a literal is a key.
    ///
    /// - Parameters:
    ///   - title: The title of the group's windows, shown as written.
    ///   - type: The type of presented data this window group accepts.
    ///   - content: A closure that creates the content for each instance of the
    ///     group, from a binding to the value it presents.
    ///   - defaultValue: A closure that returns the value a window opened with
    ///     none presents.
    @_disfavoredOverload
    public init<S, D, C>(
        _ title: S, for type: D.Type = D.self, @ViewBuilder content: @escaping (Binding<D>) -> C,
        defaultValue: @escaping () -> D
    ) where Content == PresentedWindowContent<D, C>, S: StringProtocol, D: Decodable & Encodable & Hashable, C: View {
        self.init(title: Text(title), id: nil, content: .defaulting(content, to: defaultValue))
    }
}

// MARK: - Titled, With an Identifier

extension WindowGroup {
    /// Creates a data-presenting window group with a text view title and an
    /// identifier — mirrors SwiftUI's `init(_:id:for:content:)`.
    ///
    /// - Parameters:
    ///   - title: The ``Text`` title of the group's windows.
    ///   - id: A string that uniquely identifies the window group.
    ///   - type: The type of presented data this window group accepts.
    ///   - content: A closure that creates the content for each instance of the
    ///     group, from a binding to the value it presents.
    public init<D, C>(
        _ title: Text, id: String, for type: D.Type, @ViewBuilder content: @escaping (Binding<D?>) -> C
    ) where Content == PresentedWindowContent<D, C>, D: Decodable & Encodable & Hashable, C: View {
        self.init(title: title, id: id, content: PresentedWindowContent(present: content, defaultValue: nil))
    }

    /// Creates a data-presenting window group with a localized title and an
    /// identifier — mirrors SwiftUI's `init(_:id:for:content:)`.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the localized title of the group's windows.
    ///   - id: A string that uniquely identifies the window group.
    ///   - type: The type of presented data this window group accepts.
    ///   - content: A closure that creates the content for each instance of the
    ///     group, from a binding to the value it presents.
    public init<D, C>(
        _ titleKey: LocalizedStringKey, id: String, for type: D.Type,
        @ViewBuilder content: @escaping (Binding<D?>) -> C
    ) where Content == PresentedWindowContent<D, C>, D: Decodable & Encodable & Hashable, C: View {
        self.init(title: Text(titleKey), id: id, content: PresentedWindowContent(present: content, defaultValue: nil))
    }

    /// Creates a data-presenting window group with a title string and an
    /// identifier — mirrors SwiftUI's `init(_:id:for:content:)`, disfavoured
    /// so a literal is a key.
    ///
    /// - Parameters:
    ///   - title: The title of the group's windows, shown as written.
    ///   - id: A string that uniquely identifies the window group.
    ///   - type: The type of presented data this window group accepts.
    ///   - content: A closure that creates the content for each instance of the
    ///     group, from a binding to the value it presents.
    @_disfavoredOverload
    public init<S, D, C>(
        _ title: S, id: String, for type: D.Type, @ViewBuilder content: @escaping (Binding<D?>) -> C
    ) where Content == PresentedWindowContent<D, C>, S: StringProtocol, D: Decodable & Encodable & Hashable, C: View {
        self.init(title: Text(title), id: id, content: PresentedWindowContent(present: content, defaultValue: nil))
    }

    /// Creates a data-presenting window group with a text view title, an
    /// identifier and a default value — mirrors SwiftUI's
    /// `init(_:id:for:content:defaultValue:)`.
    ///
    /// - Parameters:
    ///   - title: The ``Text`` title of the group's windows.
    ///   - id: A string that uniquely identifies the window group.
    ///   - type: The type of presented data this window group accepts.
    ///   - content: A closure that creates the content for each instance of the
    ///     group, from a binding to the value it presents.
    ///   - defaultValue: A closure that returns the value a window opened with
    ///     none presents.
    public init<D, C>(
        _ title: Text, id: String, for type: D.Type = D.self, @ViewBuilder content: @escaping (Binding<D>) -> C,
        defaultValue: @escaping () -> D
    ) where Content == PresentedWindowContent<D, C>, D: Decodable & Encodable & Hashable, C: View {
        self.init(title: title, id: id, content: .defaulting(content, to: defaultValue))
    }

    /// Creates a data-presenting window group with a localized title, an
    /// identifier and a default value — mirrors SwiftUI's
    /// `init(_:id:for:content:defaultValue:)`.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the localized title of the group's windows.
    ///   - id: A string that uniquely identifies the window group.
    ///   - type: The type of presented data this window group accepts.
    ///   - content: A closure that creates the content for each instance of the
    ///     group, from a binding to the value it presents.
    ///   - defaultValue: A closure that returns the value a window opened with
    ///     none presents.
    public init<D, C>(
        _ titleKey: LocalizedStringKey, id: String, for type: D.Type = D.self,
        @ViewBuilder content: @escaping (Binding<D>) -> C, defaultValue: @escaping () -> D
    ) where Content == PresentedWindowContent<D, C>, D: Decodable & Encodable & Hashable, C: View {
        self.init(title: Text(titleKey), id: id, content: .defaulting(content, to: defaultValue))
    }

    /// Creates a data-presenting window group with a title string, an
    /// identifier and a default value — mirrors SwiftUI's
    /// `init(_:id:for:content:defaultValue:)`, disfavoured so a literal is a
    /// key.
    ///
    /// - Parameters:
    ///   - title: The title of the group's windows, shown as written.
    ///   - id: A string that uniquely identifies the window group.
    ///   - type: The type of presented data this window group accepts.
    ///   - content: A closure that creates the content for each instance of the
    ///     group, from a binding to the value it presents.
    ///   - defaultValue: A closure that returns the value a window opened with
    ///     none presents.
    @_disfavoredOverload
    public init<S, D, C>(
        _ title: S, id: String, for type: D.Type = D.self, @ViewBuilder content: @escaping (Binding<D>) -> C,
        defaultValue: @escaping () -> D
    ) where Content == PresentedWindowContent<D, C>, S: StringProtocol, D: Decodable & Encodable & Hashable, C: View {
        self.init(title: Text(title), id: id, content: .defaulting(content, to: defaultValue))
    }
}

// MARK: - The Default Value

extension PresentedWindowContent {
    /// Content built from a binding to a value that is never `nil`: the
    /// window's value, or `defaultValue()` while it presents none.
    static func defaulting(
        _ content: @escaping (Binding<Data>) -> Content, to defaultValue: @escaping () -> Data
    ) -> Self {
        Self(
            present: { optional in
                content(Binding(get: { optional.wrappedValue ?? defaultValue() }, set: { optional.wrappedValue = $0 }))
            },
            defaultValue: defaultValue)
    }
}
