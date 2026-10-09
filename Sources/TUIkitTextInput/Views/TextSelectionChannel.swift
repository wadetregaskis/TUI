//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextSelectionChannel.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - The channel a field reads and writes

/// A selection binding as a field uses it: offsets in the text, read and
/// written. It holds no `TextSelection` itself, so a field that has one stays
/// a type every deployment target can store; the closures are made where the
/// binding is, behind the same availability.
struct _TextSelectionChannel {
    /// The selection the app holds, as character offsets — `nil` when it holds
    /// none.
    let read: () -> Range<Int>?

    /// Records a selection, as character offsets, in `text`, with `affinity`.
    let write: (Range<Int>, String, TextSelectionAffinity) -> Void

    /// A channel of the given closures — the find bar's, which steers an
    /// editor's selection to a match without a `TextSelection` of its own.
    init(read: @escaping () -> Range<Int>?, write: @escaping (Range<Int>, String, TextSelectionAffinity) -> Void) {
        self.read = read
        self.write = write
    }

    @available(macOS 15, *)
    init(_ binding: Binding<TextSelection?>, text: Binding<String>) {
        self.read = {
            guard let range = binding.wrappedValue?.firstRange else { return nil }
            return Self.offsets(of: range, in: text.wrappedValue)
        }
        self.write = { offsets, string, affinity in
            let lower = string.index(string.startIndex, offsetBy: offsets.lowerBound, limitedBy: string.endIndex)
                ?? string.endIndex
            let upper = string.index(lower, offsetBy: offsets.count, limitedBy: string.endIndex) ?? string.endIndex
            var selection = TextSelection(range: lower..<upper)
            selection.affinity = affinity
            if binding.wrappedValue != selection { binding.wrappedValue = selection }
        }
    }

    /// `range` as character offsets into `text`, clamped to it. An index from a
    /// different string — one the app kept across an edit — is clamped rather
    /// than trusted.
    private static func offsets(of range: Range<String.Index>, in text: String) -> Range<Int> {
        func offset(_ index: String.Index) -> Int {
            guard index >= text.startIndex else { return 0 }
            guard index <= text.endIndex else { return text.count }
            return text.distance(from: text.startIndex, to: text.index(index, offsetBy: 0))
        }
        let lower = offset(range.lowerBound)
        return lower..<max(lower, offset(range.upperBound))
    }
}
