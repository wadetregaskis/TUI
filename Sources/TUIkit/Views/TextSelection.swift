//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextSelection.swift
//
//  SwiftUI's text selection: where the caret is, or what is selected, in a
//  text field's or a text editor's text.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The direction a caret leans at a position two lines share — mirrors
/// SwiftUI's `TextSelectionAffinity`.
///
/// Where a wrapped line ends, one position is both the end of one row and the
/// start of the next. Upstream puts the caret at the end of the earlier row;
/// downstream at the start of the later one. A vertical ``TextField`` draws its
/// caret there by the affinity, and `.automatic` as downstream, which is where
/// the macOS text system draws an insertion point an arrow key moved there
/// (macOS leans one placed by typing or a click upstream instead, per caret,
/// which TUIkit does not track). Up and Down, and a click past a wrapped row's
/// end, keep to the row the affinity picks: under `.upstream` the start of a
/// wrapped row is the end of the row before it, so a caret moved or clicked
/// onto that row lands after its first character. A selection's ends are not
/// carets, so a drag or a Shift-click still starts or ends one before that
/// character, taking it in. A wrapping ``TextEditor``
/// draws its caret the same way; one that scrolls sideways
/// (``View/textEditorWrapsLines(_:)``) has no shared positions, and only
/// reports the affinity.
public enum TextSelectionAffinity: Sendable, Hashable {
    /// The affinity the text view chooses.
    case automatic

    /// The caret leans toward the earlier text.
    case upstream

    /// The caret leans toward the later text.
    case downstream
}

/// Represents a selection of text — mirrors SwiftUI's `TextSelection`.
///
/// A selection is an insertion point (the caret), a range of selected text, or
/// several ranges. TUIkit's fields select one range, so a selection they report
/// is never more; a multiple selection written by the app selects its first
/// range.
///
/// ```swift
/// @State private var selection: TextSelection?
///
/// TextEditor(text: $text, selection: $selection)
/// ```
@available(macOS 15, *)
public struct TextSelection: Sendable, Hashable {
    /// The selected ranges of a text.
    public enum Indices: Sendable, Hashable {
        /// One range, empty for an insertion point.
        case selection(Range<String.Index>)

        /// Several ranges.
        case multiSelection(RangeSet<String.Index>)
    }

    /// The selected ranges.
    public var indices: Indices

    /// The direction the caret leans, from the field's
    /// ``EnvironmentValues/textSelectionAffinity``.
    public internal(set) var affinity: TextSelectionAffinity = .automatic

    /// Creates a selection that is an insertion point.
    ///
    /// - Parameter insertionPoint: Where the caret is.
    public init(insertionPoint: String.Index) {
        self.indices = .selection(insertionPoint..<insertionPoint)
    }

    /// Creates a selection of one range.
    ///
    /// - Parameter range: The selected range.
    public init(range: Range<String.Index>) {
        self.indices = .selection(range)
    }

    /// Creates a selection of several ranges.
    ///
    /// - Parameter ranges: The selected ranges.
    public init(ranges: RangeSet<String.Index>) {
        self.indices = .multiSelection(ranges)
    }

    /// Whether the selection is an insertion point: nothing selected.
    public var isInsertion: Bool {
        switch indices {
        case .selection(let range): range.isEmpty
        case .multiSelection(let ranges): ranges.isEmpty || ranges.ranges.allSatisfy(\.isEmpty)
        }
    }

    /// The one range a TUIkit field selects: the range, or a multiple
    /// selection's first.
    var firstRange: Range<String.Index>? {
        switch indices {
        case .selection(let range): range
        case .multiSelection(let ranges): ranges.ranges.first
        }
    }
}

private struct TextSelectionAffinityKey: EnvironmentKey {
    static let defaultValue = TextSelectionAffinity.automatic
}

extension EnvironmentValues {
    /// The affinity text fields and editors report their selections with — see
    /// ``View/textSelectionAffinity(_:)``.
    public var textSelectionAffinity: TextSelectionAffinity {
        get { self[TextSelectionAffinityKey.self] }
        set { self[TextSelectionAffinityKey.self] = newValue }
    }
}

extension View {
    /// Sets the direction a selection leans, for text fields and editors in
    /// this view — mirrors SwiftUI's `textSelectionAffinity(_:)`.
    ///
    /// The affinity is reported with each ``TextSelection`` a field writes, and
    /// a vertical ``TextField`` and a wrapping ``TextEditor`` draw their caret
    /// by it where their text wrapped — see ``TextSelectionAffinity``. A field
    /// on one line, and an editor that scrolls sideways
    /// (``View/textEditorWrapsLines(_:)``), share no position between rows, so
    /// for them it changes nothing drawn.
    ///
    /// - Parameter affinity: The affinity.
    /// - Returns: A view whose text fields report selections with it.
    public func textSelectionAffinity(_ affinity: TextSelectionAffinity) -> some View {
        environment(\.textSelectionAffinity, affinity)
    }
}

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
