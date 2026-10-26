//  🖥️ TUI — A Terminal UI framework for Swift
//  ProgressViewStyle.swift
//
//  How a ProgressView draws — SwiftUI's open style protocol, and its linear
//  and circular built-ins.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Configuration

/// The properties of a progress view instance.
public struct ProgressViewStyleConfiguration {
    /// A type-erased label describing the task represented by the progress
    /// view.
    public struct Label: View {
        let content: AnyView

        public var body: some View { content }
    }

    /// A type-erased label that describes the current value of a progress
    /// view.
    public struct CurrentValueLabel: View {
        let content: AnyView

        public var body: some View { content }
    }

    /// The completed fraction of the task represented by the progress view,
    /// from `0.0` (not yet started) to `1.0` (fully complete), or `nil` if the
    /// progress is indeterminate.
    public let fractionCompleted: Double?

    /// A view that describes the task represented by the progress view, or
    /// `nil` for none.
    public var label: Label?

    /// A view that describes the current value of a progress view, or `nil`
    /// for none.
    public var currentValueLabel: CurrentValueLabel?

    /// The track the progress view was given with `trackStyle(_:)`, carried so
    /// a `ProgressView(configuration)` draws its bar the same way.
    var track: TrackStyle = .block
}

// MARK: - Protocol

/// A type that applies standard interaction behavior to all progress views
/// within a view hierarchy.
///
/// ```swift
/// struct PercentStyle: ProgressViewStyle {
///     func makeBody(configuration: Configuration) -> some View {
///         let percent = Int((configuration.fractionCompleted ?? 0) * 100)
///         Text("\(percent)%")
///     }
/// }
/// ```
public protocol ProgressViewStyle: Sendable {
    /// A view representing the body of a progress view.
    associatedtype Body: View

    /// Creates a view representing the body of a progress view.
    ///
    /// - Parameter configuration: The properties of the progress view being
    ///   created.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// A type alias for the properties of a progress view instance.
    typealias Configuration = ProgressViewStyleConfiguration
}

extension ProgressViewStyle {
    /// This style's body, type-erased — opening the existential the
    /// environment holds.
    @MainActor
    func makeAnyBody(configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

/// A built-in style the progress view draws itself, procedurally, as a bar
/// with its track — rather than through a body.
protocol LinearProgressViewStyleKind: ProgressViewStyle {}

/// The bar a built-in linear style draws for `configuration`.
@MainActor
private func linearBar(_ configuration: ProgressViewStyleConfiguration) -> some View {
    _ProgressViewCore(
        fractionCompleted: configuration.fractionCompleted, style: configuration.track,
        label: configuration.label, currentValueLabel: configuration.currentValueLabel)
}

// MARK: - Built-in styles

/// The default progress view style in the current context of the view being
/// styled: the linear bar, as on macOS.
public struct DefaultProgressViewStyle: LinearProgressViewStyleKind, Equatable {
    /// Creates a default progress view style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        linearBar(configuration)
    }
}

/// A progress view that visually indicates its progress using a horizontal
/// bar.
public struct LinearProgressViewStyle: LinearProgressViewStyleKind, Equatable {
    /// Creates a linear progress view style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        linearBar(configuration)
    }
}

/// A progress view that uses a circular gauge to indicate the partial
/// completion of an activity.
///
/// Determinate, a ring that fills (the ``Gauge``'s circular capacity style,
/// three rows tall); indeterminate, a ``Spinner`` — SwiftUI's own fallback
/// where no determinate circle is available.
public struct CircularProgressViewStyle: ProgressViewStyle, Equatable {
    /// Creates a circular progress view style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        if let fraction = configuration.fractionCompleted {
            Gauge(value: fraction) {
                configuration.label
            } currentValueLabel: {
                configuration.currentValueLabel
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            HStack(spacing: 1) {
                Spinner()
                configuration.label
            }
        }
    }
}

extension ProgressViewStyle where Self == DefaultProgressViewStyle {
    /// The default progress view style in the current context of the view
    /// being styled.
    public static var automatic: DefaultProgressViewStyle { DefaultProgressViewStyle() }
}

extension ProgressViewStyle where Self == LinearProgressViewStyle {
    /// A progress view that visually indicates its progress using a horizontal
    /// bar.
    public static var linear: LinearProgressViewStyle { LinearProgressViewStyle() }
}

extension ProgressViewStyle where Self == CircularProgressViewStyle {
    /// The style of a progress view that uses a circular gauge to indicate the
    /// partial completion of an activity.
    public static var circular: CircularProgressViewStyle { CircularProgressViewStyle() }
}

// MARK: - Environment

private struct ProgressViewStyleKey: EnvironmentKey {
    static let defaultValue = StyleChain<any ProgressViewStyle>(DefaultProgressViewStyle())
}

extension EnvironmentValues {
    /// The style progress views in this environment draw with, and the ones
    /// outside it. See ``StyleChain``.
    var progressViewStyleChain: StyleChain<any ProgressViewStyle> {
        get { self[ProgressViewStyleKey.self] }
        set { self[ProgressViewStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for progress views in this view.
    ///
    /// ```swift
    /// ProgressView(value: 0.5)
    ///     .progressViewStyle(.circular)
    /// ```
    ///
    /// The bar a linear style draws is chosen with ``ProgressView/trackStyle(_:)``.
    ///
    /// - Parameter style: The progress view style.
    /// - Returns: A view whose progress views use `style`.
    public func progressViewStyle<S: ProgressViewStyle>(_ style: S) -> some View {
        transformEnvironment(\.progressViewStyleChain) { $0 = $0.pushing(style) }
    }
}

// MARK: - Drawing one

/// A progress view drawn through the style in force: a built-in linear one
/// procedurally, unerased; anything else through its body, which sees the
/// style outside it so a `ProgressView(configuration)` there draws as that
/// style would.
///
/// Reads the style from the context and draws the chosen view in place,
/// rather than holding an `@Environment` and an `if`/`else` in a body: as a
/// composite every bar paid a body evaluation and a `ConditionalView` level on
/// both walks, for a branch the default style never takes. A linear bar draws
/// its core where it stands; a style's body draws under a branch identity of
/// its own, so the two never read each other's state.
struct _StyledProgressView<Label: View, CurrentValueLabel: View>: View, Renderable, Layoutable {
    let fractionCompleted: Double?
    let track: TrackStyle
    let label: Label?
    let currentValueLabel: CurrentValueLabel?

    var body: Never {
        fatalError("_StyledProgressView renders via Renderable")
    }

    /// The built-in linear bar.
    private var core: _ProgressViewCore<Label, CurrentValueLabel> {
        _ProgressViewCore(
            fractionCompleted: fractionCompleted, style: track, label: label,
            currentValueLabel: currentValueLabel)
    }

    /// `styles`' style's body, seeing the styles outside it.
    private func styledBody(_ styles: StyleChain<any ProgressViewStyle>) -> some View {
        styles.style.makeAnyBody(
            configuration: ProgressViewStyleConfiguration(
                fractionCompleted: fractionCompleted,
                label: label.map { ProgressViewStyleConfiguration.Label(content: AnyView($0)) },
                currentValueLabel: currentValueLabel.map {
                    ProgressViewStyleConfiguration.CurrentValueLabel(content: AnyView($0))
                },
                track: track)
        )
        .environment(\.progressViewStyleChain, styles.inside)
    }

    /// Whether `style` is a built-in linear style — one of the two conformers of
    /// the internal ``LinearProgressViewStyleKind`` — asked by metatype identity.
    ///
    /// Two pointer compares, where `style is any LinearProgressViewStyleKind` was a
    /// `swift_dynamicCast` to a constrained existential, a conformance-cache probe
    /// on every measure and every render: 134 µs of a frame of 200 progress bars.
    /// Exact because the protocol is internal and has exactly these two
    /// conformers; the assert says so if a third is ever added. NOT a public
    /// requirement on ``ProgressViewStyle``, which is SwiftUI's protocol and
    /// keeps SwiftUI's shape.
    private static func drawsLinearBar(_ style: any ProgressViewStyle) -> Bool {
        let styleType = type(of: style)
        let isLinear = styleType == DefaultProgressViewStyle.self || styleType == LinearProgressViewStyle.self
        assert(
            isLinear == (style is any LinearProgressViewStyleKind),
            "a LinearProgressViewStyleKind conformer drawsLinearBar does not name")
        return isLinear
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let styles = context.environment.progressViewStyleChain
        if Self.drawsLinearBar(styles.style) {
            // In place, at this view's own identity and context: what the generic
            // `renderToBuffer` does for the core (not Animatable, so no
            // substitution) minus its clamp — which the render that reached this
            // one applies to the same context anyway, and a clamp is idempotent.
            return core.renderToBuffer(context: context)
        }
        return TUIView.renderToBuffer(styledBody(styles), context: context.withBranchIdentity("styled"))
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let styles = context.environment.progressViewStyleChain
        if Self.drawsLinearBar(styles.style) {
            // In place, with no measure memo entry of its own. `measureChild` here
            // was a second entry at this view's identity, for the same proposal and
            // the same reads (the style chain is not volatile), so it could never
            // serve a miss of this view's own entry — it was only ever stored, at
            // the cost of a value hash, a key, a lookup, a lease and a store per
            // bar per pass. `isMeasuring` as `measureChild` would have set it.
            if context.isMeasuring { return core.sizeThatFits(proposal: proposal, context: context) }
            var measuring = context
            measuring.isMeasuring = true
            return core.sizeThatFits(proposal: proposal, context: measuring)
        }
        return measureChild(styledBody(styles), proposal: proposal, context: context.withBranchIdentity("styled"))
    }
}

extension ProgressView
where
    Label == ProgressViewStyleConfiguration.Label,
    CurrentValueLabel == ProgressViewStyleConfiguration.CurrentValueLabel
{
    /// Creates a progress view based on a style configuration.
    ///
    /// Use it inside a ``ProgressViewStyle``'s
    /// ``ProgressViewStyle/makeBody(configuration:)`` to draw the progress view
    /// as the style outside the custom one would, and add to it.
    ///
    /// - Parameter configuration: The properties of the progress view.
    public init(_ configuration: ProgressViewStyleConfiguration) {
        self.init(
            fractionCompleted: configuration.fractionCompleted, style: configuration.track,
            label: configuration.label, currentValueLabel: configuration.currentValueLabel)
    }
}
