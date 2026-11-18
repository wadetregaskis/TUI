//  🖥️ TUI — A Terminal UI framework for Swift
//  AttributedTextSource.swift
//
//  The `AttributedString` a TextEditor bound to one edits: kept beside the
//  `String` of its characters the editor lays out, edited in place by the
//  editor's own edits, and taken whole when the app writes another (G3 L4).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

/// The bindings an attributed ``TextEditor`` was made with.
struct AttributedTextBinding {
    let text: Binding<AttributedString>
    let selection: Binding<AttributedTextSelection>?
}

/// The `AttributedString` an attributed ``TextEditor`` edits, and the `String`
/// of its characters that the editor's lines are laid out from (G3 L4,
/// B-ATTRED-1).
///
/// The editor works on the `String` as a `String`-bound editor does, through
/// ``plainText``, a binding over this source, so the two share every key, the
/// layout and the drawing. What differs is what a write of that binding does:
///
/// - **The editor's own edit** is made in the value in place first
///   (``stage(_:in:)``, B-ATTRED-3), the inserted text taking the typing
///   attributes (B-ATTRED-16), and the write hands that value to the app.
///   Read back, it is the same storage, and costs nothing to recognise.
/// - **An undo** hands the value the step kept (``stageWhole(_:)``), its
///   attributes with it.
/// - **Any other write** of the editor's — the find bar's Replace — is made
///   as one replacement between the old text's and the new one's common
///   start and end.
///
/// A value the app writes is taken whole (B-ATTRED-4, ``sync(with:)``): its
/// characters read into a `String` and compared with the editor's, and the
/// lines' styles read afresh. Foundation gives no way to learn that only the
/// attributes changed.
final class AttributedTextSource {
    var binding: Binding<AttributedString>
    var selection: Binding<AttributedTextSelection>?

    /// The value last written or taken.
    private(set) var value: AttributedString
    /// ``value``'s characters.
    private(set) var string: String

    /// The value the next write of ``plainText`` hands the app, made by the
    /// edit that write is for, and whether it was given whole (an undo).
    private var staged: (value: AttributedString, isWhole: Bool)?

    /// The typing attributes an insertion takes in place of its own: those of
    /// a selection typed over, held from before the selection was removed
    /// (B-ATTRED-16), until the next insertion or key.
    var heldTypingAttributes: AttributeContainer?

    /// Told when a value is taken whole, and whether it has the characters of
    /// the one before: the lines' styles are read afresh.
    var onTakenWhole: ((_ sameCharacters: Bool) -> Void)?

    /// The selection last written to the app, and its character offsets: the
    /// app's binding read back as that same selection needs no finding.
    var published: (selection: AttributedTextSelection, offsets: Range<Int>)?

    init(_ bindings: AttributedTextBinding) {
        binding = bindings.text
        selection = bindings.selection
        value = bindings.text.wrappedValue
        string = Self.characters(of: value)
    }

    /// The editor's text as a `String` binding: reading it takes a value the
    /// app wrote since (``sync(with:)``); writing it hands the app the staged
    /// value (``write(_:)``).
    private(set) lazy var plainText = Binding<String>(
        get: { [weak self] in self?.currentString ?? "" },
        set: { [weak self] in self?.write($0) })

    /// ``string``, after taking a value the app wrote since.
    var currentString: String {
        sync(with: binding.wrappedValue)
        return string
    }

    /// ``value``, after taking a value the app wrote since.
    var currentValue: AttributedString {
        sync(with: binding.wrappedValue)
        return value
    }

    /// The characters of `current`, the value a measure's binding holds.
    func string(for current: AttributedString) -> String {
        sync(with: current)
        return string
    }

    /// Takes `current` if it is not the value last written or taken
    /// (B-ATTRED-4): reads its characters, keeps the `String` the layout was
    /// made from if they are the same, and has the lines' styles read afresh.
    ///
    /// Not an `==` of the values, which compares every character of two equal
    /// values in different storage (360 ns a character, measured; the
    /// initializer's documentation has the price): the characters are read
    /// through a slice of the character view, which copies the storage's
    /// chunks, at about 0.2 ns a character.
    func sync(with current: AttributedString) {
        if Self.isIdentical(current, value) { return }
        let characters = Self.characters(of: current)
        let same = TextEdit.sameBytes(characters, string)
        value = current
        if !same { string = characters }
        staged = nil
        published = nil
        onTakenWhole?(same)
    }

    /// Hands the app the staged value, or `newString` made as one replacement
    /// of the value's characters.
    func write(_ newString: String) {
        let next: AttributedString
        if let staged {
            next = staged.value
            if staged.isWhole { onTakenWhole?(TextEdit.sameBytes(newString, string)) }
        } else {
            next = replacingCharacters(with: newString)
        }
        staged = nil
        value = next
        string = newString
        binding.wrappedValue = next
    }

    // MARK: - The editor's edits

    /// Makes `replacements` in the value, as ``TextEditorReplacement/apply(to:)``
    /// makes them in `layout`'s lines, for the next write to hand the app
    /// (B-ATTRED-3). A text with more than one kind of line break is joined
    /// afresh by the editor (``TextEditorHandler/writeReplacing(_:beforeWriting:)``),
    /// and is made by the write as one replacement instead.
    func stage(_ replacements: [TextEditorReplacement], in layout: EditorLayout) {
        guard layout.hasOneLineEnding else {
            staged = nil
            return
        }
        var text = value
        var lines = layout.lines
        for replacement in replacements {
            // One replacement is placed by the layout; several (a block's rows,
            // last first) by the lines the ones before left.
            let start: Int
            let end: Int
            if replacements.count == 1 {
                start = layout.characterOffset(of: replacement.start)
                end = layout.characterOffset(of: replacement.end)
            } else {
                start = Self.offset(of: replacement.start, in: lines)
                end = Self.offset(of: replacement.end, in: lines)
                replacement.apply(to: &lines)
            }
            let lower = text.characters.index(text.startIndex, offsetBy: start)
            let upper = text.characters.index(lower, offsetBy: end - start)
            let inserted = replacement.replacement.map { String($0) }.joined(separator: layout.lineEnding)
            text.replaceSubrange(lower..<upper, with: insertion(inserted, replacing: lower..<upper, in: text))
            // Held for the insertion after a selection's removal, and spent by it.
            if !inserted.isEmpty { heldTypingAttributes = nil }
        }
        staged = (text, false)
    }

    /// Stages `whole`, an undo's value, for the next write.
    func stageWhole(_ whole: AttributedString) {
        staged = (whole, true)
    }

    /// `string` with the attributes it takes in place of `range` of `text`:
    /// the typing attributes (B-ATTRED-16); and two characters swapped, as
    /// Ctrl-T swaps them, each with its own.
    private func insertion(
        _ string: String, replacing range: Range<AttributedString.Index>, in text: AttributedString
    ) -> AttributedString {
        if !range.isEmpty, string.count == 2 {
            let middle = text.characters.index(after: range.lowerBound)
            if text.characters.index(after: middle) == range.upperBound,
                String(text[middle..<range.upperBound].characters) + String(text[range.lowerBound..<middle].characters)
                    == string
            {
                var swapped = AttributedString(text[middle..<range.upperBound])
                swapped.append(text[range.lowerBound..<middle])
                return swapped
            }
        }
        guard !string.isEmpty else { return AttributedString() }
        return AttributedString(string, attributes: typingAttributes(replacing: range, in: text))
    }

    /// What text typed in place of `range` of `text` takes (B-ATTRED-16):
    /// those held from a selection typed over; over a range, its first
    /// character's; at an insertion point, those the app's selection gave it
    /// there, else the macOS text system's rule
    /// (``AttributedTextSelection/typingAttributes(in:)``).
    private func typingAttributes(replacing range: Range<AttributedString.Index>, in text: AttributedString) -> AttributeContainer {
        if let heldTypingAttributes { return heldTypingAttributes }
        if !range.isEmpty { return AttributedTextSelection.attributes(ofCharacterAt: range.lowerBound, in: text) }
        let caret = AttributedTextSelection(
            insertionPoint: range.lowerBound, typingAttributes: appTypingAttributes(at: range.lowerBound, in: text))
        return caret.typingAttributes(in: text)
    }

    /// The typing attributes the app's selection holds, where it is an
    /// insertion point at `index` of `text` (the value before the edit).
    private func appTypingAttributes(at index: AttributedString.Index, in text: AttributedString) -> AttributeContainer? {
        guard let chosen = selection?.wrappedValue, let typing = chosen.storedTypingAttributes,
            case .insertionPoint(let caret) = chosen.indices(in: value)
        else { return nil }
        let offset = value.characters.distance(from: value.startIndex, to: caret)
        return text.characters.distance(from: text.startIndex, to: index) == offset ? typing : nil
    }

    /// The typing attributes for typing over the characters from `offset` on:
    /// the first one's, held while the selection is removed and the typed text
    /// inserted, as two writes (B-ATTRED-16).
    func holdTypingAttributes(ofCharacterAt offset: Int) {
        let text = value
        guard let index = text.characters.index(text.startIndex, offsetBy: offset, limitedBy: text.endIndex),
            index < text.endIndex
        else { return }
        heldTypingAttributes = AttributedTextSelection.attributes(ofCharacterAt: index, in: text)
    }

    /// The value with its characters made `newString`, as one replacement
    /// between their common start and end, the new characters taking the
    /// typing attributes there.
    private func replacingCharacters(with newString: String) -> AttributedString {
        let old = string
        var (oldStart, newStart) = (old.startIndex, newString.startIndex)
        var head = 0
        while oldStart < old.endIndex, newStart < newString.endIndex, old[oldStart] == newString[newStart] {
            old.formIndex(after: &oldStart)
            newString.formIndex(after: &newStart)
            head += 1
        }
        var (oldEnd, newEnd) = (old.endIndex, newString.endIndex)
        var tail = 0
        while oldEnd > oldStart, newEnd > newStart {
            let (oldLast, newLast) = (old.index(before: oldEnd), newString.index(before: newEnd))
            guard old[oldLast] == newString[newLast] else { break }
            (oldEnd, newEnd) = (oldLast, newLast)
            tail += 1
        }
        var text = value
        let lower = text.characters.index(text.startIndex, offsetBy: head)
        let upper = text.characters.index(text.endIndex, offsetBy: -tail)
        text.replaceSubrange(
            lower..<upper, with: insertion(String(newString[newStart..<newEnd]), replacing: lower..<upper, in: text))
        return text
    }

    // MARK: - Reading values

    /// `text`'s characters as a `String`.
    ///
    /// Through a slice of the character view, which Foundation copies a chunk
    /// of its storage at a time: 0.45 ms for 2.4 MB, where `String(text.characters)`
    /// reads it a character at a time, 312 ms (macOS 15.8.3, -O).
    static func characters(of text: AttributedString) -> String {
        String(text.characters[...])
    }

    /// Whether `a` and `b` are the one value in the one storage.
    ///
    /// Not `==`: a bit comparison of the one reference an `AttributedString`
    /// holds to its storage, where it holds nothing else. Equal bits are the
    /// same storage, so the same value; unequal bits say nothing, and the
    /// caller takes the value as a new one, which is right for an equal one
    /// too. `==` answers two values in the same storage as fast, but two equal
    /// values in different storage a character at a time (B-ATTRED-4). Where
    /// Foundation lays the type out otherwise, `==` it is.
    static func isIdentical(_ a: AttributedString, _ b: AttributedString) -> Bool {
        guard MemoryLayout<AttributedString>.size == MemoryLayout<UnsafeRawPointer>.size else { return a == b }
        // The address of the value's storage, never of a function: no
        // deduplication can make two storages share one.
        // swiftlint:disable:next function_address_identity
        return unsafe unsafeBitCast(a, to: UnsafeRawPointer.self) == unsafeBitCast(b, to: UnsafeRawPointer.self)
    }

    /// The character offset of `position` in `lines`, joined by one-character
    /// line breaks.
    private static func offset(of position: TextEditorPosition, in lines: [[Character]]) -> Int {
        lines[..<position.line].reduce(position.column) { $0 + $1.count + 1 }
    }
}
