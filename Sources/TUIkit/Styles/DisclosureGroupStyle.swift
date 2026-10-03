//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DisclosureGroupStyle.swift
//
//  How a DisclosureGroup draws its label, its content and the control that
//  shows and hides the content — SwiftUI's open style protocol.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Configuration

/// The properties of a disclosure group instance.
public struct DisclosureGroupStyleConfiguration {
    /// A type-erased label of a disclosure group.
    public struct Label: View {
        let content: AnyView

        public var body: some View { content }
    }

    /// A type-erased content of a disclosure group, built only when a style
    /// places it — a style that shows it only while expanded builds nothing for
    /// a collapsed group, as the automatic style does.
    public struct Content: View {
        let make: @MainActor () -> AnyView

        public var body: some View { make() }
    }

    /// The label for the disclosure group.
    public let label: Label

    /// The content of the disclosure group.
    public let content: Content

    /// A binding to a Boolean that indicates whether the disclosure group is
    /// expanded.
    @Binding public var isExpanded: Bool
}

// MARK: - Protocol

/// A type that specifies the appearance and interaction of disclosure groups
/// within a view hierarchy.
///
/// ```swift
/// struct ArrowDisclosureStyle: DisclosureGroupStyle {
///     func makeBody(configuration: Configuration) -> some View {
///         VStack(alignment: .leading, spacing: 0) {
///             Button(configuration.isExpanded ? "▼" : "▶") {
///                 configuration.isExpanded.toggle()
///             }
///             if configuration.isExpanded {
///                 configuration.content.padding(.leading, 2)
///             }
///         }
///     }
/// }
/// ```
public protocol DisclosureGroupStyle: Sendable {
    /// A view that represents the body of a disclosure group.
    associatedtype Body: View

    /// Creates a view that represents the body of a disclosure group.
    ///
    /// - Parameter configuration: The properties of the instance being created.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The properties of a disclosure group instance.
    typealias Configuration = DisclosureGroupStyleConfiguration
}

extension DisclosureGroupStyle {
    /// This style's body, type-erased — opening the existential the
    /// environment holds.
    @MainActor
    func makeAnyBody(configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

// MARK: - The automatic style

/// The default disclosure group style: a triangle beside the label that shows
/// and hides the content, indented under the label.
///
/// The header is one button: Return, Space or a click toggles it, Right opens
/// and Left closes — as an outline row does everywhere else in this framework.
public struct AutomaticDisclosureGroupStyle: DisclosureGroupStyle, Equatable {
    /// Creates an automatic disclosure group style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        // Captured once: the closures below run on a later key or click, long
        // after this body returned, and must write through the same binding
        // this frame read. A `Binding` is a pair of closures, so this is a copy
        // of two references, not a snapshot of the value.
        let expansion = configuration.$isExpanded
        VStack(alignment: .leading, spacing: 0) {
            Button(
                action: { expansion.wrappedValue.toggle() },
                label: {
                    HStack(spacing: DisclosureMetrics.glyphSpacing) {
                        // `verbatim`: a triangle is a glyph, not a localization key.
                        Text(verbatim: expansion.wrappedValue
                            ? TerminalSymbols.disclosureExpanded
                            : TerminalSymbols.disclosureCollapsed)
                        configuration.label
                    }
                }
            )
            .buttonStyle(.borderless)
            // Left closes and Right opens, which is what an outline view does
            // everywhere else in this framework — a `List(_:children:)` has
            // answered these keys since it gained a tree, and a disclosure that
            // did not was the odd one out. They SET rather than toggle, so
            // holding Right on an open group does nothing rather than shutting
            // it.
            .buttonKeyExtras(keys: [.left, .right]) { event in
                let wanted = event.key == .right
                guard expansion.wrappedValue != wanted else {
                    // Nothing to do here. Right is still the disclosure's — a
                    // group that is already open should not hand the key on and
                    // move the focus sideways. Left is not: once there is
                    // nothing left to close, it belongs to whatever encloses
                    // this group.
                    return wanted
                }
                expansion.wrappedValue = wanted
                return true
            }

            if expansion.wrappedValue {
                configuration.content.padding(.leading, DisclosureMetrics.contentIndent)
            }
        }
    }
}

extension DisclosureGroupStyle where Self == AutomaticDisclosureGroupStyle {
    /// A disclosure group style that resolves its appearance automatically
    /// based on the current context.
    public static var automatic: AutomaticDisclosureGroupStyle { AutomaticDisclosureGroupStyle() }
}

// MARK: - Environment

private struct DisclosureGroupStyleKey: EnvironmentKey {
    static let defaultValue: any DisclosureGroupStyle = AutomaticDisclosureGroupStyle()
}

extension EnvironmentValues {
    /// The style disclosure groups in this environment draw with.
    var disclosureGroupStyle: any DisclosureGroupStyle {
        get { self[DisclosureGroupStyleKey.self] }
        set { self[DisclosureGroupStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for disclosure groups within this view.
    ///
    /// - Parameter style: The style to apply.
    /// - Returns: A view whose disclosure groups use `style`.
    public func disclosureGroupStyle<S: DisclosureGroupStyle>(_ style: S) -> some View {
        environment(\.disclosureGroupStyle, style)
    }
}

/// A disclosure group drawn through the style in force: the automatic one
/// unerased, which is the case nearly every group is in.
struct _StyledDisclosureGroup: View {
    let configuration: DisclosureGroupStyleConfiguration
    @Environment(\.disclosureGroupStyle) private var style

    @ViewBuilder var body: some View {
        if style is AutomaticDisclosureGroupStyle {
            AutomaticDisclosureGroupStyle().makeBody(configuration: configuration)
        } else {
            style.makeAnyBody(configuration: configuration)
        }
    }
}
