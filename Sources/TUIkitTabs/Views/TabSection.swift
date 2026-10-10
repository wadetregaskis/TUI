//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabSection.swift
//
//  A group of tabs under a header: shown as a section in a sidebar, and as the
//  tabs alone in a tab bar.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

/// A container that you can use to add hierarchy within a tab view.
///
/// ```swift
/// TabView {
///     Tab("Requests", systemImage: "paperplane") { RequestsView() }
///     TabSection("Messages") {
///         Tab("Received", systemImage: "tray.and.arrow.down.fill") { ReceivedView() }
///         Tab("Sent", systemImage: "tray.and.arrow.up.fill") { SentView() }
///     }
/// }
/// ```
///
/// In a tab bar — the strip every TUIkit tab view style but the sidebar draws
/// — a section's tabs stand among the others and its header is not shown, as
/// SwiftUI documents for a tab bar (measured on macOS 15.8 too: a grouped tab
/// view's bar lists a section's tabs as its own).
public struct TabSection<Header: View, Content: TabContent, Footer: View, SelectionValue: Hashable>: TabContent
where SelectionValue == Content.TabValue {
    /// The type used to drive selection for the containing tab view.
    public typealias TabValue = Content.TabValue

    /// The section's header.
    let header: Header

    /// The section's tabs.
    let content: Content

    /// A section is primitive tab content: it hands its tabs over itself.
    public var body: TabSection<Header, Content, Footer, SelectionValue> {
        return self  // swiftlint:disable:this implicit_return
    }
}

extension TabSection: _TabContentPrimitive {
    func appendTabs(to tabs: inout _TabList) {
        tabs.appendSection(header: AnyView(header)) { TUIkitTabs.appendTabs(content, to: &$0) }
    }
}

extension TabSection where Header == Text, Footer == EmptyView {
    /// Creates a section with a localized title as its header.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the section's title — a literal is looked up,
    ///     see ``LocalizedStringKey``.
    ///   - content: The section's tabs.
    public init(_ titleKey: LocalizedStringKey, @TabContentBuilder<SelectionValue> content: () -> Content) {
        header = Text(titleKey)
        self.content = content()
    }

    /// Creates a section with a title shown as written as its header.
    ///
    /// - Parameters:
    ///   - title: The section's title.
    ///   - content: The section's tabs.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @TabContentBuilder<SelectionValue> content: () -> Content) {
        header = Text(verbatim: String(title))
        self.content = content()
    }
}

extension TabSection where Header == EmptyView, Footer == EmptyView {
    /// Creates a section with no header.
    ///
    /// - Parameter content: The section's tabs.
    public init(@TabContentBuilder<SelectionValue> content: () -> Content) {
        header = EmptyView()
        self.content = content()
    }
}

extension TabSection where Footer == EmptyView {
    /// Creates a section with a header of your own.
    ///
    /// - Parameters:
    ///   - content: The section's tabs.
    ///   - header: The section's header.
    public init(
        @TabContentBuilder<SelectionValue> content: () -> Content, @ViewBuilder header: () -> Header
    ) {
        self.header = header()
        self.content = content()
    }
}

// MARK: - Optional selections

// The same three families for a tab view whose selection is optional. They
// add no behaviour: what they add is a builder pinned to `V?`, which is what
// lets a `Tab(_:systemImage:value:)` inside take its promoting `V?` form. The
// section's content is type-checked before the tab view's requirement reaches
// the section, so through the forms above `Tab("Two", value: 2)` settles on
// `Int` and the section then fails `Int?` (the compile corpus caught it).

extension TabSection where Header == Text, Footer == EmptyView {
    /// Creates a section with a localized title as its header, in a tab view
    /// whose selection is optional.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the section's title.
    ///   - content: The section's tabs.
    public init<V: Hashable>(
        _ titleKey: LocalizedStringKey, @TabContentBuilder<V?> content: () -> Content
    ) where SelectionValue == V? {
        header = Text(titleKey)
        self.content = content()
    }

    /// Creates a section with a title shown as written as its header, in a
    /// tab view whose selection is optional.
    ///
    /// - Parameters:
    ///   - title: The section's title.
    ///   - content: The section's tabs.
    @_disfavoredOverload
    public init<V: Hashable, S: StringProtocol>(
        _ title: S, @TabContentBuilder<V?> content: () -> Content
    ) where SelectionValue == V? {
        header = Text(verbatim: String(title))
        self.content = content()
    }
}

extension TabSection where Header == EmptyView, Footer == EmptyView {
    /// Creates a section with no header, in a tab view whose selection is
    /// optional.
    ///
    /// - Parameter content: The section's tabs.
    public init<V: Hashable>(@TabContentBuilder<V?> content: () -> Content) where SelectionValue == V? {
        header = EmptyView()
        self.content = content()
    }
}

extension TabSection where Footer == EmptyView {
    /// Creates a section with a header of your own, in a tab view whose
    /// selection is optional.
    ///
    /// - Parameters:
    ///   - content: The section's tabs.
    ///   - header: The section's header.
    public init<V: Hashable>(
        @TabContentBuilder<V?> content: () -> Content, @ViewBuilder header: () -> Header
    ) where SelectionValue == V? {
        self.header = header()
        self.content = content()
    }
}
