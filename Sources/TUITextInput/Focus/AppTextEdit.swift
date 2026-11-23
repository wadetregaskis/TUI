//  🖥️ TUI — A Terminal UI framework for Swift
//  AppTextEdit.swift
//
//  An edit the app made to the text bound to a field or an editor, found from
//  the text before and after it, and how the control's selection moves
//  through it, as NSTextView moves its own (owner ruling O-28 (a),
//  2026-11-22).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// An edit the app made to a text control's bound text — a log line appended,
/// another user's change synced in, a reformat — found from the text before
/// and the text after, and where the control's selection goes through it.
///
/// The selection moves as an `NSTextView`'s does when its text storage is
/// edited (measured on macOS 15.8, `Documentation/SwiftUI parity/SELECTION-REPLACE/`,
/// Parts 1 and 1b; owner ruling O-28 (a), 2026-11-22):
/// - an edit wholly before the selection shifts it, an insertion at its start
///   or at a caret included;
/// - an edit wholly after it leaves it, an insertion at a selection's end
///   included;
/// - an edit that touches it collapses it to a caret at the end of the text
///   put in: one inside it, across either end, over all of it, or starting at
///   a caret;
/// - so a text replaced whole leaves a caret at the end of the new text.
///
/// A binding hands over only the text after, so the edit is what lies between
/// the two texts' common start and common end. A text that shares a start or
/// an end with the one before is taken as edited between them, as a
/// `replaceCharacters` of the middle would be. Compared as bytes, never as
/// `Character`s (the owner, 2026-11-22: no collections of `Character` for a
/// document), by the scan an undo step records its edit with
/// (``TextEdit/sharedEnds(_:_:)``).
struct AppTextEdit: Equatable {
    /// The edit as the bytes it changed, placed as far towards the text's end
    /// as the two texts allow: the bytes `start..<oldEnd` of the text before
    /// gave way to `start..<newEnd`.
    let change: EditorMarkEdit

    /// The leftmost start the same edit could have: an insertion or a deletion
    /// next to bytes like its own ("aa" to "aaa") could have been made
    /// anywhere from here to ``change``'s start, and is placed among them to
    /// leave the selection be where one does (``carry(_:)``). ``change``'s
    /// start where the edit replaced something.
    let earliestStart: Int

    /// The edit that turns `old` into `new`, or `nil` where they are the same
    /// bytes.
    init?(from old: String, to new: String) {
        var old = old
        var new = new
        let found = old.withUTF8 { oldBytes in
            new.withUTF8 { newBytes in unsafe Self.edit(oldBytes, newBytes) }
        }
        guard let found else { return nil }
        self = found
    }

    init(change: EditorMarkEdit, earliestStart: Int) {
        self.change = change
        self.earliestStart = earliestStart
    }

    /// The edit between `old` and `new`, or `nil` where they are the same.
    private static func edit(_ old: UnsafeBufferPointer<UInt8>, _ new: UnsafeBufferPointer<UInt8>) -> Self? {
        let (start, end) = unsafe TextEdit.sharedEnds(old, new)
        let oldEnd = old.count - end
        let newEnd = new.count - end
        guard start < oldEnd || start < newEnd else { return nil }
        var earliest = start
        // An insertion or a deletion (one side empty) may slide left while the
        // bytes it leaves behind match from the end too.
        if start == oldEnd || start == newEnd {
            var shared = end
            let shorter = min(old.count, new.count)
            while shared < shorter, unsafe old[old.count - 1 - shared] == new[new.count - 1 - shared] { shared += 1 }
            earliest = shorter - shared
        }
        return Self(change: EditorMarkEdit(start: start, oldEnd: oldEnd, newEnd: newEnd), earliestStart: earliest)
    }

    /// Where a selection goes through the edit.
    enum Carried: Equatable {
        /// To these bytes of the new text: shifted or left as it was. Empty
        /// for a caret.
        case moved(Range<Int>)
        /// To a caret at this byte of the new text: the end of what the edit
        /// put in.
        case collapsed(Int)
    }

    /// Where `selection`, bytes of the text before (empty for a caret), goes:
    /// moved where the edit leaves it be, else collapsed. The edit is placed,
    /// among the places it could equally have been made (``earliestStart``),
    /// as far towards the end as leaves the selection be, if any does.
    func carry(_ selection: Range<Int>) -> Carried {
        placed(around: selection).carry(selection)
    }

    /// The edit placed for `selection` (``carry(_:)``), every other holder of
    /// offsets moved by the same placement.
    func placed(around selection: Range<Int>) -> Placed {
        let rightmost = Placed(change: change)
        guard earliestStart < change.start, case .collapsed = rightmost.carry(selection) else { return rightmost }
        // Wholly before it, as far right as that can be.
        let removed = change.oldEnd - change.start
        let start = min(change.start, selection.lowerBound - removed)
        guard start >= earliestStart else { return rightmost }
        let shift = change.start - start
        return Placed(
            change: EditorMarkEdit(start: start, oldEnd: change.oldEnd - shift, newEnd: change.newEnd - shift))
    }

    /// The edit at one of the places it could have been made.
    struct Placed: Equatable {
        let change: EditorMarkEdit

        /// How far the bytes after the edit moved.
        var delta: Int { change.newEnd - change.oldEnd }

        /// Where `selection` goes through this edit (``AppTextEdit``'s rules).
        func carry(_ selection: Range<Int>) -> Carried {
            if change.oldEnd <= selection.lowerBound {
                return .moved((selection.lowerBound + delta)..<(selection.upperBound + delta))
            }
            if change.start > selection.upperBound || (change.start == selection.upperBound && !selection.isEmpty) {
                return .moved(selection)
            }
            return .collapsed(change.newEnd)
        }
    }
}
