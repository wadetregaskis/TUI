//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Tab.swift
//
//  A tab of a tab view: its label, its selection value, its role, and the
//  content shown while it is selected.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation
import TUIkitStyling

// MARK: - Tab

/// The content for a tab and the tab's associated tab item in a tab view.
///
/// ```swift
/// TabView(selection: $selection) {
///     Tab("Received", systemImage: "tray.and.arrow.down.fill", value: 0) {
///         ReceivedView()
///     }
///     .badge(2)
///     Tab("Sent", systemImage: "tray.and.arrow.up.fill", value: 1) {
///         SentView()
///     }
/// }
/// ```
///
/// A tab with a `value` is selected by it; one without is selected by its
/// place among its tab view's tabs, in a ``TabView`` built without a selection.
///
/// The label is drawn in the tab view's strip as text: the title, after the
/// SF Symbol `systemImage` names where the terminal can draw that symbol (see
/// ``Label/init(_:systemImage:)-(LocalizedStringKey,_)``), and the text of a
/// label view of your own (`Tab(content:label:)`). The `image:` forms, which
/// name an image in an asset catalogue, are not offered, as `Label`'s are not.
///
/// TUI-specific: `Tab(_:value:content:)`, a title with no symbol, which SwiftUI
/// spells with a `systemImage:` a terminal mostly cannot draw.
public struct Tab<Value: Hashable, Content: View, Label: View>: TabContent {
    /// The type used to drive selection for the containing tab view.
    public typealias TabValue = Value

    /// The tab's selection value, or `nil` for a tab selected by its place.
    let value: Value?

    /// The tab's role.
    let role: TabRole?

    /// The tab's label.
    let label: Label

    /// The view shown while the tab is selected.
    let content: Content

    init(value: Value?, role: TabRole?, label: Label, content: Content) {
        self.value = value
        self.role = role
        self.label = label
        self.content = content
    }

    /// A tab is primitive tab content: it hands itself over.
    public var body: Tab<Value, Content, Label> {
        return self  // swiftlint:disable:this implicit_return
    }
}

extension Tab: _TabContentPrimitive {
    func appendTabs(to tabs: inout _TabList) {
        let title: String
        var customLabel: AnyView?
        switch label {
        case let label as DefaultTabLabel: title = label.stripTitle(role: role)
        case is EmptyView: title = ""
        default:
            title = ""
            customLabel = AnyView(label)
        }
        let erased: AnyHashable
        if let value { erased = AnyHashable(value) } else { erased = tabs.nextPosition }
        tabs.append(
            _RawTab(
                value: erased, title: title, customLabel: customLabel, content: AnyView(content),
                role: role))
    }
}

// MARK: - A title and a symbol

extension Tab where Label == DefaultTabLabel {
    /// Creates a tab with a localized title and an SF Symbol, selected by
    /// `value`.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the tab's title — a literal is looked up, see
    ///     ``LocalizedStringKey``.
    ///   - systemImage: The SF Symbol drawn before the title, where the
    ///     terminal can draw it.
    ///   - value: The selection value that selects this tab.
    ///   - role: The tab's role.
    ///   - content: The view shown while the tab is selected.
    public init(
        _ titleKey: LocalizedStringKey, systemImage: String, value: Value, role: TabRole? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            value: value, role: role,
            label: DefaultTabLabel(title: titleKey.titleWords, systemImage: systemImage),
            content: content())
    }

    /// Creates a tab with a title shown as written and an SF Symbol, selected
    /// by `value`.
    ///
    /// - Parameters:
    ///   - title: The tab's title.
    ///   - systemImage: The SF Symbol drawn before the title, where the
    ///     terminal can draw it.
    ///   - value: The selection value that selects this tab.
    ///   - role: The tab's role.
    ///   - content: The view shown while the tab is selected.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S, systemImage: String, value: Value, role: TabRole? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            value: value, role: role,
            label: DefaultTabLabel(title: String(title), systemImage: systemImage),
            content: content())
    }

    /// Creates a tab with a localized title, selected by `value`.
    ///
    /// TUI-specific: SwiftUI's titled tabs also name a symbol or an image.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the tab's title — a literal is looked up, see
    ///     ``LocalizedStringKey``.
    ///   - value: The selection value that selects this tab.
    ///   - role: The tab's role.
    ///   - content: The view shown while the tab is selected.
    public init(
        _ titleKey: LocalizedStringKey, value: Value, role: TabRole? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            value: value, role: role, label: DefaultTabLabel(title: titleKey.titleWords, systemImage: nil),
            content: content())
    }

    /// Creates a tab with a title shown as written, selected by `value`.
    ///
    /// Generic over `StringProtocol` rather than taking a concrete `String`,
    /// which is what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey``. TUI-specific.
    ///
    /// - Parameters:
    ///   - title: The tab's title.
    ///   - value: The selection value that selects this tab.
    ///   - role: The tab's role.
    ///   - content: The view shown while the tab is selected.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S, value: Value, role: TabRole? = nil, @ViewBuilder content: () -> Content
    ) {
        self.init(
            value: value, role: role, label: DefaultTabLabel(title: String(title), systemImage: nil),
            content: content())
    }

    /// Creates a tab with no title, selected by `value`: a role's own label
    /// (``TabRole/search`` is "Search"), or none.
    ///
    /// - Parameters:
    ///   - value: The selection value that selects this tab.
    ///   - role: The tab's role.
    ///   - content: The view shown while the tab is selected.
    public init(value: Value, role: TabRole?, @ViewBuilder content: () -> Content) {
        self.init(
            value: value, role: role, label: DefaultTabLabel(title: nil, systemImage: nil),
            content: content())
    }
}

extension Tab where Value == Never, Label == DefaultTabLabel {
    /// Creates a tab with a localized title and an SF Symbol, in a tab view
    /// without a selection.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the tab's title.
    ///   - systemImage: The SF Symbol drawn before the title, where the
    ///     terminal can draw it.
    ///   - role: The tab's role.
    ///   - content: The view shown while the tab is selected.
    public init(
        _ titleKey: LocalizedStringKey, systemImage: String, role: TabRole? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            value: nil, role: role,
            label: DefaultTabLabel(title: titleKey.titleWords, systemImage: systemImage),
            content: content())
    }

    /// Creates a tab with a title shown as written and an SF Symbol, in a tab
    /// view without a selection.
    ///
    /// - Parameters:
    ///   - title: The tab's title.
    ///   - systemImage: The SF Symbol drawn before the title, where the
    ///     terminal can draw it.
    ///   - role: The tab's role.
    ///   - content: The view shown while the tab is selected.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S, systemImage: String, role: TabRole? = nil, @ViewBuilder content: () -> Content
    ) {
        self.init(
            value: nil, role: role,
            label: DefaultTabLabel(title: String(title), systemImage: systemImage),
            content: content())
    }

    /// Creates a tab with no title, in a tab view without a selection: a
    /// role's own label (``TabRole/search`` is "Search"), or none.
    ///
    /// - Parameters:
    ///   - role: The tab's role.
    ///   - content: The view shown while the tab is selected.
    public init(role: TabRole?, @ViewBuilder content: () -> Content) {
        self.init(
            value: nil, role: role, label: DefaultTabLabel(title: nil, systemImage: nil),
            content: content())
    }
}

// MARK: - A label of the app's own

extension Tab {
    /// Creates a tab with a label of your own, selected by `value`.
    ///
    /// The strip draws the label's text.
    ///
    /// - Parameters:
    ///   - value: The selection value that selects this tab.
    ///   - role: The tab's role.
    ///   - content: The view shown while the tab is selected.
    ///   - label: The tab's label.
    public init(
        value: Value, role: TabRole? = nil, @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.init(value: value, role: role, label: label(), content: content())
    }
}

extension Tab where Value == Never {
    /// Creates a tab with a label of your own, in a tab view without a
    /// selection.
    ///
    /// - Parameters:
    ///   - role: The tab's role.
    ///   - content: The view shown while the tab is selected.
    ///   - label: The tab's label.
    public init(role: TabRole? = nil, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.init(value: nil, role: role, label: label(), content: content())
    }
}

// MARK: - No label

extension Tab where Label == EmptyView {
    /// Creates a tab with no label, selected by `value`.
    ///
    /// - Parameters:
    ///   - value: The selection value that selects this tab.
    ///   - content: The view shown while the tab is selected.
    public init(value: Value, @ViewBuilder content: () -> Content) {
        self.init(value: value, role: nil, label: EmptyView(), content: content())
    }
}

extension Tab where Value == Never, Label == EmptyView {
    /// Creates a tab with no label, in a tab view without a selection.
    ///
    /// - Parameter content: The view shown while the tab is selected.
    public init(@ViewBuilder content: () -> Content) {
        self.init(value: nil, role: nil, label: EmptyView(), content: content())
    }
}

// MARK: - Values promoted to an optional selection

// SwiftUI's overloads for a tab view whose selection is OPTIONAL: each tab
// names a bare value, and the tab's value type is that value's Optional, so the
// builder's one selection type holds. Less generic than these, the forms above
// win wherever both apply.

extension Tab where Label == DefaultTabLabel {
    /// Creates a tab with a localized title and an SF Symbol, selected by
    /// `value` in a tab view whose selection is optional.
    public init<T: Hashable>(
        _ titleKey: LocalizedStringKey, systemImage: String, value: T, role: TabRole? = nil,
        @ViewBuilder content: () -> Content
    ) where Value == T? {
        self.init(
            value: value, role: role,
            label: DefaultTabLabel(title: titleKey.titleWords, systemImage: systemImage),
            content: content())
    }

    /// Creates a tab with a title shown as written and an SF Symbol, selected
    /// by `value` in a tab view whose selection is optional.
    @_disfavoredOverload
    public init<S: StringProtocol, T: Hashable>(
        _ title: S, systemImage: String, value: T, role: TabRole? = nil,
        @ViewBuilder content: () -> Content
    ) where Value == T? {
        self.init(
            value: value, role: role,
            label: DefaultTabLabel(title: String(title), systemImage: systemImage),
            content: content())
    }

    /// Creates a tab with a localized title, selected by `value` in a tab view
    /// whose selection is optional. TUI-specific.
    public init<T: Hashable>(
        _ titleKey: LocalizedStringKey, value: T, role: TabRole? = nil,
        @ViewBuilder content: () -> Content
    ) where Value == T? {
        self.init(
            value: value, role: role,
            label: DefaultTabLabel(title: titleKey.titleWords, systemImage: nil), content: content())
    }

    /// Creates a tab with a title shown as written, selected by `value` in a
    /// tab view whose selection is optional. TUI-specific.
    @_disfavoredOverload
    public init<S: StringProtocol, T: Hashable>(
        _ title: S, value: T, role: TabRole? = nil, @ViewBuilder content: () -> Content
    ) where Value == T? {
        self.init(
            value: value, role: role,
            label: DefaultTabLabel(title: String(title), systemImage: nil), content: content())
    }

    /// Creates a tab with no title, selected by `value` in a tab view whose
    /// selection is optional.
    public init<V: Hashable>(value: V, role: TabRole?, @ViewBuilder content: () -> Content)
    where Value == V? {
        self.init(
            value: value, role: role, label: DefaultTabLabel(title: nil, systemImage: nil),
            content: content())
    }
}

extension Tab {
    /// Creates a tab with a label of your own, selected by `value` in a tab
    /// view whose selection is optional.
    public init<V: Hashable>(
        value: V, role: TabRole? = nil, @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) where Value == V? {
        self.init(value: value, role: role, label: label(), content: content())
    }
}

extension Tab where Label == EmptyView {
    /// Creates a tab with no label, selected by `value` in a tab view whose
    /// selection is optional.
    public init<V: Hashable>(value: V, @ViewBuilder content: () -> Content) where Value == V? {
        self.init(value: value, role: nil, label: EmptyView(), content: content())
    }
}

// MARK: - DefaultTabLabel

/// The label of a tab built from a title and an SF Symbol: the symbol, where
/// the terminal can draw it, then the title.
public struct DefaultTabLabel: View {
    /// The title, or `nil` for a tab whose role names it.
    let title: String?
    /// The SF Symbol's name, or `nil`.
    let systemImage: String?

    public var body: some View {
        if let systemImage, let title {
            TUIkitFoundation.Label(title, systemImage: systemImage)
        } else {
            Text(verbatim: title ?? "")
        }
    }

    /// The text a tab view's strip draws for this label: the symbol's glyph
    /// and a space where the terminal can draw the symbol, then the title — or,
    /// for a tab with no title, its role's own (``TabRole/search``'s "Search").
    func stripTitle(role: TabRole?) -> String {
        let text = title ?? role?.defaultTitle ?? ""
        guard let systemImage, SFSymbol.canRender(named: systemImage), let glyph = SFSymbol.glyph(named: systemImage)
        else { return text }
        return text.isEmpty ? glyph : glyph + " " + text
    }
}

// MARK: - TabRole

/// A value that defines the purpose of the tab.
public struct TabRole: Hashable, Sendable {
    /// Which role this is.
    private let name: String

    /// The search role: a tab whose content searches.
    ///
    /// A search tab with no title of its own is labelled "Search", as SwiftUI
    /// labels it (measured on macOS 15.8, in a grouped tab view).
    public static var search: Self { Self(name: "search") }

    /// The label a tab of this role has when it is given no title.
    var defaultTitle: String? {
        self == .search ? LocalizationService.shared.string(for: LocalizationKey.Label.search) : nil
    }
}
