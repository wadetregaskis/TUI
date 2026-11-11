//  🖥️ TUI — A Terminal UI framework for Swift
//  MouseEventDispatcher+FocusFollowsPointer.swift
//
//  Focus follows the pointer, the dispatcher's half: the focusable control
//  under a pointer that moved. Which of them may take the focus is the focus
//  manager's (`FocusManagerPointerFocus.swift`).
//
//  Created by Wade Tregaskis
//  License: MIT

extension MouseEventDispatcher {
    /// Offers the focus to the focusable control under a bare pointer move,
    /// while the focus follows the pointer (``pointerFocusManager``).
    ///
    /// Only a move onto another cell counts: a report from the cell the pointer
    /// was already on moves nothing, so a pointer at rest never takes the focus
    /// back from the keyboard. The next move does — over the same control too,
    /// as long as it reaches another cell of it.
    ///
    /// The control is the innermost region under the pointer that carries a
    /// focus id: a `Button`'s, a `TextField`'s, a `List`'s, whatever a click
    /// there would focus — or names one: a control's label names its control
    /// (``filePointerFocusName(_:for:in:)``). A region with neither — a
    /// backdrop, a row's text — is looked through to the one behind it, which
    /// the focus manager then judges.
    /// Never while a drag is under way: a held button's moves arrive as drags,
    /// not here, and a drag the keyboard carries is steered by the keys.
    ///
    /// Within the control, a cursor of its own may follow too: a `List`'s,
    /// `Table`'s or outline's row (``filePointerFocusFollower(for:in:_:)``).
    /// It is offered the move whenever the control holds the focus after it —
    /// taken now or held already — and never otherwise, so everything that
    /// keeps the focus where it is (an edit, a sheet, an open menu, a disabled
    /// control) keeps that cursor where it is too.
    ///
    /// - Returns: Whether the focus or a follower's cursor moved, and so a
    ///   frame is wanted.
    func focusFollowingPointer(_ event: MouseEvent, movedCell: Bool) -> Bool {
        guard movedCell, let focusManager = pointerFocusManager else { return false }
        if let session = dragAndDropSession, session.carry != nil || session.active != nil { return false }
        // A region naming a control without being it (a label) counts as the
        // control (``filePointerFocusName(_:for:in:)``).
        guard let region = matchingRegions(at: event.x, y: event.y).first(where: {
            $0.focusID != nil || pointerFocusNames[$0.handlerID] != nil
        }), let focusID = region.focusID ?? pointerFocusNames[region.handlerID]
        else {
            return false
        }
        let moved = focusManager.focusFollowingPointer(id: focusID)
        guard region.focusID != nil, let follow = pointerFocusFollowers[region.handlerID],
            focusManager.currentFocusedID == focusID, !focusManager.activeSectionIsMenu
        else { return moved }
        let local = localize(event, byOffsetX: region.localOriginX, offsetY: region.localOriginY)
        return follow(local) || moved
    }

    /// Files `follow` for the control whose region `id` carries its focus id:
    /// while the focus follows the pointer, a move onto another cell of that
    /// region, with the control holding the focus, is offered to it, in the
    /// region's own coordinates, to move a cursor of the control's own there
    /// — a `List`'s row. It answers whether it moved anything. Filed every
    /// frame, as the region is, and replayed with it when a memo serves the
    /// control.
    @MainActor
    package func filePointerFocusFollower(
        for id: HitTestRegion.HandlerID, in context: RenderContext, _ follow: @escaping (MouseEvent) -> Bool
    ) {
        guard !context.isMeasuring else { return }
        pointerFocusFollowers[id] = follow
        context.environment.volatileReadTracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return }
        let token = context.environment.keyChannelToken
        journal.append(
            EffectJournal.Entry(kind: Self.pointerFocusFollowerKind, channelToken: token) { replay in
                replay.environment.mouseEventDispatcher?.pointerFocusFollowers[id] = follow
            })
    }

    /// The journal kind of a pointer focus follower's filing.
    static let pointerFocusFollowerKind = EffectJournal.Kind("pointerFocusFollower")

    /// Files the region `id` names as naming the control answering to
    /// `focusID`, for the focus following the pointer alone: a move onto it
    /// offers that control the focus, as a move onto the control would. A
    /// control's label (`_LabelledControlRow`), whose region carries no focus
    /// id of its own, so the control's own region is still the first with its
    /// id, where a reveal and the text cursor go; and a hover observer, so
    /// presses and the hover go on to what is behind it. Filed every frame, as
    /// the region is, and replayed with it when a memo serves the label.
    @MainActor
    package func filePointerFocusName(_ focusID: String, for id: HitTestRegion.HandlerID, in context: RenderContext) {
        guard !context.isMeasuring else { return }
        pointerFocusNames[id] = focusID
        context.environment.volatileReadTracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return }
        let token = context.environment.keyChannelToken
        journal.append(
            EffectJournal.Entry(kind: Self.pointerFocusNameKind, channelToken: token) { replay in
                replay.environment.mouseEventDispatcher?.pointerFocusNames[id] = focusID
            })
    }

    /// The journal kind of a pointer focus name's filing.
    static let pointerFocusNameKind = EffectJournal.Kind("pointerFocusName")
}
