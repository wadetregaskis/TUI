//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SheetGrabber.swift
//
//  The grabber on a detented sheet's top edge: a split view's divider between
//  the sheet and the page, which the reader drags — or moves with the keys —
//  between the sheet's detents. See `presentationDragIndicator(_:)`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitStyling

// MARK: - Handler

/// The grabber's focus stop and drag target: the keys and the pointer step the
/// sheet between its detents at event time.
///
/// The same shape as a split view's ``_SplitPaneDividerHandler``, with
/// detents where the split has free sizes: Up and Down move the boundary, and
/// a press anchors a drag (``DividerDrag``) that moves it by the distance from
/// the press.
final class _SheetGrabberHandler: PersistedFocusable {
    var focusID: String

    /// ``PersistedFocusable``: answers to `focusID` from now on.
    func repoint(focusID: String) { self.focusID = focusID }

    var canBeFocused = true

    /// This frame's detents, which the keys and the pointer move the sheet
    /// between — refreshed every frame the grabber is drawn, and moved in
    /// place by a step, so a second key before the next frame steps on from
    /// the first.
    var detents: PresentedDetents?

    /// Whether the pointer is over the grabber's rule.
    var isHovered = false

    /// The pointer's gesture, from the sheet's height when it began.
    var drag = DividerDrag<Int>()

    /// When the wheel last moved the sheet, on the dispatcher's clock.
    var lastWheelStepNanos: UInt64?

    /// The least time between two detents the wheel moves the sheet by: a
    /// quarter of a second, fifteen frames at sixty a second. One turn of a
    /// wheel, or one flick of a trackpad, is a burst of ticks a few
    /// milliseconds apart, and one detent a tick swept through them all.
    static let wheelStepNanos: UInt64 = 250_000_000

    init(focusID: String) { self.focusID = focusID }

    /// Moves the sheet one detent for the wheel — `step` is +1 to grow, -1 to
    /// shrink — reporting whether the wheel's tick is taken.
    ///
    /// A tick within ``wheelStepNanos`` of the last step is taken and moves
    /// nothing: the rest of a burst is spent on the sheet, not passed to the
    /// content to scroll it as well — asked FIRST, so that holds for the
    /// burst whose first tick reached the largest detent, whose rest the
    /// sheet can no longer move by. Asked after, they reached the content
    /// and scrolled it by the rest of the burst.
    ///
    /// Any other tick the sheet cannot move by is declined, so it reaches
    /// what is behind it: the content's scroll view, under
    /// ``PresentationContentInteraction/resizes`` at the largest detent.
    func wheelStep(by step: Int, nowNanos: UInt64) -> Bool {
        if let last = lastWheelStepNanos, nowNanos >= last, nowNanos - last < Self.wheelStepNanos { return true }
        guard var detents, let index = detents.index, detents.stops.indices.contains(index + step) else {
            return false
        }
        lastWheelStepNanos = nowNanos
        detents.select(index + step)
        self.detents = detents
        return true
    }

    /// Up to the next larger detent, Down to the next smaller, Home and End to
    /// the ends, Return and Space to the next, round to the smallest after the
    /// largest. Shift adds nothing: there are only so many detents.
    ///
    /// A step past an end is taken and moves nothing, as a split view's
    /// divider takes an arrow it cannot move by: let through, Up from the
    /// grabber would carry the focus back into the sheet while the reader was
    /// still growing it.
    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        guard var detents, let index = detents.index, detents.stops.count > 1 else { return false }
        let last = detents.stops.count - 1
        let target: Int
        switch event.key {
        case .up: target = min(last, index + 1)
        case .down: target = max(0, index - 1)
        case .home: target = 0
        case .end: target = last
        case .enter, .space: target = index == last ? 0 : index + 1
        default: return false
        }
        detents.select(target)
        self.detents = detents
        return true
    }

    /// Moves the sheet to the detent nearest `height` rows — where the
    /// pointer has dragged its top edge to.
    func snap(toHeight height: Int) {
        guard var detents, let nearest = detents.nearestIndex(toHeight: height) else { return }
        detents.select(nearest)
        self.detents = detents
    }
}

// MARK: - Drawing and registering

/// Draws a sheet's grabber over its content and makes it live.
@MainActor
enum SheetGrabber {
    /// Whether a sheet with `detents` shows its grabber, `visibility` being
    /// what its content asked (``View/presentationDragIndicator(_:)``): unless
    /// hidden, wherever there are two heights to move between.
    static func isShown(_ detents: PresentedDetents?, visibility: Visibility?) -> Bool {
        guard let detents, visibility != .hidden else { return false }
        return detents.stops.count > 1
    }

    /// `sheet` with the grabber's rule on top of it, live: a focus stop in
    /// `sectionID` after everything in the sheet, and a drag target across the
    /// whole rule, snapping the sheet to its detents as it moves.
    ///
    /// The rule is the full width of the sheet, and the handle — the resize
    /// grip `.userResizable` draws (``BorderGrip``) — sits in its middle,
    /// lit by the pointer and breathing while the grabber holds the focus.
    ///
    /// - Parameters:
    ///   - sheet: The sheet's content, drawn one row short of its detent.
    ///   - detents: The sheet's detents this frame.
    ///   - sectionID: The sheet's focus section.
    ///   - focusIDIndex: The presenter's `StateStorage` index for the
    ///     grabber's focus id.
    ///   - handlerIndex: Its index for the grabber's handler.
    ///   - context: The presenter's context.
    static func attach(
        to sheet: FrameBuffer, detents: PresentedDetents, contentInteraction: PresentationContentInteraction,
        sectionID: String, focusIDIndex: Int, handlerIndex: Int, context: RenderContext
    ) -> FrameBuffer {
        guard !context.isMeasuring, let stateStorage = context.stateStorage else { return sheet }
        var registering = context
        registering.environment.activeFocusSectionID = sectionID
        let focusID = FocusRegistration.persistFocusID(
            context: registering, explicitFocusID: nil, defaultPrefix: "sheet-grabber",
            propertyIndex: focusIDIndex)
        let handler = stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: handlerIndex),
            default: _SheetGrabberHandler(focusID: focusID)
        ).value
        handler.detents = detents
        handler.canBeFocused = context.environment.isEnabled
        // After the sheet's content, which has rendered: the content takes the
        // focus the sheet opens with, and the grabber follows it in the ring,
        // as a split view's divider follows the pane before it.
        FocusRegistration.register(context: registering, handler: handler, focusID: focusID)
        let isFocused = context.indicatesFocus(FocusRegistration.isFocused(context: registering, focusID: focusID))

        let width = max(1, sheet.width)
        var rule = DividerRule.buffer(across: .vertical, length: width, colour: context.environment.palette.border)
        drawHandle(
            into: &rule, isFocused: isFocused, isHovered: handler.isHovered, environment: context.environment)
        if handler.canBeFocused { registerDrag(handler: handler, focusID: focusID, on: &rule, context: context) }
        rule.appendVertically(sheet)
        if handler.canBeFocused {
            registerWheel(handler: handler, interaction: contentInteraction, on: &rule, context: context)
        }
        return rule
    }

    /// What the wheel does over the whole sheet, by its content's
    /// ``PresentationContentInteraction``, through wheel-only regions
    /// (``MouseEventDispatcher/registerWheelHandler(in:_:)``) that take nothing
    /// else from the controls in it:
    ///
    /// - `.resizes`: a region IN FRONT of the content takes the wheel pulled
    ///   down first and grows the sheet, declining at the largest detent so
    ///   the content scrolls from there;
    /// - `.resizes` and `.scrolls`: a region BEHIND the content takes what the
    ///   content declines — a scroll view at its end declines the wheel, and
    ///   content that does not scroll declines all of it — growing the sheet
    ///   on the wheel pulled down and shrinking it on the wheel pushed up;
    /// - `.automatic`: neither; the wheel is the content's alone.
    private static func registerWheel(
        handler: _SheetGrabberHandler, interaction: PresentationContentInteraction, on sheet: inout FrameBuffer,
        context: RenderContext
    ) {
        guard interaction.kind != .automatic, let dispatcher = context.environment.mouseEventDispatcher else {
            return
        }
        dispatcher.requestFeature(.scrolling, in: context)
        func region(_ handlerID: HitTestRegion.HandlerID) -> HitTestRegion {
            HitTestRegion(offsetX: 0, offsetY: 0, width: sheet.width, height: sheet.height, handlerID: handlerID)
        }
        let behind = dispatcher.registerWheelHandler(in: context) { event in
            switch event.button {
            case .scrollDown: handler.wheelStep(by: 1, nowNanos: dispatcher.nowNanos())
            case .scrollUp: handler.wheelStep(by: -1, nowNanos: dispatcher.nowNanos())
            default: false
            }
        }
        sheet.hitTestRegions.insert(region(behind), at: 0)
        guard interaction.kind == .resizes else { return }
        let inFront = dispatcher.registerWheelHandler(in: context) { event in
            event.button == .scrollDown && handler.wheelStep(by: 1, nowNanos: dispatcher.nowNanos())
        }
        sheet.hitTestRegions.append(region(inFront))
    }

    /// The handle in the middle of the rule, in the grip's glyphs and ink.
    private static func drawHandle(
        into rule: inout FrameBuffer, isFocused: Bool, isHovered: Bool, environment: EnvironmentValues
    ) {
        // The rule is a run of `─` with no corners, so the whole of it is the
        // run the handle centres in.
        guard let span = BorderGrip.centredSpan(in: rule.width + 2, size: BorderGrip.Size.horizontal) else { return }
        let glyphs = BorderGrip.Glyphs.standingOut(from: "─")
        let ink = BorderGrip.ink(isFocused: isFocused, isHovered: isHovered, environment: environment)
        BorderGrip.mark(
            String(repeating: glyphs.horizontal, count: span.count), cells: span.count, into: &rule,
            at: (x: span.lowerBound - 1, y: 0), ink: ink)
    }

    /// The whole rule as the drag target: a press focuses the grabber, and the
    /// drag moves the sheet's top edge with the pointer, snapping to the
    /// nearest detent as it goes — up is taller.
    private static func registerDrag(
        handler: _SheetGrabberHandler, focusID: String, on rule: inout FrameBuffer, context: RenderContext
    ) {
        guard let dispatcher = context.environment.mouseEventDispatcher else { return }
        dispatcher.requestFeature(.drag, in: context)
        // Motion reporting, so the dispatcher can synthesise the hover
        // enter/exit transitions that light the handle.
        dispatcher.requestFeature(.motion, in: context)
        let focusManager = context.environment.focusManager
        let handlerID = dispatcher.register(in: context, reportingChangesTo: { handler.isHovered }, { event in
            switch event.phase {
            case .entered:
                handler.isHovered = true
                return true
            case .exited:
                handler.isHovered = false
                return true
            default:
                return handler.drag.handle(
                    event, along: .vertical,
                    press: {
                        focusManager?.focus(id: focusID)
                        return handler.detents?.height ?? 0
                    },
                    move: { delta, height in handler.snap(toHeight: height - delta) })
            }
        })
        rule.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0, offsetY: 0, width: rule.width, height: 1, handlerID: handlerID, focusID: focusID))
    }
}
