//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ControlGroup.swift
//
//  SwiftUI's ControlGroup: semantically related controls, displayed in a way
//  that suits the context — side by side, or behind a menu.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - ControlGroup

/// A container view that displays semantically-related controls in a
/// visually-appropriate manner for the context.
///
/// ```swift
/// ControlGroup {
///     Button("Bold") { … }
///     Button("Italic") { … }
/// } label: {
///     Text("Format")
/// }
/// ```
///
/// The default style draws the controls side by side and touching, as a
/// segmented control does; `.menu` and `.compactMenu` put them behind a menu
/// that the group's label opens.
public struct ControlGroup<Content: View>: View {
    let content: Content

    /// Creates a new control group with the specified children.
    ///
    /// - Parameter content: The views to display inside the group.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        // Through the configuration's content too: `ControlGroup(configuration)`
        // holds its labelled content in one.
        let parts =
            content as? any LabeledControlGroupParts
            ?? (content as? _StyledContent)?.underlying as? any LabeledControlGroupParts
        _StyledControlGroup(
            configuration: ControlGroupStyleConfiguration(
                label: parts?.erasedLabel ?? AnyView(EmptyView()),
                content: parts?.styledContent ?? _StyledContent(content)))
    }
}

/// A control group's content together with the label that describes it — what
/// ``ControlGroup/init(content:label:)`` holds, as SwiftUI's does.
public struct LabeledControlGroupContent<Content: View, Label: View>: View {
    let content: Content
    let label: Label

    public var body: some View {
        content
    }
}

/// How a control group finds a label in its content.
@MainActor
private protocol LabeledControlGroupParts {
    var erasedLabel: AnyView { get }
    var styledContent: _StyledContent { get }
}

extension LabeledControlGroupContent: LabeledControlGroupParts {
    var erasedLabel: AnyView { AnyView(label) }
    var styledContent: _StyledContent { _StyledContent(content) }
}

extension ControlGroup {
    /// Creates a new control group with the specified content and a label.
    ///
    /// - Parameters:
    ///   - content: The views to display inside the group.
    ///   - label: A view that describes the purpose of the group.
    public init<C: View, L: View>(
        @ViewBuilder content: () -> C, @ViewBuilder label: () -> L
    ) where Content == LabeledControlGroupContent<C, L> {
        self.content = LabeledControlGroupContent(content: content(), label: label())
    }

    /// Creates a new control group with the specified content and a localized
    /// title for its label.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the group's title.
    ///   - content: The views to display inside the group.
    public init<C: View>(
        _ titleKey: LocalizedStringKey, @ViewBuilder content: () -> C
    ) where Content == LabeledControlGroupContent<C, Text> {
        self.init(content: content, label: { Text(titleKey) })
    }

    /// Creates a new control group with the specified content and a title,
    /// shown as written.
    ///
    /// - Parameters:
    ///   - title: The group's title.
    ///   - content: The views to display inside the group.
    @_disfavoredOverload
    public init<C: View, S: StringProtocol>(
        _ title: S, @ViewBuilder content: () -> C
    ) where Content == LabeledControlGroupContent<C, Text> {
        self.init(content: content, label: { Text(title) })
    }

    /// Creates a new control group with the specified content, and a label from
    /// a localized title and an SF Symbol.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the group's title.
    ///   - systemImage: The SF Symbol name for the label's icon.
    ///   - content: The views to display inside the group.
    public init<C: View>(
        _ titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> C
    ) where Content == LabeledControlGroupContent<C, Label<Text, _SymbolIcon>> {
        self.init(content: content, label: { Label(titleKey, systemImage: systemImage) })
    }

    /// Creates a new control group with the specified content, and a label from
    /// a title shown as written and an SF Symbol.
    ///
    /// - Parameters:
    ///   - title: The group's title.
    ///   - systemImage: The SF Symbol name for the label's icon.
    ///   - content: The views to display inside the group.
    @_disfavoredOverload
    public init<C: View, S: StringProtocol>(
        _ title: S, systemImage: String, @ViewBuilder content: () -> C
    ) where Content == LabeledControlGroupContent<C, Label<Text, _SymbolIcon>> {
        self.init(content: content, label: { Label(title, systemImage: systemImage) })
    }
}

extension ControlGroup where Content == ControlGroupStyleConfiguration.Content {
    /// Creates a control group based on a style configuration.
    ///
    /// Use it inside a ``ControlGroupStyle``'s
    /// ``ControlGroupStyle/makeBody(configuration:)`` to draw the group as the
    /// style outside the custom one would, and add to it. Its label goes with
    /// it.
    ///
    /// - Parameter configuration: The properties of the control group.
    public init(_ configuration: ControlGroupStyleConfiguration) {
        self.content = _StyledContent(
            LabeledControlGroupContent(content: configuration.content, label: configuration.label))
    }
}

// MARK: - Style

/// The properties of a control group.
public struct ControlGroupStyleConfiguration {
    /// A type-erased label of a control group.
    public typealias Label = AnyView

    /// A type-erased content of a control group, whose views lay out as
    /// separate children of a stack the style puts it in.
    public typealias Content = _StyledContent

    /// A view that describes the effect of interacting with the control group:
    /// empty for a group built without one.
    public let label: Label

    /// A view that represents the content of the control group.
    public let content: Content
}

/// Defines the implementation of all control groups within a view hierarchy.
public protocol ControlGroupStyle: Sendable {
    /// A view representing the body of a control group.
    associatedtype Body: View

    /// Creates a view representing the body of a control group.
    ///
    /// - Parameter configuration: The properties of the control group instance
    ///   being created.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The properties of a control group.
    typealias Configuration = ControlGroupStyleConfiguration
}

extension ControlGroupStyle {
    /// This style's body, type-erased — opening the existential the
    /// environment holds.
    @MainActor
    func makeAnyBody(configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

/// The controls side by side, touching — a segmented control's shape.
private struct _ControlStrip: View {
    let content: _StyledContent

    var body: some View {
        HStack(spacing: 0) {
            content
        }
    }
}

/// The default control group style: the controls side by side, touching, as a
/// segmented control.
public struct AutomaticControlGroupStyle: ControlGroupStyle, Equatable {
    public func makeBody(configuration: Configuration) -> some View {
        _ControlStrip(content: configuration.content)
    }
}

/// A control group style that presents its content as a menu, which the
/// group's label opens.
public struct MenuControlGroupStyle: ControlGroupStyle, Equatable {
    /// Creates a menu control group style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Menu {
            configuration.content
        } label: {
            configuration.label
        }
    }
}

/// A control group style that presents its content as a compact menu: the same
/// menu here, where a menu is already as compact as it gets.
public struct CompactMenuControlGroupStyle: ControlGroupStyle, Equatable {
    /// Creates a compact menu control group style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        MenuControlGroupStyle().makeBody(configuration: configuration)
    }
}

/// The navigation control group style, for back/forward and similar pairs: the
/// controls side by side, touching.
public struct NavigationControlGroupStyle: ControlGroupStyle, Equatable {
    /// Creates a navigation control group style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _ControlStrip(content: configuration.content)
    }
}

/// A control group style that presents its content as a palette — outside a
/// menu, as a segmented control, which is how SwiftUI renders it there too.
public struct PaletteControlGroupStyle: ControlGroupStyle, Equatable {
    /// Creates a palette control group style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _ControlStrip(content: configuration.content)
    }
}

extension ControlGroupStyle where Self == AutomaticControlGroupStyle {
    /// The default control group style.
    public static var automatic: AutomaticControlGroupStyle { AutomaticControlGroupStyle() }
}

extension ControlGroupStyle where Self == MenuControlGroupStyle {
    /// A control group style that presents its content as a menu.
    public static var menu: MenuControlGroupStyle { MenuControlGroupStyle() }
}

extension ControlGroupStyle where Self == CompactMenuControlGroupStyle {
    /// A control group style that presents its content as a compact menu.
    public static var compactMenu: CompactMenuControlGroupStyle { CompactMenuControlGroupStyle() }
}

extension ControlGroupStyle where Self == NavigationControlGroupStyle {
    /// The navigation control group style.
    public static var navigation: NavigationControlGroupStyle { NavigationControlGroupStyle() }
}

extension ControlGroupStyle where Self == PaletteControlGroupStyle {
    /// A control group style that presents its content as a palette.
    public static var palette: PaletteControlGroupStyle { PaletteControlGroupStyle() }
}

// MARK: - Environment

private struct ControlGroupStyleKey: EnvironmentKey {
    static let defaultValue = StyleChain<any ControlGroupStyle>(AutomaticControlGroupStyle())
}

extension EnvironmentValues {
    /// The control group style in force, and the ones outside it.
    var controlGroupStyleChain: StyleChain<any ControlGroupStyle> {
        get { self[ControlGroupStyleKey.self] }
        set { self[ControlGroupStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for control groups within this view.
    ///
    /// - Parameter style: The style to apply to control groups within this view.
    /// - Returns: A view whose control groups use `style`.
    public func controlGroupStyle<S: ControlGroupStyle>(_ style: S) -> some View {
        transformEnvironment(\.controlGroupStyleChain) { $0 = $0.pushing(style) }
    }
}

/// A control group drawn through the style in force; see `_StyledGroupBox` for
/// the shape.
private struct _StyledControlGroup: View {
    let configuration: ControlGroupStyleConfiguration
    @Environment(\.controlGroupStyleChain) private var styles

    @ViewBuilder var body: some View {
        if styles.isRoot {
            AutomaticControlGroupStyle().makeBody(configuration: configuration)
        } else {
            styles.style.makeAnyBody(configuration: configuration)
                .environment(\.controlGroupStyleChain, styles.inside)
        }
    }
}

// MARK: - Environment without reflection

extension _StyledControlGroup: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _styles.resolveEnvironment(environment)
    }
}
