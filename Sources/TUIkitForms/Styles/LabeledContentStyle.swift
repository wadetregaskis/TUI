//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LabeledContentStyle.swift
//
//  How a ``LabeledContent`` lays out its label and its content — SwiftUI's
//  open style protocol, modelled on ``LabelStyle``: pure recomposition of two
//  views the caller supplied, so anything a custom style wants to do here a
//  terminal can do.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Configuration

/// The properties of a labeled content instance.
public struct LabeledContentStyleConfiguration {
    /// A type-erased label of a labeled content instance.
    public typealias Label = AnyView

    /// A type-erased content of a labeled content instance.
    public typealias Content = AnyView

    /// The label of the labeled content instance.
    public let label: Label

    /// The content of the labeled content instance.
    public let content: Content
}

// MARK: - Protocol

/// The appearance and layout behavior of labeled content in a view hierarchy.
///
/// ```swift
/// struct StackedLabeledContentStyle: LabeledContentStyle {
///     func makeBody(configuration: Configuration) -> some View {
///         VStack(alignment: .leading) {
///             configuration.label.bold()
///             configuration.content
///         }
///     }
/// }
/// ```
///
/// Applied inside a ``Form`` too: a form lays its labelled rows out in a column
/// of right-aligned labels itself, and a custom style takes that row over.
public protocol LabeledContentStyle: Sendable {
    /// A view that represents the appearance and behavior of labeled content.
    associatedtype Body: View

    /// Creates a view that represents the body of labeled content.
    ///
    /// - Parameter configuration: The label and content being styled.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The properties of a labeled content instance.
    typealias Configuration = LabeledContentStyleConfiguration
}

extension LabeledContentStyle {
    /// This style's body for `configuration`, type-erased — opening the
    /// existential the environment holds, as ``LabelStyle`` does.
    @MainActor
    func makeAnyBody(configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

// MARK: - The built-in style

/// The default labeled content style: the label leading, the content trailing,
/// the content taking whatever width the row has left.
///
/// The leftover goes to the CONTENT, not to a spacer beside it. A `Spacer` is
/// width-flexible and so is a `TextField`, and the stack distributes to flexible
/// children evenly — so a labelled field came out with half the line spent on
/// the gap in front of it. A flexible frame gives the content the whole
/// remainder and aligns a fixed-width content (the `value:` overloads' `Text`)
/// at its trailing edge. The label goes through `_CollapsingLabel`, the unit
/// every labelled control uses, so `.labelsHidden()` leaves the content holding
/// the whole row.
///
/// A content of several lines trails line by line: each line of its text ends
/// at the trailing edge (`.multilineTextAlignment(.trailing)`), as the trailing
/// value of SwiftUI's grouped `Form` does, its wrapped lines too (measured,
/// `Tools/SwiftUIProbes/Trailing values and labels`). The frame alone places
/// the content as one block, its lines leading inside it, which is SwiftUI's
/// frame and draws "short" over "a much longer line" with "short" left of the
/// trailing edge. (SwiftUI's `LabeledContent` outside a form leads its content
/// after the label instead, measured in the same probe; this style trails it, as
/// a form's value does.) A content that sets its own alignment keeps it.
public struct AutomaticLabeledContentStyle: LabeledContentStyle, Equatable {
    /// Creates the automatic labeled content style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            _CollapsingLabel(label: configuration.label, controlDisabled: false)
            configuration.content
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

extension LabeledContentStyle where Self == AutomaticLabeledContentStyle {
    /// A labeled content style that resolves its appearance automatically
    /// based on the current context.
    public static var automatic: AutomaticLabeledContentStyle { AutomaticLabeledContentStyle() }
}

// MARK: - Environment

private struct LabeledContentStyleKey: EnvironmentKey {
    static let defaultValue = StyleChain<any LabeledContentStyle>(AutomaticLabeledContentStyle())
}

extension EnvironmentValues {
    /// The style labeled content in this environment draws with, and the ones
    /// outside it. See ``StyleChain``.
    var labeledContentStyleChain: StyleChain<any LabeledContentStyle> {
        get { self[LabeledContentStyleKey.self] }
        set { self[LabeledContentStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets a style for labeled content.
    ///
    /// - Parameter style: The style to use.
    /// - Returns: A view whose labeled content uses `style`.
    public func labeledContentStyle<S: LabeledContentStyle>(_ style: S) -> some View {
        transformEnvironment(\.labeledContentStyleChain) { $0 = $0.pushing(style) }
    }
}

// MARK: - Drawing one

/// Labeled content drawn through the style in force: the body of
/// ``LabeledContent``, and of a ``Form`` row whose style is a custom one.
///
/// The style's body sees the style outside it, so a `LabeledContent(configuration)`
/// a custom style draws decorates the content as it would otherwise look rather
/// than recursing into the custom style.
struct _StyledLabeledContent: View {
    let configuration: LabeledContentStyleConfiguration
    @Environment(\.labeledContentStyleChain) private var styles

    /// At the root — no custom style anywhere above — the automatic style is
    /// drawn unerased, which is the case nearly every row is in.
    @ViewBuilder var body: some View {
        if styles.isRoot {
            AutomaticLabeledContentStyle().makeBody(configuration: configuration)
        } else {
            styles.style.makeAnyBody(configuration: configuration)
                .environment(\.labeledContentStyleChain, styles.inside)
        }
    }
}

// MARK: - Environment without reflection

extension _StyledLabeledContent: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _styles.resolveEnvironment(environment)
    }
}
