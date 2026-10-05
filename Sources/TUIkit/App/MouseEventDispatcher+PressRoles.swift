//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MouseEventDispatcher+PressRoles.swift
//
//  The regions that take a left press only to act on its CLICK, and the press
//  held for them until it shows whether it is one.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Press roles

/// What a region that takes left presses is, when all it does with them is act
/// on the click.
///
/// Most regions that take a left press are controls: a button, a field, a
/// slider, a `.draggable`. A few take it only so that a click on empty space
/// does something — a scroll view's viewport focuses the scroll view, a split
/// view's column activates its section — and a drag means nothing to them.
/// Those file a role, and a press that reaches one is HELD: the dispatcher
/// captures the button itself, and hands the region its press and its release
/// together when the release arrives, if the pointer never left the cell. That
/// is what lets a drag over such a region become something else (the screen
/// selection) without taking the region's click away.
///
/// **The contract a role states:** the region acts on the RELEASE, and its
/// press does nothing anyone would see — it only claims the gesture. Every
/// region that files one does exactly that (`ScrollView`'s viewport,
/// `NavigationSplitView`'s columns). A future region that acted on the press
/// would see it late, at the release, and must not file a role.
enum PressRole {
    /// A pane's background: a scroll view's viewport, a split view's column.
    case background

    /// The rows of a `List` or a `Table` inside a
    /// ``View/textSelection(_:)``-enabled scope, filed only there. A press on
    /// a row's TEXT belongs to the text, as on macOS: it is held for a
    /// selection kept to the row, and its click goes to no one — a click on
    /// row text selects nothing. A press on a blank cell is the rows', as
    /// everywhere else.
    ///
    /// `rowArea` answers, for a line in the region's own coordinates, the
    /// row drawn there: its columns and its lines, in the same coordinates —
    /// or `nil` where no row is (a section header, the border).
    ///
    /// `cellsSelectText` says the rows' own content asked for it: a `Table`
    /// whose cells filed an enabled scope while it drew them
    /// (`Text(name).textSelection(.enabled)` in a column). A table draws its
    /// cells as text and keeps none of their regions, so no scope is under
    /// the press to say so; with this, a press under no scope at all is
    /// treated as under an enabled one. A `List`'s rows keep their regions,
    /// so a row's own scope is found under the press, and it passes `false`.
    case rows(rowArea: (_ localY: Int) -> (columns: Range<Int>, lines: Range<Int>)?, cellsSelectText: Bool)
}

extension MouseEventDispatcher {
    /// Files `role` for the region whose handler `id` names, for the frame.
    ///
    /// Recorded for a value memo, as the handler registration beside it is, so
    /// a served subtree files it again.
    @MainActor
    func filePressRole(_ role: PressRole, for id: HitTestRegion.HandlerID, in context: RenderContext) {
        guard !context.isMeasuring else { return }
        pressRoles[id] = role
        context.environment.volatileReadTracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return }
        let token = context.environment.keyChannelToken
        journal.append(
            EffectJournal.Entry(kind: Self.pressRoleKind, channelToken: token) { replay in
                replay.environment.mouseEventDispatcher?.pressRoles[id] = role
            })
    }

    /// The journal kind of a press role's filing.
    static let pressRoleKind = EffectJournal.Kind("pressRole")

    /// Registers the region a ``View/textSelection(_:)`` files over its
    /// content, and returns its id.
    ///
    /// A hover observer whose handler declines everything — geometry for the
    /// selection, taking nothing from the controls inside — with the scope's
    /// answer filed beside it, both recorded for a memo's replay.
    @MainActor
    func registerSelectionScope(_ allowsSelection: Bool, in context: RenderContext) -> HitTestRegion.HandlerID {
        let id = registerHoverObserver(in: context) { _ in false }
        guard !context.isMeasuring else { return id }
        fileSelectionScope(allowsSelection, for: id)
        guard let journal = context.recordingEffectJournal else { return id }
        let token = context.environment.keyChannelToken
        journal.append(
            EffectJournal.Entry(kind: Self.selectionScopeKind, channelToken: token) { replay in
                replay.environment.mouseEventDispatcher?.fileSelectionScope(allowsSelection, for: id)
            })
        return id
    }

    /// The journal kind of a selection scope's filing.
    static let selectionScopeKind = EffectJournal.Kind("selectionScope")

    /// Dispatches a left press, holding it for the first region with a role
    /// it reaches — or for the screen selection, where it reaches none.
    ///
    /// The regions are offered the press innermost first, as for every other
    /// event, until one takes it. A region with a role is not offered it: the
    /// press is held for it instead (``HeldPress``), and the region hears its
    /// press and release together at the release, unless the gesture became a
    /// selection. A press no region takes lands on the page's background,
    /// where it can only select.
    func dispatchLeftPress(_ event: MouseEvent, matching: [HitTestRegion]) -> Bool {
        // The innermost `textSelection(_:)` under the press: `false` turns the
        // selection off here — every region hears its press at once, as before
        // there was one — and `true` keeps it to that scope.
        let scope = selectionScopes.isEmpty ? nil : matching.first { selectionScopes[$0.handlerID] != nil }
        let tier = scope.flatMap { selectionScopes[$0.handlerID] }
        if tier == false {
            for region in matching where offer(event, to: region) != .declined { return true }
            return false
        }
        let point = ScreenSelection.Point(x: event.x, y: event.y)
        // The pane a selection keeps to, inside an enabled scope's rectangle.
        func within(_ pane: ScreenSelection.Rect) -> ScreenSelection.Rect {
            guard let scope else { return pane }
            return pane.intersection(Self.rect(of: scope)) ?? pane
        }
        for region in matching {
            if let role = pressRoles[region.handlerID], let handler = handler(for: region.handlerID) {
                switch role {
                case .background:
                    // The selection keeps to the pane the press is in.
                    hold(event, for: (handler, region.localOriginX, region.localOriginY),
                        pane: within(Self.rect(of: region)))
                    return true
                case .rows(let rowArea, let cellsSelectText):
                    // A press on a row's text, under an enabled scope: the
                    // text's, kept to the row, and no click for the row.
                    if tier == true || (tier == nil && cellsSelectText),
                        screenSelection?.isText(at: point) == true,
                        let area = rowArea(event.y - region.localOriginY)
                    {
                        let row = ScreenSelection.Rect(
                            x: region.localOriginX + area.columns.lowerBound,
                            y: region.localOriginY + area.lines.lowerBound,
                            width: area.columns.count, height: area.lines.count)
                        if let pane = row.intersection(Self.rect(of: region)), pane.contains(point) {
                            hold(event, for: nil, pane: within(pane))
                            return true
                        }
                    }
                }
            }
            if offer(event, to: region) != .declined { return true }
        }
        guard let selection = screenSelection, selection.contentArea.contains(point) else { return false }
        hold(event, for: nil, pane: within(selection.contentArea))
        return true
    }

    /// The cells a region covers on screen.
    private static func rect(of region: HitTestRegion) -> ScreenSelection.Rect {
        ScreenSelection.Rect(x: region.offsetX, y: region.offsetY, width: region.width, height: region.height)
    }

    /// Captures the left button for a held press whose click, if it is one,
    /// belongs to `claimer`, and whose drag selects within `pane`.
    private func hold(_ press: MouseEvent, for claimer: HeldPress.Claimer?, pane: ScreenSelection.Rect) {
        let held = HeldPress(press: press, claimer: claimer, pane: pane, selection: screenSelection)
        pressedHandlers[.left] = PressCapture(
            handler: { [held] event in held.receive(event) }, regionOffsetX: 0, regionOffsetY: 0)
    }
}

// MARK: - The held press

/// A left press held until it shows whether it is a click or a drag that
/// selects.
///
/// It receives the rest of the gesture in content-area coordinates, as the
/// dispatcher's capture for it is anchored at the origin.
///
/// - A **click** — a release on the cell pressed, with no motion — is the
///   claimer's: it hears its press and release at the release, in its own
///   coordinates and with the press's click count.
/// - A **drag** — the pointer reaching another cell — selects what it crosses
///   (``ScreenSelection``), within the pane the press is in; with Option (meta)
///   held, a rectangle. The claimer hears nothing of it.
/// - A **double-click** selects the word under it at once, a **triple-click**
///   the row, and a drag after either extends by words or rows. The claimer
///   still hears the click, which for a pane's background is harmless — it
///   takes the focus — and keeps a double-click's meaning for anything that
///   gives it one.
final class HeldPress {
    /// The region the click belongs to: its handler, captured at the press
    /// (the table is rebuilt every frame, and a gesture spans frames), and its
    /// origin.
    typealias Claimer = (handler: (MouseEvent) -> Bool, originX: Int, originY: Int)

    /// The press, as the dispatcher stamped it.
    let press: MouseEvent

    /// Whose click it is; `nil` on the page's background, where a click does
    /// nothing.
    let claimer: Claimer?

    /// The rectangle a selection keeps to.
    let pane: ScreenSelection.Rect

    /// The app's selection, where there is one to make.
    let selection: ScreenSelection?

    /// Whether the gesture is making a selection.
    private var isSelecting = false

    init(press: MouseEvent, claimer: Claimer?, pane: ScreenSelection.Rect, selection: ScreenSelection?) {
        self.press = press
        self.claimer = claimer
        self.pane = pane
        self.selection = selection
        if press.clickCount >= 2 { beginSelection(unit: press.clickCount == 2 ? .word : .row) }
    }

    /// One event of the rest of the gesture.
    func receive(_ event: MouseEvent) -> Bool {
        switch event.phase {
        case .dragged:
            if !isSelecting, event.x != press.x || event.y != press.y { beginSelection(unit: .character) }
            if isSelecting { selection?.extend(to: ScreenSelection.Point(x: event.x, y: event.y)) }
        case .released:
            if isSelecting { selection?.finish() }
            // A drag is not a click; a multi-click that selected still is one.
            if !isSelecting || press.clickCount >= 2 { deliverClick(ending: event) }
        default:
            break
        }
        return true
    }

    /// Starts the selection at the press.
    private func beginSelection(unit: ScreenSelection.Unit) {
        guard let selection else { return }
        selection.begin(
            at: ScreenSelection.Point(x: press.x, y: press.y), clip: pane,
            shape: press.meta ? .rectangle : .stream, unit: unit)
        isSelecting = selection.hasSelection
    }

    /// The claimer's press, then its release.
    private func deliverClick(ending release: MouseEvent) {
        guard let claimer else { return }
        func local(_ event: MouseEvent) -> MouseEvent {
            MouseEvent(
                button: event.button, phase: event.phase, x: event.x - claimer.originX,
                y: event.y - claimer.originY, shift: event.shift, ctrl: event.ctrl, meta: event.meta,
                clickCount: event.clickCount)
        }
        guard claimer.handler(local(press)) else { return }
        _ = claimer.handler(local(release))
    }
}
