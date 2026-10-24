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
/// would see it late, at the release, and must not file a role. A
/// Control-press is the secondary click: a `.background` region is passed
/// over for it, and held for only where nothing else took it
/// (``MouseEventDispatcher/dispatchLeftPress(_:matching:)``).
package enum PressRole {
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
    /// Filed too where only the rows' own content enabled selection — a
    /// `List` row's `Text(name).textSelection(.enabled)`, or a `Table` cell's,
    /// whose regions the table carries up. A press on that text is under the
    /// row's or cell's own scope, which keeps the selection to it; a press on
    /// the row's other text is under no scope, and is the row's click, as on
    /// macOS (owner ruling B-D4X-7-17, 2026-10-23: the cell's modifier no
    /// longer reaches the rest of the row).
    case rows(rowArea: (_ localY: Int) -> (columns: Range<Int>, lines: Range<Int>)?)

    /// A drag handle — a `.draggable` or `.itemProvider` view, a `Table`
    /// row's `TableRow.draggable`, a draggable tab, a gradient stop — filed
    /// only where text selection is enabled somewhere in the frame. Not a
    /// click-only region: elsewhere it is offered the press as any control
    /// is, and takes it. But where its press lands on selectable TEXT — under
    /// an enabled ``View/textSelection(_:)`` scope, or on a row's text that a
    /// `.rows` region behind it keeps for a selection — it is passed over,
    /// and the press goes on to what holds it for a selection: a drag that
    /// starts on the text selects it, and drags no row. Measured on macOS
    /// 15.8.1 (decisions D4X, B-D4X-7): in a SwiftUI `List` and `Table` whose
    /// rows are `.onMove`, `.draggable` or `.itemProvider` and whose text is
    /// selectable, a drag starting on the text selects the text; the row is
    /// not dragged.
    ///
    /// Which scope is the press's is the innermost under it, filed inside
    /// the handle's content or around the handle alike: `textSelection` is
    /// environment-like, so `Text(…).textSelection(.enabled).draggable(…)`
    /// and `Text(…).draggable(…).textSelection(.enabled)` select alike, and a
    /// scroll view of draggable text as a list of it does.
    ///
    /// A control's label is not selectable text — a `Button`'s, a draggable
    /// tab's title, a gradient stop's glyph — so a handle in front of a
    /// region that would take the press as a control, before anything that
    /// holds it for a selection, keeps it, as it does with no scope: a press
    /// released there is still that control's click, forwarded by the
    /// handle. A field is a control too: a drag on a `TextField`'s text
    /// behind the handle moves the view or row rather than selecting in the
    /// field, and a click there focuses the field, as with no scope. What
    /// takes no plain left press — a scope, a hover observer, a drop zone, a
    /// context menu's trigger
    /// (``MouseEventDispatcher/takesNoPlainLeftPress(_:)``) — is not a
    /// control. Nor is the app's own ``View/onMouseEvent(_:)`` closure taken
    /// for one: it says whether it takes a left press only when offered one
    /// (``MouseEventDispatcher/isApplicationHandler(_:)``), so the handle
    /// stands aside, and the closure is offered the press in turn — one that
    /// declines it leaves the drag to select the text, and one that takes it
    /// has it, as with the scope and no handle.
    case dragSource
}

extension MouseEventDispatcher {
    /// Files `role` for the region whose handler `id` names, for the frame.
    ///
    /// Recorded for a value memo, as the handler registration beside it is, so
    /// a served subtree files it again.
    @MainActor
    package func filePressRole(_ role: PressRole, for id: HitTestRegion.HandlerID, in context: RenderContext) {
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
    /// content and returns its id. (A bordered container's interior registers
    /// nothing: its region carries ``HitTestRegion/HandlerID/selectionInterior``,
    /// which ``selectionScope(of:)`` reads as the scope.)
    ///
    /// A hover observer whose handler declines everything — geometry for the
    /// selection, taking nothing from the controls inside — with the scope's
    /// answer filed beside it, both recorded for a memo's replay.
    @MainActor
    func registerSelectionScope(_ scope: SelectionScope, in context: RenderContext) -> HitTestRegion.HandlerID {
        let id = registerHoverObserver(in: context) { _ in false }
        guard !context.isMeasuring else { return id }
        fileSelectionScope(scope, for: id)
        guard let journal = context.recordingEffectJournal else { return id }
        let token = context.environment.keyChannelToken
        journal.append(
            EffectJournal.Entry(kind: Self.selectionScopeKind, channelToken: token) { replay in
                replay.environment.mouseEventDispatcher?.fileSelectionScope(scope, for: id)
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
    ///
    /// A Control-press is none of that: it is the secondary click, which a
    /// terminal that keeps the right button for itself (iTerm2) leaves to
    /// Control, and the regions hear it at once, innermost first, as they
    /// hear a right press. A row's text gives it to its row, which opens the
    /// row's menu where it has one (as a right-click there does, and as a
    /// Mac's Control-click does); what declines it goes on outward. It never
    /// starts a selection, and a pane's background, which acts only on a
    /// click, is passed over, so a menu around a scroll view is reached; only
    /// where nothing took it does it fall through to that pane's click. A
    /// control that acts on a left press — a button, a field, a toggle — takes
    /// it as its own click, as it does with no menu around it.
    /// (The selection's own Copy menu, on its highlight, was offered it
    /// first: ``MouseEventDispatcher/dispatch(_:)``.)
    func dispatchLeftPress(_ event: MouseEvent, matching: [HitTestRegion]) -> Bool {
        if event.ctrl { return dispatchSecondaryPress(event, matching: matching) }
        // The innermost `textSelection(_:)` under the press: `false` turns the
        // selection off here — every region hears its press at once, as before
        // there was one — and `true` keeps it to that scope. A bordered
        // container's interior says nothing about whether text selects, only
        // where: the innermost enabled scope or interior is what a selection
        // keeps to.
        var tier: Bool?
        var scope: HitTestRegion?
        if !selectionScopes.isEmpty || matching.contains(where: { $0.handlerID == .selectionInterior }) {
            tier = innermostTier(matching)
            scope = matching.first { selectionScope(of: $0.handlerID)?.confinesSelection == true }
        }
        if tier == false {
            for region in matching where offer(event, to: region) != .declined { return true }
            return false
        }
        let point = ScreenSelection.Point(x: event.x, y: event.y)
        // Whether the drag handle `matching[handle]` stands aside for the text
        // under the press: text under an enabled scope, which the rows behind
        // it keep for a selection where they are filed — unless a control
        // behind the handle would take the press before anything holds it for
        // the selection: that text is the control's label. Asked only of a
        // press that reaches a drag handle.
        func yieldsToText(behind handle: Int) -> Bool {
            guard tier == true, screenSelection?.isText(at: point) == true else { return false }
            for region in matching[(handle + 1)...] {
                switch pressRoles[region.handlerID] {
                // What holds the press for the selection.
                case .background, .rows: return true
                // Another handle stands aside by this same rule.
                case .dragSource: continue
                case nil:
                    // The app's own closure (`.onMouseEvent`) says whether it
                    // takes the press only when offered it, which it is in
                    // turn, below: one that declines leaves it to the text.
                    if isApplicationHandler(region.handlerID) { continue }
                    if !takesNoPlainLeftPress(region.handlerID) { return false }
                }
            }
            // The page's background holds it.
            return true
        }
        // The pane a selection keeps to, inside an enabled scope's rectangle.
        func within(_ pane: ScreenSelection.Rect) -> ScreenSelection.Rect {
            guard let scope else { return pane }
            return pane.intersection(Self.rect(of: scope)) ?? pane
        }
        for (index, region) in matching.enumerated() {
            if let role = pressRoles[region.handlerID], let handler = handler(for: region.handlerID) {
                switch role {
                case .background:
                    // The selection keeps to the pane the press is in.
                    hold(event, for: (handler, region.localOriginX, region.localOriginY),
                        pane: within(Self.rect(of: region)))
                    return true
                case .rows(let rowArea):
                    // A press on a row's text, under an enabled scope: the
                    // text's, kept to the row (and to a cell's own scope,
                    // `within`), and no click for the row.
                    if tier == true,
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
                case .dragSource:
                    // A drag that starts on selectable text selects it, as
                    // macOS's rows do; the regions behind hold it for that.
                    if yieldsToText(behind: index) { continue }
                }
            }
            if offer(event, to: region) != .declined { return true }
        }
        guard let selection = screenSelection, selection.contentArea.contains(point) else { return false }
        hold(event, for: nil, pane: within(selection.contentArea))
        return true
    }

    /// A Control-press, the secondary click: offered to the regions at once,
    /// innermost first, passing over a pane's background, which acts only on
    /// a click (``dispatchLeftPress(_:matching:)``).
    ///
    /// Where nothing takes it as a secondary click — no menu around, no row
    /// — it falls through to the innermost pane it landed in, as the owner
    /// put it (2026-10-06), which takes it as the click it acts on: a scroll
    /// view's viewport focuses the scroll view, a split view's column
    /// activates its section, as a Control-click did before it was the
    /// secondary click. Held for the release as a background's click always
    /// is, and selecting nothing; released outside that pane, it is no click
    /// (``HeldPress``).
    private func dispatchSecondaryPress(_ event: MouseEvent, matching: [HitTestRegion]) -> Bool {
        var pane: HitTestRegion?
        for region in matching {
            if case .background = pressRoles[region.handlerID] {
                if pane == nil { pane = region }
                continue
            }
            if offer(event, to: region) != .declined { return true }
        }
        guard let pane, let handler = handler(for: pane.handlerID) else { return false }
        hold(event, for: (handler, pane.localOriginX, pane.localOriginY), pane: Self.rect(of: pane), selects: false)
        return true
    }

    /// Whether the innermost ``View/textSelection(_:)`` among `matching` lets
    /// text select there, or `nil` where none is under the press. A bordered
    /// container's interior is passed over: it says where a selection keeps
    /// to, not whether there is one.
    private func innermostTier(_ matching: [HitTestRegion]) -> Bool? {
        for region in matching {
            switch selectionScope(of: region.handlerID) {
            case .enabled: return true
            case .disabled: return false
            case .interior, nil: continue
            }
        }
        return nil
    }

    /// The cells a region covers on screen.
    private static func rect(of region: HitTestRegion) -> ScreenSelection.Rect {
        ScreenSelection.Rect(x: region.offsetX, y: region.offsetY, width: region.width, height: region.height)
    }

    /// Captures the left button for a held press whose click, if it is one,
    /// belongs to `claimer`, and whose drag selects within `pane` — or
    /// selects nothing, where `selects` is `false`.
    private func hold(
        _ press: MouseEvent, for claimer: HeldPress.Claimer?, pane: ScreenSelection.Rect, selects: Bool = true
    ) {
        let held = HeldPress(press: press, claimer: claimer, pane: pane, selection: selects ? screenSelection : nil)
        pressedHandlers[.left] = PressCapture(
            handler: { [held] event in held.receive(event) }, regionOffsetX: 0, regionOffsetY: 0)
    }
}

// MARK: - The held press

/// A left press held until it shows whether it is a click or a drag that
/// selects.
///
/// It receives the rest of the gesture in the screen's coordinates, as the
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
/// - With **no selection to make** — a Control-press, which selects nothing —
///   a drag makes nothing, and the release is the claimer's click where it
///   lands inside the pane, as a button's is where it lands on the button: a
///   press dragged out of the pane and released outside it does nothing.
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
        if press.clickCount >= 2 {
            beginSelection(unit: press.clickCount == 2 ? .word : press.clickCount == 3 ? .line : .row)
        }
    }

    /// One event of the rest of the gesture.
    func receive(_ event: MouseEvent) -> Bool {
        switch event.phase {
        case .dragged:
            if !isSelecting, event.x != press.x || event.y != press.y { beginSelection(unit: .character) }
            if isSelecting { selection?.extend(to: ScreenSelection.Point(x: event.x, y: event.y), shift: event.shift) }
        case .released:
            if isSelecting { selection?.finish() }
            // With no selection to make, a release outside the pane is a
            // press slid off and let go: no click (review round 2 of the
            // follow-ups — a Control-drag into another pane focused the pane
            // it left).
            if selection == nil, !pane.contains(ScreenSelection.Point(x: event.x, y: event.y)) { break }
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
            shape: press.meta ? .rectangle : .stream, unit: unit, shift: press.shift)
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
