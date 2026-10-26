//  🖥️ TUI — A Terminal UI framework for Swift
//  GaugeStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - GaugeStyle Protocol

/// The appearance of a ``Gauge``.
///
/// To configure the style for a single `Gauge` or for every gauge in a view
/// hierarchy, use the ``View/gaugeStyle(_:)`` modifier:
///
/// ```swift
/// Gauge(value: 0.7) { Text("CPU") }
///     .gaugeStyle(.accessoryCircular)
/// ```
///
/// ## Built-in Styles
///
/// SwiftUI's built-in gauges are drawn with real geometry. A terminal can't
/// draw arbitrary shapes, so each of these is a terminal-native rendering that
/// carries the same name and the same intent:
///
/// | Style | Terminal rendering |
/// |-------|--------------------|
/// | ``automatic`` / ``linearCapacity`` | A full horizontal bar with bound labels — a shaded meter |
/// | ``accessoryLinear`` | A plain line with a marker at the value (`─────●─────`) — position only, no fill |
/// | ``accessoryLinearCapacity`` | A slim, sub-cell-precise bar filled from the minimum to the value |
/// | ``accessoryCircular`` | A ring dial with a marker at the value's position on the ring |
/// | ``accessoryCircularCapacity`` | A ring dial whose arc fills from the minimum to the value |
/// | ``accessoryCircularTiny`` | A single compact pie glyph (`○◔◑◕●`) — where clarity matters less than size |
///
/// The **capacity** styles are cumulative: they fill the range from the
/// minimum up to the current value. The **non-capacity** styles mark only the
/// value's *position* (a point / a marker on the ring). This mirrors SwiftUI's
/// distinction.
///
/// The first six carry SwiftUI's names and types. ``accessoryCircularTiny`` is
/// a TUI-specific addition with no SwiftUI counterpart — a terminal row is
/// often one line tall, and there the three-row ring does not fit.
///
/// ## Custom styles
///
/// Conform to `GaugeStyle` and implement ``makeBody(configuration:)`` to draw a
/// gauge however you like — a `▁▂▃▄▅▆▇` sparkline cell, an "N of M" readout, a
/// house bar. The built-in styles above don't implement `makeBody`; they render
/// procedurally, through `TrackRenderer` and the ring dial. Only custom styles
/// use it, exactly as with ``ButtonStyle``, ``ToggleStyle`` and ``LabelStyle``.
///
/// ```swift
/// struct BlocksGaugeStyle: GaugeStyle {
///     func makeBody(configuration: Configuration) -> some View {
///         let filled = Int((configuration.value * 5).rounded())
///         return HStack {
///             configuration.label
///             Text(String(repeating: "▰", count: filled)
///                 + String(repeating: "▱", count: 5 - filled))
///         }
///     }
/// }
/// ```
///
/// A custom style draws the whole gauge: the built-in label line and bound
/// labels are the built-in renderings' arrangement, not the gauge's, so whatever
/// of ``GaugeStyleConfiguration``'s five labels a custom body does not place is
/// not drawn. The same goes for ``View/labelsHidden()`` — the built-in styles
/// honour it, and a custom style that wants to reads `\.labelsVisibility` from
/// the environment itself.
///
/// ## Styles and the render cache
///
/// ``View/gaugeStyle(_:)`` puts the style into the environment, and the render
/// cache keeps memoized subtrees honest by comparing each injected value with
/// the one applied there last frame. A value it cannot compare may have changed
/// under a buffer it is about to serve with nothing able to notice, so every
/// memo below one declines to cache at all — not the gauge alone, but everything
/// under the modifier.
///
/// All seven built-in styles are therefore `Equatable`. None of them holds
/// anything, and the only thing the framework ever reads off a style is
/// `builtInShape`, which is a function of the type and of nothing else — so
/// `==` within a type is vacuously true and two instances of one really do draw
/// the same gauge. Between types it is the downcast in the comparison that
/// answers, and that is what a gauge needs: a swap from a bar to a ring changes
/// the drawing's height as well as its glyphs.
///
/// A custom style need not conform. One that is not `Equatable` simply turns
/// memoization off below itself, which costs render time rather than
/// correctness.
///
/// - Note: SwiftUI's gauge styles declare no such conformance, and this is one
///   of the places a terminal renderer has to differ. SwiftUI diffs the view
///   graph the compiler builds for it and never has to ask whether an
///   environment value changed; TUI re-runs `body` and compares values, so
///   here the question must be answerable.
public protocol GaugeStyle: Sendable {
    /// A view representing the gauge's appearance.
    associatedtype Body: View = EmptyView

    /// Creates a view that represents the body of a gauge.
    ///
    /// - Parameter configuration: The properties of the gauge being styled.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The properties of a gauge.
    typealias Configuration = GaugeStyleConfiguration
}

// MARK: - Configuration

/// The properties of a gauge, passed to a ``GaugeStyle`` so it can produce the
/// gauge's appearance.
///
/// You don't create this — TUI builds one per ``Gauge`` and hands it to a
/// custom style's ``GaugeStyle/makeBody(configuration:)``. It carries SwiftUI's
/// five properties under SwiftUI's names.
///
/// - Note: SwiftUI gives each label its own nested type-erasing struct
///   (`GaugeStyleConfiguration.Label` and friends). TUI's are names for
///   ``AnyView``, as ``ToggleStyleConfiguration``'s and
///   ``LabelStyleConfiguration``'s are: a style body places them the same way
///   either way, and source that names one compiles.
public struct GaugeStyleConfiguration {
    /// A type-erased label of a gauge, describing its purpose.
    public typealias Label = AnyView

    /// A type-erased label describing the current value of a gauge.
    public typealias CurrentValueLabel = AnyView

    /// A type-erased label describing the minimum value of a gauge.
    public typealias MinimumValueLabel = AnyView

    /// A type-erased label describing the maximum value of a gauge.
    public typealias MaximumValueLabel = AnyView

    /// A type-erased label describing a marked value of a gauge.
    public typealias MarkedValueLabel = AnyView

    /// The current value of the gauge, normalized to `0.0...1.0`.
    ///
    /// ``Gauge`` normalizes against the bounds it was given and clamps, so a
    /// style never has to — and never sees the original units. Same range, and
    /// the same documented range, as SwiftUI's.
    public let value: Double

    /// A view that describes the purpose of the gauge, type-erased.
    public let label: AnyView

    /// A view that describes the current value, or `nil` when the gauge has
    /// none.
    public let currentValueLabel: AnyView?

    /// A view that describes the minimum of the range, or `nil` when the gauge
    /// has none.
    public let minimumValueLabel: AnyView?

    /// A view that describes the maximum of the range, or `nil` when the gauge
    /// has none.
    public let maximumValueLabel: AnyView?

    /// The memberwise initializer. Configurations are produced by ``Gauge``
    /// during rendering, never by client code, so this is `package`, not
    /// public, as SwiftUI's `GaugeStyleConfiguration` publishes no initializer
    /// either; spelled out because the synthesized one is internal and `Gauge`
    /// is TUINumericControls' (TUITextInput's from step B7 until step C7).
    package init(
        value: Double, label: AnyView, currentValueLabel: AnyView?, minimumValueLabel: AnyView?,
        maximumValueLabel: AnyView?
    ) {
        self.value = value
        self.label = label
        self.currentValueLabel = currentValueLabel
        self.minimumValueLabel = minimumValueLabel
        self.maximumValueLabel = maximumValueLabel
    }
}
