//  🖥️ TUI — A Terminal UI framework for Swift
//  TestApp+Input.swift
//
//  What a person does to an app: keys, clicks, the wheel, drags, the pointer.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIApp
import TUICore
import TUIFoundation

// MARK: - Keys

extension TestApp {
    /// Presses a key, `times` times, as a terminal reports it, and draws the
    /// frames each press causes.
    ///
    /// It goes where a keypress goes: to the control with the focus, then what
    /// holds that control, then the app's shortcuts. A shortcut declared with
    /// `.command`, as a `Button`'s `.keyboardShortcut("s")` is, fires on the key
    /// that stands in for ⌘ in a terminal, which is Control unless the app
    /// says otherwise with `.commandKey(_:)`. So press it with `.control`.
    ///
    /// - Parameters:
    ///   - key: The key, such as `.space`, `.down` or `.character("a")`.
    ///   - modifiers: The modifier keys held.
    ///   - times: How many times to press it.
    /// - Returns: Whether something took the last press.
    @discardableResult
    public func press(_ key: Key, modifiers: EventModifiers = [], times: Int = 1) -> Bool {
        press(
            KeyEvent(
                key: key,
                ctrl: modifiers.contains(.control),
                alt: modifiers.contains(.option),
                shift: modifiers.contains(.shift),
                command: modifiers.contains(.command)),
            times: times)
    }

    /// Delivers a key event, `times` times, and draws the frames each causes,
    /// for what ``press(_:modifiers:times:)`` cannot say, such as a key's release.
    ///
    /// - Returns: Whether something took the last one.
    @discardableResult
    public func press(_ event: KeyEvent, times: Int = 1) -> Bool {
        start()
        var taken = false
        for _ in 0..<max(0, times) {
            taken = headless.send(event)
            drawFrames()
        }
        return taken
    }

    /// Types `text` a character at a time, as a person does: a frame after each.
    /// A newline is the Return key, and a tab the Tab key.
    public func type(_ text: String) {
        for character in text {
            switch character {
            case "\n", "\r", "\r\n": press(.enter)
            case "\t": press(.tab)
            case " ": press(.space)
            default: press(KeyEvent(character: character))
            }
        }
    }
}

// MARK: - The mouse

extension TestApp {
    /// Which way a wheel turns: what ``scroll(_:by:at:)`` moves the content
    /// towards, as a terminal reports it.
    public enum ScrollDirection: Sendable {
        case up, down, left, right
    }

    /// Clicks a cell: the button pressed, a frame, the button released, a frame.
    ///
    /// Two clicks in one place with no time between them are a double click, as
    /// they would be for a person. To make them two clicks, ``advance(by:)``
    /// between them.
    ///
    /// - Parameters:
    ///   - point: The cell, from `(0, 0)` at the top left of the screen.
    ///   - button: Which button.
    ///   - modifiers: The modifier keys held. A terminal reports Shift, Control
    ///     and Option on a click; `.command` is ignored.
    public func click(at point: CellPoint, button: MouseButton = .left, modifiers: EventModifiers = []) {
        start()
        send(.pressed, button: button, at: point, modifiers: modifiers)
        send(.released, button: button, at: point, modifiers: modifiers)
    }

    /// Clicks the middle of `text`, where it first shows on the screen.
    ///
    /// - Parameters:
    ///   - text: What to click, as ``TestScreen/location(of:)`` finds it.
    ///   - button: Which button.
    ///   - modifiers: The modifier keys held. A terminal reports Shift, Control
    ///     and Option on a click; `.command` is ignored.
    /// - Throws: ``TestAppError`` if the screen does not show `text`.
    public func click(_ text: String, button: MouseButton = .left, modifiers: EventModifiers = []) throws {
        click(at: try middle(of: text), button: button, modifiers: modifiers)
    }

    /// Turns the wheel by `ticks` over a cell, the middle of the screen unless
    /// you say otherwise, with the frames that causes.
    public func scroll(_ direction: ScrollDirection, by ticks: Int = 1, at point: CellPoint? = nil) {
        start()
        let point = point ?? CellPoint(x: headless.size.width / 2, y: headless.size.height / 2)
        let button: MouseButton
        switch direction {
        case .up: button = .scrollUp
        case .down: button = .scrollDown
        case .left: button = .scrollLeft
        case .right: button = .scrollRight
        }
        // A wheel's ticks arrive in bursts, and a frame shows them together.
        for _ in 0..<max(0, ticks) {
            headless.send(MouseEvent(button: button, phase: .scrolled, x: point.x, y: point.y))
        }
        drawFrames()
    }

    /// Turns the wheel by `ticks` over `text`, where it first shows.
    ///
    /// - Throws: ``TestAppError`` if the screen does not show `text`.
    public func scroll(_ direction: ScrollDirection, by ticks: Int = 1, over text: String) throws {
        scroll(direction, by: ticks, at: try middle(of: text))
    }

    /// Drags with the left button from one cell to another: a press, the
    /// pointer moving in steps along the line between them, a frame after each,
    /// and the release.
    public func drag(from start: CellPoint, to end: CellPoint, modifiers: EventModifiers = []) {
        self.start()
        send(.pressed, button: .left, at: start, modifiers: modifiers)
        let distance = max(abs(end.x - start.x), abs(end.y - start.y))
        let steps = max(1, min(distance, Self.mostDragSteps))
        for step in 1...steps {
            let point = CellPoint(
                x: start.x + (end.x - start.x) * step / steps,
                y: start.y + (end.y - start.y) * step / steps)
            send(.dragged, button: .left, at: point, modifiers: modifiers)
        }
        send(.released, button: .left, at: end, modifiers: modifiers)
    }

    /// Drags with the left button from the middle of one text on the screen to
    /// the middle of another.
    ///
    /// - Throws: ``TestAppError`` if the screen does not show either.
    public func drag(from start: String, to end: String, modifiers: EventModifiers = []) throws {
        drag(from: try middle(of: start), to: try middle(of: end), modifiers: modifiers)
    }

    /// Moves the pointer to a cell, with no button held, and draws what that
    /// causes.
    ///
    /// As in a terminal, the move arrives only if the app has asked to hear of
    /// moves: `.onHover`, `.help` and `.onContinuousHover` ask for them.
    public func hover(at point: CellPoint) {
        start()
        send(.moved, button: .none, at: point, modifiers: [])
    }

    /// Moves the pointer to the middle of `text`, where it first shows.
    ///
    /// - Throws: ``TestAppError`` if the screen does not show `text`.
    public func hover(over text: String) throws {
        hover(at: try middle(of: text))
    }

    /// Delivers a mouse event, and draws what it causes, for what the methods
    /// above cannot say: a button held down while the clock moves, say, which
    /// is how a long press is tested.
    ///
    /// - Returns: Whether something took it.
    @discardableResult
    public func mouse(_ event: MouseEvent) -> Bool {
        start()
        let taken = headless.send(event)
        drawFrames()
        return taken
    }

    /// The most frames a drag draws on its way, however long it is.
    private static var mostDragSteps: Int { 8 }

    /// Delivers one mouse event, and draws what it causes.
    private func send(_ phase: MousePhase, button: MouseButton, at point: CellPoint, modifiers: EventModifiers) {
        mouse(
            MouseEvent(
                button: button, phase: phase, x: point.x, y: point.y,
                shift: modifiers.contains(.shift), ctrl: modifiers.contains(.control),
                meta: modifiers.contains(.option)))
    }

    /// The cell in the middle of `text`, where it first shows.
    private func middle(of text: String) throws -> CellPoint {
        let screen = screen
        guard let point = screen.location(of: text) else {
            throw TestAppError("The screen does not show “\(text)”. It shows:\n\(screen)")
        }
        return CellPoint(x: point.x + text.strippedLength / 2, y: point.y)
    }
}
