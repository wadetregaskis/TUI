//  🖥️ TUI — A Terminal UI framework for Swift
//  DragAndDropSession+SelectionPreview.swift
//
//  The picture a selection's drag carries: the selected rows' own pictures
//  stacked in the container's order, up to the subtree's
//  `dragPreviewRowLimit(_:)`, and a "+N more" line for the rest — the stack a
//  Mac's drag shows, as a terminal can say it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// What a selection's drag shows in place of the grabbed row's own picture
/// (``DragAndDropSession/carrySelection(_:sources:picture:)``).
package struct SelectionPicture {
    /// The steady picture: the shown rows stacked, and the "+N more" line.
    package let preview: FrameBuffer

    /// Its travel from the rows' own layout, frame for frame as
    /// ``DragAndDropSession/ActiveDrag/morph`` runs; empty when no row has one.
    package let morph: [FrameBuffer]

    /// How many lines of the stack sit above the grabbed row: how far the grab
    /// point moves down the picture.
    package let linesAboveGrab: Int
}

extension DragAndDropSession {
    /// The rows of a selection's drag that its preview shows: `limit` of the
    /// `count` carried (all of them for `nil`, at least one), a window of
    /// consecutive ones in the container's order that holds the grabbed row
    /// at `grabbed` — the first ones, or those ending at the grabbed row when
    /// it lies past them.
    package static func shownSelectionRows(count: Int, grabbed: Int, limit: Int?) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let shown = min(count, max(1, limit ?? count))
        let grabbed = min(max(0, grabbed), count - 1)
        let start = max(0, grabbed - (shown - 1))
        return start..<(start + shown)
    }

    /// The picture of a selection's drag: the rows
    /// ``shownSelectionRows(count:grabbed:limit:)`` picks, stacked in the
    /// container's order, with a line under them counting the rest.
    ///
    /// - Parameters:
    ///   - count: How many rows the drag carries.
    ///   - grabbed: The grabbed row's place among them.
    ///   - limit: The subtree's ``EnvironmentValues/dragPreviewRowLimit``.
    ///   - grabbedFrames: The grabbed row's picture as the drag began, its
    ///     travel first where it has one (its last frame is the steady one).
    ///   - frames: Another carried row's picture, in the same form; `nil` for
    ///     one that has none, which is counted with the rest. Asked only for
    ///     the rows shown.
    package static func selectionPicture(
        count: Int, grabbed: Int, limit: Int?,
        grabbedFrames: [FrameBuffer], frames: (Int) -> [FrameBuffer]?
    ) -> SelectionPicture {
        let window = shownSelectionRows(count: count, grabbed: grabbed, limit: limit)
        // The stack travels only where the grabbed row does: a keyboard carry's
        // picture has no travel, and the rows beside it keep still with it.
        let travels = grabbedFrames.count > 1
        var rows: [[FrameBuffer]] = []
        var linesAboveGrab = 0
        for index in window {
            guard let picture = index == grabbed ? grabbedFrames : frames(index), let last = picture.last else {
                continue
            }
            if index < grabbed { linesAboveGrab += last.height }
            rows.append(travels ? picture : [last])
        }
        let hidden = count - rows.count
        let more =
            hidden > 0
            ? [
                LocalizedStringKey.substituting(
                    ["\(hidden)"], into: LocalizationService.shared.string(for: LocalizationKey.Label.dragMore))
            ] : []
        // Frame N of the stack is every row's frame N, so the rows travel as one
        // picture; a row with fewer frames holds its last.
        func stack(_ step: Int) -> FrameBuffer {
            FrameBuffer(lines: rows.flatMap { $0[min(step, $0.count - 1)].lines } + more)
        }
        let steps = rows.map(\.count).max() ?? 1
        return SelectionPicture(
            preview: stack(steps - 1),
            morph: steps > 1 ? (0..<steps).map(stack) : [],
            linesAboveGrab: linesAboveGrab)
    }
}

extension DragAndDropSession.ActiveDrag {
    /// The dragged picture in the form ``DragAndDropSession/selectionPicture(count:grabbed:limit:grabbedFrames:frames:)``
    /// takes: its travel, or the steady picture alone where it has none.
    package var pictureFrames: [FrameBuffer] { morph.isEmpty ? [preview] : morph }
}
