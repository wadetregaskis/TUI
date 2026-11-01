//  🖥️ TUI — A Terminal UI framework for Swift
//  GaugeStyle+Variants.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIFoundation

extension GaugeStyle {

    /// Renders this style's body for `configuration` into a frame buffer. Opens
    /// the `any GaugeStyle` existential so ``makeBody(configuration:)`` can
    /// return its concrete ``Body``. Used only for custom styles.
    @MainActor
    func makeBuffer(configuration: Configuration, context: RenderContext) -> FrameBuffer {
        renderToBuffer(
            observingStyleBody(of: Self.self, kind: .styleRender, context: context) {
                makeBody(configuration: configuration)
            }, context: context)
    }

    /// Measures this style's body for `configuration`, opening the existential
    /// the same way ``makeBuffer(configuration:context:)`` does.
    ///
    /// A custom body is an ordinary view, so it is measured as one rather than
    /// rendered and counted — the two-pass layout asks for a size far more often
    /// than it asks for bytes, and measuring by rendering is half a frame
    /// (`Documentation/Performance/What makes a page slow to open.md`).
    @MainActor
    func makeSize(
        configuration: Configuration, proposal: ProposedSize, context: RenderContext
    ) -> ViewSize {
        measureChild(
            observingStyleBody(of: Self.self, kind: .styleMeasure, context: context) {
                makeBody(configuration: configuration)
            }, proposal: proposal, context: context)
    }
}

// MARK: - Built-in Gauge Styles

/// The default gauge style. In TUI this draws what ``LinearCapacityGaugeStyle``
/// draws: a shaded horizontal meter.
///
/// `Equatable` for the reason given under ``GaugeStyle``: a memo below a value
/// the render cache cannot compare declines to cache. It holds nothing, so every
/// instance draws the same gauge.
public struct DefaultGaugeStyle: GaugeStyle, Equatable {
    /// A gauge in this style — what a style composing this one draws.
    public func makeBody(configuration: Configuration) -> some View {
        Gauge(configuration).gaugeStyle(self)
    }

    /// Creates the default gauge style.
    public init() {}
}

/// A gauge style that draws a horizontal bar filled in proportion to the value,
/// flanked by the bound labels.
///
/// The bar is a *shaded* meter (`▓`/`░`) — deliberately distinct from
/// ``ProgressView``'s solid blocks and ``Slider``'s knob-on-a-rail, so the three
/// read differently at a glance.
///
/// `Equatable` on the same terms as ``DefaultGaugeStyle``, and the two draw the
/// same meter, so the worst a comparison between them can do is drop a cache
/// entry that would have been good.
public struct LinearCapacityGaugeStyle: GaugeStyle, Equatable {
    /// A gauge in this style — what a style composing this one draws.
    public func makeBody(configuration: Configuration) -> some View {
        Gauge(configuration).gaugeStyle(self)
    }

    /// Creates a linear-capacity gauge style.
    public init() {}
}

/// A gauge style that draws a plain horizontal line with a marker at the current
/// value's position (`─────●─────`) — no fill.
///
/// `Equatable` on the same terms as ``DefaultGaugeStyle``.
public struct AccessoryLinearGaugeStyle: GaugeStyle, Equatable {
    /// A gauge in this style — what a style composing this one draws.
    public func makeBody(configuration: Configuration) -> some View {
        Gauge(configuration).gaugeStyle(self)
    }

    /// Creates an accessory-linear gauge style.
    public init() {}
}

/// A gauge style that draws a slim horizontal bar filled from the minimum to the
/// current value, with sub-cell precision.
///
/// `Equatable` on the same terms as ``DefaultGaugeStyle``.
public struct AccessoryLinearCapacityGaugeStyle: GaugeStyle, Equatable {
    /// A gauge in this style — what a style composing this one draws.
    public func makeBody(configuration: Configuration) -> some View {
        Gauge(configuration).gaugeStyle(self)
    }

    /// Creates an accessory-linear-capacity gauge style.
    public init() {}
}

/// A gauge style that draws a ring dial with a marker at the current value's
/// position on the ring.
///
/// `Equatable` on the same terms as ``DefaultGaugeStyle``, and this is one of the
/// types that earns the cross-type comparison: a ring is three rows where a bar
/// is one, so a swap between them changes the gauge's height and must read as a
/// change.
public struct AccessoryCircularGaugeStyle: GaugeStyle, Equatable {
    /// A gauge in this style — what a style composing this one draws.
    public func makeBody(configuration: Configuration) -> some View {
        Gauge(configuration).gaugeStyle(self)
    }

    /// Creates an accessory-circular gauge style.
    public init() {}
}

/// A gauge style that draws a ring dial whose arc fills from the minimum to the
/// current value.
///
/// `Equatable` on the same terms as ``AccessoryCircularGaugeStyle``.
public struct AccessoryCircularCapacityGaugeStyle: GaugeStyle, Equatable {
    /// A gauge in this style — what a style composing this one draws.
    public func makeBody(configuration: Configuration) -> some View {
        Gauge(configuration).gaugeStyle(self)
    }

    /// Creates an accessory-circular-capacity gauge style.
    public init() {}
}

/// A gauge style that draws a single compact pie glyph (`○◔◑◕●`) beside the
/// value — for when a gauge must fit a tight space and exact resolution isn't
/// important.
///
/// TUI-specific: SwiftUI has no counterpart, because the constraint it answers is
/// a terminal's. The ring dial is three rows tall, and a gauge inside a list row
/// or a status line has one.
///
/// `Equatable` on the same terms as ``DefaultGaugeStyle``.
public struct AccessoryCircularTinyGaugeStyle: GaugeStyle, Equatable {
    /// A gauge in this style — what a style composing this one draws.
    public func makeBody(configuration: Configuration) -> some View {
        Gauge(configuration).gaugeStyle(self)
    }

    /// Creates an accessory-circular-tiny gauge style.
    public init() {}
}

// MARK: - GaugeStyle Static Accessors

extension GaugeStyle where Self == DefaultGaugeStyle {
    /// The default gauge style. On a terminal this draws
    /// ``GaugeStyle/linearCapacity``.
    public static var automatic: DefaultGaugeStyle { DefaultGaugeStyle() }
}

extension GaugeStyle where Self == LinearCapacityGaugeStyle {
    /// A gauge style that draws a bar filled in proportion to the value, flanked
    /// by the bound labels.
    public static var linearCapacity: LinearCapacityGaugeStyle { LinearCapacityGaugeStyle() }
}

extension GaugeStyle where Self == AccessoryLinearGaugeStyle {
    /// A gauge style that marks the value's position on a plain line.
    public static var accessoryLinear: AccessoryLinearGaugeStyle { AccessoryLinearGaugeStyle() }
}

extension GaugeStyle where Self == AccessoryLinearCapacityGaugeStyle {
    /// A gauge style that draws a slim, sub-cell-precise bar filled from the
    /// minimum to the value.
    public static var accessoryLinearCapacity: AccessoryLinearCapacityGaugeStyle {
        AccessoryLinearCapacityGaugeStyle()
    }
}

extension GaugeStyle where Self == AccessoryCircularGaugeStyle {
    /// A gauge style that marks the value's position on a ring dial.
    public static var accessoryCircular: AccessoryCircularGaugeStyle { AccessoryCircularGaugeStyle() }
}

extension GaugeStyle where Self == AccessoryCircularCapacityGaugeStyle {
    /// A gauge style whose ring dial fills from the minimum to the value.
    public static var accessoryCircularCapacity: AccessoryCircularCapacityGaugeStyle {
        AccessoryCircularCapacityGaugeStyle()
    }
}

extension GaugeStyle where Self == AccessoryCircularTinyGaugeStyle {
    /// A gauge style that draws a single compact pie glyph beside the value.
    ///
    /// > Note: TUI-specific — SwiftUI has no `accessoryCircularTiny`.
    public static var accessoryCircularTiny: AccessoryCircularTinyGaugeStyle {
        AccessoryCircularTinyGaugeStyle()
    }
}

// MARK: - GaugeStyle Resolution

/// Which terminal rendering a built-in ``GaugeStyle`` draws.
///
/// One answer rather than a chain of `is` tests at each decision, because a
/// gauge asks four questions of its style — bar or dial, which track glyphs,
/// ring or pie, fill or mark — and each of measure and render asks them. Answered
/// in one place, adding a style is one case here; answered where each is asked,
/// it is four edits that can disagree, and the two passes disagreeing about the
/// shape is exactly the measure/render divergence `_GaugeCore` already keeps one
/// function per rule to prevent.
enum GaugeShape: Equatable {
    /// A horizontal bar, drawn with the given track glyphs.
    case linear(TrackStyle)

    /// The ring dial. `capacity` fills the arc from the minimum to the value;
    /// otherwise a single bright cell marks the value's position.
    case ring(capacity: Bool)

    /// The single pie glyph beside the value.
    case tinyDial
}

extension GaugeStyle {
    /// The terminal rendering this style draws, or `nil` for a custom style —
    /// which draws through ``makeBody(configuration:)`` instead.
    var builtInShape: GaugeShape? {
        switch self {
        case is DefaultGaugeStyle, is LinearCapacityGaugeStyle: .linear(.shade)
        case is AccessoryLinearGaugeStyle: .linear(.marker)  // position only, no fill
        case is AccessoryLinearCapacityGaugeStyle: .linear(.blockFine)  // min→value, sub-cell
        case is AccessoryCircularGaugeStyle: .ring(capacity: false)
        case is AccessoryCircularCapacityGaugeStyle: .ring(capacity: true)
        case is AccessoryCircularTinyGaugeStyle: .tinyDial
        default: nil
        }
    }
}

// MARK: - Environment

/// Environment key for the gauge style.
private struct GaugeStyleKey: EnvironmentKey {
    static let defaultValue: any GaugeStyle = DefaultGaugeStyle()
}

extension EnvironmentValues {
    /// The style ``Gauge`` views render with. Set via ``View/gaugeStyle(_:)``.
    /// Default: ``DefaultGaugeStyle``.
    ///
    /// The render cache compares this value between frames to decide whether
    /// what it memoized below is still good, so a style that is not `Equatable`
    /// turns memoization off in its subtree — see ``GaugeStyle``.
    public var gaugeStyle: any GaugeStyle {
        get { self[GaugeStyleKey.self] }
        set { self[GaugeStyleKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Sets the style for gauges within this view, mirroring SwiftUI's
    /// `gaugeStyle(_:)`.
    ///
    /// Apply it to a single ``Gauge`` or to a container to style every gauge it
    /// contains:
    ///
    /// ```swift
    /// Gauge(value: load) { Text("Load") }
    ///     .gaugeStyle(.accessoryCircular)
    /// ```
    ///
    /// - Parameter style: The gauge style to apply.
    /// - Returns: A view whose gauges use the specified style.
    nonisolated public func gaugeStyle<S: GaugeStyle>(_ style: S) -> some View {
        environment(\.gaugeStyle, style)
    }
}
