//  🖥️ TUI — A Terminal UI framework for Swift
//  PhaseAnimator.swift
//
//  `PhaseAnimator` and the two `phaseAnimator` modifiers, live (refusal review
//  O2, decisions A37): the phase is state, and each step to the next is a
//  `withAnimation` with that phase's animation, the step after it starting
//  when it completes. What SwiftUI does was measured, not taken from its
//  documentation, which describes one step per trigger change
//  (`Tools/SwiftUIProbes/Animation curves, springs and keyframes/p9.swift`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Phase Animator

/// A container that animates its content by automatically cycling through a
/// collection of phases that you provide, each defining a discrete step within
/// an animation — mirrors SwiftUI's `PhaseAnimator`.
///
/// The content is drawn at the first phase. Then, as measured on SwiftUI:
///
/// - **With a trigger**, each change of the trigger runs through the phases —
///   the second, the third and on to the last — and back to the first, where
///   it rests. A change during a run lets the step under way finish, then runs
///   through them again from the second.
/// - **With none**, it runs through them from the moment it appears, round and
///   round, for as long as it is drawn.
///
/// Each step is animated with what `animation` returns for the phase it
/// steps INTO, and the next step starts when that animation is logically
/// complete. A step whose animation is `nil` is taken at once; a cycle of the
/// trigger-less form in which no step was animated stops at the first phase,
/// as SwiftUI's does, rather than spinning. A trigger-less animator of one
/// phase rests at it once it appears, as SwiftUI's does, and never asks for
/// its animation.
///
/// A step lasts its animation's ``Animation/logicalCompletionDuration`` on the
/// frame clock whether or not anything in the content animates: a `Text`
/// whose string is the phase steps at the animation's pace, as a fade does.
/// This is a deliberate deviation from SwiftUI, which stalls such an animator
/// after its first step (measured on macOS 15.8, probe p12): "Whether or not
/// there's an actual effect shown for the animation, it should run at the
/// same speed. It definitely shouldn't freeze." (the owner, 2026-11-23,
/// H66-PACE (a); deliberate deviations A11). A SwiftUI program's animator
/// cycles here instead of freezing.
///
/// While it runs the content is drawn every frame its animations draw, as for
/// any running animation; content that does not animate is drawn once a step.
public struct PhaseAnimator<Phase: Equatable, Content: View> {
    private let phases: [Phase]
    private let trigger: AnyEquatableBox?
    private let content: (Phase) -> Content
    private let animation: (Phase) -> Animation?

    /// The phase drawn: an index into ``phases``.
    @State private var index = 0

    /// The run's bookkeeping, which no frame draws.
    @State private var run = PhaseRun()

    /// Cycles through a sequence of phases in response to changes in a
    /// specified value, animating updates to a view on each phase change.
    ///
    /// - Parameters:
    ///   - phases: The phases to cycle through, in order. Not empty.
    ///   - trigger: A value whose changes run the animator through its phases.
    ///   - content: The view at a phase.
    ///   - animation: The animation into a phase; `nil` steps into it at once.
    public init(
        _ phases: some Sequence<Phase>, trigger: some Equatable, @ViewBuilder content: @escaping (Phase) -> Content,
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) {
        self.phases = Array(phases)
        self.trigger = AnyEquatableBox(trigger)
        self.content = content
        self.animation = animation
    }

    /// Cycles through a sequence of phases continuously, animating updates to
    /// a view on each phase change.
    ///
    /// - Parameters:
    ///   - phases: The phases to cycle through, in order. Not empty.
    ///   - content: The view at a phase.
    ///   - animation: The animation into a phase; `nil` steps into it at once.
    public init(
        _ phases: some Sequence<Phase>, @ViewBuilder content: @escaping (Phase) -> Content,
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) {
        self.phases = Array(phases)
        self.trigger = nil
        self.content = content
        self.animation = animation
    }

    /// The content and behavior of this view.
    @MainActor @ViewBuilder public var body: some View {
        // An empty sequence has no phase to draw: SwiftUI warns and draws a
        // warning in its place; here it draws nothing.
        if !phases.isEmpty {
            content(phases[min(index, phases.count - 1)])
                .modifier(PhaseStepPacing(run: run))
                .onAppear {
                    run.isShown = true
                    if trigger == nil { advance() }
                }
                .onDisappear { run.isShown = false }
                .onChange(of: trigger) { beginRun() }
        }
    }

    /// A trigger change: a run through the phases, from the second to the
    /// first. Under way already, the step being taken finishes first.
    @MainActor private func beginRun() {
        run.queue = Array(1..<phases.count) + [0]
        if !run.isStepping { advance() }
    }

    /// Takes the next step: the next in the run's queue, or — trigger-less —
    /// the next phase round. Nothing, with no step to take.
    @MainActor private func advance() {
        guard run.isShown, !phases.isEmpty else { return }
        let next: Int
        if !run.queue.isEmpty {
            next = run.queue.removeFirst()
        } else if trigger == nil, phases.count > 1 {
            next = (index + 1) % phases.count
        } else {
            // A run's end, or one phase with nowhere to step: at rest. One
            // phase stepping into itself still claimed its completion (a
            // state write is not compared with what it replaces), which fired
            // at the end of every frame and asked for the next.
            return
        }
        let stepAnimation = animation(phases[next])
        if stepAnimation != nil { run.animatedThisCycle = true }
        run.unplacedPace = stepAnimation
        run.paceDeadline = nil
        run.isStepping = true
        run.isInsideStep = true
        defer { run.isInsideStep = false }
        let run = run
        let advance = advance
        let isCycling = trigger == nil
        withAnimation(stepAnimation, completionCriteria: .logicallyComplete) {
            index = next
        } completion: {
            run.isStepping = false
            let onward = {
                if next == 0, isCycling {
                    // Round once with nothing animated: rest, as SwiftUI does.
                    guard run.animatedThisCycle else { return }
                    run.animatedThisCycle = false
                }
                advance()
            }
            // Fired by the frame that finished the step, the next step starts
            // there. Fired inside this very call — a step that changed nothing,
            // so nothing waits on it — it waits for the call to return, or the
            // next step would be taken inside this one, and the next inside
            // that.
            if run.isInsideStep {
                Task { @MainActor in onward() }
            } else {
                onward()
            }
        }
    }
}
extension PhaseAnimator: View {}

/// A phase animator's run, kept across its body's evaluations.
@MainActor
private final class PhaseRun {
    nonisolated init() {}

    /// The phases still to step into, in order, for a trigger's run.
    var queue: [Int] = []
    /// Whether a step's animation is under way.
    var isStepping = false
    /// Whether a step is being started: a completion fired meanwhile was
    /// fired by the step itself.
    var isInsideStep = false
    /// Whether this cycle round has animated a step: a trigger-less animator
    /// that went round without one stops at the first phase.
    var animatedThisCycle = false
    /// Whether the animator is drawn: one that is not steps no further.
    var isShown = false
    /// The animation of the step just taken, until the frame that draws it
    /// times the step by it (``PhaseStepPacing``).
    var unplacedPace: Animation?
    /// When that step is logically complete, on the frame clock: the wake the
    /// frames before it ask for. `nil` once reached, or for a step that never
    /// completes.
    var paceDeadline: Int64?
}

/// Times each step of a ``PhaseAnimator`` by its animation, whether or not
/// anything in the content animated (H66-PACE (a), deliberate deviations A11).
///
/// A step's completion fires when the animations the frame drawing it started
/// are logically complete, and at the end of that frame if it started none
/// (`AnimationCompletionTracker`). A `Text` whose string is the phase starts
/// none, so the next step was drawn on the next frame: sixty steps a second,
/// and the app drew at its full rate for as long as the animator was on
/// screen. This reports the step's animation as started by the frame that
/// draws it, as a content dissolve or a scroll glide reports its own, so the
/// completion waits for the animation's logical completion; and it asks for a
/// frame at that instant, as nothing else may. Content that does animate
/// started the same animation in the same frame, so its pace is unchanged.
private struct PhaseStepPacing: BufferModifier {
    let run: PhaseRun

    func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        guard !context.isMeasuring else { return buffer }
        let now = context.environment.frameNowNanos
        if let pace = run.unplacedPace {
            run.unplacedPace = nil
            context.stateStorage?.animationCompletions.noteStarted(pace, at: now, key: nil)
            // A repeating animation never completes logically: no wake, as
            // its completion never fires.
            run.paceDeadline = pace.logicalCompletionDuration.flatMap {
                $0.isFinite ? AnimationClock.deadline($0, after: now, rounding: .up) : nil
            }
        }
        if let deadline = run.paceDeadline {
            if now < deadline {
                // Asked again by every frame before it, as a wake must be.
                context.requestWake(token: "phase-step-\(context.identity.path)", atNanos: deadline)
            } else {
                run.paceDeadline = nil
            }
        }
        return buffer
    }
}

// MARK: - Modifiers

extension View {
    /// Animates effects that you apply to a view over a sequence of phases
    /// that change based on a trigger — mirrors SwiftUI's
    /// `phaseAnimator(_:trigger:content:animation:)`.
    ///
    /// Each change of `trigger` runs through the phases and back to the
    /// first, as ``PhaseAnimator`` describes.
    ///
    /// - Parameters:
    ///   - phases: The phases to cycle through, in order. Not empty.
    ///   - trigger: A value whose changes run the animator through its phases.
    ///   - content: This view, as a placeholder, and the phase: the view at
    ///     that phase.
    ///   - animation: The animation into a phase; `nil` steps into it at once.
    /// - Returns: This view, animated through the phases.
    nonisolated public func phaseAnimator<Phase: Equatable, Result: View>(
        _ phases: some Sequence<Phase>, trigger: some Equatable,
        @ViewBuilder content: @escaping (PlaceholderContentView<Self>, Phase) -> Result,
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) -> some View {
        let placeholder = PlaceholderContentView<Self>(source: PlaceholderSource(view: self))
        return PhaseAnimator(phases, trigger: trigger, content: { content(placeholder, $0) }, animation: animation)
    }

    /// Animates effects that you apply to a view over a sequence of phases
    /// that change continuously — mirrors SwiftUI's
    /// `phaseAnimator(_:content:animation:)`.
    ///
    /// - Parameters:
    ///   - phases: The phases to cycle through, in order. Not empty.
    ///   - content: This view, as a placeholder, and the phase: the view at
    ///     that phase.
    ///   - animation: The animation into a phase; `nil` steps into it at once.
    /// - Returns: This view, animated through the phases, round and round.
    nonisolated public func phaseAnimator<Phase: Equatable, Result: View>(
        _ phases: some Sequence<Phase>,
        @ViewBuilder content: @escaping (PlaceholderContentView<Self>, Phase) -> Result,
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) -> some View {
        let placeholder = PlaceholderContentView<Self>(source: PlaceholderSource(view: self))
        return PhaseAnimator(phases, content: { content(placeholder, $0) }, animation: animation)
    }
}
