//  🖥️ TUI — A Terminal UI framework for Swift
//  SensoryFeedbackModifier.swift
//
//  SwiftUI's `sensoryFeedback` modifiers: the terminal's bell when a trigger
//  changes, for the kinds a terminal can play.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Sensory Feedback Modifier

/// The content, ringing the terminal's bell when `trigger` changes and
/// `feedback` answers a kind for the change.
///
/// Composed of `onChange(of:)`, which compares the trigger frame to frame,
/// and `\.ringBell`, the bell TUI's own controls ring: so a change rings once,
/// with the frame that sees it, and never on the first frame.
struct _SensoryFeedback<Content: View, T: Equatable> {
    let content: Content
    let trigger: T
    let feedback: (_ oldValue: T, _ newValue: T) -> SensoryFeedback?

    @Environment(\.ringBell) private var ringBell

    @MainActor var body: some View {
        // Every kind there is rings the bell: those a terminal cannot play
        // do not compile (SensoryFeedback.swift).
        content.onChange(of: trigger) { [ringBell, feedback] oldValue, newValue in
            if feedback(oldValue, newValue) != nil { ringBell() }
        }
    }
}
extension _SensoryFeedback: View {}

extension View {
    /// Plays the given feedback when the trigger changes: on a terminal, rings
    /// its bell.
    ///
    /// ``SensoryFeedback/error`` and ``SensoryFeedback/warning`` are the kinds
    /// a terminal can play, both on its bell; the rest do not compile. The bell
    /// rings with the frame that sees the trigger changed, once however many
    /// rang it, and never for the trigger's first value.
    ///
    /// ```swift
    /// TextField("Port", text: $port)
    ///     .sensoryFeedback(.error, trigger: rejectedCount)
    /// ```
    ///
    /// - Parameters:
    ///   - feedback: The kind of feedback to play.
    ///   - trigger: A value to watch; each change plays the feedback.
    nonisolated public func sensoryFeedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View {
        _SensoryFeedback(content: self, trigger: trigger) { _, _ in feedback }
    }

    /// Plays the given feedback when the trigger changes and `condition`
    /// returns `true` for the change: on a terminal, rings its bell.
    ///
    /// ```swift
    /// Stepper("Retries", value: $retries, in: 0...5)
    ///     .sensoryFeedback(.warning, trigger: retries) { oldValue, newValue in
    ///         newValue == 5 && oldValue < 5
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - feedback: The kind of feedback to play.
    ///   - trigger: A value to watch.
    ///   - condition: Given the old and new values, whether to play it.
    nonisolated public func sensoryFeedback<T: Equatable>(
        _ feedback: SensoryFeedback,
        trigger: T,
        condition: @escaping (_ oldValue: T, _ newValue: T) -> Bool
    ) -> some View {
        _SensoryFeedback(content: self, trigger: trigger) { oldValue, newValue in
            condition(oldValue, newValue) ? feedback : nil
        }
    }

    /// Plays the feedback the closure returns when the trigger changes, and
    /// none when it returns `nil`: on a terminal, rings its bell.
    ///
    /// ```swift
    /// Text(status.title)
    ///     .sensoryFeedback(trigger: status) { _, newValue in
    ///         newValue == .failed ? .error : nil
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - trigger: A value to watch.
    ///   - feedback: Given the old and new values, the feedback to play, or
    ///     `nil` for none.
    nonisolated public func sensoryFeedback<T: Equatable>(
        trigger: T,
        _ feedback: @escaping (_ oldValue: T, _ newValue: T) -> SensoryFeedback?
    ) -> some View {
        _SensoryFeedback(content: self, trigger: trigger, feedback: feedback)
    }

    /// Plays the feedback the closure returns when the trigger changes, and
    /// none when it returns `nil`: on a terminal, rings its bell.
    ///
    /// - Parameters:
    ///   - trigger: A value to watch.
    ///   - feedback: The feedback to play, or `nil` for none.
    nonisolated public func sensoryFeedback<T: Equatable>(
        trigger: T,
        _ feedback: @escaping () -> SensoryFeedback?
    ) -> some View {
        sensoryFeedback(trigger: trigger) { _, _ in feedback() }
    }
}
