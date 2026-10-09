//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GroupBox.swift
//
//  SwiftUI's GroupBox: a stylized view, with an optional label, that visually
//  collects a logical grouping of content — here its label, then the content
//  in a box drawn in the appearance's border, as ``Box`` draws one.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - GroupBox

/// A stylized view, with an optional label, that visually collects a logical
/// grouping of content.
///
/// ```swift
/// GroupBox("End-User Agreement") {
///     Text(agreementText)
///     Toggle("I agree to the above terms", isOn: $userAgreed)
/// }
/// ```
///
/// The default style draws the label, then the content in a bordered box — the
/// border the current ``Appearance`` draws, as `Box` uses. A style set with
/// ``View/groupBoxStyle(_:)`` lays it out instead.
public struct GroupBox<Label: View, Content: View>: View {
    let label: Label
    let content: Content

    /// Creates a group box with the provided label and view content.
    ///
    /// - Parameters:
    ///   - content: A view builder producing the box's content.
    ///   - label: A view builder producing the label.
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content()
        self.label = label()
    }

    public var body: some View {
        _StyledGroupBox(
            configuration: GroupBoxStyleConfiguration(
                label: AnyView(label), content: _StyledContent(content)))
    }
}

extension GroupBox where Label == EmptyView {
    /// Creates an unlabeled group box with the provided view content.
    ///
    /// - Parameter content: A view builder producing the box's content.
    public init(@ViewBuilder content: () -> Content) {
        self.init(content: content, label: { EmptyView() })
    }
}

extension GroupBox where Label == Text {
    /// Creates a group box with the provided view content and a localized title.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the group box's title.
    ///   - content: A view builder producing the box's content.
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content, label: { Text(titleKey) })
    }

    /// Creates a group box with the provided view content and a title, shown as
    /// written.
    ///
    /// - Parameters:
    ///   - title: The group box's title.
    ///   - content: A view builder producing the box's content.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.init(content: content, label: { Text(title) })
    }
}

extension GroupBox
where Label == GroupBoxStyleConfiguration.Label, Content == GroupBoxStyleConfiguration.Content {
    /// Creates a group box based on a style configuration.
    ///
    /// Use it inside a ``GroupBoxStyle``'s ``GroupBoxStyle/makeBody(configuration:)``
    /// to draw the box as the style outside the custom one would, and add to it.
    ///
    /// - Parameter configuration: The properties of the group box.
    public init(_ configuration: GroupBoxStyleConfiguration) {
        self.label = configuration.label
        self.content = configuration.content
    }
}

// MARK: - Style

/// The properties of a group box instance.
public struct GroupBoxStyleConfiguration {
    /// A type-erased label of a group box.
    public typealias Label = AnyView

    /// A type-erased content of a group box, whose views lay out as separate
    /// children of a stack the style puts it in.
    public typealias Content = _StyledContent

    /// A view that provides the title of the group box.
    public let label: Label

    /// A view that represents the content of the group box.
    public let content: Content
}

/// A type that specifies the appearance and interaction of all group boxes
/// within a view hierarchy.
public protocol GroupBoxStyle: Sendable {
    /// A view that represents the body of a group box.
    associatedtype Body: View

    /// Creates a view representing the body of a group box.
    ///
    /// - Parameter configuration: The content of the group box instance being
    ///   created.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The properties of a group box instance.
    typealias Configuration = GroupBoxStyleConfiguration
}

extension GroupBoxStyle {
    /// This style's body, type-erased — opening the existential the
    /// environment holds.
    @MainActor
    func makeAnyBody(configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

/// The default style for group box views: the label, then the content in a
/// box with the appearance's border.
public struct DefaultGroupBoxStyle: GroupBoxStyle, Equatable {
    /// Creates the default group box style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            configuration.label
            Box {
                configuration.content
            }
        }
    }
}

extension GroupBoxStyle where Self == DefaultGroupBoxStyle {
    /// The default style for group box views.
    public static var automatic: DefaultGroupBoxStyle { DefaultGroupBoxStyle() }
}

// MARK: - Environment

private struct GroupBoxStyleKey: EnvironmentKey {
    static let defaultValue = StyleChain<any GroupBoxStyle>(DefaultGroupBoxStyle())
}

extension EnvironmentValues {
    /// The group box style in force, and the ones outside it.
    var groupBoxStyleChain: StyleChain<any GroupBoxStyle> {
        get { self[GroupBoxStyleKey.self] }
        set { self[GroupBoxStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for group boxes within this view.
    ///
    /// - Parameter style: The style to apply to boxes within this view.
    /// - Returns: A view whose group boxes use `style`.
    public func groupBoxStyle<S: GroupBoxStyle>(_ style: S) -> some View {
        transformEnvironment(\.groupBoxStyleChain) { $0 = $0.pushing(style) }
    }
}

/// A group box drawn through the style in force. The style's body sees the
/// style outside it, so a `GroupBox(configuration)` in it draws as that style
/// would; with no custom style anywhere above, the default is drawn unerased.
private struct _StyledGroupBox: View {
    let configuration: GroupBoxStyleConfiguration
    @Environment(\.groupBoxStyleChain) private var styles

    @ViewBuilder var body: some View {
        if styles.isRoot {
            DefaultGroupBoxStyle().makeBody(configuration: configuration)
        } else {
            styles.style.makeAnyBody(configuration: configuration)
                .environment(\.groupBoxStyleChain, styles.inside)
        }
    }
}

// MARK: - Environment without reflection

extension _StyledGroupBox: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _styles.resolveEnvironment(environment)
    }
}
