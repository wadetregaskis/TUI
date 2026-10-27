//  🖥️ TUI — A Terminal UI framework for Swift
//  MouseEventDispatcher+ClickRecognizers.swift
//
//  The controls that act on a click, filed so their press is a recognizer:
//  possible while the button is down, recognized by a release over the
//  control, failed by one off it, and cancelled by a gesture ranked ahead
//  that recognizes (decisions B89).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

// MARK: - Click recognizer

/// What a control that acts on its click files beside its region, so its press
/// is a recognizer, as a plain-style SwiftUI button's is on macOS.
///
/// **The contract a filing states:** the control's press shows only that it is
/// pressed (or nothing), and its release acts — whatever the release's
/// position. The dispatcher decides where the release counts:
///
/// - **Over the control** (any region the control filed under the id, in the
///   frame on screen) the release is delivered, and the control acts:
///   recognized.
/// - **Off it**, the release is not delivered: ``cancel`` runs instead, and
///   nothing acts — failed, as macOS's plain button fails a release off it.
/// - **Cancelled**: a gesture ranked ahead of it recognized (a
///   `highPriorityGesture` drag that moved), or the arena it was in was given
///   up. ``cancel`` runs, and nothing of the press reaches the control again.
///
/// While the button is down, each drag is delivered as before, and
/// ``track`` hears whether the pointer is over the control, so a pressed look
/// can follow it off and back, as macOS's does.
///
/// In a gesture arena (``GestureArena``), a filed control is given its press
/// at once, even behind a gesture that has not decided: it draws pressed, and
/// holds back what is ranked after it, as an undecided gesture does. Its
/// release waits until everything ahead of it has given up. A control that
/// files nothing is given its press only then, as before (decisions B89).
package struct ClickRecognizer {
    /// Undoes what the press showed, acting on nothing: the press failed or
    /// was cancelled.
    package let cancel: @MainActor () -> Void

    /// Told, at each drag of the press, whether the pointer is over the
    /// control — or `nil`, for a control that draws no pressed look.
    package let track: (@MainActor (_ isOver: Bool) -> Void)?

    package init(cancel: @escaping @MainActor () -> Void, track: (@MainActor (_ isOver: Bool) -> Void)? = nil) {
        self.cancel = cancel
        self.track = track
    }

    /// A control with no pressed look: a failed or cancelled press leaves
    /// nothing to undo.
    package static let plain = Self(cancel: {})
}

extension MouseEventDispatcher {
    /// Files `recognizer` for the region whose handler `id` names, for the
    /// frame.
    ///
    /// Recorded for a value memo, as the handler registration beside it is, so
    /// a served subtree files it again.
    @MainActor
    package func fileClickRecognizer(
        _ recognizer: ClickRecognizer, for id: HitTestRegion.HandlerID, in context: RenderContext
    ) {
        guard !context.isMeasuring else { return }
        clickRecognizers[id] = recognizer
        context.environment.volatileReadTracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return }
        let token = context.environment.keyChannelToken
        journal.append(
            EffectJournal.Entry(kind: Self.clickRecognizerKind, channelToken: token) { replay in
                replay.environment.mouseEventDispatcher?.clickRecognizers[id] = recognizer
            })
    }

    /// The journal kind of a click recognizer's filing.
    static let clickRecognizerKind = EffectJournal.Kind("clickRecognizer")

    /// Whether `event`'s position is over a region the frame on screen filed
    /// under `id`.
    func isOver(_ event: MouseEvent, _ id: HitTestRegion.HandlerID) -> Bool {
        regions.contains { $0.handlerID == id && !$0.isGeometryMarker && $0.contains(x: event.x, y: event.y) }
    }

    /// Delivers a drag or release of a press a click recognizer took: a drag
    /// goes to the control, which hears whether it is over itself; a release
    /// over it goes to it, and one off it cancels it instead.
    @MainActor
    func routeRecognizedClick(_ event: MouseEvent, to capture: PressCapture, recognizer: ClickRecognizer) {
        let over = capture.handlerID.map { isOver(event, $0) } ?? false
        switch event.phase {
        case .released:
            if over { deliver(event, to: capture) } else { recognizer.cancel() }
        case .dragged:
            deliver(event, to: capture)
            recognizer.track?(over)
        default:
            deliver(event, to: capture)
        }
    }

    /// Hands `event` to the handler that took its press, in that press's
    /// region's coordinates.
    func deliver(_ event: MouseEvent, to capture: PressCapture) {
        _ = capture.handler(localize(event, byOffsetX: capture.regionOffsetX, offsetY: capture.regionOffsetY))
    }

    /// Gives up the press a click recognizer took, if its capture is still
    /// the button's: the recognizer is cancelled, and the rest of the press
    /// reaches no one through it.
    @MainActor
    func cancelRecognizedClick(_ id: HitTestRegion.HandlerID) {
        guard let capture = pressedHandlers[.left], capture.handlerID == id else { return }
        pressedHandlers[.left] = nil
        capture.recognizer?.cancel()
    }
}
