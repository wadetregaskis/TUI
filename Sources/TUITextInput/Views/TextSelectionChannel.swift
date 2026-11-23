//  🖥️ TUI — A Terminal UI framework for Swift
//  TextSelectionChannel.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - The channel a field reads and writes

/// Character offsets in a text, and the indices they are at: what a selection
/// channel converts the app's `TextSelection` by.
protocol TextCharacterOffsets {
    /// `index` as a character offset into `text`, clamped to it: an index from
    /// a different string — one the app kept across an edit — is clamped
    /// rather than trusted.
    func offset(of index: String.Index, in text: String) -> Int
    /// The index of the character `offset` characters into `text`, or its end.
    func index(atOffset offset: Int, in text: String) -> String.Index
}

/// Character offsets found by walking the text's characters from its start:
/// a field's, whose text is a line. An editor's layout knows where its lines
/// start, and walks only the line an offset is on (``EditorLayout``): a walk of
/// a 3 MB text, on every frame and key of an editor with a selection binding,
/// was most of what a key cost there.
struct WalkedCharacterOffsets: TextCharacterOffsets {
    func offset(of index: String.Index, in text: String) -> Int {
        guard index >= text.startIndex else { return 0 }
        guard index <= text.endIndex else { return text.count }
        return text.distance(from: text.startIndex, to: text.index(index, offsetBy: 0))
    }

    func index(atOffset offset: Int, in text: String) -> String.Index {
        text.index(text.startIndex, offsetBy: max(0, offset), limitedBy: text.endIndex) ?? text.endIndex
    }
}

/// A selection binding as a field uses it: offsets in the text, read and
/// written. It holds no `TextSelection` itself, so a field that has one stays
/// a type every deployment target can store; the closures are made where the
/// binding is, behind the same availability.
struct _TextSelectionChannel {
    /// The selection the app holds, as character offsets into `text` found by
    /// `offsets` — `nil` when it holds none. The text is passed, not read
    /// from the binding, so the selection can be read in the text before an
    /// edit of the app's as well as the one after (``TextEditorHandler/followAppEdit()``).
    let read: (_ offsets: any TextCharacterOffsets, _ text: String) -> Range<Int>?

    /// Records a selection, as character offsets, in `text`, with `affinity`,
    /// its indices found by `offsets`.
    let write: (Range<Int>, String, TextSelectionAffinity, _ offsets: any TextCharacterOffsets) -> Void

    /// A channel of the given closures — the find bar's, which steers an
    /// editor's selection to a match without a `TextSelection` of its own.
    init(
        read: @escaping (any TextCharacterOffsets, String) -> Range<Int>?,
        write: @escaping (Range<Int>, String, TextSelectionAffinity, any TextCharacterOffsets) -> Void
    ) {
        self.read = read
        self.write = write
    }

    init(_ binding: Binding<TextSelection?>, text: Binding<String>) {
        self.read = { locator, string in
            guard let range = binding.wrappedValue?.firstRange else { return nil }
            let lower = locator.offset(of: range.lowerBound, in: string)
            return lower..<max(lower, locator.offset(of: range.upperBound, in: string))
        }
        self.write = { offsets, string, affinity, locator in
            let lower = locator.index(atOffset: offsets.lowerBound, in: string)
            let upper = locator.index(atOffset: offsets.upperBound, in: string)
            var selection = TextSelection(range: lower..<upper)
            selection.affinity = affinity
            if binding.wrappedValue != selection { binding.wrappedValue = selection }
        }
    }
}
