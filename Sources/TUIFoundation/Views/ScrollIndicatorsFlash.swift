//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollIndicatorsFlash.swift
//
//  `scrollIndicatorsFlash(onAppear:)` and `scrollIndicatorsFlash(trigger:)`:
//  a brief highlight of the scroll indicators a scrollable draws, to draw the
//  eye to them (decisions B28).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

// MARK: - The request

/// What the `scrollIndicatorsFlash` modifiers above a scrollable ask of it:
/// whether it flashes when it first draws, and when a trigger last changed.
///
/// Equatable, so the render cache sees a trigger change where it is applied
/// and no buffer drawn before it is served under it.
package struct ScrollIndicatorsFlashRequest: Equatable, Sendable {
    /// Whether a scrollable flashes when it first draws —
    /// ``View/scrollIndicatorsFlash(onAppear:)``.
    package var onAppear = false

    /// When a ``View/scrollIndicatorsFlash(trigger:)`` value last changed, on
    /// the frame clock (`frameNowNanos`); `nil` when none has.
    package var triggeredAtNanos: Int64?

    package init() {}
}

private struct ScrollIndicatorsFlashKey: EnvironmentKey {
    static let defaultValue = ScrollIndicatorsFlashRequest()
}

extension EnvironmentValues {
    /// The flash the scrollables in this subtree are asked for. See
    /// ``View/scrollIndicatorsFlash(onAppear:)``.
    package var scrollIndicatorsFlash: ScrollIndicatorsFlashRequest {
        get { self[ScrollIndicatorsFlashKey.self] }
        set { self[ScrollIndicatorsFlashKey.self] = newValue }
    }
}

// MARK: - A scrollable's side

/// One scrollable's flash: when it first drew, and how far into a flash a
/// frame is. Kept on the scrollable's handler, which lives as long as it does.
///
/// A flash is half a second: ten steps of three 1/60 s ticks (50 ms, the
/// frame of every re-rendered animation, ``AnimationClock/standardFrameTicks``),
/// rising to its peak in two steps, holding it for four and fading over four.
/// It is drawn by re-rendering — a run would replay it from wherever its clock
/// stands, and a flash starts when it is asked for — so each step asks for the
/// frame of the next, and the frame after the last draws the indicators as
/// they were. A scrollable that is not flashing asks for nothing.
package struct ScrollIndicatorFlash: Sendable {
    /// When the scrollable first drew, on the frame clock: where a flash on
    /// appearing starts. `nil` before its first render pass.
    package private(set) var appearedAtNanos: Int64?

    package init() {}

    /// Records the scrollable's first render pass, at `nanos` on the frame
    /// clock. Later calls change nothing, so a caller that cannot tell its
    /// first frame may call it on every one.
    package mutating func noteAppearance(atNanos nanos: Int64) {
        if appearedAtNanos == nil { appearedAtNanos = nanos }
    }

    /// How strongly the indicators flash on this frame, from just above 0 to
    /// 1, or `nil` when they do not; a flashing frame asks for the frame of
    /// its next step.
    ///
    /// Asked only where indicators are drawn, and never while measuring. With
    /// no `scrollIndicatorsFlash` above, the whole cost is one environment
    /// read.
    @MainActor
    package func strength(context: RenderContext) -> Double? {
        guard !context.isMeasuring else { return nil }
        let request = context.environment.scrollIndicatorsFlash
        var start = request.triggeredAtNanos
        if request.onAppear, let appeared = appearedAtNanos {
            start = max(start ?? appeared, appeared)
        }
        guard let start else { return nil }
        // A render nothing follows on a timer — a snapshot, a frame dump —
        // draws no flash: it showed the first step, half lit, and never the
        // rest (`AnimationFrame.canAnimate`, whose rule is that changes snap
        // there). One read for both halves, as `AnimatableResolution` reads it.
        let frame = context.environment.animationFrame
        guard frame.canAnimate else { return nil }
        let elapsed = frame.nowNanos - start
        guard elapsed >= 0, elapsed < Self.stepNanos * Int64(Self.steps) else { return nil }
        let step = Int(elapsed / Self.stepNanos)
        context.requestWake(
            token: "scroll-indicators-flash-\(context.identity.path)",
            atNanos: start + Self.stepNanos * Int64(step + 1))
        return Self.strength(atStep: step)
    }

    /// The steps a flash takes.
    static let steps = 10

    /// One step: ``AnimationClock/standardFrameTicks`` ticks of 1/60 s.
    static var stepNanos: Int64 {
        AnimationClock.nanoseconds(atTick: Int64(AnimationClock.standardFrameTicks))
    }

    /// The strength at `step`: up in two steps, held, and down a fifth a step
    /// over the last four — ½, 1, 1, 1, 1, 1, ⅘, ⅗, ⅖, ⅕.
    static func strength(atStep step: Int) -> Double {
        min(1, Double(step + 1) / 2, Double(steps - step) / 5)
    }
}

// MARK: - Colours

extension ScrollbarColors {
    /// These colours part way through a flash: the thumb and the arrows
    /// `strength` of the way from where they rest to ``flashPeak(_:)``, each
    /// kept legible against the track. The track and the pointer's cell are
    /// left as they are.
    @MainActor
    package func flashing(_ strength: Double, in palette: any Palette) -> Self {
        let peak = Self.flashPeak(palette)
        func toward(_ color: Color) -> Color {
            Self.separated(
                Color.lerp(color, peak, phase: strength), in: palette, standingOffThePage: false)
        }
        return Self(thumb: toward(thumb), track: track, arrow: toward(arrow), hover: hover)
    }

    /// ``resting(in:)``, lit by a flash of `flash` when there is one.
    @MainActor
    package static func resting(in palette: any Palette, flash: Double?) -> Self {
        let colors = resting(in: palette)
        return flash.map { colors.flashing($0, in: palette) } ?? colors
    }

    /// Where a flash peaks: one step of ``Palette/hoveredForeground(_:)``
    /// past the far end of a focused bar's breath (``pulseLift(_:)``) — the
    /// focus identity's own colour, a step further from the page than the
    /// breath ever goes, so a focused bar's flash is told from its breathing.
    /// Where that step has no room (it lands within
    /// `ViewConstants.chromePulseFloor` of the breath's end), the breath's end
    /// itself, which an unfocused bar's resting grey still rises to.
    @MainActor
    static func flashPeak(_ palette: any Palette) -> Color {
        let breathEnd = pulseLift(palette)
        let further = separated(
            palette.hoveredForeground(breathEnd), in: palette, standingOffThePage: false)
        return ChromeTrack.renderedRatio(further, breathEnd) >= ViewConstants.chromePulseFloor
            ? further : breathEnd
    }
}

// MARK: - The modifiers

extension View {
    /// Flashes the scroll indicators of the scrollable views in this hierarchy
    /// when they first appear. Matches SwiftUI's
    /// `scrollIndicatorsFlash(onAppear:)`.
    ///
    /// ```swift
    /// ScrollView { … }
    ///     .scrollIndicatorsFlash(onAppear: true)
    /// ```
    ///
    /// A terminal's indicators are not overlays: a scrollable whose content
    /// overflows draws its bar, or its "N more" lines, on every frame. A flash
    /// here is a highlight instead: for half a second the bar's thumb and
    /// arrows, or the "N more" lines, brighten to a step past a focused bar's
    /// breath and fade back. As in SwiftUI, only the indicators that are drawn
    /// flash — none under `.scrollIndicators(.hidden)`, and none while the
    /// content fits. Reaches `ScrollView`, `List`, `Table` and `TextEditor`,
    /// but not the scrollers the framework puts around a tall menu, a sheet's
    /// or a framed container's content (the scrollables in that content do).
    ///
    /// - Parameter onAppear: Whether the indicators flash when each scrollable
    ///   in the hierarchy first draws.
    /// - Returns: A view whose scrollables flash their indicators on appearing.
    nonisolated public func scrollIndicatorsFlash(onAppear: Bool) -> some View {
        transformEnvironment(\.scrollIndicatorsFlash) { $0.onAppear = onAppear }
    }

    /// Flashes the scroll indicators of the scrollable views in this hierarchy
    /// when `value` changes. Matches SwiftUI's
    /// `scrollIndicatorsFlash(trigger:)`.
    ///
    /// ```swift
    /// ScrollView { … }
    ///     .scrollIndicatorsFlash(trigger: flashCount)
    /// ```
    ///
    /// The flash is the one ``scrollIndicatorsFlash(onAppear:)`` describes.
    /// The value the view first draws with flashes nothing; each change after
    /// it flashes every scrollable inside that draws an indicator.
    ///
    /// - Parameter value: The value whose change flashes the indicators.
    /// - Returns: A view whose scrollables flash their indicators when `value`
    ///   changes.
    nonisolated public func scrollIndicatorsFlash(trigger value: some Equatable) -> some View {
        _ScrollIndicatorsFlashCore(content: self, value: value)
    }
}

/// Watches a ``View/scrollIndicatorsFlash(trigger:)`` value and tells the
/// scrollables below when it last changed.
///
/// Its content renders at its own identity, so what it keeps between frames
/// sits in the reserved negative range of `StateStorage.StateKey`; two of them
/// at one identity (one modifier on another) are different generic types and
/// keep theirs apart by type, in one dictionary keyed by the type.
nonisolated struct _ScrollIndicatorsFlashCore<Content: View, Value: Equatable>: View {
    let content: Content
    let value: Value

    @MainActor var body: Never {
        fatalError("_ScrollIndicatorsFlashCore renders via Renderable")
    }

    private enum StateIndex {
        /// The last value seen and when it changed, by type. Computed: a
        /// generic type's nested enum cannot hold a stored static.
        static var trigger: Int { -150 }
    }

    /// The value last seen, and when it last changed on the frame clock.
    private struct Memory {
        var value: Value
        var changedAtNanos: Int64?
    }

    /// `context`, with this trigger's last change in the request the content
    /// reads. A render pass first compares the value with the one kept, and
    /// stamps a change with the frame's time; a measure reads what is kept.
    @MainActor private func flashing(_ context: RenderContext) -> RenderContext {
        guard let storage = context.stateStorage else { return context }
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.trigger)
        var memories: [ObjectIdentifier: Any] = storage.trackedValue(for: key) ?? [:]
        var memory = memories[ObjectIdentifier(Self.self)] as? Memory
        if !context.isMeasuring {
            storage.markActive(context.identity)
            if let kept = memory {
                if kept.value != value {
                    memory = Memory(value: value, changedAtNanos: context.environment.frameNowNanos)
                }
            } else {
                memory = Memory(value: value, changedAtNanos: nil)
            }
            memories[ObjectIdentifier(Self.self)] = memory
            storage.setTrackedValue(memories, for: key)
        }
        var request = context.environment.scrollIndicatorsFlash
        if let changed = memory?.changedAtNanos {
            request.triggeredAtNanos = max(request.triggeredAtNanos ?? changed, changed)
        }
        // A changed request reaches buffers drawn under the old one only if the
        // cache is told, as every environment modifier tells it; a flash is ink,
        // so the sizes below stay.
        if let cache = context.renderCache,
            case .changed = cache.noteAppliedEnvironment(
                request, identity: context.identity, keyPath: \EnvironmentValues.scrollIndicatorsFlash,
                depth: context.environmentApplicationDepth)
        {
            cache.clearAffected(by: context.identity, keepingSizes: true)
        }
        var inner = context
        inner.environment.scrollIndicatorsFlash = request
        inner.environmentApplicationDepth += 1
        return inner
    }
}

@MainActor extension _ScrollIndicatorsFlashCore: Renderable, Layoutable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIView.renderToBuffer(content, context: flashing(context))
    }

    /// Measures as its content: a flash changes no layout.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: flashing(context))
    }
}
