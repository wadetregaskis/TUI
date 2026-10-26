//  🖥️ TUI — A Terminal UI framework for Swift
//  MatchedTransitionSource.swift
//
//  `matchedTransitionSource(id:in:)`: the view a zoom navigation transition
//  grows from, and folds back into.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIStyling
import TUIView

// MARK: - Configuration

/// The resolved configuration of a matched transition source: what its
/// configuration modifiers set. Mirrors SwiftUI's
/// `_ResolvedMatchedTransitionSourceConfiguration`, which a
/// ``MatchedTransitionSourceConfiguration`` updates.
public struct _ResolvedMatchedTransitionSourceConfiguration: Sendable {
    /// The colour drawn behind the source's content as the zoom grows from
    /// it, or `nil` for none.
    var background: Color?

    /// The shape the zoom's rectangle is cut to as it grows from the source,
    /// or `nil` for the rectangle itself.
    var clipShape: RoundedRectangle?

    /// The shadow the zoom's rectangle casts as it grows from the source, or
    /// `nil` for none.
    var shadow: _MatchedTransitionSourceShadow?
}

/// A matched transition source's shadow, as ``MatchedTransitionSourceConfiguration/shadow(color:radius:x:y:)``
/// states it: a drop shadow, in cells.
struct _MatchedTransitionSourceShadow: Sendable {
    let color: Color
    let radius: Int
    let x: Int
    let y: Int

    /// The shadow at `strength` of its colour's alpha: what the zoom draws
    /// part of the way to the screen, which has none.
    func style(at strength: Double) -> ShadowStyle {
        .drop(color: color.opacity(strength), radius: radius, x: x, y: y)
    }
}

/// A configuration that defines the appearance of a matched transition
/// source.
///
/// Made by the configuration modifiers, starting from the
/// ``EmptyMatchedTransitionSourceConfiguration`` the closure of
/// ``View/matchedTransitionSource(id:in:configuration:)`` is handed:
/// ``background(_:)``, ``clipShape(_:)`` and ``shadow(color:radius:x:y:)``.
/// What they set is the zoom's rectangle's as it grows from the source; the
/// clip's radius and the shadow go from the source's to nothing as the
/// rectangle reaches the stack, the screen having neither, as SwiftUI
/// interpolates the source's appearance into the destination's.
public protocol MatchedTransitionSourceConfiguration: Sendable {
    /// Writes what this configuration sets into `configuration`. Not to be
    /// implemented by hand: configurations are made by the modifiers.
    func _update(configuration: inout _ResolvedMatchedTransitionSourceConfiguration)
}

/// An unstyled matched transition source configuration.
public struct EmptyMatchedTransitionSourceConfiguration: MatchedTransitionSourceConfiguration {
    /// Sets nothing.
    public func _update(configuration: inout _ResolvedMatchedTransitionSourceConfiguration) {}
}

/// A configuration with a background colour set over `base`.
struct _BackgroundMatchedTransitionSourceConfiguration<Base: MatchedTransitionSourceConfiguration>:
    MatchedTransitionSourceConfiguration
{
    let base: Base
    let color: Color

    func _update(configuration: inout _ResolvedMatchedTransitionSourceConfiguration) {
        base._update(configuration: &configuration)
        configuration.background = color
    }
}

/// A configuration with a clip shape set over `base`.
struct _ClipShapeMatchedTransitionSourceConfiguration<Base: MatchedTransitionSourceConfiguration>:
    MatchedTransitionSourceConfiguration
{
    let base: Base
    let shape: RoundedRectangle

    func _update(configuration: inout _ResolvedMatchedTransitionSourceConfiguration) {
        base._update(configuration: &configuration)
        configuration.clipShape = shape
    }
}

/// A configuration with a shadow set over `base`.
struct _ShadowMatchedTransitionSourceConfiguration<Base: MatchedTransitionSourceConfiguration>:
    MatchedTransitionSourceConfiguration
{
    let base: Base
    let shadow: _MatchedTransitionSourceShadow

    func _update(configuration: inout _ResolvedMatchedTransitionSourceConfiguration) {
        base._update(configuration: &configuration)
        configuration.shadow = shadow
    }
}

extension MatchedTransitionSourceConfiguration {
    /// Applies the specified shape as to the matched transition source,
    /// clipping its content.
    ///
    /// The zoom's rectangle is cut to the shape as it grows from the source —
    /// a cell kept where the shape covers at least half of it, as
    /// ``View/clipShape(_:style:)`` keeps one — the screen it covers showing
    /// in the corners cut away. The radius is the source's at the start, and
    /// shrinks to nothing as the rectangle reaches the stack. In square units,
    /// as every shape's are: a radius of 2 is two columns, and a row's worth
    /// of the cell aspect down (``EnvironmentValues/imageCellAspect``).
    ///
    /// - Parameter shape: The shape to use as a mask.
    /// - Returns: The configuration, with the clip shape set.
    public func clipShape(_ shape: RoundedRectangle) -> some MatchedTransitionSourceConfiguration {
        _ClipShapeMatchedTransitionSourceConfiguration(base: self, shape: shape)
    }

    /// Applies the specified shadow effect to the matched transition source.
    ///
    /// The zoom's rectangle — its clip shape, where it has one — casts a drop
    /// shadow onto the screen it grows over, in whole cells as
    /// ``View/shadow(color:radius:x:y:)`` casts one (`Deliberate deviations
    /// from SwiftUI.md`, C10): moved `x` columns and `y` rows, falling off
    /// across `radius` cells. It is at the colour's alpha at the start, and
    /// fades to nothing as the rectangle reaches the stack. A shadow past the
    /// stack's edge is cut there.
    ///
    /// - Parameters:
    ///   - color: The shadow's color: black at a third by default, as in
    ///     SwiftUI.
    ///   - radius: How many cells the shadow's alpha falls off across beyond
    ///     the rectangle.
    ///   - x: How many columns right the shadow is drawn (negative: left).
    ///   - y: How many rows down the shadow is drawn (negative: up).
    /// - Returns: The configuration, with the shadow set.
    public func shadow(
        color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33), radius: Int, x: Int = 0, y: Int = 0
    ) -> some MatchedTransitionSourceConfiguration {
        _ShadowMatchedTransitionSourceConfiguration(
            base: self, shadow: _MatchedTransitionSourceShadow(color: color, radius: max(0, radius), x: x, y: y))
    }

    /// Specifies a color that will be drawn behind the content within the
    /// matched transition source.
    ///
    /// During a zoom transition, the background color fills the interpolated
    /// shape as it grows from the matched transition source: here, the cells
    /// of the revealed rectangle that the screen's own content leaves without a
    /// background of their own.
    ///
    /// - Parameter style: The color to apply behind the content within the
    ///   matched transition source.
    /// - Returns: The configuration, with the background set.
    public func background(_ style: Color) -> some MatchedTransitionSourceConfiguration {
        _BackgroundMatchedTransitionSourceConfiguration(base: self, color: style)
    }
}

// MARK: - The Modifiers

extension View {
    /// Identifies this view as the source of a navigation transition, such as
    /// a zoom transition.
    ///
    /// - Parameters:
    ///   - id: The identifier, often derived from the identifier of the data
    ///     being displayed by the view.
    ///   - namespace: The namespace in which defines the `id`. New namespaces
    ///     are created by adding an ``Namespace`` variable to a ``View`` type
    ///     and reading its value in the view's body method.
    /// - Returns: A view that a zoom transition with the same `id` and
    ///   `namespace` grows from.
    public func matchedTransitionSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        _MatchedTransitionSourceView(
            key: MatchedTransitionSourceID.key(id, in: namespace),
            configuration: _ResolvedMatchedTransitionSourceConfiguration(), content: self)
    }

    /// Identifies this view as the source of a navigation transition, such as
    /// a zoom transition.
    ///
    /// The appearance of the source can be configured using the
    /// `configuration` trailing closure. Any modifiers applied will be
    /// smoothly interpolated when a zoom transition originates from this
    /// matched transition source.
    ///
    /// ```swift
    /// MyView()
    ///     .matchedTransitionSource(id: someID, in: someNamespace) { source in
    ///         source
    ///             .background(.blue)
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - id: The identifier, often derived from the identifier of the data
    ///     being displayed by the view.
    ///   - namespace: The namespace in which defines the `id`. New namespaces
    ///     are created by adding an ``Namespace`` variable to a ``View`` type
    ///     and reading its value in the view's body method.
    ///   - configuration: A closure that you can use to apply styling to the
    ///     source.
    /// - Returns: A view that a zoom transition with the same `id` and
    ///   `namespace` grows from.
    public func matchedTransitionSource(
        id: some Hashable, in namespace: Namespace.ID,
        configuration: (EmptyMatchedTransitionSourceConfiguration) -> some MatchedTransitionSourceConfiguration
    ) -> some View {
        var resolved = _ResolvedMatchedTransitionSourceConfiguration()
        configuration(EmptyMatchedTransitionSourceConfiguration())._update(configuration: &resolved)
        return _MatchedTransitionSourceView(
            key: MatchedTransitionSourceID.key(id, in: namespace), configuration: resolved, content: self)
    }
}

/// A transition source's id, wrapped, so that a source and a matched geometry
/// effect given the same id in the same namespace stay two groups, as they
/// are two systems in SwiftUI.
struct MatchedTransitionSourceID: Hashable {
    let id: AnyHashable

    /// The group a transition source with `id` in `namespace` joins.
    static func key(_ id: some Hashable, in namespace: Namespace.ID) -> MatchedGeometryKey {
        MatchedGeometryKey(namespace: namespace, id: AnyHashable(Self(id: AnyHashable(id))))
    }
}

// MARK: - Core

/// Draws its content unchanged, and joins the matched geometry registry as the
/// source of its group, so the scene root finds where it is
/// (``MatchedGeometryRegistry``) and a ``NavigationStack`` zooming from it
/// knows its frame. Its configuration goes to the enclosing stack.
private struct _MatchedTransitionSourceView<Content: View>: View, Renderable, Layoutable {
    let key: MatchedGeometryKey
    let configuration: _ResolvedMatchedTransitionSourceConfiguration
    let content: Content

    var body: Never {
        fatalError("_MatchedTransitionSourceView renders via Renderable")
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard !context.isMeasuring, let coordinator = context.geometryCoordinator,
            // Before the content, for the ordinal the marker's id is. Only
            // found, as `onGeometryChange` is: nothing is drawn from where it
            // is predicted to be — a zoom starts from where the root found it
            // in a frame it was on screen — so it keeps no carried origin in
            // force.
            let ask = context.makeGeometryAsk(role: .reporter)
        else { return TUIView.renderToBuffer(content, context: context) }
        // Joined to its group on every frame it draws: work a served buffer
        // cannot do.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        ask.want(.global)
        var buffer = TUIView.renderToBuffer(content, context: context)
        // A member of its own, beside an effect on the same view
        // (``MatchedMemberID``).
        var registration = MatchedRegistration(
            identity: context.identity, owner: ObjectIdentifier(Self.self), marker: ask.id, isSource: true,
            anchor: .center, size: buffer.cellSize,
            state: MatchedMemberState(key: key, followed: nil, epoch: 0, offsets: .zero))
        registration.expectedOrigin = ask.expectedOrigin(in: .global)
        ask.finishRecording(size: buffer.cellSize)
        if coordinator.register(ask) { buffer.hitTestRegions.append(.geometryMarker(ask.id)) }
        coordinator.matchedGeometry.register(registration, in: key)
        context.environment.navigationCoordinator?.noteTransitionSource(key, configuration: configuration)
        return buffer
    }
}

/// Draws its content unchanged, at its own identity.
extension _MatchedTransitionSourceView: SingleContentWrapper {
    var wrappedContent: Content { content }
}
