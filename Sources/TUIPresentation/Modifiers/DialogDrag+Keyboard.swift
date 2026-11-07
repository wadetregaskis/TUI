//  🖥️ TUI — A Terminal UI framework for Swift
//  DialogDrag+Keyboard.swift
//
//  A sheet's keyboard route to what its border's drag does: a Resize stop
//  and a Move stop after its content in the Tab order, the arrows stepping
//  the sheet's size or place and Home putting it back.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIStyling

// MARK: - The stops

/// One of a sheet's two keyboard stops: Resize, whose arrows step its size,
/// or Move, whose arrows step its place — each as a drag of the border does,
/// through the sheet's ``_DialogDragHandler``.
///
/// Shift steps five, where the terminal sends it, as it does for a
/// `.userResizable` view's keys and a split view's divider. Home puts the
/// sheet back: at its own size, or in the middle of the screen. Anything else
/// — Tab, Escape, Return — is not taken, so it reaches the focus ring and the
/// sheet's own Escape.
///
/// Its focus shows only in what the presenter draws itself, the grips and the
/// border (`FocusDrawnOnlyAtItself`): a stop registers at the presenter's
/// identity, and its focus moving must not drop the page drawn below it as a
/// backdrop, or the content, which draw nothing of it.
final class _DialogKeyStop: PersistedFocusable, FocusDrawnOnlyAtItself {
    enum Role {
        case resize
        case move
    }

    let role: Role
    var focusID: String

    /// ``PersistedFocusable``: answers to `focusID` from now on.
    func repoint(focusID: String) { self.focusID = focusID }

    var canBeFocused = true

    /// The sheet's drag state, which the keys change as the pointer does.
    var drag: _DialogDragHandler?

    init(role: Role, focusID: String) {
        self.role = role
        self.focusID = focusID
    }

    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        guard let drag else { return false }
        let step = event.shift ? 5 : 1
        let delta: (x: Int, y: Int)
        switch event.key {
        case .left: delta = (-step, 0)
        case .right: delta = (step, 0)
        case .up: delta = (0, -step)
        case .down: delta = (0, step)
        case .home:
            switch role {
            case .resize: drag.resetSize()
            case .move: drag.centre()
            }
            return true
        default:
            return false
        }
        switch role {
        case .resize: drag.resize(width: delta.x, height: delta.y)
        case .move: drag.move(x: delta.x, y: delta.y)
        }
        return true
    }
}

// MARK: - Registering and drawing

@MainActor extension DialogDrag {
    /// Where a sheet's keyboard stops live: its focus section, and the
    /// presenter's `StateStorage` indices for each stop's focus id and
    /// handler.
    struct KeyStops {
        let sectionID: String
        let resizeFocusIDIndex: Int
        let resizeIndex: Int
        let moveFocusIDIndex: Int
        let moveIndex: Int
    }

    /// Registers the sheet's Resize stop, where it `resizes`, then its Move
    /// stop, in its section — after its content, which has drawn, so the
    /// content takes the focus the sheet opens with and the two follow it in
    /// the ring, Resize first, as a resizable view's grip follows its content
    /// — and names on the status bar what the focused one's keys do.
    ///
    /// - Returns: The stop that shows the focus, or `nil` for neither.
    static func registerKeyStops(
        _ stops: KeyStops, handler: _DialogDragHandler, resizes: Bool, context: RenderContext
    ) -> _DialogKeyStop.Role? {
        guard let stateStorage = context.stateStorage else { return nil }
        var registering = context
        registering.environment.activeFocusSectionID = stops.sectionID
        var focused: _DialogKeyStop.Role?
        func register(_ role: _DialogKeyStop.Role, prefix: String, focusIDIndex: Int, index: Int) {
            let focusID = FocusRegistration.persistFocusID(
                context: registering, explicitFocusID: nil, defaultPrefix: prefix, propertyIndex: focusIDIndex)
            let stop = stateStorage.storage(
                for: StateStorage.StateKey(identity: context.identity, propertyIndex: index),
                default: _DialogKeyStop(role: role, focusID: focusID)
            ).value
            stop.drag = handler
            stop.canBeFocused = context.environment.isEnabled
            FocusRegistration.register(context: registering, handler: stop, focusID: focusID)
            guard stop.canBeFocused, FocusRegistration.isFocused(context: registering, focusID: focusID) else {
                return
            }
            publishHint(for: role, sectionID: stops.sectionID, context: context)
            if context.indicatesFocus(true) { focused = role }
        }
        if resizes {
            register(.resize, prefix: "sheet-resize", focusIDIndex: stops.resizeFocusIDIndex, index: stops.resizeIndex)
        }
        register(.move, prefix: "sheet-move", focusIDIndex: stops.moveFocusIDIndex, index: stops.moveIndex)
        return focused
    }

    /// Names the focused stop's keys on the status bar, among the sheet's own
    /// items: "↑↓←→ resize · Home reset", or "↑↓←→ move · Home centre". Shown
    /// only: the stop takes the keys itself.
    private static func publishHint(for role: _DialogKeyStop.Role, sectionID: String, context: RenderContext) {
        guard let statusBar = context.environment.statusBar else { return }
        let service = LocalizationService.shared
        let (arrows, home): (LocalizationKey.StatusBar, LocalizationKey.StatusBar) =
            switch role {
            case .resize: (.resize, .resetSize)
            case .move: (.move, .centre)
            }
        statusBar.keepPresentationItem(
            StatusBarItem(shortcut: Shortcut.arrowsAll, label: service.string(for: arrows)), inSection: sectionID)
        statusBar.keepPresentationItem(
            StatusBarItem(shortcut: Shortcut.home, label: service.string(for: home)), inSection: sectionID)
    }

    /// The border of `buffer` in the focus's breathing ink, for the Move stop:
    /// every box cell round its edge — the title, and anything else the edge
    /// carries, left as drawn. The grips go over it afterwards, in their own
    /// ink.
    static func breatheBorder(of buffer: inout FrameBuffer, environment: EnvironmentValues) {
        let width = buffer.width
        let height = buffer.height
        guard width > 0, height > 0, buffer.lines.count >= height else { return }
        let ink = BorderGrip.ink(isFocused: true, isHovered: false, environment: environment)
        for y in 0..<height {
            let runs = borderRuns(in: buffer.lines[y].stripped, width: width)
            if y == 0 || y == height - 1 {
                for run in runs {
                    BorderGrip.mark(run.text, cells: run.text.count, into: &buffer, at: (x: run.x, y: y), ink: ink)
                }
                continue
            }
            // Inside rows, only the cells on the left and right edges.
            if let first = runs.first, first.x == 0, let glyph = first.text.first {
                BorderGrip.mark(String(glyph), cells: 1, into: &buffer, at: (x: 0, y: y), ink: ink)
            }
            if width > 1, let last = runs.last, last.x + last.text.count == width, let glyph = last.text.last {
                BorderGrip.mark(String(glyph), cells: 1, into: &buffer, at: (x: width - 1, y: y), ink: ink)
            }
        }
    }

    /// The runs of box cells in `row`, `width` cells wide, each with the cell
    /// it starts at — one cell per glyph, which every Box Drawing and block
    /// glyph is.
    private static func borderRuns(in row: String, width: Int) -> [(x: Int, text: String)] {
        var runs: [(x: Int, text: String)] = []
        var x = 0
        var current: (x: Int, text: String)?
        for character in row {
            let cells = character.terminalWidth
            if cells == 1, isBorderCell(character) {
                if current == nil { current = (x, "") }
                current?.text.append(character)
            } else if let run = current {
                runs.append(run)
                current = nil
            }
            x += cells
            if x >= width { break }
        }
        if let current { runs.append(current) }
        return runs
    }
}
