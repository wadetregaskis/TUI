//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyframeAnimator.swift
//
//  `KeyframeAnimator` and the two `keyframeAnimator` modifiers, live (refusal
//  review O2): a keyframe timeline played on the frame clock, the content
//  drawn at the timeline's value each frame while it plays. What SwiftUI does
//  was measured (`Tools/SwiftUIProbes/Animation curves, springs and
//  keyframes/p9.swift`) where its documentation says otherwise.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

// MARK: - Keyframe Animator

/// A container that animates its content with keyframes — mirrors SwiftUI's
/// `KeyframeAnimator`.
///
/// The content is drawn at the value the keyframes give it, every frame while
/// they play. As measured on SwiftUI:
///
/// - **With a trigger**, it rests at `initialValue` until the trigger changes;
///   then `keyframes` is asked for a timeline from `initialValue`, which plays
///   to its end, where the animator rests. Each later change plays it again
///   from `initialValue` — SwiftUI's documentation says from the end value,
///   but it starts again — except a change while it plays, which asks for a
///   timeline from the value it has reached, and plays that instead.
/// - **Repeating**, it plays from `initialValue` round and round while it is
///   drawn; not repeating, it draws the value at the start of the timeline and
///   never plays.
///
/// A timeline started part-way through another starts at rest: TUI's
/// keyframes take no initial velocity, so a spring or cubic keyframe does not
/// carry on the velocity of the one it replaced, as SwiftUI's does.
public struct KeyframeAnimator<Value, KeyframePath: Keyframes, Content: View>
where Value == KeyframePath.Value {
    private let initialValue: Value
    private let trigger: AnyEquatableBox?
    private let repeating: Bool
    private let content: (Value) -> Content
    private let keyframes: (Value) -> KeyframePath

    /// Whether a timeline is playing: what keeps the frame clock running.
    @State private var isPlaying = false

    /// The playback, which no frame's value depends on but the clock's.
    @State private var playback = KeyframePlayback<Value>()

    /// Plays the given keyframes when the given trigger value changes,
    /// updating the view at each frame's value.
    ///
    /// - Parameters:
    ///   - initialValue: The value the animator rests at, and the keyframes
    ///     start from.
    ///   - trigger: A value whose changes play the keyframes.
    ///   - content: The view at a value.
    ///   - keyframes: The keyframes, from the value they start at.
    public init(
        initialValue: Value, trigger: some Equatable, @ViewBuilder content: @escaping (Value) -> Content,
        @KeyframesBuilder<Value> keyframes: @escaping (Value) -> KeyframePath
    ) {
        self.initialValue = initialValue
        self.trigger = AnyEquatableBox(trigger)
        self.repeating = false
        self.content = content
        self.keyframes = keyframes
    }

    /// Loops the given keyframes continuously, updating the view at each
    /// frame's value.
    ///
    /// - Parameters:
    ///   - initialValue: The value the keyframes start from.
    ///   - repeating: Whether the keyframes play round and round; `false` draws
    ///     the value at the start of the timeline.
    ///   - content: The view at a value.
    ///   - keyframes: The keyframes, from the value they start at.
    public init(
        initialValue: Value, repeating: Bool = true, @ViewBuilder content: @escaping (Value) -> Content,
        @KeyframesBuilder<Value> keyframes: @escaping (Value) -> KeyframePath
    ) {
        self.initialValue = initialValue
        self.trigger = nil
        self.repeating = repeating
        self.content = content
        self.keyframes = keyframes
    }

    /// The content and behavior of this view.
    @MainActor @ViewBuilder public var body: some View {
        TimelineView(.animation(paused: !isPlaying)) { context in
            content(value(at: context.date))
        }
        .onAppear {
            playback.isShown = true
            if trigger == nil, repeating { play(from: initialValue) }
        }
        .onDisappear {
            playback.isShown = false
            isPlaying = false
        }
        .onChange(of: trigger) {
            // Mid-play, from where it has got to; otherwise from the start.
            let isMidPlay = isPlaying && !playback.hasFinished
            play(from: isMidPlay ? playback.current ?? initialValue : initialValue)
        }
    }

    /// Starts a timeline from `start`, timed from the next frame drawn.
    @MainActor private func play(from start: Value) {
        playback.timeline = KeyframeTimeline(initialValue: start) { keyframes(start) }
        playback.startDate = nil
        playback.hasFinished = false
        isPlaying = true
    }

    /// The value at `date`: the playing timeline's, the rest value where none
    /// plays, or — repeating off — the value at the start of the timeline.
    @MainActor private func value(at date: Date) -> Value {
        guard isPlaying, let timeline = playback.timeline else {
            if trigger == nil, !repeating {
                let timeline = playback.timeline ?? KeyframeTimeline(initialValue: initialValue) { keyframes(initialValue) }
                playback.timeline = timeline
                return timeline.value(time: 0)
            }
            return playback.current ?? initialValue
        }
        // Timed from the first frame that draws it, on the frame clock this
        // date comes from.
        let start = playback.startDate ?? date
        playback.startDate = start
        let elapsed = max(0, date.timeIntervalSince(start))
        let duration = timeline.duration
        let value: Value
        if repeating {
            value = timeline.value(time: duration > 0 ? elapsed.truncatingRemainder(dividingBy: duration) : 0)
        } else if elapsed >= duration {
            value = timeline.value(time: duration)
            // Played out: rest at the end, and let the clock stop — after the
            // frame, since this is drawing it.
            if !playback.hasFinished {
                playback.hasFinished = true
                let isPlaying = $isPlaying
                // Unless a new play began meanwhile: a trigger that changed on
                // this frame restarted it (`hasFinished` false again), and
                // stopping the clock would leave it resting on the old end.
                Task { @MainActor [playback] in
                    guard playback.hasFinished else { return }
                    isPlaying.wrappedValue = false
                }
            }
        } else {
            value = timeline.value(time: elapsed)
        }
        playback.current = value
        return value
    }
}
extension KeyframeAnimator: View {}

/// A keyframe animator's playback, kept across its body's evaluations.
@MainActor
private final class KeyframePlayback<Value> {
    nonisolated init() {}

    /// The timeline playing, or last played.
    var timeline: KeyframeTimeline<Value>?
    /// When it started, on the frame clock: `nil` until a frame draws it.
    var startDate: Date?
    /// The value last drawn: where a timeline started part-way through starts
    /// from, and where a finished one rests.
    var current: Value?
    /// Whether the timeline has played out: the animator rests at its end,
    /// whether or not the clock has stopped yet.
    var hasFinished = false
    /// Whether the animator is drawn.
    var isShown = false
}

// MARK: - Modifiers

// SwiftUI's `content` closures here are `@Sendable`, and so nonisolated; a
// TUI view is made on the main actor, so these are `@MainActor @Sendable`.
// A closure written for SwiftUI's signature compiles against them unchanged.
extension View {
    /// Loops the given keyframes continuously, updating the view using the
    /// modifiers you apply in `content` — mirrors SwiftUI's
    /// `keyframeAnimator(initialValue:repeating:content:keyframes:)`.
    ///
    /// - Parameters:
    ///   - initialValue: The value the keyframes start from.
    ///   - repeating: Whether the keyframes play round and round; `false` draws
    ///     the value at the start of the timeline.
    ///   - content: This view, as a placeholder, and the value: the view at it.
    ///   - keyframes: The keyframes, from the value they start at.
    /// - Returns: This view, animated by the keyframes.
    @MainActor public func keyframeAnimator<Value, Result: View, Path: Keyframes<Value>>(
        initialValue: Value, repeating: Bool = true,
        @ViewBuilder content: @escaping @MainActor @Sendable (PlaceholderContentView<Self>, Value) -> Result,
        @KeyframesBuilder<Value> keyframes: @escaping (Value) -> Path
    ) -> some View {
        let placeholder = PlaceholderContentView<Self>(source: PlaceholderSource(view: self))
        return KeyframeAnimator(
            initialValue: initialValue, repeating: repeating, content: { content(placeholder, $0) },
            keyframes: keyframes)
    }

    /// Plays the given keyframes when the given trigger value changes,
    /// updating the view using the modifiers you apply in `content` — mirrors
    /// SwiftUI's `keyframeAnimator(initialValue:trigger:content:keyframes:)`.
    ///
    /// - Parameters:
    ///   - initialValue: The value the animator rests at, and the keyframes
    ///     start from.
    ///   - trigger: A value whose changes play the keyframes.
    ///   - content: This view, as a placeholder, and the value: the view at it.
    ///   - keyframes: The keyframes, from the value they start at.
    /// - Returns: This view, animated by the keyframes when `trigger` changes.
    @MainActor public func keyframeAnimator<Value, Result: View, Path: Keyframes<Value>>(
        initialValue: Value, trigger: some Equatable,
        @ViewBuilder content: @escaping @MainActor @Sendable (PlaceholderContentView<Self>, Value) -> Result,
        @KeyframesBuilder<Value> keyframes: @escaping (Value) -> Path
    ) -> some View {
        let placeholder = PlaceholderContentView<Self>(source: PlaceholderSource(view: self))
        return KeyframeAnimator(
            initialValue: initialValue, trigger: trigger, content: { content(placeholder, $0) },
            keyframes: keyframes)
    }
}
