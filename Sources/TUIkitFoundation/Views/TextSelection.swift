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
